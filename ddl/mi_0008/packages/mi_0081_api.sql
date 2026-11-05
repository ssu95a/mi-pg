--
-- Пакет      : mi_0081_api
-- Назначение : Приём запросов ФНС (ВС 81), регистрация позиций и подтверждение
-- Версия     : 0.2.0
--
-- Контракты:
--   1. Один входящий payload -> один mi_req (81), kind хранится в позициях.
--   2. Успешное сопоставление -> source_itm_id, result_code=NULL.
--   3. Не найдена позиция -> source_itm_id=NULL, result_code='NOT_FOUND'.
--   4. Повтор original_request_uuid ИЛИ requestId -> отказ без повторной обработки.
--   5. Отказ имеет собственные mi_req + диагностическую позицию mi_0081
--      для привязки ответа к itm_id (не создаёт Doc/Sum).
--   6. После READY один mi_req (81) переводится в DONE атомарно.
--   7. Отправка response выполняется после завершения автономной транзакции.
--   8. Формирование исходящих запросов ВС 8 здесь не выполняется.
--
CREATE OR REPLACE PACKAGE mi_0081_api

CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
   #export off
DECLARE

   c_Version     CONSTANT varchar(20) := '1.0.1';
   c_Pkg_Name    CONSTANT varchar(20) := 'mi_0081_api';
   c_Logger      CONSTANT varchar(20) := 'mi.0081';
   c_Inf_Id      CONSTANT numeric     := 81;

   c_Kind_Doc    CONSTANT numeric := 1;
   c_Kind_Sum    CONSTANT numeric := 2;

   c_Status_New  CONSTANT numeric := 0;
   c_Status_Done CONSTANT numeric := 1;

   -- Коды category/result должны соответствовать контракту XXL.
   -- До интеграционного теста используем действующий SUCCESS/OK и
   -- предварительный ERROR/DUPLICATE_REQUEST для отрицательного ответа.
   c_Rsp_Accept_Category CONSTANT varchar(50)  := 'SUCCESS';
   c_Rsp_Accept_Code     CONSTANT varchar(100) := 'OK';
   c_Rsp_Reject_Category CONSTANT varchar(50)  := 'ERROR';
   c_Rsp_Reject_Code     CONSTANT varchar(100) := 'DUPLICATE_REQUEST';

BEGIN
   RAISE DEBUG 'Package "%" - % - initialized', c_Pkg_Name, c_Version;
END;
$init$


/* Версия пакета. */
CREATE FUNCTION get_Version()
   RETURNS varchar
AS
$function$
   #package
BEGIN
   RETURN c_Version;
END;
$function$


/*
 * Регистрирует весь входящий запрос ФНС в автономной транзакции.
 *
 * При нормальном приёме создаёт один или два заголовка mi_req и все позиции.

 * При повторном original_request_uuid или requestId создаёт только запись
 * об отказе и одну диагностическую позицию, не выполняя бизнес-обработку.
 *
 * Если такое же отклонённое сообщение уже зарегистрировано,
 * возвращает существующий READY/SENT response без новых INSERT.
 */
CREATE PROCEDURE register_Request_AT(
   
   IN  p_original_request_uuid uuid,
   IN  p_correlation_id        uuid,
   IN  p_message_uuid          uuid,

   IN  p_ctaxreq_id            varchar,
   IN  p_iyear                 numeric,
   
   IN  p_positions             jsonb,

   OUT p_req_id_81 numeric,
   OUT p_reject_req_id         numeric,
   OUT p_rsp_id                numeric,
   OUT p_is_rejected           boolean,
   OUT p_found_count           bigint,
   OUT p_not_found_count       bigint
)
AS
$procedure$
   #package
   #private
DECLARE

   

   l_position_count bigint;
   

   l_inserted       bigint;
   l_done_count     bigint;

   l_existing_req_id numeric;
   l_duplicate_reason varchar(50);

   l_anchor_req_id numeric;
   l_anchor_itm_id numeric;

   l_rsp_category varchar(50);
   l_rsp_code     varchar(100);
   l_rsp_info     varchar;
   l_rsp_payload  jsonb;

   l_ready_code int4;
   l_ready_info varchar;

BEGIN AUTONOMOUS

   p_req_id_81 := NULL;
   p_reject_req_id   := NULL;
   p_rsp_id          := NULL;
   p_is_rejected     := false;

   p_found_count     := 0;
   p_not_found_count := 0;

   SELECT count(*) INTO l_position_count
     FROM jsonb_array_elements(p_positions) AS x(elem);

   IF l_position_count = 0 THEN
      RAISE EXCEPTION 'MI_0081: empty or invalid positions';
   END IF;

   /* Два разных идентификатора блокируем в постоянном порядке. */
   PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('mi_0081_api.original_request'),
      pg_catalog.hashtext(p_original_request_uuid::text)
   );

   PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('mi_0081_api.tax_request'),
      pg_catalog.hashtext(p_ctaxreq_id)
   );

   /* Повтор любого из двух бизнес-идентификаторов запрещён. */
   SELECT r.req_id,
          CASE
             WHEN r.original_request_uuid = p_original_request_uuid THEN 
                  'DUPLICATE_ORIGINAL_REQUEST'
             ELSE 
                  'DUPLICATE_TAX_REQUEST'
          END
     INTO 
          l_existing_req_id, l_duplicate_reason
     FROM xxi.mi_req AS r
    WHERE r.inf_id = c_Inf_Id
      AND (r.original_request_uuid = p_original_request_uuid OR r.ctaxreq_id = p_ctaxreq_id)
    ORDER BY (r.i3 = 0) DESC NULLS LAST, r.created_at, r.req_id
    LIMIT 1;

   IF l_existing_req_id IS NOT NULL THEN
    
      p_is_rejected := true;

      /*
       * Повтор ранее отклонённого транспортного сообщения:
       * не создаём новые записи об отказе, возвращаем сохранённый response.
       */
      SELECT r.req_id, s.rsp_id
        INTO p_reject_req_id, p_rsp_id
        FROM xxi.mi_req AS r
        JOIN xxi.mi_rsp AS s
          ON s.req_id = r.req_id
        JOIN xxi.mi_0081 AS i
          ON i.req_id = r.req_id
         AND i.itm_id = s.itm_id
       WHERE r.inf_id = c_Inf_Id
         AND r.i3 IS NULL
         AND r.result_code = c_Rsp_Reject_Code
         AND r.status_cd   = c_Status_Done

         AND r.original_request_uuid = p_original_request_uuid
         AND r.ctaxreq_id            = p_ctaxreq_id

         AND r.message_uuid   = p_message_uuid
         AND r.correlation_id = p_correlation_id

         AND s.result_code  = c_Rsp_Reject_Code
         AND s.status_cd IN (1, 2)
       ORDER BY r.req_id
       LIMIT 1;

      IF p_rsp_id IS NOT NULL THEN
         RETURN;
      END IF;

      /*
       * Служебный заголовок отказа: i3=NULL, поэтому не занимает
       * уникальный ключ принятого запроса (i3=0).
       * parent_req_id указывает на ранее зарегистрированный запрос.
       */
      p_reject_req_id := MI_Request_Api.create_Request(
         p_inf_id                => c_Inf_Id,
         p_correlation_id        => p_correlation_id,
         p_original_request_uuid => p_original_request_uuid,
         p_ctaxreq_id            => p_ctaxreq_id,
         p_message_uuid          => p_message_uuid,
         p_status_cd             => c_Status_New,
         p_i1                    => p_iyear,
         p_i2                    => 2,
         p_i3                    => NULL::numeric,
         p_parent_req_id         => l_existing_req_id
      );

      IF p_reject_req_id IS NULL THEN
         RAISE EXCEPTION 'MI_0081: cannot create rejected request';
      END IF;

      /*
       * MI_Response_Api требует настоящий itm_id. Одна диагностическая
       * позиция представляет отказ всего payload, без повторной
       * регистрации всех позиций входящего запроса.
       */
      INSERT INTO xxi.mi_0081
      (
         req_id, source_itm_id, iyear, inum, icorr, kind, result_code
      )
      SELECT p_reject_req_id,
             NULL::numeric,
             p_iyear,
             (x.elem ->> 'number')::numeric,
             (x.elem ->> 'correctionNumber')::numeric,
             (x.elem ->> 'kind')::numeric,
             c_Rsp_Reject_Code
        FROM jsonb_array_elements(p_positions) WITH ORDINALITY AS x(elem, ord)
       ORDER BY x.ord
       LIMIT 1
             RETURNING itm_id INTO l_anchor_itm_id;

      l_anchor_req_id := p_reject_req_id;
      
      l_rsp_category := c_Rsp_Reject_Category;
      l_rsp_code     := c_Rsp_Reject_Code;
      l_rsp_info     := CASE l_duplicate_reason
                           WHEN 'DUPLICATE_ORIGINAL_REQUEST'
                              THEN 'Повторный запрос: original_request_uuid уже зарегистрирован'
                           ELSE 'Повторный запрос: requestId уже зарегистрирован'
                        END;
      l_rsp_payload  := jsonb_build_object(
         'reason', l_duplicate_reason,
         'requestId', p_ctaxreq_id
      );

   ELSE

      /* Один заголовок 81 для всего payload. */
      p_req_id_81 := MI_Request_Api.create_Request(
         p_inf_id                => c_Inf_Id,
         p_correlation_id        => p_correlation_id,
         p_original_request_uuid => p_original_request_uuid,
         p_ctaxreq_id            => p_ctaxreq_id,
         p_message_uuid          => p_message_uuid,
         p_status_cd             => c_Status_New,
         p_i1                    => p_iyear,
         p_i2                    => 2,
         p_i3                    => 0::numeric
      );
      IF p_req_id_81 IS NULL THEN
         RAISE EXCEPTION 'MI_0081: cannot create incoming request';
      END IF;

      /*
       * Ненайденные позиции сохраняем с source_itm_id=NULL/NOT_FOUND.
       * Невозможность однозначно найти исходную строку является ошибкой.
       */
      WITH positions AS MATERIALIZED
      (
         SELECT (x.elem ->> 'number')::numeric AS inum,
                (x.elem ->> 'correctionNumber')::numeric AS icorr,
                (x.elem ->> 'kind')::numeric AS rkind
           FROM jsonb_array_elements(p_positions) AS x(elem)
      ),
      resolved AS MATERIALIZED
      (
         SELECT p.inum, p.icorr, p.rkind,
                count(m.itm_id) AS match_count,
                min(m.itm_id) AS source_itm_id
           FROM positions AS p
           LEFT JOIN xxi.mi_0008 AS m
             ON m.iyear = p_iyear
            AND m.inum  = p.inum
            AND m.icorr = p.icorr
            AND EXISTS
                (
                   SELECT 1 FROM xxi.mi_req AS r WHERE r.req_id = m.req_id AND r.inf_id = 8 AND r.status_cd IN (1, 2, 3)
                )
          GROUP BY p.inum, p.icorr, p.rkind
      )
      INSERT INTO xxi.mi_0081
      (
         req_id, source_itm_id, iyear, inum, icorr, kind, result_code
      )
      SELECT p_req_id_81,
             s.source_itm_id,
             p_iyear, s.inum, s.icorr, s.rkind,
             CASE WHEN s.match_count = 0 THEN 'NOT_FOUND' ELSE NULL END
        FROM 
             resolved AS s
       WHERE 
             NOT EXISTS ( SELECT 1 FROM resolved WHERE match_count > 1 );


      GET DIAGNOSTICS l_inserted = ROW_COUNT;

      IF l_inserted <> l_position_count THEN
         RAISE EXCEPTION 'MI_0081: ambiguous history or item cardinality mismatch: expected=%, written=%', l_position_count, l_inserted;
      END IF;

      SELECT count(*) FILTER (WHERE i.source_itm_id IS NOT NULL),
             count(*) FILTER (WHERE i.source_itm_id IS NULL)
        INTO p_found_count, p_not_found_count
        FROM xxi.mi_0081 AS i
       WHERE i.req_id = p_req_id_81;

      l_anchor_req_id := p_req_id_81;

      SELECT min(i.itm_id)
        INTO l_anchor_itm_id
        FROM xxi.mi_0081 AS i
       WHERE i.req_id = l_anchor_req_id;

      
      l_rsp_category := c_Rsp_Accept_Category;
      l_rsp_code     := c_Rsp_Accept_Code;
      l_rsp_info     := format(
         'Registered %s position(s); NOT_FOUND=%s',
         l_position_count, p_not_found_count
      );
      l_rsp_payload := jsonb_build_object('confirmed_at', clock_timestamp());

   END IF;

   IF l_anchor_req_id IS NULL OR l_anchor_itm_id IS NULL THEN
      RAISE EXCEPTION 'MI_0081: no valid response anchor';
   END IF;

   /* Один синхронный response на весь входящий payload. */
   p_rsp_id := MI_Response_Api.create_Response(
      p_req_id       => l_anchor_req_id,
      p_itm_id       => l_anchor_itm_id,
      p_category_cd  => l_rsp_category,
      p_result_code  => l_rsp_code,
      p_result_info  => l_rsp_info,
      p_payload      => l_rsp_payload
   );

   IF p_rsp_id IS NULL THEN
      RAISE EXCEPTION 'MI_0081: create_Response returned NULL';
   END IF;

   CALL MI_Response_Api.to_Ready(
      p_rsp_id   => p_rsp_id,
      p_res_code => l_ready_code,
      p_res_info => l_ready_info
   );

   IF l_ready_code IS DISTINCT FROM 0 THEN
      RAISE EXCEPTION 'MI_0081: cannot set response READY: %', coalesce(l_ready_info, '<empty>');
   END IF;

   /*
    * Успешный приём (в том числе зарегистрированный отказ) завершён.
    * Единственный mi_req (81) переходит в DONE атомарно с mi_rsp.READY.
    */
   UPDATE xxi.mi_req AS r
      SET status_cd   = c_Status_Done,
          result_code = CASE WHEN p_is_rejected THEN c_Rsp_Reject_Code ELSE NULL END,
          result_info = CASE WHEN p_is_rejected THEN l_duplicate_reason ELSE NULL END,
          result_time = clock_timestamp()
    WHERE r.inf_id = c_Inf_Id AND r.status_cd = c_Status_New
      AND r.req_id = coalesce(p_req_id_81, p_reject_req_id);

   GET DIAGNOSTICS l_done_count = ROW_COUNT;

   IF l_done_count <> 1 THEN
      RAISE EXCEPTION 'MI_0081: DONE cardinality mismatch: expected=1, updated=%', l_done_count;
   END IF;

END;
$procedure$


/*
 * Обрабатывает входящий payload ФНС.
 * Регистрация и READY/DONE завершаются до отправки синхронного ответа.
 * Не выполняет расчёты ВС 8.
 *
 * p_ret_code=0 означает успешную обработку сообщения, включая
 * зарегистрированный бизнес-отказ (см. p_ret_info и mi_rsp.result_code).
 */
CREATE PROCEDURE apply_Request(
   IN  p_message_uuid          uuid,
   IN  p_original_request_uuid uuid,
   IN  p_correlation_id        uuid,
   IN  p_request_time          timestamptz,
   IN  p_payload_text          text,
   OUT p_ret_code              int4,
   OUT p_ret_info              varchar
)
AS
$procedure$
   #package
DECLARE
   l_payload       jsonb;
   l_positions     jsonb;
   l_ctaxreq_id    varchar;
   l_iyear         numeric;

   l_invalid_count bigint;
   l_dupe_count    bigint;

   l_req_id_81 numeric;
   l_reject_req_id numeric;
   l_rsp_id        numeric;
   l_is_rejected   boolean;
   l_found_count   bigint;
   l_missing_count bigint;

   l_send_result MI_resultCtx.exec_Result;
BEGIN
   p_ret_code := -1;
   p_ret_info := NULL;

   IF num_nulls(p_message_uuid, p_original_request_uuid, p_correlation_id, p_request_time, p_payload_text) > 0
   OR 
      btrim(p_payload_text) = '' THEN
      
      p_ret_info := 'INVALID_REQUEST_PARAMETERS';
      
      RETURN;

   END IF;

   /* Ошибка чтения JSON превращается в ошибку формата. */
   BEGIN
      l_payload := p_payload_text::jsonb;
   EXCEPTION WHEN OTHERS THEN
      p_ret_info := 'INVALID_JSON: ' || SQLERRM;
      RETURN;
   END;

   IF jsonb_typeof(l_payload) IS DISTINCT FROM 'object' THEN
      p_ret_info := 'INVALID_PAYLOAD_OBJECT';
      RETURN;
   END IF;

   l_ctaxreq_id := NULLIF(btrim(l_payload ->> 'requestId'), '');
   IF l_ctaxreq_id IS NULL OR length(l_ctaxreq_id) > 50 THEN
      p_ret_info := 'INVALID_REQUEST_ID';
      RETURN;
   END IF;

   IF coalesce(l_payload ->> 'period', '') !~ '^[0-9]{4}$' THEN
      p_ret_info := 'INVALID_PERIOD';
      RETURN;
   END IF;

   l_iyear := (l_payload ->> 'period')::numeric;
   IF l_iyear NOT BETWEEN 1 AND 9999 THEN
      p_ret_info := 'INVALID_PERIOD';
      RETURN;
   END IF;

   l_positions := l_payload -> 'clarifications';
   IF jsonb_typeof(l_positions) IS DISTINCT FROM 'array' THEN
      p_ret_info := 'INVALID_CLARIFICATIONS';
      RETURN;
   END IF;

   IF jsonb_array_length(l_positions) = 0 THEN
      p_ret_info := 'EMPTY_CLARIFICATIONS';
      RETURN;
   END IF;

   /* Делаем все проверки формата до числовых приведений. */
   SELECT count(*) FILTER
          (
             WHERE jsonb_typeof(x.elem) IS DISTINCT FROM 'object'
                OR coalesce(x.elem ->> 'number', '') !~ '^[0-9]{1,12}$'
                OR coalesce(x.elem ->> 'correctionNumber', '') !~ '^[0-9]{1,2}$'
                OR coalesce(x.elem ->> 'kind', '') NOT IN ('1', '2')
          )
     INTO l_invalid_count
     FROM jsonb_array_elements(l_positions) AS x(elem);

   IF l_invalid_count > 0 THEN
      p_ret_info := format('INVALID_CLARIFICATIONS: %s invalid position(s)', l_invalid_count);
      RETURN;
   END IF;

   SELECT count(*) - count(DISTINCT ROW(
             (x.elem ->> 'number')::numeric,
             (x.elem ->> 'correctionNumber')::numeric
          ))
     INTO l_dupe_count
     FROM jsonb_array_elements(l_positions) AS x(elem);
     
   IF l_dupe_count > 0 THEN
      p_ret_info := 'DUPLICATE_CLARIFICATIONS';
      RETURN;
   END IF;

   /* Атомарная регистрация (включая DONE и сохранение READY response). */
   CALL mi_0081_api.register_Request_AT(
      p_original_request_uuid => p_original_request_uuid,
      p_correlation_id        => p_correlation_id,
      p_message_uuid          => p_message_uuid,
      p_ctaxreq_id            => l_ctaxreq_id,
      p_iyear                 => l_iyear,
      p_positions             => l_positions,
      p_req_id_81 => l_req_id_81,
      p_reject_req_id         => l_reject_req_id,
      p_rsp_id                => l_rsp_id,
      p_is_rejected           => l_is_rejected,
      p_found_count           => l_found_count,
      p_not_found_count       => l_missing_count
   );

   /* Отправка только после фиксации автономной регистрации. */
   CALL mi_mbus.send_response(
      p_rsp_id => l_rsp_id,
      p_result => l_send_result
   );

   IF l_send_result.is_success IS NOT TRUE THEN
      p_ret_info := format( 'RESPONSE_READY_NOT_SENT: rsp_id=%s; %s', l_rsp_id, coalesce(l_send_result.result_info, 'transport error') );
      RETURN;
   END IF;

   p_ret_code := 0;

   IF l_is_rejected THEN
      p_ret_info := format( 'REJECTED_DUPLICATE: reject_req_id=%s, rsp_id=%s', l_reject_req_id, l_rsp_id );
   ELSE
      p_ret_info := format(
         'ACCEPTED: req_id_81=%s, found=%s, not_found=%s, rsp_id=%s',
          l_req_id_81,
         l_found_count, l_missing_count, l_rsp_id
      );
   END IF;

EXCEPTION WHEN OTHERS THEN
   /* Автономная регистрация откатывается целиком при ошибке внутри неё. */
   p_ret_code := -1;
   p_ret_info := SQLERRM;

   CALL MI_logger.error(
      p_logger_name  => c_Logger,
      p_message_text => 'Ошибка обработки входящего запроса ВС 81',
      p_details_text => SQLERRM,
      p_inf_id       => c_Inf_Id,
      p_action_cd    => 'apply_request',
      p_object_name  => c_Pkg_Name
   );
END;
$procedure$


/*
 * Подготавливает исходящий запрос ВС 8 для одного kind принятого 81. Не отправляет запрос: вызывающий код фиксирует
 * транзакцию, затем отдельно вызывает mi_mbus.send_request().
 *
 * Повторный вызов возвращает ранее созданный req_id ВС 8.
 * Все действия (marker, отчёт, parent link) выполняются в транзакции
 * вызывающей стороны.
 */
CREATE PROCEDURE prepare_Correction(
   IN  p_req_id_81    numeric,
   IN  p_kind numeric,
   OUT p_req_id_8     numeric,
   OUT p_ires_code    int4,
   OUT p_cres_info    text
)
AS
$procedure$
   #package
DECLARE
   c_Inf_Id_8  CONSTANT numeric := 8;
   c_Reason_Fns CONSTANT numeric := 2;

   r_source     record;
   l_marker_id  bigint;
   l_count      bigint;
   l_existing   bigint;
   l_lsr_id     numeric;
   l_updated    bigint;
BEGIN
   p_req_id_8  := NULL;
   p_ires_code := -1;
   p_cres_info := NULL;

   IF p_req_id_81 IS NULL THEN
      p_cres_info := 'REQUEST_ID_REQUIRED';
      RETURN;
   END IF;

   IF p_kind IS NULL OR p_kind NOT IN (c_Kind_Doc, c_Kind_Sum) THEN
      p_cres_info := 'INVALID_KIND';
      RETURN;
   END IF;

   /*
    * Блокируем исходный заголовок: два конкурентных вызова не должны
    * создавать две коррекции для одного входящего запроса.
    */
   SELECT r.req_id, r.i1 AS iyear, r.i3,
          r.ctaxreq_id, r.status_cd, r.result_code
     INTO r_source
     FROM xxi.mi_req AS r
    WHERE r.req_id = p_req_id_81
      AND r.inf_id = c_Inf_Id
    FOR UPDATE;

   IF NOT FOUND THEN
      p_cres_info := 'SOURCE_81_NOT_FOUND';
      RETURN;
   END IF;

   IF r_source.status_cd <> c_Status_Done
      OR r_source.i3 IS DISTINCT FROM 0
      OR r_source.result_code IS NOT NULL
      OR NULLIF(btrim(r_source.ctaxreq_id), '') IS NULL
   THEN
      p_cres_info := 'SOURCE_81_NOT_ACCEPTED';
      RETURN;
   END IF;

   /*
    * У уже созданной коррекции отправка могла не состояться.
    * Не пересоздаём её; возвращаем готовый req_id для отдельной отправки.
    */
   SELECT count(*), min(r.req_id)
     INTO l_count, l_existing
     FROM xxi.mi_req AS r
    WHERE r.inf_id = c_Inf_Id_8
      AND r.parent_req_id = p_req_id_81
       AND r.i3 = p_kind;

   IF l_count > 1 THEN
      RAISE EXCEPTION 'MI_0081: multiple outgoing 8 requests for source req_id=%', p_req_id_81;
   ELSIF l_count = 1 THEN
      p_req_id_8  := l_existing;
      p_ires_code := 0;
      p_cres_info := 'ALREADY_PREPARED';
      RETURN;
   END IF;

   /*
    * Сопоставленные позиции ВС 81 определяют scope коррекции.
    * В режиме correction build_Scope использует mrk_id2.idarow.
    */
   SELECT count(DISTINCT m.icusnum)
     INTO l_count
     FROM xxi.mi_0081 AS i
     JOIN xxi.mi_0008 AS m
       ON m.itm_id = i.source_itm_id
    WHERE i.req_id = p_req_id_81
      AND i.result_code IS NULL
       AND i.kind = p_kind
       AND m.icusnum IS NOT NULL;

   IF l_count = 0 THEN
      p_ires_code := 1;
      p_cres_info := 'NO_MATCHED_CLIENTS';
      RETURN;
   END IF;

   l_marker_id := util.mrk_getnextmarkerid();

   INSERT INTO xxi.mrk_id2 (idrow, idarow, idmarker)
   SELECT DISTINCT m.icusnum, m.icusnum, l_marker_id
     FROM xxi.mi_0081 AS i
     JOIN xxi.mi_0008 AS m
       ON m.itm_id = i.source_itm_id
    WHERE i.req_id = p_req_id_81
      AND i.result_code IS NULL
       AND i.kind = p_kind
       AND m.icusnum IS NOT NULL;

   GET DIAGNOSTICS l_updated = ROW_COUNT;

   IF l_updated <> l_count THEN
      RAISE EXCEPTION 'MI_0081: marker cardinality mismatch: expected=%, written=%',
         l_count, l_updated;
   END IF;

   CALL mi_0008_api.prepare_Report(
      p_iyear      => r_source.iyear,
      p_itype      => 2::numeric,
      p_irsn_corr  => c_Reason_Fns,
      p_ireq_kind  => p_kind,
      p_cus_marker => l_marker_id,
      p_ctaxreq_id => r_source.ctaxreq_id,
      p_lsr_id     => l_lsr_id,
      p_req_id     => p_req_id_8,
      p_ires_code  => p_ires_code,
      p_cres_info  => p_cres_info
   );

   /*
    * Marker используется только во время формирования.
    * При ошибке транзакции и INSERT, и DELETE откатятся.
    */
   CALL util.mrk_deleteall(l_marker_id, 2);

   IF p_ires_code = 0 THEN
      IF p_req_id_8 IS NULL THEN
         RAISE EXCEPTION 'MI_0081: prepare_Report succeeded without req_id';
      END IF;

      UPDATE xxi.mi_req AS r
         SET parent_req_id = p_req_id_81
       WHERE r.req_id = p_req_id_8
         AND r.inf_id = c_Inf_Id_8
         AND r.parent_req_id IS NULL;

      GET DIAGNOSTICS l_updated = ROW_COUNT;
      IF l_updated <> 1 THEN
         RAISE EXCEPTION 'MI_0081: failed to link outgoing req_id=% to source req_id=%',
            p_req_id_8, p_req_id_81;
      END IF;
   END IF;
END;
$procedure$


/* Конец пакета. */
;

COMMENT ON SCHEMA mi_0081_api IS
   'MI-edo. Приём запросов ФНС, ВС 81. Версия 0.3.0 {$Id$}'
;

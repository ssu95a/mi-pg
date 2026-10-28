--
-- Пакет      : mi_0081_api
-- Назначение : Приём запросов ФНС (ВС 81), регистрация позиций и подтверждение
-- Версия     : 0.1.0
--
-- Требует:
--   xxi.mi_req, xxi.mi_req_id, xxi.mi_0081, xxi.mi_0008, xxi.mi_rsp;
--   MI_Request_Api, MI_Response_Api, MI_resultCtx, mi_mbus;
--
CREATE OR REPLACE PACKAGE mi_0081_api

CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
   #export off
DECLARE
   cVersion  CONSTANT varchar(20) := '0.1.0';
   cPkg_Name CONSTANT varchar(20) := 'mi_0081_api';
   cInf_Id   CONSTANT numeric     := 81;
BEGIN
   RAISE DEBUG 'Package "%" - % - initialized', cPkg_Name, cVersion;
END;
$init$


/* Версия пакета. */
CREATE FUNCTION get_Version()
   RETURNS varchar
AS
$function$
   #package
BEGIN
   RETURN cVersion;
END;
$function$


/*
 * Атомарно регистрирует один входящий payload (до двух mi_req),
 * все его позиции mi_0081 и один синхронный response в READY.
 *
 * Автономная транзакция обеспечивает независимость приёма от будущего
 * расчёта финансовых сумм/документов ВС 8.
 *
 * На повторную доставку возвращает исходные req_id/rsp_id.
 */
CREATE PROCEDURE register_Request_AT(
   
   IN  p_original_request_uuid uuid,
   IN  p_correlation_id        uuid,
   IN  p_message_uuid          uuid,

   IN  p_ctaxreq_id            varchar,

   IN  p_iyear                 numeric,
   IN  p_positions             jsonb,

   OUT p_doc_req_id            numeric,
   OUT p_sum_req_id            numeric,
   OUT p_rsp_id                numeric,
   OUT p_is_repeat             boolean,
   OUT p_found_count           bigint,
   OUT p_not_found_count       bigint
)
AS
$procedure$
   #package
   #private
DECLARE

   l_has_doc        boolean;
   l_has_sum        boolean;

   l_expected_kinds integer;
   l_position_count bigint;
   l_existing_count bigint;

   l_metadata_ok    boolean;

   l_positions_diff boolean;
   l_inserted       bigint;

   l_anchor_req_id  numeric;
   l_anchor_itm_id  numeric;

   l_ready_code     int4;
   l_ready_info     varchar;

BEGIN AUTONOMOUS

   SELECT coalesce(bool_or(x.elem ->> 'kind' = '1'), false),
          coalesce(bool_or(x.elem ->> 'kind' = '2'), false),
          count(*)
     INTO 
          l_has_doc, l_has_sum, l_position_count
     FROM 
          jsonb_array_elements(p_positions) AS x(elem);

   l_expected_kinds := l_has_doc::integer + l_has_sum::integer;

   /* Один входящий UUID одновременно регистрирует только один backend. */
   PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('mi_0081_api.original_request'),
      pg_catalog.hashtext(p_original_request_uuid::text)
   );

   /* Сериализуем также конкурирующие входящие запросы с одним requestId. */
   PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('mi_0081_api.tax_request'),
      pg_catalog.hashtext(p_ctaxreq_id)
   );

   p_doc_req_id      := NULL;
   p_sum_req_id      := NULL;
   p_rsp_id          := NULL;
   p_is_repeat       := false;
   p_found_count     := 0;
   p_not_found_count := 0;

   /* Проверяем полный состав ранее зарегистрированной группы, а не LIMIT 1. */
   SELECT count(*),
          max(r.req_id) FILTER (WHERE r.i3 = 1),
          max(r.req_id) FILTER (WHERE r.i3 = 2),
          bool_and(
             r.i3 IN (1, 2)
             AND r.message_uuid IS NOT DISTINCT FROM p_message_uuid
             AND r.correlation_id IS NOT DISTINCT FROM p_correlation_id
             AND r.ctaxreq_id IS NOT DISTINCT FROM p_ctaxreq_id
             AND r.i1 IS NOT DISTINCT FROM p_iyear
             AND r.i2 IS NOT DISTINCT FROM 2::numeric
             AND r.parent_req_id IS NULL
          )
     INTO l_existing_count, p_doc_req_id, p_sum_req_id, l_metadata_ok
     FROM xxi.mi_req AS r
    WHERE r.inf_id = cInf_Id
      AND r.original_request_uuid = p_original_request_uuid;

   IF l_existing_count > 0 THEN

      IF l_existing_count <> l_expected_kinds
         OR l_metadata_ok IS NOT TRUE
         OR (p_doc_req_id IS NOT NULL) <> l_has_doc
         OR (p_sum_req_id IS NOT NULL) <> l_has_sum
      THEN
         RAISE EXCEPTION
            'MI_0081: conflicting registration of original_request_uuid=%',
            p_original_request_uuid;
      END IF;

      /* Состав сохранённых позиций должен в точности совпадать с payload. */
      WITH expected AS
      (
         SELECT (x.elem ->> 'number')::numeric AS inum,
                (x.elem ->> 'correctionNumber')::numeric AS icorr,
                (x.elem ->> 'kind')::numeric AS rkind
           FROM jsonb_array_elements(p_positions) AS x(elem)
      ),
      stored AS
      (
         SELECT i.inum, i.icorr, r.i3 AS rkind
           FROM xxi.mi_req AS r
           JOIN xxi.mi_0081 AS i ON i.req_id = r.req_id
          WHERE r.inf_id = cInf_Id
            AND r.original_request_uuid = p_original_request_uuid
      )
      SELECT EXISTS
      (
         (SELECT inum, icorr, rkind FROM expected
          EXCEPT
          SELECT inum, icorr, rkind FROM stored)
         UNION ALL
         (SELECT inum, icorr, rkind FROM stored
          EXCEPT
          SELECT inum, icorr, rkind FROM expected)
      )
        INTO l_positions_diff;

      IF l_positions_diff THEN
         RAISE EXCEPTION
            'MI_0081: payload positions differ for original_request_uuid=%',
            p_original_request_uuid;
      END IF;

      l_anchor_req_id := coalesce(p_doc_req_id, p_sum_req_id);

      SELECT min(i.itm_id)
        INTO l_anchor_itm_id
        FROM xxi.mi_0081 AS i
       WHERE i.req_id = l_anchor_req_id;

      SELECT s.rsp_id
        INTO p_rsp_id
        FROM xxi.mi_rsp AS s
       WHERE s.req_id = l_anchor_req_id
         AND s.itm_id = l_anchor_itm_id
         AND s.category_cd = 'SUCCESS'
         AND s.result_code = 'OK'
       ORDER BY s.rsp_id
       LIMIT 1;

      IF p_rsp_id IS NULL THEN
         RAISE EXCEPTION
            'MI_0081: registered request has no response: original_request_uuid=%',
            p_original_request_uuid;
      END IF;

      SELECT count(*) FILTER (WHERE i.source_itm_id IS NOT NULL),
             count(*) FILTER (WHERE i.source_itm_id IS NULL)
        INTO p_found_count, p_not_found_count
        FROM xxi.mi_0081 AS i
        JOIN xxi.mi_req AS r ON r.req_id = i.req_id
       WHERE r.inf_id = cInf_Id
         AND r.original_request_uuid = p_original_request_uuid;

      p_is_repeat := true;

      RETURN;

   END IF;

   /*
    * Дубликат business requestId под другим original_request_uuid:
    * не создаём фиктивную связь parent_req_id и не подтверждаем как новый.
    * Для него ещё предстоит закрепить отдельный бизнес-ответ.
    */
   IF EXISTS
   (
      SELECT 1
        FROM xxi.mi_req AS r
       WHERE r.inf_id = cInf_Id
         AND r.ctaxreq_id = p_ctaxreq_id
         AND r.original_request_uuid IS DISTINCT FROM p_original_request_uuid
   ) THEN
      RAISE EXCEPTION 'MI_0081: duplicate business requestId=% with different original_request_uuid', p_ctaxreq_id;
   END IF;

   IF l_has_doc THEN
      p_doc_req_id := MI_Request_Api.create_Request(
         p_inf_id                => cInf_Id,
         p_correlation_id        => p_correlation_id,
         p_original_request_uuid => p_original_request_uuid,
         p_ctaxreq_id            => p_ctaxreq_id,
         p_message_uuid          => p_message_uuid,
         p_status_cd             => 0,
         p_i1                    => p_iyear,
         p_i2                    => 2,
         p_i3                    => 1
      );
   END IF;

   IF l_has_sum THEN
      p_sum_req_id := MI_Request_Api.create_Request(
         p_inf_id                => cInf_Id,
         p_correlation_id        => p_correlation_id,
         p_original_request_uuid => p_original_request_uuid,
         p_ctaxreq_id            => p_ctaxreq_id,
         p_message_uuid          => p_message_uuid,
         p_status_cd             => 0,
         p_i1                    => p_iyear,
         p_i2                    => 2,
         p_i3                    => 2
      );
   END IF;

   /*
    * Сопоставляем все позиции c историей вида 8.
    * Не найденная позиция остаётся в mi_0081 с NOT_FOUND.
    * Неоднозначная позиция приводит к откату всей регистрации.
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
                SELECT 1
                  FROM xxi.mi_req AS r
                 WHERE r.req_id = m.req_id
                   AND r.inf_id = 8
                   AND r.status_cd IN (1, 2, 3)
             )
       GROUP BY p.inum, p.icorr, p.rkind
   )
   INSERT INTO xxi.mi_0081
   (
      req_id, source_itm_id, iyear, inum, icorr, result_code
   )
   SELECT CASE WHEN s.rkind = 1 THEN p_doc_req_id ELSE p_sum_req_id END,
          s.source_itm_id,
          p_iyear, s.inum, s.icorr,
          CASE WHEN s.match_count = 0 THEN 'NOT_FOUND' ELSE NULL END
     FROM resolved AS s
    WHERE NOT EXISTS
          (
             SELECT 1 FROM resolved WHERE match_count > 1
          );

   GET DIAGNOSTICS l_inserted = ROW_COUNT;

   IF l_inserted <> l_position_count THEN
      RAISE EXCEPTION
         'MI_0081: ambiguous source position or registration cardinality mismatch: expected=%, inserted=%',
         l_position_count, l_inserted;
   END IF;

   SELECT count(*) FILTER (WHERE i.source_itm_id IS NOT NULL),
          count(*) FILTER (WHERE i.source_itm_id IS NULL)
     INTO p_found_count, p_not_found_count
     FROM xxi.mi_0081 AS i
    WHERE i.req_id = p_doc_req_id
       OR i.req_id = p_sum_req_id;

   /*
    * Одно подтверждение на весь входящий payload.
    * Якорь детерминирован: первый itm_id группы Doc, иначе Sum.
    * Это транспортная привязка mi_rsp, а не признак владельца payload.
    */
   l_anchor_req_id := coalesce(p_doc_req_id, p_sum_req_id);

   SELECT min(i.itm_id)
     INTO l_anchor_itm_id
     FROM xxi.mi_0081 AS i
    WHERE i.req_id = l_anchor_req_id;

   IF l_anchor_itm_id IS NULL THEN
      RAISE EXCEPTION 'MI_0081: no item to anchor synchronous response';
   END IF;

   p_rsp_id := MI_Response_Api.create_Response(
      p_req_id       => l_anchor_req_id,
      p_itm_id       => l_anchor_itm_id,
      p_category_cd  => 'SUCCESS',
      p_result_code  => 'OK',
      p_result_info  => format( 'Registered %s position(s), NOT_FOUND=%s', l_position_count, p_not_found_count ),
      p_payload      => jsonb_build_object('confirmed_at', clock_timestamp())
   );

   IF p_rsp_id IS NULL THEN
      RAISE EXCEPTION 'MI_0081: MI_Response_Api.create_Response returned NULL';
   END IF;

   CALL MI_Response_Api.to_Ready(
      p_rsp_id   => p_rsp_id,
      p_res_code => l_ready_code,
      p_res_info => l_ready_info
   );

   IF l_ready_code IS DISTINCT FROM 0 THEN
      RAISE EXCEPTION 'MI_0081: cannot mark response READY: %', coalesce(l_ready_info, '<empty>');
   END IF;

END;
$procedure$


/*
 * Принимает входящий Payload ФНС, регистрирует позиции и отправляет
 * синхронное подтверждение через существующий MI_Response_Api/mi_mbus.
 *
 * Не запускает финансовый расчёт: его сбой не должен откатывать приём.
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

   l_doc_req_id    numeric;
   l_sum_req_id    numeric;
   l_rsp_id        numeric;
   l_is_repeat     boolean;
   l_found_count   bigint;
   l_missing_count bigint;

   l_send_result   MI_resultCtx.exec_Result;

BEGIN

   p_ret_code := -1;
   p_ret_info := NULL;

   if num_nulls(p_message_uuid, p_original_request_uuid, p_correlation_id, p_request_time, p_payload_text) > 0 OR btrim(p_payload_text) = '' then
      p_ret_info := 'INVALID_REQUEST_PARAMETERS';
      RETURN;
   end if;

   /* Только ошибка разбора JSON преобразуется в отказ входной валидации. */
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
      p_ret_info := format( 'INVALID_REQUEST_ID: %s', l_ctaxreq_id );
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

   /* Формат каждого элемента, включая numeric(12)/numeric(2), проверяем заранее. */
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
      p_ret_info := format('INVALID_CLARIFICATIONS: invalid_count=%s', l_invalid_count);
      RETURN;
   END IF;

   /* Один inum/icorr в пределах входящего сообщения только один раз. */
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

   /* Независимая автономная регистрация и сохранение READY response. */
   CALL mi_0081_api.register_Request_AT(
      p_original_request_uuid => p_original_request_uuid,
      p_correlation_id        => p_correlation_id,
      p_message_uuid          => p_message_uuid,
      p_ctaxreq_id            => l_ctaxreq_id,
      p_iyear                 => l_iyear,
      p_positions             => l_positions,
      p_doc_req_id            => l_doc_req_id,
      p_sum_req_id            => l_sum_req_id,
      p_rsp_id                => l_rsp_id,
      p_is_repeat             => l_is_repeat,
      p_found_count           => l_found_count,
      p_not_found_count       => l_missing_count
   );

   /* Отправка выполняется после фиксации регистрации. */
   CALL mi_mbus.send_response(
      p_rsp_id => l_rsp_id,
      p_result => l_send_result
   );

   IF l_send_result.is_success IS NOT TRUE THEN
      p_ret_info := format(
         'REGISTERED_BUT_RESPONSE_NOT_SENT: rsp_id=%s; %s',
         l_rsp_id,
         coalesce(l_send_result.result_info, 'unknown transport failure')
      );
      RETURN;
   END IF;

   p_ret_code := 0;
   p_ret_info := format(
      '%s: doc_req_id=%s, sum_req_id=%s, found=%s, not_found=%s, rsp_id=%s',
      CASE WHEN l_is_repeat THEN 'ALREADY_REGISTERED' ELSE 'REGISTERED' END,
      coalesce(l_doc_req_id::text, '<none>'),
      coalesce(l_sum_req_id::text, '<none>'),
      l_found_count,
      l_missing_count,
      l_rsp_id
   );

EXCEPTION WHEN OTHERS THEN
   /* Ошибка отправки не откатывает регистрацию из автономной транзакции. */
   p_ret_code := -1;
   p_ret_info := SQLERRM;
END;
$procedure$

/* Конец пакета. */
;

COMMENT ON SCHEMA mi_0081_api IS
   'MI-edo. Входящие запросы ФНС, ВС 81. Версия 0.1.0 {$Id$}'
;

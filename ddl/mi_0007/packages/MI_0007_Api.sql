CREATE OR REPLACE PACKAGE mi_0007_api

CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
DECLARE

   cVersion  CONSTANT varchar(20) := '1.0.1';

   cPkg_Name CONSTANT varchar(20) := 'mi_0007_Api';
   cLogger   CONSTANT varchar(20) := 'mi.0007';

   ret_OK    CONSTANT int4 := 0;
   ret_FAIL  CONSTANT int4 := -1;

   cInitiator_Slf CONSTANT numeric := -1;

   g_PsrtRf_Id numeric := null;

BEGIN
   RAISE DEBUG 'Package "%" - % - initialized', cPkg_Name, cVersion;
END;
$init$


/* Версия */
CREATE FUNCTION get_Version()
   RETURNS
      varchar
AS
$function$
   #package
BEGIN
   RETURN cVersion;
END;
$function$


/* Код типа ДУЛ паспорт РФ */
CREATE FUNCTION get_PassportRF_Id()
   RETURNS
      numeric
AS
$function$
   #package
   #private
BEGIN

   IF g_PsrtRf_Id is not null THEN
      return g_PsrtRf_Id;
   END IF;

   SELECT pud.ipudid
     INTO g_PsrtRf_Id
     FROM pud
    WHERE 
          ipudint_code = 1;

   IF NOT FOUND THEN

      CALL mi_logger.error(
         p_logger_name  => cLogger,
         p_message_text => 'Не задан ID типа документа для паспорта РФ. Не установлено поле IPUDINT_CODE в 1 в таблице PUD.',
         p_action_cd    => 'get_PassportRF_Id',
         p_object_name  => cPkg_Name
      );

      RAISE EXCEPTION USING
            ERRCODE = 'MI',
            MESSAGE = 'Не задан ID типа документа для "Паспорт гражданина РФ". Не установлено поле IPUDINT_CODE в 1 в таблице PUD.';

   END IF;

   CALL mi_logger.info(
      p_logger_name  => cLogger,
      p_message_text => 'ID типа документа для паспорта РФ: ' || g_PsrtRf_Id,
      p_action_cd    => 'get_PassportRF_Id',
      p_object_name  => cPkg_Name
   );

   RETURN g_PsrtRf_Id;

END;
$function$


/* */
CREATE FUNCTION build_Json_Person (
   IN p_icusnum     numeric,
   IN p_last_name   varchar,
   IN p_first_name  varchar,
   IN p_middle_name varchar,
   IN p_birth_date  date,
   IN p_doc_series  varchar,
   IN p_doc_number  varchar,
   IN p_doc_issue_date date,
   IN p_region_code varchar
)
   RETURNS
      jsonb
AS
$function$
   #package
   #private
DECLARE
   l_json jsonb;
BEGIN
   l_json :=
      jsonb_build_object (
         'icusnum',        p_icusnum,
         'last_name',      p_last_name,
         'first_name',     p_first_name,
         'middle_name',    p_middle_name,
         'birth_date',     p_birth_date,
         'doc_type_id',    MI_0007_api.get_PassportRF_Id(),
         'doc_ser',        p_doc_series,
         'doc_num',        p_doc_number,
         'doc_issue_date', p_doc_issue_date,
         'region_code',    p_region_code
      );

   RETURN jsonb_strip_nulls(l_json);

END;
$function$


/*
   Создать item 0007
*/
CREATE FUNCTION create_Item (
   IN p_req_id    numeric,
   IN p_person_id numeric
)
   RETURNS
      numeric
AS
$function$
   #package
   #private
DECLARE
   l_itm_id numeric;
BEGIN

   l_itm_id := mi_request_Api.next_Itm_Id( );

   INSERT INTO xxi.mi_0007 (
      itm_id,
      req_id,
      person_id,
      created_at
   )
   VALUES(
      l_itm_id,
      p_req_id,
      p_person_id,
      clock_timestamp()
   );

   RETURN l_itm_id;

END;
$function$


/*
   Создать request для 0007
*/
CREATE FUNCTION create_Request (
   IN p_inf_Id numeric DEFAULT 74::numeric
)
   RETURNS
      numeric
AS
$function$
   #package
   #private
BEGIN
   RETURN mi_request_Api.create_Request( p_inf_Id, NULL::uuid );
END;
$function$


/*
   Главная функция создания request 0007
*/
CREATE FUNCTION create_Person_Item (
   IN p_json_person jsonb
)
   RETURNS
      numeric
AS
$function$
   #package
DECLARE
   l_person_id numeric;
   l_req_id    numeric;
   l_itm_id    numeric;
BEGIN

   l_person_id := mi_person_Api.get_Or_Create(
      p_inf_id      => 74::numeric,
      p_json_person => p_json_person
   );

   l_req_id := mi_0007_Api.create_Request( );

   l_itm_id := mi_0007_Api.create_Item(
      p_req_id    => l_req_id,
      p_person_id => l_person_id
   );

   RETURN l_itm_Id;

END;
$function$


/*
   Перегрузка:
   icusnum приходит отдельно от json payload
*/
CREATE FUNCTION create_Person_Item (
   IN p_icusnum     numeric,
   IN p_json_person jsonb,
   IN p_inf_Id      numeric DEFAULT 74::numeric
)
   RETURNS
      numeric
AS
$function$
   #package
DECLARE
   l_person_id numeric;
   l_req_id    numeric;
   l_itm_id    numeric;
BEGIN

   l_person_id := MI_person_Api.get_Or_Create (
      p_inf_Id,
      p_icusnum::numeric,
      p_json_person::jsonb
   );

   l_req_id := mi_0007_Api.create_Request (
      p_inf_Id => p_inf_Id 
   );

   l_itm_id := mi_0007_Api.create_Item(
      p_req_id    => l_req_id,
      p_person_id => l_person_id
   );

   RETURN l_itm_id;

END;
$function$


/* Проверка атрибутов клиента, для создания записи запроса по паспортам */
CREATE FUNCTION check_Attrs (
   IN p_last_name    varchar,
   IN p_first_name   varchar,
   IN p_middle_name  varchar,
   IN p_doc_ser      varchar,
   IN p_doc_num      varchar
)
   RETURNS
      VARCHAR
AS
$function$
   #private
   #package
DECLARE
   l_msg varchar;
BEGIN
   IF p_last_name IS NULL THEN
      l_msg := ', Фамилия';
   END IF;

   IF p_first_name IS NULL THEN
      l_msg := coalesce(l_msg, '') || ', Имя';
   END IF;

   IF p_doc_ser IS NULL THEN
      l_msg := coalesce(l_msg, '') || ', Серия паспорта';
   END IF;

   IF p_doc_num IS NULL THEN
      l_msg := coalesce(l_msg, '') || ', Номер паспорта';
   END IF;

   IF l_msg IS NOT NULL THEN
      RETURN 'Создание записи не возможно, не заданы обязательные атрибуты: ' || substr(l_msg, 3);
   END IF;

   IF regexp_replace(coalesce(p_doc_ser, ''), '\s+', '', 'g') !~ '^\d{4}$' THEN
      RETURN 'Создание записи не возможно: не корректное значение серии паспорта - "' || coalesce(p_doc_ser, '') || '". Требуется 4 цифры.';
   END IF;

   IF regexp_replace(coalesce(p_doc_num, ''), '\s+', '', 'g') !~ '^\d{6}$' THEN
      RETURN 'Создание записи не возможно: не корректное значение номера паспорта - "'|| coalesce(p_doc_num, '') || '". Требуется 6 цифр.';
   END IF;

   IF p_last_name !~ '^[А-Яа-яЁё\-\s,.]{1,100}$' THEN
      RETURN 'Создание записи не возможно: не корректное значение Фамилии - "'
             || p_last_name
             || '". Русский текст, длиной до 100 символов, тире, цифры не допускаются.';
   END IF;

   IF p_first_name !~ '^[А-Яа-яЁё\-\s,.]{1,100}$' THEN
      RETURN 'Создание записи не возможно: не корректное значение Имени - "'
             || p_first_name
             || '". Русский текст, длиной до 100 символов, тире, цифры не допускаются.';
   END IF;

   IF p_middle_name IS NOT NULL
      AND p_middle_name !~ '^[А-Яа-яЁё\-\s,.]{1,100}$' THEN
      RETURN 'Создание записи не возможно: не корректное значение Отчества - "'
             || p_middle_name
             || '". Русский текст, длиной до 100 символов, тире, цифры не допускаются.';
   END IF;

   RETURN NULL;

END;
$function$


/* */
CREATE PROCEDURE has_Entry_Set (
   IN  p_inf_id        numeric,
   IN  p_icusnum       numeric,
   IN  p_last_name     varchar,
   IN  p_first_name    varchar,
   IN  p_middle_name   varchar,
   IN  p_doc_num       varchar,
   IN  p_doc_ser       varchar,
   IN  p_doc_issue_date date,
   IN  p_birth_date    date,
   IN  p_n_day         numeric,
   OUT p_found         boolean,
   OUT p_iState        numeric,
   OUT p_req_id        numeric,
   OUT p_itm_id        numeric
)
AS
$procedure$
   #private
   #package
DECLARE
   cPsrtRf CONSTANT numeric := MI_0007_api.get_PassportRF_Id();
BEGIN

   p_found  := false;
   p_iState := null;
   p_req_id := null;
   p_itm_id := null;

   SELECT coalesce( v.ires_code, r.status_cd ),
          v.req_id,
          v.itm_id
     INTO p_iState, p_req_id, p_itm_id
     FROM xxi.v_mi_0007 v inner join xxi.mi_req r on r.req_Id = v.req_Id
    WHERE upper(v.last_name ) = upper( p_last_name )
      AND upper(v.first_name) = upper( p_first_name)
      AND (p_middle_name IS NULL OR upper(v.middle_name) = upper(p_middle_name))
      AND ((v.birth_date IS NULL OR p_birth_date IS NULL) OR v.birth_date = p_birth_date)
      AND v.doc_Type_Id = cPsrtRf
      AND replace(v.doc_num, ' ', '') = replace(p_doc_num, ' ', '' )
      AND replace(v.doc_ser, ' ', '') = replace(p_doc_ser, ' ', '' )
      AND ( p_doc_issue_date IS NULL OR v.doc_issue_date = p_doc_issue_date )
      AND r.inf_id = p_inf_id
      AND current_date < ( coalesce(v.tres_time, v.created_at)::date + p_n_day::int4 )
    ORDER BY
          CASE WHEN r.status_cd = 1 THEN 1 ELSE 2 END,
          v.tres_time DESC NULLS LAST,
          v.created_at DESC,
          v.itm_id DESC
    LIMIT 1;

   IF FOUND THEN
      p_found := true;
   END IF;

END;
$procedure$


/* Запрос в таблицу на наличии, записи с ручной установкой валидности */
CREATE PROCEDURE has_Manual_Set (
   IN  p_icusnum        numeric,
   IN  p_last_name      varchar,
   IN  p_first_name     varchar,
   IN  p_middle_name    varchar,
   IN  p_doc_num        varchar,
   IN  p_doc_ser        varchar,
   IN  p_doc_issue_date date,
   IN  p_n_day          numeric,
   OUT p_found          boolean,
   OUT p_iState         numeric,
   OUT p_req_id         numeric,
   OUT p_itm_id         numeric
)
AS
$procedure$
   #private
   #package
BEGIN

   CALL mi_0007_Api.has_Entry_Set (
        75::numeric, p_icusnum, p_last_name, p_first_name, p_middle_name, p_doc_num, p_doc_ser, p_doc_issue_date, NULL::date,
       p_n_day, p_found, p_iState, p_req_id, p_itm_id
   );

   IF coalesce( p_iState, -1) <> 300 THEN
      p_found  := false;
      p_iState := null;
      p_req_id := null;
      p_itm_id := null;
   END IF;

END;
$procedure$


/* Создает новый запрос, и если надо отправляет в MI */
CREATE PROCEDURE create_And_Exec (
   IN  p_inf_id          numeric,

   IN  p_icusnum         numeric,
   IN  p_last_name       varchar,
   IN  p_first_name      varchar,
   IN  p_middle_name     varchar,
   IN  p_birth_date      date,
   IN  p_doc_ser         varchar,
   IN  p_doc_num         varchar,
   IN  p_doc_issue_date  date,
   IN  p_region_code     varchar,

   IN  p_time_out        numeric,
   IN  p_do_send         boolean,

   OUT p_res_code        int4,
   OUT p_req_id          numeric,
   OUT p_itm_id          numeric,
   OUT p_iState          numeric,
   OUT p_result_info     varchar
)
AS
$procedure$
   #package
DECLARE

   cAction_Name  CONSTANT varchar(50) :=  cPkg_Name || '.create_And_Exec';

   l_inf_id      numeric := coalesce( p_inf_id, 74::numeric );
   l_n_day       numeric;
   l_json_person jsonb;
   l_person_id   numeric;
   l_check_msg   varchar;

   l_req_id      numeric;
   l_itm_id      numeric;

   l_res_code_75 int4;
   l_res_info_75 varchar;

   l_found       boolean;

BEGIN

   p_res_code    := ret_Fail;
   p_req_id      := null;
   p_itm_id      := null;
   p_iState      := null;
   p_result_info := null;

   CALL MI_logger.enter_f( p_logger_name => cLogger, p_function_name => cAction_Name, p_inf_id => p_inf_id, p_icusnum => p_icusnum );

   BEGIN

      l_check_msg := mi_0007_Api.check_Attrs (
         p_last_name,
         p_first_name,
         p_middle_name,
         p_doc_ser,
         p_doc_num
      );

      IF l_check_msg IS NOT NULL THEN
         p_res_code    := ret_Fail;
         p_result_info := l_check_msg;

         RETURN;

      END IF;

      l_n_day := mi_prp.get_Wsp_Property( 7::numeric, 'VALID_PERIOD_DOC_DAYS', '0')::numeric;

      CALL mi_0007_Api.has_Manual_Set(
         p_icusnum,
         p_last_name,
         p_first_name,
         p_middle_name,
         p_doc_num,
         p_doc_ser,
         p_doc_issue_date,
         l_n_day,
         l_found,
         p_iState,
         p_req_id,
         p_itm_id
      );

      IF l_found THEN

         p_res_code    := ret_OK;
         p_result_info := null;

         RETURN;

      END IF;

      IF l_inf_id <> 75 THEN

         CALL mi_0007_Api.has_Entry_Set ( 74::numeric,
            p_icusnum,
            p_last_name,
            p_first_name,
            p_middle_name,
            p_doc_num,
            p_doc_ser,
            p_doc_issue_date,
            p_birth_date,
            l_n_day,
            l_found,
            p_iState,
            p_req_id,
            p_itm_id
         );

         IF l_found THEN
            p_res_code    := ret_OK;
            p_result_info := null;
            RETURN;
         END IF;

      END IF;

      IF l_inf_id = 75 THEN

         CALL mi_0007_Api.create_75_Person_Item (
            p_icusnum,
            p_last_name,
            p_first_name,
            p_middle_name,
            p_doc_ser,
            p_doc_num,
            p_doc_issue_date,
            p_birth_date,
            p_region_code,
            l_res_code_75,
            l_res_info_75
         );

         p_res_code    := l_res_code_75;
         p_result_info := l_res_info_75;

         RETURN;

      END IF;

      l_json_person := mi_0007_Api.build_Json_Person (
         p_icusnum,
         p_last_name,
         p_first_name,
         p_middle_name,
         p_birth_date,
         p_doc_ser,
         p_doc_num,
         p_doc_issue_date,
         p_region_code
      );

      l_person_id := mi_person_Api.get_Or_Create(
         l_inf_id,
         l_json_person
      );

      l_req_id := mi_0007_Api.create_Request(
         l_inf_id
      );

      l_itm_id := mi_0007_Api.create_Item(
         l_req_id,
         l_person_id
      );

      p_req_id := l_req_id;
      p_itm_id := l_itm_id;

   end;

   COMMIT;

   DECLARE
      l_result  mi_resultctx.exec_result;
   BEGIN

      IF p_do_send THEN

         CALL MI_MBus.send_Request( p_req_id, l_result );

         IF coalesce( p_time_out, 0 ) > 0 THEN
            PERFORM pg_sleep(p_time_out);
         END IF;

         IF l_result.is_success THEN
            p_res_code := RET_OK;
            p_result_info := coalesce(l_result.result_info, '����������');
         ELSE
            p_res_code := RET_Fail;
            p_result_info := coalesce(l_result.result_info, '������ �������� � M-Bus');
         END IF;

      END IF;

      if p_res_code = ret_OK THEN

      SELECT coalesce( v.ires_code, r.status_cd )
        INTO p_iState
        FROM xxi.v_mi_0007 v inner join xxi.mi_req r on v.req_Id = r.req_Id
       WHERE v.itm_id = p_itm_id;

      END IF;

      -- CALL mi_logger.info( cLogger, 'create_And_Exec completed', l_inf_id, p_req_id, NULL::varchar, NULL::text, NULL::varchar, cAction_Name, l_person_id, p_icusnum, p_itm_id, NULL::numeric );
      CALL MI_logger.info(
         p_logger_name => cLogger,
         p_message_text=> 'create_And_Exec completed',
         p_inf_id => l_inf_id,
         p_req_id => p_req_id,
         p_icusnum => p_icusnum
      );


   EXCEPTION

      WHEN OTHERS THEN
         DECLARE
            ex TS.T_StackedDiagnostics;
         BEGIN
           GET STACKED DIAGNOSTICS
               ex.RETURNED_SQLSTATE    = RETURNED_SQLSTATE,
               ex.MESSAGE_TEXT         = MESSAGE_TEXT,
               ex.PG_EXCEPTION_DETAIL  = PG_EXCEPTION_DETAIL,
               ex.PG_EXCEPTION_HINT    = PG_EXCEPTION_HINT,
               ex.PG_EXCEPTION_CONTEXT = PG_EXCEPTION_CONTEXT;

               CALL mi_logger.error (
                    p_logger_name => cLogger,
                    p_message_text=> TS.WhenOthersError( cAction_Name, ex ),
                    p_inf_id => l_inf_id,
                    p_req_id => p_req_id
               );

         END;

         p_res_code    := ret_Fail;
         p_result_info := SQLERRM;

         RAISE;
   end;

END;
$procedure$


/* Создание запроса для конкретного cus атрибуты подтягиваются из справочника */
CREATE PROCEDURE create_And_Exec(
   IN  p_inf_id       numeric,
   IN  p_icusnum      numeric,
   IN  p_time_out     numeric,
   IN  p_do_send      boolean,
   OUT p_res_code     int4,
   OUT p_req_id       numeric,
   OUT p_itm_id       numeric,
   OUT p_iState       numeric,
   OUT p_result_info  varchar
)
AS
$procedure$
   #package
DECLARE
   cAction_Name CONSTANT varchar(30) := 'create_and_exec.2';

   cPsrtRf numeric := MI_0007_api.get_PassportRF_Id();

   l_last_name       varchar;
   l_first_name      varchar;
   l_middle_name     varchar;
   l_birth_date      date;
   l_doc_ser         varchar;
   l_doc_num         varchar;
   l_doc_issue_date  date;
   l_region_code     varchar := null;

BEGIN

   p_res_code    := -1;
   p_req_id      := null;
   p_itm_id      := null;
   p_iState      := null;
   p_result_info := null;

   SELECT
         a.ccuslast_name,
         a.ccusfirst_name,
         a.ccusmiddle_name,
         a.dcusbirthday,
         b.doc_ser,
         b.doc_num,
         b.doc_date
     INTO
         l_last_name,
         l_first_name,
         l_middle_name,
         l_birth_date,
         l_doc_ser,
         l_doc_num,
         l_doc_issue_date
     FROM "CUS" a,
          cus_docum b
    WHERE a.icusnum   = b.icusnum
      AND b.id_doc_tp = cPsrtRf
      AND a.ccusflag  IN ( '1', '4' ) -- ФЛ и ИП
      AND ( b.doc_period IS NULL OR b.doc_period >= now()::date )
      AND a.icusnum   = p_iCusNum;

   IF NOT FOUND THEN

      p_res_code    := -1;
      p_result_info := 'Не найден клиент в справочнике по icusnum = ' || p_icusnum;

      CALL mi_logger.info (
         p_logger_name   => cLogger,
         p_message_text  => 'create_And_Exec rejected: cus not found',
         p_inf_id        => p_inf_id,
         p_details_text  => p_result_info,
         p_action_cd     => cAction_Name,
         p_context_value => 'icusnum=' || p_icusnum::varchar,
         p_object_name   => cPkg_Name,
         p_icusnum       => p_icusnum
      );

      RETURN;

   END IF;

   CALL mi_0007_Api.create_And_Exec(
      p_inf_id,
      p_icusnum,
      l_last_name,
      l_first_name,
      l_middle_name,
      l_birth_date,
      l_doc_ser,
      l_doc_num,
      l_doc_issue_date,
      l_region_code,
      p_time_out,
      p_do_send,
      p_res_code,
      p_req_id,
      p_itm_id,
      p_iState,
      p_result_info
   );

END;
$procedure$


/* Создает запрос для 75 вида сведений - ручная установка */
CREATE PROCEDURE create_75_Person_Item(
   IN  p_icusnum         numeric,
   IN  p_last_name       varchar,
   IN  p_first_name      varchar,
   IN  p_middle_name     varchar,
   IN  p_doc_ser         varchar,
   IN  p_doc_num         varchar,
   IN  p_doc_issue_date  date,
   IN  p_birth_date      date,
   IN  p_region_code     varchar,
   OUT p_res_code        int4,
   OUT p_res_info        varchar
)
AS
$procedure$
   #package
DECLARE

   cAction_Name  CONSTANT varchar(100) := cPkg_Name || '.create_75_item';

   l_json_person jsonb;
   l_person_id   numeric;
   l_req_id      numeric;
   l_itm_id      numeric;

BEGIN

   p_res_code := ret_Fail;
   p_res_info := NULL;

   l_json_person := mi_0007_Api.build_json_person (
      p_icusnum::numeric,
      p_last_name::varchar,
      p_first_name::varchar,
      p_middle_name::varchar,
      p_birth_date::date,
      p_doc_ser::varchar,
      p_doc_num::varchar,
      p_doc_issue_date::date,
      p_region_code::varchar
   );

   l_person_id := mi_person_Api.get_Or_Create (
      75::numeric,
      l_json_person
   );

   /*
     Последний request для inf_id = 75, нет - создаём новый СРАЗУ в status = 1
   */
   SELECT r.req_id
     INTO l_req_id
     FROM xxi.mi_req r
    WHERE r.inf_id = 75::numeric
    ORDER BY r.created_at DESC,
             r.req_id DESC
    LIMIT 1;

   IF NOT FOUND THEN

      l_req_id := mi_Request_Api.create_Request (
         p_inf_id    => 75::numeric,
         p_status_cd =>  1::numeric
      );

   END IF;

   l_itm_id := mi_request_Api.next_Itm_Id( );

   INSERT INTO xxi.mi_0007 (
      itm_id,
      req_id,
      person_id,
      created_at,
      ires_code,
      tres_time
   )
   VALUES(
      l_itm_id,
      l_req_id,
      l_person_id,
      clock_timestamp(),
      300::numeric,
      clock_timestamp()
   );

   p_res_code := 0;
   p_res_info := 'Создан item 75. req_id=' || l_req_id || ', itm_id=' || l_itm_id;

   CALL mi_logger.info(
      p_logger_name  => cLogger,
      p_message_text => 'create_75_Person_Item completed',
      p_inf_id       => 75,
      p_req_id       => l_req_id,
      p_itm_Id       => l_itm_id,
      p_details_text => p_res_info,
      p_action_cd    => cAction_Name,
      p_object_name  => cPkg_Name,
      p_person_id    => l_person_id,
      p_icusnum      => p_icusnum
   );

EXCEPTION
   WHEN OTHERS THEN
      DECLARE
         ex TS.T_StackedDiagnostics;
      BEGIN
        GET STACKED DIAGNOSTICS
            ex.RETURNED_SQLSTATE    = RETURNED_SQLSTATE,
            ex.MESSAGE_TEXT         = MESSAGE_TEXT,
            ex.PG_EXCEPTION_DETAIL  = PG_EXCEPTION_DETAIL,
            ex.PG_EXCEPTION_HINT    = PG_EXCEPTION_HINT,
            ex.PG_EXCEPTION_CONTEXT = PG_EXCEPTION_CONTEXT;

            CALL mi_logger.error(
               p_logger_name  => cLogger,
               p_message_text => cAction_Name || ' failed',
               p_inf_id       => 75,
               p_req_id       => l_req_id,
               p_details_text => TS.WhenOthersError( cPkg_Name || '.' || cAction_Name, ex ),
               p_action_cd    => 'exception',
               p_object_name  => cPkg_Name
            );

      END;

   RAISE;

END;
$procedure$


/* Создание запроса с позициями на основе маркера в "CUS" */
CREATE PROCEDURE create_Person_Items_By_Marker (
    IN p_marker_id      numeric,
   OUT p_req_id         numeric,
   OUT p_created_count  int4,
   OUT p_res_Code       int4,
   OUT p_res_Info       varchar
)
AS
$procedure$
   #package
DECLARE
   cAction_Name   CONSTANT varchar(20) := 'create_items_batch';
   cInf_Id        CONSTANT numeric     := 74::numeric;
   r              record;
   l_has_rows     boolean;

   l_json_person  jsonb;
   l_person_id    numeric;
   l_itm_id       numeric;

BEGIN

   p_req_id        := NULL;
   p_created_count := 0;
   p_res_code      := 0;
   p_res_info      := NULL;

   /*
     Проверка marker. Если пустой - request НЕ создаём.
   */
   SELECT EXISTS (
      SELECT 1
        FROM xxi.mrk_id m WHERE m.idmarker = p_marker_id
   )
     INTO l_has_rows;

   IF NOT l_has_rows THEN

      p_res_code := 0;
      p_res_info := 'По marker_id = ' || p_marker_id || ' не найдено помеченных клиентов. Request не создан.';

      CALL mi_logger.info (
         p_logger_name   => cLogger,
         p_message_text  => 'create_Person_Items_By_Marker skipped: marker is empty',
         p_inf_id        => cInf_Id,
         p_details_text  => p_res_info,
         p_action_cd     => cAction_Name,
         p_context_value => 'marker_id=' || p_marker_id::varchar,
         p_object_name   => cPkg_Name
      );

      RETURN;

   END IF;

   /*
     Новый request для всей batch-операции
   */
   p_req_id := mi_0007_Api.create_Request( );

   CALL mi_logger.info(
      p_logger_name   => cLogger,
      p_message_text  => 'Batch request created',
      p_inf_id        => cInf_Id,
      p_req_id        => p_req_id,
      p_action_cd     => cAction_Name,
      p_context_value => 'marker_id=' || p_marker_id::varchar,
      p_object_name   => cPkg_Name
   );

   /*
     Клиенты из marker
   */
   FOR r IN
   (
      SELECT c.icusnum,
             c.ccuslast_name last_Name,
             c.ccusfirst_name first_Name,
             c.ccusmiddle_name middle_Name,
             c.dcusbirthday birth_date,
             b.doc_ser doc_ser,
             b.doc_num doc_num,
             b.doc_date doc_issue_date,
             null::varchar AS region_code
        FROM xxi.mrk_id m
        JOIN xxi."CUS" c
          ON c.icusnum  = m.idrow
             join cus_docum b on c.icusnum = b.icusnum
       WHERE m.idmarker = p_marker_id )
   LOOP

      l_json_person := mi_0007_Api.build_json_person (
         r.icusnum::numeric,
         r.last_name::varchar,
         r.first_name::varchar,
         r.middle_name::varchar,
         r.birth_date::date,
         r.doc_ser::varchar,
         r.doc_num::varchar,
         r.doc_issue_date::date,
         r.region_code::varchar
      );

      l_person_id := mi_person_Api.get_Or_Create (
         cInf_Id,
         l_json_person
      );

      l_itm_id := mi_0007_Api.create_Item (
         p_req_id,
         l_person_id
      );

      p_created_count := p_created_count + 1;

      CALL mi_logger.debug (
         p_logger_name   => cLogger,
         p_message_text  => 'Batch item created',
         p_inf_id        => cInf_Id,
         p_req_id        => p_req_id,
         p_itm_Id        => l_itm_id,
         p_action_cd     => cAction_Name,
         p_context_value => 'icusnum=' || r.icusnum::varchar,
         p_object_name   => cPkg_Name,
         p_person_id     => l_person_id,
         p_icusnum       => r.icusnum
      );

   END LOOP;

   p_res_code := ret_OK;
   p_res_info := 'Создан request, req_id=' || p_req_id || ', item_count=' || p_created_count::varchar;

   CALL mi_logger.info(
      p_logger_name   => cLogger,
      p_message_text  => 'create_Person_Items_By_Marker completed',
      p_inf_id        => cInf_Id,
      p_req_id        => p_req_id,
      p_details_text  => p_res_info,
      p_action_cd     => cAction_Name,
      p_context_value => 'marker_id=' || p_marker_id::varchar,
      p_object_name   => cPkg_Name
   );

EXCEPTION
   WHEN OTHERS THEN
      DECLARE
         ex TS.T_StackedDiagnostics;
      BEGIN
        GET STACKED DIAGNOSTICS
            ex.RETURNED_SQLSTATE    = RETURNED_SQLSTATE,
            ex.MESSAGE_TEXT         = MESSAGE_TEXT,
            ex.PG_EXCEPTION_DETAIL  = PG_EXCEPTION_DETAIL,
            ex.PG_EXCEPTION_HINT    = PG_EXCEPTION_HINT,
            ex.PG_EXCEPTION_CONTEXT = PG_EXCEPTION_CONTEXT;

            p_res_Info := TS.WhenOthersError( cPkg_Name || '.' || cAction_Name, ex );

            CALL mi_logger.error(
               p_logger_name  => cLogger,
               p_message_text => cAction_Name || ' failed',
               p_inf_id       => cInf_Id,
               p_req_id       => p_req_id,
               p_details_text => p_res_Info,
               p_action_cd    => 'exception',
               p_object_name  => cPkg_Name
            );

      END;

   p_res_code := ret_Fail;
   p_res_info := coalesce( p_res_Info, SQLERRM );

   RAISE;

END;
$procedure$


CREATE FUNCTION map_Item_Result (
   IN p_itm_Id  numeric,
   IN p_payload jsonb
)
RETURNS
   MI_Item_Result_Api.Item_Result
AS
$function$
   #package
DECLARE
   l_result     MI_Item_Result_Api.Item_Result;
   l_doc_status numeric;
BEGIN
   l_doc_status := NULLIF(p_payload ->> 'docStatus', '')::numeric;

   IF l_doc_status IS NULL THEN
      RAISE EXCEPTION 'docStatus is null in successful payload';
   END IF;

   l_result.ires_code := l_doc_status;
   l_result.cres_info := COALESCE( NULLIF(p_payload ->> 'comment', ''),'docStatus=' || l_doc_status );

   RETURN l_result;

END;
$function$

/* */
CREATE PROCEDURE apply_Item_Result (
   IN  p_request_uuid      uuid,
   IN  p_message_uuid      uuid,
   IN  p_item_uuid         uuid,

   IN  p_response_kind     int4,

   IN  p_response_code     varchar,
   IN  p_response_info     varchar,
   IN  p_response_details  text,
   IN  p_response_time     timestamptz,

   IN  p_payload_text      text,

   OUT p_ret_code          int4,
   OUT p_ret_info          varchar
)
AS
$procedure$
   #package
BEGIN
   CALL MI_Item_Result_Api.apply_Item_Result (

      'xxi.mi_0007'::regclass,
      'MI_0007_Api.map_Item_Result'::regproc,

      p_request_uuid,
      p_message_uuid,
      p_item_uuid,

      p_response_kind,

      p_response_code,
      p_response_info,
      p_response_details,
      p_response_time,

      p_payload_text,

      p_ret_code,
      p_ret_info
   );
END;
$procedure$


/* end_Of_Package */
;

COMMENT ON SCHEMA mi_0007_api IS 'Package mi_0007_api {$Id$}'
;

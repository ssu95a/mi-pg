CREATE OR REPLACE PACKAGE mi_0062_api

   -- Инициализация пакета
   CREATE FUNCTION __init__() RETURNS void AS $$
   DECLARE
      /*
         Пакет для ведения логики MI-edo
         Модуль: Начисления по УИН/ЕИП (вид сведений 0062)
      */
      cVersion CONSTANT VARCHAR(100) := '$id: {1.0.1} {09.10.2026} Sukhotina$';

      RET_OK   CONSTANT INTEGER := 0;
      RET_FAIL CONSTANT INTEGER := -1;
      RET_NO_DATA CONSTANT INTEGER := 1;

      c_Inf_Id CONSTANT NUMERIC := 62;
      cPkg_Name CONSTANT VARCHAR(20) := 'mi_0062_api';
      c_Logger  CONSTANT VARCHAR(20) := 'mi.0062';
   BEGIN
      RAISE DEBUG 'Package "%" - % - initialized', cPkg_Name, cVersion;
   END;
   $$

   CREATE FUNCTION get_version() RETURNS VARCHAR AS $$
      #package
   BEGIN
      RETURN cVersion;
   END;
   $$

   -- Создание запроса в mi_req
   CREATE FUNCTION create_request(
      p_itype integer
   ) RETURNS NUMERIC AS $$
      #package
      --#private
   BEGIN
      IF p_itype IS NULL OR p_itype NOT IN (1, 2) THEN
         RAISE EXCEPTION 'Недопустимый p_itype: % (допустимо 1-ЕИП, 2-УИН)', p_itype;
      END IF;

      RETURN MI_request_Api.create_Request(
         p_inf_id         => c_Inf_Id,
         p_correlation_id => gen_random_uuid(),
         p_status_cd      => 0,
         p_itype          => p_itype
      );
   END;
   $$

   -- Вставка одного элемента запроса
   CREATE FUNCTION create_item(
      p_req_id    numeric,
      p_id_value  varchar,
      p_icusnum   numeric DEFAULT NULL
   ) RETURNS numeric AS $$
      #package
      --#private
   DECLARE
      l_itm_id numeric;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'create_item',
         p_message_text  => format('req_id=%s, id_value=%s', p_req_id, p_id_value),
         p_inf_id        => c_Inf_Id
      );

      l_itm_id := MI_request_Api.next_Itm_Id();

      INSERT INTO xxi.mi_0062 (
         itm_id,
         req_id,
         icusnum,
         id_value,
         created_at
      ) VALUES (
         l_itm_id,
         p_req_id,
         p_icusnum,
         p_id_value,
         clock_timestamp()
      );

      CALL mi_logger.variable_value(
         p_logger_name   => c_Logger,
         p_variable_name => 'itm_id',
         p_value_text    => l_itm_id::varchar,
         p_inf_id        => c_Inf_Id
      );

      RETURN l_itm_id;
   END;
   $$

   -- Массовое создание элементов одного типа (тип задаётся для всего запроса)
   CREATE PROCEDURE create_items(
      IN  p_id_type       integer,
      IN  p_id_list       varchar,
      OUT p_req_id        numeric,
      OUT p_items_created integer,
      OUT p_ret_code      integer,
      OUT p_ret_info      varchar
   ) AS $$
      #package
   DECLARE
      l_req_id   numeric;
      l_count    integer := 0;
      l_id_value varchar;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'create_items',
         p_message_text  => format('id_type=%s, id_list=%s', p_id_type, p_id_list),
         p_inf_id        => c_Inf_Id
      );

      p_ret_code := RET_FAIL;
      p_ret_info := NULL;
      p_req_id   := NULL;
      p_items_created := 0;

      BEGIN
         IF p_id_type NOT IN (1,2) THEN
            p_ret_info := 'Недопустимый тип идентификатора (допустимо 1-ЕИП, 2-УИН)';
            RETURN;
         END IF;

         IF p_id_list IS NULL OR btrim(p_id_list) = '' THEN
            p_ret_info := 'Список идентификаторов пуст';
            RETURN;
         END IF;

         -- Создание запроса с указанием типа (itype)
         l_req_id := mi_0062_api.create_request(p_id_type);

         IF l_req_id IS NULL THEN
            p_ret_info := 'Не удалось создать запрос в mi_req';
            RETURN;
         END IF;

         FOR l_id_value IN
            SELECT trim(t.v)
              FROM regexp_split_to_table(p_id_list, ';') AS t(v)
             WHERE trim(t.v) IS NOT NULL
               AND trim(t.v) <> ''
         LOOP
            PERFORM mi_0062_api.create_item(
               p_req_id   => l_req_id,
               p_id_value => l_id_value
            );
            l_count := l_count + 1;
         END LOOP;

         IF l_count = 0 THEN
            p_ret_info := 'Не найдено ни одного идентификатора для создания элементов';
            RETURN;
         END IF;

         p_req_id        := l_req_id;
         p_items_created := l_count;
         p_ret_code      := RET_OK;

      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка в create_items',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
      END;

      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('ret_code=%s, req_id=%s, items=%s', p_ret_code, p_req_id, p_items_created),
         p_inf_id        => c_Inf_Id
      );
   END;
   $$

   -- Отправка запроса в СМЭВ
   CREATE PROCEDURE submit_request(
      IN  p_req_id   numeric,
      OUT p_ret_code integer,
      OUT p_ret_info varchar
   ) AS $$
      #package
   DECLARE
      l_result mi_resultctx.exec_result;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'submit_request',
         p_message_text  => 'req_id=' || p_req_id,
         p_inf_id        => c_Inf_Id
      );

      p_ret_code := RET_FAIL;
      p_ret_info := NULL;

      BEGIN
         IF p_req_id IS NULL THEN
            p_ret_info := 'p_req_id is null';
            RETURN;
         END IF;

         -- Вызов отправки
         CALL mi_mbus.send_request(p_req_id, l_result);

         IF NOT l_result.is_success THEN
            p_ret_info := 'Ошибка отправки: ' || coalesce(l_result.result_info, 'неизвестная ошибка');
            RETURN;
         END IF;

         p_ret_code := RET_OK;
         p_ret_info := coalesce(l_result.result_info, 'Запрос отправлен');

      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка в submit_request',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
      END;

      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('ret_code=%s, info=%s', p_ret_code, p_ret_info),
         p_inf_id        => c_Inf_Id
      );
   END;
   $$

   -- Приём результата по элементу
   CREATE PROCEDURE apply_item_result(
      IN  p_request_uuid    uuid,
      IN  p_message_uuid    uuid,
      IN  p_item_uuid       uuid,
      IN  p_response_kind   integer,
      IN  p_response_code   varchar,
      IN  p_response_info   varchar,
      IN  p_response_details text,
      IN  p_response_time   timestamptz,
      IN  p_payload_text    text,
      OUT p_ret_code        integer,
      OUT p_ret_info        varchar
   ) AS $$
      #package
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'apply_item_result',
         p_message_text  => 'item_uuid=' || p_item_uuid,
         p_inf_id        => c_Inf_Id
      );

      CALL MI_Item_Result_Api.apply_Item_Result(
         'xxi.mi_0062'::regclass,
         'MI_0062_Api.map_Item_Result(numeric,jsonb)'::regprocedure,
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

      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('ret_code=%s, ret_info=%s', p_ret_code, p_ret_info),
         p_inf_id        => c_Inf_Id
      );
   END;
   $$

   -- Разбор payload ответа по элементу
   CREATE FUNCTION map_item_result(p_itm_id numeric, p_payload jsonb)
      RETURNS MI_Item_Result_Api.Item_Result AS $$
      #package
   DECLARE
      cFunc      varchar := cPkg_Name || '.map_item_result';
      l_xml      xml;
      l_xml_text text;
      l_result   varchar;
      l_info     varchar;
      l_ires     numeric;
      l_res      MI_Item_Result_Api.Item_Result;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'map_item_result',
         p_message_text  => 'itm_id=' || p_itm_id,
         p_inf_id        => c_Inf_Id
      );

      -- Извлечение XML из payload (структура?)
      l_xml_text := p_payload->>'xml';

      IF l_xml_text IS NULL OR btrim(l_xml_text) = '' THEN
         l_res.iRes_Code := RET_FAIL;
         l_res.cRes_info := 'XML в payload не найден';
         CALL mi_logger.error(
            p_logger_name   => c_Logger,
            p_message_text  => l_res.cRes_info,
            p_inf_id        => c_Inf_Id
         );
         RETURN l_res;
      END IF;

      l_xml := l_xml_text::xml;

      -- Определение результата из ответа
      l_result := (xpath('/response/@result', l_xml))[1]::text;

      IF l_result = 'success' THEN
         l_ires := 0;
      ELSIF l_result = 'fault' THEN
         l_info := coalesce(
            (xpath('/response/message/text()', l_xml))[1]::text,
            (xpath('/response/faultReason/text()', l_xml))[1]::text
         );
         IF l_info LIKE '%data_not_found%' THEN
            l_ires := 1;
         ELSE
            l_ires := -1;
         END IF;
      ELSE
         l_ires := -1;
         l_info := 'Неизвестный ответ: ' || l_xml_text;
      END IF;

      l_res.iRes_Code := l_ires;
      l_res.cRes_info := l_info;

      -- Разбор ChargeInfo ? kz_charges
      IF l_ires = 0 THEN
         CALL mi_0062_api.save_charge_docs(p_itm_id, l_xml);
      END IF;

      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('iRes_Code=%s, cRes_info=%s', l_res.iRes_Code, l_res.cRes_info),
         p_inf_id        => c_Inf_Id
      );

      RETURN l_res;

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

            l_res.iRes_Code := RET_FAIL;
            l_res.cRes_info := 'Error on map item: ' || TS.WhenOthersError(cFunc, ex);
         END;

         CALL mi_logger.error(
            p_logger_name   => c_Logger,
            p_message_text  => 'Ошибка в map_item_result',
            p_details_text  => SQLERRM,
            p_inf_id        => c_Inf_Id
         );

         RETURN l_res;
   END;
   $$

   -- Разбор ChargeInfo из XML ответа и загрузка в kz_charges
   CREATE PROCEDURE save_charge_docs(
      IN p_itm_id numeric,
      IN p_xml    xml
   ) AS $$
      #package
      --#private
   DECLARE
      l_cnt  integer;
      l_user varchar(30);
   BEGIN
      -- Пользователь, инициировавший загрузку
      l_user := sys_context('B21'::varchar, 'IDUsr'::varchar)::varchar(30);

      INSERT INTO xxi.kz_charges (
         ichargeid,
         csupplierbillid,
         dbilldate,
         csoi_name,
         csoi_inn,
         csoi_kpp,
         csoi_ogrn,
         csoi_account,
         csoi_bankname,
         csoi_bankbik,
         cbillfor,
         ckbk,
         cokato,
         cbi_status,
         cbi_purpose,
         cbi_taxperiod,
         cbi_taxdocnumber,
         cbi_taxdocdate,
         cpayerid,
         caltpayerid,
         cuser,
         idiscount_size,
         ddiscount_date,
         cmessageid,
         mamount,
         cpayername,
         mtotal_amount,
         cpurpose,
         crec_coracc,
         creason_info,
         idiscount_type,
         doffdate,
         coffplace,
         coffdepartment,
         cofflink,
         coffact,
         coffsupplierbillid,
         ccheckcode
      )
      SELECT
         nextval('xxi.s_kz_charges'),
         x.csupplierbillid,
         (x.dbilldate_s)::timestamptz,                      -- dbilldate = timestamp
         x.csoi_name,
         x.csoi_inn,
         x.csoi_kpp,
         x.csoi_ogrn,
         x.csoi_account,
         x.csoi_bankname,
         x.csoi_bankbik,
         x.cpurpose,                                        -- cbillfor
         x.ckbk,
         x.cokato,
         x.cbi_status,
         x.cbi_purpose,
         x.cbi_taxperiod,
         x.cbi_taxdocnumber,
         x.cbi_taxdocdate,
         x.cpayerid,
         x.cpayerid,                                        -- caltpayerid
         l_user,                                            -- cuser
         x.idiscount_size,
         (x.ddiscount_date_s)::date,
         r.correlation_id::text,                            -- cmessageid
         round(x.mamount / 100.0, 2),
         x.cpayername,
         round(x.mtotal_amount / 100.0, 2),
         x.cpurpose,
         x.crec_coracc,
         x.creason_info,
         x.idiscount_type,
         (x.doffdate_s)::timestamptz AT TIME ZONE 'Europe/Moscow',
         x.coffplace,
         x.coffdepartment,
         x.cofflink,
         x.coffact,
         x.coffsupplierbillid,
         x.ccheckcode
      FROM XMLTABLE('//ChargeInfo' PASSING p_xml
         COLUMNS
            csupplierbillid    varchar(250)  PATH '@supplierBillID',
            dbilldate_s        varchar(30)   PATH '@billDate',
            csoi_name          varchar(2000) PATH 'Payee/@name',
            csoi_inn           varchar(10)   PATH 'Payee/@inn',
            csoi_kpp           varchar(9)    PATH 'Payee/@kpp',
            csoi_ogrn          varchar(100)  PATH 'Payee/@ogrn',
            csoi_account       varchar(20)   PATH 'Payee/OrgAccount/@accountNumber',
            csoi_bankname      varchar(100)  PATH 'Payee/OrgAccount/@Bank.name',
            csoi_bankbik       varchar(9)    PATH 'Payee/OrgAccount/Bank/@bik',
            ckbk               varchar(20)   PATH '@kbk',
            cokato             varchar(11)   PATH '@oktmo',
            cbi_status         varchar(2)    PATH 'BudgetIndex/@status',
            cbi_purpose        varchar(2)    PATH 'BudgetIndex/@paytReason',
            cbi_taxperiod      varchar(10)   PATH 'BudgetIndex/@taxPeriod',
            cbi_taxdocnumber   varchar(20)   PATH 'BudgetIndex/@taxDocNumber',
            cbi_taxdocdate     varchar(10)   PATH 'BudgetIndex/@taxDocDate',
            cpayerid           varchar(25)   PATH 'Payer/@payerIdentifier',
            idiscount_size     numeric       PATH 'DiscountSize/Value',
            ddiscount_date_s   varchar(30)   PATH 'DiscountSize/Expiry',
            mamount            numeric       PATH '@amountToPay',
            cpayername         varchar(160)  PATH 'Payer/@payerName',
            mtotal_amount      numeric       PATH '@totalAmount',
            cpurpose           varchar(2000) PATH '@purpose',
            crec_coracc        varchar(25)   PATH 'Payee/OrgAccount/Bank/@correspondentBankAccount',
            creason_info       varchar(4000) PATH 'ChangeStatus/@Reason',
            idiscount_type     numeric       PATH 'DiscountFixed/DiscountSize/@MultiplierSize',
            doffdate_s         varchar(30)   PATH 'AdditionalOffense/@offenseDate',
            coffplace          varchar(255)  PATH 'AdditionalOffense/@offensePlace',
            coffdepartment     varchar(255)  PATH 'AdditionalOffense/@departmentName',
            cofflink           varchar(2000) PATH 'AdditionalOffense/@digitalLink',
            coffact            varchar(255)  PATH 'AdditionalOffense/@legalAct',
            coffsupplierbillid varchar(255)  PATH 'AdditionalOffense/@supplierBillID',
            ccheckcode         varchar(255)  PATH '@requisiteCheckCode'
      ) AS x
      JOIN xxi.mi_0062 m ON m.itm_id = p_itm_id
      JOIN xxi.mi_req  r ON r.req_id = m.req_id;

      GET DIAGNOSTICS l_cnt = ROW_COUNT;

      CALL mi_logger.variable_value(
         p_logger_name   => c_Logger,
         p_variable_name => 'kz_charges.sql%rowcount',
         p_value_text    => l_cnt::varchar,
         p_inf_id        => c_Inf_Id
      );
   END;
   $$

;

COMMENT ON SCHEMA mi_0062_api IS 'Package mi_0062_api {$Id$}'
;
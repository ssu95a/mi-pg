CREATE OR REPLACE PACKAGE mi_0202_api

   -- Инициализация пакета
   CREATE FUNCTION __init__() RETURNS void AS $$
   DECLARE
      /*
         Пакет для ведения логики MI-edo
         Модуль: Социальные счета (вид сведений 0202)
      */
      cVersion CONSTANT VARCHAR(100) := '$id: {1.1.0} {26.10.2026} Sukhotina$';

      RET_OK   CONSTANT INTEGER := 0;
      RET_FAIL CONSTANT INTEGER := -1;

      c_Inf_Id    CONSTANT NUMERIC      := 202;
      c_Fps_Check CONSTANT VARCHAR(100) := 'SMEV.202.CHECK';

      cPkg_Name CONSTANT VARCHAR(20) := 'mi_0202_api';
      c_Logger  CONSTANT VARCHAR(20) := 'mi.0202';
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
      p_message_uuid          uuid,
      p_original_request_uuid uuid,
      p_correlation_id        uuid,
      p_request_time          timestamptz
   ) RETURNS NUMERIC AS $$
      #package
      --#private
   DECLARE
      l_req_id numeric;
   BEGIN
      IF p_message_uuid IS NULL THEN
         RAISE EXCEPTION 'p_message_uuid is null';
      END IF;

      IF p_original_request_uuid IS NULL THEN
         RAISE EXCEPTION 'p_original_request_uuid is null';
      END IF;

      IF p_correlation_id IS NULL THEN
         RAISE EXCEPTION 'p_correlation_id is null';
      END IF;

      IF p_request_time IS NULL THEN
         RAISE EXCEPTION 'p_request_time is null';
      END IF;

      l_req_id := MI_request_Api.create_Request(
         p_inf_id                => c_Inf_Id,
         p_correlation_id        => p_correlation_id,
         p_original_request_uuid => p_original_request_uuid,
         p_message_uuid          => p_message_uuid,
         p_status_cd             => 0
      );

      RETURN l_req_id;
   END;
   $$

   -- Разбор одного адреса и сохранение в mi_addr и mi_p2a
   CREATE PROCEDURE save_address(
      IN p_req_id    numeric,
      IN p_itm_id    numeric,
      IN p_person_id numeric,
      IN p_addr_json jsonb,
      IN p_itype     numeric
   ) AS $$
      #package
      --#private
   DECLARE
      l_addr_id numeric;
   BEGIN
      IF p_addr_json IS NULL OR p_addr_json = 'null'::jsonb THEN
         RETURN;
      END IF;

      -- Если в адресе нет ни одного значимого поля, ничего не сохраняем
      IF coalesce(p_addr_json ->> 'fullAddress', '')           = ''
         AND coalesce(p_addr_json ->> 'postalCode', '')        = ''
         AND coalesce(p_addr_json -> 'region' ->> 'value', '') = ''
         AND coalesce(p_addr_json -> 'city'   ->> 'value', '') = ''
         AND coalesce(p_addr_json -> 'street' ->> 'value', '') = ''
      THEN
         RETURN;
      END IF;

      INSERT INTO xxi.mi_addr (
         req_id,
         itm_id,
         cpostcode,
         cregion_code,
         cregion_type,
         cregion_name,
         carea_type,
         carea_name,
         ccity_type,
         ccity_name,
         cplace_type,
         cplace_name,
         cstreet_type,
         cstreet_name,
         chouse,
         cbuild,
         capart,
         cfias_code,
         cstrct,
         cunstrct_addr
      ) VALUES (
         p_req_id,
         p_itm_id,
         nullif(p_addr_json ->> 'postalCode', ''),
         nullif(p_addr_json -> 'region' ->> 'code', ''),
         nullif(p_addr_json -> 'region' ->> 'type', ''),
         nullif(p_addr_json -> 'region' ->> 'value', ''),
         nullif(p_addr_json -> 'area'   ->> 'type', ''),
         nullif(p_addr_json -> 'area'   ->> 'value', ''),
         nullif(p_addr_json -> 'city'   ->> 'type', ''),
         nullif(p_addr_json -> 'city'   ->> 'value', ''),
         nullif(p_addr_json -> 'place'  ->> 'type', ''),
         nullif(p_addr_json -> 'place'  ->> 'value', ''),
         nullif(p_addr_json -> 'street' ->> 'type', ''),
         nullif(p_addr_json -> 'street' ->> 'value', ''),
         nullif(p_addr_json ->> 'house', ''),
         nullif(p_addr_json ->> 'building1', ''),
         nullif(p_addr_json ->> 'apartment', ''),
         nullif(p_addr_json ->> 'fiasCode', ''),
         nullif(p_addr_json ->> 'building2', ''),
         nullif(p_addr_json ->> 'fullAddress', '')
      )
      RETURNING addr_id INTO l_addr_id;

      INSERT INTO xxi.mi_p2a (
         person_id,
         addr_id,
         itype,
         dbeg_reg,
         dend_reg
      ) VALUES (
         p_person_id,
         l_addr_id,
         p_itype,
         nullif(p_addr_json ->> 'startDateRegistration', '')::date,
         nullif(p_addr_json ->> 'endDateRegistration', '')::date
      );

      CALL mi_logger.variable_value(
         p_logger_name   => c_Logger,
         p_variable_name => 'addr_id',
         p_value_text    => l_addr_id::varchar || ' (itype=' || p_itype || ')',
         p_inf_id        => c_Inf_Id
      );
   END;
   $$

   -- Создание элемента запроса с полным разбором payload
   CREATE PROCEDURE create_item(
      IN  p_req_id       numeric,
      IN  p_payload_text text,
      OUT p_itm_id       numeric,
      OUT p_ret_code     integer,
      OUT p_ret_info     varchar
   ) AS $$
      #package
   DECLARE
      l_payload        jsonb;
      l_person_json    jsonb;
      l_person_for_api jsonb;
      l_person_id      numeric;
      l_doc            jsonb;
      l_doc_type_code  varchar(20);
      l_doc_type_id    numeric;
      l_itm_id         numeric;
      l_kind           varchar(50);
      l_agreement      varchar(50);
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'create_item',
         p_message_text  => 'req_id=' || p_req_id,
         p_inf_id        => c_Inf_Id
      );

      p_itm_id   := NULL;
      p_ret_code := RET_FAIL;
      p_ret_info := NULL;

      BEGIN
         IF p_req_id IS NULL THEN
            p_ret_info := 'p_req_id is null';
            RETURN;
         END IF;

         IF p_payload_text IS NULL OR btrim(p_payload_text) = '' THEN
            p_ret_info := 'p_payload_text is null or empty';
            RETURN;
         END IF;

         l_payload := p_payload_text::jsonb;

         l_kind := l_payload ->> 'kind';

         IF l_kind IS NULL OR btrim(l_kind) = '' THEN
            p_ret_info := 'kind is null or empty in payload';
            RETURN;
         END IF;

         -- Заявитель: person или foreignPerson (структура одинаковая)
         l_person_json := coalesce(
            l_payload -> 'subjects' -> 0 -> 'person',
            l_payload -> 'subjects' -> 0 -> 'foreignPerson'
         );

         IF l_person_json IS NULL OR l_person_json = 'null'::jsonb THEN
            p_ret_info := 'person or foreignPerson not found in payload';
            RETURN;
         END IF;

         -- Документ удостоверения личности
         l_doc := l_person_json -> 'personalDoc';
         l_doc_type_code := nullif(l_doc -> 'documentType' ->> 'code', '');

         -- Определение doc_type_id по коду из справочника PUD
         IF l_doc_type_code IS NOT NULL THEN
            BEGIN
               SELECT MIN(pud.iPudId)
                 INTO l_doc_type_id
                 FROM pud
                WHERE pud.cpudCode9 = l_doc_type_code
                  AND pud.ipuduse = 0;
            EXCEPTION
               WHEN OTHERS THEN
                  l_doc_type_id := NULL;
            END;
         END IF;

         -- Формирование JSON для mi_person_api
         l_person_for_api := jsonb_build_object(
            'last_name',       nullif(l_person_json ->> 'lastName', ''),
            'first_name',      nullif(l_person_json ->> 'firstName', ''),
            'middle_name',     nullif(l_person_json ->> 'middleName', ''),
            'inn',             nullif(l_person_json ->> 'inn', ''),
            'snils',           nullif(l_person_json ->> 'snils', ''),
            'birth_date',      nullif(l_person_json ->> 'birthday', ''),
            'doc_type_id',     l_doc_type_id,
            'doc_type_code',   l_doc_type_code,
            'doc_ser',         nullif(l_doc ->> 'documentSeries', ''),
            'doc_num',         nullif(l_doc ->> 'documentNumber', ''),
            'doc_issue_date',  nullif(l_doc ->> 'documentIssueDate', ''),
            'doc_issuer_code', nullif(l_doc -> 'documentIssuer' ->> 'code', ''),
            'doc_issuer_name', nullif(l_doc -> 'documentIssuer' ->> 'name', '')
         );

         -- Создание или поиск персоны
         l_person_id := mi_person_api.get_Or_Create(
            p_inf_id   => c_Inf_Id,
            p_person_J => l_person_for_api
         );

         -- Тип продукта: Счет или Вклад
         l_agreement := l_payload -> 'subservice' -> 'anyData' -> 'Product_Type' ->> 'What_kind_agreement';

         l_itm_id := MI_request_Api.next_Itm_Id();

         INSERT INTO xxi.mi_0202 (
            itm_id,
            req_id,
            person_id,
            kind,
            order_id,
            order_timestamp,
            subservice_code,
            subservice_title,
            subservice_data,
            agreement_type,
            documents,
            payload,
            created_at
         ) VALUES (
            l_itm_id,
            p_req_id,
            l_person_id,
            l_kind,
            nullif(l_payload ->> 'orderId', '')::numeric(38),
            nullif(l_payload ->> 'orderTimestamp', '')::timestamptz,
            nullif(l_payload -> 'subservice' ->> 'code', ''),
            nullif(l_payload -> 'subservice' ->> 'title', ''),
            nullif(
               jsonb_strip_nulls(
                  jsonb_build_object(
                     'anyData',     l_payload -> 'subservice' -> 'anyData',
                     'variantData', l_payload -> 'subservice' -> 'variantData'
                  )
               ),
               '{}'::jsonb
            ),
            nullif(l_agreement, ''),
            nullif(l_payload -> 'documents', 'null'::jsonb),
            p_payload_text,
            clock_timestamp()
         );

         -- Сохранение адресов: постоянная регистрация, временная, фактический
         CALL mi_0202_api.save_address(p_req_id, l_itm_id, l_person_id, l_person_json -> 'address',                  1);
         CALL mi_0202_api.save_address(p_req_id, l_itm_id, l_person_id, l_person_json -> 'tempRegistrationAddress', 2);
         CALL mi_0202_api.save_address(p_req_id, l_itm_id, l_person_id, l_person_json -> 'factAddress',             3);

         p_itm_id   := l_itm_id;
         p_ret_code := RET_OK;

      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка в create_item',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
      END;

      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('ret_code=%s, itm_id=%s, info=%s', p_ret_code, p_itm_id, p_ret_info),
         p_inf_id        => c_Inf_Id
      );
   END;
   $$

   -- Оркестратор обработки заявления: создание запроса и элемента, затем вызов ФПЗ
   CREATE PROCEDURE apply_request(
      IN  p_message_uuid          uuid,
      IN  p_original_request_uuid uuid,
      IN  p_correlation_id        uuid,
      IN  p_request_time          timestamptz,
      IN  p_payload_text          text,
      OUT p_req_id                numeric,
      OUT p_itm_id                numeric,
      OUT p_ret_code              integer,
      OUT p_ret_info              varchar
   ) AS $$
      #package
   DECLARE
      l_req_id     numeric;
      l_itm_id     numeric;
      l_ret_code   integer;
      l_ret_info   varchar;
      l_fps_result varchar;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'apply_request',
         p_message_text  => 'message_uuid=' || p_message_uuid,
         p_inf_id        => c_Inf_Id
      );

      p_req_id   := NULL;
      p_itm_id   := NULL;
      p_ret_code := RET_FAIL;
      p_ret_info := NULL;

      IF p_message_uuid IS NULL THEN
         p_ret_info := 'p_message_uuid is null';
         RETURN;
      END IF;

      IF p_original_request_uuid IS NULL THEN
         p_ret_info := 'p_original_request_uuid is null';
         RETURN;
      END IF;

      IF p_correlation_id IS NULL THEN
         p_ret_info := 'p_correlation_id is null';
         RETURN;
      END IF;

      IF p_request_time IS NULL THEN
         p_ret_info := 'p_request_time is null';
         RETURN;
      END IF;

      IF p_payload_text IS NULL OR btrim(p_payload_text) = '' THEN
         p_ret_info := 'p_payload_text is null or empty';
         RETURN;
      END IF;

      -- Создание запроса и элемента в отдельной транзакции
      <<creation>>
      BEGIN AUTONOMOUS
         l_req_id := mi_0202_api.create_request(
            p_message_uuid          => p_message_uuid,
            p_original_request_uuid => p_original_request_uuid,
            p_correlation_id        => p_correlation_id,
            p_request_time          => p_request_time
         );

         CALL mi_0202_api.create_item(
            p_req_id       => l_req_id,
            p_payload_text => p_payload_text,
            p_itm_id       => l_itm_id,
            p_ret_code     => l_ret_code,
            p_ret_info     => l_ret_info
         );

         IF l_ret_code <> RET_OK THEN
            RAISE EXCEPTION '%', coalesce(l_ret_info, 'create_item failed');
         END IF;
      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := 'Ошибка создания запроса или элемента: ' || SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка создания запроса или элемента',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
            RETURN;
      END creation;

      p_req_id := l_req_id;
      p_itm_id := l_itm_id;

      -- Вызов ФПЗ в отдельной транзакции
      <<fps_call>>
      BEGIN AUTONOMOUS
         l_fps_result := ac.get_value2(
            cDefint  => c_Fps_Check,
            tabParam => ARRAY[l_itm_id::varchar]
         );
      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := 'Ошибка вызова ФПЗ: ' || SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка вызова ФПЗ',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
            RETURN;
      END fps_call;

      -- Разбор результата ФПЗ
      IF upper(substr(l_fps_result, 1, 2)) = 'OK' THEN
         p_ret_code := RET_OK;
         p_ret_info := l_fps_result;
      ELSE
         p_ret_code := RET_FAIL;
         p_ret_info := l_fps_result;
      END IF;

      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('ret_code=%s, req_id=%s, itm_id=%s, info=%s',
                                   p_ret_code, p_req_id, p_itm_id, p_ret_info),
         p_inf_id        => c_Inf_Id
      );
   END;
   $$

;

COMMENT ON SCHEMA MI_0202_Api IS 'Package MI_0202_Api {$Id$}'
;
CREATE OR REPLACE PACKAGE mi_0202_api

   -- Инициализация пакета
   CREATE FUNCTION __init__() RETURNS void AS $$
   DECLARE
      /*
         Пакет для ведения логики MI-edo
         Модуль: Социальные счета (вид сведений 0202)
      */
      cVersion CONSTANT VARCHAR(100) := '$id: {1.0.1} {15.10.2026} Sukhotina$';

      RET_OK   CONSTANT INTEGER := 0;
      RET_FAIL CONSTANT INTEGER := -1;

      c_Inf_Id CONSTANT NUMERIC := 202;
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
      l_payload  jsonb;
      l_person   jsonb;
      l_doc      jsonb;
      l_itm_id   numeric;
      l_kind     varchar(50);
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

         -- Разбор payload в JSON
         l_payload := p_payload_text::jsonb;

         -- Извлечение подвида документа
         l_kind := l_payload ->> 'kind';

         IF l_kind IS NULL OR btrim(l_kind) = '' THEN
            p_ret_info := 'kind is null or empty in payload';
            RETURN;
         END IF;

         -- Заявитель: либо person, либо foreignPerson (структура одинаковая?)
         l_person := coalesce(
            l_payload -> 'subjects' -> 0 -> 'person',
            l_payload -> 'subjects' -> 0 -> 'foreignPerson'
         );

         IF l_person IS NULL OR l_person = 'null'::jsonb THEN
            p_ret_info := 'person or foreignPerson not found in payload';
            RETURN;
         END IF;

         -- Основной документ удостоверения личности
         l_doc := l_person -> 'personalDoc';

         l_itm_id := MI_request_Api.next_Itm_Id();

         INSERT INTO xxi.mi_0202 (
            itm_id,
            req_id,
            kind,
            order_id,
            order_timestamp,
            subservice_code,
            subservice_title,
            subservice_mnemonic,
            subservice_data,
            documents,
            person_last_name,
            person_first_name,
            person_middle_name,
            person_inn,
            person_snils,
            person_birthday,
            doc_type_code,
            doc_type_name,
            doc_series,
            doc_number,
            doc_issuer_code,
            doc_issuer_name,
            doc_issue_date,
            payload,
            created_at
         ) VALUES (
            l_itm_id,
            p_req_id,
            l_kind,
            NULLIF(l_payload ->> 'orderId', '')::numeric(38),
            NULLIF(l_payload ->> 'orderTimestamp', '')::timestamptz,
            NULLIF(l_payload -> 'subservice' ->> 'code', ''),
            NULLIF(l_payload -> 'subservice' ->> 'title', ''),
            NULLIF(l_payload -> 'subservice' ->> 'mnemonic', ''),
            NULLIF(
               jsonb_strip_nulls(
                  jsonb_build_object(
                     'anyData',     l_payload -> 'subservice' -> 'anyData',
                     'variantData', l_payload -> 'subservice' -> 'variantData'
                  )
               ),
               '{}'::jsonb
            ),
            NULLIF(l_payload -> 'documents', 'null'::jsonb),
            NULLIF(l_person ->> 'lastName', ''),
            NULLIF(l_person ->> 'firstName', ''),
            NULLIF(l_person ->> 'middleName', ''),
            NULLIF(l_person ->> 'inn', ''),
            NULLIF(l_person ->> 'snils', ''),
            NULLIF(l_person ->> 'birthday', '')::date,
            NULLIF(l_doc -> 'documentType' ->> 'code', ''),
            NULLIF(l_doc -> 'documentType' ->> 'name', ''),
            NULLIF(l_doc ->> 'documentSeries', ''),
            NULLIF(l_doc ->> 'documentNumber', ''),
            NULLIF(l_doc -> 'documentIssuer' ->> 'code', ''),
            NULLIF(l_doc -> 'documentIssuer' ->> 'name', ''),
            NULLIF(l_doc ->> 'documentIssueDate', '')::date,
            p_payload_text,
            clock_timestamp()
         );

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

;

COMMENT ON SCHEMA MI_0202_Api IS 'Package MI_0202_Api {$Id$}'
;
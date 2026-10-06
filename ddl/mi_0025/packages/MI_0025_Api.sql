CREATE OR REPLACE PACKAGE mi_0025_api

   -- Инициализация пакета
   CREATE FUNCTION __init__() RETURNS void AS $$
   DECLARE
      cVersion CONSTANT VARCHAR(100) := '$id: {1.0.2} {26.08.2026} Sukhotina$';

      RET_OK   CONSTANT INTEGER := 0;
      RET_FAIL CONSTANT INTEGER := -1;
      c_Inf_Id CONSTANT NUMERIC := 25;

      cPkg_Name CONSTANT VARCHAR(20) := 'mi_0025_api';
   BEGIN
      RAISE DEBUG 'Package "%" - % - initialized', cPkg_Name, cVersion;
   END;
   $$

   CREATE FUNCTION Get_Version() RETURNS VARCHAR AS $$
   BEGIN
      RETURN cVersion;
   END;
   $$

   -- Процедура создания элемента запроса из XML и файла PDF
   CREATE PROCEDURE create_item(
       IN  p_xml_text              text,           -- XML запроса нотариуса
       IN  p_attach_file           bytea,          -- PDF файл документа
       IN  p_message_uuid          uuid,           -- ID сообщения из MI
       IN  p_original_request_uuid uuid,           -- ID исходного запроса из MI
       IN  p_correlation_id        uuid,           -- Корреляционный ID из MI
       IN  p_request_time          timestamptz,    -- Время запроса
       OUT p_ret_code              integer,
       OUT p_ret_info              varchar,
       OUT p_itm_id                numeric
   ) AS $$
      #package
   DECLARE
       l_req_id          numeric;
       l_itm_id          numeric;
       l_request_id      uuid;
       l_version         varchar(10);
       l_request_date    timestamptz;
       l_creditor_name   varchar(2000);
       l_debtor_name     varchar(2000);
       l_cred_id         varchar(50);
       l_cred_name       varchar(2000);
       l_n_full_name     varchar(255);
       l_n_fed_num       varchar(50);
       l_n_uivid         uuid;
       l_a_full_name     varchar(255);
       l_a_fed_num       varchar(50);
       l_a_uivid         uuid;
       l_attach_name     varchar(250);
       l_attach_hash     varchar(250);
       l_attach_hash_type varchar(10);
       l_xml_text_no_ns  text;
       l_xml             xml;
   BEGIN
       CALL mi_logger.enter_f(
           p_logger_name   => cPkg_Name,
           p_function_name => 'create_item',
           p_message_text  => 'XML length=' || length(p_xml_text),
           p_inf_id        => c_Inf_Id
       );

       p_ret_code := RET_FAIL;
       p_ret_info := NULL;
       p_itm_id := NULL;

       BEGIN
           -- Проверка обязательных входных параметров
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

           IF p_xml_text IS NULL OR btrim(p_xml_text) = '' THEN
               p_ret_info := 'p_xml_text is null or empty';
               RETURN;
           END IF;

           -- (на всякий случай) удаление объявления namespace для упрощения парсинга
           l_xml_text_no_ns := regexp_replace(p_xml_text, 'xmlns="[^"]*"', '', 'g');
           l_xml := l_xml_text_no_ns::xml;

           -- Извлечение полей из XML с помощью XMLTABLE
           SELECT
               x.RequestId,
               x.Version,
               x.RequestDate,
               x.CreditorName,
               x.DebtorName,
               x.CredId,
               x.CredName,
               x.N_FullName,
               x.N_FedNum,
               x.N_UivId,
               x.A_FullName,
               x.A_FedNum,
               x.A_UivId,
               x.AttachName,
               x.AttachHash,
               x.AttachHashType
           INTO
               l_request_id,
               l_version,
               l_request_date,
               l_creditor_name,
               l_debtor_name,
               l_cred_id,
               l_cred_name,
               l_n_full_name,
               l_n_fed_num,
               l_n_uivid,
               l_a_full_name,
               l_a_fed_num,
               l_a_uivid,
               l_attach_name,
               l_attach_hash,
               l_attach_hash_type
           FROM XMLTABLE(
               '//EisRciRequest'
               PASSING l_xml
               COLUMNS
                   RequestId       uuid           PATH 'RequestId',
                   Version         varchar(10)    PATH 'Version',
                   RequestDate     timestamptz    PATH 'RequestDate',
                   CreditorName    varchar(2000)  PATH 'CreditorName',
                   DebtorName      varchar(2000)  PATH 'DebtorName',
                   CredId          varchar(50)    PATH 'CreditInstitution/Id',
                   CredName        varchar(2000)  PATH 'CreditInstitution/Name',
                   N_FullName      varchar(255)   PATH 'Sender/Assistant/Notary/FullName',
                   N_FedNum        varchar(50)    PATH 'Sender/Assistant/Notary/FedNum',
                   N_UivId         uuid           PATH 'Sender/Assistant/Notary/UivId',
                   A_FullName      varchar(255)   PATH 'Sender/Assistant/FullName',
                   A_FedNum        varchar(50)    PATH 'Sender/Assistant/FedNum',
                   A_UivId         uuid           PATH 'Sender/Assistant/UivId',
                   AttachName      varchar(250)   PATH 'Attachments/Attachment/Name',
                   AttachHash      varchar(250)   PATH 'Attachments/Attachment/Hash',
                   AttachHashType  varchar(10)    PATH 'Attachments/Attachment/HashType'
           ) x;

           -- Проверка обязательных полей
           IF l_request_id IS NULL OR l_version IS NULL OR l_creditor_name IS NULL OR l_debtor_name IS NULL OR
              l_cred_id IS NULL OR l_cred_name IS NULL OR l_n_full_name IS NULL OR
              l_n_fed_num IS NULL OR l_n_uivid IS NULL OR
              l_attach_name IS NULL OR l_attach_hash IS NULL OR l_attach_hash_type IS NULL THEN
               p_ret_info := 'Не найдены обязательные поля в XML';
               RETURN;
           END IF;

           -- Создание запроса в mi_req с сохранением транспортных параметров
           l_req_id := MI_request_Api.create_Request(
               p_inf_id                => c_Inf_Id,
               p_correlation_id        => p_correlation_id,
               p_original_request_uuid => p_original_request_uuid,
               p_message_uuid          => p_message_uuid,
               p_status_cd             => 0
           );

           -- Получение нового идентификатора элемента
           l_itm_id := MI_request_Api.next_Itm_Id();

           INSERT INTO xxi.mi_0025 (
               itm_id,
               req_id,
               version,
               request_id,
               request_date,
               creditor_name,
               debtor_name,
               cred_id,
               cred_name,
               n_full_name,
               n_fed_num,
               n_uivid,
               a_full_name,
               a_fed_num,
               a_uivid,
               attach_name,
               attach_hash,
               attach_hash_type,
               attach_file,
               payload,
               created_at
           ) VALUES (
               l_itm_id,
               l_req_id,
               l_version,
               l_request_id,
               l_request_date,
               l_creditor_name,
               l_debtor_name,
               l_cred_id,
               l_cred_name,
               l_n_full_name,
               l_n_fed_num,
               l_n_uivid,
               l_a_full_name,
               l_a_fed_num,
               l_a_uivid,
               l_attach_name,
               l_attach_hash,
               l_attach_hash_type,
               p_attach_file,
               p_xml_text,
               clock_timestamp()
           );

           p_itm_id := l_itm_id;
           p_ret_code := RET_OK;

       EXCEPTION
           WHEN OTHERS THEN
               p_ret_info := SQLERRM;
               CALL mi_logger.error(
                   p_logger_name   => cPkg_Name,
                   p_message_text  => 'Ошибка в create_item',
                   p_details_text  => SQLERRM,
                   p_inf_id        => c_Inf_Id
               );
       END;

       CALL mi_logger.exit_f(
           p_logger_name   => cPkg_Name,
           p_message_text  => 'ret_code=' || p_ret_code || ', itm_id=' || p_itm_id,
           p_inf_id        => c_Inf_Id
       );
   END;
   $$

   -- Процедура подтверждения/отклонения запроса
   CREATE PROCEDURE update_req_status(
      IN  p_itm_id          numeric,
      IN  p_confirmed_value integer,   -- 1 = подтверждаю, 0 = не подтверждаю
      OUT p_ret_code        integer,
      OUT p_ret_info        varchar
   ) AS $$
      #package
   DECLARE
      l_cur_user_id       integer;
      l_cur_user_name     varchar(64);
      l_cur_user_position varchar(150);
      l_row_count         integer;
      l_req_id            numeric;
      l_rsp_id            numeric;
      l_to_ready_code     integer;
      l_to_ready_info     varchar;
      l_send_result       mi_resultctx.exec_result;  -- результат отправки в XXL
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => cPkg_Name,
         p_function_name => 'update_req_status',
         p_message_text  => 'itm_id=' || p_itm_id || ', confirmed_value=' || p_confirmed_value,
         p_inf_id        => c_Inf_Id
      );
   
      p_ret_code := RET_FAIL;
      p_ret_info := NULL;

      <<registration>>
      BEGIN AUTONOMOUS
   
         -- Проверка входных данных
         IF p_confirmed_value NOT IN (0,1) THEN
            p_ret_info := 'confirmed_value должен быть 0 или 1';
            EXIT registration;
         END IF;
   
         -- Получение текущего пользователя
         l_cur_user_id := sys_context('B21'::character varying, 'IDUsr'::character varying)::integer;
         IF l_cur_user_id IS NULL THEN
            p_ret_info := 'Не удалось определить текущего пользователя (sys_context B21 IDUsr)';
            EXIT registration;
         END IF;
   
         SELECT cusrname, cusrposition
            INTO l_cur_user_name, l_cur_user_position
           FROM xxi.usr
          WHERE iusrid = l_cur_user_id;
   
         IF NOT FOUND THEN
            p_ret_info := 'Пользователь с ID=' || l_cur_user_id || ' не найден';
            EXIT registration;
         END IF;
   
         -- Обновление записи mi_0025
         UPDATE xxi.mi_0025
            SET confirmed_usr_id = l_cur_user_id,
                confirmed_value  = p_confirmed_value,
                confirmed_at     = clock_timestamp(),
                confirmed_name   = l_cur_user_name,
                confirmed_post   = l_cur_user_position
          WHERE itm_id = p_itm_id
            AND EXISTS (
               SELECT 1
                 FROM xxi.mi_req r
                WHERE r.req_id = xxi.mi_0025.req_id
                  AND r.status_cd = 0
            );
   
         GET DIAGNOSTICS l_row_count = ROW_COUNT;
   
         IF l_row_count = 0 THEN
            p_ret_info := 'Запись не найдена или запрос уже обработан (статус не 0)';
            EXIT registration;
         END IF;
   
         -- Получаем req_id
         SELECT req_id INTO l_req_id
           FROM xxi.mi_0025
          WHERE itm_id = p_itm_id;
   
         -- Создаем ответ со статусом New
         l_rsp_id := MI_Response_Api.create_response(
            p_req_id      => l_req_id,
            p_itm_id      => p_itm_id,
            p_category_cd => 'SUCCESS',
            p_result_code => '0',
            p_result_info => CASE p_confirmed_value WHEN 1 THEN 'Подтверждено' ELSE 'Не подтверждено' END,
            p_payload     => jsonb_build_object(
                                'confirmed_value', p_confirmed_value,
                                'confirmed_usr_id', l_cur_user_id,
                                'confirmed_at', clock_timestamp()
                             )
         );
   
         -- Переводим ответ в статус Ready
         CALL MI_Response_Api.to_ready(
            p_rsp_id   => l_rsp_id,
            p_res_code => l_to_ready_code,
            p_res_info => l_to_ready_info
         );
   
         IF l_to_ready_code <> 0 THEN
            -- откатываем всю автономную транзакцию
            RAISE EXCEPTION 'Ошибка перевода бизнес-ответа в статус READY: %', l_to_ready_info;
         END IF;
   
         p_ret_code := RET_OK;
         p_ret_info := 'OK, updated ' || l_row_count || ' row(s), response id=' || l_rsp_id;
   
      EXCEPTION
         WHEN OTHERS THEN
            p_ret_code := RET_FAIL;
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => cPkg_Name,
               p_message_text  => 'Ошибка регистрации request/item/response. update_req_status',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id,
               p_req_id        => l_req_id,
               p_itm_id        => p_itm_id,
               p_rsp_id        => l_rsp_id
            );
      END registration; -- автономная транзакция закоммичена

      -- Отправляем ответ в XXL
      IF p_ret_code = RET_OK AND l_rsp_id IS NOT NULL THEN
   
         BEGIN
            CALL mi_mbus.send_response(l_rsp_id, l_send_result);
   
            IF NOT l_send_result.is_success THEN
               CALL mi_logger.error(
                  p_logger_name  => cPkg_Name,
                  p_message_text => 'Business response оставлен READY: ошибка отправки в XXL. update_req_status',
                  p_details_text => coalesce(l_send_result.result_info, 'неизвестная ошибка'),
                  p_inf_id       => c_Inf_Id,
                  p_req_id       => l_req_id,
                  p_itm_id       => p_itm_id,
                  p_rsp_id       => l_rsp_id
               );
               p_ret_info := p_ret_info || '; предупреждение: ошибка отправки в XXL: ' || COALESCE(l_send_result.result_info, 'неизвестная ошибка');
            END IF;
   
         EXCEPTION
            WHEN OTHERS THEN
               CALL mi_logger.error(
                  p_logger_name  => cPkg_Name,
                  p_message_text => 'Business response оставлен READY: ошибка отправки в XXL. update_req_status',
                  p_details_text => SQLERRM,
                  p_inf_id       => c_Inf_Id,
                  p_req_id       => l_req_id,
                  p_itm_id       => p_itm_id,
                  p_rsp_id       => l_rsp_id
               );
               p_ret_info := p_ret_info || '; предупреждение: ошибка отправки в XXL: ' || SQLERRM;
         END;
   
      END IF;
   
      CALL mi_logger.exit_f(
         p_logger_name   => cPkg_Name,
         p_message_text  => 'ret_code=' || p_ret_code || ', info=' || p_ret_info,
         p_inf_id        => c_Inf_Id
      );
   END;
   $$
;
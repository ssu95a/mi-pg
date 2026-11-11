CREATE OR REPLACE PACKAGE mi_request_sup

   -- Инициализация пакета
   CREATE FUNCTION __init__() RETURNS void AS $$
   DECLARE
      /*
         Пакет для ведения логики MI-edo
         Модуль: Универсальные сценарии запросов и ответов
      */
      cVersion CONSTANT VARCHAR(100) := '$id: {1.0.1} {11.11.2026} Sukhotina$';

      RET_OK   CONSTANT INTEGER := 0;
      RET_FAIL CONSTANT INTEGER := -1;

      cPkg_Name CONSTANT VARCHAR(20) := 'mi_request_sup';
      c_Logger  CONSTANT VARCHAR(20) := 'mi.req.sup';
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

   -- Универсальное создание запроса с одной позицией и опциональной отправкой ответа
   CREATE PROCEDURE apply_Request(
      IN  p_inf_id                numeric,
      IN  p_item_table            regclass,
      IN  p_message_uuid          uuid,
      IN  p_original_request_uuid uuid,
      IN  p_correlation_id        uuid,
      IN  p_request_time          timestamptz,
      IN  p_payload_text          text,
      OUT p_req_id                numeric,
      OUT p_itm_id                numeric,
      OUT p_rsp_id                numeric,
      OUT p_ret_code              int4,
      OUT p_ret_info              varchar,
      IN  p_send_response         boolean DEFAULT false,
      IN  p_response_payload      jsonb   DEFAULT NULL
   ) AS $$
      #package
   DECLARE
      l_req_id      numeric;
      l_itm_id      numeric;
      l_rsp_id      numeric;
      l_res_code    int4;
      l_res_info    varchar;
      l_send_result mi_resultctx.exec_result;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'apply_Request',
         p_message_text  => 'inf_id=' || p_inf_id ||
                            ', item_table=' || p_item_table::varchar ||
                            ', send_response=' || coalesce(p_send_response, false),
         p_inf_id        => p_inf_id
      );

      p_req_id   := NULL;
      p_itm_id   := NULL;
      p_rsp_id   := NULL;
      p_ret_code := RET_FAIL;
      p_ret_info := NULL;

      IF p_inf_id IS NULL THEN
         p_ret_info := 'p_inf_id is null';
         RETURN;
      END IF;

      IF p_item_table IS NULL THEN
         p_ret_info := 'p_item_table is null';
         RETURN;
      END IF;

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

      <<main>>
      BEGIN

         -- Создание заголовка запроса
         l_req_id := MI_request_Api.create_Request(
            p_inf_id                => p_inf_id,
            p_correlation_id        => p_correlation_id,
            p_original_request_uuid => p_original_request_uuid,
            p_message_uuid          => p_message_uuid,
            p_status_cd             => 1
         );

         -- Создание позиции в таблице, переданной вызывающей стороной
         l_itm_id := MI_request_Api.next_Itm_Id();

         EXECUTE format(
            'INSERT INTO %s (itm_id, req_id, created_at, payload, ires_code) '
            'VALUES ($1, $2, clock_timestamp(), $3, 0)',
            p_item_table
         )
         USING l_itm_id, l_req_id, p_payload_text;

         p_req_id := l_req_id;
         p_itm_id := l_itm_id;

         -- Формирование ответа при необходимости
         IF coalesce(p_send_response, false) THEN

            l_rsp_id := MI_Response_Api.create_response(
               p_req_id      => l_req_id,
               p_itm_id      => l_itm_id,
               p_category_cd => 'SUCCESS',
               p_result_code => 'OK',
               p_result_info => 'Запрос зарегистрирован',
               p_payload     => coalesce(
                                   p_response_payload,
                                   jsonb_build_object(
                                      'processed_at', clock_timestamp()
                                   )
                                )
            );

            CALL MI_Response_Api.to_ready(
               p_rsp_id   => l_rsp_id,
               p_res_code => l_res_code,
               p_res_info => l_res_info
            );

            IF l_res_code <> RET_OK THEN
               RAISE EXCEPTION 'Ошибка перевода response в READY: %',
                               coalesce(l_res_info, 'unknown error');
            END IF;

            p_rsp_id := l_rsp_id;

         END IF;

         p_ret_code := RET_OK;

      EXCEPTION
         WHEN OTHERS THEN
            p_ret_code := RET_FAIL;
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка регистрации req/item/response',
               p_details_text  => SQLERRM,
               p_inf_id        => p_inf_id,
               p_req_id        => l_req_id,
               p_itm_id        => l_itm_id,
               p_rsp_id        => l_rsp_id
            );
      END main;

      -- Отправка ответа
      IF p_ret_code = RET_OK
         AND coalesce(p_send_response, false)
         AND p_rsp_id IS NOT NULL
      THEN

         BEGIN

            CALL mi_mbus.send_response(p_rsp_id, l_send_result);

            IF NOT l_send_result.is_success THEN

               CALL mi_logger.error(
                  p_logger_name   => c_Logger,
                  p_message_text  => 'Business response оставлен READY: ошибка отправки в XXL',
                  p_details_text  => coalesce(l_send_result.result_info, 'неизвестная ошибка'),
                  p_inf_id        => p_inf_id,
                  p_req_id        => l_req_id,
                  p_itm_id        => l_itm_id,
                  p_rsp_id        => l_rsp_id
               );

            END IF;

         EXCEPTION
            WHEN OTHERS THEN

               CALL mi_logger.error(
                  p_logger_name   => c_Logger,
                  p_message_text  => 'Business response оставлен READY: исключение при отправке в XXL',
                  p_details_text  => SQLERRM,
                  p_inf_id        => p_inf_id,
                  p_req_id        => l_req_id,
                  p_itm_id        => l_itm_id,
                  p_rsp_id        => l_rsp_id
               );

         END;

      END IF;

      IF p_ret_code = RET_OK THEN
         p_ret_info := 'registered; req_id=' || l_req_id || '; itm_id=' || l_itm_id
                       || case when p_rsp_id is not null
                               then '; rsp_id=' || p_rsp_id
                               else ''
                          end;
      END IF;

      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => 'ret_code=' || p_ret_code || ', info=' || coalesce(p_ret_info, 'null'),
         p_inf_id        => p_inf_id,
         p_req_id        => l_req_id,
         p_itm_id        => l_itm_id,
         p_rsp_id        => l_rsp_id
      );

   END;
   $$

;

COMMENT ON SCHEMA mi_request_sup IS
'MI-edo. Универсальные сценарии запросов и ответов. $id: {1.0.1} {11.11.2026} Sukhotina$';
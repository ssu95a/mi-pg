CREATE OR REPLACE PACKAGE mi_0600_api

   CREATE TYPE t_schedule_entry AS (
      dow    smallint,   -- день недели (ISO: 1=Пн ... 7=Вс)
      t_from time,       -- время начала
      t_to   time        -- время окончания
   )

   -- Инициализация пакета
   CREATE FUNCTION __init__() RETURNS void AS $$
   DECLARE
      cVersion CONSTANT VARCHAR(100) := '$id: {1.2.11} {05.10.2026} Sukhotina$';

      RET_OK      CONSTANT INTEGER := 0;
      RET_FAIL    CONSTANT INTEGER := -1;
      RET_NO_DATA CONSTANT INTEGER := 1;
      RET_EXISTS  CONSTANT INTEGER := 4;
   
      cPkg_Name CONSTANT VARCHAR(20) := 'mi_0600_api';
      c_Logger  CONSTANT VARCHAR(20) := 'mi.0600';

      -- Ключи в MI_prp
      c_Sched_Key     CONSTANT VARCHAR(50) := 'MI_0600.SCHEDULE';
      c_Sched_Upd_Key CONSTANT VARCHAR(50) := 'MI_0600.SCHEDULE_UPDATED_AT';

      -- Кэш расписания
      g_sched_cache    jsonb     := NULL;
      g_sched_cache_at timestamptz := NULL;
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

   -- Создание запроса в mi_req (вызывается из Java)
   CREATE PROCEDURE create_request(
      IN  p_inf_id                numeric,
      IN  p_czip_name             varchar,
      IN  p_bzip_data             bytea,
      IN  p_izip_size             integer,
      IN  p_izip_files_count      integer,
      IN  p_file_names            varchar[],
      OUT p_req_id                numeric,
      OUT p_itm_id                numeric,
      OUT p_ret_code              integer,
      OUT p_ret_info              varchar,
      IN  p_original_request_uuid uuid    DEFAULT NULL,  -- ответчик
      IN  p_message_uuid          uuid    DEFAULT NULL,  -- ответчик
      IN  p_ctaxreq_id            varchar DEFAULT NULL,  -- ответчик
      IN  p_icreate_type          integer DEFAULT 0
   ) AS $$
      #package
   DECLARE
      l_req_id          numeric;
      l_itm_id          numeric;
      l_file_name       varchar;
      l_existing_req_id numeric;
      l_existing_itm_id numeric;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'create_request',
         p_message_text  => format('inf_id=%s, zip=%s, size=%s, files=%s',
                                   p_inf_id, p_czip_name, p_izip_size, p_izip_files_count),
         p_inf_id        => p_inf_id
      );
   
      p_req_id   := NULL;
      p_itm_id   := NULL;
      p_ret_code := RET_FAIL;
      p_ret_info := NULL;
   
      BEGIN
         IF p_inf_id IS NULL THEN
            p_ret_info := 'p_inf_id is null';
            RETURN;
         END IF;

         IF p_inf_id NOT IN (601, 602, 603, 604, 611, 612) THEN
            p_ret_info := 'Недопустимый p_inf_id: ' || p_inf_id || ' (допустимо 601, 602, 603, 604, 611, 612)';
            RETURN;
         END IF;
   
         IF p_czip_name IS NULL OR btrim(p_czip_name) = '' THEN
            p_ret_info := 'p_czip_name is null or empty';
            RETURN;
         END IF;

         -- Проверка дубликатов
         IF p_inf_id IN (601, 603, 611) THEN
            -- Инициатор: дубликат по имени архива
            SELECT h.req_id, h.itm_id
              INTO l_existing_req_id, l_existing_itm_id
              FROM xxi.mi_0600 h
             WHERE h.czip_name = p_czip_name
             LIMIT 1;

            IF FOUND THEN
               -- Обновляем архив и метаданные
               UPDATE xxi.mi_0600
                  SET bzip_data        = p_bzip_data,
                      izip_size        = p_izip_size,
                      izip_files_count = p_izip_files_count
                WHERE itm_id = l_existing_itm_id;

               -- Пересобираем имена файлов: старые удаляем, новые вставляем
               DELETE FROM xxi.mi_0600_f WHERE itm_id = l_existing_itm_id;

               IF p_file_names IS NOT NULL AND array_length(p_file_names, 1) > 0 THEN
                  FOREACH l_file_name IN ARRAY p_file_names
                  LOOP
                     IF l_file_name IS NULL OR btrim(l_file_name) = '' THEN
                        CONTINUE;
                     END IF;
                     INSERT INTO xxi.mi_0600_f (itm_id, czip_file_name)
                     VALUES (l_existing_itm_id, l_file_name);
                  END LOOP;
               END IF;

               p_req_id   := l_existing_req_id;
               p_itm_id   := l_existing_itm_id;
               p_ret_code := RET_OK;
               p_ret_info := 'Дубликат архива: возвращён существующий req_id=' || l_existing_req_id
                             || ', zip_data и имена файлов обновлены';

               CALL mi_logger.info(
                  p_logger_name   => c_Logger,
                  p_message_text  => p_ret_info,
                  p_inf_id        => p_inf_id
               );
               RETURN;
            END IF;

         ELSIF p_inf_id IN (602, 604, 612) THEN
            -- Ответчик: дубликат по original_request_uuid
            IF p_original_request_uuid IS NOT NULL THEN
               SELECT h.req_id, h.itm_id
                 INTO l_existing_req_id, l_existing_itm_id
                 FROM xxi.mi_req r
                 LEFT JOIN xxi.mi_0600 h ON h.req_id = r.req_id
                WHERE r.original_request_uuid = p_original_request_uuid
                LIMIT 1;

               IF FOUND THEN
                  p_req_id   := l_existing_req_id;
                  p_itm_id   := l_existing_itm_id;
                  p_ret_code := RET_EXISTS;
                  p_ret_info := 'Дубликат original_request_uuid: уже существует req_id=' || l_existing_req_id;

                  CALL mi_logger.info(
                     p_logger_name   => c_Logger,
                     p_message_text  => p_ret_info,
                     p_inf_id        => p_inf_id
                  );
                  RETURN;
               END IF;
            END IF;
         END IF;
   
         -- Заголовок запроса
         l_req_id := MI_request_Api.create_Request(
            p_inf_id                => p_inf_id,
            p_correlation_id        => gen_random_uuid(),
            p_original_request_uuid => p_original_request_uuid,
            p_ctaxreq_id            => p_ctaxreq_id,
            p_message_uuid          => p_message_uuid,
            p_status_cd             => 0
         );
   
         -- Элемент запроса
         l_itm_id := MI_request_Api.next_Itm_Id();
   
         INSERT INTO xxi.mi_0600 (
            itm_id,
            req_id,
            czip_name,
            bzip_data,
            izip_size,
            izip_files_count,
            icreate_type,
            created_at
         ) VALUES (
            l_itm_id,
            l_req_id,
            p_czip_name,
            p_bzip_data,
            p_izip_size,
            p_izip_files_count,
            p_icreate_type,
            clock_timestamp()
         );
   
         -- Имена файлов внутри архива
         IF p_file_names IS NOT NULL AND array_length(p_file_names, 1) > 0 THEN
            FOREACH l_file_name IN ARRAY p_file_names
            LOOP
               IF l_file_name IS NULL OR btrim(l_file_name) = '' THEN
                  CONTINUE;
               END IF;
               INSERT INTO xxi.mi_0600_f (itm_id, czip_file_name)
               VALUES (l_itm_id, l_file_name);
            END LOOP;
         END IF;
   
         p_req_id   := l_req_id;
         p_itm_id   := l_itm_id;
         p_ret_code := RET_OK;
   
      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка в create_request',
               p_details_text  => SQLERRM,
               p_inf_id        => p_inf_id
            );
      END;
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('ret_code=%s, req_id=%s, itm_id=%s, info=%s',
                                   p_ret_code, p_req_id, p_itm_id, p_ret_info),
         p_inf_id        => p_inf_id
      );
   END;
   $$
   
   -- Получение даты постановки файла в очередь на обработку в ФНС по его имени
   CREATE FUNCTION get_fns_file_inqueue_date(p_file_name varchar)
      RETURNS date AS $$
      #package
   DECLARE
      v_dsend_stamp date := NULL;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'get_fns_file_inqueue_date',
         p_message_text  => 'p_fileName = ' || p_file_name,
         p_inf_id        => NULL
      );

      IF p_file_name IS NULL OR btrim(p_file_name) = '' THEN
         CALL mi_logger.exit_f(
            p_logger_name  => c_Logger,
            p_message_text => 'p_file_name is null or empty',
            p_inf_id       => NULL
         );
         RETURN NULL;
      END IF;
   
      -- ЗАГЛУШКА: текущая системная дата
      --v_dsend_stamp := date_trunc('day', clock_timestamp());
   
      -- Поиск даты постановки по имени файла
      SELECT MAX(date_trunc('day', h.dsend_stamp))
         INTO v_dsend_stamp
         FROM xxi.mi_0600 h
         JOIN xxi.mi_0600_f f ON f.itm_id = h.itm_id
        WHERE upper(btrim(f.czip_file_name)) = upper(btrim(p_file_name));
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => 'v_dsend_stamp = ' || coalesce(v_dsend_stamp::text, '<NULL>'),
         p_inf_id        => NULL
      );

      RETURN v_dsend_stamp;
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
         p_inf_id        => NULL
      );

      CALL MI_Item_Result_Api.apply_Item_Result(
         'xxi.mi_0600'::regclass,
         'MI_0600_Api.map_Item_Result(numeric,jsonb)'::regprocedure,
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
         p_inf_id        => NULL
      );
   END;
   $$

   -- Разбор payload ответа по элементу
   CREATE FUNCTION map_item_result(p_itm_id numeric, p_payload jsonb)
      RETURNS MI_Item_Result_Api.Item_Result AS $$
      #package
   DECLARE
      cFunc         varchar := cPkg_Name || '.map_Item_Result';
      l_state       integer;
      l_message     varchar;
      l_error       varchar;
      l_dsend_stamp timestamptz;
      l_res         MI_Item_Result_Api.Item_Result;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'map_item_result',
         p_message_text  => 'itm_id=' || p_itm_id,
         p_inf_id        => NULL
      );

      -- Извлечение значений из payload ответа (формат???)
      l_state       := (p_payload ->> 'state')::integer;
      l_message     := p_payload ->> 'message';
      l_error       := p_payload ->> 'errorCode';

      -- Дата постановки в очередь СМЭВ (поле пока неизвестно, тоже на будущее)
      -- l_dsend_stamp := (p_payload ->> 'inQueueDate')::timestamptz;

      IF l_state IS NOT NULL AND l_state >= 0 THEN
         l_res.iRes_Code := l_state;
         l_res.cRes_info := l_message;
      ELSE
         l_res.iRes_Code := RET_FAIL;
         l_res.cRes_info := coalesce(l_message, 'Ошибка обработки запроса') || coalesce(' [' || l_error || ']', '');
      END IF;

      -- Обновление элемента mi_0600
      UPDATE xxi.mi_0600
         SET ires_code   = l_res.iRes_Code,
             cres_info   = l_res.cRes_info,
             tres_time   = clock_timestamp(),
             dsend_stamp = coalesce(l_dsend_stamp, dsend_stamp)
       WHERE itm_id = p_itm_id;

      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('iRes_Code=%s, cRes_info=%s', l_res.iRes_Code, l_res.cRes_info),
         p_inf_id        => NULL
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
            l_res.cRes_info := 'Error on map JSON item: ' || TS.WhenOthersError(cFunc, ex);
         END;

         CALL mi_logger.error(
            p_logger_name   => c_Logger,
            p_message_text  => 'Ошибка в map_item_result',
            p_details_text  => SQLERRM,
            p_inf_id        => NULL
         );

         RETURN l_res;
   END;
   $$
      
   CREATE PROCEDURE send_request(
      IN  p_req_id   numeric,
      OUT p_ret_code integer,
      OUT p_ret_info varchar
   ) AS $$
      #package
   DECLARE
      l_result  mi_resultctx.exec_result;
      l_status  numeric;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'send_request',
         p_message_text  => 'req_id=' || p_req_id,
         p_inf_id        => NULL
      );
   
      p_ret_code := RET_FAIL;
      p_ret_info := NULL;
   
      BEGIN
         IF p_req_id IS NULL THEN
            p_ret_info := 'p_req_id is null';
            RETURN;
         END IF;
   
         SELECT status_cd INTO l_status
           FROM xxi.mi_req
          WHERE req_id = p_req_id;
   
         IF NOT FOUND THEN
            p_ret_info := 'Запрос с req_id=' || p_req_id || ' не найден';
            RETURN;
         END IF;
   
         IF l_status IN (2, 3) THEN
            p_ret_code := RET_OK;
            p_ret_info := 'Запрос уже отправлен (status_cd=' || l_status || ')';
            RETURN;
         END IF;
   
         IF l_status = 1 THEN
            p_ret_code := RET_OK;
            p_ret_info := 'Запрос уже завершён';
            RETURN;
         END IF;
   
         -- Вызов отправки
         CALL mi_mbus.send_request(p_req_id, l_result);
         
         IF l_result.is_success THEN
            p_ret_code := RET_OK;
            p_ret_info := coalesce(l_result.result_info, 'Отправлено');
         ELSE
            p_ret_info := coalesce(l_result.result_info, 'Ошибка отправки');
         END IF;
   
         --p_ret_code := RET_OK;
         --p_ret_info := 'Отправка запроса имитирована (вызов mi_mbus.send_request закомментирован для теста)';
   
      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка в send_request',
               p_details_text  => SQLERRM,
               p_inf_id        => NULL
            );
      END;
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('ret_code=%s, info=%s', p_ret_code, p_ret_info),
         p_inf_id        => NULL
      );
   END;
   $$
   
   CREATE PROCEDURE send_response(
      IN  p_rsp_id   numeric,
      OUT p_ret_code integer,
      OUT p_ret_info varchar
   ) AS $$
      #package
   DECLARE
      l_result mi_resultctx.exec_result;
      l_status numeric;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'send_response',
         p_message_text  => 'rsp_id=' || p_rsp_id,
         p_inf_id        => NULL
      );
   
      p_ret_code := RET_FAIL;
      p_ret_info := NULL;
   
      BEGIN
         IF p_rsp_id IS NULL THEN
            p_ret_info := 'p_rsp_id is null';
            RETURN;
         END IF;
   
         SELECT status_cd INTO l_status
           FROM xxi.mi_rsp
          WHERE rsp_id = p_rsp_id;
   
         IF NOT FOUND THEN
            p_ret_info := 'Ответ с rsp_id=' || p_rsp_id || ' не найден';
            RETURN;
         END IF;
   
         IF l_status = 2 THEN
            p_ret_code := RET_OK;
            p_ret_info := 'Ответ уже отправлен';
            RETURN;
         ELSIF l_status = 0 THEN
            p_ret_info := 'Ответ ещё не готов к отправке (status_cd=0)';
            RETURN;
         END IF;
   
         -- Вызов отправки
         CALL mi_mbus.send_response(p_rsp_id, l_result);
         
         IF l_result.is_success THEN
            p_ret_code := RET_OK;
            p_ret_info := coalesce(l_result.result_info, 'Отправлено');
         ELSE
            p_ret_info := coalesce(l_result.result_info, 'Ошибка отправки');
         END IF;
   
         --p_ret_code := RET_OK;
         --p_ret_info := 'Отправка ответа имитирована (вызов mi_mbus.send_response закомментирован для теста)';
   
      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка в send_response',
               p_details_text  => SQLERRM,
               p_inf_id        => NULL
            );
      END;
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('ret_code=%s, info=%s', p_ret_code, p_ret_info),
         p_inf_id        => NULL
      );
   END;
   $$
   
   -- Чтение расписания отправки из MI_prp (с кэшированием)
   CREATE FUNCTION get_schedule() RETURNS jsonb AS $$
      #package
   DECLARE
      l_value      varchar;
      l_updated_at timestamptz;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'get_schedule',
         p_message_text  => 'Чтение расписания из MI_prp по ключу ' || c_Sched_Key,
         p_inf_id        => NULL
      );
   
      -- Читаем timestamp последнего изменения
      l_value := MI_prp.get_sys_property(c_Sched_Upd_Key, NULL);
      IF l_value IS NOT NULL AND btrim(l_value) <> '' THEN
         l_updated_at := l_value::timestamptz;
      END IF;
   
      -- Кэш актуален
      IF l_updated_at IS NOT NULL AND g_sched_cache_at IS NOT NULL
         AND l_updated_at = g_sched_cache_at AND g_sched_cache IS NOT NULL THEN
         CALL mi_logger.info(
            p_logger_name   => c_Logger,
            p_message_text  => 'Расписание взято из кэша',
            p_inf_id        => NULL
         );
         RETURN g_sched_cache;
      END IF;
   
      -- Читаем JSON
      l_value := MI_prp.get_sys_property(c_Sched_Key, '{}');
      IF l_value IS NULL OR btrim(l_value) = '' THEN
         l_value := '{}';
      END IF;
   
      g_sched_cache    := l_value::jsonb;
      g_sched_cache_at := l_updated_at;
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => 'Расписание прочитано, длина ' || length(l_value),
         p_inf_id        => NULL
      );
   
      RETURN g_sched_cache;
   
   EXCEPTION
      WHEN OTHERS THEN
         CALL mi_logger.error(
            p_logger_name   => c_Logger,
            p_message_text  => 'Ошибка чтения расписания',
            p_details_text  => SQLERRM,
            p_inf_id        => NULL
         );
         RETURN '{}'::jsonb;
   END;
   $$
   
   -- Сохранение расписания отправки в MI_prp
   CREATE PROCEDURE set_schedule(
      IN  p_entries  mi_0600_api.t_schedule_entry[],
      OUT p_ret_code integer,
      OUT p_ret_info varchar
   ) AS $$
      #package
   DECLARE
      l_json       jsonb := '{}'::jsonb;
      l_entry      mi_0600_api.t_schedule_entry;
      l_now        timestamptz := clock_timestamp();
      l_cmd_result mi_resultctx.exec_result;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'set_schedule',
         p_message_text  => 'Запись расписания в MI_prp по ключу ' || c_Sched_Key,
         p_inf_id        => NULL
      );
   
      p_ret_code := RET_FAIL;
      p_ret_info := NULL;
   
      BEGIN
         IF p_entries IS NULL OR array_length(p_entries, 1) = 0 THEN
            p_ret_info := 'p_entries is null or empty';
            RETURN;
         END IF;
   
         FOREACH l_entry IN ARRAY p_entries
         LOOP
            IF l_entry.dow IS NULL OR l_entry.dow NOT BETWEEN 1 AND 7 THEN
               p_ret_info := 'Недопустимый день недели: ' || coalesce(l_entry.dow::varchar, '<NULL>') || ' (допустимо 1..7)';
               RETURN;
            END IF;

            IF l_entry.t_from >= l_entry.t_to THEN
               p_ret_info := 't_from должно быть меньше t_to';
               RETURN;
            END IF;
   
            l_json := jsonb_set(
               l_json,
               ARRAY[l_entry.dow::text],
               jsonb_build_object(
                  'from', to_char(l_entry.t_from, 'HH24:MI'),
                  'to',   to_char(l_entry.t_to,   'HH24:MI')
               )
            );
         END LOOP;
   
         CALL MI_prp.set_sys_property(c_Sched_Key,     l_json::text);
         CALL MI_prp.set_sys_property(c_Sched_Upd_Key, l_now::text);
   
         -- Сброс кэша
         g_sched_cache    := NULL;
         g_sched_cache_at := NULL;
   
         p_ret_code := RET_OK;

         -- Уведомление MI об изменении расписания
         BEGIN
            -- По какой-то причине падает в бесконечное зависание на шаге "QUERY_RECEIVE_X cor". Причина выясняется.
            CALL mi_mbus.send_command(
               p_result     => l_cmd_result,
               p_action     => 'SCHEDULE_CHANGE_NOTIFICATION',
               p_inf_id     => 601,
               p_req_id     => NULL,
               p_parameters => '{}'::jsonb
            );

            IF NOT l_cmd_result.is_success THEN
               CALL mi_logger.error(
                  p_logger_name   => c_Logger,
                  p_message_text  => 'Уведомление MI об изменении расписания не отправлено',
                  p_details_text  => coalesce(l_cmd_result.result_code, '<NULL>') || ': ' || coalesce(l_cmd_result.result_info, '<NULL>'),
                  p_inf_id        => 601
               );
            END IF;
         EXCEPTION
            WHEN OTHERS THEN
               CALL mi_logger.error(
                  p_logger_name   => c_Logger,
                  p_message_text  => 'Исключение при уведомлении MI об изменении расписания',
                  p_details_text  => SQLERRM,
                  p_inf_id        => 601
               );
         END;
   
      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка сохранения расписания',
               p_details_text  => SQLERRM,
               p_inf_id        => NULL
            );
      END;
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('ret_code=%s, info=%s', p_ret_code, p_ret_info),
         p_inf_id        => NULL
      );
   END;
   $$
   
   CREATE PROCEDURE send_pending(
      OUT p_ret_code integer,
      OUT p_ret_info varchar
   ) AS $$
      #package
   DECLARE
      l_item       record;
      l_sub_ret    integer;
      l_sub_info   varchar;
      l_schedule   jsonb;
      l_dow        smallint;
      l_t_from     time;
      l_t_to       time;
      l_workday    integer;
      l_now_time   time;
      l_sent_req   integer := 0;
      l_failed_req integer := 0;
      l_sent_rsp   integer := 0;
      l_failed_rsp integer := 0;
      l_use_calendar boolean;
      l_use_sched    varchar;
      l_currency     varchar;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'send_pending',
         p_message_text  => 'Запуск периодической отправки',
         p_inf_id        => NULL
      );
   
      p_ret_code := RET_FAIL;
      p_ret_info := NULL;
   
      BEGIN
         -- Чтение настройки использования календаря
         l_use_sched    := MI_prp.get_Wsp_Property(600, 'USE_SCHEDULE', '0');
         l_use_calendar := mi_utils.to_bool(l_use_sched);
   
         CALL mi_logger.info(
            p_logger_name   => c_Logger,
            p_message_text  => 'USE_SCHEDULE=' || l_use_sched || ', use_calendar=' || l_use_calendar,
            p_inf_id        => NULL
         );
   
         -- Проверка наличия неотправленных запросов
         PERFORM 1 FROM xxi.mi_req r
            WHERE r.status_cd = 0 AND r.inf_id IN (601, 603, 611)
         UNION ALL
         SELECT 1 FROM xxi.mi_rsp s
            JOIN xxi.mi_req r ON r.req_id = s.req_id
            WHERE s.status_cd = 1 AND r.inf_id IN (602, 604, 612)
            LIMIT 1;
         IF NOT FOUND THEN
            CALL mi_logger.info(
               p_logger_name   => c_Logger,
               p_message_text  => 'Нет запросов в статусе 0 или ответов в статусе 1, выход из функции',
               p_inf_id        => NULL
            );
            p_ret_code := RET_OK;
            RETURN;
         END IF;
   
         -- Проверка календаря
         IF l_use_calendar THEN
            -- Валюта календаря из настроек
            l_currency := MI_prp.get_Wsp_Property(600, 'CURRENCY', NULL);
            -- pcaliso.is_workday: 0 = рабочий день, 1 = нерабочий, < 0 = нет данных (инвертировано)
            l_workday := 1 - pcaliso.is_workday(l_currency, clock_timestamp()::date);
   
            IF l_workday = 0 THEN
               CALL mi_logger.info(
                  p_logger_name   => c_Logger,
                  p_message_text  => 'Нерабочий день по календарю, отправка пропущена',
                  p_inf_id        => NULL
               );
               p_ret_code := RET_OK;
               RETURN;
            ELSIF l_workday > 1 THEN
               CALL mi_logger.info(
                  p_logger_name   => c_Logger,
                  p_message_text  => 'Нет данных в календаре, день считается рабочим',
                  p_inf_id        => NULL
               );
            END IF;
   
            -- Проверка расписания
            l_schedule := mi_0600_api.get_schedule();
            l_dow      := extract(isodow FROM clock_timestamp())::smallint;
   
            IF l_schedule ? l_dow::text THEN
               l_t_from   := (l_schedule -> l_dow::text ->> 'from')::time;
               l_t_to     := (l_schedule -> l_dow::text ->> 'to')::time;
               l_now_time := clock_timestamp()::time;
   
               IF l_t_from IS NOT NULL AND l_t_to IS NOT NULL
                  AND NOT (l_now_time BETWEEN l_t_from AND l_t_to) THEN
                  CALL mi_logger.info(
                     p_logger_name   => c_Logger,
                     p_message_text  => format('Текущее время %s вне окна %s-%s, отправка пропущена',
                                               l_now_time, l_t_from, l_t_to),
                     p_inf_id        => NULL
                  );
                  p_ret_code := RET_OK;
                  RETURN;
               END IF;
            ELSE
               CALL mi_logger.info(
                  p_logger_name   => c_Logger,
                  p_message_text  => 'Расписание для текущего дня не задано, отправка без ограничений',
                  p_inf_id        => NULL
               );
            END IF;
         END IF;
   
         -- 1. Отправка запросов-инициаторов (отдельными транзакциями)
         FOR l_item IN
            SELECT r.req_id
               FROM xxi.mi_req r
               JOIN xxi.mi_inf i ON i.inf_id = r.inf_id
            WHERE r.status_cd = 0
               AND r.inf_id IN (601, 603, 611)
               AND i.initiator_cd = -1
         LOOP
            l_sub_ret  := NULL;
            l_sub_info := NULL;
   
            BEGIN AUTONOMOUS
               CALL mi_0600_api.send_request(l_item.req_id, l_sub_ret, l_sub_info);
            EXCEPTION
               WHEN OTHERS THEN
                  l_sub_ret  := RET_FAIL;
                  l_sub_info := SQLERRM;
                  CALL mi_logger.error(
                     p_logger_name   => c_Logger,
                     p_message_text  => 'Исключение при отправке req_id=' || l_item.req_id,
                     p_details_text  => SQLERRM,
                     p_inf_id        => NULL
                  );
            END;
   
            IF l_sub_ret = RET_OK THEN
               l_sent_req := l_sent_req + 1;
            ELSE
               l_failed_req := l_failed_req + 1;
               CALL mi_logger.error(
                  p_logger_name   => c_Logger,
                  p_message_text  => 'Ошибка отправки req_id=' || l_item.req_id,
                  p_details_text  => l_sub_info,
                  p_inf_id        => NULL
               );
            END IF;
         END LOOP;
   
         -- 2. Отправка ответов (отдельными транзакциями)
         FOR l_item IN
            SELECT s.rsp_id
               FROM xxi.mi_rsp s
               JOIN xxi.mi_req r ON r.req_id = s.req_id
               JOIN xxi.mi_inf i ON i.inf_id = r.inf_id
            WHERE s.status_cd = 1
               AND r.inf_id IN (602, 604, 612)
               AND i.initiator_cd = 1
         LOOP
            l_sub_ret  := NULL;
            l_sub_info := NULL;
   
            BEGIN AUTONOMOUS
               CALL mi_0600_api.send_response(l_item.rsp_id, l_sub_ret, l_sub_info);
            EXCEPTION
               WHEN OTHERS THEN
                  l_sub_ret  := RET_FAIL;
                  l_sub_info := SQLERRM;
                  CALL mi_logger.error(
                     p_logger_name   => c_Logger,
                     p_message_text  => 'Исключение при отправке rsp_id=' || l_item.rsp_id,
                     p_details_text  => SQLERRM,
                     p_inf_id        => NULL
                  );
            END;
   
            IF l_sub_ret = RET_OK THEN
               l_sent_rsp := l_sent_rsp + 1;
            ELSE
               l_failed_rsp := l_failed_rsp + 1;
               CALL mi_logger.error(
                  p_logger_name   => c_Logger,
                  p_message_text  => 'Ошибка отправки rsp_id=' || l_item.rsp_id,
                  p_details_text  => l_sub_info,
                  p_inf_id        => NULL
               );
            END IF;
         END LOOP;
   
         CALL mi_logger.info(
            p_logger_name   => c_Logger,
            p_message_text  => format('Отправлено: запросов %s (ошибок %s), ответов %s (ошибок %s)',
                                      l_sent_req, l_failed_req, l_sent_rsp, l_failed_rsp),
            p_inf_id        => NULL
         );
   
         p_ret_code := RET_OK;
   
      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка в send_pending',
               p_details_text  => SQLERRM,
               p_inf_id        => NULL
            );
      END;
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('ret_code=%s, info=%s', p_ret_code, p_ret_info),
         p_inf_id        => NULL
      );
   END;
   $$

   -- Конфигурация расписания для внешнего микросервиса
   CREATE PROCEDURE get_schedule_config(
      OUT p_use_schedule  integer,   -- 1/0: используется ли расписание
      OUT p_is_workday    integer,   -- 1/0: рабочий ли сегодня день
      OUT p_begin_time    time,      -- время начала работы; NULL = allDay
      OUT p_end_time      time,      -- время окончания работы; NULL = allDay
      OUT p_schedule_info text,      -- JSON с расписанием на сегодня (если p_is_workday = 1)
      OUT p_resolved_date date,      -- дата, на которую сформирована конфигурация (p_on_date или системная)
      OUT p_ret_code      integer,
      OUT p_ret_info      varchar,
      IN  p_on_date       date DEFAULT NULL   -- дата, на которую запрашивается расписание
   ) AS $$
      #package
   DECLARE
      l_use_sched    varchar;
      l_workday      integer;
      l_dow          smallint;
      l_target_date  date;
      l_schedule     jsonb;
      l_day_sched    jsonb;
      l_currency     varchar;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => 'get_schedule_config',
         p_message_text  => 'Запрос конфигурации расписания, p_on_date=' || coalesce(p_on_date::text, '<NULL>'),
         p_inf_id        => NULL
      );
   
      p_use_schedule  := 0;
      p_is_workday    := NULL;
      p_begin_time    := NULL;
      p_end_time      := NULL;
      p_schedule_info := NULL; 
      p_resolved_date := NULL;  
      p_ret_code      := RET_FAIL;
      p_ret_info      := NULL;
   
      BEGIN
         -- Целевая дата: переданная или системная
         l_target_date := coalesce(p_on_date, clock_timestamp()::date);
         p_resolved_date := l_target_date;

         -- Чтение настройки использования расписания
         l_use_sched := MI_prp.get_Wsp_Property(600, 'USE_SCHEDULE', '0');
         p_use_schedule := CASE WHEN mi_utils.to_bool(l_use_sched) THEN 1 ELSE 0 END;
   
         CALL mi_logger.variable_value(
            p_logger_name   => c_Logger,
            p_variable_name => 'USE_SCHEDULE',
            p_value_text    => l_use_sched,
            p_inf_id        => NULL
         );
   
         -- Если расписание не используется, остальные параметры игнорируются
         IF p_use_schedule = 0 THEN
            p_ret_code := RET_OK;
            CALL mi_logger.exit_f(
               p_logger_name   => c_Logger,
               p_message_text  => 'Расписание не используется',
               p_inf_id        => NULL
            );
            RETURN;
         END IF;
   
         -- Валюта календаря из настроек
         l_currency := MI_prp.get_Wsp_Property(600, 'CURRENCY', NULL);
         -- pcaliso.is_workday: 0 = рабочий день, 1 = нерабочий, < 0 = нет данных (инвертировано)
         l_workday := 1 - pcaliso.is_workday(l_currency, l_target_date);
   
         -- Нет данных в календаре (< 0) считаем рабочим днем
         IF l_workday > 1 THEN
            l_workday := 1;
            CALL mi_logger.info(
               p_logger_name   => c_Logger,
               p_message_text  => 'На дату ' || l_target_date::text || ' нет данных в календаре, день считается рабочим',
               p_inf_id        => NULL
            );
         END IF;
   
         p_is_workday := l_workday;
   
         CALL mi_logger.variable_value(
            p_logger_name   => c_Logger,
            p_variable_name => 'is_workday',
            p_value_text    => l_workday::varchar,
            p_inf_id        => NULL
         );
   
         -- Если день нерабочий, расписание не формируем
         IF l_workday = 0 THEN
            p_ret_code := RET_OK;
            CALL mi_logger.exit_f(
               p_logger_name   => c_Logger,
               p_message_text  => 'Расписание не сформировано, причина: ' || l_target_date::text || ' является нерабочим днем',
               p_inf_id        => NULL
            );
            RETURN;
         END IF;
   
         -- Формирование JSON с расписанием на сегодня
         l_dow       := extract(isodow FROM l_target_date)::smallint;
         l_schedule  := mi_0600_api.get_schedule();
         l_day_sched := l_schedule -> l_dow::text;

         -- Время начала/окончания
         IF l_day_sched IS NOT NULL AND l_day_sched <> 'null'::jsonb THEN
            p_begin_time := (l_day_sched ->> 'from')::time;
            p_end_time   := (l_day_sched ->> 'to')::time;
         END IF;

         p_schedule_info := jsonb_build_object(
            'working', true,
            'allDay',  (p_begin_time IS NULL AND p_end_time IS NULL),
            'from',    to_char(p_begin_time, 'HH24:MI'),
            'to',      to_char(p_end_time,   'HH24:MI'),
            'resolvedDate', l_target_date
         )::text;

         p_ret_code := RET_OK;
   
      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка в get_schedule_config',
               p_details_text  => SQLERRM,
               p_inf_id        => NULL
            );
      END;
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('ret_code=%s, use_schedule=%s, is_workday=%s, resolved_date=%s, info=%s',
                                   p_ret_code, p_use_schedule, p_is_workday, p_resolved_date, p_ret_info),
         p_inf_id        => NULL
      );
   END;
   $$
   
   -- Установка dsend_stamp
   CREATE PROCEDURE on_request_sent(p_req_id numeric) AS $$
   BEGIN
      UPDATE xxi.mi_0600
         SET dsend_stamp = clock_timestamp()
       WHERE req_id = p_req_id
         AND dsend_stamp IS NULL;
   EXCEPTION
      WHEN OTHERS THEN
         CALL mi_logger.error(
            p_logger_name   => c_Logger,
            p_message_text  => 'Ошибка в on_request_sent для req_id=' || p_req_id,
            p_details_text  => SQLERRM,
            p_inf_id        => NULL
         );
   END;
   $$
;
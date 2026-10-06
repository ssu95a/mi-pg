CREATE OR REPLACE PACKAGE mi_0023_Api

   -- Функция инициализации пакета mi_0023_Api
   CREATE FUNCTION __init__() RETURNS void AS $$
   DECLARE
      /*
         Пакет для ведения логики СМЭВ 3.0
         Модуль: Реестр контролируемых лиц
      */
      cVersion CONSTANT VARCHAR(100) := '$id: {1.0.1} {29.07.2026} Sukhotina$';

      -- Коды возврата
      RET_OK   CONSTANT INTEGER := 0;
      RET_FAIL CONSTANT INTEGER := -1;
      RET_LOCK CONSTANT INTEGER := 3;
   
      -- Ключ для рекомендательной блокировки
      --g_lock_key CONSTANT BIGINT := hashtext('mi_rci_0023_Api');
   
      -- Глобальные переменные состояния загрузки
      g_lock_acquired  BOOLEAN := FALSE;   -- признак, что сессия удерживает lock
      g_upload_started BOOLEAN := FALSE;
      g_target_slot    CHAR(1) := NULL;   -- целевой слот ('1','2','3')
      g_lock_handle    VARCHAR(100) := NULL;   -- дескриптор блокировки от lock_proc
      g_req_id         NUMERIC(12) := NULL;

      -- Имя временной staging-таблицы
      c_Staging_Table CONSTANT VARCHAR := 'temp_rci_staging';
      c_Logger_Name   CONSTANT VARCHAR := 'mi_0023_Api';
      c_Inf_Id        CONSTANT NUMERIC := 23;
   BEGIN
      raise debug 'Package "mi_0023_Api" - % - initialized', cVersion;
   END;
   $$
  
   CREATE FUNCTION Get_Version() RETURNS VARCHAR AS $$
   BEGIN
      RETURN cVersion;
   END;
   $$
  
   -- Возвращает команду copy для загрузки CSV-файла в staging-таблицу.
   -- Параметр p_file_path – абсолютный путь к файлу на клиентской машине.
   CREATE FUNCTION get_Copy_Command(p_file_path VARCHAR) RETURNS TEXT AS $$
   BEGIN
      RETURN 'copy pg_temp.' || c_Staging_Table || ' FROM ''' || p_file_path || ''' WITH (FORMAT csv, HEADER true, DELIMITER '';'', ENCODING ''UTF8'');';
   END;
   $$
   
   CREATE FUNCTION get_Copy_Command() RETURNS TEXT AS $$
   BEGIN
      RETURN 'copy pg_temp.' || c_Staging_Table || ' FROM STDIN WITH (FORMAT csv, HEADER true, DELIMITER '';'', ENCODING ''UTF8'');';
   END;
   $$
   
   /*
   
	CREATE FUNCTION generate_variants(p_text text)
	RETURNS text[]
	LANGUAGE plpgsql
	IMMUTABLE STRICT
	AS $$
	DECLARE
		v_input       text := upper(p_text);
		v_variants    text[] := ARRAY[''];
		v_new         text[];
		ch            char;
		replacement   char;
		v             text;
	BEGIN
		FOR i IN 1..length(v_input) LOOP
			ch := substr(v_input, i, 1);
			replacement := NULL;

			-- Таблица визуально похожих букв (латиница и кириллица)
			CASE ch
				WHEN 'A' THEN replacement := 'А';
				WHEN 'А' THEN replacement := 'A';
				WHEN 'B' THEN replacement := 'В';
				WHEN 'В' THEN replacement := 'B';
				WHEN 'C' THEN replacement := 'С';
				WHEN 'С' THEN replacement := 'C';
				WHEN 'E' THEN replacement := 'Е';
				WHEN 'Е' THEN replacement := 'E';
				WHEN 'H' THEN replacement := 'Н';
				WHEN 'Н' THEN replacement := 'H';
				WHEN 'K' THEN replacement := 'К';
				WHEN 'К' THEN replacement := 'K';
				WHEN 'M' THEN replacement := 'М';
				WHEN 'М' THEN replacement := 'M';
				WHEN 'O' THEN replacement := 'О';
				WHEN 'О' THEN replacement := 'O';
				WHEN 'P' THEN replacement := 'Р';
				WHEN 'Р' THEN replacement := 'P';
				WHEN 'T' THEN replacement := 'Т';
				WHEN 'Т' THEN replacement := 'T';
				WHEN 'X' THEN replacement := 'Х';
				WHEN 'Х' THEN replacement := 'X';
				ELSE replacement := NULL;
			END CASE;

			v_new := '{}';
			IF replacement IS NOT NULL THEN
				FOREACH v IN ARRAY v_variants LOOP
					v_new := array_append(v_new, v || ch);
					v_new := array_append(v_new, v || replacement);
				END LOOP;
			ELSE
				FOREACH v IN ARRAY v_variants LOOP
					v_new := array_append(v_new, v || ch);
				END LOOP;
			END IF;
			v_variants := v_new;
		END LOOP;

	   -- Удаляем возможные дубликаты
		SELECT array_agg(DISTINCT v1) INTO v_variants FROM unnest(v_variants) AS v1;

		RETURN v_variants;
	END;
	$$
   
   */
   
   -- Регистрирует запрос (mi_req) для текущей загрузки и сохраняет req_id
   CREATE PROCEDURE apply_request(
      IN  p_message_uuid           uuid,
      IN  p_original_request_uuid  uuid,
      IN  p_correlation_id         uuid,
      IN  p_request_time           timestamptz,
      OUT p_ret_code               integer,
      OUT p_ret_info               varchar
   ) AS $$
   DECLARE
      l_req_id NUMERIC(12);
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger_Name,
         p_function_name => 'apply_request',
         p_message_text  => 'message_uuid=' || p_message_uuid,
         p_inf_id        => c_Inf_Id
      );
   
      p_ret_code := RET_FAIL;
      p_ret_info := NULL;
   
      BEGIN
         IF p_message_uuid IS NULL THEN
            p_ret_info := 'p_message_uuid is null';
            RETURN;
         END IF;
         
         IF p_request_time IS NULL THEN
            p_ret_info := 'p_request_time is null';
            RETURN;
         END IF;
         
         IF p_original_request_uuid IS NULL THEN
            p_ret_info := 'p_original_request_uuid is null';
            RETURN;
         END IF;

         l_req_id := MI_Request_Api.create_Request(
            p_inf_id                => 23::numeric,
            p_correlation_id        => p_correlation_id,
            p_original_request_uuid => p_original_request_uuid,
            p_message_uuid          => p_message_uuid,
            p_status_cd             => 1::numeric
         );
         
         g_req_id := l_req_id;
         p_ret_code := RET_OK;
         p_ret_info := 'Request registered, req_id=' || l_req_id;

      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := 'Ошибка регистрации запроса: ' || SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger_Name,
               p_message_text  => p_ret_info,
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
      END;
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger_Name,
         p_message_text  => 'ret = ' || CASE p_ret_code WHEN 0 THEN 'OK' ELSE 'FAIL' END || ', ' || p_ret_info,
         p_inf_id        => c_Inf_Id
      );
   END;
   $$
   
   -- Функции дат
   CREATE FUNCTION try_make_BirthDate(p_year VARCHAR, p_month VARCHAR, p_day VARCHAR) RETURNS DATE AS $$
   DECLARE
      l_y INTEGER;
      l_m INTEGER;
      l_d INTEGER;
   BEGIN
      IF p_year IS NULL OR p_month IS NULL OR p_day IS NULL THEN
         RETURN NULL;
      END IF;
  
      l_y := TRIM(p_year)::INTEGER;
  
      IF LOWER(TRIM(p_month)) = 'нп' THEN
         l_m := 1;
         l_d := 1;
      ELSIF LOWER(TRIM(p_day)) = 'нп' THEN
         l_m := TRIM(p_month)::INTEGER;
         l_d := 1;
      ELSE
         l_m := TRIM(p_month)::INTEGER;
         l_d := TRIM(p_day)::INTEGER;
      END IF;
  
      RETURN to_date(
         LPAD(l_y::TEXT, 4, '0') ||
         LPAD(l_m::TEXT, 2, '0') ||
         LPAD(l_d::TEXT, 2, '0'),
         'YYYYMMDD'
      );
   EXCEPTION
      WHEN OTHERS THEN
         RETURN NULL;
   END;
   $$
  
   CREATE FUNCTION try_make_DocIssueDate(p_value VARCHAR) RETURNS DATE AS $$
   DECLARE
      l_dt DATE;
   BEGIN
      IF p_value IS NULL OR TRIM(p_value) = '' THEN
         RETURN NULL;
      END IF;
  
      l_dt := to_date(TRIM(p_value), 'YYYY-MM-DD');
      RETURN l_dt;
   EXCEPTION
      WHEN OTHERS THEN
         RETURN NULL;
   END;
   $$
  
   -- Удаление первичного ключа (перед вставкой)
   CREATE PROCEDURE drop_Target_PK(p_target_slot CHAR) AS $$
   BEGIN
      CALL mi_logger.info(
         p_logger_name   => c_Logger_Name,
         p_message_text  => 'drop_Target_PK',
         p_details_text  => 'slot=' || p_target_slot,
         p_inf_id        => c_Inf_Id
      );
  
      EXECUTE 'ALTER TABLE xxi.mi_rci_' || p_target_slot || ' DROP CONSTRAINT IF EXISTS pk_mi_rci_' || p_target_slot;
      EXECUTE 'ALTER TABLE xxi.mi_rci_' || p_target_slot || ' ALTER COLUMN cureg_id DROP NOT NULL';
   END;
   $$
  
   -- Создание первичного ключа (после вставки)
   CREATE PROCEDURE create_Target_PK(p_target_slot CHAR) AS $$
   DECLARE
      l_nNullRows INTEGER;
      l_dup_info  VARCHAR(4000);
   BEGIN
      CALL mi_logger.info(
         p_logger_name   => c_Logger_Name,
         p_message_text  => 'create_Target_PK',
         p_details_text  => 'slot=' || p_target_slot,
         p_inf_id        => c_Inf_Id
      );

      -- Проверка на NULL в cureg_id
      EXECUTE 'SELECT count(*) FROM xxi.mi_rci_' || p_target_slot || ' WHERE cureg_id IS NULL' INTO l_nNullRows;
      IF l_nNullRows > 0 THEN
         RAISE EXCEPTION 'Невозможно создать первичный ключ: столбец cureg_id содержит NULL (найдено %)', l_nNullRows;
      END IF;
  
      -- Проверка на дубликаты
      l_dup_info := mi_0023_Api.get_Duplicate_Cureg_Info(p_target_slot);
      IF l_dup_info IS NOT NULL THEN
         RAISE EXCEPTION 'Обнаружены дубли по cureg_id. Примеры: %', l_dup_info;
      END IF;
  
      EXECUTE 'ALTER TABLE xxi.mi_rci_' || p_target_slot || ' ADD CONSTRAINT pk_mi_rci_' || p_target_slot || ' PRIMARY KEY (cureg_id)';
   END;
   $$
  
   -- Удаление индекса (перед вставкой)
   CREATE PROCEDURE drop_Target_Index(p_target_slot CHAR) AS $$
   BEGIN
      CALL mi_logger.info(
         p_logger_name   => c_Logger_Name,
         p_message_text  => 'drop_Target_Index',
         p_details_text  => 'slot=' || p_target_slot,
         p_inf_id        => c_Inf_Id
      );
  
      EXECUTE 'DROP INDEX IF EXISTS xxi.ix_mi_rci_' || p_target_slot || '_cdoc_raw';
   END;
   $$
  
   -- Создание индекса (после вставки)
   CREATE PROCEDURE create_Target_Index(p_target_slot CHAR) AS $$
   BEGIN
      CALL mi_logger.info(
         p_logger_name   => c_Logger_Name,
         p_message_text  => 'create_Target_Index',
         p_details_text  => 'slot=' || p_target_slot,
         p_inf_id        => c_Inf_Id
      );
  
      EXECUTE 'CREATE INDEX IF NOT EXISTS ix_mi_rci_' || p_target_slot || '_cdoc_raw ON xxi.mi_rci_' || p_target_slot || ' (cdoc_raw)';
   END;
   $$
  
   -- Начало загрузки: создаёт или обновляет управляющую запись, устанавливая статус 'LOADING' и переданный этап.
   -- Важно! Автономная транзакция!
   CREATE PROCEDURE set_Loading_At(p_stage VARCHAR) AS $$
   BEGIN
      AUTONOMOUS
      BEGIN
         -- Замена Merge: если запись с ctrl_id=1 существует - обновить, иначе - новую с активным слотом '1'.
         INSERT INTO xxi."MI_RCI_CTRL" (
            ctrl_id,
            active_slot,
            status,
            stage,
            started_at,
            stage_started_at,
            finished_at,
            last_error,
            last_loaded_rows
         ) VALUES (
            1,
            '1',
            'LOADING',
            p_stage,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP,
            NULL,
            NULL,
            NULL
         )
         ON CONFLICT (ctrl_id) DO UPDATE SET
            status           = 'LOADING',
            stage            = p_stage,
            started_at       = CURRENT_TIMESTAMP,
            stage_started_at = CURRENT_TIMESTAMP,
            finished_at      = NULL,
            last_error       = NULL,
            last_loaded_rows = NULL;
  
      EXCEPTION
         WHEN OTHERS THEN
            CALL mi_logger.error(
               p_logger_name   => c_Logger_Name,
               p_message_text  => 'Ошибка set_Loading_At',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
      END;
   END;
   $$
  
   -- Смена этапа загрузки: обновляет статус и время начала этапа.
   -- Важно! Автономная транзакция!
   CREATE PROCEDURE set_Stage_At(p_stage VARCHAR) AS $$
   BEGIN
      AUTONOMOUS
      BEGIN
         UPDATE xxi."MI_RCI_CTRL"
            SET status          = 'LOADING',
               stage            = p_stage,
               stage_started_at = CURRENT_TIMESTAMP
          WHERE ctrl_id = 1;
  
      EXCEPTION
         WHEN OTHERS THEN
            CALL mi_logger.error(
               p_logger_name   => c_Logger_Name,
               p_message_text  => 'Ошибка set_Stage_At',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
      END;
   END;
   $$
  
   -- Успешное завершение загрузки: фиксирует активный слот, количество загруженных строк, сбрасывает статус и ошибки.
   -- Важно! Автономная транзакция!
   CREATE PROCEDURE set_Ok_At(p_active_slot CHAR, p_rows INTEGER) AS $$
   BEGIN
      AUTONOMOUS
      BEGIN
         UPDATE xxi."MI_RCI_CTRL"
            SET active_slot     = p_active_slot,
               status           = 'OK',
               stage            = NULL,
               stage_started_at = NULL,
               finished_at      = CURRENT_TIMESTAMP,
               last_error       = NULL,
               last_loaded_rows = p_rows
          WHERE ctrl_id = 1;
  
      EXCEPTION
         WHEN OTHERS THEN
            CALL mi_logger.error(
               p_logger_name   => c_Logger_Name,
               p_message_text  => 'Ошибка set_Ok_At',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
      END;
   END;
   $$
  
   -- Ошибка загрузки: устанавливает статус 'FAIL', сохраняет текст ошибки (обрезанный до 4000 символов).
   -- Важно! Автономная транзакция!
   CREATE PROCEDURE set_Fail_At(p_error VARCHAR) AS $$
   BEGIN
      AUTONOMOUS
      BEGIN
         -- Также замена Merge
         INSERT INTO xxi."MI_RCI_CTRL" (
            ctrl_id,
            active_slot,
            status,
            stage,
            started_at,
            stage_started_at,
            finished_at,
            last_error,
            last_loaded_rows
         ) VALUES (
            1,
            '1',
            'FAIL',
            NULL,
            NULL,
            NULL,
            CURRENT_TIMESTAMP,
            substring(p_error, 1, 4000),
            NULL
         )
         ON CONFLICT (ctrl_id) DO UPDATE SET
            status      = 'FAIL',
            finished_at = CURRENT_TIMESTAMP,
            last_error  = substring(p_error, 1, 4000);
  
      EXCEPTION
         WHEN OTHERS THEN
            CALL mi_logger.error(
               p_logger_name   => c_Logger_Name,
               p_message_text  => 'Ошибка set_Fail_At',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
      END;
   END;
   $$
   
   -- Синхронизация связей реестра с клиентами CUS по указанному слоту.
   CREATE PROCEDURE sync_Cus_With_Target(
      p_target_slot   IN  CHAR,
      p_unlink_only   IN  BOOLEAN,
      OUT p_unlink_count  INTEGER,
      OUT p_link_count    INTEGER
   ) AS $$
   DECLARE
      l_table        TEXT;
      l_cureg_ids    CHAR(36)[];
      l_icusnums     BIGINT[];
      l_sql          TEXT;
      l_gcs_removed  INTEGER := 0;
      l_gcs_inserted INTEGER := 0;
   BEGIN
      p_unlink_count := 0;
      p_link_count   := 0;
  
      l_table := 'xxi.mi_rci_' || p_target_slot;
  
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger_Name,
         p_function_name => 'sync_Cus_With_Target',
         p_message_text  => 'slot=' || p_target_slot || ', unlink_only=' || p_unlink_only::TEXT,
         p_inf_id        => c_Inf_Id
      );
  
      -- 1. Отвязка клиентов (unlink)
      CALL mi_logger.info(
         p_logger_name   => c_Logger_Name,
         p_message_text  => 'CUS unlink',
         p_details_text  => 'Удаление невалидных связей из mi_rci_cus',
         p_inf_id        => c_Inf_Id
      );
  
      -- Собираем невалидные пары (cureg_id, icusnum) в массивы
      l_sql := 'SELECT array_agg(x.cureg_id), array_agg(x.icusnum)
              FROM xxi.mi_rci_cus x
             WHERE NOT EXISTS (
                  SELECT 1
                   FROM ' || l_table || ' r
                   JOIN XXI.CUS_DOCUM d ON r.cdoc_raw = d.DOCSERNUM
                   JOIN XXI."CUS" c ON c.ICUSNUM = d.ICUSNUM
                  WHERE r.cureg_id = x.cureg_id
                    AND d.ICUSNUM  = x.icusnum
                    AND (d.DOC_PERIOD IS NULL OR d.DOC_PERIOD >= CURRENT_DATE)
                    AND (d.DOC_DATE IS NULL OR r.ddoc_date IS NULL
                        OR d.DOC_DATE = r.ddoc_date)
                    AND (r.dbth IS NULL OR c.DCUSBIRTHDAY IS NULL
                        OR (r.ipr_dbth IS NULL AND r.dbth = c.DCUSBIRTHDAY)
                        OR (r.ipr_dbth = 1 AND to_char(r.dbth, ''YYYY'') = to_char(c.DCUSBIRTHDAY, ''YYYY''))
                        OR (r.ipr_dbth = 2 AND to_char(r.dbth, ''MMYYYY'') = to_char(c.DCUSBIRTHDAY, ''MMYYYY''))
                       )
                 )';
      EXECUTE l_sql INTO l_cureg_ids, l_icusnums;
  
      -- Физическое удаление из mi_rci_cus
      IF l_cureg_ids IS NOT NULL AND array_length(l_cureg_ids, 1) > 0 THEN
         DELETE FROM xxi.mi_rci_cus
          WHERE (cureg_id, icusnum) IN (SELECT unnest(l_cureg_ids), unnest(l_icusnums));
         GET DIAGNOSTICS p_unlink_count = ROW_COUNT;
      ELSE
         p_unlink_count := 0;
      END IF;
  
      CALL mi_logger.variable_value(
         p_logger_name   => c_Logger_Name,
         p_variable_name => 'unlink_count',
         p_value_text    => p_unlink_count::TEXT,
         p_inf_id        => c_Inf_Id
      );
  
      -- Снимаем GCS только у тех клиентов, у которых не осталось ни одной записи в mi_rci_cus после удаления
      IF l_icusnums IS NOT NULL AND array_length(l_icusnums, 1) > 0 THEN
         DELETE FROM XXI.GCS
          WHERE IGCSCAT = 18
            AND IGCSNUM = 11
            AND IGCSCUS = ANY(l_icusnums)
            AND NOT EXISTS (SELECT 1 FROM xxi.mi_rci_cus WHERE icusnum = IGCSCUS);
         GET DIAGNOSTICS l_gcs_removed = ROW_COUNT;
         CALL mi_logger.variable_value(
            p_logger_name   => c_Logger_Name,
            p_variable_name => 'cus_gcs_removed',
            p_value_text    => l_gcs_removed::TEXT,
            p_inf_id        => c_Inf_Id
         );
      END IF;
  
      -- Если только отвязка – завершаем
      IF p_unlink_only THEN
         CALL mi_logger.info(
            p_logger_name   => c_Logger_Name,
            p_message_text  => 'unlink_Only режим',
            p_details_text  => 'Только отвязка клиентов',
            p_inf_id        => c_Inf_Id
         );
         RETURN;
      END IF;
  
      -- 2. Привязка клиентов (link)
      CALL mi_logger.info(
         p_logger_name   => c_Logger_Name,
         p_message_text  => 'CUS link',
         p_details_text  => 'Привязка клиентов к данным нового слота',
         p_inf_id        => c_Inf_Id
      );
  
      l_sql := 'INSERT INTO xxi.mi_rci_cus (cureg_id, icusnum)
         SELECT r.cureg_id, d.ICUSNUM
           FROM ' || l_table || ' r
           JOIN XXI.CUS_DOCUM d ON r.cdoc_raw = d.DOCSERNUM
           JOIN XXI."CUS" c ON c.ICUSNUM = d.ICUSNUM
          WHERE (d.DOC_PERIOD IS NULL OR d.DOC_PERIOD >= CURRENT_DATE)
            AND (d.DOC_DATE IS NULL OR r.ddoc_date IS NULL
               OR d.DOC_DATE = r.ddoc_date)
            AND NOT EXISTS (
               SELECT 1 FROM xxi.mi_rci_cus x
                WHERE x.cureg_id = r.cureg_id AND x.icusnum = d.ICUSNUM
               )
            AND (r.dbth IS NULL OR c.DCUSBIRTHDAY IS NULL
               OR (r.ipr_dbth IS NULL AND r.dbth = c.DCUSBIRTHDAY)
               OR (r.ipr_dbth = 1 AND to_char(r.dbth, ''YYYY'') = to_char(c.DCUSBIRTHDAY, ''YYYY''))
               OR (r.ipr_dbth = 2 AND to_char(r.dbth, ''MMYYYY'') = to_char(c.DCUSBIRTHDAY, ''MMYYYY''))
               )';
      EXECUTE l_sql;
      GET DIAGNOSTICS p_link_count = ROW_COUNT;
      CALL mi_logger.variable_value(
         p_logger_name   => c_Logger_Name,
         p_variable_name => 'link_count',
         p_value_text    => p_link_count::TEXT,
         p_inf_id        => c_Inf_Id
      );
  
      -- 3. Проставка GCS для новых клиентов в реестре
      IF p_link_count > 0 THEN
         INSERT INTO XXI.GCS (IGCSCUS, IGCSCAT, IGCSNUM)
         SELECT DISTINCT c.icusnum, 18, 11
           FROM xxi.mi_rci_cus c
          WHERE NOT EXISTS (
               SELECT 1 FROM XXI.GCS x
               WHERE x.IGCSCUS = c.icusnum
                 AND x.IGCSCAT = 18
                 AND x.IGCSNUM = 11
               );
         GET DIAGNOSTICS l_gcs_inserted = ROW_COUNT;
         CALL mi_logger.variable_value(
            p_logger_name   => c_Logger_Name,
            p_variable_name => 'cus_gcs_inserted',
            p_value_text    => l_gcs_inserted::TEXT,
            p_inf_id        => c_Inf_Id
         );
      END IF;
  
   EXCEPTION
      WHEN OTHERS THEN
         RAISE;
   END;
   $$
  
   -- Ручная синхронизация CUS по активному слоту.
   CREATE FUNCTION sync_With_Cus()
   RETURNS TABLE (ret_code INTEGER, result_info VARCHAR) AS $$
   DECLARE
      l_active_slot CHAR(1);
      l_nUnl_Count  INTEGER := 0;
      l_nLnk_Count  INTEGER := 0;
      l_lock_ret    INTEGER;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger_Name,
         p_function_name => 'sync_With_Cus',
         p_message_text  => 'sync_With_Cus at ' || to_char(CURRENT_TIMESTAMP, 'DD.MM.YYYY HH24:MI:SS'),
         p_inf_id        => c_Inf_Id
      );
  
      -- 1. Блокировка (та же, что и у загрузки)
      IF g_lock_acquired THEN
         ret_code := RET_LOCK;
         result_info := 'В данный момент идет загрузка/синхронизация. Sync недоступен.';
         CALL mi_logger.error(
            p_logger_name   => c_Logger_Name,
            p_message_text  => result_info,
            p_inf_id        => c_Inf_Id
         );
         RETURN NEXT;
         RETURN;
      END IF;

      /*  
      IF NOT pg_try_advisory_lock(g_lock_key) THEN
         ret_code := RET_LOCK;
         result_info := 'В данный момент идет загрузка/синхронизация. Sync недоступен.';
         CALL mi_logger.error(
            p_logger_name   => c_Logger_Name,
            p_message_text  => result_info,
            p_inf_id        => c_Inf_Id
         );
         RETURN NEXT;
         RETURN;
      END IF;
      */

      DECLARE
         l_ret_info   VARCHAR(4000);
      BEGIN
         CALL mi_utils.lock_proc(
            lockname          => 'mi_rci_0023_Api',
            release_on_commit => FALSE,
            locktimeout       => 0,
            ret_code          => l_lock_ret,
            ret_info          => l_ret_info,
            lock_handle       => g_lock_handle
         );
      END;
   
      IF l_lock_ret <> RET_OK THEN
         IF l_lock_ret = 1 THEN
            ret_code := RET_LOCK;
            result_info := 'В данный момент идет загрузка/синхронизация. Sync недоступен.';
         ELSE
            ret_code := RET_FAIL;
            result_info := 'Ошибка при получении блокировки: ' || COALESCE(l_ret_info, 'неизвестная ошибка');
         END IF;
   
         CALL mi_logger.error(
            p_logger_name   => c_Logger_Name,
            p_message_text  => result_info,
            p_inf_id        => c_Inf_Id,
            p_action_cd     => 'error'
         );
         RETURN NEXT;
         RETURN;
      END IF;
   
      g_lock_acquired := TRUE;
  
      -- 2. Определяем активный слот
      BEGIN
         SELECT active_slot
           INTO l_active_slot
           FROM xxi."MI_RCI_CTRL"
          WHERE ctrl_id = 1;
  
         IF NOT FOUND THEN
            ret_code := RET_FAIL;
            result_info := 'Не найдена управляющая запись MI_RCI_CTRL';
            CALL mi_logger.error(
               p_logger_name   => c_Logger_Name,
               p_message_text  => result_info,
               p_inf_id        => c_Inf_Id
            );
            --PERFORM pg_advisory_unlock(g_lock_key);
            g_lock_acquired := FALSE;
            RETURN NEXT;
            RETURN;
         END IF;
      EXCEPTION
         WHEN OTHERS THEN
            ret_code := RET_FAIL;
            result_info := 'Ошибка чтения активного слота: ' || SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger_Name,
               p_message_text  => result_info,
               p_inf_id        => c_Inf_Id
            );
            --PERFORM pg_advisory_unlock(g_lock_key);
            g_lock_acquired := FALSE;
            RETURN NEXT;
            RETURN;
      END;
  
      -- 3. Полная синхронизация (unlink + link)
      BEGIN
         CALL mi_0023_Api.sync_Cus_With_Target(
            p_target_slot   => l_active_slot,
            p_unlink_only   => FALSE,
            p_unlink_count  => l_nUnl_Count,
            p_link_count    => l_nLnk_Count
         );
  
         ret_code := RET_OK;
         result_info := 'Ручная CUS синхронизация завершена. ' ||
                        'Привязано: ' || l_nLnk_Count || ', ' ||
                        'Отвязано: ' || l_nUnl_Count;
  
      EXCEPTION
         WHEN OTHERS THEN
            ret_code := RET_FAIL;
            result_info := 'Ошибка синхронизации CUS: ' || SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger_Name,
               p_message_text  => 'sync_With_Cus error',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
      END;
  
      -- 4. Освобождаем блокировку и сбрасываем состояние
      --PERFORM pg_advisory_unlock(g_lock_key);
      g_lock_acquired := FALSE;
  
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger_Name,
         p_message_text  => 'ret = ' || CASE ret_code WHEN 0 THEN 'OK' WHEN -1 THEN 'FAIL' WHEN 3 THEN 'LOCK' ELSE ret_code::TEXT END || ', ' || result_info,
         p_inf_id        => c_Inf_Id
      );
  
      RETURN NEXT;
   END;
   $$
   
   -- Инициализация загрузки: блокировка, подготовка окружения, переход в режим приёма CSV.
   CREATE PROCEDURE before_Load(OUT p_ret_code INTEGER, OUT p_ret_info VARCHAR) AS $$
   DECLARE
      l_ret         INTEGER := RET_FAIL;
      l_active_slot CHAR(1);
      l_target_slot CHAR(1);
      l_err_msg     VARCHAR(4000);
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger_Name,
         p_function_name => 'before_Load',
         p_message_text  => 'before_Load at ' || to_char(CURRENT_TIMESTAMP, 'DD.MM.YYYY HH24:MI:SS'),
         p_inf_id        => c_Inf_Id
      );
  
      BEGIN
         -- 1. Блокировка через Advisory Lock
         -- Проверяем, не захвачена ли уже блокировка этой сессией
         IF g_lock_acquired THEN
            RAISE EXCEPTION 'Resource busy' USING ERRCODE = 'P0002';
         END IF;
         --
         --CALL mi_logger.info(
         --   p_logger_name   => c_Logger_Name,
         --   p_message_text  => 'Блокировка для загрузки данных',
         --   p_details_text  => 'pg_try_advisory_lock( key=' || g_lock_key::text || ' )',
         --   p_inf_id        => c_Inf_Id
         --);
         --
         --IF pg_try_advisory_lock(g_lock_key) THEN
         --   g_lock_acquired := TRUE;
         --   l_ret := RET_OK;
         --ELSE
         --   l_ret := 1;   -- имитация занятости
         --END IF;

         -- Новая блокировка (результат в l_ret)
         DECLARE
            l_ret_info   VARCHAR(4000);
         BEGIN
            CALL mi_utils.lock_proc(
               lockname          => 'mi_rci_0023_Api',
               release_on_commit => FALSE,
               locktimeout       => 0,
               ret_code          => l_ret,
               ret_info          => l_ret_info,
               lock_handle       => g_lock_handle
            );

            CALL mi_logger.info(
               p_logger_name   => c_Logger_Name,
               p_message_text  => 'Блокировка для загрузки данных',
               p_details_text  => 'mi_utils.lock_proc( key=' || g_lock_handle::text || ' )',
               p_inf_id        => c_Inf_Id
            );
         END;
   
         -- Обработка результата блокировки
         IF l_ret <> RET_OK THEN
            IF l_ret = 1 THEN
               RAISE EXCEPTION 'Resource busy' USING ERRCODE = 'P0002';
            ELSE
               RAISE EXCEPTION 'Bad Data' USING ERRCODE = 'P0003';
            END IF;
         END IF;
   
         g_lock_acquired := TRUE;
         l_ret := RET_FAIL;   -- сбрасываем для дальнейших операций
  
         -- 2. Инициализируем управляющую запись
         CALL mi_0023_Api.set_Loading_At('PREPARE');
  
         -- 3. Создаём временную staging-таблицу
         CALL mi_0023_Api.set_Stage_At('CREATE_STAGING');
  
         EXECUTE 'DROP TABLE IF EXISTS pg_temp.' || c_Staging_Table;
         EXECUTE 'CREATE TEMP TABLE ' || c_Staging_Table || ' (
            UniqueRegistryID   VARCHAR(36),
            DigitalProfileID   VARCHAR(50),
            Day                VARCHAR(4),
            Month              VARCHAR(20),
            Year               VARCHAR(20),
            DocumentID         VARCHAR(100),
            DocumentIssueDate  VARCHAR(10)
         )';
  
         -- 4. Определяем слоты
         CALL mi_0023_Api.set_Stage_At('DEF_SLOT');
  
         SELECT active_slot
           INTO l_active_slot
           FROM xxi."MI_RCI_CTRL"
          WHERE ctrl_id = 1;
  
         IF NOT FOUND THEN
            l_active_slot := '1';
         END IF;
  
         -- Циклический выбор следующего слота: 1-2-3-1
         l_target_slot := CASE l_active_slot
                        WHEN '1' THEN '2'
                        WHEN '2' THEN '3'
                        WHEN '3' THEN '1'
            END;
  
         g_target_slot := l_target_slot;
         g_upload_started := TRUE;
  
         -- 5. Переходим в режим ожидания COPY
         CALL mi_0023_Api.set_Stage_At('STAGING_READY');
  
         l_ret := RET_OK;
  
      EXCEPTION
         WHEN SQLSTATE 'P0003' THEN
            NULL;
  
         WHEN SQLSTATE 'P0002' THEN
            l_ret := RET_LOCK;
            CALL mi_logger.error(
               p_logger_name   => c_Logger_Name,
               p_message_text  => 'В данный момент уже идет загрузка данных SM_RCI.',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
  
         WHEN OTHERS THEN
            l_err_msg := COALESCE(SQLERRM, 'Ошибка before_Load. см log');
            CALL mi_logger.error(
               p_logger_name   => c_Logger_Name,
               p_message_text  => 'before_Load exception',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
            CALL mi_0023_Api.set_Fail_At(l_err_msg);
      END;
  
      IF l_ret <> RET_OK THEN
         g_upload_started := FALSE;
         g_target_slot    := NULL;
  
         -- Удаляем staging-таблицу, если она была создана
         EXECUTE 'DROP TABLE IF EXISTS pg_temp.' || c_Staging_Table;
  
         IF g_lock_acquired THEN
         --   PERFORM pg_advisory_unlock(g_lock_key);
            g_lock_acquired := FALSE;
         END IF;
      END IF;
  
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger_Name,
         p_message_text  => 'ret = ' || CASE l_ret WHEN 0 THEN 'OK' WHEN -1 THEN 'FAIL' WHEN 3 THEN 'LOCK' ELSE l_ret::TEXT END,
         p_inf_id        => c_Inf_Id
      );
  
      p_ret_code := l_ret;
      p_ret_info := CASE
          WHEN l_ret = RET_OK THEN NULL
          WHEN l_ret = RET_LOCK THEN 'В данный момент уже идет загрузка данных SM_RCI.'
          ELSE l_err_msg
      END;
      RETURN;
   END;
   $$
  
   -- Аварийное завершение загрузки.
   -- Вызывается из Java-приложения. Освобождает блокировку, сбрасывает состояние,
   -- фиксирует статус FAIL в MI_RCI_CTRL (если ещё не зафиксирован).
   CREATE PROCEDURE abort_Load(OUT p_ret_code INTEGER, OUT p_ret_info VARCHAR, IN p_error VARCHAR DEFAULT 'Загрузка аварийно прервана') AS $$
   DECLARE
      l_status     xxi."MI_RCI_CTRL".status%TYPE;
      l_last_error  xxi."MI_RCI_CTRL".last_error%TYPE;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger_Name,
         p_function_name => 'abort_Load',
         p_inf_id        => c_Inf_Id
      );
  
      -- 2. Устанавливаем статус FAIL, если его ещё нет, с непустой ошибкой
      BEGIN
         SELECT status, last_error
           INTO l_status, l_last_error
           FROM xxi."MI_RCI_CTRL"
          WHERE ctrl_id = 1;
  
         IF NOT (l_status = 'FAIL' AND l_last_error IS NOT NULL AND TRIM(l_last_error) <> '') THEN
            CALL mi_0023_Api.set_Fail_At(COALESCE(p_error, 'Загрузка аварийно прервана'));
         END IF;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            CALL mi_0023_Api.set_Fail_At(COALESCE(p_error, 'Загрузка аварийно прервана'));
         WHEN OTHERS THEN
            CALL mi_logger.error(
               p_logger_name   => c_Logger_Name,
               p_message_text  => 'Ошибка set_Fail_At в abort_Load',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
      END;
  
      -- 3. Очистка состояния (статус FAIL уже установлен, если нужно)
      CALL mi_0023_Api.cleanup(RET_OK, NULL);
  
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger_Name,
         p_message_text  => 'ret = OK',
         p_inf_id        => c_Inf_Id
      );
  
      p_ret_code := RET_OK;
      p_ret_info := NULL;
      RETURN;
  
   EXCEPTION
      WHEN OTHERS THEN
         -- крайний случай: даже при ошибке сброса пытаемся всё очистить
         BEGIN
            g_upload_started := FALSE;
            g_target_slot   := NULL;
            g_lock_acquired  := FALSE;
            EXECUTE 'DROP TABLE IF EXISTS pg_temp.' || c_Staging_Table;
            --PERFORM pg_advisory_unlock(g_lock_key);
         EXCEPTION WHEN OTHERS THEN NULL;
         END;
  
         p_ret_code := RET_FAIL;
         p_ret_info := SQLERRM;
         RETURN;
   END;
   $$
   
     -- Получить набор дублирующих CUREG_ID (первые 20) для диагностики ошибки PK.
   CREATE FUNCTION get_Duplicate_Cureg_Info(p_target_slot CHAR) RETURNS VARCHAR AS $$
   DECLARE
      l_res VARCHAR(4000);
   BEGIN
      EXECUTE 'SELECT STRING_AGG(cureg_id, '','' ORDER BY cureg_id)
               FROM (
                   SELECT cureg_id
                     FROM xxi.mi_rci_' || p_target_slot || '
                    WHERE cureg_id IS NOT NULL
                    GROUP BY cureg_id
                   HAVING COUNT(*) > 1
                    LIMIT 20
                  ) dup' INTO l_res;
  
      RETURN l_res;
   EXCEPTION
      WHEN OTHERS THEN
         RETURN NULL;
   END;
   $$
  
   -- Завершение загрузки: вставка из staging, индексы, CUS-синхронизация,
   -- переключение активного слота, очистка staging-таблицы.
   -- Возвращает RET_OK или RET_FAIL.
   CREATE PROCEDURE after_Load(OUT p_ret_code INTEGER, OUT p_ret_info VARCHAR) AS $$
   DECLARE
      l_active_slot  CHAR(1);
      l_target_slot  CHAR(1);
      l_nRows        INTEGER := 0;
      l_nUnl_Count   INTEGER := 0;
      l_nLnk_Count   INTEGER := 0;
      l_load_Only    BOOLEAN;
      l_prop_val     VARCHAR(100);
      l_err_msg      VARCHAR(4000);
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger_Name,
         p_function_name => 'after_Load',
         p_message_text  => 'after_Load at ' || to_char(CURRENT_TIMESTAMP, 'DD.MM.YYYY HH24:MI:SS'),
         p_inf_id        => c_Inf_Id
      );
  
      BEGIN
         p_ret_code := RET_FAIL;
         p_ret_info := NULL;

         -- Проверка состояния сессии
         IF NOT g_lock_acquired OR NOT g_upload_started OR g_target_slot IS NULL THEN
            RAISE EXCEPTION 'Некорректное состояние загрузки' USING ERRCODE = 'P0003';
         END IF;
  
         l_target_slot := g_target_slot;
  
         -- Определяем активный слот (до переключения)
         SELECT active_slot
           INTO l_active_slot
           FROM xxi."MI_RCI_CTRL"
          WHERE ctrl_id = 1;
  
         IF NOT FOUND THEN
            RAISE EXCEPTION 'Не найдена управляющая запись MI_RCI_CTRL' USING ERRCODE = 'P0003';
         END IF;
  
         CALL mi_logger.variable_value(
            p_logger_name   => c_Logger_Name,
            p_variable_name => 'active_slot',
            p_value_text    => l_active_slot,
            p_inf_id        => c_Inf_Id
         );
         CALL mi_logger.variable_value(
            p_logger_name   => c_Logger_Name,
            p_variable_name => 'target_slot',
            p_value_text    => l_target_slot,
            p_inf_id        => c_Inf_Id
         );

         -- 0. Подготовка целевого слота (TRUNCATE, снятие PK и индекса)
         CALL mi_0023_Api.set_Stage_At('PREPARE_TARGET');
         EXECUTE 'TRUNCATE TABLE xxi.mi_rci_' || l_target_slot;
         CALL mi_0023_Api.drop_Target_PK(l_target_slot);
         CALL mi_0023_Api.drop_Target_Index(l_target_slot);
  
         -- 1. Вставка данных из staging в целевой слот
         CALL mi_0023_Api.set_Stage_At('INSERT_DATA');
  
         EXECUTE 'INSERT INTO xxi.mi_rci_' || l_target_slot || ' (
            cureg_id,
            cdprf_id,
            dbth,
            ipr_dbth,
            cdoc_raw,
            ddoc_date
         )
         SELECT
            UniqueRegistryID,
            DigitalProfileID,
            mi_0023_Api.try_make_BirthDate(Year, Month, Day),
            CASE
               WHEN LOWER(TRIM(Month)) = ''нп'' THEN 1
               WHEN LOWER(TRIM(Day))   = ''нп'' THEN 2
               ELSE NULL
            END,
            DocumentID,
            mi_0023_Api.try_make_DocIssueDate(DocumentIssueDate)
         FROM pg_temp.' || c_Staging_Table;
  
         GET DIAGNOSTICS l_nRows = ROW_COUNT;
         CALL mi_logger.variable_value(
            p_logger_name   => c_Logger_Name,
            p_variable_name => 'loaded rows',
            p_value_text    => l_nRows::TEXT,
            p_inf_id        => c_Inf_Id
         );
  
         -- 2. Восстановление PK
         CALL mi_0023_Api.set_Stage_At('ENABLE_PK');
         BEGIN
            CALL mi_0023_Api.create_Target_PK(l_target_slot);
         EXCEPTION
            WHEN OTHERS THEN
               l_err_msg := 'Ошибка создания первичного ключа: ' || SQLERRM;
               --CALL mi_0023_Api.cleanup(RET_FAIL, l_err_msg);
               RAISE EXCEPTION '%', l_err_msg;
         END;
  
         -- 3. Восстановление индекса
         CALL mi_0023_Api.set_Stage_At('REBUILD_INDEXES');
         CALL mi_0023_Api.create_Target_Index(l_target_slot);
  
         -- 4. Сбор статистики
         CALL mi_0023_Api.set_Stage_At('GATHER_STATS');
         EXECUTE 'ANALYZE xxi.mi_rci_' || l_target_slot;
  
         -- 5. Получение настройки "только загрузка" (unlink_only)
         l_prop_val := SM_pkg.get_Wsp_Property(23, 8, '0');
         BEGIN
            l_load_Only := mi_utils.to_bool(l_prop_val);
         EXCEPTION
            WHEN OTHERS THEN
               l_err_msg := 'mi_0023_Api.after_Load: error convert "' || l_prop_val || '" string to bool';
               --CALL mi_0023_Api.cleanup(RET_FAIL, l_err_msg);
               RAISE EXCEPTION '%', l_err_msg;
         END;
  
         -- 6. Синхронизация CUS (откат изменений в случае ошибки)
         CALL mi_0023_Api.set_Stage_At('SYNC_CUS');
         BEGIN
            CALL mi_0023_Api.sync_Cus_With_Target(
               p_target_slot   => l_target_slot,
               p_unlink_only   => l_load_Only,
               p_unlink_count  => l_nUnl_Count,
               p_link_count    => l_nLnk_Count
            );
         EXCEPTION
            WHEN OTHERS THEN
               l_err_msg := 'Ошибка при привязке/отвязке клиентов CUS: ' || SQLERRM;
               CALL mi_logger.error(
                  p_logger_name   => c_Logger_Name,
                  p_message_text  => 'Cus_With_Target exception',
                  p_details_text  => SQLERRM,
                  p_inf_id      => c_Inf_Id
               );
         END;
  
         -- 7. Переключение активного слота
         CALL mi_0023_Api.set_Stage_At('SWITCH_SLOT');
         CALL mi_0023_Api.set_Ok_At(l_target_slot, l_nRows);
  
         p_ret_code := RET_OK;
         p_ret_info := NULL;
         CALL mi_0023_Api.cleanup(RET_OK, NULL);
  
      EXCEPTION
         WHEN OTHERS THEN
            CALL mi_0023_Api.cleanup(RET_FAIL, SQLERRM);
            p_ret_code := RET_FAIL;
            p_ret_info := SQLERRM;
            RETURN;
      END;

      p_ret_code := RET_OK;
      p_ret_info := CASE p_ret_code WHEN RET_OK THEN NULL ELSE 'Ошибка загрузки' END;
  
      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger_Name,
         p_message_text  => 'ret = ' || CASE p_ret_code WHEN 0 THEN 'OK' WHEN -1 THEN 'FAIL' ELSE p_ret_code::TEXT END,
         p_inf_id        => c_Inf_Id
      );
  
      RETURN;
   END;
   $$
   
   -- Очистка состояния загрузки: удаление staging-таблицы, сброс переменных,
   -- при необходимости фиксация ошибки в MI_RCI_CTRL.
   CREATE OR REPLACE PROCEDURE cleanup(
      p_state   IN INTEGER,
      p_message IN VARCHAR DEFAULT NULL
   ) AS $$
   BEGIN
      -- 1. Удаляем staging-таблицу, если она существует
      BEGIN
         EXECUTE 'DROP TABLE IF EXISTS pg_temp.' || c_Staging_Table;
      EXCEPTION
         WHEN OTHERS THEN
            NULL; 
      END;
  
      -- 2. Сбрасываем глобальные переменные пакета
      g_upload_started := FALSE;
      g_target_slot    := NULL;
  
      -- 3. Если загрузка завершилась ошибкой – фиксируем FAIL
      IF p_state = RET_FAIL THEN
         CALL mi_0023_Api.set_Fail_At(p_message);
         CALL mi_logger.error(
            p_logger_name   => c_Logger_Name,
            p_message_text  => p_message,
            p_inf_id        => c_Inf_Id,
            p_action_cd     => 'error'
         );
      END IF;

      -- Записываем req_id в управляющую таблицу, если он был установлен
      IF g_req_id IS NOT NULL THEN
         UPDATE xxi."MI_RCI_CTRL" SET req_id = g_req_id WHERE ctrl_id = 1;
         g_req_id := NULL;
      END IF;

      -- 4. При необходимости явно освобождаем блокировку
      IF g_lock_acquired AND g_lock_handle IS NOT NULL THEN
         DECLARE
            l_rel_ret  INTEGER;
            l_rel_info VARCHAR(4000);
         BEGIN
            CALL mi_utils.lock_release(g_lock_handle, l_rel_ret, l_rel_info);
            CALL mi_logger.info(
               p_logger_name   => c_Logger_Name,
               p_message_text  => 'Снятие блокировки',
               p_details_text  => 'mi_utils.lock_release( key=' || g_lock_handle::text || ' )',
               p_inf_id        => c_Inf_Id
            );
         EXCEPTION WHEN OTHERS THEN NULL;
         END;
      END IF;

      g_lock_acquired := FALSE;
      g_lock_handle   := NULL;
   END;
   $$
;
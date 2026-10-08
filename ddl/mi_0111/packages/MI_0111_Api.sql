CREATE OR REPLACE PACKAGE mi_0111_Api

   -- Функция инициализации пакета mi_0111_Api
   CREATE FUNCTION __init__() RETURNS void AS $$
   DECLARE
      /*
         Пакет для ведения логики MI-edo
         Модуль: Признак самозанятого (вид сведений 0111)
      */
      cVersion CONSTANT VARCHAR(100) := '$id: {1.0.1} {29.07.2026} Sukhotina$';
   
      -- Коды возврата
      RET_OK      CONSTANT INTEGER := 0;
      RET_FAIL    CONSTANT INTEGER := -1;
      RET_LOCK    CONSTANT INTEGER := 3;
      RET_NO_DATA CONSTANT INTEGER := 1;   -- нет данных для отправки
   
      -- Названия для логирования и блокировок
      c_Pkg_Name    CONSTANT VARCHAR(20) := 'mi_0111_Api';
      c_Inf_Id      CONSTANT NUMERIC := 111;
   BEGIN
      RAISE DEBUG 'Package "%" - % - initialized', c_Pkg_Name, cVersion;
   END;
   $$

   -- Возвращает версию пакета
   CREATE FUNCTION Get_Version() RETURNS VARCHAR AS $$
   BEGIN
      RETURN cVersion;
   END;
   $$
   
   CREATE FUNCTION create_request() RETURNS NUMERIC AS $$
      #package
      --#private
   BEGIN
      RETURN MI_request_Api.create_Request(c_Inf_Id, NULL::UUID);
   END;
   $$
   
   -- Формирование JSON с персональными данными (включая ИНН)
   CREATE FUNCTION build_json_person(p_cus v_mi_0111_ca) RETURNS JSONB AS $$
      #package
      --#private
   DECLARE
      l_json JSONB;
   BEGIN
      l_json := jsonb_build_object(
         'icusnum',     p_cus.icusnum,
         'last_name',   p_cus.last_name,
         'first_name',  p_cus.first_name,
         'middle_name', p_cus.middle_name,
         'birth_date',  p_cus.birth_date,
         'inn',         p_cus.inn
      );
      RETURN jsonb_strip_nulls(l_json);
   END;
   $$
   
   -- Вставка элемента в xxi.mi_0001, включая ИНН, и удаление устаревших записей
   CREATE FUNCTION create_item(
      p_inf_id       NUMERIC,
      p_req_id       NUMERIC,
      p_cus          v_mi_0111_ca,
      p_ids4remove   NUMERIC[],
      p_inn_check_on DATE
   ) RETURNS NUMERIC AS $$
      #package
      --#private
   DECLARE
      l_person_id   NUMERIC;
      l_itm_id      NUMERIC;
      l_json_person JSONB;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Pkg_Name,
         p_function_name => 'create_item',
         p_message_text  => 'p_req_id = ' || p_req_id || ', icusnum = ' || p_cus.icusnum,
         p_inf_id        => c_Inf_Id
      );

      l_json_person := mi_0111_api.build_json_person(p_cus);
   
      l_person_id := MI_person_Api.get_Or_Create(
         p_inf_id   => p_inf_id,
         p_person_J => l_json_person
      );
   
      l_itm_id := MI_request_Api.next_Itm_Id();
   
      INSERT INTO xxi.mi_0001 (
         itm_id,
         req_id,
         person_id,
         icusnum,
         inn,
         created_at,
         inn_check_on
      ) VALUES (
         l_itm_id,
         p_req_id,
         l_person_id,
         p_cus.icusnum,
         p_cus.inn,
         clock_timestamp(),
         p_inn_check_on
      );
   
      CALL mi_logger.variable_value(
         p_logger_name   => c_Pkg_Name,
         p_variable_name => 'itm_id',
         p_value_text    => l_itm_id::VARCHAR,
         p_inf_id        => c_Inf_Id
      );

      IF p_ids4remove IS NOT NULL AND array_length(p_ids4remove, 1) > 0 THEN
         DELETE FROM xxi.mi_0001
          WHERE itm_id = ANY(p_ids4remove);
   
         CALL mi_logger.info(
            p_logger_name   => c_Pkg_Name,
            p_message_text  => 'Удалено ' || array_length(p_ids4remove, 1) || ' старых записей',
            p_details_text  => 'mi_0001.itm_id: ' || array_to_string(p_ids4remove, ','),
            p_inf_id        => c_Inf_Id
         );
      END IF;
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Pkg_Name,
         p_message_text  => 'itm_id = ' || l_itm_id,
         p_inf_id        => c_Inf_Id
      );

      RETURN l_itm_id;
   END;
   $$

   -- Проверка возможности создания запроса для клиента
   CREATE PROCEDURE check_4_prepare(
      IN  p_icusnum          NUMERIC,
      IN  p_last_name        VARCHAR,
      IN  p_first_name       VARCHAR,
      IN  p_middle_name      VARCHAR,
      IN  p_birth_date       DATE,
      IN  p_inn              VARCHAR,
      IN  p_handle_not_found BOOLEAN,
      IN  p_wait_hour_range  INTEGER,
      IN  p_valid_days       INTEGER,    -- срок действия признака (0 – не проверять)
      IN  p_inn_check_on     DATE,
      OUT p_create           BOOLEAN,
      OUT p_ids4remove       NUMERIC[],
      OUT p_error_count      INTEGER,
      OUT p_result_info      VARCHAR
   ) AS $$
   DECLARE
      l_ncount    INTEGER := 0;
      l_doCreate  BOOLEAN := TRUE;
      l_dLast     DATE;
   
      -- Курсор для проверки существующих запросов
      c_data CURSOR FOR
         SELECT r.req_id, r.inf_id, r.status_cd, i.ires_code, r.created_at, i.person_id, i.itm_id
           FROM xxi.mi_req r
                INNER JOIN xxi.mi_0001 i ON r.req_id = i.req_id
          WHERE i.icusnum = p_icusnum
            AND r.inf_id = 111
          ORDER BY r.created_at DESC,
                   CASE r.status_cd
                      WHEN  1 THEN -2
                      WHEN -1 THEN -3
                      ELSE r.status_cd
                   END DESC;
      r record;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Pkg_Name,
         p_function_name => 'check_4_prepare',
         p_message_text  => 'p_icusnum=' || p_icusnum || ', p_inn=' || p_inn,
         p_inf_id        => c_Inf_Id
      );

      p_ids4remove := '{}';
      p_result_info := NULL;
      p_error_count := 0;
   
      -- 1. Валидация ИНН (12 цифр)
      IF p_inn IS NULL OR NOT p_inn ~ '^\d{12}$' THEN
         p_result_info := 'У клиента ' || p_icusnum || ' некорректный ИНН: ' || COALESCE(p_inn, 'NULL');
         CALL mi_logger.info(
            p_logger_name   => c_Pkg_Name,
            p_message_text  => p_result_info,
            p_inf_id        => c_Inf_Id,
            p_icusnum       => p_icusnum
         );
         p_create := FALSE;
         CALL mi_logger.exit_f(
            p_logger_name   => c_Pkg_Name,
            p_message_text  => 'create = FALSE, reason: ' || p_result_info,
            p_inf_id        => c_Inf_Id
         );
         RETURN;
      END IF;
      
      -- 2. Проверка актуальности признака самозанятого (атрибут 669)
      IF p_valid_days > 0 THEN
         BEGIN
            SELECT MAX(b.date_value)
              INTO l_dLast
              FROM xxi.cus_add_atr a
                   JOIN xxi.cus_add_atr_val b ON b.id_value = a.id_value
             WHERE a.id_atr = 669
               AND a.icusnum = p_icusnum;
         EXCEPTION WHEN OTHERS THEN
            l_dLast := NULL;
         END;
   
         IF l_dLast IS NOT NULL AND (p_inn_check_on - l_dLast) < p_valid_days THEN
            p_result_info := 'У клиента ' || p_icusnum || ' признак самозанятого ещё актуален (установлен ' || l_dLast::TEXT || ')';
            CALL mi_logger.info(
               p_logger_name   => c_Pkg_Name,
               p_message_text  => p_result_info,
               p_inf_id        => c_Inf_Id,
               p_icusnum       => p_icusnum
            );
            p_create := FALSE;
            CALL mi_logger.exit_f(
               p_logger_name   => c_Pkg_Name,
               p_message_text  => 'create = FALSE, reason: ' || p_result_info,
               p_inf_id        => c_Inf_Id
            );
            RETURN;
         END IF;
      END IF;
   
      -- 3. Проверка существующих запросов в статусе 0 или -1 (кроме не повторяемых ошибок)
      FOR r IN c_data LOOP
         l_ncount := l_ncount + 1;
   
         IF r.status_cd = 0 THEN
            -- уже есть подготовленный запрос, но ещё не отправлен
            l_doCreate := FALSE;
            p_result_info := 'Для клиента ' || p_icusnum || ' уже есть подготовленный запрос, но ещё не принят в обработку';
   
         ELSIF r.status_cd = 1 AND r.ires_code IS NULL THEN
            -- успешный запрос, но результат не обработан
            l_doCreate := FALSE;
            p_result_info := 'Для клиента ' || p_icusnum || ' есть успешно выполненный запрос, но результат не зафиксирован';
   
         ELSIF r.status_cd = 1 AND r.ires_code = 1 THEN
            -- "Сведения не найдены"
            IF NOT p_handle_not_found THEN
               l_doCreate := FALSE;
               p_result_info := 'Для клиента ' || p_icusnum || ' есть запрос со статусом "Сведения не найдены"';
            END IF;
   
         ELSIF r.status_cd IN (2, 3) THEN
            -- запрос в обработке, проверяем таймаут
            IF (EXTRACT(EPOCH FROM CURRENT_TIMESTAMP - r.created_at) / 3600) > p_wait_hour_range THEN
               CALL mi_logger.info(
                  p_logger_name   => c_Pkg_Name,
                  p_message_text  => 'Для клиента ' || p_icusnum || ' удаляем подвисший запрос',
                  p_inf_id        => c_Inf_Id,
                  p_person_id     => r.person_id,
                  p_icusnum       => p_icusnum
               );
               p_ids4remove := array_append(p_ids4remove, r.itm_id);
            ELSE
               l_doCreate := FALSE;
            END IF;
   
         ELSIF r.status_cd = -1 THEN
            -- ошибочный запрос – удаляем, чтобы создать новый
            CALL mi_logger.info(
               p_logger_name   => c_Pkg_Name,
               p_message_text  => 'Для клиента ' || p_icusnum || ' удаляем ошибочный запрос',
               p_inf_id        => c_Inf_Id,
               p_person_id     => r.person_id,
               p_icusnum       => p_icusnum
            );
            p_ids4remove := array_append(p_ids4remove, r.itm_id);
         END IF;
      END LOOP;
   
      IF p_result_info IS NOT NULL THEN
         CALL mi_logger.info(
            p_logger_name   => c_Pkg_Name,
            p_message_text  => p_result_info,
            p_inf_id        => c_Inf_Id,
            p_icusnum       => p_icusnum
         );
      END IF;
   
      IF l_ncount > 0 THEN
         CALL mi_logger.info(
            p_logger_name   => c_Pkg_Name,
            p_message_text  => 'Для клиента ' || p_icusnum || ' было ' || l_ncount || ' записей запросов',
            p_inf_id        => c_Inf_Id,
            p_icusnum       => p_icusnum
         );
      END IF;
   
      -- 4. Проверка обязательных полей, если всё ещё планируется создание
      IF l_doCreate THEN
         IF p_last_name IS NULL OR p_first_name IS NULL THEN
            p_result_info := 'У клиента ' || p_icusnum || ' не заполнены Фамилия или Имя';
            l_doCreate := FALSE;
         END IF;
   
         IF p_birth_date IS NULL THEN
            p_result_info := 'У клиента ' || p_icusnum || ' не заполнена Дата рождения';
            l_doCreate := FALSE;
         END IF;
   
         IF NOT l_doCreate THEN
            p_error_count := p_error_count + 1;
         END IF;
   
         IF p_result_info IS NOT NULL THEN
            CALL mi_logger.info(
               p_logger_name   => c_Pkg_Name,
               p_message_text  => p_result_info,
               p_inf_id        => c_Inf_Id,
               p_icusnum       => p_icusnum
            );
         END IF;
      END IF;
   
      p_create := l_doCreate;

      CALL mi_logger.exit_f(
         p_logger_name   => c_Pkg_Name,
         p_message_text  => 'create = ' || p_create || ', ids4remove = ' || array_length(p_ids4remove, 1) || ', reason: ' || COALESCE(p_result_info, 'OK'),
         p_inf_id        => c_Inf_Id
      );
   END;
   $$

   CREATE PROCEDURE create_personal_request(
      IN  p_cus          v_mi_0111_ca,
      OUT p_req_id       NUMERIC,
      OUT p_itm_id       NUMERIC,
      OUT p_res_code     INTEGER,
      OUT p_res_info     VARCHAR,
      IN  p_inn_check_on DATE DEFAULT CURRENT_DATE
   ) AS $$
   DECLARE
      l_wait_Hour_Range  INTEGER := 72;
      l_handle_Not_Found BOOLEAN := MI_prp.get_Wsp_Property(1, 'HANDLE_NOT_FOUND', 'false')::BOOLEAN;
      l_valid_Days       INTEGER := MI_prp.get_Wsp_Property(1, 'SLFEMPL_NDAYS_VALID', '0')::INTEGER;
      l_doCreate         BOOLEAN := FALSE;
      l_ids4Remove       NUMERIC[];
      l_error_Count      INTEGER := 0;
      l_info             VARCHAR;

      -- блокировка
      l_lock_Handle      VARCHAR(100);
      l_lock_Code        INTEGER;
      l_lock_Info        VARCHAR(4000);
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Pkg_Name,
         p_function_name => 'create_personal_request',
         p_message_text  => 'icusnum=' || p_cus.icusnum,
         p_inf_id        => c_Inf_Id
      );
   
      p_res_code := RET_FAIL;
      p_req_id   := NULL;
      p_itm_id   := NULL;
   
      -- Захват сессионной блокировки
      CALL MI_utils.lock_Proc(c_Pkg_Name, false, 0, l_lock_Code, l_lock_Info, l_lock_Handle);
      IF l_lock_Code <> RET_OK THEN
         IF l_lock_Code = 1 THEN
            p_res_code := RET_LOCK;
            p_res_info := 'Блокировка уже захвачена другой сессией';
            CALL mi_logger.info(
               p_logger_name   => c_Pkg_Name,
               p_message_text  => p_res_info,
               p_inf_id        => c_Inf_Id
            );
            RETURN;
         ELSE
            p_res_code := RET_FAIL;
            p_res_info := 'Ошибка при получении блокировки: ' || COALESCE(l_lock_Info, 'неизвестная ошибка');
            CALL mi_logger.error(
               p_logger_name   => c_Pkg_Name,
               p_message_text  => p_res_info,
               p_inf_id        => c_Inf_Id
            );
            RETURN;
         END IF;
      END IF;
   
      BEGIN
         CALL mi_0111_api.check_4_prepare(
            p_icusnum          => p_cus.icusnum,
            p_last_name        => p_cus.last_name,
            p_first_name       => p_cus.first_name,
            p_middle_name      => p_cus.middle_name,
            p_birth_date       => p_cus.birth_date,
            p_inn              => p_cus.inn,
            p_handle_not_found => l_handle_Not_Found,
            p_wait_hour_range  => l_wait_Hour_Range,
            p_valid_days       => l_valid_Days,
            p_inn_check_on     => p_inn_check_on,
            p_create           => l_doCreate,
            p_ids4remove       => l_ids4Remove,
            p_error_count      => l_error_Count,
            p_result_info      => l_info
         );
   
         IF l_doCreate THEN
            p_req_id := mi_0111_api.create_request();
            p_itm_id := mi_0111_api.create_item(c_Inf_Id, p_req_id, p_cus, l_ids4Remove, p_inn_check_on);
            p_res_code := RET_OK;
            p_res_info := NULL;
         ELSE
            p_res_code := RET_FAIL;
            p_res_info := l_info;
         END IF;
   
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
               p_res_info := TS.WhenOthersError('MI_0111_Api.create_Personal_Request', ex);
            END;
      END;
   
      -- Освобождение блокировки
      IF l_lock_Handle IS NOT NULL THEN
         DECLARE
            l_rel_ret  INTEGER;
            l_rel_info VARCHAR(4000);
         BEGIN
            CALL MI_utils.lock_release(l_lock_Handle, l_rel_ret, l_rel_info);
         EXCEPTION WHEN OTHERS THEN NULL;
         END;
      END IF;
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Pkg_Name,
         p_message_text  => 'ret_code = ' || p_res_code || ', req_id = ' || p_req_id || ', itm_id = ' || p_itm_id,
         p_inf_id        => c_Inf_Id
      );
   END;
   $$
   
   CREATE PROCEDURE auto_prepare(OUT p_ret_code INTEGER, OUT p_ret_info VARCHAR, IN p_inn_check_on DATE DEFAULT CURRENT_DATE) AS $$
      #package
   DECLARE
      l_lock_Handle     VARCHAR(100);
      l_lock_Code       INTEGER;
      l_lock_Info       VARCHAR(4000);
   
      l_req_Id          NUMERIC;
   
      l_handle_Not_Found BOOLEAN := MI_prp.get_Wsp_Property(1, 'HANDLE_NOT_FOUND', 'false')::BOOLEAN;
      l_wait_Hour_Range  INTEGER := 72;
      l_valid_Days       INTEGER := MI_prp.get_Wsp_Property(1, 'SLFEMPL_NDAYS_VALID', '0')::INTEGER;
      l_has_data         BOOLEAN;
   
      l_ttl_Count        INTEGER := 0;
      l_suc_Count        INTEGER := 0;
      l_err_Count        INTEGER := 0;
   
      l_doCreate         BOOLEAN;
      l_ids4Remove       NUMERIC[];
      l_error_Count      INTEGER;
      l_result_Info      VARCHAR(4000);
   
      r                  v_mi_0111_ca%ROWTYPE;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Pkg_Name,
         p_function_name => 'auto_prepare',
         p_message_text  => 'Начало автоматического сбора данных для самозанятых',
         p_inf_id        => c_Inf_Id
      );

      -- Предварительная проверка наличия данных
      SELECT EXISTS (SELECT 1 FROM xxi.v_mi_0111_ca) INTO l_has_data;
      IF NOT l_has_data THEN
         p_ret_code := RET_NO_DATA;
         p_ret_info := 'Нет данных для отправки';
         CALL mi_logger.info(
            p_logger_name   => c_Pkg_Name,
            p_message_text  => p_ret_info,
            p_inf_id        => c_Inf_Id
         );
         CALL mi_logger.exit_f(
            p_logger_name   => c_Pkg_Name,
            p_message_text  => 'auto_prepare: ' || p_ret_info,
            p_inf_id        => c_Inf_Id
         );
         RETURN;
      END IF;
   
      -- 1. Блокировка процесса
      CALL MI_utils.lock_Proc(c_Pkg_Name, false, 0, l_lock_Code, l_lock_Info, l_lock_Handle);
      IF l_lock_Code <> RET_OK THEN
         IF l_lock_Code = 1 THEN
            p_ret_code := RET_LOCK;
            p_ret_info := 'Блокировка уже захвачена другой сессией';
            CALL mi_logger.info(
               p_logger_name   => c_Pkg_Name,
               p_message_text  => p_ret_info,
               p_inf_id        => c_Inf_Id
            );
            RETURN;
         ELSE
            p_ret_code := RET_FAIL;
            p_ret_info := 'Ошибка при получении блокировки: ' || COALESCE(l_lock_Info, 'неизвестная ошибка');
            CALL mi_logger.error(
               p_logger_name   => c_Pkg_Name,
               p_message_text  => p_ret_info,
               p_inf_id        => c_Inf_Id
            );
            RETURN;
         END IF;
      END IF;
   
      -- 2. Создаём общий запрос вида сведений 0111
      l_req_Id := mi_0111_api.create_request();
      CALL mi_logger.variable_value(
         p_logger_name   => c_Pkg_Name,
         p_variable_name => 'req_id',
         p_value_text    => l_req_Id::VARCHAR,
         p_inf_id        => c_Inf_Id
      );
   
      -- 3. Цикл по клиентам из представления
      FOR r IN (SELECT * FROM xxi.v_mi_0111_ca) LOOP
         l_ttl_Count := l_ttl_Count + 1;
   
         BEGIN
            CALL mi_0111_api.check_4_prepare(
               p_icusnum          => r.icusnum,
               p_last_name        => r.last_name,
               p_first_name       => r.first_name,
               p_middle_name      => r.middle_name,
               p_birth_date       => r.birth_date,
               p_inn              => r.inn,
               p_handle_not_found => l_handle_Not_Found,
               p_wait_hour_range  => l_wait_Hour_Range,
               p_valid_days       => l_valid_Days,
               p_inn_check_on     => p_inn_check_on,
               p_create           => l_doCreate,
               p_ids4remove       => l_ids4Remove,
               p_error_count      => l_error_Count,
               p_result_info      => l_result_Info
            );
   
            IF l_error_Count > 0 THEN
               l_err_Count := l_err_Count + l_error_Count;
            END IF;
   
            IF l_doCreate THEN
               PERFORM mi_0111_api.create_item(c_Inf_Id, l_req_Id, r, l_ids4Remove, p_inn_check_on);
               l_suc_Count := l_suc_Count + 1;
            END IF;
         EXCEPTION
            WHEN OTHERS THEN
               l_err_Count := l_err_Count + 1;
               CALL mi_logger.error(
                  p_logger_name   => c_Pkg_Name,
                  p_message_text  => 'Ошибка при обработке клиента ' || r.icusnum,
                  p_details_text  => SQLERRM,
                  p_inf_id        => c_Inf_Id,
                  p_icusnum       => r.icusnum
               );
         END;
      END LOOP;
   
      -- 4. Итоговое логирование
      CALL mi_logger.info(
         p_logger_name   => c_Pkg_Name,
         p_message_text  => 'Автосбор завершён. Всего: ' || l_ttl_Count ||
                            ', успешно: ' || l_suc_Count ||
                            ', ошибок: ' || l_err_Count ||
                            ', пропущено: ' || (l_ttl_Count - l_suc_Count - l_err_Count),
         p_inf_id        => c_Inf_Id
      );

      -- Освобождаем сессионную блокировку
      IF l_lock_Handle IS NOT NULL THEN
         DECLARE
            l_rel_ret  INTEGER;
            l_rel_info VARCHAR(4000);
         BEGIN
            CALL MI_utils.lock_release(l_lock_Handle, l_rel_ret, l_rel_info);
            CALL mi_logger.variable_value(
               p_logger_name   => c_Pkg_Name,
               p_variable_name => 'lock_release',
               p_value_text    => l_rel_ret::VARCHAR,
               p_inf_id        => c_Inf_Id
            );
         EXCEPTION WHEN OTHERS THEN NULL;
         END;
      END IF;
   
      p_ret_code := RET_OK;
      p_ret_info := NULL;
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Pkg_Name,
         p_message_text  => 'auto_prepare завершён успешно',
         p_inf_id        => c_Inf_Id
      );
   
   
   EXCEPTION
      WHEN OTHERS THEN
         -- Освобождаем блокировку даже при ошибке
         IF l_lock_Handle IS NOT NULL THEN
            BEGIN
               DECLARE
                  l_rel_ret  INTEGER;
                  l_rel_info VARCHAR(4000);
               BEGIN
                  CALL MI_utils.lock_release(l_lock_Handle, l_rel_ret, l_rel_info);
               EXCEPTION WHEN OTHERS THEN NULL;
               END;
            END;
         END IF;
   
         p_ret_code := RET_FAIL;
         p_ret_info := SQLERRM;
   
         CALL mi_logger.error(
            p_logger_name   => c_Pkg_Name,
            p_message_text  => 'Критическая ошибка в auto_prepare',
            p_details_text  => SQLERRM,
            p_inf_id        => c_Inf_Id
         );
         RETURN;
   END;
   $$
   
      -- Преобразование текстового кода ошибки СМЭВ в числовой код результата
   CREATE FUNCTION map_error_code(p_error_code VARCHAR) RETURNS INTEGER AS $$
      #package
      --#private
   BEGIN
      RETURN CASE p_error_code
         WHEN 'taxpayer.status.service.unavailable.error' THEN 101
         WHEN 'taxpayer.status.service.limited.error'     THEN 102
         WHEN 'validation.failed'                         THEN 103
         WHEN 'bad_request'                               THEN 104
         WHEN 'internal_error'                            THEN 105
         ELSE NULL
      END;
   END;
   $$

   -- Разбор JSON-ответа по одному элементу, обновление xxi.mi_0001
   CREATE FUNCTION map_item_result(p_itm_id NUMERIC, p_payload JSONB)
      RETURNS MI_Item_Result_Api.Item_Result AS $$
      #package
   DECLARE
      cFunc       VARCHAR := c_Pkg_Name || '.map_Item_Result';
      l_status    BOOLEAN;
      l_message   VARCHAR;
      l_error_code VARCHAR;
      l_ires_code INTEGER;
      l_res       MI_Item_Result_Api.Item_Result;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Pkg_Name,
         p_function_name => 'map_item_result',
         p_message_text  => 'itm_id = ' || p_itm_id,
         p_inf_id        => c_Inf_Id
      );
   
      l_message    := p_payload->>'message';
      l_error_code := p_payload->>'code';
   
      -- Определяем тип ответа по наличию ключей
      IF p_payload ? 'status' THEN
         -- Успешный ответ
         l_status := (p_payload->>'status')::BOOLEAN;
         IF l_status THEN
            l_ires_code := 1;
         ELSE
            l_ires_code := 0;
         END IF;
         l_res.iRes_Code  := l_ires_code;
         l_res.cRes_info  := l_message;
      ELSIF l_error_code IS NOT NULL THEN
         -- Ошибка с кодом
         l_res.iRes_Code  := mi_0111_api.map_error_code(l_error_code);
         l_res.cRes_info  := COALESCE(l_message, 'Ошибка обработки запроса');
      ELSE
         -- Неизвестный формат
         l_res.iRes_Code  := RET_FAIL;
         l_res.cRes_info  := 'Некорректный формат ответа';
      END IF;
   
      UPDATE xxi.mi_0001
         SET ires_code  = l_res.iRes_Code,
             cres_info  = l_res.cRes_info,
             tres_time  = clock_timestamp()
       WHERE itm_id     = p_itm_id;
   
      CALL mi_logger.exit_f(
         p_logger_name   => c_Pkg_Name,
         p_message_text  => 'iRes_Code = ' || COALESCE(l_res.iRes_Code::TEXT, 'NULL') || ', cRes_info = ' || COALESCE(l_res.cRes_info, 'NULL'),
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
            l_res.cRes_info := 'Error on map JSON item: ' || TS.WhenOthersError(cFunc, ex);
         END;
   
         CALL mi_logger.error(
            p_logger_name   => c_Pkg_Name,
            p_message_text  => 'Ошибка в map_item_result',
            p_details_text  => SQLERRM,
            p_inf_id        => c_Inf_Id
         );
   
         RETURN l_res;
   END;
   $$

   -- Обёртка для вызова универсального обработчика ответа по элементу
   CREATE PROCEDURE apply_item_result(
      IN  p_request_uuid    UUID,
      IN  p_message_uuid    UUID,
      IN  p_item_uuid       UUID,
      IN  p_response_kind   INTEGER,
      IN  p_response_code   VARCHAR,
      IN  p_response_info   VARCHAR,
      IN  p_response_details TEXT,
      IN  p_response_time   TIMESTAMPTZ,
      IN  p_payload_text    TEXT,
      OUT p_ret_code        INTEGER,
      OUT p_ret_info        VARCHAR
   ) AS $$
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Pkg_Name,
         p_function_name => 'apply_item_result',
         p_message_text  => 'item_uuid = ' || p_item_uuid,
         p_inf_id        => c_Inf_Id
      );

      CALL MI_Item_Result_Api.apply_Item_Result(
         'xxi.mi_0001'::REGCLASS,
         'MI_0111_Api.map_Item_Result(numeric,jsonb)'::REGPROCEDURE,
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
         p_logger_name   => c_Pkg_Name,
         p_message_text  => 'ret_code = ' || p_ret_code || ', ret_info = ' || COALESCE(p_ret_info, 'OK'),
         p_inf_id        => c_Inf_Id
      );
   END;
   $$
   
   CREATE PROCEDURE submit_auto_prepare(
      OUT p_job_id        BIGINT,
      IN  p_inn_check_on  DATE DEFAULT CURRENT_DATE,
      IN  p_source        VARCHAR DEFAULT NULL
   ) AS $$
   DECLARE
      c_job_name CONSTANT TEXT := 'MI_0111_AUTO_PREPARE';
   BEGIN
      -- Транзакционная блокировка для сериализации проверки/создания задания
      PERFORM pg_advisory_xact_lock(
         hashtext('MI_0111_API'),
         hashtext('AUTO_PREPARE')
      );

      -- Проверяем, нет ли уже активного задания с таким именем
      SELECT j.id
             INTO p_job_id
        FROM schedule.job_status j
       WHERE j.name = c_job_name
         AND j.status::text IN ('submitted', 'processing')
       ORDER BY j.id DESC
       LIMIT 1;

      IF FOUND THEN
         p_job_id := -p_job_id;   -- возвращаем отрицательный ID существующего задания
         RETURN;
      END IF;

      -- Создаём новое задание, вызывающее auto_prepare с переданной датой.
      p_job_id := schedule.submit_job(
         query  => 'CALL mi_0111_Api.auto_prepare(NULL, NULL, $1::date);',
         params => ARRAY[p_inn_check_on::text],
         name   => c_job_name,
         comments => format('source=%s, inn_check_on=%s', COALESCE(p_source, 'UNKNOWN'), p_inn_check_on)
      );
   END;
   $$
;

COMMENT ON SCHEMA mi_0111_api IS 'Package mi_0111_api {$Id$}'
;
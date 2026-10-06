CREATE OR REPLACE PACKAGE mi_0003_Api

   -- Инициализация пакета
   CREATE FUNCTION __init__() RETURNS void AS $$
   DECLARE
      /*
         Пакет для ведения логики СМЭВ 3.0
         Модуль: Сведения ЕГРЮЛ/ЕГРИП (вид сведений 003)
      */
      cVersion CONSTANT VARCHAR(100) := '$id: {1.0.1} {12.08.2026} Sukhotina$';

      -- Коды возврата
      RET_OK      CONSTANT INTEGER := 0;
      RET_FAIL    CONSTANT INTEGER := -1;
      RET_LOCK    CONSTANT INTEGER := 3;
      RET_NO_DATA CONSTANT INTEGER := 1;

      -- Идентификаторы видов сведений
      c_Inf_Id_UL CONSTANT NUMERIC := 32;   -- ЮЛ
      c_Inf_Id_IP CONSTANT NUMERIC := 34;   -- ИП

      -- Названия для логирования и блокировок
      cPkg_Name   CONSTANT VARCHAR(20) := 'mi_0003_Api';
      c_Lock_Name CONSTANT VARCHAR(20) := 'mi_0003_auto';
   BEGIN
      RAISE DEBUG 'Package "%" - % - initialized', cPkg_Name, cVersion;
   END;
   $$

   -- Возвращает версию пакета
   CREATE FUNCTION Get_Version() RETURNS VARCHAR AS $$
   BEGIN
      RETURN cVersion;
   END;
   $$
   
   CREATE FUNCTION mi_0003_api.create_request(p_cus_type INTEGER) RETURNS NUMERIC AS $$
      #package
      --#private
   DECLARE
      l_inf_id NUMERIC;
   BEGIN
      IF p_cus_type = 2 THEN
         l_inf_id := c_Inf_Id_UL;      -- 32
      ELSIF p_cus_type = 4 THEN
         l_inf_id := c_Inf_Id_IP;      -- 34
      ELSE
         RAISE EXCEPTION 'Invalid cus_type: %', p_cus_type;
      END IF;
   
      RETURN MI_request_Api.create_Request(l_inf_id, NULL::UUID);
   END;
   $$
   
   CREATE FUNCTION mi_0003_api.create_item(
      p_inf_id       NUMERIC,
      p_req_id       NUMERIC,
      p_icusnum      NUMERIC,
      p_cus_type     INTEGER,
      p_ogrn         VARCHAR DEFAULT NULL,
      p_inn          VARCHAR DEFAULT NULL,
      --p_person_id    NUMERIC DEFAULT NULL,
      p_ids4remove   NUMERIC[] DEFAULT NULL
   ) RETURNS NUMERIC AS $$
      #package
      --#private
   DECLARE
      l_itm_id NUMERIC;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => cPkg_Name,
         p_function_name => 'create_item',
         p_message_text  => format('req_id=%s, icusnum=%s, cus_type=%s, ogrn=%s, inn=%s',
                                   p_req_id, p_icusnum, p_cus_type, p_ogrn, p_inn),
         p_inf_id        => p_inf_id
      );
   
      l_itm_id := MI_request_Api.next_Itm_Id();
   
      INSERT INTO xxi.mi_0003 (
         itm_id, req_id, cus_type, icusnum, cogrn, cinn, created_at
      ) VALUES (
         l_itm_id, p_req_id, p_cus_type, p_icusnum, p_ogrn, p_inn, clock_timestamp()
      );
   
      CALL mi_logger.variable_value(
         p_logger_name   => cPkg_Name,
         p_variable_name => 'itm_id',
         p_value_text    => l_itm_id::VARCHAR,
         p_inf_id        => p_inf_id
      );
   
      -- Удаление устаревших записей
      IF p_ids4remove IS NOT NULL AND array_length(p_ids4remove, 1) > 0 THEN
         DELETE FROM xxi.mi_0003 WHERE itm_id = ANY(p_ids4remove);
         CALL mi_logger.info(
            p_logger_name   => cPkg_Name,
            p_message_text  => 'Удалено ' || array_length(p_ids4remove, 1) || ' старых записей',
            p_details_text  => 'mi_0003.itm_id: ' || array_to_string(p_ids4remove, ','),
            p_inf_id        => p_inf_id
         );
      END IF;
   
      CALL mi_logger.exit_f(
         p_logger_name   => cPkg_Name,
         p_message_text  => 'itm_id = ' || l_itm_id,
         p_inf_id        => p_inf_id
      );
   
      RETURN l_itm_id;
   END;
   $$

   CREATE OR REPLACE PROCEDURE mi_0003_api.check_4_prepare(
      IN  p_icusnum           NUMERIC,
      IN  p_cus_type          INTEGER,
      IN  p_ogrn              VARCHAR,
      IN  p_inn               VARCHAR,
      IN  p_handle_not_found  BOOLEAN,
      IN  p_wait_hour_range   INTEGER,
      OUT p_create            BOOLEAN,
      OUT p_ids4remove        NUMERIC[],
      OUT p_error_count       INTEGER,
      OUT p_result_info       VARCHAR
   ) AS $$
      #package
      --#private
   DECLARE
      l_ncount    INTEGER := 0;
      l_doCreate  BOOLEAN := TRUE;
   
      -- Курсор по существующим запросам
      c_data CURSOR FOR
         SELECT r.req_id, r.status_cd, i.ires_code, r.created_at, i.itm_id
           FROM xxi.mi_req r
                INNER JOIN xxi.mi_0003 i ON r.req_id = i.req_id
          WHERE i.icusnum = p_icusnum
            AND i.cus_type = p_cus_type
          ORDER BY r.created_at DESC,
                   CASE r.status_cd
                      WHEN  1 THEN -2
                      WHEN -1 THEN -3
                      ELSE r.status_cd
                   END DESC;
      r record;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => cPkg_Name,
         p_function_name => 'check_4_prepare',
         p_message_text  => format('icusnum=%s, cus_type=%s, ogrn=%s, inn=%s', p_icusnum, p_cus_type, p_ogrn, p_inn),
         p_inf_id        => CASE p_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END
      );
   
      p_ids4remove := '{}';
      p_result_info := NULL;
      p_error_count := 0;
   
      -- 1. Валидация ОГРН/ИНН
      IF p_ogrn IS NOT NULL THEN
         IF p_cus_type = 2 AND length(p_ogrn) <> 13 THEN
            p_result_info := 'ОГРН ЮЛ должен содержать 13 цифр, фактически: ' || length(p_ogrn);
         ELSIF p_cus_type = 4 AND length(p_ogrn) <> 15 THEN
            p_result_info := 'ОГРН ИП должен содержать 15 цифр, фактически: ' || length(p_ogrn);
         END IF;
      END IF;
   
      IF p_inn IS NOT NULL THEN
         IF p_cus_type = 2 AND length(p_inn) <> 10 THEN
            p_result_info := 'ИНН ЮЛ должен содержать 10 цифр, фактически: ' || length(p_inn);
         ELSIF p_cus_type = 4 AND length(p_inn) <> 12 THEN
            p_result_info := 'ИНН ИП должен содержать 12 цифр, фактически: ' || length(p_inn);
         END IF;
      END IF;
   
      -- Если и ОГРН, и ИНН заданы, проверяем согласованность (необязательно, но можно)
      IF p_ogrn IS NOT NULL AND p_inn IS NOT NULL THEN
         IF (p_cus_type = 2 AND (length(p_ogrn) != 13 OR length(p_inn) != 10)) OR
            (p_cus_type = 4 AND (length(p_ogrn) != 15 OR length(p_inn) != 12)) THEN
            p_result_info := 'Несоответствие длин ОГРН и ИНН для типа субъекта ' || p_cus_type;
         END IF;
      END IF;
   
      IF p_result_info IS NOT NULL THEN
         p_error_count := 1;
         p_create := FALSE;
         CALL mi_logger.info(
            p_logger_name   => cPkg_Name,
            p_message_text  => p_result_info,
            p_inf_id        => CASE p_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END,
            p_icusnum       => p_icusnum
         );
         CALL mi_logger.exit_f(
            p_logger_name   => cPkg_Name,
            p_message_text  => 'create = FALSE, reason: ' || p_result_info,
            p_inf_id        => CASE p_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END
         );
         RETURN;
      END IF;
   
      -- 2. Проверка существующих запросов
      FOR r IN c_data LOOP
         l_ncount := l_ncount + 1;
   
         IF r.status_cd = 0 THEN
            -- уже есть подготовленный запрос, ещё не отправлен
            l_doCreate := FALSE;
            p_result_info := 'Для клиента ' || p_icusnum || ' уже есть подготовленный запрос (тип ' || p_cus_type || ')';
   
         ELSIF r.status_cd = 1 AND r.ires_code IS NULL THEN
            -- успешно выполнен, но результат не зафиксирован
            l_doCreate := FALSE;
            p_result_info := 'Для клиента ' || p_icusnum || ' есть успешный запрос с незавершённой обработкой результата';
   
         ELSIF r.status_cd = 1 AND r.ires_code = 1 THEN
            -- сведения не найдены
            IF NOT p_handle_not_found THEN
               l_doCreate := FALSE;
               p_result_info := 'Для клиента ' || p_icusnum || ' есть запрос со статусом "сведения не найдены"';
            END IF;
   
         ELSIF r.status_cd IN (2, 3) THEN
            -- запрос в обработке: удаляем, если превышен таймаут
            IF (EXTRACT(EPOCH FROM CURRENT_TIMESTAMP - r.created_at) / 3600) > p_wait_hour_range THEN
               CALL mi_logger.info(
                  p_logger_name   => cPkg_Name,
                  p_message_text  => 'Удаляем подвисший запрос для клиента ' || p_icusnum,
                  p_inf_id        => CASE p_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END,
                  p_icusnum       => p_icusnum
               );
               p_ids4remove := array_append(p_ids4remove, r.itm_id);
            ELSE
               l_doCreate := FALSE;
            END IF;
   
         ELSIF r.status_cd = -1 THEN
            -- ошибочный запрос – удаляем и создаём новый
            CALL mi_logger.info(
               p_logger_name   => cPkg_Name,
               p_message_text  => 'Удаляем ошибочный запрос для клиента ' || p_icusnum,
               p_inf_id        => CASE p_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END,
               p_icusnum       => p_icusnum
            );
            p_ids4remove := array_append(p_ids4remove, r.itm_id);
         END IF;
      END LOOP;
   
      IF p_result_info IS NOT NULL THEN
         CALL mi_logger.info(
            p_logger_name   => cPkg_Name,
            p_message_text  => p_result_info,
            p_inf_id        => CASE p_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END,
            p_icusnum       => p_icusnum
         );
      END IF;
   
      IF l_ncount > 0 THEN
         CALL mi_logger.info(
            p_logger_name   => cPkg_Name,
            p_message_text  => 'Для клиента ' || p_icusnum || ' было ' || l_ncount || ' записей запросов (тип ' || p_cus_type || ')',
            p_inf_id        => CASE p_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END,
            p_icusnum       => p_icusnum
         );
      END IF;
   
      p_create := l_doCreate;
   
      CALL mi_logger.exit_f(
         p_logger_name   => cPkg_Name,
         p_message_text  => format('create = %s, ids4remove = %s, reason: %s',
                                   p_create, array_length(p_ids4remove, 1), COALESCE(p_result_info, 'OK')),
         p_inf_id        => CASE p_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END
      );
   END;
   $$
   
   CREATE OR REPLACE PROCEDURE mi_0003_api.create_personal_item(
      IN  p_req_id       NUMERIC,
      IN  p_icusnum      NUMERIC,
      OUT p_itm_id       NUMERIC,
      OUT p_res_code     INTEGER,
      OUT p_res_info     VARCHAR,
      IN  p_ogrn         VARCHAR DEFAULT NULL,
      IN  p_inn          VARCHAR DEFAULT NULL
   ) AS $$
      #package
   DECLARE
      l_cus_type INTEGER;
      l_inf_id   NUMERIC;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => cPkg_Name,
         p_function_name => 'create_personal_item',
         p_message_text  => format('req_id=%s, icusnum=%s, ogrn=%s, inn=%s', p_req_id, p_icusnum, p_ogrn, p_inn),
         p_inf_id        => NULL
      );
   
      p_res_code := RET_FAIL;
      p_itm_id   := NULL;
   
      -- Определение типа субъекта по длине ОГРН/ИНН
      IF p_ogrn IS NOT NULL THEN
         IF length(p_ogrn) = 13 THEN
            l_cus_type := 2;           -- ЮЛ
         ELSIF length(p_ogrn) = 15 THEN
            l_cus_type := 4;           -- ИП
         ELSE
            p_res_info := 'Некорректная длина ОГРН: ' || length(p_ogrn);
            CALL mi_logger.error(p_logger_name => cPkg_Name, p_message_text => p_res_info, p_inf_id => NULL);
            RETURN;
         END IF;
      ELSIF p_inn IS NOT NULL THEN
         IF length(p_inn) = 10 THEN
            l_cus_type := 2;
         ELSIF length(p_inn) = 12 THEN
            l_cus_type := 4;
         ELSE
            p_res_info := 'Некорректная длина ИНН: ' || length(p_inn);
            CALL mi_logger.error(p_logger_name => cPkg_Name, p_message_text => p_res_info, p_inf_id => NULL);
            RETURN;
         END IF;
      ELSE
         p_res_info := 'Не указаны ни ОГРН, ни ИНН';
         CALL mi_logger.error(p_logger_name => cPkg_Name, p_message_text => p_res_info, p_inf_id => NULL);
         RETURN;
      END IF;
   
      -- Дополнительная проверка согласованности, если заданы оба реквизита
      IF p_ogrn IS NOT NULL AND p_inn IS NOT NULL THEN
         IF (l_cus_type = 2 AND (length(p_inn) != 10)) OR
            (l_cus_type = 4 AND (length(p_inn) != 12)) THEN
            p_res_info := 'ОГРН и ИНН не соответствуют одному типу субъекта';
            CALL mi_logger.error(p_logger_name => cPkg_Name, p_message_text => p_res_info, p_inf_id => NULL);
            RETURN;
         END IF;
      END IF;
   
      l_inf_id := CASE l_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END;
   
      p_itm_id := mi_0003_api.create_item(
         p_inf_id     => l_inf_id,
         p_req_id     => p_req_id,
         p_icusnum    => p_icusnum,
         p_cus_type   => l_cus_type,
         p_ogrn       => p_ogrn,
         p_inn        => p_inn,
         p_ids4remove => NULL
      );
   
      p_res_code := RET_OK;
      p_res_info := NULL;
   
      CALL mi_logger.exit_f(
         p_logger_name   => cPkg_Name,
         p_message_text  => format('res_code=%s, itm_id=%s', p_res_code, p_itm_id),
         p_inf_id        => l_inf_id
      );
   EXCEPTION
      WHEN OTHERS THEN
         p_res_code := RET_FAIL;
         p_res_info := SQLERRM;
         CALL mi_logger.error(
            p_logger_name   => cPkg_Name,
            p_message_text  => 'Ошибка в create_personal_item',
            p_details_text  => SQLERRM,
            p_inf_id        => NULL
         );
   END;
   $$

   /*
   CREATE OR REPLACE PROCEDURE mi_0003_api.create_personal_request(
      IN  p_icusnum       NUMERIC,
      IN  p_cus_type      INTEGER,
      OUT p_req_id        NUMERIC,
      OUT p_itm_id        NUMERIC,
      OUT p_res_code      INTEGER,
      OUT p_res_info      VARCHAR,
      IN  p_ogrn          VARCHAR DEFAULT NULL,
      IN  p_inn           VARCHAR DEFAULT NULL,
      IN  p_person_id     NUMERIC DEFAULT NULL
   ) AS $$
      #package
   DECLARE
      l_handle_not_found BOOLEAN := MI_prp.get_Wsp_Property(1, 'HANDLE_NOT_FOUND', 'false')::BOOLEAN;
      l_wait_hour_range  INTEGER := 72;
      l_doCreate         BOOLEAN := FALSE;
      l_ids4Remove       NUMERIC[];
      l_error_Count      INTEGER := 0;
      l_info             VARCHAR;
      l_inf_id           NUMERIC;
   
      -- блокировка
      l_lock_Handle      VARCHAR(100);
      l_lock_Code        INTEGER;
      l_lock_Info        VARCHAR(4000);
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => cPkg_Name,
         p_function_name => 'create_personal_request',
         p_message_text  => format('icusnum=%s, cus_type=%s, ogrn=%s, inn=%s', p_icusnum, p_cus_type, p_ogrn, p_inn),
         p_inf_id        => CASE p_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END
      );
   
      p_res_code := RET_FAIL;
      p_req_id   := NULL;
      p_itm_id   := NULL;
   
      -- Захват сессионной блокировки
      CALL MI_utils.lock_Proc(c_Lock_Name, false, 0, l_lock_Code, l_lock_Info, l_lock_Handle);
      IF l_lock_Code <> RET_OK THEN
         IF l_lock_Code = 1 THEN
            p_res_code := RET_LOCK;
            p_res_info := 'Блокировка уже захвачена другой сессией';
            CALL mi_logger.info(
               p_logger_name   => cPkg_Name,
               p_message_text  => p_res_info,
               p_inf_id        => CASE p_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END
            );
            RETURN;
         ELSE
            p_res_code := RET_FAIL;
            p_res_info := 'Ошибка при получении блокировки: ' || COALESCE(l_lock_Info, 'неизвестная ошибка');
            CALL mi_logger.error(
               p_logger_name   => cPkg_Name,
               p_message_text  => p_res_info,
               p_inf_id        => CASE p_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END
            );
            RETURN;
         END IF;
      END IF;
   
      BEGIN
         l_inf_id := CASE p_cus_type WHEN 2 THEN c_Inf_Id_UL ELSE c_Inf_Id_IP END;
   
         -- Проверка возможности создания
         CALL mi_0003_api.check_4_prepare(
            p_icusnum           => p_icusnum,
            p_cus_type          => p_cus_type,
            p_ogrn              => p_ogrn,
            p_inn               => p_inn,
            p_handle_not_found  => l_handle_not_found,
            p_wait_hour_range   => l_wait_hour_range,
            p_create            => l_doCreate,
            p_ids4remove        => l_ids4Remove,
            p_error_count       => l_error_Count,
            p_result_info       => l_info
         );
   
         IF l_doCreate THEN
            p_req_id := mi_0003_api.create_request(p_cus_type);
            p_itm_id := mi_0003_api.create_item(
                           p_inf_id     => l_inf_id,
                           p_req_id     => p_req_id,
                           p_icusnum    => p_icusnum,
                           p_cus_type   => p_cus_type,
                           p_ogrn       => p_ogrn,
                           p_inn        => p_inn,
                           p_person_id  => p_person_id,
                           p_ids4remove => l_ids4Remove
                        );
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
               p_res_info := TS.WhenOthersError('mi_0003_api.create_personal_request', ex);
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
         p_logger_name   => cPkg_Name,
         p_message_text  => format('ret_code = %s, req_id = %s, itm_id = %s', p_res_code, p_req_id, p_itm_id),
         p_inf_id        => l_inf_id
      );
   END;
   $$
   */
   
   -- Вспомогательная функция для построения JSON персоны (для ИП)
   /*
   CREATE FUNCTION mi_0003_api.build_json_person(p_cus v_mi_0003_ca) RETURNS JSONB AS $$
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
   */

   -- Автоматический сбор данных по клиентам, требующим обновления ЕГРЮЛ/ЕГРИП
   /*
   CREATE OR REPLACE PROCEDURE mi_0003_api.auto_prepare(
      OUT p_ret_code INTEGER,
      OUT p_ret_info VARCHAR
   ) AS $$
      #package
   DECLARE
      l_lock_Handle       VARCHAR(100);
      l_lock_Code         INTEGER;
      l_lock_Info         VARCHAR(4000);
   
      l_handle_not_found  BOOLEAN := MI_prp.get_Wsp_Property(1, 'HANDLE_NOT_FOUND', 'false')::BOOLEAN;
      l_wait_hour_range   INTEGER := 72;
   
      l_has_data          BOOLEAN;
   
      l_req_id_ul         NUMERIC;
      l_req_id_ip         NUMERIC;
      l_ttl_ul            INTEGER := 0;
      l_suc_ul            INTEGER := 0;
      l_ttl_ip            INTEGER := 0;
      l_suc_ip            INTEGER := 0;
   
      l_doCreate          BOOLEAN;
      l_ids4Remove        NUMERIC[];
      l_error_Count       INTEGER;
      l_result_Info       VARCHAR(4000);
   
      l_person_id         NUMERIC;
      l_json_person       JSONB;
   
      r                   v_mi_0003_ca%ROWTYPE;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => cPkg_Name,
         p_function_name => 'auto_prepare',
         p_message_text  => 'Начало автоматического сбора данных ЕГРЮЛ/ЕГРИП',
         p_inf_id        => c_Inf_Id_UL   -- можно любой, т.к. далее будут использоваться конкретные
      );
   
      -- Проверка наличия данных
      SELECT EXISTS (SELECT 1 FROM xxi.v_mi_0003_ca) INTO l_has_data;
      IF NOT l_has_data THEN
         p_ret_code := RET_NO_DATA;
         p_ret_info := 'Нет данных для отправки';
         CALL mi_logger.info(
            p_logger_name   => cPkg_Name,
            p_message_text  => p_ret_info,
            p_inf_id        => c_Inf_Id_UL
         );
         CALL mi_logger.exit_f(
            p_logger_name   => cPkg_Name,
            p_message_text  => 'auto_prepare: ' || p_ret_info,
            p_inf_id        => c_Inf_Id_UL
         );
         RETURN;
      END IF;
   
      -- Захват блокировки
      CALL MI_utils.lock_Proc(c_Lock_Name, false, 0, l_lock_Code, l_lock_Info, l_lock_Handle);
      IF l_lock_Code <> RET_OK THEN
         IF l_lock_Code = 1 THEN
            p_ret_code := RET_LOCK;
            p_ret_info := 'Блокировка уже захвачена другой сессией';
            CALL mi_logger.info(
               p_logger_name   => cPkg_Name,
               p_message_text  => p_ret_info,
               p_inf_id        => c_Inf_Id_UL
            );
            RETURN;
         ELSE
            p_ret_code := RET_FAIL;
            p_ret_info := 'Ошибка при получении блокировки: ' || COALESCE(l_lock_Info, 'неизвестная ошибка');
            CALL mi_logger.error(
               p_logger_name   => cPkg_Name,
               p_message_text  => p_ret_info,
               p_inf_id        => c_Inf_Id_UL
            );
            RETURN;
         END IF;
      END IF;
   
      -- Обработка юридических лиц (cus_type = 2)
      SELECT EXISTS (SELECT 1 FROM xxi.v_mi_0003_ca WHERE cus_type = 2) INTO l_has_data;
      IF l_has_data THEN
         l_req_id_ul := mi_0003_api.create_request(2);
         CALL mi_logger.variable_value(
            p_logger_name   => cPkg_Name,
            p_variable_name => 'req_id_UL',
            p_value_text    => l_req_id_ul::VARCHAR,
            p_inf_id        => c_Inf_Id_UL
         );
   
         FOR r IN (SELECT * FROM xxi.v_mi_0003_ca WHERE cus_type = 2) LOOP
            l_ttl_ul := l_ttl_ul + 1;
            BEGIN
               CALL mi_0003_api.check_4_prepare(
                  p_icusnum           => r.icusnum,
                  p_cus_type          => 2,
                  p_ogrn              => r.ogrn,
                  p_inn               => r.inn,
                  p_handle_not_found  => l_handle_not_found,
                  p_wait_hour_range   => l_wait_hour_range,
                  p_create            => l_doCreate,
                  p_ids4remove        => l_ids4Remove,
                  p_error_count       => l_error_Count,
                  p_result_info       => l_result_Info
               );
   
               IF l_doCreate THEN
                  PERFORM mi_0003_api.create_item(
                     p_inf_id     => c_Inf_Id_UL,
                     p_req_id     => l_req_id_ul,
                     p_icusnum    => r.icusnum,
                     p_cus_type   => 2,
                     p_ogrn       => r.ogrn,
                     p_inn        => r.inn,
                     p_person_id  => NULL,
                     p_ids4remove => l_ids4Remove
                  );
                  l_suc_ul := l_suc_ul + 1;
               END IF;
            EXCEPTION
               WHEN OTHERS THEN
                  CALL mi_logger.error(
                     p_logger_name   => cPkg_Name,
                     p_message_text  => 'Ошибка при обработке ЮЛ клиента ' || r.icusnum,
                     p_details_text  => SQLERRM,
                     p_inf_id        => c_Inf_Id_UL,
                     p_icusnum       => r.icusnum
                  );
            END;
         END LOOP;
      END IF;

      -- Обработка индивидуальных предпринимателей (cus_type = 4)
      SELECT EXISTS (SELECT 1 FROM xxi.v_mi_0003_ca WHERE cus_type = 4) INTO l_has_data;
      IF l_has_data THEN
         l_req_id_ip := mi_0003_api.create_request(4);
         CALL mi_logger.variable_value(
            p_logger_name   => cPkg_Name,
            p_variable_name => 'req_id_IP',
            p_value_text    => l_req_id_ip::VARCHAR,
            p_inf_id        => c_Inf_Id_IP
         );
   
         FOR r IN (SELECT * FROM xxi.v_mi_0003_ca WHERE cus_type = 4) LOOP
            l_ttl_ip := l_ttl_ip + 1;
            BEGIN
               CALL mi_0003_api.check_4_prepare(
                  p_icusnum           => r.icusnum,
                  p_cus_type          => 4,
                  p_ogrn              => r.ogrn,
                  p_inn               => r.inn,
                  p_handle_not_found  => l_handle_not_found,
                  p_wait_hour_range   => l_wait_hour_range,
                  p_create            => l_doCreate,
                  p_ids4remove        => l_ids4Remove,
                  p_error_count       => l_error_Count,
                  p_result_info       => l_result_Info
               );
         
               IF l_doCreate THEN
                  --l_json_person := mi_0003_api.build_json_person(r);
                  --l_person_id := MI_person_Api.get_Or_Create(
                  --   p_inf_id   => c_Inf_Id_IP,
                  --   p_person_J => l_json_person
                  --);

                  l_person_id := NULL;
         
                  PERFORM mi_0003_api.create_item(
                     p_inf_id     => c_Inf_Id_IP,
                     p_req_id     => l_req_id_ip,
                     p_icusnum    => r.icusnum,
                     p_cus_type   => 4,
                     p_ogrn       => r.ogrn,
                     p_inn        => r.inn,
                     p_person_id  => l_person_id,
                     p_ids4remove => l_ids4Remove
                  );
                  l_suc_ip := l_suc_ip + 1;
               END IF;
            EXCEPTION
               WHEN OTHERS THEN
                  CALL mi_logger.error(
                     p_logger_name   => cPkg_Name,
                     p_message_text  => 'Ошибка при обработке ИП клиента ' || r.icusnum,
                     p_details_text  => SQLERRM,
                     p_inf_id        => c_Inf_Id_IP,
                     p_icusnum       => r.icusnum
                  );
            END;
         END LOOP;
      END IF;
   
      -- Итоговое логирование
      CALL mi_logger.info(
         p_logger_name   => cPkg_Name,
         p_message_text  => 'Автосбор завершён. ЮЛ: всего ' || l_ttl_ul || ', успешно ' || l_suc_ul ||
                            '; ИП: всего ' || l_ttl_ip || ', успешно ' || l_suc_ip,
         p_inf_id        => c_Inf_Id_UL
      );
   
      -- Освобождение блокировки
      IF l_lock_Handle IS NOT NULL THEN
         DECLARE
            l_rel_ret  INTEGER;
            l_rel_info VARCHAR(4000);
         BEGIN
            CALL MI_utils.lock_release(l_lock_Handle, l_rel_ret, l_rel_info);
            CALL mi_logger.variable_value(
               p_logger_name   => cPkg_Name,
               p_variable_name => 'lock_release',
               p_value_text    => l_rel_ret::VARCHAR,
               p_inf_id        => c_Inf_Id_UL
            );
         EXCEPTION WHEN OTHERS THEN NULL;
         END;
      END IF;
   
      p_ret_code := RET_OK;
      p_ret_info := NULL;
   
      CALL mi_logger.exit_f(
         p_logger_name   => cPkg_Name,
         p_message_text  => 'auto_prepare завершён успешно',
         p_inf_id        => c_Inf_Id_UL
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
            p_logger_name   => cPkg_Name,
            p_message_text  => 'Критическая ошибка в auto_prepare',
            p_details_text  => SQLERRM,
            p_inf_id        => c_Inf_Id_UL
         );
         RETURN;
   END;
   $$
   */
   
   CREATE OR REPLACE PROCEDURE mi_0003_api.apply_item_result(
      IN p_request_uuid    UUID,
      IN p_message_uuid    UUID,
      IN p_item_uuid       UUID,
      IN p_response_kind   INTEGER,
      IN p_response_code   VARCHAR,
      IN p_response_info   VARCHAR,
      IN p_response_details TEXT,
      IN p_response_time   TIMESTAMPTZ,
      IN p_payload_text    TEXT,
      OUT p_ret_code       INTEGER,
      OUT p_ret_info       VARCHAR
   ) AS $$
      #package
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => cPkg_Name,
         p_function_name => 'apply_item_result',
         p_message_text  => 'item_uuid=' || p_item_uuid,
         p_inf_id        => c_Inf_Id_UL
      );
   
      p_ret_code := RET_FAIL;
      p_ret_info := NULL;
   
      BEGIN
         UPDATE xxi.mi_0003 i
            SET payload      = p_payload_text,
                ires_code    = 0,
                cres_info    = NULL,
                tres_time    = COALESCE(p_response_time, clock_timestamp()),
                message_uuid = p_message_uuid
          WHERE i.external_uuid = p_item_uuid;
   
         IF NOT FOUND THEN
            p_ret_info := 'Элемент с external_uuid=' || p_item_uuid || ' не найден';
            CALL mi_logger.error(
               p_logger_name   => cPkg_Name,
               p_message_text  => p_ret_info,
               p_inf_id        => NULL
            );
            RETURN;
         END IF;
   
         p_ret_code := RET_OK;
      EXCEPTION
         WHEN OTHERS THEN
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => cPkg_Name,
               p_message_text  => 'Ошибка в apply_item_result',
               p_details_text  => SQLERRM,
               p_inf_id        => NULL
            );
      END;
   
      CALL mi_logger.exit_f(
         p_logger_name   => cPkg_Name,
         p_message_text  => 'ret_code=' || p_ret_code || ', ret_info=' || COALESCE(p_ret_info, 'OK'),
         p_inf_id        => NULL
      );
   END;
   $$
;
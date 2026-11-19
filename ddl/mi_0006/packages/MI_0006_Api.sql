CREATE OR REPLACE PACKAGE mi_0006_api

   -- Инициализация пакета
   CREATE FUNCTION __init__() RETURNS void AS $$
   DECLARE
      /*
         Пакет для ведения логики MI-edo
         Модуль: ГИС ГМП (вид сведений 0006)
      */
      cVersion    CONSTANT VARCHAR(100) := '$id: {1.0.1} {18.11.2026} Sukhotina$';

      RET_OK      CONSTANT INTEGER := 0;
      RET_FAIL    CONSTANT INTEGER := -1;
      RET_LOCK    CONSTANT INTEGER := 3;

      c_Inf_Id    CONSTANT NUMERIC := 61;
      cPkg_Name   CONSTANT VARCHAR(20) := 'mi_0006_api';
      c_Logger    CONSTANT VARCHAR(20) := 'mi.0006';
      c_Lock_Name CONSTANT VARCHAR(20) := 'mi_0006_auto';
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
      p_itype integer DEFAULT 1
   ) RETURNS NUMERIC AS $$
      #package
      --#private
   BEGIN
      IF p_itype IS NULL OR p_itype NOT IN (1, 2, 3) THEN
         RAISE EXCEPTION 'Недопустимый p_itype: % (допустимо 1-Добавление, 2-Изменение, 3-Удаление)', p_itype;
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
      p_itrnnum   numeric,
      p_itrnanum  numeric,
      p_dtrndate  timestamptz
   ) RETURNS numeric AS $$
      #package
      --#private
   DECLARE
      l_itm_id numeric;
   BEGIN
      l_itm_id := MI_request_Api.next_Itm_Id();

      INSERT INTO xxi.mi_0006 (
         itm_id,
         req_id,
         istate,
         itrnnum,
         itrnanum,
         dtrndate
      ) VALUES (
         l_itm_id,
         p_req_id,
         0,
         p_itrnnum,
         p_itrnanum,
         p_dtrndate
      );

      RETURN l_itm_id;
   END;
   $$

   -- Автоматическая генерация пачек платежей ГИС ГМП
   CREATE PROCEDURE auto_generate(
      IN  p_dbeg          date,
      IN  p_dend          date,
      OUT p_req_id        numeric,
      OUT p_items_created int,
      OUT p_ret_code      int,
      OUT p_ret_info      varchar
   ) AS $$
      #package
   DECLARE
      c_Action_Name CONSTANT VARCHAR(100) := cPkg_Name || '.auto_generate';

      l_lock_Handle    varchar(100);
      l_lock_Code      int;
      l_lock_Info      varchar(4000);

      l_req_id         numeric;
      l_count          int := 0;
      l_skip_count     int := 0;
      l_err_count      int := 0;

      l_predicate      varchar(4000);
      l_sql            text;

      l_check_for_s    varchar(20);
      l_check_val      numeric;

      l_payment_date_s varchar(50);
      l_payment_date   timestamptz;

      l_dbeg_ts        timestamptz;
      l_dend_ts        timestamptz;

      r                record;
   BEGIN
      CALL mi_logger.enter_f(
         p_logger_name   => c_Logger,
         p_function_name => c_Action_Name,
         p_message_text  => format('p_dbeg=%s, p_dend=%s', p_dbeg, p_dend),
         p_inf_id        => c_Inf_Id
      );

      p_req_id        := NULL;
      p_items_created := 0;
      p_ret_code      := RET_FAIL;
      p_ret_info      := NULL;

      BEGIN

         IF p_dbeg IS NULL OR p_dend IS NULL THEN
            p_ret_info := 'p_dbeg or p_dend is null';
            RETURN;
         END IF;

         IF p_dbeg > p_dend THEN
            p_ret_info := 'p_dbeg > p_dend';
            RETURN;
         END IF;

         -- Границы интервала как в Oracle: с начала p_dbeg до конца p_dend
         l_dbeg_ts := p_dbeg::timestamptz;
         l_dend_ts := (p_dend::date + interval '1 day' - interval '1 second')::timestamptz;

         -- Блокировка процесса автогенерации
         CALL mi_utils.lock_Proc(
            c_Lock_Name, false, 0, l_lock_Code, l_lock_Info, l_lock_Handle
         );

         IF l_lock_Code <> RET_OK THEN
            IF l_lock_Code = 1 THEN
               p_ret_code := RET_LOCK;
               p_ret_info := 'Уже идет процесс автогенерации платежей';
            ELSE
               p_ret_info := 'Ошибка получения блокировки: ' || coalesce(l_lock_Info, 'unknown');
            END IF;

            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'lock failed: ' || p_ret_info,
               p_inf_id        => c_Inf_Id
            );
            RETURN;
         END IF;

         -- Создание контейнера запроса (itype = 1 - добавление)
         l_req_id := mi_0006_api.create_request(1);

         CALL mi_logger.variable_value(
            p_logger_name   => c_Logger,
            p_variable_name => 'req_id',
            p_value_text    => l_req_id::varchar,
            p_inf_id        => c_Inf_Id,
            p_req_id        => l_req_id
         );

         -- Предикат отбора от ФПЗ (может быть пустым)
         BEGIN
            l_predicate := ac.get_value2(
               cdefint  => 'SMEV.GISGMP.PAYMENTS.AUTO.Predicate',
               tabparam => ARRAY[]::varchar[]
            );

            CALL mi_logger.variable_value(
               p_logger_name   => c_Logger,
               p_variable_name => 'predicate.length',
               p_value_text    => coalesce(length(l_predicate), 0)::varchar,
               p_inf_id        => c_Inf_Id,
               p_req_id        => l_req_id
            );
         EXCEPTION
            WHEN OTHERS THEN
               p_ret_info := 'Ошибка при вызове ФПЗ SMEV.GISGMP.PAYMENTS.AUTO.Predicate: ' || SQLERRM;
               CALL mi_logger.error(
                  p_logger_name   => c_Logger,
                  p_message_text  => p_ret_info,
                  p_inf_id        => c_Inf_Id,
                  p_req_id        => l_req_id
               );
               RETURN;
         END;

         -- Динамический отбор документов:
         --   - не обрабатываем то, что уже есть в mi_0006;
         --   - ограничиваем по дате проводки;
         --   - добавляем ФПЗ-предикат, если он задан.
         l_sql :=
            'SELECT t.itrnnum, t.itrnanum FROM xxi.trn_mf t '
            ' WHERE NOT EXISTS ( '
            '     SELECT 1 FROM xxi.mi_0006 x '
            '      WHERE x.itrnnum = t.itrnnum '
            '        AND x.itrnanum = t.itrnanum '
            ' ) '
            ' AND t.dtrntran BETWEEN ' || quote_literal(l_dbeg_ts) || ' AND ' || quote_literal(l_dend_ts);

         IF l_predicate IS NOT NULL AND btrim(l_predicate) <> '' THEN
            l_sql := l_sql || ' AND ( ' || l_predicate || ' )';
         END IF;

         CALL mi_logger.info(
            p_logger_name   => c_Logger,
            p_message_text  => 'отбор документов',
            p_details_text  => left(l_sql, 2000),
            p_inf_id        => c_Inf_Id,
            p_req_id        => l_req_id
         );

         FOR r IN EXECUTE l_sql
         LOOP

            -- ФПЗ: нужен ли документ
            BEGIN
               l_check_for_s := ac.get_value2(
                  cdefint  => 'SMEV.GISGMP.PAYMENTS.CHECK.CheckFor',
                  tabparam => ARRAY[r.itrnnum::varchar, r.itrnanum::varchar, '1'::varchar],
                  ctype    => 'N'
               );

               l_check_val := NULLIF(l_check_for_s, '')::numeric;
            EXCEPTION
               WHEN OTHERS THEN
                  l_err_count := l_err_count + 1;
                  CALL mi_logger.error(
                     p_logger_name   => c_Logger,
                     p_message_text  => format('Ошибка ФПЗ SMEV.GISGMP.PAYMENTS.CHECK.CheckFor для документа (itrnnum=%s, itrnanum=%s): %s',
                                               r.itrnnum, r.itrnanum, SQLERRM),
                     p_inf_id        => c_Inf_Id,
                     p_req_id        => l_req_id
                  );
                  CONTINUE;
            END;

            IF coalesce(l_check_val, 0) <= 0 THEN
               l_skip_count := l_skip_count + 1;
               CONTINUE;
            END IF;

            -- ФПЗ: дата платежа
            BEGIN
               l_payment_date_s := ac.get_value2(
                  cdefint  => 'SMEV.GIS.PAY.GET.PaymentDate',
                  tabparam => ARRAY[r.itrnnum::varchar, r.itrnanum::varchar]
               );

               l_payment_date := to_timestamp(l_payment_date_s, 'DD.MM.YYYY HH24:MI:SS');
            EXCEPTION
               WHEN OTHERS THEN
                  l_err_count := l_err_count + 1;
                  CALL mi_logger.error(
                     p_logger_name   => c_Logger,
                     p_message_text  => format('Ошибка ФПЗ SMEV.GIS.PAY.GET.PaymentDate для документа (itrnnum=%s, itrnanum=%s): %s',
                                               r.itrnnum, r.itrnanum, SQLERRM),
                     p_inf_id        => c_Inf_Id,
                     p_req_id        => l_req_id
                  );
                  CONTINUE;
            END;

            PERFORM mi_0006_api.create_item(
               p_req_id   => l_req_id,
               p_itrnnum  => r.itrnnum,
               p_itrnanum => r.itrnanum,
               p_dtrndate => l_payment_date
            );

            l_count := l_count + 1;

         END LOOP;

         p_req_id        := l_req_id;
         p_items_created := l_count;
         p_ret_code      := RET_OK;
         p_ret_info      := format('Создано=%s, пропущено=%s, ошибок=%s, req_id=%s',
                                   l_count, l_skip_count, l_err_count, l_req_id);

         CALL mi_logger.info(
            p_logger_name   => c_Logger,
            p_message_text  => p_ret_info,
            p_inf_id        => c_Inf_Id,
            p_req_id        => l_req_id
         );

      EXCEPTION
         WHEN OTHERS THEN
            p_ret_code := RET_FAIL;
            p_ret_info := SQLERRM;
            CALL mi_logger.error(
               p_logger_name   => c_Logger,
               p_message_text  => 'Ошибка в auto_generate',
               p_details_text  => SQLERRM,
               p_inf_id        => c_Inf_Id
            );
      END;

      -- Освобождение блокировки
      IF l_lock_Handle IS NOT NULL THEN
         DECLARE
            l_rel_ret  integer;
            l_rel_info varchar(4000);
         BEGIN
            CALL MI_utils.lock_release(l_lock_Handle, l_rel_ret, l_rel_info);
         EXCEPTION WHEN OTHERS THEN NULL;
         END;
      END IF;

      CALL mi_logger.exit_f(
         p_logger_name   => c_Logger,
         p_message_text  => format('ret_code=%s, info=%s', p_ret_code, p_ret_info),
         p_inf_id        => c_Inf_Id,
         p_req_id        => p_req_id
      );
   END;
   $$

;
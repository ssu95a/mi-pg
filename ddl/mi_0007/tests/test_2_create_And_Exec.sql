BEGIN;
DO $$
DECLARE
   l_limit      int := 100;
   l_i          int := 0;
   l_created    int := 0;
   l_failed     int := 0;
   l_dedup      int := 0;   -- сработал has_Entry_Set (уже есть свежий)
   r            record;
   l_res_code   int;
   l_req_id     numeric;
   l_itm_id     numeric;
   l_iState     numeric;
   l_result     varchar;
   l_t_start    timestamptz;
   l_t_end      timestamptz;
   l_t_call_max interval := '0 second'::interval;
   l_ic_max     numeric  := null;
   l_before_itm int;
   l_after_itm  int;
   l_before_req int;
   l_after_req  int;
BEGIN
   RAISE NOTICE '============ Тест 2: Нагрузка create_And_Exec (p_do_send=false) ============';
   RAISE NOTICE 'Лимит: % клиентов с действующим паспортом РФ', l_limit;

   SELECT count(*) INTO l_before_itm FROM xxi.mi_0007;
   SELECT count(*) INTO l_before_req FROM xxi.mi_req WHERE inf_id = 74;

   l_t_start := clock_timestamp();

   FOR r IN (
      SELECT c.icusnum,
             c.ccuslast_name   AS last_name,
             c.ccusfirst_name  AS first_name,
             c.ccusmiddle_name AS middle_name,
             c.dcusbirthday    AS birth_date,
             d.doc_ser,
             d.doc_num,
             d.doc_date        AS doc_issue_date
        FROM xxi."CUS" c
        JOIN LATERAL (
             SELECT b.doc_ser, b.doc_num, b.doc_date
               FROM xxi.cus_docum b
              WHERE b.icusnum = c.icusnum
                AND b.id_doc_tp = (SELECT pud.ipudid FROM xxi.pud WHERE pud.ipudint_code = 1)
                AND (b.doc_period IS NULL OR b.doc_period >= CURRENT_DATE)
              ORDER BY (b.pref = 'Y') DESC, b.doc_date DESC NULLS LAST, b.id_doc DESC
              LIMIT 1
        ) d ON true
       WHERE c.ccusflag IN ('1','4')
       LIMIT l_limit
   ) LOOP
      l_i := l_i + 1;

      DECLARE
         l_tc_start timestamptz := clock_timestamp();
         l_tc_end   timestamptz;
      BEGIN
         CALL mi_0007_api.create_And_Exec(
            p_inf_id         => 74,
            p_icusnum        => r.icusnum,
            p_last_name      => r.last_name,
            p_first_name     => r.first_name,
            p_middle_name    => r.middle_name,
            p_birth_date     => r.birth_date,
            p_doc_ser        => r.doc_ser,
            p_doc_num        => r.doc_num,
            p_doc_issue_date => r.doc_issue_date,
            p_region_code    => NULL,
            p_time_out       => 0,
            p_do_send        => false,
            p_res_code       => l_res_code,
            p_req_id         => l_req_id,
            p_itm_id         => l_itm_id,
            p_iState         => l_iState,
            p_result_info    => l_result
         );
         l_tc_end := clock_timestamp();

         IF (l_tc_end - l_tc_start) > l_t_call_max THEN
            l_t_call_max := l_tc_end - l_tc_start;
            l_ic_max     := r.icusnum;
         END IF;

         IF l_res_code = 0 THEN
            l_created := l_created + 1;
         ELSE
            l_failed := l_failed + 1;
            IF l_i <= 10 THEN
               RAISE NOTICE 'FAILED #%: icusnum=%, res_code=%, info=%',
                            l_i, r.icusnum, l_res_code, l_result;
            END IF;
         END IF;
      EXCEPTION WHEN OTHERS THEN
         l_failed := l_failed + 1;
         IF l_i <= 10 THEN
            RAISE NOTICE 'EXCEPTION #%: icusnum=%, err=%',
                         l_i, r.icusnum, SQLERRM;
         END IF;
      END;
   END LOOP;

   l_t_end := clock_timestamp();

   SELECT count(*) INTO l_after_itm FROM xxi.mi_0007;
   SELECT count(*) INTO l_after_req FROM xxi.mi_req WHERE inf_id = 74;

   RAISE NOTICE 'Итог:';
   RAISE NOTICE '  обработано = %', l_i;
   RAISE NOTICE '  успешно    = %', l_created;
   RAISE NOTICE '  ошибок     = %', l_failed;
   RAISE NOTICE '  прирост mi_0007 = %, mi_req(74) = %',
                l_after_itm - l_before_itm, l_after_req - l_before_req;
   RAISE NOTICE '  всего времени = %', l_t_end - l_t_start;
   RAISE NOTICE '  среднее на вызов = %', (l_t_end - l_t_start) / NULLIF(l_i, 0);
   RAISE NOTICE '  МАКСИМУМ = % (icusnum=%)', l_t_call_max, coalesce(l_ic_max::text, '—');
END $$;
ROLLBACK;
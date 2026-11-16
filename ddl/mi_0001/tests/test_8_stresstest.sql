BEGIN;
DO $$
DECLARE
   l_limit    int := 1000;
   l_i        int := 0;
   l_created  int := 0;
   l_failed   int := 0;
   r          xxi.v_mi_0001_ca%ROWTYPE;
   l_req_id   numeric;
   l_itm_id   numeric;
   l_res_code int;
   l_res_info varchar;
   l_t_start  timestamptz;
   l_t_end    timestamptz;
   l_per_call interval;
   l_max_time interval := '0 second'::interval;
   l_max_ic   numeric  := null;
BEGIN
   RAISE NOTICE '============ Тест 8: Стресс-тест N=% ============', l_limit;

   l_t_start := clock_timestamp();

   FOR r IN (
      SELECT * FROM xxi.v_mi_0001_ca
       WHERE last_name IS NOT NULL AND first_name IS NOT NULL
         AND birth_date IS NOT NULL
         AND doc_type_code IS NOT NULL AND doc_num IS NOT NULL
       LIMIT l_limit
   ) LOOP
      l_i := l_i + 1;
      DECLARE
         l_tc_start timestamptz := clock_timestamp();
         l_tc_end   timestamptz;
      BEGIN
         CALL mi_0001_api.create_Personal_Request(r, l_req_id, l_itm_id,
                                                   l_res_code, l_res_info);
         l_tc_end := clock_timestamp();

         IF (l_tc_end - l_tc_start) > l_max_time THEN
            l_max_time := l_tc_end - l_tc_start;
            l_max_ic   := r.icusnum;
         END IF;

         IF l_res_code = 0 THEN
            l_created := l_created + 1;
         ELSE
            l_failed := l_failed + 1;
            RAISE NOTICE 'FAILED #%: icusnum=%, res_code=%, info=%',
                         l_i, r.icusnum, l_res_code, l_res_info;
         END IF;
      EXCEPTION WHEN OTHERS THEN
         l_failed := l_failed + 1;
         RAISE NOTICE 'EXCEPTION #%: icusnum=%, err=%',
                      l_i, r.icusnum, SQLERRM;
      END;
   END LOOP;

   l_t_end := clock_timestamp();
   l_per_call := (l_t_end - l_t_start) / NULLIF(l_i, 0);

   RAISE NOTICE 'Итог:';
   RAISE NOTICE '  обработано = %', l_i;
   RAISE NOTICE '  успешно    = %', l_created;
   RAISE NOTICE '  ошибок     = %', l_failed;
   RAISE NOTICE '  всего      = %', l_t_end - l_t_start;
   RAISE NOTICE '  среднее    = %', l_per_call;
   RAISE NOTICE '  МАКСИМУМ   = % (icusnum=%)',
                l_max_time, coalesce(l_max_ic::text, '—');
END $$;
ROLLBACK;
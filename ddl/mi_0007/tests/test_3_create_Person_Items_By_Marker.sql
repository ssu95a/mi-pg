BEGIN;
DO $$
DECLARE
   l_marker_id  numeric;
   l_cnt_cli    int;
   l_req_id     numeric;
   l_created    int;
   l_res_code   int;
   l_res_info   varchar;
   l_t_start    timestamptz;
   l_t_end      timestamptz;
   l_before_itm int;
   l_after_itm  int;
BEGIN
   RAISE NOTICE '============ Тест 3: create_Person_Items_By_Marker ============';

   -- Найти маркер с наибольшим числом клиентов
   SELECT m.idmarker, count(*) INTO l_marker_id, l_cnt_cli
     FROM xxi.mrk_id m
     JOIN xxi."CUS" c ON c.icusnum = m.idrow
    WHERE c.ccusflag IN ('1','4')
    GROUP BY m.idmarker
    ORDER BY count(*) DESC
    LIMIT 1;

   IF l_marker_id IS NULL THEN
      RAISE NOTICE 'Нет маркеров с клиентами 1/4 — тест пропущен';
      RETURN;
   END IF;

   RAISE NOTICE 'Маркер: id=%, клиентов с flag 1/4 = %', l_marker_id, l_cnt_cli;

   SELECT count(*) INTO l_before_itm FROM xxi.mi_0007;

   l_t_start := clock_timestamp();

   CALL mi_0007_api.create_Person_Items_By_Marker(
      p_marker_id     => l_marker_id,
      p_req_id        => l_req_id,
      p_created_count => l_created,
      p_res_code      => l_res_code,
      p_res_info      => l_res_info
   );

   l_t_end := clock_timestamp();

   SELECT count(*) INTO l_after_itm FROM xxi.mi_0007;

   RAISE NOTICE 'Итог:';
   RAISE NOTICE '  req_id    = %', coalesce(l_req_id::text, '<NULL>');
   RAISE NOTICE '  создано   = %  (с паспортом: < %)', l_created, l_cnt_cli;
   RAISE NOTICE '  res_code  = %', l_res_code;
   RAISE NOTICE '  res_info  = %', l_res_info;
   RAISE NOTICE '  прирост mi_0007 = %', l_after_itm - l_before_itm;
   RAISE NOTICE '  время     = %', l_t_end - l_t_start;
   RAISE NOTICE '  среднее на элемент = %',
                (l_t_end - l_t_start) / NULLIF(l_created, 0);
END $$;
ROLLBACK;
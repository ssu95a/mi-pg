BEGIN;
DO $$
DECLARE
   l_before_req   int;
   l_before_itm   int;
   l_before_pers  int;
   l_after_req    int;
   l_after_itm    int;
   l_after_pers   int;
   l_err_count    int;
   l_wrn_count    int;
   l_inf_count    int;
   l_t_start      timestamptz;
   l_t_end        timestamptz;
   l_raised       boolean := false;
   l_raised_msg   text;
   r              record;
BEGIN
   RAISE NOTICE '============ Тест 3: Нагрузочный auto_Prepare ============';

   SELECT count(*) INTO l_before_req  FROM xxi.mi_req    WHERE inf_id = 13;
   SELECT count(*) INTO l_before_itm  FROM xxi.mi_0001;
   SELECT count(*) INTO l_before_pers FROM xxi.mi_person;

   RAISE NOTICE 'До:  mi_req(13)=%, mi_0001=%, mi_person=%',
                l_before_req, l_before_itm, l_before_pers;

   l_t_start := clock_timestamp();

   BEGIN
      CALL mi_0001_api.auto_Prepare(false);
   EXCEPTION WHEN OTHERS THEN
      l_raised := true;
      l_raised_msg := SQLERRM;
      RAISE NOTICE '!!! auto_Prepare ВЫБРОСИЛ: %', SQLERRM;
   END;

   l_t_end := clock_timestamp();

   SELECT count(*) INTO l_after_req  FROM xxi.mi_req    WHERE inf_id = 13;
   SELECT count(*) INTO l_after_itm  FROM xxi.mi_0001;
   SELECT count(*) INTO l_after_pers FROM xxi.mi_person;

   RAISE NOTICE 'После: mi_req(13)=%, mi_0001=%, mi_person=%',
                l_after_req, l_after_itm, l_after_pers;
   RAISE NOTICE 'Прирост: req=%, itm=%, person=%',
                l_after_req - l_before_req,
                l_after_itm - l_before_itm,
                l_after_pers - l_before_pers;
   RAISE NOTICE 'Время: %', l_t_end - l_t_start;
   RAISE NOTICE 'Исключение: %  (%)', l_raised, coalesce(l_raised_msg, '—');

   SELECT count(*) INTO l_err_count
     FROM xxi.mi_log
    WHERE logged_at >= l_t_start
      AND level_cd  = 'err'
      AND logger_name = 'mi.0001.auto';

   SELECT count(*) INTO l_wrn_count
     FROM xxi.mi_log
    WHERE logged_at >= l_t_start
      AND level_cd  = 'wrn'
      AND logger_name = 'mi.0001.auto';

   SELECT count(*) INTO l_inf_count
     FROM xxi.mi_log
    WHERE logged_at >= l_t_start
      AND level_cd  = 'inf'
      AND logger_name = 'mi.0001.auto';

   RAISE NOTICE 'Логи mi.0001.auto: inf=%, wrn=%, err=%', l_inf_count, l_wrn_count, l_err_count;

   RAISE NOTICE '--- Детали из mi_log (последние 20) ---';
   FOR r IN (
      SELECT logged_at, level_cd, action_cd, message_text, person_id, icusnum
        FROM xxi.mi_log
       WHERE logged_at >= l_t_start
         AND logger_name = 'mi.0001.auto'
       ORDER BY logged_at DESC
       LIMIT 20
   ) LOOP
      RAISE NOTICE '  [%] % %: % (person=%, icusnum=%)',
                   r.level_cd, r.action_cd,
                   to_char(r.logged_at, 'HH24:MI:SS.MS'),
                   r.message_text, r.person_id, r.icusnum;
   END LOOP;
END $$;
ROLLBACK;
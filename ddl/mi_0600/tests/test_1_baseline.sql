DO $$
DECLARE
   l_inf_cnt        int;
   l_mi0600_cnt     int;
   l_mi0600f_cnt    int;
   l_req_new        int;
   l_req_sent       int;
   l_rsp_ready      int;
   l_sched_setting  varchar;
   l_upd_setting    varchar;
   l_use_schedule   varchar;
   l_currency       varchar;
BEGIN
   RAISE NOTICE '============ Тест 1: Baseline mi_0600 ============';

   SELECT count(*) INTO l_inf_cnt
     FROM xxi.mi_inf WHERE inf_id IN (601, 602, 603, 604, 611, 612);
   RAISE NOTICE 'mi_inf с inf_id 601-612: % (ожидание: 6)', l_inf_cnt;

   SELECT count(*) INTO l_mi0600_cnt  FROM xxi.mi_0600;
   SELECT count(*) INTO l_mi0600f_cnt FROM xxi.mi_0600_f;
   RAISE NOTICE 'mi_0600: %, mi_0600_f: %', l_mi0600_cnt, l_mi0600f_cnt;

   SELECT count(*) INTO l_req_new FROM xxi.mi_req
    WHERE inf_id IN (601, 603, 611) AND status_cd = 0;
   SELECT count(*) INTO l_req_sent FROM xxi.mi_req
    WHERE inf_id IN (601, 602, 603, 604, 611, 612) AND status_cd = 3;
   SELECT count(*) INTO l_rsp_ready FROM xxi.mi_rsp
    WHERE status_cd = 1 AND req_id IN (
       SELECT req_id FROM xxi.mi_req WHERE inf_id IN (602, 604, 612)
    );
   RAISE NOTICE 'К отправке: инициаторы (0) = %, отправленные (3) = %, ответы Ready = %',
                l_req_new, l_req_sent, l_rsp_ready;

   l_sched_setting := MI_prp.get_sys_property('MI_0600.SCHEDULE', NULL);
   l_upd_setting   := MI_prp.get_sys_property('MI_0600.SCHEDULE_UPDATED_AT', NULL);
   l_use_schedule  := MI_prp.get_Wsp_Property(600, 'USE_SCHEDULE', '0');
   l_currency      := MI_prp.get_Wsp_Property(600, 'CURRENCY', NULL);

   RAISE NOTICE 'Настройки:';
   RAISE NOTICE '  MI_0600.SCHEDULE            = %', coalesce(left(l_sched_setting, 80), '<NULL>');
   RAISE NOTICE '  MI_0600.SCHEDULE_UPDATED_AT = %', coalesce(l_upd_setting, '<NULL>');
   RAISE NOTICE '  USE_SCHEDULE                = %', l_use_schedule;
   RAISE NOTICE '  CURRENCY                    = %', coalesce(l_currency, '<NULL>');

   RAISE NOTICE 'Версия пакета: %', mi_0600_api.get_version();
END $$;
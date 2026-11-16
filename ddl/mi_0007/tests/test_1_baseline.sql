DO $$
DECLARE
   l_cus_total       int;
   l_cus_with_pass   int;
   l_pud_pass_id     numeric;
   l_pud_cnt         int;
   l_mi0007_total    int;
   l_mi0007_pending  int;
   l_req74           int;
   l_req75           int;
   l_persons         int;
   l_markers         int;
   l_mrk_clients     int;
BEGIN
   RAISE NOTICE '============ Тест 1: Baseline для 0007 ============';

   SELECT count(*) INTO l_cus_total
     FROM xxi."CUS"
    WHERE ccusflag IN ('1','4');

   SELECT count(*) INTO l_cus_with_pass
     FROM xxi."CUS" c
    WHERE c.ccusflag IN ('1','4')
      AND EXISTS (
         SELECT 1 FROM xxi.cus_docum d
          WHERE d.icusnum = c.icusnum
            AND d.id_doc_tp = (
               SELECT pud.ipudid FROM xxi.pud WHERE pud.ipudint_code = 1
            )
            AND (d.doc_period IS NULL OR d.doc_period >= CURRENT_DATE)
      );

   RAISE NOTICE 'Клиенты (ccusflag 1/4): всего = %, с действующим паспортом РФ = %',
                l_cus_total, l_cus_with_pass;

   SELECT pud.ipudid INTO l_pud_pass_id
     FROM xxi.pud
    WHERE pud.ipudint_code = 1;
   RAISE NOTICE 'ID типа документа "Паспорт РФ": %', coalesce(l_pud_pass_id::text, '<NULL>');

   IF l_pud_pass_id IS NULL THEN
      RAISE NOTICE '!!! КРИТИЧНО: не задан pud.ipudint_code = 1 !!!';
      RAISE NOTICE '    create_And_Exec будет падать с "Не задан ID типа документа"';
   END IF;

   SELECT count(*) INTO l_pud_cnt
     FROM xxi.pud
    WHERE pud.ipudint_code = 1;
   RAISE NOTICE 'Записей в pud с ipudint_code = 1: % (ожидание: 1)', l_pud_cnt;

   SELECT count(*) INTO l_mi0007_total FROM xxi.mi_0007;
   SELECT count(*) INTO l_mi0007_pending FROM xxi.mi_0007 WHERE message_uuid IS NULL;
   RAISE NOTICE 'mi_0007: всего = %, ожидают ответа = %', l_mi0007_total, l_mi0007_pending;

   SELECT count(*) INTO l_req74 FROM xxi.mi_req WHERE inf_id = 74;
   SELECT count(*) INTO l_req75 FROM xxi.mi_req WHERE inf_id = 75;
   RAISE NOTICE 'mi_req: inf_id=74 = %, inf_id=75 = %', l_req74, l_req75;

   SELECT count(*) INTO l_persons FROM xxi.mi_person;
   RAISE NOTICE 'mi_person: всего = %', l_persons;

   SELECT count(*) INTO l_markers FROM xxi.mrk_id;
   RAISE NOTICE 'mrk_id: всего строк = %', l_markers;

   SELECT count(DISTINCT m.idmarker) INTO l_mrk_clients
     FROM xxi.mrk_id m
     JOIN xxi."CUS" c ON c.icusnum = m.idrow
    WHERE c.ccusflag IN ('1','4');
   RAISE NOTICE 'mrk_id: уникальных маркеров с клиентами 1/4 = %', l_mrk_clients;

   RAISE NOTICE 'Настройки:';
   RAISE NOTICE '  VALID_PERIOD_DOC_DAYS = %',
                MI_prp.get_Wsp_Property(7, 'VALID_PERIOD_DOC_DAYS', '0');
END $$;
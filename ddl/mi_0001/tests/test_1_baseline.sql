DO $$
DECLARE
   l_ca_total    int;
   l_ca_valid    int;
   l_req_12      int;
   l_req_13      int;
   l_itm_total   int;
   l_itm_pending int;
   l_persons     int;
   r             xxi.v_mi_0001_ca%ROWTYPE;
BEGIN
   RAISE NOTICE '============ Тест 1: Baseline ============';

   SELECT count(*) INTO l_ca_total FROM xxi.v_mi_0001_ca;
   RAISE NOTICE 'v_mi_0001_ca: всего строк = %', l_ca_total;

   SELECT count(*) INTO l_ca_valid
     FROM xxi.v_mi_0001_ca
    WHERE last_name IS NOT NULL AND first_name IS NOT NULL
      AND birth_date IS NOT NULL
      AND doc_type_code IS NOT NULL AND doc_num IS NOT NULL;
   RAISE NOTICE 'v_mi_0001_ca с валидными атрибутами = % (потолок нагрузки)', l_ca_valid;

   SELECT count(*) INTO l_req_12 FROM xxi.mi_req WHERE inf_id = 12;
   SELECT count(*) INTO l_req_13 FROM xxi.mi_req WHERE inf_id = 13;
   RAISE NOTICE 'mi_req: inf_id=12 (personal) = %; inf_id=13 (batch) = %', l_req_12, l_req_13;

   SELECT count(*) INTO l_itm_total FROM xxi.mi_0001;
   SELECT count(*) INTO l_itm_pending FROM xxi.mi_0001 WHERE message_uuid IS NULL;
   RAISE NOTICE 'mi_0001: всего = %; ожидают ответа = %', l_itm_total, l_itm_pending;

   SELECT count(*) INTO l_persons FROM xxi.mi_person;
   RAISE NOTICE 'mi_person: всего = %', l_persons;

   RAISE NOTICE 'Настройки:';
   RAISE NOTICE '  CUS_HOUR_RANGE   = %', MI_prp.get_Wsp_Property(1, 'CUS_HOUR_RANGE',   '48');
   RAISE NOTICE '  HANDLE_NOT_FOUND = %', MI_prp.get_Wsp_Property(1, 'HANDLE_NOT_FOUND', 'false');

   RAISE NOTICE '--- Первый клиент из представления ---';
   SELECT * INTO r FROM xxi.v_mi_0001_ca LIMIT 1;

   IF FOUND THEN
      RAISE NOTICE '  icusnum=%, ФИО=% % %',
                   r.icusnum, r.last_name, r.first_name, r.middle_name;
      RAISE NOTICE '  ДР=%, doc: тип=%, серия=%, номер=%, дата=%',
                   r.birth_date, r.doc_type_code, r.doc_ser, r.doc_num, r.doc_issue_date;
   ELSE
      RAISE NOTICE '  представление пустое';
   END IF;

   RAISE NOTICE '--- Первый клиент с валидными атрибутами ---';
   SELECT * INTO r FROM xxi.v_mi_0001_ca
    WHERE last_name IS NOT NULL AND first_name IS NOT NULL
      AND birth_date IS NOT NULL
      AND doc_type_code IS NOT NULL AND doc_num IS NOT NULL
    LIMIT 1;

   IF FOUND THEN
      RAISE NOTICE '  icusnum=%, ФИО=% % %',
                   r.icusnum, r.last_name, r.first_name, r.middle_name;
      RAISE NOTICE '  ДР=%, doc: тип=%, серия=%, номер=%, дата=%',
                   r.birth_date, r.doc_type_code, r.doc_ser, r.doc_num, r.doc_issue_date;
   END IF;
END $$;
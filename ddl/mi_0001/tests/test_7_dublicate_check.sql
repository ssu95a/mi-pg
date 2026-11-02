BEGIN;
DO $$
DECLARE
   r                 xxi.v_mi_0001_ca%ROWTYPE;
   l_req_id_1        numeric;
   l_itm_id_1        numeric;
   l_res_code_1      int;
   l_res_info_1      varchar;
   l_req_id_2        numeric;
   l_itm_id_2        numeric;
   l_res_code_2      int;
   l_res_info_2      varchar;
BEGIN
   RAISE NOTICE '============ Тест 7: Защита от дубликатов ============';

   SELECT * INTO r FROM xxi.v_mi_0001_ca
    WHERE last_name IS NOT NULL AND first_name IS NOT NULL
      AND birth_date IS NOT NULL
      AND doc_type_code IS NOT NULL AND doc_num IS NOT NULL
    LIMIT 1;

   IF NOT FOUND THEN
      RAISE NOTICE 'Нет клиентов — тест пропущен';
      RETURN;
   END IF;

   CALL mi_0001_api.create_Personal_Request(r, l_req_id_1, l_itm_id_1, l_res_code_1, l_res_info_1);
   RAISE NOTICE 'Первое создание: res_code=%, req_id=%, itm_id=%, info=%',
                l_res_code_1, l_req_id_1, l_itm_id_1, l_res_info_1;

   IF l_res_code_1 <> 0 THEN
      RAISE NOTICE 'Первое создание не удалось — тест прерван';
      RETURN;
   END IF;

   CALL mi_0001_api.create_Personal_Request(r, l_req_id_2, l_itm_id_2, l_res_code_2, l_res_info_2);
   RAISE NOTICE 'Повторный create_Personal_Request: res_code=%, req_id=%, itm_id=%, info=%',
                l_res_code_2, l_req_id_2, l_itm_id_2, l_res_info_2;

   IF l_res_code_2 <> 0 THEN
      RAISE NOTICE 'OK: повторный запрос отклонён (res_code=%)', l_res_code_2;
   ELSE
      RAISE NOTICE '!!! БАГ: создан дубликат req_id=% itm_id=% (первый=%/%) !!!',
                   l_req_id_2, l_itm_id_2, l_req_id_1, l_itm_id_1;
   END IF;
END $$;
ROLLBACK;
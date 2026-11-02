BEGIN;
DO $$
DECLARE
   l_res_ok mi_item_result_api.item_result;
   l_res_no mi_item_result_api.item_result;
BEGIN
   RAISE NOTICE '============ Тест 6: Прямой map_Item_Result ============';

   RAISE NOTICE '--- Успешный payload {"innPhP":"1234567890"} ---';
   l_res_ok := mi_0001_api.map_Item_Result(1, '{"innPhP":"1234567890"}'::jsonb);
   RAISE NOTICE 'ires_code=%, cres_info=%', l_res_ok.ires_code, l_res_ok.cres_info;
   RAISE NOTICE 'Ожидание: ires_code=0';

   IF l_res_ok.ires_code IS DISTINCT FROM 0 THEN
      RAISE NOTICE '!!! БАГ: при успехе ires_code должен быть 0, получено %', l_res_ok.ires_code;
   END IF;

   RAISE NOTICE '--- Пустой payload {} ---';
   l_res_no := mi_0001_api.map_Item_Result(1, '{}'::jsonb);
   RAISE NOTICE 'ires_code=%, cres_info=%', l_res_no.ires_code, l_res_no.cres_info;
   RAISE NOTICE 'Ожидание: ires_code=1, cres_info="Данные не найдены"';

   IF l_res_no.ires_code IS DISTINCT FROM 1 THEN
      RAISE NOTICE '!!! БАГ: при пустом payload ires_code должен быть 1, получено %', l_res_no.ires_code;
   END IF;
END $$;
ROLLBACK;
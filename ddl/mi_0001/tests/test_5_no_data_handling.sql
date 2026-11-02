BEGIN;
DO $$
DECLARE
   r          xxi.v_mi_0001_ca%ROWTYPE;
   l_req_id   numeric;
   l_itm_id   numeric;
   l_res_code int;
   l_res_info varchar;
   l_itm_uuid uuid;
   l_req_uuid uuid;
   l_ret_code int;
   l_ret_info varchar;
   l_inn      varchar;
   l_ires     numeric;
   l_cres     text;
BEGIN
   RAISE NOTICE '============ Тест 5: Обработка "нет данных" ============';

   SELECT * INTO r FROM xxi.v_mi_0001_ca
    WHERE last_name IS NOT NULL AND first_name IS NOT NULL
      AND birth_date IS NOT NULL
      AND doc_type_code IS NOT NULL AND doc_num IS NOT NULL
    LIMIT 1;

   IF NOT FOUND THEN
      RAISE NOTICE 'Нет клиентов — тест пропущен';
      RETURN;
   END IF;

   CALL mi_0001_api.create_Personal_Request(r, l_req_id, l_itm_id, l_res_code, l_res_info);
   IF l_res_code <> 0 THEN
      RAISE NOTICE 'Не удалось создать: %', l_res_info;
      RETURN;
   END IF;

   SELECT m.external_uuid, q.external_uuid
     INTO l_itm_uuid, l_req_uuid
     FROM xxi.mi_0001 m JOIN xxi.mi_req q ON q.req_id = m.req_id
    WHERE m.itm_id = l_itm_id;

   CALL mi_0001_api.apply_Item_Result(
      p_request_uuid     => l_req_uuid,
      p_message_uuid     => gen_random_uuid(),
      p_item_uuid        => l_itm_uuid,
      p_response_kind    => 0,
      p_response_code    => NULL,
      p_response_info    => NULL,
      p_response_details => NULL,
      p_response_time    => clock_timestamp(),
      p_payload_text     => '{}',
      p_ret_code         => l_ret_code,
      p_ret_info         => l_ret_info
   );

   RAISE NOTICE 'apply_Item_Result: ret_code=%, ret_info=%', l_ret_code, l_ret_info;

   SELECT inn, ires_code, cres_info
     INTO l_inn, l_ires, l_cres
     FROM xxi.mi_0001 WHERE itm_id = l_itm_id;

   RAISE NOTICE 'После ответа: inn=%, ires_code=%, cres_info=%', l_inn, l_ires, l_cres;
   RAISE NOTICE 'Ожидание: ires_code=1, cres_info="Данные не найдены"';
END $$;
ROLLBACK;
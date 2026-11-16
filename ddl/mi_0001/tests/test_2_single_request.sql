BEGIN;
DO $$
DECLARE
   r           xxi.v_mi_0001_ca%ROWTYPE;
   l_req_id    numeric;
   l_itm_id    numeric;
   l_res_code  int;
   l_res_info  varchar;
   l_person_id numeric;
   l_itm_uuid  uuid;
   l_req_uuid  uuid;
   l_ret_code  int;
   l_ret_info  varchar;
   l_inn       varchar;
   l_ires      numeric;
   l_cres      text;
   l_msg       uuid;
   l_t_start   timestamptz;
   l_t_end     timestamptz;
   l_payload   text := '{"innPhP":"1234567890"}';
BEGIN
   RAISE NOTICE '============ Тест 2: Одиночный запрос ============';

   SELECT * INTO r FROM xxi.v_mi_0001_ca
    WHERE last_name IS NOT NULL AND first_name IS NOT NULL
      AND birth_date IS NOT NULL
      AND doc_type_code IS NOT NULL AND doc_num IS NOT NULL
    LIMIT 1;

   IF NOT FOUND THEN
      RAISE NOTICE 'Нет валидных клиентов — тест пропущен';
      RETURN;
   END IF;

   RAISE NOTICE 'Клиент: icusnum=%, ФИО=% % %, ДР=%',
                r.icusnum, r.last_name, r.first_name, r.middle_name, r.birth_date;

   l_t_start := clock_timestamp();
   CALL mi_0001_api.create_Personal_Request(r, l_req_id, l_itm_id, l_res_code, l_res_info);
   l_t_end := clock_timestamp();

   RAISE NOTICE 'create_Personal_Request: res_code=%, req_id=%, itm_id=%, info=%',
                l_res_code, l_req_id, l_itm_id, l_res_info;
   RAISE NOTICE 'Время: %', l_t_end - l_t_start;

   IF l_res_code <> 0 THEN
      RAISE NOTICE 'Запрос не создан — тест прерван';
      RETURN;
   END IF;

   PERFORM 1 FROM xxi.mi_req WHERE req_id = l_req_id AND inf_id = 12;
   RAISE NOTICE 'mi_req с inf_id=12 создан: %', FOUND;

   PERFORM 1 FROM xxi.mi_0001 WHERE itm_id = l_itm_id AND req_id = l_req_id;
   RAISE NOTICE 'mi_0001 создан: %', FOUND;

   SELECT person_id INTO l_person_id FROM xxi.mi_0001 WHERE itm_id = l_itm_id;
   PERFORM 1 FROM xxi.mi_person WHERE person_id = l_person_id;
   RAISE NOTICE 'mi_person person_id=%: %', l_person_id, FOUND;

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
      p_payload_text     => l_payload,
      p_ret_code         => l_ret_code,
      p_ret_info         => l_ret_info
   );

   RAISE NOTICE 'apply_Item_Result: ret_code=%, ret_info=%', l_ret_code, l_ret_info;

   SELECT inn, ires_code, cres_info, message_uuid
     INTO l_inn, l_ires, l_cres, l_msg
     FROM xxi.mi_0001 WHERE itm_id = l_itm_id;

   RAISE NOTICE 'После ответа: inn=%, ires_code=%, cres_info=%, message_uuid=%',
                l_inn, l_ires, l_cres, l_msg;
END $$;
ROLLBACK;
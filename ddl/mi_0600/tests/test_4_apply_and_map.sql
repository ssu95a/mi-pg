BEGIN;
DO $$
DECLARE
   -- Успешный сценарий (инициатор 601)
   l_req_id   numeric;
   l_itm_id   numeric;
   l_rc       int;
   l_ri       varchar;
   l_req_uuid uuid;
   l_itm_uuid uuid;
   l_msg_uuid uuid := gen_random_uuid();
   l_payload  text;
   l_ret_rc   int;
   l_ret_ri   varchar;
   l_ires     numeric;
   l_cres     text;
   l_tres     timestamptz;
   l_msg_out  uuid;
   -- Ошибочный сценарий
   l_req_id2  numeric;
   l_itm_id2  numeric;
   l_req_uuid2 uuid;
   l_itm_uuid2 uuid;
   l_ret_rc2  int;
   l_ret_ri2  varchar;
   l_ires2    numeric;
   l_cres2    text;
BEGIN
   RAISE NOTICE '============ Тест 4: apply_item_result + map_item_result ============';

   -- === Сценарий 1: успешный ответ ===
   CALL mi_0600_api.create_request(
      p_inf_id           => 601,
      p_czip_name        => 'apply_test_ok.zip',
      p_bzip_data        => decode('504b0304', 'hex'),
      p_izip_size        => 4,
      p_izip_files_count => 1,
      p_file_names       => ARRAY['f.xml'],
      p_req_id           => l_req_id,
      p_itm_id           => l_itm_id,
      p_ret_code         => l_rc,
      p_ret_info         => l_ri
   );
   RAISE NOTICE 'setup #1: req_id=%, itm_id=%', l_req_id, l_itm_id;

   SELECT r.external_uuid, h.external_uuid
     INTO l_req_uuid, l_itm_uuid
     FROM xxi.mi_req r JOIN xxi.mi_0600 h ON h.req_id = r.req_id
    WHERE r.req_id = l_req_id;

   -- Успешный ответ: state=0
   l_payload := '{"state": 0, "message": "OK"}';

   CALL mi_0600_api.apply_item_result(
      p_request_uuid     => l_req_uuid,
      p_message_uuid     => l_msg_uuid,
      p_item_uuid        => l_itm_uuid,
      p_response_kind    => 0,
      p_response_code    => NULL,
      p_response_info    => NULL,
      p_response_details => NULL,
      p_response_time    => clock_timestamp(),
      p_payload_text     => l_payload,
      p_ret_code         => l_ret_rc,
      p_ret_info         => l_ret_ri
   );
   RAISE NOTICE 'apply success: rc=%, ri=%', l_ret_rc, l_ret_ri;

   SELECT ires_code, cres_info, tres_time, message_uuid
     INTO l_ires, l_cres, l_tres, l_msg_out
     FROM xxi.mi_0600 WHERE itm_id = l_itm_id;

   RAISE NOTICE 'после apply: ires_code=%, cres_info=%, tres_time=% , message_uuid=%',
                l_ires, coalesce(l_cres, '<NULL>'),
                coalesce(l_tres::text, '<NULL>'),
                coalesce(l_msg_out::text, '<NULL>');
   RAISE NOTICE 'ожидание: ires_code=0, tres_time не NULL, message_uuid совпадает: %',
                (l_msg_out = l_msg_uuid);

   -- === Сценарий 2: ошибочный ответ (state < 0) ===
   CALL mi_0600_api.create_request(
      p_inf_id           => 601,
      p_czip_name        => 'apply_test_err.zip',
      p_bzip_data        => decode('504b0304', 'hex'),
      p_izip_size        => 4,
      p_izip_files_count => 1,
      p_file_names       => ARRAY['g.xml'],
      p_req_id           => l_req_id2,
      p_itm_id           => l_itm_id2,
      p_ret_code         => l_rc,
      p_ret_info         => l_ri
   );
   RAISE NOTICE 'setup #2: req_id=%, itm_id=%', l_req_id2, l_itm_id2;

   SELECT r.external_uuid, h.external_uuid
     INTO l_req_uuid2, l_itm_uuid2
     FROM xxi.mi_req r JOIN xxi.mi_0600 h ON h.req_id = r.req_id
    WHERE r.req_id = l_req_id2;

   -- payload с ошибкой
   l_payload := '{"state": -5, "message": "СМЭВ вернул ошибку", "errorCode": "ERR-123"}';

   CALL mi_0600_api.apply_item_result(
      p_request_uuid     => l_req_uuid2,
      p_message_uuid     => gen_random_uuid(),
      p_item_uuid        => l_itm_uuid2,
      p_response_kind    => 0,
      p_response_code    => NULL,
      p_response_info    => NULL,
      p_response_details => NULL,
      p_response_time    => clock_timestamp(),
      p_payload_text     => l_payload,
      p_ret_code         => l_ret_rc2,
      p_ret_info         => l_ret_ri2
   );
   RAISE NOTICE 'apply error: rc=%, ri=%', l_ret_rc2, l_ret_ri2;

   SELECT ires_code, cres_info
     INTO l_ires2, l_cres2
     FROM xxi.mi_0600 WHERE itm_id = l_itm_id2;

   RAISE NOTICE 'после apply: ires_code=%, cres_info=%', l_ires2, coalesce(l_cres2, '<NULL>');
   RAISE NOTICE 'ожидание: ires_code=-1, cres_info содержит текст ошибки и код ERR-123';
END $$;
ROLLBACK;
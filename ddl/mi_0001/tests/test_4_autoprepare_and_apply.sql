BEGIN;
DO $$
DECLARE
   r           record;
   l_processed int := 0;
   l_failed    int := 0;
   l_ret_code  int;
   l_ret_info  varchar;
   l_payload   text := '{"innPhP":"9999999999"}';
   l_t_start   timestamptz;
   l_t_end     timestamptz;
BEGIN
   RAISE NOTICE '============ Тест 4: auto_Prepare + apply_Item_Result ============';

   BEGIN
      CALL mi_0001_api.auto_Prepare(false);
   EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '!!! auto_Prepare ВЫБРОСИЛ: %', SQLERRM;
   END;

   l_t_start := clock_timestamp();

   FOR r IN (
      SELECT i.itm_id, i.external_uuid AS itm_uuid, q.external_uuid AS req_uuid, i.icusnum
        FROM xxi.mi_0001 i
        JOIN xxi.mi_req  q ON q.req_id = i.req_id
       WHERE i.message_uuid IS NULL
       LIMIT 20
   ) LOOP
      BEGIN
         CALL mi_0001_api.apply_Item_Result(
            p_request_uuid     => r.req_uuid,
            p_message_uuid     => gen_random_uuid(),
            p_item_uuid        => r.itm_uuid,
            p_response_kind    => 0,
            p_response_code    => NULL,
            p_response_info    => NULL,
            p_response_details => NULL,
            p_response_time    => clock_timestamp(),
            p_payload_text     => l_payload,
            p_ret_code         => l_ret_code,
            p_ret_info         => l_ret_info
         );
         IF l_ret_code = 0 THEN
            l_processed := l_processed + 1;
         ELSE
            l_failed := l_failed + 1;
            RAISE NOTICE 'apply FAILED: itm_id=%, icusnum=%, ret_code=%, ret_info=%',
                         r.itm_id, r.icusnum, l_ret_code, l_ret_info;
         END IF;
      EXCEPTION WHEN OTHERS THEN
         l_failed := l_failed + 1;
         RAISE NOTICE 'apply EXCEPTION: itm_id=%, icusnum=%, err=%',
                      r.itm_id, r.icusnum, SQLERRM;
      END;
   END LOOP;

   l_t_end := clock_timestamp();

   RAISE NOTICE 'Обработано: успешно=%, ошибок=%', l_processed, l_failed;
   RAISE NOTICE 'Время: %', l_t_end - l_t_start;
END $$;
ROLLBACK;
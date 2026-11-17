BEGIN;
DO $$
DECLARE
   l_orig_uuid uuid := gen_random_uuid();
   l_msg_uuid  uuid := gen_random_uuid();
   l_req_id1   numeric;
   l_itm_id1   numeric;
   l_rc1       int;
   l_ri1       varchar;
   l_req_id2   numeric;
   l_itm_id2   numeric;
   l_rc2       int;
   l_ri2       varchar;
   l_req_id3   numeric;
   l_itm_id3   numeric;
   l_rc3       int;
   l_ri3       varchar;
   l_req_uuid  uuid;
   l_itm_uuid  uuid;
BEGIN
   RAISE NOTICE '============ Тест 3: answerer 602 ============';

   -- Создание запроса-ответчика
   CALL mi_0600_api.create_request(
      p_inf_id                => 602,
      p_czip_name             => 'answer_602_incoming.zip',
      p_bzip_data             => decode('504b030414', 'hex'),
      p_izip_size             => 5,
      p_izip_files_count      => 1,
      p_file_names            => ARRAY['request.xml'],
      p_original_request_uuid => l_orig_uuid,
      p_message_uuid          => l_msg_uuid,
      p_ctaxreq_id            => 'FNS-TEST-001',
      p_req_id                => l_req_id1,
      p_itm_id                => l_itm_id1,
      p_ret_code              => l_rc1,
      p_ret_info              => l_ri1
   );
   RAISE NOTICE 'create #1: rc=%, req_id=%, itm_id=%, info=%',
                l_rc1, l_req_id1, l_itm_id1, l_ri1;

   IF l_rc1 <> 0 THEN
      RAISE NOTICE '!!! ОШИБКА: первое создание не удалось';
      RETURN;
   END IF;

   -- Для ответчика external_uuid элемента должен отличаться от external_uuid запроса
   SELECT r.external_uuid, h.external_uuid
     INTO l_req_uuid, l_itm_uuid
     FROM xxi.mi_req r JOIN xxi.mi_0600 h ON h.req_id = r.req_id
    WHERE r.req_id = l_req_id1;

   RAISE NOTICE 'UUID: req=%, item=%, совпадают=%, (ожидание: НЕ совпадают=f)',
                l_req_uuid, l_itm_uuid, (l_req_uuid = l_itm_uuid);

   -- Проверка transport-полей
   PERFORM 1 FROM xxi.mi_req
    WHERE req_id = l_req_id1
      AND original_request_uuid = l_orig_uuid
      AND message_uuid = l_msg_uuid
      AND ctaxreq_id = 'FNS-TEST-001'
      AND status_cd = 0;
   RAISE NOTICE 'transport-поля mi_req сохранены: %', FOUND;

   -- Дубликат по original_request_uuid
   CALL mi_0600_api.create_request(
      p_inf_id                => 602,
      p_czip_name             => 'answer_602_other.zip',
      p_bzip_data             => decode('504b0304AABB', 'hex'),
      p_izip_size             => 6,
      p_izip_files_count      => 1,
      p_file_names            => ARRAY['other.xml'],
      p_original_request_uuid => l_orig_uuid,
      p_message_uuid          => gen_random_uuid(),
      p_ctaxreq_id            => 'FNS-TEST-002',
      p_req_id                => l_req_id2,
      p_itm_id                => l_itm_id2,
      p_ret_code              => l_rc2,
      p_ret_info              => l_ri2
   );
   RAISE NOTICE 'create #2 (дубликат orig_uuid): rc=%, req_id=%, itm_id=%, info=%',
                l_rc2, l_req_id2, l_itm_id2, l_ri2;
   RAISE NOTICE 'ожидание: rc=4 (RET_EXISTS), тот же req_id=%', (l_req_id2 = l_req_id1);
   RAISE NOTICE 'итм_id при дубликате: % (ожидание: не NULL)',
                coalesce(l_itm_id2::text, '<NULL>');

   -- Другой original_request_uuid → новый запрос
   CALL mi_0600_api.create_request(
      p_inf_id                => 602,
      p_czip_name             => 'answer_602_third.zip',
      p_bzip_data             => decode('504b0304CCDD', 'hex'),
      p_izip_size             => 6,
      p_izip_files_count      => 1,
      p_file_names            => ARRAY['third.xml'],
      p_original_request_uuid => gen_random_uuid(),
      p_message_uuid          => gen_random_uuid(),
      p_ctaxreq_id            => 'FNS-TEST-003',
      p_req_id                => l_req_id3,
      p_itm_id                => l_itm_id3,
      p_ret_code              => l_rc3,
      p_ret_info              => l_ri3
   );
   RAISE NOTICE 'create #3 (новый orig_uuid): rc=%, req_id=%, info=%',
                l_rc3, l_req_id3, l_ri3;
   RAISE NOTICE 'новый req_id ≠ первого: %', (l_req_id3 <> l_req_id1);
END $$;
ROLLBACK;
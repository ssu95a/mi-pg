BEGIN;
DO $$
DECLARE
   l_req_id1   numeric;
   l_itm_id1   numeric;
   l_rc1       int;
   l_ri1       varchar;
   l_req_id2   numeric;
   l_itm_id2   numeric;
   l_rc2       int;
   l_ri2       varchar;
   l_req_uuid  uuid;
   l_itm_uuid  uuid;
   l_before_f  int;
   l_after_f   int;
   l_dsend     timestamptz;
   l_file_date date;
   l_status    numeric;
BEGIN
   RAISE NOTICE '============ Тест 2: initiator 601 ============';

   SELECT count(*) INTO l_before_f FROM xxi.mi_0600_f;

   -- Создание первого запроса
   CALL mi_0600_api.create_request(
      p_inf_id           => 601,
      p_czip_name        => 'test_601_v1.zip',
      p_bzip_data        => decode('504b0304140000000800', 'hex'),
      p_izip_size        => 10,
      p_izip_files_count => 2,
      p_file_names       => ARRAY['file1.xml', 'file2.xml'],
      p_req_id           => l_req_id1,
      p_itm_id           => l_itm_id1,
      p_ret_code         => l_rc1,
      p_ret_info         => l_ri1
   );
   RAISE NOTICE 'create #1: rc=%, req_id=%, itm_id=%, info=%',
                l_rc1, l_req_id1, l_itm_id1, l_ri1;

   IF l_rc1 <> 0 OR l_req_id1 IS NULL OR l_itm_id1 IS NULL THEN
      RAISE NOTICE '!!! ОШИБКА: первое создание не удалось';
      RETURN;
   END IF;

   -- Проверка UUID (для инициатора external_uuid элемента = external_uuid запроса)
   SELECT r.external_uuid, h.external_uuid
     INTO l_req_uuid, l_itm_uuid
     FROM xxi.mi_req r JOIN xxi.mi_0600 h ON h.req_id = r.req_id
    WHERE r.req_id = l_req_id1;

   RAISE NOTICE 'UUID: req=%, item=%, совпадают=%, (ожидание: совпадают=t для инициатора)',
                l_req_uuid, l_itm_uuid, (l_req_uuid = l_itm_uuid);

   SELECT count(*) INTO l_after_f FROM xxi.mi_0600_f;
   RAISE NOTICE 'mi_0600_f: было=%, стало=% (ожидание прирост 2)', l_before_f, l_after_f;

   -- Дубликат по czip_name
   CALL mi_0600_api.create_request(
      p_inf_id           => 601,
      p_czip_name        => 'test_601_v1.zip',
      p_bzip_data        => decode('504b0304140000000800FFFFFFFF', 'hex'),
      p_izip_size        => 14,
      p_izip_files_count => 1,
      p_file_names       => ARRAY['new_file.xml'],
      p_req_id           => l_req_id2,
      p_itm_id           => l_itm_id2,
      p_ret_code         => l_rc2,
      p_ret_info         => l_ri2
   );
   RAISE NOTICE 'create #2 (дубликат): rc=%, req_id=%, itm_id=%, info=%',
                l_rc2, l_req_id2, l_itm_id2, l_ri2;
   RAISE NOTICE 'Вернул тот же req_id (ожидание t): %, тот же itm_id: %',
                (l_req_id2 = l_req_id1), (l_itm_id2 = l_itm_id1);

   -- Проверка обновления bzip_data и файлов после дубликата
   PERFORM 1 FROM xxi.mi_0600 WHERE itm_id = l_itm_id1
      AND bzip_data = decode('504b0304140000000800FFFFFFFF', 'hex')
      AND izip_size = 14
      AND izip_files_count = 1;
   RAISE NOTICE 'bzip_data/meta обновлены: %', FOUND;

   PERFORM 1 FROM xxi.mi_0600_f WHERE itm_id = l_itm_id1 AND czip_file_name = 'new_file.xml';
   RAISE NOTICE 'новый файл присутствует: %', FOUND;

   PERFORM 1 FROM xxi.mi_0600_f WHERE itm_id = l_itm_id1 AND czip_file_name = 'file1.xml';
   RAISE NOTICE 'старый файл УДАЛЁН: % (ожидание t)', NOT FOUND;

   -- Триггер dsend_stamp: переход 0 -> 2 -> 3
   UPDATE xxi.mi_req SET status_cd = 2 WHERE req_id = l_req_id1;
   UPDATE xxi.mi_req SET status_cd = 3 WHERE req_id = l_req_id1;

   SELECT dsend_stamp INTO l_dsend FROM xxi.mi_0600 WHERE itm_id = l_itm_id1;
   RAISE NOTICE 'dsend_stamp после 2->3: % (ожидание: не NULL)', coalesce(l_dsend::text, '<NULL>');

   -- get_fns_file_inqueue_date по имени файла
   l_file_date := mi_0600_api.get_fns_file_inqueue_date('new_file.xml');
   RAISE NOTICE 'get_fns_file_inqueue_date(''new_file.xml'') = % (ожидание: сегодня)', l_file_date;

   l_file_date := mi_0600_api.get_fns_file_inqueue_date('  NEW_FILE.XML  ');
   RAISE NOTICE 'с пробелами и в верхнем регистре = % (ожидание: тоже)', l_file_date;

   l_file_date := mi_0600_api.get_fns_file_inqueue_date('non_existent.xml');
   RAISE NOTICE 'несуществующий файл = % (ожидание: NULL)', coalesce(l_file_date::text, '<NULL>');
END $$;
ROLLBACK;
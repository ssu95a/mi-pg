BEGIN;
DO $$
DECLARE
   l_limit      int := 100;
   l_i          int := 0;
   l_processed  int := 0;
   l_failed     int := 0;
   r            record;
   l_ret_code   int;
   l_ret_info   varchar;
   l_payload    text := '{"docStatus":1,"comment":"Паспорт действителен"}';
   l_t_start    timestamptz;
   l_t_end      timestamptz;
BEGIN
   RAISE NOTICE '============ Тест 4: apply_Item_Result пачкой ============';
   RAISE NOTICE 'Лимит: % элементов', l_limit;

   -- Подготовка: создать N элементов (без отправки) для последующей обработки
   DECLARE
      r_cus record;
   BEGIN
      FOR r_cus IN (
         SELECT c.icusnum,
                c.ccuslast_name   AS last_name,
                c.ccusfirst_name  AS first_name,
                c.ccusmiddle_name AS middle_name,
                c.dcusbirthday    AS birth_date,
                d.doc_ser, d.doc_num, d.doc_date AS doc_issue_date
           FROM xxi."CUS" c
           JOIN LATERAL (
                SELECT b.doc_ser, b.doc_num, b.doc_date
                  FROM xxi.cus_docum b
                 WHERE b.icusnum = c.icusnum
                   AND b.id_doc_tp = (SELECT pud.ipudid FROM xxi.pud WHERE pud.ipudint_code = 1)
                   AND (b.doc_period IS NULL OR b.doc_period >= CURRENT_DATE)
                 ORDER BY (b.pref = 'Y') DESC, b.doc_date DESC NULLS LAST, b.id_doc DESC
                 LIMIT 1
           ) d ON true
          WHERE c.ccusflag IN ('1','4')
          LIMIT l_limit
      ) LOOP
         BEGIN
            CALL mi_0007_api.create_And_Exec(
               p_inf_id         => 74,
               p_icusnum        => r_cus.icusnum,
               p_last_name      => r_cus.last_name,
               p_first_name     => r_cus.first_name,
               p_middle_name    => r_cus.middle_name,
               p_birth_date     => r_cus.birth_date,
               p_doc_ser        => r_cus.doc_ser,
               p_doc_num        => r_cus.doc_num,
               p_doc_issue_date => r_cus.doc_issue_date,
               p_region_code    => NULL,
               p_time_out       => 0,
               p_do_send        => false,
               p_res_code       => NULL,
               p_req_id         => NULL,
               p_itm_id         => NULL,
               p_iState         => NULL,
               p_result_info    => NULL
            );
         EXCEPTION WHEN OTHERS THEN NULL;
         END;
      END LOOP;
   END;

   RAISE NOTICE 'Подготовка завершена, начинаем обработку';

   l_t_start := clock_timestamp();

   FOR r IN (
      SELECT i.itm_id, i.external_uuid AS itm_uuid, q.external_uuid AS req_uuid, i.person_id
        FROM xxi.mi_0007 i
        JOIN xxi.mi_req  q ON q.req_id = i.req_id
       WHERE i.message_uuid IS NULL
         AND q.inf_id = 74
       LIMIT l_limit
   ) LOOP
      l_i := l_i + 1;
      BEGIN
         CALL mi_0007_api.apply_Item_Result(
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
            IF l_failed <= 5 THEN
               RAISE NOTICE 'apply FAILED: itm_id=%, ret_code=%, ret_info=%',
                            r.itm_id, l_ret_code, l_ret_info;
            END IF;
         END IF;
      EXCEPTION WHEN OTHERS THEN
         l_failed := l_failed + 1;
         IF l_failed <= 5 THEN
            RAISE NOTICE 'apply EXCEPTION: itm_id=%, err=%', r.itm_id, SQLERRM;
         END IF;
      END;
   END LOOP;

   l_t_end := clock_timestamp();

   RAISE NOTICE 'Итог:';
   RAISE NOTICE '  обработано = %, успешно = %, ошибок = %', l_i, l_processed, l_failed;
   RAISE NOTICE '  время     = %', l_t_end - l_t_start;
   RAISE NOTICE '  среднее   = %', (l_t_end - l_t_start) / NULLIF(l_i, 0);
END $$;
ROLLBACK;
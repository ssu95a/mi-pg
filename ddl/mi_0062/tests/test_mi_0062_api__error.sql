-- Тест: обработка ошибочного ответа mi_0062_api
-- Ответ СМЭВ с result="fault": ires_code = -1, kz_charges не заполняется
SET client_min_messages = debug1;
DO $$
DECLARE
   v_req_id      numeric;
   v_itm_id      numeric;
   v_res_code    integer;
   v_res_info    varchar;
   v_req_uuid    uuid;
   v_itm_uuid    uuid;
   v_payload     text;
   v_ires        numeric;
   v_cres        text;
   v_kz_cnt      integer;
BEGIN
   RAISE NOTICE '===============================';
   RAISE NOTICE 'Шаг 1. Создание запроса и элемента';
   RAISE NOTICE '===============================';

   v_req_id := mi_0062_api.create_request(2);
   v_itm_id := mi_0062_api.create_item(
      p_req_id   => v_req_id,
      p_id_value => '32117072411021588933'
   );

   RAISE NOTICE 'req_id = %', v_req_id;
   RAISE NOTICE 'itm_id = %', v_itm_id;

   SELECT external_uuid INTO v_req_uuid
     FROM xxi.mi_req WHERE req_id = v_req_id;

   SELECT external_uuid INTO v_itm_uuid
     FROM xxi.mi_0062 WHERE itm_id = v_itm_id;

   RAISE NOTICE '===============================';
   RAISE NOTICE 'Шаг 2. Эмуляция ошибочного ответа СМЭВ (fault)';
   RAISE NOTICE '===============================';

   v_payload := '<response result="fault">
      <message>internal error: service unavailable</message>
   </response>';

   CALL mi_0062_api.apply_item_result(
      p_request_uuid    => v_req_uuid,
      p_message_uuid    => gen_random_uuid(),
      p_item_uuid       => v_itm_uuid,
      p_response_kind   => 0,
      p_response_code   => NULL,
      p_response_info   => NULL,
      p_response_details => NULL,
      p_response_time   => clock_timestamp(),
      p_payload_text    => v_payload,
      p_ret_code        => v_res_code,
      p_ret_info        => v_res_info
   );

   RAISE NOTICE 'res_code = %', v_res_code;
   RAISE NOTICE 'res_info = %', v_res_info;

   RAISE NOTICE '===============================';
   RAISE NOTICE 'Шаг 3. Проверка результата';
   RAISE NOTICE '===============================';

   SELECT ires_code, cres_info INTO v_ires, v_cres
     FROM xxi.mi_0062 WHERE itm_id = v_itm_id;

   RAISE NOTICE 'mi_0062.ires_code = %', v_ires;
   RAISE NOTICE 'mi_0062.cres_info = %', v_cres;

   SELECT count(*) INTO v_kz_cnt
     FROM xxi.kz_charges
    WHERE cmessageid = (SELECT correlation_id::text FROM xxi.mi_req WHERE req_id = v_req_id);

   RAISE NOTICE 'kz_charges rows   = %', v_kz_cnt;

   RAISE NOTICE '===============================';
   RAISE NOTICE 'ИТОГО:';
   RAISE NOTICE '  req_id     = %', v_req_id;
   RAISE NOTICE '  itm_id     = %', v_itm_id;
   RAISE NOTICE '  ires_code  = %  (ожидание: -1)', v_ires;
   RAISE NOTICE '  kz_charges = %  (ожидание: 0)', v_kz_cnt;
   RAISE NOTICE '===============================';

   IF v_ires <> -1 THEN
      RAISE EXCEPTION 'Ожидался ires_code = -1, получено %', v_ires;
   END IF;

   IF v_kz_cnt <> 0 THEN
      RAISE EXCEPTION 'Ожидалось 0 записей в kz_charges, получено %', v_kz_cnt;
   END IF;

END;
$$;

-- Детальная проверка (выполнить с подставленным req_id из NOTICE выше)
/* 
SELECT r.req_id,
       r.inf_id,
       r.itype,
       r.status_cd,
       r.correlation_id,
       i.itm_id,
       i.id_value,
       i.ires_code,
       i.cres_info,
       i.tres_time,
       i.message_uuid,
       i.error_code
  FROM xxi.mi_req r
  JOIN xxi.mi_0062 i ON i.req_id = r.req_id
 WHERE r.req_id = <req_id>;
 */
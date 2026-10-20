-- Тест: полный успешный цикл mi_0062_api
-- Создание запроса, отправка, обработка успешного ответа, запись в kz_charges

DO $$
DECLARE
   v_itype       integer := 2;                                -- 2 = УИН
   v_id_value    varchar := '32117072411021588933';
   v_req_id      numeric;
   v_items_cnt   integer;
   v_itm_id      numeric;
   v_res_code    integer;
   v_res_info    varchar;
   v_req_uuid    uuid;
   v_itm_uuid    uuid;
   v_msg_uuid    uuid := gen_random_uuid();
   v_payload     text;
   v_ires        numeric;
   v_msg         uuid;
   v_kz_cnt      integer;
BEGIN
   RAISE NOTICE '===============================';
   RAISE NOTICE 'Шаг 1. Создание запроса и элемента (create_items)';
   RAISE NOTICE '===============================';

   CALL mi_0062_api.create_items(
      p_id_type       => v_itype,
      p_id_list       => v_id_value,
      p_req_id        => v_req_id,
      p_items_created => v_items_cnt,
      p_ret_code      => v_res_code,
      p_ret_info      => v_res_info
   );

   RAISE NOTICE 'req_id        = %', v_req_id;
   RAISE NOTICE 'items_created = %', v_items_cnt;
   RAISE NOTICE 'res_code      = %', v_res_code;
   RAISE NOTICE 'res_info      = %', v_res_info;

   IF v_res_code <> 0 OR v_req_id IS NULL THEN
      RAISE EXCEPTION 'create_items failed: %', v_res_info;
   END IF;

   -- Получаем UUID request и элемента для последующей обработки ответа
   SELECT external_uuid INTO v_req_uuid
     FROM xxi.mi_req WHERE req_id = v_req_id;

   SELECT itm_id, external_uuid INTO v_itm_id, v_itm_uuid
     FROM xxi.mi_0062 WHERE req_id = v_req_id
    ORDER BY itm_id LIMIT 1;

   RAISE NOTICE '===============================';
   RAISE NOTICE 'Шаг 2. Отправка запроса в СМЭВ (submit_request)';
   RAISE NOTICE '===============================';

   CALL mi_0062_api.submit_request(
      p_req_id   => v_req_id,
      p_ret_code => v_res_code,
      p_ret_info => v_res_info
   );

   RAISE NOTICE 'res_code = %', v_res_code;
   RAISE NOTICE 'res_info = %', v_res_info;

   -- Отправка могла не пройти (среда без шины) — не считаем это фатальным,
   -- проверяем именно разбор ответа ниже
   IF v_res_code <> 0 THEN
      RAISE NOTICE 'WARNING: submit_request вернул ошибку (продолжаем разбор)';
   END IF;

   RAISE NOTICE '===============================';
   RAISE NOTICE 'Шаг 3. Эмуляция успешного ответа СМЭВ (apply_item_result)';
   RAISE NOTICE '===============================';

   v_payload := '<response result="success">
      <ChargeInfo supplierBillID="32117072411021588933"
                  amountToPay="5000"
                  billDate="2026-08-14T14:06:30+03:00"
                  totalAmount="500000"
                  purpose="Плата за предоставление сведений (ТЕСТ)"
                  kbk="32111301031016000130"
                  oktmo="45348000">
         <Payee inn="7705401341" kpp="770542151" name="ФГБУ ФКП Росреестра по г Москва">
            <OrgAccount accountNumber="40101810045250010041">
               <Bank bik="044525000"/>
            </OrgAccount>
         </Payee>
         <Payer payerIdentifier="1010000000008751379232" payerName="Тестовый плательщик"/>
         <BudgetIndex paytReason="0" status="01" taxDocDate="0" taxDocNumber="0" taxPeriod="0"/>
      </ChargeInfo>
   </response>';

   CALL mi_0062_api.apply_item_result(
      p_request_uuid    => v_req_uuid,
      p_message_uuid    => v_msg_uuid,
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

   IF v_res_code <> 0 THEN
      RAISE EXCEPTION 'apply_item_result failed: %', v_res_info;
   END IF;

   RAISE NOTICE '===============================';
   RAISE NOTICE 'Шаг 4. Проверка результата';
   RAISE NOTICE '===============================';

   SELECT ires_code, message_uuid INTO v_ires, v_msg
     FROM xxi.mi_0062 WHERE itm_id = v_itm_id;

   RAISE NOTICE 'mi_0062.ires_code    = %', v_ires;
   RAISE NOTICE 'mi_0062.message_uuid = %', v_msg;

   SELECT count(*) INTO v_kz_cnt
     FROM xxi.kz_charges
    WHERE cmessageid = (SELECT correlation_id::text FROM xxi.mi_req WHERE req_id = v_req_id);

   RAISE NOTICE 'kz_charges rows      = %', v_kz_cnt;

   RAISE NOTICE '===============================';
   RAISE NOTICE 'ИТОГО:';
   RAISE NOTICE '  req_id        = %', v_req_id;
   RAISE NOTICE '  itm_id        = %', v_itm_id;
   RAISE NOTICE '  ires_code     = %  (ожидание: 0)', v_ires;
   RAISE NOTICE '  message_uuid  = %  (ожидание: не NULL)', v_msg;
   RAISE NOTICE '  kz_charges    = %  (ожидание: 1)', v_kz_cnt;
   RAISE NOTICE '===============================';

   IF v_ires <> 0 THEN
      RAISE EXCEPTION 'Ожидался ires_code = 0, получено %', v_ires;
   END IF;

   IF v_msg IS NULL THEN
      RAISE EXCEPTION 'Ожидался message_uuid заполненным';
   END IF;

   IF v_kz_cnt <> 1 THEN
      RAISE EXCEPTION 'Ожидалась 1 запись в kz_charges, получено %', v_kz_cnt;
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
       r.created_at,
       i.itm_id,
       i.id_value,
       i.ires_code,
       i.tres_time,
       i.cres_info,
       i.message_uuid,
       (SELECT count(*) FROM xxi.kz_charges WHERE cmessageid = r.correlation_id::text) AS kz_cnt
  FROM xxi.mi_req r
  JOIN xxi.mi_0062 i ON i.req_id = r.req_id
  WHERE r.req_id = <req_id>;
*/
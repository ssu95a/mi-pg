-- Триггер    : t_ad_mi_req__delete_req_id
-- Назначение : Удаление ID из таблицы mi_req_id
-- Описание   : При DELETE удалет ID из mi_req_id
--
CREATE OR REPLACE FUNCTION mi_request_trg.tf_ad_mi_req__delete_req_id()
RETURNS 
   trigger
LANGUAGE 
   plpgsql
AS
$function$
BEGIN
   DELETE
     FROM xxi.mi_req_id
    WHERE req_id = OLD.req_id;
   RETURN NULL;
END;
$function$
;

CREATE OR REPLACE TRIGGER 
   t_ad_mi_req__delete_req_id
AFTER 
   DELETE
ON
   xxi.mi_req
FOR
   EACH ROW
EXECUTE 
   FUNCTION mi_request_trg.tf_ad_mi_req__delete_req_id()
;

COMMENT ON FUNCTION mi_request_trg.tf_ad_mi_req__delete_req_id() IS 'Trigger function mi_request_trg.tf_ad_mi_req__delete_req_id {$Id$}'
;

COMMENT ON TRIGGER t_ad_mi_req__delete_req_id ON xxi.mi_req IS 'Trigger t_ad_mi_req__delete_req_id on xxi.mi_req {$Id$}'
;

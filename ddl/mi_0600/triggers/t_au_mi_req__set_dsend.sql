CREATE SCHEMA IF NOT EXISTS mi_request_trg;

-- Триггерная функция: реакция на переход статуса 2 -> 3
CREATE OR REPLACE FUNCTION mi_request_trg.tf_au_mi_req__set_dsend()
RETURNS trigger AS $$
BEGIN
   CALL mi_0600_api.on_request_sent(NEW.req_id);
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION mi_request_trg.tf_au_mi_req__set_dsend()
IS 'Trigger function mi_request_trg.tf_au_mi_req__set_dsend. $Id$'
;

-- Триггер на mi_req
CREATE OR REPLACE TRIGGER t_au_mi_req__set_dsend
AFTER UPDATE OF status_cd ON xxi.mi_req
FOR EACH ROW
WHEN (OLD.status_cd = 2 AND NEW.status_cd = 3)
EXECUTE FUNCTION mi_request_trg.tf_au_mi_req__set_dsend();

COMMENT ON TRIGGER t_au_mi_req__set_dsend
ON xxi.mi_req
IS 'Trigger t_ad_mi_req__delete_req_id on xxi.mi_req. $Id$'
;
-- Триггерная функция: реакция на переход статуса 2 -> 3
CREATE OR REPLACE FUNCTION xxi.mi_req_status_to_sent_fn()
RETURNS trigger AS $$
BEGIN
   CALL mi_0600_api.on_request_sent(NEW.req_id);
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер на mi_req
CREATE TRIGGER mi_req_status_to_sent
AFTER UPDATE OF status_cd ON xxi.mi_req
FOR EACH ROW
WHEN (OLD.status_cd = 2 AND NEW.status_cd = 3)
EXECUTE FUNCTION xxi.mi_req_status_to_sent_fn();
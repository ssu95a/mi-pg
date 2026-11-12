-- NOTE хранит служебное примечание только для промежуточных состояний.
-- При переходе в конечные статусы DONE (1) / ERROR (-1)
-- старое NOTE очищается, если вызывающий код явно не записал новое значение.
CREATE OR REPLACE FUNCTION mi_request_trg.tf_bu_mi_req__clear_note()
RETURNS trigger
   LANGUAGE plpgsql
AS
$function$
BEGIN

   IF NEW.status_cd IS DISTINCT FROM OLD.status_cd AND NEW.status_cd IN (1, -1)
      AND NEW.note IS NOT DISTINCT FROM OLD.note
   THEN
      NEW.note := NULL;
   END IF;

   RETURN NEW;

END;
$function$
;
CREATE OR REPLACE TRIGGER t_bu_mi_req__clear_note
BEFORE UPDATE OF status_cd
ON xxi.mi_req
FOR EACH ROW
EXECUTE FUNCTION mi_request_trg.tf_bu_mi_req__clear_note()
;
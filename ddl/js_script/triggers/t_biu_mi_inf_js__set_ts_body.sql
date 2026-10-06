-- Триггер    : t_biu_mi_inf_js__set_ts_body
-- Назначение : Установка времени последнего изменения тела JS-скрипта
-- Описание   : При INSERT устанавливает ts_body, при UPDATE изменяет его только при изменении js_body
--
CREATE OR REPLACE FUNCTION mi_request_trg.tf_biu_mi_inf_js__set_ts_body()
RETURNS trigger
LANGUAGE plpgsql
AS
$function$
BEGIN
   IF TG_OP = 'INSERT' THEN
      NEW.ts_body := current_timestamp;
      RETURN NEW;
   END IF;

   IF NEW.js_body IS DISTINCT FROM OLD.js_body THEN
      NEW.ts_body := current_timestamp;
   END IF;

   RETURN NEW;
END;
$function$
;
CREATE OR REPLACE TRIGGER t_biu_mi_inf_js__set_ts_body
BEFORE 
   INSERT OR UPDATE
ON 
   xxi.mi_inf_js
FOR
   EACH ROW
EXECUTE
   FUNCTION mi_request_trg.tf_biu_mi_inf_js__set_ts_body()
;
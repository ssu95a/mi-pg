--
-- View       : xxi.v_mi_0008_req
-- Назначение : Список запосов по доходам, 8, 81 ВС
-- Описание   : wrap над mi_req, для раскрытия спец атрибутов ВС
drop VIEW xxi.v_mi_0008_req
;
CREATE VIEW xxi.v_mi_0008_req
AS 
 SELECT
   mi_req.req_id,
   mi_req.inf_id,
   mi_req.created_at,
   mi_req.correlation_id,
   mi_req.status_cd,
   case inf_id when 81 then 1 else -1 end initiator_cd,
   mi_req.idsmr,
   mi_req.ctaxreq_id,
   mi_req.i1 as iyear,
   mi_req.i2 as irsn_corr
 FROM mi_req 
WHERE
   mi_req.inf_id in (8,81)
;
COMMENT ON VIEW xxi.v_mi_0008_req IS 
   'MI-edo. Доходы физ лиц. Список запросов по доходам 1.0.2. $Id$'
;

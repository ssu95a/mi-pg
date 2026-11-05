-- MI_0081: request uniqueness for single inbound 81 and outbound 8 per kind.
-- Execute after the mi_req_0081 partition has been created.
--
-- One accepted inbound request has i3=0; rejected duplicates have i3=NULL.
CREATE UNIQUE INDEX IF NOT EXISTS ux_mi_req_0081__original_single
   ON xxi.mi_req_0081 (original_request_uuid)
   TABLESPACE indexes
   WHERE original_request_uuid IS NOT NULL AND i3 = 0
;

-- One outbound correction per source 81 and correction kind (Doc / Sum).
CREATE UNIQUE INDEX IF NOT EXISTS ux_mi_req_0008__parent_kind
   ON xxi.mi_req_0008 (parent_req_id, i3)
   TABLESPACE indexes
   WHERE parent_req_id IS NOT NULL AND i3 IN (1, 2)
;

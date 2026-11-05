--
-- MI_0081: один входящий заголовок 81, kind переносится в позиции.
-- Migration for already deployed tables; existing 81 records are preserved.
--
ALTER TABLE xxi.mi_0081
   ADD COLUMN IF NOT EXISTS kind numeric(1)
;

-- Для старых запросов (где kind был в mi_req.i3) восстанавливаем тип позиции.
UPDATE xxi.mi_0081 AS i
   SET kind = r.i3
  FROM xxi.mi_req AS r
 WHERE r.req_id = i.req_id
   AND r.inf_id = 81
   AND r.i3 IN (1, 2)
   AND i.kind IS NULL
;

DO $migration$
BEGIN
   IF NOT EXISTS (
      SELECT 1
        FROM pg_constraint
       WHERE conrelid = 'xxi.mi_0081'::regclass
         AND conname = 'ck_mi_0081__kind'
   ) THEN
      ALTER TABLE xxi.mi_0081
         ADD CONSTRAINT ck_mi_0081__kind CHECK (kind IN (1, 2));
   END IF;
END;
$migration$
;

COMMENT ON COLUMN xxi.mi_0081.kind IS
   'Вид запрашиваемой коррекции: 1 = документы, 2 = суммы'
;

-- i3=0 обозначает новый единый входящий запрос 81.
-- i3=NULL оставляем для служебных отказов; исторические i3=1/2 не переписываем.
CREATE UNIQUE INDEX IF NOT EXISTS ux_mi_req_0081__original_single
   ON xxi.mi_req_0081 (original_request_uuid)
   TABLESPACE indexes
   WHERE original_request_uuid IS NOT NULL AND i3 = 0
;

-- Для одного входящего 81 и каждого kind может быть не более одного исходящего 8.
CREATE UNIQUE INDEX IF NOT EXISTS ux_mi_req_0008__parent_kind
   ON xxi.mi_req_0008 (parent_req_id, i3)
   TABLESPACE indexes
   WHERE parent_req_id IS NOT NULL AND i3 IN (1, 2)
;

-- POS-17817
-- Добавляем партицию для 81 ВС
DO $$
BEGIN
   IF NOT EXISTS (
      SELECT 1
        FROM pg_inherits
       WHERE inhparent = 'xxi.mi_req'::regclass
         AND inhrelid = to_regclass('xxi.mi_req_0081')
   ) THEN
   -- Отдельная партиция для ВС 81.
   CREATE TABLE xxi.mi_req_0081 PARTITION OF xxi.mi_req FOR VALUES IN (81) TABLESPACE users
   ;
   -- Локальный индекс на партицию!
   -- Для одного внешнего запроса допускается:
   --   i3 = 1: один запрос Doc;
   --   i3 = 2: один запрос Sum.
   ALTER TABLE xxi.mi_req_0081 OWNER TO "XXI"
   ;
   COMMENT ON TABLE xxi.mi_req_0081 IS
      'MI-edo. Заголовки входящих запросов ФНС, ВС 81. {$Id$}'
   ;
   END IF
   ;
   CREATE UNIQUE INDEX IF NOT EXISTS ux_mi_req_0081__original_kind ON xxi.mi_req_0081 ( original_request_uuid, i3 ) 
      TABLESPACE indexes
         WHERE original_request_uuid IS NOT NULL AND i3 IN (1, 2) 
   ;
   COMMENT ON INDEX xxi.ux_mi_req_0081__original_kind IS
      'Один запрос Doc и один Sum на original_request_uuid для ВС 81'
   ;
END;
$$;


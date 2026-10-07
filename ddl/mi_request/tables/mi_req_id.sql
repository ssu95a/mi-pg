-- Таблица   : xxi.mi_req_id
-- Назначение: Глобальный реестр req_id.
-- Описание  : Эмулирует "глобальный уникальный индекс" для req_id
CREATE TABLE IF NOT EXISTS xxi.mi_req_id (
   
   req_id numeric(12) not null 
      default nextval('xxi.s_mi_req'::regclass),

   created_at timestamp with time zone not null
      default clock_timestamp(),

-- Constraints
-- PK
   constraint pk_mi_req_id primary key (req_id) using index tablespace indexes
)
tablespace indexes
;
-- Owner
ALTER TABLE xxi.mi_req_id OWNER TO "XXI"
;
-- Comments
COMMENT ON TABLE xxi.mi_req_id is
   'MI-edo. Реестр запросов. Глобальный реестр идентификаторов запросов. Используется как якорь для FK по req_id. {$Id$}'

COMMENT ON COLUMN xxi.mi_req_id.req_id is
   'Глобально уникальный идентификатор запроса'
;
COMMENT ON COLUMN xxi.mi_req_id.created_at is
   'Дата и время резервирования req_id'
;

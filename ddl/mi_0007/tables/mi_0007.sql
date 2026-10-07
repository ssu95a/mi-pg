--
-- Таблица    : xxi.mi_0007
-- Назначение : Элементы запросов паспорта физ лиц
-- Описание   : Запросы на валидность паспортов
--
CREATE TABLE IF NOT EXISTS xxi.mi_0007 (
-- +------------------------------------------------------------------------------------
-- |   column      |  type      |   null  | default 
-- +------------------------------------------------------------------------------------
      itm_id        numeric(12)   NOT NULL  DEFAULT nextval('xxi.s_mi_item'::regclass),
      external_uuid uuid          NOT NULL  DEFAULT uuidv7(),
      req_id        numeric(12)   NOT NULL,
      
      person_id     numeric(12)   NOT NULL,
      
      created_at    timestamp     NOT NULL  DEFAULT current_timestamp,
   -- бизнес ответ на запрос
      message_uuid  uuid              NULL,

      ires_code     numeric(3)        NULL,
      tres_time     timestamptz       NULL,
      cres_info     text              NULL,
      -- код обработки при ошибке
      error_code    varchar(100)      NULL,

-- constraints
-- PK
   constraint pk_mi_0007 primary key (itm_id) using index tablespace indexes,
-- UK
   constraint uk_0007_external_uuid unique (external_uuid) using index tablespace indexes,
-- FK      
   constraint fk_mi_0007__req_id foreign key (req_id   ) references xxi.mi_req_id (req_id   ) on delete cascade,
   constraint fk_mi_0007__person foreign key (person_id) references xxi.mi_person (person_id)
)
tablespace users
;
-- Indexes
create index if not exists fx_mi_0007__req_id on xxi.mi_0007 using btree ( req_id ) tablespace indexes
;
create index if not exists fx_mi_0007__person_id on xxi.mi_0007 using btree ( person_id ) tablespace indexes
;
-- Grants
alter table xxi.mi_0007 owner to "xxi"
;
-- Comments
comment on table xxi.mi_0007 is 
   'MI-edo. Валидность данных физ лиц. Запросы валидности паспортов физ лиц $Id: {1.0.1} {06.10.2026} Sulimoff$'
;
COMMENT ON COLUMN xxi.mi_0007.itm_id is 
   'ID элемента запроса'
;
COMMENT ON COLUMN xxi.mi_0007.req_id is 
   'ID запроса /mi_req/'
;
COMMENT ON COLUMN xxi.mi_0007.person_id is 
   'ID физ лица /mi_person/'
;
COMMENT ON COLUMN xxi.mi_0007.ires_code is 
   'Код результата из MI или -1 в случае ошибки при обработке элемента'
;
COMMENT ON COLUMN xxi.mi_0007.cres_info is 
   'Информация о результате'
;
COMMENT ON COLUMN xxi.mi_0007.tres_time is 
   'Дата/время получения результата'
;
COMMENT ON COLUMN xxi.mi_0007.message_uuid is 
   'ID сообщения из MI, где был обработан элемент'
;

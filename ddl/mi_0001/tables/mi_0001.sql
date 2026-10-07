--
-- Таблица    : xxi.mi_0001
-- Назначение : Элементы запросов ИНН физ лиц
-- Описание   : Запросы на получения ИНН по данным физ лица
--
CREATE TABLE IF NOT EXISTS xxi.mi_0001 (
-- +---------------------------------------------------------------------------
-- |     column     |    type    |   null   | default 
-- +---------------------------------------------------------------------------
      itm_id         numeric(12)   NOT NULL   DEFAULT nextval('xxi.s_mi_item'::regclass),
      external_uuid  uuid          NOT NULL   DEFAULT uuidv7(),
      req_id         numeric(12)   NOT NULL,

      person_id      numeric(12)   NOT NULL,
      icusnum        numeric(12)   NOT NULL,

      created_at     timestamp     NOT NULL   DEFAULT current_timestamp,

      inn            varchar(13)       NULL,
      inn_check_on   date              NULL,
            
      ires_code      numeric(3)        NULL,
      tres_time      timestamp         NULL,
      cres_info      text              NULL,
      message_uuid   uuid              NULL,
      -- код обработки при ошибке
      error_code     varchar(100)      NULL,

-- constraints
-- PK
   constraint pk_mi_0001 primary key (itm_id) using index tablespace indexes,

-- UK
   constraint uk_0001_external_uuid unique (external_uuid) using index tablespace indexes,

-- FK      
   constraint fk_mi_0001__req_id foreign key (req_id   ) references xxi.mi_req_id (req_id   ) on delete cascade,
   constraint fk_mi_0001__person foreign key (person_id) references xxi.mi_person (person_id),
   constraint fk_mi_0001__cus    foreign key (icusnum  ) references xxi."CUS" (icusnum)
)
TABLESPACE users
;

-- Indexes
create index if not exists fx_mi_0001__req_id on xxi.mi_0001 using btree ( req_id ) tablespace indexes
;
create index if not exists fx_mi_0001__person_id on xxi.mi_0001 using btree ( person_id ) tablespace indexes
;
create index if not exists fx_mi_0001__icusnum on xxi.mi_0001 using btree ( icusnum ) tablespace indexes
;
create index if not exists ix_mi_0001__message_uuid on xxi.mi_0001(message_uuid) tablespace indexes where message_uuid is not null
;

-- Grants
ALTER TABLE xxi.mi_0001 owner to "XXI"
;

-- Comments
COMMENT ON TABLE xxi.mi_0001 is 
   'MI-edo. ИНН физ.лица. Запрос cведений об ИНН физ лица $Id: {1.0.1} {06.10.2026} Sulimoff$'
;
COMMENT ON COLUMN xxi.mi_0001.itm_id is 
   'ID элемента запроса'
;
COMMENT ON COLUMN xxi.mi_0001.req_id is 
   'ID запроса /mi_req/'
;
COMMENT ON COLUMN xxi.mi_0001.person_id is 
   'ID физ лица /mi_person/'
;
COMMENT ON COLUMN xxi.mi_0001.icusnum is 
   'ID клиента XXI /CUS/'
;
COMMENT ON COLUMN xxi.mi_0001.inn is 
   'Инн полученный в качестве ответа'
;
COMMENT ON COLUMN xxi.mi_0001.inn_check_on is 
   'Дата, на которую проверяется актуальность признака самозанятого (дата запроса)'
;
COMMENT ON COLUMN xxi.mi_0001.ires_code is 
   'Код результата из MI'
;
COMMENT ON COLUMN xxi.mi_0001.cres_info is 
   'Информация о результате'
;
COMMENT ON COLUMN xxi.mi_0001.tres_time is 
   'Дата/время получения результата'
;
COMMENT ON COLUMN xxi.mi_0001.inn is 
   'ИНН полученный из MI'
;
COMMENT ON COLUMN xxi.mi_0001.message_uuid is 
   'ID сообщения из MI, где был обработан элемент'
;

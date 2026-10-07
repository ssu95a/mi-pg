--
-- Таблица    : xxi.mi_req
-- Назначение :Реестр запросов. Таблица единого реестра
-- Описание   : Хранит все заголовки запросов. Исходник для VIEW по видам сведений. Партицированная по inf_id. Нет PK!
-- 
CREATE TABLE IF NOT EXISTS xxi.mi_req (
-- +---------------------------------------------------------------------------
-- |     column     |    type    |    null   | default 
-- +---------------------------------------------------------------------------
      req_id         numeric(12)   NOT NULL,
      inf_id         numeric(6)    NOT NULL,
      external_uuid  uuid          NOT NULL   DEFAULT uuidv7(),
      created_at     timestamp     NOT NULL   DEFAULT current_timestamp,
      status_cd      numeric(3)    NOT NULL   DEFAULT 0,
      idsmr          varchar(3)    NOT NULL   DEFAULT sys_context('B21'::character varying, 'IDSmr'::character varying),
      correlation_id uuid          NOT NULL,
      note           text              NULL, 
      ctaxreq_id     varchar(50)       NULL,
      itype          numeric(3)        NULL,
      i1             numeric(3)        NULL, 
      i2             numeric(3)        NULL,
      i3             numeric(3)        NULL,
      result_code    varchar(100)      NULL,
      result_info    varchar(300)      NULL,
      result_time    timestamp         NULL,
      message_uuid   uuid              NULL,
      original_request_uuid
                     uuid              NULL,
      parent_req_id  numeric(12)       NULL,

-- Constraints:
-- FK
   CONSTRAINT fk_mi_req__req_id
      FOREIGN KEY (req_id)
         REFERENCES xxi.mi_req_id(req_id)
            ON DELETE CASCADE,

   CONSTRAINT fk_mi_req__mi_inf
      FOREIGN KEY (inf_id)
        REFERENCES xxi.mi_inf(inf_id),

   CONSTRAINT fk_mi_req__smr
      FOREIGN KEY (idsmr)
         REFERENCES xxi."SMR"(idsmr),

   -- родительский запрос
   CONSTRAINT fk_mi_req__parent_req
      foreign key (parent_req_id)
         references xxi.mi_req_id (req_id),

-- Check
-- Статус запроса
   CONSTRAINT ck_mi_req__status_cd
        CHECK ( status_cd in ( 0, 1, 2, 3, -1) )
)
PARTITION 
   BY LIST (inf_id);

-- Indexes
-- FK на req_Id
create index if not exists fx_mi_req__req_id
   on xxi.mi_req (req_id)
      tablespace indexes
;
create index if not exists ix_mi_req__correlation_id
   on xxi.mi_req (correlation_id)
      tablespace indexes
;
create index if not exists ix_mi_req__inf_id_created_at
   on xxi.mi_req (inf_id, created_at)
      tablespace indexes
;
create index if not exists ix_mi_req__inf_ctaxreq 
   on xxi.mi_req( inf_id, ctaxreq_id ) 
      tablespace indexes
;
create index if not exists ix_mi_req__external_uuid
   on xxi.mi_req (external_uuid)
      tablespace indexes
;
create index if not exists ix_mi_req__original_request_uuid
   on xxi.mi_req(original_request_uuid)
      tablespace indexes
         where original_request_uuid is not null
;
create index if not exists ix_mi_req__parent_req_id
   on xxi.mi_req (parent_req_id)
      tablespace indexes
         where parent_req_id is not null
;
-- Partitions
-- Валидация физ лиц
create table if not exists xxi.mi_req_0007
   partition of xxi.mi_req
      for values in ( 71, 72, 73, 74, 75 )
          tablespace users
;
-- ГИС ГМП - отправка
create table if not exists xxi.mi_req_0006
   partition of xxi.mi_req
      for values in ( 61 )
          tablespace users
;
-- Доходы физ лиц
create table if not exists xxi.mi_req_0008
   partition of xxi.mi_req
      for values in ( 8 )
          tablespace users
;
-- ИНН физ лиц
create table if not exists xxi.mi_req_0001
   partition of xxi.mi_req
      for values in ( 12, 13 )
          tablespace users
;
-- ЗАГС
create table if not exists xxi.mi_req_0010
   partition of xxi.mi_req
      for values in ( 10 )
          tablespace users
;
-- ЕГРИП/ЕГРЮЛ
create table if not exists xxi.mi_req_0003
   partition of xxi.mi_req
      for values in ( 32, 34 )
          tablespace users
;
-- РКЛ
create table if not exists xxi.mi_req_0023
   partition of xxi.mi_req
      for values in ( 23 )
          tablespace users
;
-- Нотариат
create table if not exists xxi.mi_req_0025
   partition of xxi.mi_req
      for values in ( 25 )
          tablespace users
;
-- Самозанятые
create table if not exists xxi.mi_req_0111
   partition of xxi.mi_req
      for values in ( 111 )
          tablespace users
;
-- ЭДО с ФНС
create table if not exists xxi.mi_req_0600
   partition of xxi.mi_req
      for values in ( 601, 602, 603, 604, 605, 606, 607, 608, 609, 610, 611, 612 )
          tablespace users
;
-- default
create table if not exists xxi.mi_req_default
   partition of xxi.mi_req
      default
         tablespace users
;
-- Owner
alter table xxi.mi_req owner to "XXI"
;
-- Comments
comment on table xxi.mi_req is
   'MI-edo. Реестр запросов. Таблица единого реестра. {$Id$}'

comment on column xxi.mi_req.inf_id is
   'Идентификатор вида сведений. Ключ партицирования /mi_inf/'
;
comment on column xxi.mi_req.req_id is
   'Идентификатор запроса из xxi.mi_req_id'
;
comment on column xxi.mi_req.created_at is
   'Дата и время создания заголовка запроса'
;
comment on column xxi.mi_req.correlation_id is
   'Корреляционный идентификатор запроса'
;
comment on column xxi.mi_req.status_cd is
   'Статус запроса: 0=new, 1=done, 2=in_work, 3=sent, -1=error'
;
comment on column xxi.mi_req.idsmr is
   'Идентификатор IDSMR'
;
comment on column xxi.mi_req.ctaxreq_id is
   'Идентификатор запроса из ФНС, там где нужен'
;
comment on column xxi.mi_req.external_uuid is
   'Внешний глобальный идентификатор запроса'
;
comment on column xxi.mi_req.result_code is
   'Код результата операции'
;
comment on column xxi.mi_req.result_info is
   'Инорфмация о результате'
;
comment on column xxi.mi_req.result_time is
   'Дата время получения информации'
;
comment on column xxi.mi_req.message_uuid is
   'ИД сообщения MI на который сформирован запрос или получен ответ'
;
comment on column xxi.mi_req.original_request_uuid is
   'ID исходного запроса в MI для входящих business-запросов MI -> XXL -> XXI'
;
comment on column xxi.mi_req.parent_req_id is
   'ID родительского запроса в MI'
;
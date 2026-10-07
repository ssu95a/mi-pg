--
-- Таблица    : xxi.mi_p2i
-- Назначение : Связь физ лиц и видов сведений
-- Описание   : Хранит связь ID физ лица и видоа сведения, где он участвует
--
create table if not exists xxi.mi_p2i (
   person_id numeric(12) NOT NULL,
   inf_id    numeric(6) NOT NULL,
   linked_at timestamp not null default current_timestamp,
   -- Constraints
   -- PK
   constraint pk_mi_p2i primary key (person_id, inf_id) using index tablespace indexes,
   -- FK
   constraint fk_mi_p2i__mi_inf foreign key (inf_id)
      references xxi.mi_inf (inf_id) 
         match full
         on delete cascade,

   constraint fk_mi_p2i__mi_person 
      foreign key (person_id)
         references xxi.mi_person (person_id) 
         match full
         on delete cascade
)
tablespace users
;
create index if not exists fx_mi_p2i__inf on xxi.mi_p2i using btree( inf_id ) tablespace indexes
;
comment on table xxi.mi_p2i is
   'MI-edo. Реестр физ лиц. Связь person и видами сведений {$Id$}'

comment on column xxi.mi_p2i.linked_at is
   'Когда была сформирована связь'
;
alter table xxi.mi_p2i owner to "XXI"
;

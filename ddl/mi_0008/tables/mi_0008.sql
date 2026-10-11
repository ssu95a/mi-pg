-- Таблица    : xxi.mi_0008
-- Назначение : Доходы физ-лиц
-- Описание   : Одна запись при отправке выписки. 1.0.1
--
CREATE TABLE IF NOT EXISTS xxi.mi_0008 (
-- +---------------------------------------------------------------------------
-- |   column      |  type      |   null  | default 
-- +---------------------------------------------------------------------------
      itm_id        numeric(12)   NOT NULL  DEFAULT nextval('xxi.s_mi_item'::regclass),
      external_uuid uuid          NOT NULL  DEFAULT uuidv7(),
      req_id        numeric(12)   NOT NULL,

      created_at    timestamp     NOT NULL  DEFAULT current_timestamp,

      icusnum       numeric(12)   NOT NULL,
      iyear         numeric(4 )   NOT NULL,
      icorr         numeric(2 )   NOT NULL  DEFAULT  0,

      inum          numeric(12)   NOT NULL  DEFAULT nextval('xxi.s_mi_0008__inum'::regclass),

      person_id     numeric(12)   NOT NULL,

      msum_f_dep    numeric(22,2) NULL,
      msum_i_dep    numeric(22,2) NULL,
      msum_f_crd    numeric(22,2) NULL,
      msum_i_crd    numeric(22,2) NULL,
      msum_i_acc    numeric(22,2) NULL,
      msum_f_acc    numeric(22,2) NULL,
-- constraints
-- PK
   constraint pk_mi_0008 primary key (itm_id) using index tablespace indexes,
-- UK
   constraint uk_mi_0008_cyc unique  (icusnum, iyear, icorr) using index tablespace indexes,
-- FK      
   constraint fk_mi_0008__req_id  foreign key (req_id   ) references xxi.mi_req_id (req_id   ) on delete cascade,
   constraint fk_mi_0008__person  foreign key (person_id) references xxi.mi_person (person_id),
   constraint fk_mi_0008__icusnum foreign key (icusnum  ) references xxi."CUS"(icusnum),
-- CK
   constraint ck_mi_0008__icorr CHECK (icorr BETWEEN 0 AND 99)
)
TABLESPACE users
;
ALTER TABLE xxi.mi_0008 OWNER TO "XXI"
;
COMMENT ON TABLE xxi.mi_0008 IS 
   'MI-edo. Доходы физ лиц. Одна запись при отправке выписки 1.0.1 {$Id$}'
;   
COMMENT ON COLUMN  xxi.mi_0008.icorr IS 
   'Номер корректировки: 0-изначальная, 99-удаление'
;
COMMENT ON COLUMN xxi.mi_0008.msum_f_dep IS 
   'Сумма процентов депозитов для физлица'
;
COMMENT ON COLUMN xxi.mi_0008.inum IS 
   'Порядковый номер - ID запроса, уникальный'
;
COMMENT ON COLUMN xxi.mi_0008.iyear IS 
   'Отчетный год'
;
COMMENT ON COLUMN xxi.mi_0008.msum_i_dep IS 
   'Сумма процентов депозитов для ИП'
;
COMMENT ON COLUMN xxi.mi_0008.msum_f_crd IS 
   'Доход по картам физ лица'
;
COMMENT ON COLUMN xxi.mi_0008.msum_i_crd IS 
   'Доход по картам ИП'
;
COMMENT ON COLUMN xxi.mi_0008.msum_i_acc IS 
   'Доход по счетам в ядре ИП'
;
COMMENT ON COLUMN xxi.mi_0008.msum_f_acc IS 
   'Доход по счетам в ядре ФЛ'
;
COMMENT ON COLUMN xxi.mi_0008.person_id IS 
   'Id клиента /ms_person/'
;
COMMENT ON COLUMN xxi.mi_0008.itm_id IS 
   'ID элемента запроса'
;

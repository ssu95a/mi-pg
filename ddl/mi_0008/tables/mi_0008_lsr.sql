-- Таблица    : xxi.mi_0008_lsr
-- Назначение : Доходы физ-лиц. Sanitarium
-- Описание   : Реестр процессов подготовки данных по виду сведений 0008.
--
CREATE TABLE IF NOT EXISTS xxi.mi_0008_lsr
(
-- +---------------------------------------------------------------------------
-- |   column      |  type      |   null  |  default 
-- +---------------------------------------------------------------------------

      lsr_id         numeric(12)  NOT NULL   DEFAULT nextval('xxi.s_mi_0008_lsr'::regclass)::numeric(12),

    -- Параметры расчета
      itype          numeric(2)   NOT NULL,
      iyear          numeric(4)   NOT NULL,
      irsn_corr      numeric(2)   NOT NULL,
      ireq_kind      numeric(2)   NOT NULL,

   -- Текущее состояние процесса
      status_cd      varchar(12)  NOT NULL DEFAULT 'RUNNING',
      stage_cd       varchar(20)  NOT NULL DEFAULT 'CREATED',

      started_at     timestamptz  NOT NULL DEFAULT clock_timestamp(),
      finished_at    timestamptz  NULL,

      -- Итоговый запрос. Может отсутствовать при NO_DATA или отказе.
      req_id         numeric(12)  NULL,

      ires_code      numeric(3)   NULL,
      cres_info      text         NULL,
      note           text         NULL,
      -- сессия айдита
      audit_session_id  numeric(12),

-- CONSTRAINTS
-- PK
   constraint pk_mi_0008_lsr primary key (lsr_id) using index tablespace indexes,

-- UK
-- Один LSR создаёт не более одного итогового запроса.
   constraint uk_mi_0008_lsr__req_id unique (req_id) using index tablespace indexes,

-- FK
   constraint fk_mi_0008_lsr__mi_req foreign key (req_id) references xxi.mi_req_id (req_id) on delete set null,

-- CHECK
   -- типы пачек
   constraint ck_mi_0008_lsr__itype check (itype in (1, 2, 3, 4)),
   -- причина корректировки
   constraint ck_mi_0008_lsr__irsn_corr check (irsn_corr in (1, 2)),
   -- вид отчета дул/сумма
   constraint ck_mi_0008_lsr__ireq_kind check (ireq_kind in (1, 2)),
   --   
   constraint ck_mi_0008_lsr__status check ( status_cd IN ( 'RUNNING', 'COMPLETED', 'REJECTED', 'FAILED'  ) ),
   --
   constraint ck_mi_0008_lsr__stage check ( stage_cd IN ( 'CREATED', 'SOURCE_CALC', 'SANITARIUM', 'FINAL_WRITE', 'FINISHED' ) ),
   --
   constraint ck_mi_0008_lsr__finished check ( ( status_cd = 'RUNNING' AND finished_at IS NULL ) OR ( status_cd <> 'RUNNING' AND finished_at IS NOT NULL ) ),
   --
   constraint ck_mi_0008_lsr__time check ( finished_at IS NULL OR finished_at >= started_at)
)
TABLESPACE users
;
ALTER TABLE xxi.mi_0008_lsr OWNER TO "XXI"
;
CREATE UNIQUE INDEX IF NOT EXISTS 
   ux_mi_0008_lsr__active_year 
      ON xxi.mi_0008_lsr (iyear) TABLESPACE indexes WHERE finished_at IS NULL
;
ALTER SEQUENCE xxi.s_mi_0008_lsr OWNED BY xxi.mi_0008_lsr.lsr_id
;
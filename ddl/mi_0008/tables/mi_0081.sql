--
-- Таблица    : xxi.mi_0081
-- Назначение : Регистрация входящих запросов ФНС (ВС 81)
-- Описание   : Позиции запроса ФНС со ссылкой на исходные сведения ВС 8
-- Версия     : 1.0.0
--
CREATE TABLE IF NOT EXISTS xxi.mi_0081 (
-- +---------------------------------------------------------------------------
-- |   column      |  type      |   null  | default 
-- +---------------------------------------------------------------------------

      itm_id         numeric(12)  NOT NULL    DEFAULT nextval('xxi.s_mi_item'::regclass),

      external_uuid  uuid         NOT NULL    DEFAULT uuidv7(),
      req_id         numeric(12)  NOT NULL,
      created_at     timestamp    NOT NULL    DEFAULT current_timestamp,

      -- Ссылка на исходную позицию ВС 8. NULL, если позиция не найдена.
      source_itm_id  numeric(12)  NULL,

   -- Реквизиты исходной позиции, полученные из Payload ФНС.
      iyear          numeric(4)   NOT NULL,
      inum           numeric(12)  NOT NULL,
      icorr          numeric(2)   NOT NULL,

   -- NULL = успешное сопоставление; NOT_FOUND = исходная позиция отсутствует.
      result_code    varchar(30) NULL,

   -- Constraints
   -- PK
      CONSTRAINT pk_mi_0081 PRIMARY KEY (itm_id) USING INDEX TABLESPACE indexes,

   -- Повторение позиции в рамках одного входящего запроса запрещено.
      CONSTRAINT uk_mi_0081__req_position UNIQUE (req_id, iyear, inum, icorr) USING INDEX TABLESPACE indexes,

   -- Одна найденная исходная строка может встречаться в запросе один раз.
   -- При source_itm_id IS NULL несколько NOT_FOUND допустимы.
      CONSTRAINT uk_mi_0081__req_source UNIQUE (req_id, source_itm_id) USING INDEX TABLESPACE indexes,

   -- FK
      CONSTRAINT fk_mi_0081__req_id FOREIGN KEY (req_id) REFERENCES xxi.mi_req_id (req_id) ON DELETE CASCADE,

      CONSTRAINT fk_mi_0081__source_itm_id FOREIGN KEY (source_itm_id) REFERENCES xxi.mi_0008 (itm_id),

   -- CHECK
      CONSTRAINT ck_mi_0081__iyear CHECK (iyear BETWEEN 1 AND 9999),

      CONSTRAINT ck_mi_0081__icorr CHECK (icorr BETWEEN 0 AND 99)
)
TABLESPACE users
;

-- Уникальная внешняя идентичность позиции ВС 81.
CREATE UNIQUE INDEX IF NOT EXISTS ux_mi_0081__external_uuid ON xxi.mi_0081 (external_uuid) TABLESPACE indexes
;

-- Индекс для поиска входящих позиций по исходной записи ВС 8.
CREATE INDEX IF NOT EXISTS fx_mi_0081__source_itm_id ON xxi.mi_0081 (source_itm_id) TABLESPACE indexes
;
-- owner
ALTER TABLE xxi.mi_0081 OWNER TO "XXI"
;
COMMENT ON TABLE xxi.mi_0081 IS
   'MI-edo. Позиции входящих запросов ФНС на уточнение сведений о доходах (ВС 81). 1.0.1 {$Id$}'
;
COMMENT ON COLUMN xxi.mi_0081.itm_id IS
   'Идентификатор позиции входящего запроса ФНС'
;
COMMENT ON COLUMN xxi.mi_0081.external_uuid IS
   'Внешний UUID позиции входящего запроса'
;
COMMENT ON COLUMN xxi.mi_0081.req_id IS
   'Идентификатор заголовка входящего запроса ВС 81 (mi_req)'
;
COMMENT ON COLUMN xxi.mi_0081.created_at IS
   'Дата и время регистрации входящей позиции'
;
COMMENT ON COLUMN xxi.mi_0081.source_itm_id IS
   'Ссылка на исходную строку xxi.mi_0008.itm_id; NULL, если строка не найдена'
;
COMMENT ON COLUMN xxi.mi_0081.iyear IS
   'Отчётный год исходной позиции, указанный ФНС'
;
COMMENT ON COLUMN xxi.mi_0081.inum IS
   'Номер исходной позиции из Payload ФНС'
;
COMMENT ON COLUMN xxi.mi_0081.icorr IS
   'Номер корректировки исходной позиции из Payload ФНС'
;
COMMENT ON COLUMN xxi.mi_0081.result_code IS
   'Диагностика сопоставления: NULL означает успех; NOT_FOUND — исходная позиция не найдена'
;
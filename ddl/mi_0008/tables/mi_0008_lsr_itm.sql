-- Протокол обработки клиентов в рамках запуска Sanitarium.
CREATE TABLE IF NOT EXISTS xxi.mi_0008_lsr_itm
(
-- +---------------------------------------------------------------------------
-- |   column      |  type      |   null  |  default 
-- +---------------------------------------------------------------------------

      lsr_itm_id numeric(12) NOT NULL DEFAULT nextval('xxi.s_mi_0008_lsr_itm'::regclass),

      lsr_id     numeric(12) NOT NULL,

    -- Исходный icusnum, полученный от депозитного модуля.
      s_icusnum  numeric(12) NOT NULL,

    -- Реальный icusnum после обработки связи типа 17.
    -- Для CUS_MAP всегда заполнен.
    -- Если замена не требуется: r_icusnum = s_icusnum.
      r_icusnum  numeric(12),

    -- CUS_MAP означает, что клиент прошёл Sanitarium и допущен
    -- к расчёту. Остальные значения являются кодами отказа
    -- или диагностическими событиями.
      result_code varchar(50) NOT NULL,

      result_info text,
      result_data text,

      created_at timestamptz NOT NULL DEFAULT clock_timestamp(),

   -- Constraints
   -- PK
   CONSTRAINT pk_mi_0008_lsr_itm PRIMARY KEY (lsr_itm_id) USING INDEX TABLESPACE indexes,

   -- FK
   CONSTRAINT fk_mi_0008_lsr_itm_lsr FOREIGN KEY (lsr_id) REFERENCES xxi.mi_0008_lsr (lsr_id) ON DELETE CASCADE,

   -- CHECK
    -- PostgreSQL, в отличие от Oracle, отличает '' от NULL.
    CONSTRAINT ck_mi_0008_lsr_itm_result_code CHECK (btrim(result_code) <> ''),

    -- Каждая разрешающая запись должна однозначно указывать, реального клиента.
    CONSTRAINT ck_mi_0008_lsr_itm_cus_map CHECK ( result_code <> 'CUS_MAP' OR r_icusnum IS NOT NULL )
)
TABLESPACE users
;


-- Для одного исходного клиента в рамках LSR допустимо
-- не более одного итогового отображения.
--
-- INCLUDE позволяет получать r_icusnum непосредственно из индекса
-- при соединении с результатом депозитного расчёта.
create unique index if not exists 
   ux_mi_0008_lsr_itm_cus_map ON xxi.mi_0008_lsr_itm( lsr_id, s_icusnum) 
      INCLUDE (r_icusnum) 
         TABLESPACE indexes 
            WHERE result_code = 'CUS_MAP';

-- Просмотр протокола запуска, выборка отказов и поддержка FK при удалении LSR.
create index if not exists ix_mi_0008_lsr_itm_lsr_result 
       on xxi.mi_0008_lsr_itm (lsr_id, result_code, s_icusnum) 
         tablespace indexes
;

alter sequence xxi.s_mi_0008_lsr_itm
      owned by xxi.mi_0008_lsr_itm.lsr_itm_id
;

ALTER TABLE xxi.mi_0008_lsr_itm 
      OWNER TO "XXI"
;

COMMENT ON TABLE xxi.mi_0008_lsr_itm IS
    'MI-edo. Доходы физических лиц. Протокол обработки клиентов в рамках LSR. '
    'Хранит разрешённые отображения исходного клиента в реального клиента '
    'и причины отклонения клиентов Sanitarium.'
;

COMMENT ON COLUMN xxi.mi_0008_lsr_itm.lsr_itm_id IS
   'PK. Идентификатор записи протокола Sanitarium.'
;

COMMENT ON COLUMN xxi.mi_0008_lsr_itm.lsr_id IS
   'FK на xxi.mi_0008_lsr. Идентификатор процесса подготовки данных.'
;

COMMENT ON COLUMN xxi.mi_0008_lsr_itm.s_icusnum IS
   'Исходный идентификатор клиента, полученный от депозитного модуля.'
;

COMMENT ON COLUMN xxi.mi_0008_lsr_itm.r_icusnum IS
   'Реальный идентификатор клиента после обработки связи типа 17. Для клиента без замены совпадает с s_icusnum.'
;

COMMENT ON COLUMN xxi.mi_0008_lsr_itm.result_code IS
   'Код решения Sanitarium. CUS_MAP означает, что клиент допущен к расчёту; остальные значения содержат коды отказа или диагностики.'
;

COMMENT ON COLUMN xxi.mi_0008_lsr_itm.result_info IS
   'Человекочитаемое описание решения, отказа или найденной проблемы.'
;

COMMENT ON COLUMN xxi.mi_0008_lsr_itm.result_data IS
   'Дополнительный технический контекст. Формат пока не регламентирован.'
;

COMMENT ON COLUMN xxi.mi_0008_lsr_itm.created_at IS
   'Фактическое время создания записи протокола.'
;

COMMENT ON INDEX xxi.ux_mi_0008_lsr_itm_cus_map IS
   'Не более одного отображения s_icusnum в r_icusnum в рамках одного LSR.'
;

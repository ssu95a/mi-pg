-- Таблица-слот 3 реестра контролируемых лиц
CREATE TABLE IF NOT EXISTS xxi.mi_rci_3 (
    cureg_id    CHAR(36),
    cdprf_id    VARCHAR(50),
    dbth        DATE,
    ipr_dbth    SMALLINT,
    cdoc_raw    VARCHAR(100),
    ddoc_date   DATE
);

-- Первичный ключ
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pk_mi_rci_3' AND contype = 'p') THEN
        ALTER TABLE xxi.mi_rci_3 ADD CONSTRAINT pk_mi_rci_3 PRIMARY KEY (cureg_id);
    END IF;
END $$;

-- Индекс по cdoc_raw
CREATE INDEX IF NOT EXISTS ix_mi_rci_3__cdoc_raw ON xxi.mi_rci_3 (cdoc_raw);

-- Комментарии к столбцам
COMMENT ON COLUMN xxi.mi_rci_3.cureg_id IS 'Уникальный идентификатор записи реестра (UUID)';
COMMENT ON COLUMN xxi.mi_rci_3.cdprf_id IS 'Идентификатор цифрового профиля';
COMMENT ON COLUMN xxi.mi_rci_3.dbth     IS 'Дата рождения';
COMMENT ON COLUMN xxi.mi_rci_3.ipr_dbth IS 'Признак неполноты даты рождения: 1 – месяц ''нп'', 2 – день ''нп'', NULL – полная дата';
COMMENT ON COLUMN xxi.mi_rci_3.cdoc_raw IS 'Серия и номер документа (сырое значение из реестра)';
COMMENT ON COLUMN xxi.mi_rci_3.ddoc_date IS 'Дата выдачи документа';

COMMENT ON TABLE xxi.mi_rci_3 IS
$$MI-edo. Реестр контролируемых лиц. Таблица-слот 3. '$id: {1.0.1} {22.07.2026} Sukhotina$'$$;
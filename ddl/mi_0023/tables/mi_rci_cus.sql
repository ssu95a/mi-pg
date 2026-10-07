-- Таблица связей реестра контролируемых лиц с клиентами CUS
CREATE TABLE IF NOT EXISTS xxi.mi_rci_cus (
    cureg_id    CHAR(36) NOT NULL,
    icusnum     NUMERIC(12)   NOT NULL,
    CONSTRAINT pk_mi_rci_cus PRIMARY KEY (cureg_id, icusnum)
);

COMMENT ON COLUMN xxi.mi_rci_cus.cureg_id IS 'Идентификатор записи реестра';
COMMENT ON COLUMN xxi.mi_rci_cus.icusnum  IS 'Идентификатор клиента CUS (ICUSNUM)';

COMMENT ON TABLE xxi.mi_rci_cus IS 
$$MI-edo. Реестр контролируемых лиц. Связи реестра с клиентами CUS. '$id: {1.0.1} {22.07.2026} Sukhotina$'$$;
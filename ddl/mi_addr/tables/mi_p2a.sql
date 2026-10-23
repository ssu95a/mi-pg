--
-- Таблица    : xxi.mi_p2a
-- Назначение : Связь физлиц с адресами
-- Описание   : Промежуточная таблица связи mi_person и mi_addr
--

CREATE TABLE IF NOT EXISTS xxi.mi_p2a (
    person_id   numeric(12) NOT NULL,   -- ID физлица
    addr_id     numeric(12) NOT NULL,   -- ID адреса
    itype       numeric     NOT NULL,   -- Тип адреса: 1 - постоянная регистрация, 2 - временная регистрация
    dbeg_reg    date,                   -- Дата начала срока регистрации
    dend_reg    date,                   -- Дата окончания срока регистрации
    CONSTRAINT pk_mi_p2a PRIMARY KEY (person_id, addr_id, itype)
        USING INDEX TABLESPACE indexes,
    CONSTRAINT fk_mi_p2a__mi_person FOREIGN KEY (person_id)
        REFERENCES xxi.mi_person(person_id) ON DELETE CASCADE,
    CONSTRAINT fk_mi_p2a__mi_addr FOREIGN KEY (addr_id)
        REFERENCES xxi.mi_addr(addr_id) ON DELETE CASCADE
) TABLESPACE users;

-- Индекс по addr_id
CREATE INDEX IF NOT EXISTS fx_mi_p2a__mi_addr
    ON xxi.mi_p2a USING btree (addr_id) TABLESPACE indexes;

-- Комментарии
COMMENT ON TABLE xxi.mi_p2a IS
'MI-edo. Адресные данные. Связь физлиц с адресами. $id: {1.0.1} {23.10.2026} Sukhotina$';

COMMENT ON COLUMN xxi.mi_p2a.person_id IS 'ID физлица /mi_person/';
COMMENT ON COLUMN xxi.mi_p2a.addr_id   IS 'ID адреса /mi_addr/';
COMMENT ON COLUMN xxi.mi_p2a.itype     IS 'Тип адреса: 1 - постоянная регистрация, 2 - временная регистрация';
COMMENT ON COLUMN xxi.mi_p2a.dbeg_reg  IS 'Дата начала срока регистрации';
COMMENT ON COLUMN xxi.mi_p2a.dend_reg  IS 'Дата окончания срока регистрации';
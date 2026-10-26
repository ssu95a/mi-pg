--
-- Таблица    : xxi.mi_addr
-- Назначение : Адресные данные
-- Описание   : Адреса, привязанные к запросам и элементам запросов
--

CREATE TABLE IF NOT EXISTS xxi.mi_addr (
    addr_id         numeric(12) NOT NULL DEFAULT nextval('xxi.s_mi_addr'), -- ID адреса
    req_id          numeric(12) NOT NULL,                         -- ID запроса /mi_req_id/
    itm_id          numeric(12),                                  -- ID элемента запроса
    ckladr_code     varchar(30),                                  -- Код по КЛАДР
    cpostcode       varchar(6),                                   -- Индекс
    cregion_code    varchar(2),                                   -- Код региона
    cregion_type    varchar(30),                                  -- Тип региона
    cregion_name    varchar(50),                                  -- Наименование региона
    carea_type      varchar(30),                                  -- Тип района
    carea_name      varchar(100),                                 -- Наименование района
    ccity_type      varchar(30),                                  -- Тип города
    ccity_name      varchar(50),                                  -- Наименование города
    cplace_type     varchar(30),                                  -- Тип населенного пункта
    cplace_name     varchar(250),                                 -- Наименование населенного пункта
    cstreet_type    varchar(30),                                  -- Тип улицы
    cstreet_name    varchar(200),                                 -- Наименование улицы
    chouse          varchar(100),                                 -- Номер дома
    cbuild          varchar(100),                                 -- Корпус
    capart          varchar(100),                                 -- Квартира/офис
    cfias_code      char(36),                                     -- Идентификатор адреса в ФИАС
    cstrct          varchar(100),                                 -- Строение
    cctya3          char(3),                                      -- Код страны (Alpha3)
    coktmo_code     varchar(20),                                  -- Код региона по ОКТМО
    cunstrct_addr   varchar(250),                                 -- Неструктурированный адрес
    created_at      timestamptz DEFAULT clock_timestamp() NOT NULL, -- Дата создания
    CONSTRAINT pk_mi_addr PRIMARY KEY (addr_id)
        USING INDEX TABLESPACE indexes,
    CONSTRAINT fk_mi_addr__mi_req_id FOREIGN KEY (req_id)
        REFERENCES xxi.mi_req_id(req_id) ON DELETE CASCADE
) TABLESPACE users;

-- Индексы
CREATE INDEX IF NOT EXISTS fx_mi_addr__mi_req_id
    ON xxi.mi_addr USING btree (req_id) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS ix_mi_addr__itm_id
    ON xxi.mi_addr USING btree (itm_id) TABLESPACE indexes
    WHERE itm_id IS NOT NULL;

-- Комментарии
COMMENT ON TABLE xxi.mi_addr IS
'MI-edo. Адресные данные. Адреса, привязанные к запросам и элементам запросов. $id: {1.0.1} {23.10.2026} Sukhotina$';

COMMENT ON COLUMN xxi.mi_addr.addr_id       IS 'ID адреса';
COMMENT ON COLUMN xxi.mi_addr.req_id        IS 'ID запроса /mi_req_id/';
COMMENT ON COLUMN xxi.mi_addr.itm_id        IS 'ID элемента запроса (таблица элемента определяется через mi_req.inf_id)';
COMMENT ON COLUMN xxi.mi_addr.ckladr_code   IS 'Код по КЛАДР';
COMMENT ON COLUMN xxi.mi_addr.cpostcode     IS 'Индекс';
COMMENT ON COLUMN xxi.mi_addr.cregion_code  IS 'Код региона';
COMMENT ON COLUMN xxi.mi_addr.cregion_type  IS 'Тип региона';
COMMENT ON COLUMN xxi.mi_addr.cregion_name  IS 'Наименование региона';
COMMENT ON COLUMN xxi.mi_addr.carea_type    IS 'Тип района';
COMMENT ON COLUMN xxi.mi_addr.carea_name    IS 'Наименование района';
COMMENT ON COLUMN xxi.mi_addr.ccity_type    IS 'Тип города';
COMMENT ON COLUMN xxi.mi_addr.ccity_name    IS 'Наименование города';
COMMENT ON COLUMN xxi.mi_addr.cplace_type   IS 'Тип населенного пункта';
COMMENT ON COLUMN xxi.mi_addr.cplace_name   IS 'Наименование населенного пункта';
COMMENT ON COLUMN xxi.mi_addr.cstreet_type  IS 'Тип улицы';
COMMENT ON COLUMN xxi.mi_addr.cstreet_name  IS 'Наименование улицы';
COMMENT ON COLUMN xxi.mi_addr.chouse        IS 'Номер дома';
COMMENT ON COLUMN xxi.mi_addr.cbuild        IS 'Корпус';
COMMENT ON COLUMN xxi.mi_addr.capart        IS 'Квартира/офис';
COMMENT ON COLUMN xxi.mi_addr.cfias_code    IS 'Идентификатор адреса в ФИАС';
COMMENT ON COLUMN xxi.mi_addr.cstrct        IS 'Строение';
COMMENT ON COLUMN xxi.mi_addr.cctya3        IS 'Код страны (Alpha3)';
COMMENT ON COLUMN xxi.mi_addr.coktmo_code   IS 'Код региона по ОКТМО';
COMMENT ON COLUMN xxi.mi_addr.cunstrct_addr IS 'Неструктурированный адрес';
COMMENT ON COLUMN xxi.mi_addr.created_at    IS 'Дата создания';
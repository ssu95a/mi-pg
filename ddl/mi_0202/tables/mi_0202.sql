--
-- Таблица    : xxi.mi_0202
-- Назначение : Элементы запросов вида сведений 0202
-- Описание   : Социальные счета. Договор социального вклада/счёта
--

CREATE TABLE IF NOT EXISTS xxi.mi_0202 (
    itm_id              numeric(12) NOT NULL,                       -- ID элемента запроса
    external_uuid       uuid DEFAULT gen_random_uuid() NOT NULL,    -- Внешний UUID элемента
    req_id              numeric(12) NOT NULL,                       -- ID запроса /mi_req_id/
    person_id           numeric(12),                                -- ID физлица /mi_person/
    icusnum             numeric(12),                                -- ID клиента XXI (заполняется ФПЗ)
    kind                varchar(50) NOT NULL,                       -- Подвид документа: Appeal / CancelRequest / Message / signRequest / signResponse
    order_id            numeric(38),                                -- Идентификатор заявления на ЕПГУ (orderId)
    order_timestamp     timestamptz,                                -- Дата и время формирования заявления (orderTimestamp)
    subservice_code     varchar(100),                               -- Код услуги (subservice.code)
    subservice_title    varchar(500),                               -- Наименование услуги (subservice.title)
    subservice_data     jsonb,                                      -- Свободные атрибуты услуги (subservice.anyData, variantData)
    agreement_type      varchar(50),                                -- Тип продукта: Счет / Вклад (из subservice.anyData.Product_Type.What_kind_agreement)
    documents           jsonb,                                      -- Документы (documents[] с метаданными вложений)
    payload             text,                                       -- Исходный JSON от Джавы
    created_at          timestamptz DEFAULT clock_timestamp() NOT NULL, -- Дата создания элемента
    ires_code           numeric(3) DEFAULT 0,                       -- Код результата: 0 - черновик
    tres_time           timestamptz,                                -- Время получения результата
    cres_info           text,                                       -- Информация о результате
    message_uuid        uuid,                                       -- ID сообщения, обработавшего элемент
    error_code          varchar(100),                               -- Код ошибки при обработке
    CONSTRAINT pk_mi_0202 PRIMARY KEY (itm_id)
        USING INDEX TABLESPACE indexes,
    CONSTRAINT uk_mi_0202__external_uuid UNIQUE (external_uuid)
        USING INDEX TABLESPACE indexes,
    CONSTRAINT fk_mi_0202__mi_req_id FOREIGN KEY (req_id)
        REFERENCES xxi.mi_req_id(req_id) ON DELETE CASCADE,
    CONSTRAINT fk_mi_0202__mi_person FOREIGN KEY (person_id)
        REFERENCES xxi.mi_person(person_id),
    CONSTRAINT fk_mi_0202__cus FOREIGN KEY (icusnum)
        REFERENCES xxi."CUS"(icusnum)
) TABLESPACE users;

-- Индексы
CREATE INDEX IF NOT EXISTS fx_mi_0202__mi_req_id
    ON xxi.mi_0202 USING btree (req_id) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS fx_mi_0202__mi_person
    ON xxi.mi_0202 USING btree (person_id) TABLESPACE indexes
    WHERE person_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS fx_mi_0202__cus
    ON xxi.mi_0202 USING btree (icusnum) TABLESPACE indexes
    WHERE icusnum IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_mi_0202__kind
    ON xxi.mi_0202 USING btree (kind) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS ix_mi_0202__order_id
    ON xxi.mi_0202 USING btree (order_id) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS ix_mi_0202__message_uuid
    ON xxi.mi_0202 USING btree (message_uuid) TABLESPACE indexes
    WHERE message_uuid IS NOT NULL;

-- Комментарии
COMMENT ON TABLE xxi.mi_0202 IS
'MI-edo. Социальные счета. Договор социального вклада/счёта (вид сведений 0202). $id: {1.0.1} {23.10.2026} Sukhotina$';

COMMENT ON COLUMN xxi.mi_0202.itm_id           IS 'ID элемента запроса';
COMMENT ON COLUMN xxi.mi_0202.external_uuid    IS 'Внешний UUID элемента';
COMMENT ON COLUMN xxi.mi_0202.req_id           IS 'ID запроса /mi_req_id/';
COMMENT ON COLUMN xxi.mi_0202.person_id        IS 'ID физлица /mi_person/';
COMMENT ON COLUMN xxi.mi_0202.icusnum          IS 'ID клиента XXI (заполняется ФПЗ при проверке)';
COMMENT ON COLUMN xxi.mi_0202.kind             IS 'Подвид документа: Appeal / CancelRequest / Message / signRequest / signResponse';
COMMENT ON COLUMN xxi.mi_0202.order_id         IS 'Идентификатор заявления на ЕПГУ (orderId)';
COMMENT ON COLUMN xxi.mi_0202.order_timestamp  IS 'Дата и время формирования заявления (orderTimestamp)';
COMMENT ON COLUMN xxi.mi_0202.subservice_code  IS 'Код услуги (subservice.code)';
COMMENT ON COLUMN xxi.mi_0202.subservice_title IS 'Наименование услуги (subservice.title)';
COMMENT ON COLUMN xxi.mi_0202.subservice_data  IS 'Свободные атрибуты услуги (subservice.anyData, variantData)';
COMMENT ON COLUMN xxi.mi_0202.agreement_type   IS 'Тип продукта: Счет / Вклад (из subservice.anyData.Product_Type.What_kind_agreement)';
COMMENT ON COLUMN xxi.mi_0202.documents        IS 'Документы (documents[] с метаданными вложений)';
COMMENT ON COLUMN xxi.mi_0202.payload          IS 'Исходный JSON от Джавы';
COMMENT ON COLUMN xxi.mi_0202.created_at       IS 'Дата создания элемента';
COMMENT ON COLUMN xxi.mi_0202.ires_code        IS 'Код результата: 0 - черновик';
COMMENT ON COLUMN xxi.mi_0202.tres_time        IS 'Время получения результата';
COMMENT ON COLUMN xxi.mi_0202.cres_info        IS 'Информация о результате';
COMMENT ON COLUMN xxi.mi_0202.message_uuid     IS 'ID сообщения, обработавшего элемент';
COMMENT ON COLUMN xxi.mi_0202.error_code       IS 'Код ошибки при обработке';
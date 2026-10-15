--
-- Таблица    : xxi.mi_0202
-- Назначение : Элементы запросов вида сведений 0202
-- Описание   : Социальные счета. Договор социального вклада/счёта
--

CREATE TABLE IF NOT EXISTS xxi.mi_0202 (
    itm_id              numeric(12) NOT NULL,                       -- ID элемента запроса
    external_uuid       uuid DEFAULT gen_random_uuid() NOT NULL,    -- Внешний UUID элемента
    req_id              numeric(12) NOT NULL,                       -- ID запроса /mi_req_id/
    icusnum             numeric(12),                                -- ID клиента XXI (если найден)
    kind                varchar(50) NOT NULL,                       -- Подвид: Appeal / CancelRequest / Message / signRequest / signResponse
    order_id            numeric(38),                                -- Идентификатор заявления на ЕПГУ (orderId)
    order_timestamp     timestamptz,                                -- Дата и время формирования заявления (orderTimestamp)
    subservice_code     varchar(100),                               -- Код услуги (subservice.code)
    subservice_title    varchar(500),                               -- Наименование услуги (subservice.title)
    subservice_mnemonic varchar(200),                               -- Мнемоника услуги (subservice.mnemonic)
    subservice_data     jsonb,                                      -- Свободные атрибуты услуги (subservice.anyData, variantData)
    documents           jsonb,                                      -- Документы (documents[] с метаданными вложений)
    -- Идентификационные данные заявителя (person или foreignPerson)
    person_last_name    varchar(150),                               -- Фамилия
    person_first_name   varchar(100),                               -- Имя
    person_middle_name  varchar(150),                               -- Отчество
    person_inn          varchar(12),                                -- ИНН
    person_snils        varchar(11),                                -- СНИЛС
    person_birthday     date,                                       -- Дата рождения
    doc_type_code       varchar(20),                                -- Код типа документа (personalDoc.documentType.code)
    doc_type_name       varchar(500),                               -- Наименование типа документа (personalDoc.documentType.name)
    doc_series          varchar(20),                                -- Серия документа
    doc_number          varchar(20),                                -- Номер документа
    doc_issuer_code     varchar(20),                                -- Код подразделения, выдавшего документ
    doc_issuer_name     varchar(500),                               -- Наименование органа, выдавшего документ
    doc_issue_date      date,                                       -- Дата выдачи документа
    -- Технические поля
    payload             text,                                       -- Исходный JSON от Джавы
    created_at          timestamptz DEFAULT clock_timestamp() NOT NULL, -- Дата создания элемента
    ires_code           numeric(3),                                 -- Код результата: 0 - успех, -1 - ошибка, 1 - данные не найдены
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
    CONSTRAINT fk_mi_0202__cus FOREIGN KEY (icusnum)
        REFERENCES xxi."CUS"(icusnum)
) TABLESPACE users;

-- Индексы
CREATE INDEX IF NOT EXISTS fx_mi_0202__mi_req_id
    ON xxi.mi_0202 USING btree (req_id) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS fx_mi_0202__cus
    ON xxi.mi_0202 USING btree (icusnum) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS ix_mi_0202__kind
    ON xxi.mi_0202 USING btree (kind) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS ix_mi_0202__order_id
    ON xxi.mi_0202 USING btree (order_id) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS ix_mi_0202__message_uuid
    ON xxi.mi_0202 USING btree (message_uuid) TABLESPACE indexes
    WHERE message_uuid IS NOT NULL;

-- Комментарии
COMMENT ON TABLE xxi.mi_0202 IS
'MI-edo. Социальные счета. Договор социального вклада/счёта (вид сведений 0202). $id: {1.0.1} {15.10.2026} Sukhotina$';

COMMENT ON COLUMN xxi.mi_0202.itm_id              IS 'ID элемента запроса';
COMMENT ON COLUMN xxi.mi_0202.external_uuid       IS 'Внешний UUID элемента';
COMMENT ON COLUMN xxi.mi_0202.req_id              IS 'ID запроса /mi_req_id/';
COMMENT ON COLUMN xxi.mi_0202.icusnum             IS 'ID клиента XXI (если найден)';
COMMENT ON COLUMN xxi.mi_0202.kind                IS 'Подвид документа: Appeal / CancelRequest / Message / signRequest / signResponse';
COMMENT ON COLUMN xxi.mi_0202.order_id            IS 'Идентификатор заявления на ЕПГУ (orderId)';
COMMENT ON COLUMN xxi.mi_0202.order_timestamp     IS 'Дата и время формирования заявления (orderTimestamp)';
COMMENT ON COLUMN xxi.mi_0202.subservice_code     IS 'Код услуги (subservice.code)';
COMMENT ON COLUMN xxi.mi_0202.subservice_title    IS 'Наименование услуги (subservice.title)';
COMMENT ON COLUMN xxi.mi_0202.subservice_mnemonic IS 'Мнемоника услуги (subservice.mnemonic)';
COMMENT ON COLUMN xxi.mi_0202.subservice_data     IS 'Свободные атрибуты услуги (subservice.anyData, variantData)';
COMMENT ON COLUMN xxi.mi_0202.documents           IS 'Документы (documents[] с метаданными вложений)';
COMMENT ON COLUMN xxi.mi_0202.person_last_name    IS 'Фамилия заявителя';
COMMENT ON COLUMN xxi.mi_0202.person_first_name   IS 'Имя заявителя';
COMMENT ON COLUMN xxi.mi_0202.person_middle_name  IS 'Отчество заявителя';
COMMENT ON COLUMN xxi.mi_0202.person_inn          IS 'ИНН заявителя';
COMMENT ON COLUMN xxi.mi_0202.person_snils        IS 'СНИЛС заявителя';
COMMENT ON COLUMN xxi.mi_0202.person_birthday     IS 'Дата рождения заявителя';
COMMENT ON COLUMN xxi.mi_0202.doc_type_code       IS 'Код типа документа';
COMMENT ON COLUMN xxi.mi_0202.doc_type_name       IS 'Наименование типа документа';
COMMENT ON COLUMN xxi.mi_0202.doc_series          IS 'Серия документа';
COMMENT ON COLUMN xxi.mi_0202.doc_number          IS 'Номер документа';
COMMENT ON COLUMN xxi.mi_0202.doc_issuer_code     IS 'Код подразделения, выдавшего документ';
COMMENT ON COLUMN xxi.mi_0202.doc_issuer_name     IS 'Наименование органа, выдавшего документ';
COMMENT ON COLUMN xxi.mi_0202.doc_issue_date      IS 'Дата выдачи документа';
COMMENT ON COLUMN xxi.mi_0202.payload             IS 'Исходный JSON от Джавы';
COMMENT ON COLUMN xxi.mi_0202.created_at          IS 'Дата создания элемента';
COMMENT ON COLUMN xxi.mi_0202.ires_code           IS 'Код результата: 0 - успех, -1 - ошибка, 1 - данные не найдены';
COMMENT ON COLUMN xxi.mi_0202.tres_time           IS 'Время получения результата';
COMMENT ON COLUMN xxi.mi_0202.cres_info           IS 'Информация о результате';
COMMENT ON COLUMN xxi.mi_0202.message_uuid        IS 'ID сообщения, обработавшего элемент';
COMMENT ON COLUMN xxi.mi_0202.error_code          IS 'Код ошибки при обработке';
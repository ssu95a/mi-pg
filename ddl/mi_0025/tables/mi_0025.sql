--
-- Таблица    : xxi.mi_0025
-- Назначение : Элементы запросов вида сведений 025
-- Описание   : Нотариат
--

CREATE TABLE IF NOT EXISTS xxi.mi_0025 (
    itm_id          numeric(12) NOT NULL,               -- ID элемента запроса
    external_uuid   uuid DEFAULT gen_random_uuid() NOT NULL, -- внешний UUID элемента
    req_id          numeric(12) NOT NULL,               -- ID запроса /mi_req_id/
    version         varchar(10) NOT NULL,               -- Версия формата
    request_id      uuid NOT NULL,                      -- ID запроса нотариата (GUID)
    request_date    timestamptz NOT NULL,               -- Дата запроса
    creditor_name   varchar(2000) NOT NULL,             -- Информация о займодавце
    debtor_name     varchar(2000) NOT NULL,             -- Информация о заёмщике
    cred_id         varchar(50) NOT NULL,               -- Идентификатор кредитной организации
    cred_name       varchar(2000) NOT NULL,             -- Наименование кредитной организации
    n_full_name     varchar(255) NOT NULL,              -- Полное имя нотариуса
    n_fed_num       varchar(50) NOT NULL,               -- Федеральный номер нотариуса
    n_uivid         uuid NOT NULL,                      -- UivId нотариуса
    a_full_name     varchar(255),                       -- Полное имя ВРИО нотариуса
    a_fed_num       varchar(50),                        -- Федеральный номер ВРИО нотариуса
    a_uivid         uuid,                               -- UivId ВРИО нотариуса
    attach_name     varchar(250) NOT NULL,              -- Наименование вложения
    attach_hash     varchar(250) NOT NULL,              -- Hash-код вложения (Base64)
    attach_hash_type varchar(10) NOT NULL,              -- Алгоритм расчёта хэша (SHA-256)
    attach_file     bytea NOT NULL,                     -- Файл вложения (PDF)
    created_at      timestamptz DEFAULT clock_timestamp() NOT NULL, -- Дата создания элемента

    confirmed_usr_id  numeric,                          -- ID пользователя, подтвердившего ответ /USR/
    confirmed_value   numeric,                          -- Решение: 1 – подтверждаю, 0 – не подтверждаю
    confirmed_at      timestamptz,                      -- Дата и время подтверждения
    confirmed_name    varchar(255),                     -- Имя подтвердившего (на момент подтверждения)
    confirmed_post    varchar(255),                     -- Должность подтвердившего
    
    payload         text,                               -- Исходный XML/JSON запроса

    CONSTRAINT pk_mi_0025 PRIMARY KEY (itm_id),
    CONSTRAINT uk_mi_0025__external_uuid UNIQUE (external_uuid),
    CONSTRAINT fk_mi_0025__mi_req_id FOREIGN KEY (req_id) REFERENCES xxi.mi_req_id(req_id) ON DELETE CASCADE,
    CONSTRAINT fk_mi_0025__usr FOREIGN KEY (confirmed_usr_id) REFERENCES xxi.usr(iusrid),
    CONSTRAINT ck_mi_0025__confirmed_value CHECK (confirmed_value IN (0,1))
)
TABLESPACE users;

-- Индексы для поиска
CREATE INDEX IF NOT EXISTS ix_mi_0025__req_id ON xxi.mi_0025 USING btree (req_id);
CREATE INDEX IF NOT EXISTS ix_mi_0025__request_id ON xxi.mi_0025 USING btree (request_id);
CREATE INDEX IF NOT EXISTS ix_mi_0025__n_uivid ON xxi.mi_0025 USING btree (n_uivid);
CREATE INDEX IF NOT EXISTS ix_mi_0025__a_uivid ON xxi.mi_0025 USING btree (a_uivid) WHERE a_uivid IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_mi_0025__cred_id ON xxi.mi_0025 USING btree (cred_id);
CREATE INDEX IF NOT EXISTS ix_mi_0025__confirmed_usr_id ON xxi.mi_0025 USING btree (confirmed_usr_id) WHERE confirmed_usr_id IS NOT NULL;

-- Комментарии
COMMENT ON TABLE  xxi.mi_0025 IS 'MI-edo. Нотариат. Элементы запроса (входящие данные). $Id$';
COMMENT ON COLUMN xxi.mi_0025.itm_id IS 'ID элемента запроса';
COMMENT ON COLUMN xxi.mi_0025.external_uuid IS 'Внешний UUID элемента';
COMMENT ON COLUMN xxi.mi_0025.req_id IS 'ID запроса /mi_req_id/';
COMMENT ON COLUMN xxi.mi_0025.version IS 'Версия формата';
COMMENT ON COLUMN xxi.mi_0025.request_id IS 'ID запроса нотариата (GUID)';
COMMENT ON COLUMN xxi.mi_0025.request_date IS 'Дата запроса';
COMMENT ON COLUMN xxi.mi_0025.creditor_name IS 'Информация о займодавце';
COMMENT ON COLUMN xxi.mi_0025.debtor_name IS 'Информация о заёмщике';
COMMENT ON COLUMN xxi.mi_0025.cred_id IS 'Идентификатор кредитной организации';
COMMENT ON COLUMN xxi.mi_0025.cred_name IS 'Наименование кредитной организации';
COMMENT ON COLUMN xxi.mi_0025.n_full_name IS 'Полное имя нотариуса';
COMMENT ON COLUMN xxi.mi_0025.n_fed_num IS 'Федеральный номер нотариуса';
COMMENT ON COLUMN xxi.mi_0025.n_uivid IS 'UivId нотариуса';
COMMENT ON COLUMN xxi.mi_0025.a_full_name IS 'Полное имя ВРИО нотариуса';
COMMENT ON COLUMN xxi.mi_0025.a_fed_num IS 'Федеральный номер ВРИО нотариуса';
COMMENT ON COLUMN xxi.mi_0025.a_uivid IS 'UivId ВРИО нотариуса';
COMMENT ON COLUMN xxi.mi_0025.attach_name IS 'Наименование вложения';
COMMENT ON COLUMN xxi.mi_0025.attach_hash IS 'Hash-код вложения (Base64)';
COMMENT ON COLUMN xxi.mi_0025.attach_hash_type IS 'Алгоритм расчёта хэша (SHA-256)';
COMMENT ON COLUMN xxi.mi_0025.attach_file IS 'Файл вложения (PDF)';
COMMENT ON COLUMN xxi.mi_0025.created_at IS 'Дата создания элемента';
COMMENT ON COLUMN xxi.mi_0025.confirmed_usr_id IS 'ID пользователя, подтвердившего ответ';
COMMENT ON COLUMN xxi.mi_0025.confirmed_value IS 'Решение: 1 – подтверждаю, 0 – не подтверждаю';
COMMENT ON COLUMN xxi.mi_0025.confirmed_at IS 'Дата и время подтверждения';
COMMENT ON COLUMN xxi.mi_0025.confirmed_name IS 'Имя подтвердившего (на момент подтверждения)';
COMMENT ON COLUMN xxi.mi_0025.confirmed_post IS 'Должность подтвердившего';
COMMENT ON COLUMN xxi.mi_0025.payload IS 'Исходный XML/JSON запроса';
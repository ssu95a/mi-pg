--
-- Таблица    : xxi.mi_0600
-- Назначение : Элементы запросов видов сведений 601-604, 611, 612
-- Описание   : ЭДО с ФНС
--

CREATE TABLE xxi.mi_0600 (
    itm_id           numeric(12) NOT NULL,                     -- ID элемента запроса
    external_uuid    uuid DEFAULT gen_random_uuid() NOT NULL,  -- Внешний UUID элемента
    req_id           numeric(12) NOT NULL,                     -- ID запроса /mi_req_id/
    czip_name        varchar(300) NOT NULL,                    -- Наименование ZIP-архива
    bzip_data        bytea,                                    -- Данные архива (ZIP)
    izip_size        integer,                                  -- Размер архива (КБ или байты)
    izip_files_count integer,                                  -- Количество файлов в архиве
    ires_code        integer,                                  -- Код результата обработки
    dsend_stamp      timestamptz,                              -- Время постановки в очередь отправки
    icreate_type     integer DEFAULT 0,                        -- Способ создания: 1 - автоматически, 0 - вручную
    cerr_msg         varchar(255),                             -- Текст ошибки (если есть)
    was_uploaded     integer DEFAULT 0,                        -- Признак выгрузки архива (1 - выгружен)
    created_at       timestamptz DEFAULT clock_timestamp() NOT NULL, -- Дата создания элемента
    message_uuid     uuid,                                     -- ID сообщения (для ответчиков)
    CONSTRAINT pk_mi_0600 PRIMARY KEY (itm_id),
    CONSTRAINT uk_mi_0600__req_id UNIQUE (req_id),
    CONSTRAINT uk_mi_0600_external_uuid UNIQUE (external_uuid),
    CONSTRAINT fk_mi_0600__req FOREIGN KEY (req_id) REFERENCES xxi.mi_req_id(req_id) ON DELETE CASCADE
) TABLESPACE users;

-- Индексы
CREATE INDEX ix_mi_0600__czip_name    ON xxi.mi_0600 USING btree (czip_name);
CREATE INDEX ix_mi_0600__dsend_stamp  ON xxi.mi_0600 USING btree (dsend_stamp);
CREATE INDEX ix_mi_0600__message_uuid ON xxi.mi_0600 USING btree (message_uuid) WHERE message_uuid IS NOT NULL;

-- Комментарии
COMMENT ON TABLE  xxi.mi_0600 IS 'СМЭВ-3. ЭДО с ФНС (виды сведений 601-604, 611, 612). Элементы запросов (ZIP-архивы)';
COMMENT ON COLUMN xxi.mi_0600.itm_id           IS 'ID элемента запроса';
COMMENT ON COLUMN xxi.mi_0600.external_uuid    IS 'Внешний UUID элемента';
COMMENT ON COLUMN xxi.mi_0600.req_id           IS 'ID запроса /mi_req_id/';
COMMENT ON COLUMN xxi.mi_0600.czip_name        IS 'Наименование ZIP-архива';
COMMENT ON COLUMN xxi.mi_0600.bzip_data        IS 'Данные ZIP-архива';
COMMENT ON COLUMN xxi.mi_0600.izip_size        IS 'Размер архива';
COMMENT ON COLUMN xxi.mi_0600.izip_files_count IS 'Количество файлов в архиве';
COMMENT ON COLUMN xxi.mi_0600.ires_code        IS 'Код результата обработки';
COMMENT ON COLUMN xxi.mi_0600.dsend_stamp      IS 'Время постановки в очередь отправки';
COMMENT ON COLUMN xxi.mi_0600.icreate_type     IS 'Способ создания: 1 - автоматически, 0 - вручную';
COMMENT ON COLUMN xxi.mi_0600.cerr_msg         IS 'Текст ошибки, если код не равен 0';
COMMENT ON COLUMN xxi.mi_0600.was_uploaded     IS 'Признак выгрузки архива (1 - выгружен)';
COMMENT ON COLUMN xxi.mi_0600.created_at       IS 'Дата создания элемента';
COMMENT ON COLUMN xxi.mi_0600.message_uuid     IS 'ID сообщения (для ответчиков)';

ALTER TABLE xxi.mi_0600 ADD COLUMN cres_info  text;
ALTER TABLE xxi.mi_0600 ADD COLUMN tres_time  timestamptz;

COMMENT ON COLUMN xxi.mi_0600.cres_info IS 'Информация о результате';
COMMENT ON COLUMN xxi.mi_0600.tres_time IS 'Время получения результата';
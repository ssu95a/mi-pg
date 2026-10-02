--
-- Таблица    : xxi.mi_0003
-- Назначение : Элементы запросов вида сведений 003
-- Описание   : Запросы на ЕГРЮЛ/ЕГРИП
--

CREATE TABLE IF NOT EXISTS xxi.mi_0003 (
    itm_id         numeric(12) NOT NULL,        -- ID элемента запроса
    external_uuid  uuid DEFAULT gen_random_uuid() NOT NULL, -- внешний UUID элемента
    req_id         numeric(12) NOT NULL,        -- ID запроса /mi_req_id/
    cus_type       smallint NOT NULL,           -- Тип субъекта: 2-ЮЛ, 4-ИП
    icusnum        numeric(12) NOT NULL,        -- ID клиента XXI /CUS/
    cogrn          varchar(20),                 -- ОГРН/ОГРНИП
    cinn           varchar(12),                 -- ИНН
    created_at     timestamptz DEFAULT clock_timestamp() NOT NULL, -- дата создания элемента
    payload        text,                        -- исходный ответ СМЭВ (XML/JSON)
    ires_code      numeric(3),                  -- код результата из СМЭВ
    tres_time      timestamptz,                 -- время получения результата
    cres_info      text,                        -- информация о результате
    message_uuid   uuid,                        -- ID сообщения, обработавшего элемент
    error_code     varchar(100),                -- код ошибки при обработке
    CONSTRAINT pk_mi_0003 PRIMARY KEY (itm_id),
    CONSTRAINT uk_0003_external_uuid UNIQUE (external_uuid),
    CONSTRAINT fk_mi_0003__req FOREIGN KEY (req_id) REFERENCES xxi.mi_req_id(req_id) ON DELETE CASCADE,
    CONSTRAINT fk_mi_0003__cus FOREIGN KEY (icusnum) REFERENCES xxi."CUS"(icusnum)
)
TABLESPACE users;

-- Индексы
CREATE INDEX IF NOT EXISTS fx_mi_0003__icusnum    ON xxi.mi_0003 USING btree (icusnum);
--CREATE INDEX IF NOT EXISTS fx_mi_0003__person_id  ON xxi.mi_0003 USING btree (person_id) WHERE person_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS fx_mi_0003__req_id     ON xxi.mi_0003 USING btree (req_id);
CREATE INDEX IF NOT EXISTS ix_mi_0003__message_uuid ON xxi.mi_0003 USING btree (message_uuid) WHERE message_uuid IS NOT NULL;
CREATE INDEX IF NOT EXISTS fx_mi_0003__cogrn      ON xxi.mi_0003 USING btree (cogrn) WHERE cogrn IS NOT NULL;
CREATE INDEX IF NOT EXISTS fx_mi_0003__cinn       ON xxi.mi_0003 USING btree (cinn) WHERE cinn IS NOT NULL;

-- Комментарии
COMMENT ON TABLE  xxi.mi_0003 IS 'СМЭВ-3. Запрос сведений ЕГРЮЛ/ЕГРИП (вид сведений 003)';
COMMENT ON COLUMN xxi.mi_0003.itm_id         IS 'ID элемента запроса';
COMMENT ON COLUMN xxi.mi_0003.external_uuid  IS 'Внешний UUID элемента';
COMMENT ON COLUMN xxi.mi_0003.req_id         IS 'ID запроса /mi_req_id/';
COMMENT ON COLUMN xxi.mi_0003.cus_type       IS 'Тип субъекта: 2-ЮЛ, 4-ИП';
COMMENT ON COLUMN xxi.mi_0003.icusnum        IS 'ID клиента XXI /CUS/';
COMMENT ON COLUMN xxi.mi_0003.cogrn          IS 'ОГРН/ОГРНИП';
COMMENT ON COLUMN xxi.mi_0003.cinn           IS 'ИНН';
COMMENT ON COLUMN xxi.mi_0003.created_at     IS 'Дата создания элемента';
COMMENT ON COLUMN xxi.mi_0003.payload        IS 'Исходный ответ СМЭВ (XML/JSON)';
COMMENT ON COLUMN xxi.mi_0003.ires_code      IS 'Код результата из СМЭВ';
COMMENT ON COLUMN xxi.mi_0003.tres_time      IS 'Время получения результата';
COMMENT ON COLUMN xxi.mi_0003.cres_info      IS 'Информация о результате';
COMMENT ON COLUMN xxi.mi_0003.message_uuid   IS 'ID сообщения, обработавшего элемент';
COMMENT ON COLUMN xxi.mi_0003.error_code     IS 'Код ошибки при обработке';
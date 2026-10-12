--
-- Таблица    : xxi.mi_0062
-- Назначение : Элементы запросов вида сведений 0062
-- Описание   : Начисления по УИН/ЕИП
--

CREATE TABLE IF NOT EXISTS xxi.mi_0062 (
    itm_id          numeric(12) NOT NULL,                        -- ID элемента запроса
    external_uuid   uuid DEFAULT gen_random_uuid() NOT NULL,     -- Внешний UUID элемента
    req_id          numeric(12) NOT NULL,                        -- ID запроса /mi_req_id/
    icusnum         numeric(12),                                 -- ID клиента XXI (если привязан)
    id_value        varchar(250) NOT NULL,                       -- Номер УИН или ЕИП
    created_at      timestamptz DEFAULT clock_timestamp() NOT NULL, -- Дата создания элемента
    ires_code       numeric(3),                                  -- Код результата: 0 - успех, -1 - ошибка, 1 - данные не найдены
    tres_time       timestamptz,                                 -- Время получения результата
    cres_info       text,                                        -- Информация о результате
    message_uuid    uuid,                                        -- ID сообщения, обработавшего элемент
    error_code      varchar(100),                                -- Код ошибки при обработке
    CONSTRAINT pk_mi_0062 PRIMARY KEY (itm_id)
        USING INDEX TABLESPACE indexes,
    CONSTRAINT uk_mi_0062__external_uuid UNIQUE (external_uuid)
        USING INDEX TABLESPACE indexes,
    CONSTRAINT fk_mi_0062__mi_req_id FOREIGN KEY (req_id)
        REFERENCES xxi.mi_req_id(req_id) ON DELETE CASCADE,
    CONSTRAINT fk_mi_0062__cus FOREIGN KEY (icusnum)
        REFERENCES xxi."CUS"(icusnum)
) TABLESPACE users;

-- Индексы
CREATE INDEX IF NOT EXISTS fx_mi_0062__cus
   ON xxi.mi_0062 USING btree (icusnum) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS fx_mi_0062__mi_req_id
   ON xxi.mi_0062 USING btree (req_id) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS ix_mi_0062__id_value
   ON xxi.mi_0062 USING btree (id_value) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS ix_mi_0062__message_uuid
   ON xxi.mi_0062 USING btree (message_uuid) TABLESPACE indexes
   WHERE message_uuid IS NOT NULL;

-- Комментарии
COMMENT ON TABLE  xxi.mi_0062 IS
'MI-edo. Начисления. Запрос начислений по УИН/ЕИП (вид сведений 0062). $id: {1.0.1} {09.10.2026} Sukhotina$';

COMMENT ON COLUMN xxi.mi_0062.itm_id        IS 'ID элемента запроса';
COMMENT ON COLUMN xxi.mi_0062.external_uuid IS 'Внешний UUID элемента';
COMMENT ON COLUMN xxi.mi_0062.req_id        IS 'ID запроса /mi_req_id/';
COMMENT ON COLUMN xxi.mi_0062.icusnum       IS 'ID клиента XXI (если привязан)';
COMMENT ON COLUMN xxi.mi_0062.id_value      IS 'Номер УИН или ЕИП';
COMMENT ON COLUMN xxi.mi_0062.created_at    IS 'Дата создания элемента';
COMMENT ON COLUMN xxi.mi_0062.ires_code     IS 'Код результата: 0 - успех, -1 - ошибка, 1 - данные не найдены';
COMMENT ON COLUMN xxi.mi_0062.tres_time     IS 'Время получения результата';
COMMENT ON COLUMN xxi.mi_0062.cres_info     IS 'Информация о результате';
COMMENT ON COLUMN xxi.mi_0062.message_uuid  IS 'ID сообщения, обработавшего элемент';
COMMENT ON COLUMN xxi.mi_0062.error_code    IS 'Код ошибки при обработке';
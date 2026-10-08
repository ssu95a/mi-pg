-- Управляющая таблица загрузки реестра контролируемых лиц
CREATE TABLE IF NOT EXISTS xxi."MI_RCI_CTRL" (
    ctrl_id             NUMERIC,              -- Идентификатор управляющей записи (всегда 1)
    active_slot         CHAR(1) NOT NULL,     -- Активный слот данных (1,2,3)
    status              VARCHAR(10) NOT NULL, -- Статус загрузки: OK, LOADING, FAIL
    stage               VARCHAR(50),          -- Текущий этап загрузки
    started_at          TIMESTAMPTZ,          -- Время старта загрузки
    finished_at         TIMESTAMPTZ,          -- Время завершения загрузки
    last_error          VARCHAR(4000),        -- Текст последней ошибки (обрезан до 4000 символов)
    last_loaded_rows    NUMERIC,              -- Количество загруженных строк в последней успешной загрузке
    stage_started_at    TIMESTAMPTZ,          -- Время начала текущего этапа
    req_id              NUMERIC(12),          -- Идентификатор запроса (mi_req.req_id), в рамках которого выполнялась загрузка
    CONSTRAINT pk_mi_rci_ctrl              PRIMARY KEY (ctrl_id),
    CONSTRAINT ck_mi_rci_ctrl__active_slot CHECK ((active_slot = ANY (ARRAY['1'::bpchar, '2'::bpchar, '3'::bpchar]))),
    CONSTRAINT ck_mi_rci_ctrl__ctrl_id     CHECK ((ctrl_id = 1)),
    CONSTRAINT ck_mi_rci_ctrl__status      CHECK (((status)::text = ANY ((ARRAY['OK'::character varying, 'LOADING'::character varying, 'FAIL'::character varying])::text[])))
);

-- Инициализация единственной строки
INSERT INTO xxi."MI_RCI_CTRL" (ctrl_id, active_slot, status)
VALUES (1, '1', 'OK')
ON CONFLICT (ctrl_id) DO NOTHING;

COMMENT ON COLUMN xxi."MI_RCI_CTRL".ctrl_id          IS 'Идентификатор управляющей записи (всегда 1)';
COMMENT ON COLUMN xxi."MI_RCI_CTRL".active_slot      IS 'Активный слот данных (1,2,3)';
COMMENT ON COLUMN xxi."MI_RCI_CTRL".status           IS 'Статус загрузки: OK, LOADING, FAIL';
COMMENT ON COLUMN xxi."MI_RCI_CTRL".stage            IS 'Текущий этап загрузки';
COMMENT ON COLUMN xxi."MI_RCI_CTRL".started_at       IS 'Время старта загрузки';
COMMENT ON COLUMN xxi."MI_RCI_CTRL".finished_at      IS 'Время завершения загрузки';
COMMENT ON COLUMN xxi."MI_RCI_CTRL".last_error       IS 'Текст последней ошибки (обрезан до 4000 символов)';
COMMENT ON COLUMN xxi."MI_RCI_CTRL".last_loaded_rows IS 'Количество загруженных строк в последней успешной загрузке';
COMMENT ON COLUMN xxi."MI_RCI_CTRL".stage_started_at IS 'Время начала текущего этапа';
COMMENT ON COLUMN xxi."MI_RCI_CTRL".req_id           IS 'Идентификатор запроса (mi_req.req_id), в рамках которого выполнялась загрузка';

COMMENT ON TABLE xxi."MI_RCI_CTRL" IS
'MI-edo. Реестр контролируемых лиц. Управляющая таблица загрузки. $Id$';
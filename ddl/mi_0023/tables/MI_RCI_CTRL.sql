-- Управляющая таблица загрузки реестра контролируемых лиц
CREATE TABLE IF NOT EXISTS xxi."MI_RCI_CTRL" (
    ctrl_id             INTEGER PRIMARY KEY CHECK (ctrl_id = 1),
    active_slot         CHAR(1) NOT NULL CHECK (active_slot IN ('1','2','3')),
    status              VARCHAR(10) NOT NULL CHECK (status IN ('OK','LOADING','FAIL')),
    stage               VARCHAR(50),
    started_at          TIMESTAMPTZ,
    finished_at         TIMESTAMPTZ,
    last_error          VARCHAR(4000),
    last_loaded_rows    INTEGER,
    stage_started_at    TIMESTAMPTZ
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

ALTER TABLE xxi."MI_RCI_CTRL"
  ADD COLUMN IF NOT EXISTS req_id NUMERIC(12);

COMMENT ON COLUMN xxi."MI_RCI_CTRL".req_id IS 'Идентификатор запроса (mi_req.req_id), в рамках которого выполнялась загрузка';
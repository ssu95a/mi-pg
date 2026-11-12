-- Добавление поля кода ошибки, для поддержки общего контракта обраотчика элементов
--
ALTER TABLE xxi.mi_0600 ADD COLUMN IF NOT EXISTS error_code varchar(100)
;
COMMENT ON COLUMN xxi.mi_0600.error_code IS 'Код ошибки обработки элемента'
;
COMMENT ON TABLE xxi.mi_0600 IS 'MI-edo. ЭДО с ФНС. Элементы запросов (ZIP-архивы) ВС: 601–604, 611, 612. 1.0.2. $Id$';

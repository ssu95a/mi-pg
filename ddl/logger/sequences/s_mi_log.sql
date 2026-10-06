-- Sequence   : xxi.s_mi_log
-- Назначение : Генератор идентификаторов записей лога
-- Описание   : Формирует значения ID для записей лога
CREATE SEQUENCE IF NOT EXISTS xxi.s_mi_log START WITH 1 INCREMENT BY 1 MINVALUE 1 CACHE 50 NO CYCLE
;
ALTER SEQUENCE xxi.s_mi_log owner to "XXI"
;
COMMENT ON SEQUENCE xxi.s_mi_log IS 'MI-edo. Система логирования. Генератор идентификаторов записей лога. $Id: {1.0.1} {06.10.2026} Sulimoff$'
;

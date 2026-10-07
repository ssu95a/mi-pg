-- Схема      : mi_request_trg
-- Назначение : Триггерные функции модуля запросов
-- Описание   : Содержит trigger functions объектов модуля Реестр запросов
--
CREATE SCHEMA IF NOT EXISTS mi_request_trg
;
ALTER SCHEMA mi_request_trg OWNER TO "XXI"
;
COMMENT ON SCHEMA mi_request_trg IS 
   'MI-edo. Реестр запросов. Триггерные функции модуля запросов. {$Id$}'
;

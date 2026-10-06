-- Sequence   : xxi.s_mi_item
-- Назначение : Генератор идентификаторов элементов <mi_item> запросов
-- Описание   : Формирует значения ID в таблицах элементов запросов
CREATE SEQUENCE IF NOT EXISTS xxi.s_mi_item START WITH 1 INCREMENT BY 1 MINVALUE 1 CACHE 50 NO CYCLE
;
ALTER SEQUENCE xxi.s_mi_item owner to "XXI"
;
COMMENT ON SEQUENCE xxi.s_mi_item IS
   'MI-edo. Реестр запросов. Генератор идентификаторов элементов mi_item запросов в СМЭВ. $Id: {1.0.1} {06.10.2026} Sulimoff$'
;
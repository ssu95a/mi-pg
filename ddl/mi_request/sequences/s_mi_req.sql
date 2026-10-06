-- Sequence   : xxi.s_mi_req
-- Назначение : Генератор идентификаторов запросов
-- Описание   : Формирует значения ID для заголовков запросов в СМЭВ

CREATE SEQUENCE IF NOT EXISTS xxi.s_mi_req
   START WITH 1
   INCREMENT BY 1
   MINVALUE 1
   CACHE 50
   NO CYCLE
;

ALTER SEQUENCE xxi.s_mi_req OWNER TO "XXI"
;

COMMENT ON SEQUENCE xxi.s_mi_req IS
   'MI-edo. Реестр запросов. Генератор идентификаторов запросов в СМЭВ. $Id: {1.0.1} {06.10.2026} Sulimoff$'
;
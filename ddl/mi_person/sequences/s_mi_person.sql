-- Sequence   : xxi.s_mi_person
-- Назначение : Генератор идентификаторов записей реестра физ лиц
-- Описание   : Формирует значения ID для записей
create sequence if not exists xxi.s_mi_person start with 1 increment by 1 minvalue 1 no cycle
;
ALTER SEQUENCE xxi.s_mi_person OWNER TO "XXI"
;
COMMENT ON SEQUENCE xxi.s_mi_person IS 'MI-edo. Реестр физлиц. Генератор идентификаторов PK записей реестра. $Id: {1.0.1} {06.10.2026} Sulimoff$'
;

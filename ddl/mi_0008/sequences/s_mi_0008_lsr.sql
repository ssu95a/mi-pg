-- Sequence   : xxi.s_mi_0008_lsr
-- Назначение : Генератор PK реестра запусков расчета
-- Описание   : Формирует и заполняет PK
CREATE SEQUENCE IF NOT EXISTS xxi.s_mi_0008_lsr INCREMENT BY 1 MINVALUE 1 START WITH 1 NO CYCLE
;
ALTER SEQUENCE xxi.s_mi_0008_lsr OWNER TO "XXI"
;
COMMENT ON SEQUENCE xxi.s_mi_person IS 'MI-edo. Доходы физ лиц. Генератор PK запуска реестра расчетов. {$Id$}'
;

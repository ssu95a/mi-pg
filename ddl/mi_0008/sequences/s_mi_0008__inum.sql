-- Sequence   : xxi.s_mi_0008__inum
-- Назначение : Генератор номеров позиций
-- Описание   : Формирует и заполняет поле inum
CREATE SEQUENCE IF NOT EXISTS xxi.s_mi_0008__inum START WITH 1 INCREMENT BY 1 MINVALUE 1 NO CYCLE
;
ALTER SEQUENCE xxi.s_mi_0008__inum owner to "XXI"
;
COMMENT ON SEQUENCE xxi.s_mi_0008__inum IS 'MI-edo. Доходы физ лиц. Генератор номеров позиций. {$Id$}'
;

-- Sequence   : xxi.s_mi_rsp
-- Назначение : Генератор идентификаторов ответов
-- Описание   : Формирует значения ID для заголовков ответов в MI

CREATE SEQUENCE IF NOT EXISTS xxi.s_mi_rsp
   START WITH 1
     INCREMENT BY 1
         NO MINVALUE
            NO MAXVALUE
               CACHE 20
;
COMMENT ON SEQUENCE xxi.s_mi_rsp IS
   'MI-edo. Реестр запросов. Генератор идентификаторов ответов в MI. {$Id$}'
;

--
-- Таблица    : xxi.mi_wsp
-- Назначение : Реестр АРМ
-- 
CREATE TABLE IF NOT EXISTS xxi.mi_wsp (
   wsp_id numeric(3) NOT NULL,
   name   varchar(250) NOT NULL,
   note   text,

   constraint pk_mi_wsp primary key (wsp_id)  using index tablespace indexes
)
tablespace users
;
COMMENT ON TABLE xxi.mi_wsp IS 'MI-edo. Виды сведений. АРМ модуля MI. $Id: {1.0.1} {06.10.2026} Sulimoff$'
;
COMMENT ON COLUMN xxi.mi_wsp.wsp_id IS 'ID Арм'
;
COMMENT ON COLUMN xxi.mi_wsp.name IS 'Наименование'
;
COMMENT ON COLUMN xxi.mi_wsp.note IS 'Примечание'
;
ALTER TABLE xxi.mi_wsp OWNER TO "XXI"
;

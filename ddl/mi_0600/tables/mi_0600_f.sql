--
-- Таблица    : xxi.mi_0600_f
-- Назначение : Имена файлов внутри архивов видов сведений 601-604, 611, 612
-- Описание   : Список имен файлов
--

CREATE TABLE IF NOT EXISTS xxi.mi_0600_f (
    itm_id           numeric(12) NOT NULL,                     -- Ссылка на элемент mi_0600
    czip_file_name   varchar(300) NOT NULL,                    -- Имя файла внутри ZIP-архива
    CONSTRAINT pk_mi_0600_f PRIMARY KEY (itm_id, czip_file_name),
    CONSTRAINT fk_mi_0600_f__mi_0600 FOREIGN KEY (itm_id) REFERENCES xxi.mi_0600(itm_id) ON DELETE CASCADE
) TABLESPACE users;

CREATE INDEX IF NOT EXISTS ix_mi_0600_f__file_name   ON xxi.mi_0600_f USING btree (upper(btrim((czip_file_name)::text)));

COMMENT ON TABLE  xxi.mi_0600_f IS 'MI-edo. ЭДО с ФНС. Имена файлов внутри ZIP-архивов видов сведений 601-604, 611, 612. $Id$';
COMMENT ON COLUMN xxi.mi_0600_f.itm_id         IS 'Ссылка на элемент mi_0600';
COMMENT ON COLUMN xxi.mi_0600_f.czip_file_name IS 'Имя файла внутри ZIP-архива';
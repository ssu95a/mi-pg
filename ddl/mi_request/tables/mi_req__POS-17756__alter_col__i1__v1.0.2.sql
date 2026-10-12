-- Изменение длины поля i1 (год отчёта) + пересоздание View
-- с сохранением определения и комментария.
\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE _v_def ON COMMIT DROP AS
SELECT rtrim(pg_get_viewdef('xxi.v_mi_0008_req'::regclass, true), E' \n\t;') AS def,
       obj_description('xxi.v_mi_0008_req'::regclass, 'pg_class')            AS cmt
;

DROP VIEW xxi.v_mi_0008_req;

ALTER TABLE xxi.mi_req
      ALTER COLUMN i1 TYPE numeric(6) USING i1::numeric(6);

DO $$
DECLARE
    v_def text;
    v_cmt text;
BEGIN
    SELECT def, cmt INTO v_def, v_cmt FROM _v_def;

    EXECUTE 'CREATE VIEW xxi.v_mi_0008_req AS ' || v_def;

    EXECUTE 'ALTER VIEW xxi.v_mi_0008_req OWNER TO "XXI"';
    EXECUTE 'GRANT ALL ON TABLE xxi.v_mi_0008_req TO odb';

    EXECUTE format('COMMENT ON VIEW xxi.v_mi_0008_req IS %L', v_cmt);
END $$;

COMMENT ON TABLE xxi.mi_req IS
    'MI-edo. Реестр запросов. Таблица единого реестра. 1.0.2 {$Id$}';

COMMIT;
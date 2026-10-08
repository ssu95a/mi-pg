CREATE OR REPLACE VIEW xxi.v_mi_0111_ca AS
SELECT
   c.icusnum,
   c.ccuslast_name   AS last_name,
   c.ccusfirst_name  AS first_name,
   c.ccusmiddle_name AS middle_name,
   c.dcusbirthday    AS birth_date,
   c.ccusnumnal      AS inn
FROM xxi."CUS" c
WHERE c.ccusnumnal IS NOT NULL
   AND c.ccusflag = ANY (ARRAY['1'::bpchar, '4'::bpchar])
   AND EXISTS (
      SELECT 1 FROM xxi."ACC" a
      WHERE a.iacccus = c.icusnum
        AND a.caccprizn = 'О'::bpchar
  )
;

COMMENT ON VIEW xxi.v_mi_0111_ca IS 
   'MI-edo. Самозанятые. Список клиентов без признака самозанятого, по которым не было запроса в СМЭВ. $Id$';
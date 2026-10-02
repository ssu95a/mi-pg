CREATE OR REPLACE VIEW xxi.v_mi_0003_ca AS
SELECT
   c.icusnum,
   CASE c.ccusflag
      WHEN '2' THEN 2
      WHEN '4' THEN 4
      ELSE NULL
   END AS cus_type,
   c.ccusksiva   AS ogrn,
   c.ccusnumnal  AS inn
   --,
   --CASE WHEN c.ccusflag = '4' THEN c.ccuslast_name   ELSE NULL END AS last_name,
   --CASE WHEN c.ccusflag = '4' THEN c.ccusfirst_name  ELSE NULL END AS first_name,
   --CASE WHEN c.ccusflag = '4' THEN c.ccusmiddle_name ELSE NULL END AS middle_name,
   --CASE WHEN c.ccusflag = '4' THEN c.dcusbirthday    ELSE NULL END AS birth_date
FROM xxi."CUS" c
WHERE c.ccusflag = ANY (ARRAY['2'::bpchar, '4'::bpchar])
  AND (c.ccusksiva IS NOT NULL OR c.ccusnumnal IS NOT NULL)
  --AND EXISTS (
  --    SELECT 1
  --      FROM xxi."ACC" a
  --     WHERE a.iacccus = c.icusnum
  --       AND a.caccprizn = 'О'::bpchar
  --)
  --LIMIT 100
  ;
  
COMMENT ON VIEW xxi.v_mi_0003_ca IS 
   'СМЭВ-3. Список клиентов для запроса сведений ЕГРЮЛ/ЕГРИП (вид сведений 003) $id: {1.0.0} {13.08.2026} Sukhotina$';
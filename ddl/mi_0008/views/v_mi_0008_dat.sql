--
-- View       : xxi.v_mi_0008_dat
-- Назначение : Доходы физ лиц. Данные для выгрузки
-- Описание   : СОбранные данные для выгрузки
CREATE OR REPLACE VIEW xxi.v_mi_0008_dat
AS
SELECT m.itm_id,
       m.external_uuid,
       m.created_at,
       m.iyear,
       m.icorr,
       m.inum,
       coalesce(m.msum_f_dep,0) + coalesce(m.msum_f_crd,0) + coalesce( m.msum_f_acc, 0 ) sum_f,
       coalesce(m.msum_i_dep,0) + coalesce(m.msum_i_crd,0) + coalesce( m.msum_i_acc, 0 ) sum_i,
       p.last_name,
       p.first_name,
       p.middle_name,
       p.ctzn_country_code,
       p.inn,
       p.doc_type_code,
       p.doc_ser,
       p.doc_num,
       p.doc_issue_date,
       p.birth_date,
       r.ctaxreq_id tax_req_id,
       r.i2 corr_sign,
       m.rkind
  FROM xxi.mi_0008 AS m
  JOIN xxi.mi_person AS p  
    ON p.person_id = m.person_id
  JOIN xxi.mi_req AS r
    ON r.req_id = m.req_id 
;
COMMENT ON VIEW xxi.v_mi_0008_dat IS
   'MI-edo. Доходы физ лиц. Данные для выгрузки. (8, 81 ВС). 1.0.1. {$Id$}'
;
--
-- View       : xxi.v_mi_0008
-- Назначение : Доходы физ лиц.Список клиентов с их доходами, 8, 81 ВС
-- Описание   : Список собранных данных клиенов
CREATE OR REPLACE VIEW xxi.v_mi_0008
AS
SELECT m.itm_id,
       m.external_uuid,
       m.req_id,
       m.created_at,
       m.icusnum,
       m.iyear,
       m.icorr,
       (CASE
           WHEN m.icorr = 0 THEN 1
           WHEN m.icorr = 99 THEN 3
           ELSE 2
        END)::numeric(2) AS itype,
       m.inum,
       m.person_id,
       m.msum_f_dep,
       m.msum_i_dep,
       m.msum_f_crd,
       m.msum_i_crd,
       m.msum_f_acc,
       m.msum_i_acc,
       p.last_name,
       p.first_name,
       p.middle_name,
       p.ctzn_country_code,
       p.inn,
       p.doc_type_id,
       p.doc_type_code,
       p.doc_ser,
       p.doc_num,
       p.doc_issue_date,
       p.doc_issuer_code,
       p.doc_expire_date,
       p.doc_issuer_name,
       p.birth_date
  FROM xxi.mi_0008 AS m
  JOIN xxi.mi_person AS p
    ON p.person_id = m.person_id
;
COMMENT ON VIEW xxi.v_mi_0008 IS
   'MI-edo. Доходы физ лиц.Список клиентов с их доходами. (8, 81 ВС). 1.0.1. {$Id$}'
;

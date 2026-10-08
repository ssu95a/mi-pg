-- Представление реестра контролируемых лиц (активный слот + клиенты CUS)
CREATE OR REPLACE VIEW xxi.v_mi_rci AS
SELECT
    r.cureg_id,
    r.cdprf_id,
    r.dbth,
    r.ddoc_date,
    r.ipr_dbth,
    r.cdoc_raw,
    c.icusnum
FROM (
    SELECT * FROM xxi.mi_rci_1
    WHERE EXISTS (SELECT 1 FROM xxi."MI_RCI_CTRL" WHERE active_slot = '1')
    UNION ALL
    SELECT * FROM xxi.mi_rci_2
    WHERE EXISTS (SELECT 1 FROM xxi."MI_RCI_CTRL" WHERE active_slot = '2')
    UNION ALL
    SELECT * FROM xxi.mi_rci_3
    WHERE EXISTS (SELECT 1 FROM xxi."MI_RCI_CTRL" WHERE active_slot = '3')
) r
LEFT JOIN xxi.mi_rci_cus c ON r.cureg_id = c.cureg_id;

COMMENT ON VIEW xxi.v_mi_rci IS 
'MI-edo. Реестр контролируемых лиц. Представление реестра контролируемых лиц. $Id$';
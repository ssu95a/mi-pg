CREATE SEQUENCE IF NOT EXISTS xxi.s_mi_log START WITH 1 INCREMENT BY 1 MINVALUE 1 CACHE 50 NO CYCLE
;
ALTER SEQUENCE xxi.s_mi_log owner to "XXI"
;
COMMENT ON SEQUENCE xxi.s_mi_log IS 'РЎРњР­Р’ 3. Р“РµРЅРµСЂР°С‚РѕСЂ ID РґР»СЏ С‚Р°Р±Р»РёС†С‹ xxi.mi_log'
;

CREATE SEQUENCE IF NOT EXISTS xxi.s_mi_addr
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

COMMENT ON SEQUENCE xxi.s_mi_addr IS
'MI-edo. Адресные данные. Последовательность идентификаторов адресов. $id: {1.0.1} {23.10.2026} Sukhotina$';
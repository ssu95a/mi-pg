CREATE SCHEMA IF NOT EXISTS mi_0202_srv;

COMMENT ON SCHEMA mi_0202_srv IS
'MI-edo. Социальные счета. Схема серверных функций вида сведений 0202. $id: {1.0.1} {23.10.2026} Sukhotina$';

-- Составной тип: адрес с типом и периодом регистрации
CREATE TYPE mi_0202_srv.t_addr_t AS (
    itype     numeric,
    dbeg_reg  date,
    dend_reg  date,
    addr      xxi.mi_addr
);

-- Составной тип: полная запись элемента 0202 вместе с персоной и адресами
CREATE TYPE mi_0202_srv.t_item_t AS (
    item      xxi.mi_0202,
    person    xxi.mi_person,
    addresses mi_0202_srv.t_addr_t[]
);

-- Возвращает полную запись mi_0202 с персоной и адресами в виде JSON по itm_id
CREATE OR REPLACE FUNCTION mi_0202_srv.get_item_json(p_itm_id numeric)
    RETURNS jsonb AS $$
DECLARE
    l_item      xxi.mi_0202%ROWTYPE;
    l_person    xxi.mi_person%ROWTYPE;
    l_addresses jsonb;
BEGIN
    SELECT * INTO STRICT l_item
      FROM xxi.mi_0202
     WHERE itm_id = p_itm_id;

    IF l_item.person_id IS NOT NULL THEN
        SELECT * INTO STRICT l_person
          FROM xxi.mi_person
         WHERE person_id = l_item.person_id;

        SELECT jsonb_agg(
                  jsonb_build_object(
                     'itype',    a.itype,
                     'dbeg_reg', a.dbeg_reg,
                     'dend_reg', a.dend_reg,
                     'address',  to_jsonb(ad)
                  )
               )
          INTO l_addresses
          FROM xxi.mi_p2a a
               JOIN xxi.mi_addr ad ON ad.addr_id = a.addr_id
         WHERE a.person_id = l_item.person_id;
    END IF;

    RETURN jsonb_build_object(
              'item',      to_jsonb(l_item),
              'person',    to_jsonb(l_person),
              'addresses', coalesce(l_addresses, '[]'::jsonb)
           );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION mi_0202_srv.get_item_json(numeric) IS
'MI-edo. Социальные счета. Возвращает запись mi_0202 с персоной и адресами в виде JSON по itm_id. $id: {1.0.1} {23.10.2026} Sukhotina$';

-- Возвращает полную запись mi_0202 с персоной и адресами в виде составного типа
CREATE OR REPLACE FUNCTION mi_0202_srv.get_item_row(p_itm_id numeric)
    RETURNS mi_0202_srv.t_item_t AS $$
DECLARE
    l_item      xxi.mi_0202%ROWTYPE;
    l_person    xxi.mi_person%ROWTYPE;
    l_addresses mi_0202_srv.t_addr_t[];
    l_res       mi_0202_srv.t_item_t;
BEGIN
    SELECT * INTO STRICT l_item
      FROM xxi.mi_0202
     WHERE itm_id = p_itm_id;

    IF l_item.person_id IS NOT NULL THEN
        SELECT * INTO STRICT l_person
          FROM xxi.mi_person
         WHERE person_id = l_item.person_id;

        SELECT array_agg(
                  (a.itype, a.dbeg_reg, a.dend_reg, ad)::mi_0202_srv.t_addr_t
               )
          INTO l_addresses
          FROM xxi.mi_p2a a
               JOIN xxi.mi_addr ad ON ad.addr_id = a.addr_id
         WHERE a.person_id = l_item.person_id;

        l_addresses := coalesce(l_addresses, '{}'::mi_0202_srv.t_addr_t[]);
    ELSE
        l_addresses := '{}'::mi_0202_srv.t_addr_t[];
    END IF;

    l_res.item      := l_item;
    l_res.person    := l_person;
    l_res.addresses := l_addresses;

    RETURN l_res;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION mi_0202_srv.get_item_row(numeric) IS
'MI-edo. Социальные счета. Возвращает запись mi_0202 с персоной и адресами в виде составного типа по itm_id. $id: {1.0.1} {26.10.2026} Sukhotina$';
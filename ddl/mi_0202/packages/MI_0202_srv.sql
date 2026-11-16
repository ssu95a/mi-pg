CREATE OR REPLACE PACKAGE mi_0202_srv

   -- Составной тип: адрес с типом и периодом регистрации
   CREATE TYPE t_addr_t AS (
       itype     numeric,
       dbeg_reg  date,
       dend_reg  date,
       addr      xxi.mi_addr
   )
   
   -- Составной тип: полная запись элемента 0202 вместе с персоной и адресами
   CREATE TYPE t_item_t AS (
       item      xxi.mi_0202,
       person    xxi.mi_person,
       addresses mi_0202_srv.t_addr_t[]
   )
   
   -- Инициализация пакета
   CREATE FUNCTION __init__() RETURNS void AS $$
   DECLARE
      /*
         Пакет для ведения логики MI-edo
         Модуль: Социальные счета (вид сведений 0202)
       Схема серверных функций вида сведений 0202.
      */
      cVersion CONSTANT VARCHAR(100) := '$id: {1.0.1} {23.10.2026} Sukhotina$';
      cPkg_Name CONSTANT VARCHAR(20)  := 'mi_0202_srv';
   BEGIN
      RAISE DEBUG 'Package "%" - % - initialized', cPkg_Name, cVersion;
   END;
   $$
   
   -- Возвращает полную запись mi_0202 с персоной и адресами в виде JSON по itm_id
   CREATE FUNCTION get_item_json(p_itm_id numeric)
      RETURNS jsonb AS $$
      #package
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
            WHERE a.person_id = l_item.person_id
               AND ad.itm_id  = l_item.itm_id;
       END IF;
   
       RETURN jsonb_build_object(
                 'item',      to_jsonb(l_item),
                 'person',    to_jsonb(l_person),
                 'addresses', coalesce(l_addresses, '[]'::jsonb)
              );
   END;
   $$
   
   -- Возвращает полную запись mi_0202 с персоной и адресами в виде составного типа
   CREATE FUNCTION get_item_row(p_itm_id numeric)
      RETURNS mi_0202_srv.t_item_t AS $$
      #package
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
            WHERE a.person_id = l_item.person_id
               AND ad.itm_id  = l_item.itm_id;
   
           l_addresses := coalesce(l_addresses, '{}'::mi_0202_srv.t_addr_t[]);
       ELSE
           l_addresses := '{}'::mi_0202_srv.t_addr_t[];
       END IF;
   
       l_res.item      := l_item;
       l_res.person    := l_person;
       l_res.addresses := l_addresses;
   
       RETURN l_res;
   END;
   $$
;
      
COMMENT ON SCHEMA mi_0202_srv IS
'MI-edo. Социальные счета. Схема серверных функций вида сведений 0202. 1.0.1 {$Id$}';
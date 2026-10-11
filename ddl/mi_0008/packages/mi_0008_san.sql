-- Проверки клиентов для вида сведений 0008.
-- Пакет не получает исходные данные расчёта и не управляет стадиями LSR.
create or replace package mi_0008_san

CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
   #export off
DECLARE

   cVersion     CONSTANT varchar(100) := '1.0.1';

   cPkg_Name    CONSTANT varchar(20 ) := 'mi_0008_san'; 
   cLogger      CONSTANT varchar(20 ) := 'mi.0008'; 

   ret_OK       CONSTANT int4 := 0;
   ret_FAIL     CONSTANT int4 := -1;

   c_link_type_17       constant numeric(3)  := 17;
   c_result_cus_pending constant varchar(50) := 'CUS_PENDING';

   c_err_Not_Found      CONSTANT varchar(200) := 'MI_0008_SAN.SANITIZE_CUS#LSR_NOT_FOUND';
   c_err_Bad_Status     CONSTANT varchar(200) := 'MI_0008_SAN.SANITIZE_CUS#BAD_STATUS';
   c_err_Bad_Stage      CONSTANT varchar(200) := 'MI_0008_SAN.SANITIZE_CUS#BAD_STAGE';
   c_err_Already_Processed CONSTANT varchar(200) := 'MI_0008_SAN.SANITIZE_CUS#ALREADY_PROCESSED';
   c_err_Unexpected     constant varchar(200) := 'MI_0008_SAN.SANITIZE_CUS#UNEXPECTED';

BEGIN
   raise debug 'Package "%" - % - initialized', cPkg_Name, cVersion;
END;
$init$


/* Версия */
CREATE FUNCTION get_Version()
   RETURNS 
      varchar
AS
$function$
   #package
BEGIN
   RETURN cVersion;
END;
$function$


/* */
create procedure create_temp_tables
as
$procedure$
   #private
begin

   -- Exact recreation protects pooled sessions from stale temp-table layouts
   -- after a package deployment. Names are private to the current session.
   DROP TABLE IF EXISTS pg_temp.mi_0008_san_component;
   DROP TABLE IF EXISTS pg_temp.mi_0008_san_frontier;
   DROP TABLE IF EXISTS pg_temp.mi_0008_san_node;
   DROP TABLE IF EXISTS pg_temp.mi_0008_san_edge;
   DROP TABLE IF EXISTS pg_temp.mi_0008_san_source;

   CREATE TEMPORARY TABLE mi_0008_san_source
   (
      s_icusnum numeric(12) NOT NULL,

      CONSTRAINT pk_mi_0008_san_source
         PRIMARY KEY (s_icusnum)
   )
   ON COMMIT DROP;

   CREATE TEMPORARY TABLE mi_0008_san_edge
   (
      p_icusnum numeric(12) NOT NULL,
      c_icusnum numeric(12) NOT NULL,

      CONSTRAINT pk_mi_0008_san_edge
         PRIMARY KEY (p_icusnum, c_icusnum)
   )
   ON COMMIT DROP;

   CREATE INDEX ix_mi_0008_san_edge_child
       ON mi_0008_san_edge (c_icusnum, p_icusnum);

   CREATE TEMPORARY TABLE mi_0008_san_node
   (
      icusnum             numeric(12) NOT NULL,
      component_id        numeric(12),

      -- Initial and mutable in-degree for Kahn's algorithm.
      in_degree           bigint      NOT NULL DEFAULT 0,
      work_in_degree      bigint      NOT NULL DEFAULT 0,
      is_removed          boolean     NOT NULL DEFAULT false,

      r_icusnum           numeric(12),
      graph_result_code   varchar(50),

      CONSTRAINT pk_mi_0008_san_node
         PRIMARY KEY (icusnum)
   )
   ON COMMIT DROP;

   CREATE TEMPORARY TABLE mi_0008_san_frontier
   (
      icusnum numeric(12) NOT NULL,

      CONSTRAINT pk_mi_0008_san_frontier
         PRIMARY KEY (icusnum)
   )
   ON COMMIT DROP;

   CREATE TEMPORARY TABLE mi_0008_san_component
   (
      component_id numeric(12) NOT NULL,
      node_count   bigint      NOT NULL,
      root_count   bigint      NOT NULL,
      root_icusnum numeric(12),
      has_cycle    boolean     NOT NULL,

      CONSTRAINT pk_mi_0008_san_component
         PRIMARY KEY (component_id)
   )
   ON COMMIT DROP;

end;
$procedure$


/* Загрузить входной список клиентов, подготовленный mi_0008_api.create_And_Exec. */
create procedure load_source_clients (
    in p_lsr_id numeric,
   out p_source_count bigint
)
as
$procedure$
   #private
begin
   INSERT INTO pg_temp.mi_0008_san_source (s_icusnum)
   SELECT i.s_icusnum
     FROM xxi.mi_0008_lsr_itm AS i
    WHERE i.lsr_id = p_lsr_id
      AND i.result_code = c_result_cus_pending;

   GET DIAGNOSTICS p_source_count = ROW_COUNT;

   ANALYZE pg_temp.mi_0008_san_source;

end;
$procedure$


/* Загрузить единый снимок активного графа связей типа 17. */
create procedure load_link_graph(
   out p_graph_node_count bigint
)
as
$procedure$
   #private
begin

   ---------------------------------------------------------------------------
   -- One consistent snapshot of the complete active graph for link 17.
   --
   -- LEGACY: date_begin is intentionally not checked. The Oracle logic only
   -- checked date_end. TODO: semantics to verify before changing this rule.
   ---------------------------------------------------------------------------
   INSERT INTO pg_temp.mi_0008_san_edge
   (
      p_icusnum,
      c_icusnum
   )
   SELECT DISTINCT
          l.id_cus_parent,
          l.id_cus_child
     FROM xxi.cus_lnk AS l
    WHERE l.id_lnk_type = c_link_type_17
      AND (l.date_end IS NULL OR l.date_end >= CURRENT_DATE);

   INSERT INTO pg_temp.mi_0008_san_node
   (
      icusnum,
      component_id
   )
   SELECT e.p_icusnum,
          e.p_icusnum
     FROM pg_temp.mi_0008_san_edge AS e
   UNION
   SELECT e.c_icusnum,
          e.c_icusnum
     FROM pg_temp.mi_0008_san_edge AS e;

   SELECT count(*)
     INTO p_graph_node_count
     FROM pg_temp.mi_0008_san_node;

   ANALYZE pg_temp.mi_0008_san_edge;
   ANALYZE pg_temp.mi_0008_san_node;
end;
$procedure$


/*
 * Публичный технический API для mi_0008_api.create_And_Exec.
 * До вызова create_And_Exec создаёт CUS_PENDING и устанавливает SANITARIUM.
 */
CREATE PROCEDURE sanitize_Cus( 
   in p_lsr_id    numeric, 
  out p_ires_code int4,
  out p_cres_info varchar
)
AS 
$procedure$
DECLARE

   cAction_Name CONSTANT varchar(50) := cPkg_Name || '.sanitize_Cus';

   c_status_running        constant varchar(12) := 'RUNNING';
   c_stage_sanitarium      constant varchar(20) := 'SANITARIUM';

   c_result_cus_map        constant varchar(50) := 'CUS_MAP';
   c_result_cycle          constant varchar(50) := 'SAN17_CYCLE';
   c_result_multi_root     constant varchar(50) := 'SAN17_MULTI_ROOT';
   c_result_cus_not_found  constant varchar(50) := 'SAN_CUS_NOT_FOUND';


   l_status_cd       varchar(12);
   l_stage_cd        varchar(20);

   l_source_count          bigint;
   l_updated_count         bigint;
   l_graph_node_count      bigint;
   l_affected_count        bigint;
   v_frontier_count        bigint;
   l_component_pass        bigint := 0;
   l_kahn_pass             bigint := 0;

BEGIN

   CALL MI_logger.enter_f(
      p_logger_name   => cLogger,
      p_function_name => cAction_Name,
      p_inf_id        => 8,
      p_object_id     => p_lsr_id
   );

   p_ires_code := ret_FAIL;
   p_cres_info := null;

      -- 1. Проверка и блокировка LSR.
      SELECT lsr.status_cd,
             lsr.stage_cd
        INTO l_status_cd,
             l_stage_cd
         FROM xxi.mi_0008_lsr lsr
        WHERE lsr.lsr_id = p_lsr_id
          FOR UPDATE;

      IF NOT FOUND THEN
         CALL MI_resultCtx.raise_fail( p_result_Code => c_err_Not_Found, p_result_Info => format('LSR %s не существует', p_lsr_id ) );
      END IF;

      IF l_status_cd <> c_status_running THEN
         CALL MI_resultCtx.raise_fail( p_result_Code => c_err_Bad_Status, p_result_Info => format('LSR %s имеет недопустимый статус %s', p_lsr_id, l_status_cd ) );
      END IF;

      IF l_stage_cd <> c_stage_sanitarium THEN
         CALL MI_resultCtx.raise_fail( p_result_Code => c_err_Bad_Stage, p_result_Info => format('LSR %s имеет недопустимую стадию %s для Sanitarium', p_lsr_id, l_stage_cd ) );
      END IF;

      -- mi_0008_api.create_And_Exec создаёт входные CUS_PENDING до вызова Sanitarium.
      -- Любая итоговая запись означает, что этот LSR уже обрабатывался.
      IF EXISTS (
         SELECT 1
            FROM xxi.mi_0008_lsr_itm item
           WHERE item.lsr_id = p_lsr_id
             AND item.result_code <> c_result_cus_pending
         )
      THEN
         CALL MI_resultCtx.raise_fail( p_result_Code => c_err_Already_Processed, p_result_Info => format( 'Для LSR %s уже существуют результаты Sanitarium', p_lsr_id  ) );
      END IF;

       -- 2. Временные рабочие таблицы текущей сессии. Удаляются при COMMIT/ROLLBACK.
       call mi_0008_san.create_temp_tables();

       call mi_0008_san.load_source_clients( p_lsr_id, l_source_count );

       IF l_source_count = 0 THEN
          p_ires_code := ret_OK;
          RETURN;
       END IF;

       call mi_0008_san.load_link_graph( l_graph_node_count );


      ---------------------------------------------------------------------------
      -- 3. Weakly connected components.
      --
      -- Each pass propagates the smallest node ID across one undirected hop.
      -- The loop is set-based; it does not iterate through source clients.
      ---------------------------------------------------------------------------
      IF l_graph_node_count > 0 THEN
         
         LOOP

            l_component_pass := l_component_pass + 1;

            WITH proposed_component AS
            (
               SELECT e.p_icusnum AS icusnum,
                      least(p.component_id, c.component_id) AS component_id
                 FROM pg_temp.mi_0008_san_edge AS e
                 JOIN pg_temp.mi_0008_san_node AS p
                   ON p.icusnum = e.p_icusnum
                 JOIN pg_temp.mi_0008_san_node AS c
                   ON c.icusnum = e.c_icusnum

               UNION ALL

               SELECT e.c_icusnum AS icusnum,
                      least(p.component_id, c.component_id) AS component_id
                 FROM pg_temp.mi_0008_san_edge AS e
                 JOIN pg_temp.mi_0008_san_node AS p
                   ON p.icusnum = e.p_icusnum
                 JOIN pg_temp.mi_0008_san_node AS c
                   ON c.icusnum = e.c_icusnum
            ),
            best_component AS
            (
               SELECT p.icusnum,
                      min(p.component_id) AS component_id
                 FROM proposed_component AS p
                GROUP BY p.icusnum
            )
            UPDATE pg_temp.mi_0008_san_node AS n
               SET component_id = b.component_id
              FROM best_component AS b
             WHERE n.icusnum = b.icusnum
               AND b.component_id < n.component_id;

            GET DIAGNOSTICS l_affected_count = ROW_COUNT;

            EXIT WHEN l_affected_count = 0;

            IF l_component_pass > l_graph_node_count THEN
               RAISE EXCEPTION 'sanitize_cus: component propagation did not converge for LSR %', p_lsr_id;
            END IF;

         END LOOP;

         ------------------------------------------------------------------------
         -- 4. Cycle detection using Kahn's topological-removal algorithm.
         --
         -- A component is acyclic iff every node can be removed by repeatedly
         -- removing zero-in-degree nodes. Any node left behind means that the
         -- whole weak component contains a directed cycle.
         ------------------------------------------------------------------------
         WITH degree_by_node AS
         (
            SELECT e.c_icusnum AS icusnum,
                   count(*)    AS in_degree
              FROM pg_temp.mi_0008_san_edge AS e
             GROUP BY e.c_icusnum
         )
         UPDATE pg_temp.mi_0008_san_node AS n
            SET in_degree      = d.in_degree,
                work_in_degree = d.in_degree
           FROM degree_by_node AS d
          WHERE n.icusnum = d.icusnum;

         LOOP
            l_kahn_pass := l_kahn_pass + 1;

            TRUNCATE TABLE pg_temp.mi_0008_san_frontier;

            INSERT INTO pg_temp.mi_0008_san_frontier (icusnum)
            SELECT n.icusnum
              FROM pg_temp.mi_0008_san_node AS n
             WHERE NOT n.is_removed
               AND n.work_in_degree = 0;

            GET DIAGNOSTICS v_frontier_count = ROW_COUNT;

            EXIT WHEN v_frontier_count = 0;

            WITH removed_edges AS
            (
               SELECT e.c_icusnum AS icusnum,
                      count(*)    AS edge_count
                 FROM pg_temp.mi_0008_san_edge AS e
                 JOIN pg_temp.mi_0008_san_frontier AS f
                   ON f.icusnum = e.p_icusnum
                 JOIN pg_temp.mi_0008_san_node AS c
                   ON c.icusnum = e.c_icusnum
                WHERE NOT c.is_removed
                GROUP BY e.c_icusnum
            )
            UPDATE pg_temp.mi_0008_san_node AS n
               SET work_in_degree = n.work_in_degree - r.edge_count
              FROM removed_edges AS r
             WHERE n.icusnum = r.icusnum
               AND NOT n.is_removed;

            UPDATE pg_temp.mi_0008_san_node AS n
               SET is_removed = true
              FROM pg_temp.mi_0008_san_frontier AS f
             WHERE n.icusnum = f.icusnum;

            IF l_kahn_pass > l_graph_node_count THEN
               RAISE EXCEPTION
                  'sanitize_cus: cycle analysis did not converge for LSR %',
                  p_lsr_id;
            END IF;

         END LOOP;


         ------------------------------------------------------------------------
         -- 5. Component policy.
         --
         -- Valid component: no cycle and exactly one zero-in-degree root.
         -- For a finite DAG with one root, every node is reachable from that root.
         ------------------------------------------------------------------------
         INSERT INTO pg_temp.mi_0008_san_component
         (
            component_id,
            node_count,
            root_count,
            root_icusnum,
            has_cycle
         )
         SELECT n.component_id,
                count(*) AS node_count,
                count(*) FILTER (WHERE n.in_degree = 0) AS root_count,
                min(n.icusnum) FILTER (WHERE n.in_degree = 0) AS root_icusnum,
                bool_or(NOT n.is_removed) AS has_cycle
           FROM pg_temp.mi_0008_san_node AS n
          GROUP BY n.component_id;

         IF EXISTS
            (
               SELECT 1
                 FROM pg_temp.mi_0008_san_component AS c
                WHERE NOT c.has_cycle
                  AND c.root_count = 0
            )
         THEN
            RAISE EXCEPTION
               'sanitize_cus: acyclic component without a root for LSR %',
               p_lsr_id;
         END IF;

         UPDATE pg_temp.mi_0008_san_node AS n
            SET r_icusnum = CASE
                               WHEN NOT c.has_cycle AND c.root_count = 1
                               THEN c.root_icusnum
                               ELSE NULL
                            END,
                graph_result_code = CASE
                                       WHEN c.has_cycle
                                       THEN c_result_cycle
                                       WHEN c.root_count <> 1
                                       THEN c_result_multi_root
                                       ELSE NULL
                                    END
           FROM pg_temp.mi_0008_san_component AS c
          WHERE c.component_id = n.component_id;

         IF EXISTS
            (
               SELECT 1
                 FROM pg_temp.mi_0008_san_node AS n
                WHERE n.graph_result_code IS NULL
                  AND n.r_icusnum IS NULL
            )
         THEN
            RAISE EXCEPTION
               'sanitize_cus: valid graph node without r_icusnum for LSR %',
               p_lsr_id;
         END IF;

   END IF; --  l_graph_node_count > 0

   ---------------------------------------------------------------------------
   -- 6. Exactly one terminal Sanitarium record per source client.
   --
   -- A client absent from the link graph maps to itself. Invalid graph
   -- components have r_icusnum = NULL. For SAN_CUS_NOT_FOUND the calculated
   -- r_icusnum is retained for diagnostics.
   ---------------------------------------------------------------------------
   WITH mapped_client AS
   (
      SELECT s.s_icusnum,
             n.component_id,
             g.node_count,
             g.root_count,
             n.graph_result_code,
             CASE
                WHEN n.graph_result_code IS NULL
                THEN coalesce(n.r_icusnum, s.s_icusnum)
                ELSE NULL
             END AS r_icusnum
        FROM pg_temp.mi_0008_san_source AS s
        LEFT JOIN pg_temp.mi_0008_san_node AS n
          ON n.icusnum = s.s_icusnum
        LEFT JOIN pg_temp.mi_0008_san_component AS g
          ON g.component_id = n.component_id
   ),
   checked_client AS
   (
      SELECT m.s_icusnum,
             m.r_icusnum,
             m.component_id,
             m.node_count,
             m.root_count,
             m.graph_result_code,
             (c.icusnum IS NOT NULL) AS cus_exists
        FROM mapped_client AS m
        LEFT JOIN xxi."CUS" AS c
          ON c.icusnum = m.r_icusnum
   ),
   decision AS
   (
      SELECT c.s_icusnum,
             c.r_icusnum,
             CASE
                WHEN c.graph_result_code IS NOT NULL
                THEN c.graph_result_code
                WHEN NOT c.cus_exists
                THEN c_result_cus_not_found
                ELSE c_result_cus_map
             END AS result_code,
             CASE c.graph_result_code
                WHEN c_result_cycle THEN
                   'Компонента активных связей типа 17 содержит цикл'
                WHEN c_result_multi_root THEN
                   'Ациклическая компонента активных связей типа 17 имеет несколько корней'
                ELSE
                   CASE
                      WHEN NOT c.cus_exists
                      THEN format(
                         'Канонический клиент %s отсутствует в CUS',
                         c.r_icusnum
                      )
                      ELSE NULL
                   END
             END AS result_info,
             CASE
                WHEN c.graph_result_code IS NOT NULL THEN
                   jsonb_build_object(
                      'link_type',    c_link_type_17,
                      'component_id', c.component_id,
                      'node_count',   c.node_count,
                      'root_count',   c.root_count
                   )::text
                WHEN NOT c.cus_exists THEN
                   jsonb_build_object(
                      'missing_icusnum', c.r_icusnum
                   )::text
                ELSE NULL
             END AS result_data
        FROM checked_client AS c
   )
   UPDATE xxi.mi_0008_lsr_itm AS item
      SET r_icusnum   = d.r_icusnum,
          result_code = d.result_code,
          result_info = d.result_info,
          result_data = d.result_data
     FROM decision AS d
    WHERE item.lsr_id = p_lsr_id
      AND item.s_icusnum = d.s_icusnum
      AND item.result_code = c_result_cus_pending;

   GET DIAGNOSTICS l_updated_count = ROW_COUNT;

   IF l_updated_count <> l_source_count THEN
      RAISE EXCEPTION
         'sanitize_cus: result cardinality mismatch for LSR %: source %, updated %',
         p_lsr_id,
         l_source_count,
         l_updated_count;
   END IF;

   p_ires_code := ret_OK;

EXCEPTION
   WHEN OTHERS THEN
   DECLARE
      ex TS.T_StackedDiagnostics;
      l_error_Text varchar;
      l_result MI_resultCtx.exec_Result;
   begin
      GET STACKED DIAGNOSTICS
          ex.RETURNED_SQLSTATE    = RETURNED_SQLSTATE,  
          ex.MESSAGE_TEXT         = MESSAGE_TEXT,
          ex.PG_EXCEPTION_DETAIL  = PG_EXCEPTION_DETAIL,
          ex.PG_EXCEPTION_HINT    = PG_EXCEPTION_HINT,
          ex.PG_EXCEPTION_CONTEXT = PG_EXCEPTION_CONTEXT;   
      
          l_error_Text := TS.WhenOthersError( cAction_Name, ex);

         /*
            Любая ошибка, ожидаемая или неожиданная, превращается в MI_resultCtx.exec_Result.
         */
         l_result := MI_resultCtx.from_exception (
            p_sqlstate => ex.returned_sqlstate,
            p_message  => ex.message_text,
            p_detail   => ex.pg_exception_detail,
            p_hint     => ex.pg_exception_hint,
            p_context  => ex.pg_exception_context
         );

      /*
         Если это не наше структурированное MI001-исключение, добавим технический контекст.
      */
      IF ex.returned_sqlstate IS DISTINCT FROM 'MI001' THEN

         l_result.is_success  := false;
         l_result.result_code := c_err_Unexpected;
         l_result.result_info := 'Unexpected error in ' || cAction_Name;
         l_result.parameters  := coalesce( l_result.parameters, '{}'::jsonb ) || jsonb_build_object( 'error_info', l_error_Text );
            
      END IF;

      /*
         Логируем итоговый exec_result.
      */
      CALL MI_logger.log_exec_result(
         p_logger_name   => cLogger,
         p_result        => l_result,
         p_inf_id        => 8,
         p_action_cd     => 'exception',
         p_context_value => l_result.result_code,
         p_object_name   => cAction_Name,
         p_object_id     => p_lsr_id
      );

      raise;

   end;   

END;
$procedure$
--end_Of_Package
;

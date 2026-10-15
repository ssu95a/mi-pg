--
-- Package      : mi_0008_san
-- Purpose      : Client sanitarium for MI_0008
-- Version      : 1.0.1
--
-- The graph core is retained from rescue commit 4e46149.  The I/O boundary is
-- intentionally different: the package reads and updates only
-- pg_temp.mi_0008_acc_tmp and persists only rare current diagnostics to
-- mi_0008_lsr_itm.
--
CREATE OR REPLACE PACKAGE mi_0008_san

CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
   #export off
DECLARE

   cVersion  CONSTANT varchar(100) := '1.3.0';
   cPkg_Name CONSTANT varchar(20)  := 'mi_0008_san';
   cLogger   CONSTANT varchar(20)  := 'mi.0008';

   ret_OK    CONSTANT int4 := 0;
   ret_FAIL  CONSTANT int4 := -1;

   c_link_type_17      CONSTANT numeric(3)  := 17;
   c_result_cus_map    CONSTANT varchar(50) := 'CUS_MAP';
   c_result_cycle      CONSTANT varchar(50) := 'SAN17_CYCLE';
   c_result_multi_root CONSTANT varchar(50) := 'SAN17_MULTI_ROOT';
   c_result_not_found  CONSTANT varchar(50) := 'SAN_CUS_NOT_FOUND';
   c_result_bad_inn    CONSTANT varchar(50) := 'SAN_CUS_BAD_INN';
   c_result_no_birth   CONSTANT varchar(50) := 'SAN_CUS_NO_BIRTH';
   c_result_no_doc     CONSTANT varchar(50) := 'SAN_CUS_NO_DOC';
   c_result_doc_after  CONSTANT varchar(50) := 'SAN_CUS_DOC_AFTER_PERIOD';
BEGIN
   RAISE DEBUG 'Package "%" - % - initialized', cPkg_Name, cVersion;
END;
$init$


CREATE FUNCTION get_Version()
   RETURNS varchar
AS
$function$
   #package
BEGIN
   RETURN cVersion;
END;
$function$


/* Recreate only the graph work tables.  The accumulator belongs to API. */
CREATE PROCEDURE create_Graph_Tables()
AS
$procedure$
   #package
   #private
BEGIN

   DROP TABLE IF EXISTS pg_temp.mi_0008_san_component;
   DROP TABLE IF EXISTS pg_temp.mi_0008_san_frontier;
   DROP TABLE IF EXISTS pg_temp.mi_0008_san_node;
   DROP TABLE IF EXISTS pg_temp.mi_0008_san_edge;

   CREATE TEMPORARY TABLE mi_0008_san_edge
   (
      p_icusnum numeric(12) NOT NULL,
      c_icusnum numeric(12) NOT NULL,
      CONSTRAINT pk_mi_0008_san_edge PRIMARY KEY (p_icusnum, c_icusnum)
   ) ON COMMIT DROP;

   CREATE INDEX ix_mi_0008_san_edge__child
       ON mi_0008_san_edge (c_icusnum, p_icusnum);

   CREATE TEMPORARY TABLE mi_0008_san_node
   (
      icusnum           numeric(12) NOT NULL,
      component_id      numeric(12),
      in_degree         bigint      NOT NULL DEFAULT 0,
      work_in_degree    bigint      NOT NULL DEFAULT 0,
      is_removed        boolean     NOT NULL DEFAULT false,
      r_icusnum         numeric(12),
      graph_result_code varchar(50),
      CONSTRAINT pk_mi_0008_san_node PRIMARY KEY (icusnum)
   ) ON COMMIT DROP;

   CREATE TEMPORARY TABLE mi_0008_san_frontier
   (
      icusnum numeric(12) NOT NULL,
      CONSTRAINT pk_mi_0008_san_frontier PRIMARY KEY (icusnum)
   ) ON COMMIT DROP;

   CREATE TEMPORARY TABLE mi_0008_san_component
   (
      component_id numeric(12) NOT NULL,
      node_count   bigint      NOT NULL,
      root_count   bigint      NOT NULL,
      root_icusnum numeric(12),
      has_cycle    boolean     NOT NULL,
      CONSTRAINT pk_mi_0008_san_component PRIMARY KEY (component_id)
   ) ON COMMIT DROP;

END;
$procedure$


/* */
CREATE PROCEDURE resolve_Components (
   IN p_graph_node_count bigint
)
AS
$procedure$
   #package
   #private
DECLARE
   l_affected_count bigint;
   l_component_pass bigint := 0;
BEGIN

   IF p_graph_node_count = 0 THEN
      RETURN;
   END IF;

   LOOP

      l_component_pass := l_component_pass + 1;

      WITH proposed AS
      (
         SELECT e.p_icusnum AS icusnum,
                least(p.component_id, c.component_id) AS component_id
           FROM pg_temp.mi_0008_san_edge AS e
           JOIN pg_temp.mi_0008_san_node AS p
             ON p.icusnum = e.p_icusnum
           JOIN pg_temp.mi_0008_san_node AS c
             ON c.icusnum = e.c_icusnum

         UNION ALL

         SELECT e.c_icusnum,
                least(p.component_id, c.component_id)
           FROM pg_temp.mi_0008_san_edge AS e
           JOIN pg_temp.mi_0008_san_node AS p
             ON p.icusnum = e.p_icusnum
           JOIN pg_temp.mi_0008_san_node AS c
             ON c.icusnum = e.c_icusnum
      ),
      best AS
      (
         SELECT p.icusnum,
                min(p.component_id) AS component_id
           FROM proposed AS p
          GROUP BY p.icusnum
      )
      UPDATE pg_temp.mi_0008_san_node AS n
         SET component_id = b.component_id
        FROM best AS b
       WHERE n.icusnum = b.icusnum
         AND b.component_id < n.component_id;

      GET DIAGNOSTICS l_affected_count = ROW_COUNT;

      EXIT WHEN l_affected_count = 0;

      IF l_component_pass > p_graph_node_count THEN
         RAISE EXCEPTION 'Component propagation did not converge';
      END IF;

   END LOOP;

END;
$procedure$


/* */
CREATE PROCEDURE resolve_Roots(
   IN p_graph_node_count bigint
)
AS
$procedure$
   #package
   #private
DECLARE
   l_frontier_count bigint;
   l_kahn_pass      bigint := 0;
BEGIN

   IF p_graph_node_count = 0 THEN
      RETURN;
   END IF;

   WITH degree_by_node AS
   (
      SELECT e.c_icusnum AS icusnum,
             count(*) AS in_degree
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

      GET DIAGNOSTICS l_frontier_count = ROW_COUNT;

      EXIT WHEN l_frontier_count = 0;

      WITH removed_edges AS
      (
         SELECT e.c_icusnum AS icusnum,
                count(*) AS edge_count
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

      IF l_kahn_pass > p_graph_node_count THEN
         RAISE EXCEPTION
            'Cycle analysis did not converge';
      END IF;
   END LOOP;

   INSERT INTO pg_temp.mi_0008_san_component
   (
      component_id,
      node_count,
      root_count,
      root_icusnum,
      has_cycle
   )
   SELECT n.component_id,
          count(*),
          count(*) FILTER (WHERE n.in_degree = 0),
          min(n.icusnum) FILTER (WHERE n.in_degree = 0),
          bool_or(NOT n.is_removed)
     FROM pg_temp.mi_0008_san_node AS n
    GROUP BY n.component_id;

   UPDATE pg_temp.mi_0008_san_node AS n
      SET r_icusnum =
             CASE
                WHEN NOT c.has_cycle AND c.root_count = 1
                   THEN c.root_icusnum
                ELSE NULL
             END,
          graph_result_code =
             CASE
                WHEN c.has_cycle
                   THEN c_result_cycle
                WHEN c.root_count <> 1
                   THEN c_result_multi_root
                ELSE NULL
             END
     FROM pg_temp.mi_0008_san_component AS c
    WHERE c.component_id = n.component_id;

END;
$procedure$


CREATE PROCEDURE apply_Cus_Mapping(
   OUT p_special_count bigint,
   OUT p_reject_count  bigint
)
AS
$procedure$
   #package
   #private
BEGIN

   p_special_count := 0;
   p_reject_count  := 0;

   WITH mapped AS
   (
      SELECT a.s_icusnum,
             n.component_id,
             c.node_count,
             c.root_count,
             n.graph_result_code,

             CASE
                WHEN n.graph_result_code IS NULL
                   THEN coalesce(n.r_icusnum, a.s_icusnum)
                ELSE NULL
             END AS canonical_icusnum

        FROM pg_temp.mi_0008_acc_tmp AS a

        LEFT JOIN pg_temp.mi_0008_san_node AS n
          ON n.icusnum = a.s_icusnum

        LEFT JOIN pg_temp.mi_0008_san_component AS c
          ON c.component_id = n.component_id
   ),
   checked AS
   (
      SELECT m.*,
             cus.icusnum IS NOT NULL AS canonical_exists

        FROM mapped AS m

        LEFT JOIN xxi."CUS" AS cus
          ON cus.icusnum = m.canonical_icusnum
   ),
   decision AS
   (
      SELECT x.s_icusnum,

             CASE
                WHEN x.graph_result_code IS NOT NULL
                   THEN NULL

                WHEN NOT x.canonical_exists
                   THEN x.canonical_icusnum

                WHEN x.canonical_icusnum IS DISTINCT FROM x.s_icusnum
                   THEN x.canonical_icusnum

                ELSE NULL
             END AS r_icusnum,

             CASE
                WHEN x.graph_result_code IS NOT NULL
                   THEN x.graph_result_code

                WHEN NOT x.canonical_exists
                   THEN c_result_not_found

                WHEN x.canonical_icusnum IS DISTINCT FROM x.s_icusnum
                   THEN c_result_cus_map

                ELSE NULL
             END AS result_code,

             CASE x.graph_result_code
                WHEN c_result_cycle
                   THEN 'Active relation-17 component contains a cycle'

                WHEN c_result_multi_root
                   THEN 'Active relation-17 component has multiple roots'

                ELSE
                   CASE
                      WHEN NOT x.canonical_exists
                         THEN format(
                            'Canonical client %s is absent from CUS',
                            x.canonical_icusnum
                         )
                      ELSE NULL
                   END
             END AS result_info,

             CASE
                WHEN x.graph_result_code IS NOT NULL THEN
                   jsonb_build_object(
                      'link_type',    c_link_type_17,
                      'component_id', x.component_id,
                      'node_count',   x.node_count,
                      'root_count',   x.root_count
                   )::text

                WHEN NOT x.canonical_exists THEN
                   jsonb_build_object(
                      'missing_icusnum', x.canonical_icusnum
                   )::text

                WHEN x.canonical_icusnum IS DISTINCT FROM x.s_icusnum THEN
                   jsonb_build_object(
                      'link_type', c_link_type_17
                   )::text

                ELSE NULL
             END AS result_data

        FROM checked AS x
   )
   UPDATE pg_temp.mi_0008_acc_tmp AS a
      SET r_icusnum       = d.r_icusnum,
          san_result_code = d.result_code,
          san_result_info = d.result_info,
          san_result_data = d.result_data
     FROM decision AS d
    WHERE a.s_icusnum = d.s_icusnum
      AND d.result_code IS NOT NULL;

   GET DIAGNOSTICS p_special_count = ROW_COUNT;

   SELECT count(*)
     INTO p_reject_count
     FROM pg_temp.mi_0008_acc_tmp AS a
    WHERE a.san_result_code IS NOT NULL
      AND a.san_result_code <> c_result_cus_map;

END;
$procedure$


/* */
CREATE PROCEDURE write_Diagnostics(
   IN p_lsr_id numeric
)
AS
$procedure$
   #package
   #private
BEGIN

   INSERT INTO xxi.mi_0008_lsr_itm
   (
      lsr_id,
      s_icusnum,
      r_icusnum,
      result_code,
      result_info,
      result_data
   )
   SELECT p_lsr_id,
          a.s_icusnum,
          a.r_icusnum,
          a.san_result_code,
          a.san_result_info,
          a.san_result_data
     FROM pg_temp.mi_0008_acc_tmp AS a
    WHERE a.san_result_code IS NOT NULL

   ON CONFLICT (lsr_id, s_icusnum) DO UPDATE
      SET r_icusnum   = EXCLUDED.r_icusnum,
          result_code = EXCLUDED.result_code,
          result_info = EXCLUDED.result_info,
          result_data = EXCLUDED.result_data;

END;
$procedure$

/* One consistent snapshot of the complete active relation-17 graph. */
CREATE PROCEDURE load_Link_Graph(
   OUT p_graph_node_count bigint
)
AS
$procedure$
   #package
   #private
BEGIN
   INSERT INTO pg_temp.mi_0008_san_edge (p_icusnum, c_icusnum)
   SELECT DISTINCT l.id_cus_parent, l.id_cus_child
     FROM xxi.cus_lnk AS l
    WHERE l.id_lnk_type = c_link_type_17
      -- Oracle checks DATE_END only.  DATE_BEGIN is deliberately not added.
      AND (l.date_end IS NULL OR l.date_end >= CURRENT_DATE);

   INSERT INTO pg_temp.mi_0008_san_node (icusnum, component_id)
   SELECT e.p_icusnum, e.p_icusnum FROM pg_temp.mi_0008_san_edge AS e
   UNION
   SELECT e.c_icusnum, e.c_icusnum FROM pg_temp.mi_0008_san_edge AS e;

   SELECT count(*) INTO p_graph_node_count
     FROM pg_temp.mi_0008_san_node;

   ANALYZE pg_temp.mi_0008_san_edge;
   ANALYZE pg_temp.mi_0008_san_node;

END;
$procedure$


/* */
CREATE PROCEDURE assert_Run(
   IN p_lsr_id          numeric,
   IN p_expected_stage  varchar
)
AS
$procedure$
   #package
   #private
DECLARE
   l_status_cd varchar(12);
   l_stage_cd  varchar(20);
BEGIN

   SELECT l.status_cd,
          l.stage_cd
     INTO l_status_cd,
          l_stage_cd
     FROM xxi.mi_0008_lsr AS l
    WHERE l.lsr_id = p_lsr_id
      FOR UPDATE;

   IF NOT FOUND THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_SAN#RUN_NOT_FOUND',
         p_result_info => format('LSR %s does not exist', p_lsr_id)
      );
   END IF;

   IF l_status_cd <> 'RUNNING' THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_SAN#BAD_STATUS',
         p_result_info => format(
            'LSR %s has status %s',
            p_lsr_id,
            l_status_cd
         )
      );
   END IF;

   IF l_stage_cd <> p_expected_stage THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_SAN#BAD_STAGE',
         p_result_info => format(
            'LSR %s has stage %s, expected %s',
            p_lsr_id,
            l_stage_cd,
            p_expected_stage
         )
      );
   END IF;

END;
$procedure$

/*
 * Public technical entry point used by mi_0008_api.prepare_Report.
 */
CREATE PROCEDURE resolve_Cus (
   IN  p_lsr_id    numeric,
   IN  p_inf_id    numeric,
   OUT p_ires_code int4,
   OUT p_cres_info varchar
)
AS
$procedure$
   #package
DECLARE
   cAction_Name CONSTANT varchar(50) := cPkg_Name || '.resolve_Cus';

   l_source_count     bigint;
   l_graph_node_count bigint;
   l_special_count    bigint;
   l_reject_count     bigint;
BEGIN

   p_ires_code := ret_FAIL;
   p_cres_info := NULL;

   CALL mi_0008_san.assert_Run(
      p_lsr_id         => p_lsr_id,
      p_expected_stage => 'SANITARIUM'
   );

   CALL MI_logger.enter_f(
      p_logger_name   => cLogger,
      p_function_name => cAction_Name,
      p_inf_id        => p_inf_id,
      p_object_id     => p_lsr_id
   );

   SELECT count(*) INTO l_source_count
     FROM pg_temp.mi_0008_acc_tmp;

   IF l_source_count = 0 THEN
      p_ires_code := ret_OK;
      p_cres_info := 'Sanitarium: no clients';
      CALL MI_logger.exit_f(
         p_logger_name  => cLogger,
         p_message_text => p_cres_info,
         p_inf_id       => p_inf_id,
         p_object_id    => p_lsr_id
      );
      RETURN;
   END IF;

   CALL mi_0008_san.create_Graph_Tables();
   CALL mi_0008_san.load_Link_Graph(l_graph_node_count);

   CALL mi_0008_san.resolve_Components(l_graph_node_count);
   CALL mi_0008_san.resolve_Roots(l_graph_node_count);

   CALL mi_0008_san.apply_Cus_Mapping(
      l_special_count,
      l_reject_count
   );

   CALL mi_0008_san.write_Diagnostics(
      p_lsr_id
   );

   p_ires_code := ret_OK;
   p_cres_info := format(
      'Sanitarium: source=%s, special=%s, rejected=%s',
      l_source_count, l_special_count, l_reject_count
   );

   CALL MI_logger.exit_f(
      p_logger_name  => cLogger,
      p_message_text => p_cres_info,
      p_inf_id       => p_inf_id,
      p_object_id    => p_lsr_id
   );

EXCEPTION
   WHEN OTHERS THEN
      DECLARE
         ex TS.T_StackedDiagnostics;
      BEGIN
         GET STACKED DIAGNOSTICS
            ex.RETURNED_SQLSTATE    = RETURNED_SQLSTATE,
            ex.MESSAGE_TEXT         = MESSAGE_TEXT,
            ex.PG_EXCEPTION_DETAIL  = PG_EXCEPTION_DETAIL,
            ex.PG_EXCEPTION_HINT    = PG_EXCEPTION_HINT,
            ex.PG_EXCEPTION_CONTEXT = PG_EXCEPTION_CONTEXT;

         CALL MI_logger.error(
            p_logger_name   => cLogger,
            p_message_text  => cAction_Name || ' failed',
            p_inf_id        => p_inf_id,
            p_details_text  => TS.WhenOthersError(cAction_Name, ex),
            p_action_cd     => 'exception',
            p_context_value => ex.RETURNED_SQLSTATE,
            p_object_name   => cPkg_Name,
            p_object_id     => p_lsr_id
         );
      END;
      RAISE;
END;
$procedure$



/* */
CREATE PROCEDURE apply_Root_Validation(
   IN  p_iyear         numeric,
   IN  p_launch_itype  numeric,
   IN  p_irsn_corr     numeric,
   IN  p_ireq_kind     numeric,

   OUT p_root_count     bigint,
   OUT p_reject_count   bigint,
   OUT p_citizen_warn   bigint
)
AS
$procedure$
   #package
   #private
DECLARE
   l_updated_count bigint;
BEGIN

   p_root_count   := 0;
   p_reject_count := 0;
   p_citizen_warn := 0;

   WITH roots AS MATERIALIZED
   (
      SELECT a.s_icusnum AS icusnum
        FROM pg_temp.mi_0008_acc_tmp AS a
       WHERE a.san_result_code IS NULL
   ),
   person_data AS MATERIALIZED
   (
      SELECT r.icusnum,
             c.icusnum IS NOT NULL AS cus_exists,

             NULLIF(btrim(c.ccusnumnal), '') AS inn,
             c.dcusbirthday::date AS birth_date,

             coalesce(
                pref_doc.doc_type_id,
                alt_doc.doc_type_id
             ) AS doc_type_id,

             CASE
                WHEN pref_doc.doc_type_id IS NOT NULL
                   THEN pref_doc.doc_issue_date
                ELSE alt_doc.doc_issue_date
             END AS doc_issue_date,

             coalesce(
                cus_country.cdigital,
                doc_country.cdigital
             ) AS ctzn_country_code

        FROM roots AS r

        LEFT JOIN xxi."CUS" AS c
          ON c.icusnum = r.icusnum

        LEFT JOIN LATERAL
        (
           SELECT CASE
                     WHEN btrim(p.cpudcode9) ~ '^[0-9]{1,3}$'
                        THEN btrim(p.cpudcode9)::numeric(3)
                     ELSE NULL::numeric(3)
                  END AS doc_type_id,

                  d.doc_date::date AS doc_issue_date,
                  d.doc_cnt

             FROM xxi.cus_docum AS d

             LEFT JOIN xxi.pud AS p
               ON p.ipudid = d.id_doc_tp

            WHERE d.icusnum = r.icusnum
              AND d.pref = 'Y'

            ORDER BY d.doc_date DESC NULLS LAST,
                     d.id_doc DESC

            LIMIT 1
        ) AS pref_doc
          ON true

        LEFT JOIN LATERAL
        (
           SELECT CASE
                     WHEN btrim(p.cpudcode9) ~ '^[0-9]{1,3}$'
                        THEN btrim(p.cpudcode9)::numeric(3)
                     ELSE NULL::numeric(3)
                  END AS doc_type_id,

                  d.doc_date::date AS doc_issue_date,
                  d.doc_cnt

             FROM xxi.cus_docum AS d

             LEFT JOIN xxi.pud AS p
               ON p.ipudid = d.id_doc_tp

            WHERE d.icusnum = r.icusnum
              AND coalesce(d.pref, 'N') = 'N'
              AND coalesce(d.doc_period, CURRENT_DATE) >= CURRENT_DATE

            ORDER BY d.doc_date DESC NULLS LAST,
                     d.id_doc DESC

            LIMIT 1
        ) AS alt_doc
          ON true

        LEFT JOIN LATERAL
        (
           SELECT k.cdigital
             FROM xxi.ok_sm AS k
            WHERE k.calfa_2 = c.ccuscountry1
            LIMIT 1
        ) AS cus_country
          ON true

        LEFT JOIN LATERAL
        (
           SELECT k.cdigital
             FROM xxi.ok_sm AS k
            WHERE k.calfa_3 =
                  CASE
                     WHEN pref_doc.doc_type_id IS NOT NULL
                        THEN pref_doc.doc_cnt
                     ELSE alt_doc.doc_cnt
                  END
            LIMIT 1
        ) AS doc_country
          ON true
   ),
   decision AS MATERIALIZED
   (
      SELECT p.*,

             CASE
                WHEN NOT p.cus_exists
                   THEN c_result_not_found

                WHEN p.doc_type_id IS NULL
                   THEN c_result_no_doc

                WHEN p_launch_itype = 2
                 AND p_ireq_kind = 1
                 AND p_irsn_corr = 1
                 AND extract(year FROM p.doc_issue_date) > p_iyear
                   THEN c_result_doc_after

                WHEN p.inn IS NULL
                  OR length(p.inn) > 12
                   THEN c_result_bad_inn

                WHEN p.birth_date IS NULL
                   THEN c_result_no_birth

                ELSE NULL
             END::varchar(50) AS result_code

        FROM person_data AS p
   ),
   updated AS
   (
      UPDATE pg_temp.mi_0008_acc_tmp AS a
         SET r_icusnum       = d.icusnum,
             san_result_code = d.result_code,

             san_result_info =
                CASE d.result_code
                   WHEN c_result_not_found
                      THEN 'Клиент не найден в справочнике CUS'

                   WHEN c_result_no_doc
                      THEN 'Отсутствует действующий ДУЛ или не распознан его тип'

                   WHEN c_result_doc_after
                      THEN format(
                         'ДУЛ выдан после отчётного периода: дата=%s, год=%s',
                         d.doc_issue_date,
                         p_iyear
                      )

                   WHEN c_result_bad_inn
                      THEN 'Некорректный ИНН: значение отсутствует или длина превышает 12'

                   WHEN c_result_no_birth
                      THEN 'Не задана дата рождения'

                   ELSE d.result_code
                END,

             san_result_data =
                jsonb_strip_nulls(
                   jsonb_build_object(
                      'stage',          'ROOT_VALIDATION',
                      'doc_issue_date', d.doc_issue_date,
                      'report_year',    p_iyear
                   )
                )::text

        FROM decision AS d

       WHERE a.s_icusnum = d.icusnum
         AND d.result_code IS NOT NULL

      RETURNING a.s_icusnum
   )
   SELECT count(*),

          count(*) FILTER (
             WHERE d.result_code IS NOT NULL
          ),

          count(*) FILTER (
             WHERE d.result_code IS NULL
               AND d.ctzn_country_code IS NULL
          ),

          (SELECT count(*) FROM updated)

     INTO p_root_count,
          p_reject_count,
          p_citizen_warn,
          l_updated_count

     FROM decision AS d;

   IF l_updated_count <> p_reject_count THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_SAN#ROOT_CARDINALITY',
         p_result_info => format(
            'Expected %s rejected roots, updated %s',
            p_reject_count,
            l_updated_count
         )
      );
   END IF;

END;
$procedure$


CREATE PROCEDURE persist_Root_Diagnostics(
   IN p_lsr_id numeric
)
AS
$procedure$
   #package
   #private
BEGIN

   INSERT INTO xxi.mi_0008_lsr_itm
   (
      lsr_id,
      s_icusnum,
      r_icusnum,
      result_code,
      result_info,
      result_data
   )
   SELECT p_lsr_id,
          a.s_icusnum,
          a.s_icusnum,
          a.san_result_code,
          a.san_result_info,
          a.san_result_data
     FROM pg_temp.mi_0008_acc_tmp AS a
    WHERE a.san_result_code IN
          (
             c_result_not_found,
             c_result_bad_inn,
             c_result_no_birth,
             c_result_no_doc,
             c_result_doc_after
          )
   ON CONFLICT (lsr_id, s_icusnum) DO UPDATE
      SET r_icusnum   = EXCLUDED.r_icusnum,
          result_code = EXCLUDED.result_code,
          result_info = EXCLUDED.result_info,
          result_data = EXCLUDED.result_data;

END;
$procedure$


CREATE PROCEDURE propagate_Root_Rejections(
   IN p_lsr_id numeric
)
AS
$procedure$
   #package
   #private
BEGIN

   UPDATE xxi.mi_0008_lsr_itm AS item
      SET result_code = root.san_result_code,
          result_info = format(
             'Канонический клиент %s отклонён: %s',
             root.s_icusnum,
             root.san_result_info
          ),
          result_data = root.san_result_data
     FROM pg_temp.mi_0008_acc_tmp AS root
    WHERE item.lsr_id = p_lsr_id
      AND item.result_code = c_result_cus_map
      AND item.r_icusnum = root.s_icusnum
      AND root.san_result_code IN
          (
             c_result_not_found,
             c_result_bad_inn,
             c_result_no_birth,
             c_result_no_doc,
             c_result_doc_after
          );

END;
$procedure$


/*
 * Проверяет данные итоговых корневых клиентов после collapse_To_Roots.
 *
 * Процедура не читает историю отчёта и не принимает решений по icorr.
 * Она изменяет только санитарные поля аккумулятора и протокол LSR.
 * Отсутствие гражданства после fallback из ДУЛ логируется, но не является
 * причиной отклонения клиента.
 */
CREATE PROCEDURE validate_Root_Cus(
   IN  p_lsr_id        numeric,
   IN  p_inf_id        numeric,
   IN  p_iyear         numeric,
   IN  p_launch_itype  numeric,
   IN  p_irsn_corr     numeric,
   IN  p_ireq_kind     numeric,
   OUT p_ires_code     int4,
   OUT p_cres_info     varchar
)
AS
$procedure$
   #package
DECLARE
   cAction_Name CONSTANT varchar(50) := cPkg_Name || '.validate_Root_Cus';

   l_root_count      bigint;
   l_reject_count    bigint;
   l_citizen_warn    bigint;
BEGIN

   p_ires_code := ret_FAIL;
   p_cres_info := NULL;

   CALL mi_0008_san.assert_Run (
      p_lsr_id         => p_lsr_id,
      p_expected_stage => 'SANITARIUM'
   );

   CALL MI_logger.enter_f (
      p_logger_name   => cLogger,
      p_function_name => cAction_Name,
      p_inf_id        => p_inf_id,
      p_object_id     => p_lsr_id
   );


   CALL mi_0008_san.apply_Root_Validation (
      p_iyear         => p_iyear,
      p_launch_itype  => p_launch_itype,
      p_irsn_corr     => p_irsn_corr,
      p_ireq_kind     => p_ireq_kind,

      p_root_count    => l_root_count,
      p_reject_count  => l_reject_count,
      p_citizen_warn  => l_citizen_warn
   );
   
   IF l_root_count = 0 THEN
      p_ires_code := ret_OK;
      p_cres_info := 'Sanitarium root validation: no clients';

      CALL MI_logger.exit_f(...);
      RETURN;
   END IF;   

   CALL persist_Root_Diagnostics(p_lsr_id);

   CALL propagate_Root_Rejections(p_lsr_id);

   IF l_citizen_warn > 0 THEN

      CALL MI_logger.warn(
         p_logger_name   => cLogger,
         p_message_text  => format(
            'Citizenship is absent after DUL fallback for %s accepted roots',
            l_citizen_warn
         ),
         p_inf_id        => p_inf_id,
         p_action_cd     => 'root_validation',
         p_object_name   => cPkg_Name,
         p_object_id     => p_lsr_id
      );
   END IF;

   p_ires_code := ret_OK;
   p_cres_info := format(
      'Sanitarium root validation: roots=%s, rejected=%s, citizenship_warnings=%s',
      l_root_count,
      l_reject_count,
      l_citizen_warn
   );

   CALL MI_logger.exit_f(
      p_logger_name  => cLogger,
      p_message_text => p_cres_info,
      p_inf_id       => p_inf_id,
      p_object_id    => p_lsr_id
   );

EXCEPTION
   WHEN OTHERS THEN
      DECLARE
         ex TS.T_StackedDiagnostics;
      BEGIN
         GET STACKED DIAGNOSTICS
            ex.RETURNED_SQLSTATE    = RETURNED_SQLSTATE,
            ex.MESSAGE_TEXT         = MESSAGE_TEXT,
            ex.PG_EXCEPTION_DETAIL  = PG_EXCEPTION_DETAIL,
            ex.PG_EXCEPTION_HINT    = PG_EXCEPTION_HINT,
            ex.PG_EXCEPTION_CONTEXT = PG_EXCEPTION_CONTEXT;

         CALL MI_logger.error(
            p_logger_name   => cLogger,
            p_message_text  => cAction_Name || ' failed',
            p_inf_id        => p_inf_id,
            p_details_text  => TS.WhenOthersError(cAction_Name, ex),
            p_action_cd     => 'exception',
            p_context_value => ex.RETURNED_SQLSTATE,
            p_object_name   => cPkg_Name,
            p_object_id     => p_lsr_id
         );
      END;
      RAISE;
END;
$procedure$


/* end_Of_Package */
;

COMMENT ON SCHEMA mi_0008_san IS
   'MI-edo. MI_0008 client sanitarium 1.0.1 {$Id$}'
;



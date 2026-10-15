--
-- Пакет         : mi_0008_api
-- Назначение    : формирование отчётов MI_0008 (без отправки)
-- Версия        : 1.0.1
--
-- Расчёты внешних источников намеренно скрыты за пакетом
-- mi_0008_src. См. EXTERNAL_DEPENDENCIES.md.
--
CREATE OR REPLACE PACKAGE mi_0008_api

/* Явный контекст запуска, передаваемый между внутренними этапами оркестрации. */
CREATE TYPE mi_0008_api.run_context_t AS
(
   lsr_id       numeric(12),
   inf_id       numeric(6),
   iyear        numeric(4),
   launch_itype numeric(2),
   irsn_corr    numeric(2),
   ireq_kind    numeric(2),
   cus_marker   numeric,
   pack_num     numeric,
   scope_all    boolean
)

CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
   #export off
DECLARE

   cVersion  CONSTANT varchar(100) := '1.2.0';
   cPkg_Name CONSTANT varchar(20)  := 'mi_0008_api';
   cLogger   CONSTANT varchar(20)  := 'mi.0008';

   ret_Ok   CONSTANT int4 := 0;
   ret_Fail CONSTANT int4 := -1;

   c_result_no_data  CONSTANT int4 := 1;
   c_result_busy     CONSTANT int4 := 2;

   c_reason_fns  CONSTANT numeric := 2;
   c_kind_person CONSTANT numeric := 1;
   c_kind_sum    CONSTANT numeric := 2;

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


/*
 * Сессионные рабочие наборы.
 *
 * Параметры запуска не хранятся в сессионных таблицах: оркестратор передаёт
 * run_context_t каждому внутреннему этапу. mi_0008_acc_tmp — единственная
 * полнообъёмная материализация финансовых данных; область кандидатов компактна.
 */
CREATE PROCEDURE create_Temp_Tables( )
AS
$procedure$
   #package
   #private
BEGIN

   DROP TABLE IF EXISTS pg_temp.mi_0008_acc_tmp;
   DROP TABLE IF EXISTS pg_temp.mi_0008_scope_tmp;

   CREATE TEMPORARY TABLE mi_0008_scope_tmp
   (
      s_icusnum    numeric(12) NOT NULL,
      in_scope     boolean     NOT NULL DEFAULT false,
      is_requested boolean     NOT NULL DEFAULT false,
      is_excluded  boolean     NOT NULL DEFAULT false,
      source_seen  boolean     NOT NULL DEFAULT false,
      
      CONSTRAINT pk_mi_0008_scope_tmp PRIMARY KEY (s_icusnum)

   ) ON COMMIT DROP;

   -- временный агрегатор для фин данных
   CREATE TEMPORARY TABLE mi_0008_acc_tmp
   (
      s_icusnum numeric(12) NOT NULL,

      msum_f_dep numeric(22,2),
      msum_i_dep numeric(22,2),
      msum_f_crd numeric(22,2),
      msum_i_crd numeric(22,2),
      msum_f_acc numeric(22,2),
      msum_i_acc numeric(22,2),

      r_icusnum       numeric(12),

      san_result_code varchar(50),
      san_result_info text,
      san_result_data text,

      CONSTRAINT pk_mi_0008_acc_tmp PRIMARY KEY (s_icusnum)

   ) ON COMMIT DROP;

END;
$procedure$


/*
 * Формируем компактный набор кандидатов и расширяем его по активным связям типа 17.
 * Рекурсивный обход считает связи неориентированными только для охвата кандидатов;
 * Санитарий по-прежнему трактует граф как направленный: родитель -> потомок.
 */
CREATE PROCEDURE build_Scope(
   IN  p_ctx         mi_0008_api.run_context_t,
   OUT p_scope_all   boolean,
   OUT p_scope_count bigint
)
AS
$procedure$
   #package
   #private
BEGIN

   p_scope_all := (p_ctx.launch_itype = 1 AND p_ctx.cus_marker IS NULL);

   ---------------------------------------------------------------------------
   -- Исходные клиенты, заданные параметрами запуска.
   ---------------------------------------------------------------------------
   IF p_ctx.launch_itype = 1 AND p_ctx.cus_marker IS NOT NULL THEN
      -- Структура пакета Oracle: IDROW — клиент, IDAROW — номер пакета.
      INSERT INTO pg_temp.mi_0008_scope_tmp
         (s_icusnum, in_scope, is_requested)
      SELECT DISTINCT m.idrow, true, true
        FROM xxi.mrk_id2 AS m
       WHERE m.idmarker = p_ctx.cus_marker
         AND m.idarow = p_ctx.pack_num
         AND m.idrow IS NOT NULL
      ON CONFLICT (s_icusnum) DO UPDATE
         SET in_scope     = true,
             is_requested = true;

   ELSIF p_ctx.launch_itype IN (2, 3) AND p_ctx.cus_marker IS NOT NULL THEN
      -- Структура обычного маркера Oracle: IDAROW — клиент.
      INSERT INTO pg_temp.mi_0008_scope_tmp
         (s_icusnum, in_scope, is_requested)
      SELECT DISTINCT m.idarow, true, true
        FROM xxi.mrk_id2 AS m
       WHERE m.idmarker = p_ctx.cus_marker
         AND m.idarow IS NOT NULL
      ON CONFLICT (s_icusnum) DO UPDATE
         SET in_scope = true,
             is_requested = true;

   ELSIF p_ctx.launch_itype = 2 AND p_ctx.cus_marker IS NULL THEN
      -- Банковский режим поиска изменений. Финансовые корректировки начинаются
      -- с первичной истории, а уточнения данных клиента — с любой допустимой истории.
      INSERT INTO pg_temp.mi_0008_scope_tmp
         (s_icusnum, in_scope, is_requested)
      SELECT DISTINCT i.icusnum, true, true
        FROM xxi.mi_0008 AS i
        JOIN xxi.mi_req AS q ON q.req_id = i.req_id
       WHERE q.inf_id = p_ctx.inf_id
         AND q.status_cd IN (1, 2, 3)
         AND i.iyear = p_ctx.iyear
         AND (p_ctx.ireq_kind = c_kind_person OR i.icorr = 0)
      ON CONFLICT (s_icusnum) DO UPDATE
         SET in_scope = true,
             is_requested = true;
   END IF;

   ---------------------------------------------------------------------------
   -- Полное расширение по слабой компоненте связности предотвращает потерю
   -- сумм дочерних клиентов в цепочках.
   ---------------------------------------------------------------------------
   WITH RECURSIVE walk(icusnum) AS
   (
      SELECT s.s_icusnum
        FROM pg_temp.mi_0008_scope_tmp AS s
       WHERE s.in_scope
      UNION
      SELECT CASE
                WHEN l.id_cus_parent = w.icusnum THEN l.id_cus_child
                ELSE l.id_cus_parent
             END
        FROM walk AS w
        JOIN xxi.cus_lnk AS l
          ON l.id_cus_parent = w.icusnum OR l.id_cus_child = w.icusnum
       WHERE l.id_lnk_type = 17
         AND (l.date_end IS NULL OR l.date_end >= CURRENT_DATE)
   )
   INSERT INTO pg_temp.mi_0008_scope_tmp (s_icusnum, in_scope)
   SELECT w.icusnum, true FROM walk AS w
   ON CONFLICT (s_icusnum) DO UPDATE SET in_scope = true;

   ---------------------------------------------------------------------------
   -- При первичном сборе исключаем клиентов, уже представленных допустимой
   -- первичной строкой истории. Исключения расширяем по тому же графу, чтобы
   -- потомок не был повторно сопоставлен уже включённому в отчёт корню.
   ---------------------------------------------------------------------------
   IF p_ctx.launch_itype = 1 THEN

      INSERT INTO pg_temp.mi_0008_scope_tmp ( s_icusnum, is_excluded )
      SELECT DISTINCT i.icusnum, true
        FROM xxi.mi_0008 AS i
        JOIN xxi.mi_req AS q ON q.req_id = i.req_id
       WHERE q.inf_id = p_ctx.inf_id
         AND q.status_cd IN (1, 2, 3)
         AND i.iyear = p_ctx.iyear
         AND i.icorr = 0
      ON CONFLICT (s_icusnum) DO UPDATE SET is_excluded = true;

      WITH RECURSIVE excluded_walk(icusnum) AS
      (
         SELECT s.s_icusnum
           FROM pg_temp.mi_0008_scope_tmp AS s
          WHERE s.is_excluded
         UNION
         SELECT CASE
                   WHEN l.id_cus_parent = w.icusnum THEN l.id_cus_child
                   ELSE l.id_cus_parent
                END
           FROM excluded_walk AS w
           JOIN xxi.cus_lnk AS l
             ON l.id_cus_parent = w.icusnum OR l.id_cus_child = w.icusnum
          WHERE l.id_lnk_type = 17
            AND (l.date_end IS NULL OR l.date_end >= CURRENT_DATE)
      )
      INSERT INTO pg_temp.mi_0008_scope_tmp (s_icusnum, is_excluded)
      SELECT w.icusnum, true FROM excluded_walk AS w
      ON CONFLICT (s_icusnum) DO UPDATE SET is_excluded = true;
   END IF;

   SELECT count(*) INTO p_scope_count
     FROM pg_temp.mi_0008_scope_tmp AS s
    WHERE s.in_scope AND NOT s.is_excluded;
END;
$procedure$


/* DEP изменяет только msum_f_dep и msum_i_dep. */
CREATE PROCEDURE load_Dep(
   IN p_ctx mi_0008_api.run_context_t
)
AS
$procedure$
   #package
   #private
BEGIN
   /*
    * Исходные данные читаются напрямую из DEP.
    * В src формируется не более одной строки на клиента.
    */
   WITH src AS MATERIALIZED
   (
      SELECT d.icusnum AS s_icusnum,
             NULLIF(sum(d.sumprocfizonly), 0)::numeric(22,2) AS msum_f_dep,
             NULLIF(sum(d.sumprocind), 0)::numeric(22,2) AS msum_i_dep
        FROM dj_v_prc_to_Client AS d
        LEFT 
            JOIN pg_temp.mi_0008_scope_tmp AS scope ON scope.s_icusnum = d.icusnum
       WHERE
            d.icusnum IS NOT NULL
         /* NULL в поле года сохраняет Oracle-совместимое поведение. */
         AND (d.year IS NULL OR d.year = p_ctx.iyear)
         /*
          * Для полного запуска берём всех клиентов, кроме исключённых.
          * Для ограниченного запуска берём только рассчитанную область.
          */
         AND CASE
                WHEN p_ctx.scope_all
                     THEN coalesce( NOT scope.is_excluded, true )
                ELSE
                     coalesce( scope.in_scope AND NOT scope.is_excluded, false )
             END

       GROUP BY d.icusnum

      /*
       * Полностью пустые строки не считаются результатом расчёта.
       * Исходные нулевые значения сохраняют факт выполненного расчёта:
       * после суммирования итоговый ноль будет преобразован в NULL.
       */
      HAVING count(d.sumprocfizonly) > 0 OR count(d.sumprocind) > 0
   ),
   mark_seen AS
   (
      UPDATE pg_temp.mi_0008_scope_tmp AS scope
         SET source_seen = true
        FROM src
       WHERE scope.s_icusnum = src.s_icusnum
   RETURNING scope.s_icusnum
   )
   INSERT INTO pg_temp.mi_0008_acc_tmp
   (
      s_icusnum,
      msum_f_dep,
      msum_i_dep
   )
   SELECT src.s_icusnum,
          src.msum_f_dep,
          src.msum_i_dep
     FROM src;

END;
$procedure$

/* CRD изменяет только msum_f_crd и msum_i_crd. */
/* CRD изменяет только msum_f_crd и msum_i_crd. */
CREATE PROCEDURE load_Crd(
   IN p_ctx mi_0008_api.run_context_t
)
AS
$procedure$
   #package
   #private
BEGIN
   WITH src AS MATERIALIZED
   (
      SELECT e.icusnum AS s_icusnum,
             NULLIF( sum(e.msum) FILTER (WHERE e.itype = 1), 0 )::numeric(22,2) AS msum_f_crd,
             NULLIF( sum(e.msum) FILTER (WHERE e.itype = 2), 0 )::numeric(22,2) AS msum_i_crd
        FROM sm_008_Ed_tmp AS e
        LEFT 
             JOIN pg_temp.mi_0008_scope_tmp AS s ON s.s_icusnum = e.icusnum
       WHERE e.icusnum IS NOT NULL
         AND e.itype IN (1, 2)
         AND e.msum IS NOT NULL
         AND CASE
                WHEN p_ctx.scope_all
                   THEN coalesce(NOT s.is_excluded, true)
                ELSE
                   coalesce(
                      s.in_scope AND NOT s.is_excluded,
                      false
                   )
             END
       GROUP BY e.icusnum
   ),
   mark_seen AS
   (
      UPDATE pg_temp.mi_0008_scope_tmp AS s
         SET source_seen = true
        FROM src
       WHERE s.s_icusnum = src.s_icusnum
       RETURNING s.s_icusnum
   )
   INSERT INTO pg_temp.mi_0008_acc_tmp
   (
      s_icusnum,
      msum_f_crd,
      msum_i_crd
   )
   SELECT src.s_icusnum,
          src.msum_f_crd,
          src.msum_i_crd
     FROM src
   ON CONFLICT (s_icusnum) DO UPDATE
      SET msum_f_crd = EXCLUDED.msum_f_crd,
          msum_i_crd = EXCLUDED.msum_i_crd;
END;
$procedure$


/* ACC изменяет только msum_f_acc и msum_i_acc. */
CREATE PROCEDURE load_Acc(
   IN p_ctx mi_0008_api.run_context_t
)
AS
$procedure$
   #package
   #private
BEGIN
   WITH src AS MATERIALIZED
   (
      SELECT p.inum AS s_icusnum,
             NULLIF(sum(p.msum2), 0)::numeric(22,2) AS msum_f_acc,
             NULLIF(sum(p.msum1), 0)::numeric(22,2) AS msum_i_acc
        FROM perc_Temp AS p
        LEFT JOIN pg_temp.mi_0008_scope_tmp AS s
          ON s.s_icusnum = p.inum
       WHERE p.inum IS NOT NULL
         AND CASE
                WHEN p_ctx.scope_all
                   THEN coalesce(NOT s.is_excluded, true)
                ELSE
                   coalesce(
                      s.in_scope AND NOT s.is_excluded,
                      false
                   )
             END
       GROUP BY p.inum
      HAVING count(p.msum1) > 0 OR count(p.msum2) > 0
   ),
   mark_seen AS
   (
      UPDATE pg_temp.mi_0008_scope_tmp AS s
         SET source_seen = true
        FROM src
       WHERE s.s_icusnum = src.s_icusnum
       RETURNING s.s_icusnum
   )
   INSERT INTO pg_temp.mi_0008_acc_tmp
   (
      s_icusnum,
      msum_f_acc,
      msum_i_acc
   )
   SELECT src.s_icusnum,
          src.msum_f_acc,
          src.msum_i_acc
     FROM src
   ON CONFLICT (s_icusnum) DO UPDATE
      SET msum_f_acc = EXCLUDED.msum_f_acc,
          msum_i_acc = EXCLUDED.msum_i_acc;
END;
$procedure$


/* */
CREATE PROCEDURE load_Sources( IN p_ctx mi_0008_api.run_context_t )
AS
$procedure$
   #package
   #private
BEGIN
   -- Порядок соответствует Oracle. Перед загрузкой своей пары каждый адаптер
   -- обязан заменить собственный снимок источника в текущей сессии.
   CALL mi_0008_api.load_Dep(p_ctx);
   CALL mi_0008_api.load_Crd(p_ctx);
   CALL mi_0008_api.load_Acc(p_ctx);
END;
$procedure$


/*
 * Принятые строки источников сворачиваем к каноническим корням В ТОМ ЖЕ
 * аккумуляторе. 
 * Групповой INSERT/UPSERT заменяет суммы корней, после чего
 * сопоставленные дочерние и отклонённые строки удаляются. Это позволяет
 * обойтись без второй полнообъёмной таблицы сумм.
 */
CREATE PROCEDURE collapse_To_Roots()
AS
$procedure$
   #package
   #private
BEGIN
   -- Сохраняем на каноническом корне метаданные целевого запуска или запроса ФНС.
   INSERT INTO pg_temp.mi_0008_scope_tmp AS current_scope
               (s_icusnum, in_scope, is_requested, source_seen)
   SELECT coalesce(a.r_icusnum, a.s_icusnum),
          true,
          bool_or(coalesce(s.is_requested, false)),
          bool_or(coalesce(s.source_seen,  false))
     FROM pg_temp.mi_0008_acc_tmp AS a
     LEFT JOIN pg_temp.mi_0008_scope_tmp AS s ON s.s_icusnum = a.s_icusnum
    WHERE a.san_result_code IS NULL
       OR a.san_result_code = 'CUS_MAP'
    GROUP BY coalesce(a.r_icusnum, a.s_icusnum)
   ON CONFLICT (s_icusnum) DO UPDATE
      SET in_scope = true,
          is_requested = current_scope.is_requested OR EXCLUDED.is_requested,
          source_seen = current_scope.source_seen OR EXCLUDED.source_seen;

   INSERT INTO pg_temp.mi_0008_acc_tmp
   (
      s_icusnum,
      msum_f_dep, msum_i_dep, msum_f_crd, msum_i_crd,
      msum_f_acc, msum_i_acc
   )
   SELECT coalesce(a.r_icusnum, a.s_icusnum),
          NULLIF(sum(a.msum_f_dep), 0)::numeric(22,2),
          NULLIF(sum(a.msum_i_dep), 0)::numeric(22,2),
          NULLIF(sum(a.msum_f_crd), 0)::numeric(22,2),
          NULLIF(sum(a.msum_i_crd), 0)::numeric(22,2),
          NULLIF(sum(a.msum_f_acc), 0)::numeric(22,2),
          NULLIF(sum(a.msum_i_acc), 0)::numeric(22,2)
     FROM pg_temp.mi_0008_acc_tmp AS a
    WHERE a.san_result_code IS NULL
       OR a.san_result_code = 'CUS_MAP'
    GROUP BY coalesce(a.r_icusnum, a.s_icusnum)
   ON CONFLICT (s_icusnum) DO UPDATE
      SET msum_f_dep = EXCLUDED.msum_f_dep,
          msum_i_dep = EXCLUDED.msum_i_dep,
          msum_f_crd = EXCLUDED.msum_f_crd,
          msum_i_crd = EXCLUDED.msum_i_crd,
          msum_f_acc = EXCLUDED.msum_f_acc,
          msum_i_acc = EXCLUDED.msum_i_acc,
          r_icusnum = NULL,
          san_result_code = NULL,
          san_result_info = NULL,
          san_result_data = NULL;

   -- Все особые состояния уже сохранены в mi_0008_lsr_itm. Полученные выше
   -- корневые строки являются обычными строками аккумулятора; особые исходные
   -- строки теперь можно удалить.
   DELETE FROM pg_temp.mi_0008_acc_tmp
    WHERE san_result_code IS NOT NULL;
END;
$procedure$


/*
 * Итоговый конвейер корней, истории, данных клиента и решений параметризован
 * типом run_context_t и расположен в write_Report; сессионные представления
 * не создаются.
 */
CREATE PROCEDURE finish_Run(
   IN p_ctx       mi_0008_api.run_context_t,
   IN p_status_cd varchar,
   IN p_req_id    numeric,
   IN p_ires_code int4,
   IN p_cres_info text
)
AS
$procedure$
   #package
   #private
DECLARE
   l_count bigint;
BEGIN
   UPDATE xxi.mi_0008_lsr AS l
      SET status_cd   = p_status_cd,
          stage_cd    = 'FINISHED',
          finished_at = clock_timestamp(),
          req_id      = p_req_id,
          ires_code   = p_ires_code,
          cres_info   = p_cres_info
    WHERE l.lsr_id = p_ctx.lsr_id
      AND l.status_cd = 'RUNNING'
      AND l.finished_at IS NULL;

   GET DIAGNOSTICS l_count = ROW_COUNT;
   IF l_count <> 1 THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#LSR_NOT_ACTIVE',
         p_result_info => format('LSR %s is not active', p_ctx.lsr_id)
      );
   END IF;
END;
$procedure$


/*
 * Параметризованный итоговый конвейер. Набор решений материализуется один раз
 * внутри этого оператора; сессионная таблица контекста и итоговые представления
 * не требуются.
 */
CREATE PROCEDURE write_Report(
   IN  p_ctx          mi_0008_api.run_context_t,
   IN  p_ctaxreq_id   varchar,
   OUT p_req_id       numeric,
   OUT p_ires_code    int4,
   OUT p_cres_info    text
)
AS
$procedure$
   #package
   #private
DECLARE
   l_candidate_count  bigint := 0;
   l_emit_count       bigint := 0;
   l_written_count    bigint := 0;
   l_person_count     bigint := 0;
   l_linked_count     bigint := 0;

   l_unchanged_count  bigint := 0;
   l_diag_count       bigint := 0;
   l_diag_written     bigint := 0;
   l_icorr_diag_count bigint := 0;
   l_san_reject_count bigint := 0;
BEGIN
   p_req_id    := NULL;
   p_ires_code := c_result_no_data;
   p_cres_info := NULL;

   /*
    * Рабочая таблица содержит ровно одну строку
    * на одного итогового клиента после Sanitarium
    * и объединения по связи 17.
    */
   DROP TABLE IF EXISTS pg_temp.mi_0008_report_tmp;

   CREATE TEMPORARY TABLE mi_0008_report_tmp
   (
      icusnum numeric(12) NOT NULL,

      is_requested boolean NOT NULL DEFAULT false,
      source_seen  boolean NOT NULL DEFAULT false,

      /*
       * Суммы, полученные из аккумулятора.
       */
      msum_f_dep numeric(22,2),
      msum_i_dep numeric(22,2),
      msum_f_crd numeric(22,2),
      msum_i_crd numeric(22,2),
      msum_f_acc numeric(22,2),
      msum_i_acc numeric(22,2),

      /*
       * Последняя допустимая историческая запись.
       */
      has_primary   boolean NOT NULL DEFAULT false,
      hist_itm_id   numeric(12),
      hist_icorr    numeric(2),
      hist_inum     numeric(12),
      hist_person_id numeric(12),

      hist_msum_f_dep numeric(22,2),
      hist_msum_i_dep numeric(22,2),
      hist_msum_f_crd numeric(22,2),
      hist_msum_i_crd numeric(22,2),
      hist_msum_f_acc numeric(22,2),
      hist_msum_i_acc numeric(22,2),

      /*
       * Текущий снимок клиента.
       */
      first_name        varchar(50),
      last_name         varchar(50),
      middle_name       varchar(50),
      ctzn_country_code varchar(10),
      inn               varchar(13),

      doc_type_id       numeric(3),
      doc_type_code     varchar(20),
      doc_ser           varchar(10),
      doc_num           varchar(20),
      doc_issue_date    date,
      doc_issuer_code   varchar(20),
      doc_expire_date   date,
      doc_issuer_name   varchar(500),

      birth_date date,

      /*
       * Исторический снимок клиента.
       * Используется только для проверки неизменности
       * банковского уточнения сведений о физическом лице.
       */
      old_first_name        varchar(50),
      old_last_name         varchar(50),
      old_middle_name       varchar(50),
      old_ctzn_country_code varchar(10),
      old_birth_date        date,
      old_inn               varchar(13),
      old_doc_type_id       numeric(3),
      old_doc_ser           varchar(10),
      old_doc_num           varchar(20),
      old_doc_issue_date    date,

      /*
       * Итоговые суммы строки отчёта.
       */
      out_msum_f_dep numeric(22,2),
      out_msum_i_dep numeric(22,2),
      out_msum_f_crd numeric(22,2),
      out_msum_i_crd numeric(22,2),
      out_msum_f_acc numeric(22,2),
      out_msum_i_acc numeric(22,2),

      /*
       * Расчётное состояние строки.
       *
       * numeric(3) используется намеренно:
       * после исторического icorr=99 расчётное значение
       * может временно стать 100, но такая строка никогда
       * не записывается в xxi.mi_0008.
       */
      target_icorr       numeric(3),
      financial_total    numeric,
      financial_unchanged boolean,
      person_unchanged    boolean,

      decision_code varchar(50),

      /*
       * Идентификатор нового immutable-снимка.
       */
      person_id numeric(12),

      CONSTRAINT pk_mi_0008_report_tmp
         PRIMARY KEY (icusnum)
   ) ON COMMIT DROP;

   /*
    * После collapse_To_Roots и проверки итоговых клиентов
    * в расчёт допускаются только строки без результата Sanitarium.
    */
   INSERT INTO pg_temp.mi_0008_report_tmp
   (
      icusnum,
      is_requested,
      source_seen,

      msum_f_dep,
      msum_i_dep,
      msum_f_crd,
      msum_i_crd,
      msum_f_acc,
      msum_i_acc
   )
   SELECT a.s_icusnum,
          coalesce(s.is_requested, false),
          coalesce(s.source_seen, false),

          a.msum_f_dep,
          a.msum_i_dep,
          a.msum_f_crd,
          a.msum_i_crd,
          a.msum_f_acc,
          a.msum_i_acc

     FROM pg_temp.mi_0008_acc_tmp AS a

     LEFT JOIN pg_temp.mi_0008_scope_tmp AS s
       ON s.s_icusnum = a.s_icusnum

    WHERE a.san_result_code IS NULL;

   /*
    * Таблица может содержать сотни тысяч строк.
    * Статистика собирается один раз перед тяжёлыми соединениями.
    */
   ANALYZE pg_temp.mi_0008_report_tmp;

   /*
    * История ограничивается:
    *
    *   - текущим видом сведений;
    *   - текущим отчётным годом;
    *   - запросами в статусах 1, 2, 3.
    *
    * Последняя запись определяется по порядку фактического создания,
    * а не через MAX(icorr).
    *
    * Одновременно определяется наличие первичной записи.
    */
   WITH latest AS MATERIALIZED
   (
      SELECT DISTINCT ON (r.icusnum)
             r.icusnum,

             bool_or(i.icorr = 0)
                OVER (PARTITION BY r.icusnum) AS has_primary,

             i.itm_id,
             i.icorr,
             i.inum,
             i.person_id,

             i.msum_f_dep,
             i.msum_i_dep,
             i.msum_f_crd,
             i.msum_i_crd,
             i.msum_f_acc,
             i.msum_i_acc,

             oldp.first_name,
             oldp.last_name,
             oldp.middle_name,
             oldp.ctzn_country_code,
             oldp.birth_date,
             oldp.inn,
             oldp.doc_type_id,
             oldp.doc_ser,
             oldp.doc_num,
             oldp.doc_issue_date

        FROM pg_temp.mi_0008_report_tmp AS r

        JOIN xxi.mi_0008 AS i
          ON i.icusnum = r.icusnum
         AND i.iyear = p_ctx.iyear

        JOIN xxi.mi_req AS q
          ON q.req_id = i.req_id
         AND q.inf_id = p_ctx.inf_id
         AND q.status_cd IN (1, 2, 3)

        LEFT JOIN xxi.mi_person AS oldp
          ON oldp.person_id = i.person_id

       ORDER BY r.icusnum,
                q.created_at DESC,
                q.req_id DESC,
                i.itm_id DESC
   )
   UPDATE pg_temp.mi_0008_report_tmp AS r
      SET has_primary = h.has_primary,

          hist_itm_id    = h.itm_id,
          hist_icorr     = h.icorr,
          hist_inum      = h.inum,
          hist_person_id = h.person_id,

          hist_msum_f_dep = h.msum_f_dep,
          hist_msum_i_dep = h.msum_i_dep,
          hist_msum_f_crd = h.msum_f_crd,
          hist_msum_i_crd = h.msum_i_crd,
          hist_msum_f_acc = h.msum_f_acc,
          hist_msum_i_acc = h.msum_i_acc,

          old_first_name        = h.first_name,
          old_last_name         = h.last_name,
          old_middle_name       = h.middle_name,
          old_ctzn_country_code = h.ctzn_country_code,
          old_birth_date        = h.birth_date,
          old_inn               = h.inn,
          old_doc_type_id       = h.doc_type_id,
          old_doc_ser           = h.doc_ser,
          old_doc_num           = h.doc_num,
          old_doc_issue_date    = h.doc_issue_date

     FROM latest AS h
    WHERE h.icusnum = r.icusnum;

   /*
    * Формируется текущий immutable-снимок клиента.
    *
    * Проверки здесь не выполняются: итоговый клиент уже прошёл
    * sanitize_Root_Cus.
    *
    * Выбор ДУЛ совпадает с Sanitarium:
    *
    *   1. последний preferred-документ;
    *   2. если его тип не распознан — последний действующий
    *      non-preferred-документ.
    */
   WITH person_cur AS MATERIALIZED
   (
      SELECT r.icusnum,

             coalesce(c.ccusfirst_name, 'отсутствует')::varchar(50)
                AS first_name,

             coalesce(c.ccuslast_name, 'отсутствует')::varchar(50)
                AS last_name,

             c.ccusmiddle_name::varchar(50)
                AS middle_name,

             coalesce(cus_country.cdigital, doc_country.cdigital)::varchar(10)
                AS ctzn_country_code,

             c.ccusnumnal::varchar(13)
                AS inn,

             coalesce(pref_doc.doc_type_id, alt_doc.doc_type_id)
                AS doc_type_id,

             CASE
                WHEN pref_doc.doc_type_id IS NOT NULL
                   THEN pref_doc.doc_type_code
                ELSE alt_doc.doc_type_code
             END AS doc_type_code,

             CASE
                WHEN pref_doc.doc_type_id IS NOT NULL
                   THEN pref_doc.doc_ser
                ELSE alt_doc.doc_ser
             END AS doc_ser,

             CASE
                WHEN pref_doc.doc_type_id IS NOT NULL
                   THEN pref_doc.doc_num
                ELSE alt_doc.doc_num
             END AS doc_num,

             CASE
                WHEN pref_doc.doc_type_id IS NOT NULL
                   THEN pref_doc.doc_issue_date
                ELSE alt_doc.doc_issue_date
             END AS doc_issue_date,

             CASE
                WHEN pref_doc.doc_type_id IS NOT NULL
                   THEN pref_doc.doc_issuer_code
                ELSE alt_doc.doc_issuer_code
             END AS doc_issuer_code,

             CASE
                WHEN pref_doc.doc_type_id IS NOT NULL
                   THEN pref_doc.doc_expire_date
                ELSE alt_doc.doc_expire_date
             END AS doc_expire_date,

             CASE
                WHEN pref_doc.doc_type_id IS NOT NULL
                   THEN pref_doc.doc_issuer_name
                ELSE alt_doc.doc_issuer_name
             END AS doc_issuer_name,

             c.dcusbirthday::date
                AS birth_date

        FROM pg_temp.mi_0008_report_tmp AS r

        JOIN xxi."CUS" AS c
          ON c.icusnum = r.icusnum

        LEFT JOIN LATERAL
        (
           SELECT CASE
                     WHEN btrim(p.cpudcode9) ~ '^[0-9]{1,3}$'
                        THEN btrim(p.cpudcode9)::numeric(3)
                     ELSE NULL::numeric(3)
                  END AS doc_type_id,

                  NULLIF(btrim(p.cpudcode9), '')::varchar(20)
                     AS doc_type_code,

                  d.doc_ser::varchar(10)
                     AS doc_ser,

                  d.doc_num::varchar(20)
                     AS doc_num,

                  d.doc_date::date
                     AS doc_issue_date,

                  d.doc_subdiv::varchar(20)
                     AS doc_issuer_code,

                  d.doc_period::date
                     AS doc_expire_date,

                  d.doc_agency::varchar(500)
                     AS doc_issuer_name,

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

                  NULLIF(btrim(p.cpudcode9), '')::varchar(20)
                     AS doc_type_code,

                  d.doc_ser::varchar(10)
                     AS doc_ser,

                  d.doc_num::varchar(20)
                     AS doc_num,

                  d.doc_date::date
                     AS doc_issue_date,

                  d.doc_subdiv::varchar(20)
                     AS doc_issuer_code,

                  d.doc_period::date
                     AS doc_expire_date,

                  d.doc_agency::varchar(500)
                     AS doc_issuer_name,

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
   )
   UPDATE pg_temp.mi_0008_report_tmp AS r
      SET first_name        = p.first_name,
          last_name         = p.last_name,
          middle_name       = p.middle_name,
          ctzn_country_code = p.ctzn_country_code,
          inn               = p.inn,

          doc_type_id       = p.doc_type_id,
          doc_type_code     = p.doc_type_code,
          doc_ser           = p.doc_ser,
          doc_num           = p.doc_num,
          doc_issue_date    = p.doc_issue_date,
          doc_issuer_code   = p.doc_issuer_code,
          doc_expire_date   = p.doc_expire_date,
          doc_issuer_name   = p.doc_issuer_name,

          birth_date = p.birth_date

     FROM person_cur AS p
    WHERE p.icusnum = r.icusnum;

   /*
    * Вычисляются суммы итоговой строки и номер корректировки.
    *
    * Для уточнения сведений о физическом лице используются
    * суммы последней исторической строки.
    *
    * Для запроса ФНС по суммам, если выбранный клиент не пришёл
    * из источников, также используются исторические суммы.
    *
    * Аннулирование всегда содержит NULL во всех шести суммах.
    */
   UPDATE pg_temp.mi_0008_report_tmp AS r
      SET out_msum_f_dep =
             CASE
                WHEN p_ctx.launch_itype = 3
                   THEN NULL

                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_person
                   THEN r.hist_msum_f_dep

                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_sum
                 AND p_ctx.irsn_corr = c_reason_fns
                 AND r.is_requested
                 AND NOT r.source_seen
                   THEN r.hist_msum_f_dep

                ELSE r.msum_f_dep
             END,

          out_msum_i_dep =
             CASE
                WHEN p_ctx.launch_itype = 3
                   THEN NULL

                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_person
                   THEN r.hist_msum_i_dep

                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_sum
                 AND p_ctx.irsn_corr = c_reason_fns
                 AND r.is_requested
                 AND NOT r.source_seen
                   THEN r.hist_msum_i_dep

                ELSE r.msum_i_dep
             END,

          out_msum_f_crd =
             CASE
                WHEN p_ctx.launch_itype = 3
                   THEN NULL

                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_person
                   THEN r.hist_msum_f_crd

                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_sum
                 AND p_ctx.irsn_corr = c_reason_fns
                 AND r.is_requested
                 AND NOT r.source_seen
                   THEN r.hist_msum_f_crd

                ELSE r.msum_f_crd
             END,

          out_msum_i_crd =
             CASE
                WHEN p_ctx.launch_itype = 3
                   THEN NULL

                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_person
                   THEN r.hist_msum_i_crd

                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_sum
                 AND p_ctx.irsn_corr = c_reason_fns
                 AND r.is_requested
                 AND NOT r.source_seen
                   THEN r.hist_msum_i_crd

                ELSE r.msum_i_crd
             END,

          out_msum_f_acc =
             CASE
                WHEN p_ctx.launch_itype = 3
                   THEN NULL

                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_person
                   THEN r.hist_msum_f_acc

                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_sum
                 AND p_ctx.irsn_corr = c_reason_fns
                 AND r.is_requested
                 AND NOT r.source_seen
                   THEN r.hist_msum_f_acc

                ELSE r.msum_f_acc
             END,

          out_msum_i_acc =
             CASE
                WHEN p_ctx.launch_itype = 3
                   THEN NULL

                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_person
                   THEN r.hist_msum_i_acc

                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_sum
                 AND p_ctx.irsn_corr = c_reason_fns
                 AND r.is_requested
                 AND NOT r.source_seen
                   THEN r.hist_msum_i_acc

                ELSE r.msum_i_acc
             END,

          target_icorr =
             CASE
                WHEN p_ctx.launch_itype = 1
                   THEN 0

                WHEN p_ctx.launch_itype = 3
                   THEN 99

                WHEN r.hist_itm_id IS NULL
                   THEN 0

                ELSE r.hist_icorr + 1
             END;

   /*
    * Сравнение сумм выполняется поколоночно и NULL-safe.
    * Общая сумма используется только для отсечения
    * неположительного финансового результата.
    */
   UPDATE pg_temp.mi_0008_report_tmp AS r
      SET financial_total =
             coalesce(r.out_msum_f_dep, 0)
           + coalesce(r.out_msum_i_dep, 0)
           + coalesce(r.out_msum_f_crd, 0)
           + coalesce(r.out_msum_i_crd, 0)
           + coalesce(r.out_msum_f_acc, 0)
           + coalesce(r.out_msum_i_acc, 0),

          financial_unchanged =
             r.out_msum_f_dep IS NOT DISTINCT FROM r.hist_msum_f_dep
         AND r.out_msum_i_dep IS NOT DISTINCT FROM r.hist_msum_i_dep
         AND r.out_msum_f_crd IS NOT DISTINCT FROM r.hist_msum_f_crd
         AND r.out_msum_i_crd IS NOT DISTINCT FROM r.hist_msum_i_crd
         AND r.out_msum_f_acc IS NOT DISTINCT FROM r.hist_msum_f_acc
         AND r.out_msum_i_acc IS NOT DISTINCT FROM r.hist_msum_i_acc,

          person_unchanged =
             r.first_name IS NOT DISTINCT FROM r.old_first_name
         AND r.last_name IS NOT DISTINCT FROM r.old_last_name
         AND r.middle_name IS NOT DISTINCT FROM r.old_middle_name
         AND r.ctzn_country_code
                IS NOT DISTINCT FROM r.old_ctzn_country_code
         AND r.birth_date IS NOT DISTINCT FROM r.old_birth_date
         AND r.inn IS NOT DISTINCT FROM r.old_inn
         AND r.doc_type_id IS NOT DISTINCT FROM r.old_doc_type_id
         AND r.doc_ser IS NOT DISTINCT FROM r.old_doc_ser
         AND r.doc_num IS NOT DISTINCT FROM r.old_doc_num
         AND r.doc_issue_date IS NOT DISTINCT FROM r.old_doc_issue_date;

   /*
    * Определяется итоговое решение по каждому клиенту.
    *
    * Проверок CUS, ДУЛ, ИНН и даты рождения здесь нет:
    * они уже выполнены Sanitarium.
    */
   UPDATE pg_temp.mi_0008_report_tmp AS r
      SET decision_code =
          CASE
             /*
              * Последняя строка icorr=99 всегда означает,
              * что новые действия по клиенту запрещены.
              */
             WHEN r.hist_icorr = 99
                THEN 'ICORR_AFTER_CANCEL'

             /*
              * Повторная первичная строка для того же
              * inf_id и отчётного года не создаётся.
              */
             WHEN p_ctx.launch_itype = 1
              AND r.has_primary
                THEN 'ALREADY_PRIMARY'

             /*
              * Oracle-specific skip:
              * уточнение сведений о физическом лице
              * невозможно без исторической строки.
              */
             WHEN p_ctx.launch_itype = 2
              AND p_ctx.ireq_kind = c_kind_person
              AND r.hist_itm_id IS NULL
                THEN 'PERSON_NO_HISTORY'

             /*
              * Обычная коррекция после 97 дала бы 98,
              * а после legacy 98 — 99.
              * Обе ситуации запрещены.
              *
              * Для явного аннулирования эта проверка
              * не применяется: после legacy 98 можно
              * сформировать icorr=99.
              */
             WHEN p_ctx.launch_itype = 2
              AND r.hist_icorr IN (97, 98)
                THEN 'ICORR_EXHAUSTED'

             /*
              * Неположительная сумма не превращается
              * в аннулирование.
              */
             WHEN p_ctx.launch_itype IN (1, 2)
              AND p_ctx.ireq_kind = c_kind_sum
              AND r.financial_total <= 0
                THEN 'NONPOSITIVE_TOTAL'

             /*
              * Банк не формирует финансовую коррекцию,
              * если все шесть сумм остались прежними.
              *
              * Для ФНС строка создаётся даже без изменений.
              */
             WHEN p_ctx.launch_itype = 2
              AND p_ctx.ireq_kind = c_kind_sum
              AND p_ctx.irsn_corr <> c_reason_fns
              AND r.hist_itm_id IS NOT NULL
              AND r.financial_unchanged
                THEN 'UNCHANGED_FINANCIAL'

             /*
              * Банк не формирует person-коррекцию,
              * если Oracle-набор полей не изменился.
              *
              * Для ФНС строка создаётся даже без изменений.
              */
             WHEN p_ctx.launch_itype = 2
              AND p_ctx.ireq_kind = c_kind_person
              AND p_ctx.irsn_corr <> c_reason_fns
              AND r.person_unchanged
                THEN 'UNCHANGED_PERSON'

             /*
              * Защита от уже занятого физического ключа.
              * Проверяется вся xxi.mi_0008, поскольку её
              * уникальность не содержит inf_id.
              */
             WHEN EXISTS
                  (
                     SELECT 1
                       FROM xxi.mi_0008 AS occupied
                      WHERE occupied.icusnum = r.icusnum
                        AND occupied.iyear = p_ctx.iyear
                        AND occupied.icorr = r.target_icorr
                  )
                THEN 'ITEM_KEY_EXISTS'

             ELSE 'EMIT'
          END;

   /*
    * Подсчитываются решения.
    */
   SELECT count(*),

          count(*) FILTER (
             WHERE r.decision_code = 'EMIT'
          ),

          count(*) FILTER (
             WHERE r.decision_code IN
                   (
                      'UNCHANGED_FINANCIAL',
                      'UNCHANGED_PERSON'
                   )
          ),

          count(*) FILTER (
             WHERE r.decision_code IN
                   (
                      'ICORR_EXHAUSTED',
                      'ICORR_AFTER_CANCEL',
                      'PERSON_NO_HISTORY',
                      'ITEM_KEY_EXISTS'
                   )
          ),

          count(*) FILTER (
             WHERE r.decision_code IN
                   (
                      'ICORR_EXHAUSTED',
                      'ICORR_AFTER_CANCEL'
                   )
          )

     INTO l_candidate_count,
          l_emit_count,
          l_unchanged_count,
          l_diag_count,
          l_icorr_diag_count

     FROM pg_temp.mi_0008_report_tmp AS r;

   /*
    * В статистику входят все отклонения Sanitarium,
    * включая граф связи 17 и проверки итогового клиента.
    *
    * CUS_MAP сюда не попадает.
    */
   SELECT count(*)
     INTO l_san_reject_count
     FROM xxi.mi_0008_lsr_itm AS i
    WHERE i.lsr_id = p_ctx.lsr_id
      AND i.result_code LIKE 'SAN%';

   /*
    * Сохраняются только действительно исключительные
    * final-write состояния.
    *
    * icorr=-1 физически нигде не создаётся.
    */
   INSERT INTO xxi.mi_0008_lsr_itm
   (
      lsr_id,
      s_icusnum,
      r_icusnum,
      result_code,
      result_info,
      result_data
   )
   SELECT p_ctx.lsr_id,
          r.icusnum,
          r.icusnum,
          r.decision_code,

          CASE r.decision_code
             WHEN 'ICORR_EXHAUSTED'
                THEN format(
                   'Обычная коррекция после icorr=%s попадает в зарезервированный диапазон',
                   r.hist_icorr
                )

             WHEN 'ICORR_AFTER_CANCEL'
                THEN 'Последняя допустимая историческая строка является аннулированием icorr=99'

             WHEN 'PERSON_NO_HISTORY'
                THEN 'Для уточнения сведений о физическом лице отсутствует допустимая историческая строка'

             WHEN 'ITEM_KEY_EXISTS'
                THEN format(
                   'Итоговый ключ строки уже существует: год=%s, icorr=%s',
                   p_ctx.iyear,
                   r.target_icorr
                )

             ELSE r.decision_code
          END,

          jsonb_strip_nulls(
             jsonb_build_object(
                'history_itm_id', r.hist_itm_id,
                'history_icorr', r.hist_icorr,
                'target_icorr', r.target_icorr
             )
          )::text

     FROM pg_temp.mi_0008_report_tmp AS r

    WHERE r.decision_code IN
          (
             'ICORR_EXHAUSTED',
             'ICORR_AFTER_CANCEL',
             'PERSON_NO_HISTORY',
             'ITEM_KEY_EXISTS'
          )

   ON CONFLICT (lsr_id, s_icusnum) DO UPDATE
      SET r_icusnum   = EXCLUDED.r_icusnum,
          result_code = EXCLUDED.result_code,
          result_info = EXCLUDED.result_info,
          result_data = EXCLUDED.result_data;

   GET DIAGNOSTICS l_diag_written = ROW_COUNT;

   IF l_diag_written <> l_diag_count THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#DIAGNOSTIC_CARDINALITY',
         p_result_info => format(
            'Ожидалось диагностических записей: %s, сохранено: %s',
            l_diag_count,
            l_diag_written
         )
      );
   END IF;

   IF l_diag_count > 0 THEN
      CALL MI_logger.warn(
         p_logger_name  => cLogger,
         p_message_text => format(
            'Для %s клиентов записана диагностика формирования отчёта',
            l_diag_count
         ),
         p_inf_id      => p_ctx.inf_id,
         p_action_cd   => 'write_report',
         p_object_name => cPkg_Name,
         p_object_id   => p_ctx.lsr_id
      );
   END IF;

   IF l_icorr_diag_count > 0 THEN
      CALL MI_logger.warn(
         p_logger_name  => cLogger,
         p_message_text => format(
            'Для %s клиентов достигнута граница номера корректировки',
            l_icorr_diag_count
         ),
         p_inf_id      => p_ctx.inf_id,
         p_action_cd   => 'icorr',
         p_object_name => cPkg_Name,
         p_object_id   => p_ctx.lsr_id
      );
   END IF;

   /*
    * Пустой запрос не создаётся.
    */
   IF l_emit_count = 0 THEN
      p_req_id    := NULL;
      p_ires_code := c_result_no_data;
      p_cres_info := format(
         'NO_DATA: accepted_roots=%s, emitted=0, unchanged=%s, san_rejected=%s, diagnostics=%s',
         l_candidate_count,
         l_unchanged_count,
         l_san_reject_count,
         l_diag_count
      );

      RETURN;
   END IF;

   /*
    * Заголовок создаётся отдельным явным действием
    * только после подтверждения наличия строк EMIT.
    *
    * Общий report-level itype для MI_0008 не используется.
    */
   p_req_id := MI_Request_Api.create_Request(
      p_inf_id     => p_ctx.inf_id,
      p_ctaxreq_id => NULLIF(btrim(p_ctaxreq_id), ''),
      p_status_cd  => 0::numeric,
      p_itype      => NULL::numeric,
      p_i1         => p_ctx.iyear,
      p_i2         => p_ctx.irsn_corr,
      p_i3         => p_ctx.ireq_kind
   );

   IF p_req_id IS NULL THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#REQUEST_NOT_CREATED',
         p_result_info => 'Функция создания запроса вернула NULL'
      );
   END IF;

   /*
    * Для каждой строки отчёта создаётся новый immutable-снимок.
    * Существующие записи mi_person не изменяются и не переиспользуются.
    */
   WITH inserted_person AS
   (
      INSERT INTO xxi.mi_person
      (
         icusnum,

         first_name,
         last_name,
         middle_name,

         ctzn_country_code,
         inn,

         doc_type_id,
         doc_type_code,
         doc_ser,
         doc_num,
         doc_issue_date,
         doc_issuer_code,
         doc_expire_date,
         doc_issuer_name,

         birth_date
      )
      SELECT r.icusnum,

             r.first_name,
             r.last_name,
             r.middle_name,

             r.ctzn_country_code,
             r.inn,

             r.doc_type_id,
             r.doc_type_code,
             r.doc_ser,
             r.doc_num,
             r.doc_issue_date,
             r.doc_issuer_code,
             r.doc_expire_date,
             r.doc_issuer_name,

             r.birth_date

        FROM pg_temp.mi_0008_report_tmp AS r
       WHERE r.decision_code = 'EMIT'

      RETURNING person_id, icusnum
   )
   UPDATE pg_temp.mi_0008_report_tmp AS r
      SET person_id = p.person_id
     FROM inserted_person AS p
    WHERE p.icusnum = r.icusnum;

   GET DIAGNOSTICS l_person_count = ROW_COUNT;

   IF l_person_count <> l_emit_count THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#PERSON_CARDINALITY',
         p_result_info => format(
            'Ожидалось снимков физического лица: %s, создано: %s',
            l_emit_count,
            l_person_count
         )
      );
   END IF;

   /*
    * Новый снимок связывается с фактическим inf_id запуска.
    */
   INSERT INTO xxi.mi_p2i
   (
      person_id,
      inf_id
   )
   SELECT r.person_id,
          p_ctx.inf_id
     FROM pg_temp.mi_0008_report_tmp AS r
    WHERE r.decision_code = 'EMIT'
   ON CONFLICT (person_id, inf_id) DO NOTHING;

   GET DIAGNOSTICS l_linked_count = ROW_COUNT;

   IF l_linked_count <> l_emit_count THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#PERSON_LINK_CARDINALITY',
         p_result_info => format(
            'Ожидалось связей person/inf: %s, создано: %s',
            l_emit_count,
            l_linked_count
         )
      );
   END IF;

   /*
    * Записываются итоговые строки отчёта.
    *
    * Тип строки физически не сохраняется:
    *
    *   icorr=0     -> itype=1 во view;
    *   icorr=1..98 -> itype=2 во view;
    *   icorr=99    -> itype=3 во view.
    */
   INSERT INTO xxi.mi_0008
   (
      req_id,
      icusnum,
      iyear,
      icorr,
      inum,
      person_id,

      msum_f_dep,
      msum_i_dep,
      msum_f_crd,
      msum_i_crd,
      msum_f_acc,
      msum_i_acc
   )
   SELECT p_req_id,
          r.icusnum,
          p_ctx.iyear,
          r.target_icorr,

          coalesce(
             r.hist_inum,
             nextval('xxi.s_mi_0008__inum')
          ),

          r.person_id,

          r.out_msum_f_dep,
          r.out_msum_i_dep,
          r.out_msum_f_crd,
          r.out_msum_i_crd,
          r.out_msum_f_acc,
          r.out_msum_i_acc

     FROM pg_temp.mi_0008_report_tmp AS r
    WHERE r.decision_code = 'EMIT';

   GET DIAGNOSTICS l_written_count = ROW_COUNT;

   IF l_written_count <> l_emit_count THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#WRITE_CARDINALITY',
         p_result_info => format(
            'Ожидалось строк отчёта: %s, записано: %s',
            l_emit_count,
            l_written_count
         )
      );
   END IF;

   p_ires_code := c_result_ok;
   p_cres_info := format(
      'OK: accepted_roots=%s, written=%s, unchanged=%s, san_rejected=%s, diagnostics=%s',
      l_candidate_count,
      l_written_count,
      l_unchanged_count,
      l_san_reject_count,
      l_diag_count
   );
END;
$procedure$






/*
 * Основная бизнес-точка входа. Процедура формирует один запрос отчёта и никогда
 * его не отправляет. Бизнес-результаты возвращаются через OUT-параметры;
 * технические ошибки логируются и пробрасываются повторно. COMMIT выполняет
 * вызывающая сторона.
 */
CREATE PROCEDURE prepare_Report(
   IN  p_inf_id       numeric,
   IN  p_iyear        numeric,
   IN  p_itype        numeric,
   IN  p_irsn_corr    numeric,
   IN  p_ireq_kind    numeric,
   IN  p_cus_marker   numeric,
   IN  p_ctaxreq_id   varchar,
   OUT p_lsr_id       numeric,
   OUT p_req_id       numeric,
   OUT p_ires_code    int4,
   OUT p_cres_info    text,
   IN  p_pack_num     numeric DEFAULT NULL
)
SECURITY INVOKER
AS
$procedure$
   #package
DECLARE
   cAction_Name CONSTANT varchar(50) := cPkg_Name || '.prepare_Report';

   l_ctx             mi_0008_api.run_context_t;
   l_scope_all       boolean;
   l_scope_count     bigint;
   l_acc_count       bigint;
   l_san_code        int4;
   l_san_info        varchar;
   l_req_id          numeric;
   l_write_code      int4;
   l_write_info      text;
BEGIN
   p_lsr_id := NULL;
   p_req_id := NULL;
   p_ires_code := ret_Fail;
   p_cres_info := NULL;

   CALL MI_logger.enter_f(
      p_logger_name   => cLogger,
      p_function_name => cAction_Name,
      p_inf_id        => p_inf_id,
      p_parameters    => format(
         'year=%s,type=%s,reason=%s,kind=%s,marker=%s,pack=%s',
         p_iyear, p_itype, p_irsn_corr, p_ireq_kind,
         p_cus_marker, p_pack_num
      )
   );

   ---------------------------------------------------------------------------
   -- Проверка бизнес-параметров. Для некорректного запроса LSR не создаётся.
   ---------------------------------------------------------------------------
   IF p_inf_id IS NULL OR p_inf_id NOT IN (8, 81) THEN
      p_cres_info := 'INVALID_INF_ID: allowed values are 8 and 81';
   ELSIF p_iyear IS NULL OR p_iyear <> trunc(p_iyear)
         OR p_iyear NOT BETWEEN 1 AND 9999 THEN
      p_cres_info := 'INVALID_YEAR';
   ELSIF p_itype IS NULL OR p_itype NOT IN (1, 2, 3, 4) THEN
      p_cres_info := 'INVALID_ITYPE';
   ELSIF p_itype = 4 THEN
      p_cres_info := 'NOT_SUPPORTED: p_itype=4';
   ELSIF p_irsn_corr IS NULL OR p_irsn_corr NOT IN (1, 2) THEN
      p_cres_info := 'INVALID_REASON';
   ELSIF p_ireq_kind IS NULL OR p_ireq_kind NOT IN (1, 2) THEN
      p_cres_info := 'INVALID_REQUEST_KIND';
   ELSIF p_inf_id = 81 AND NULLIF(btrim(p_ctaxreq_id), '') IS NULL THEN
      p_cres_info := 'CTAXREQ_ID_REQUIRED_FOR_INF_81';
   ELSIF p_itype = 1 AND p_ireq_kind <> c_kind_sum THEN
      p_cres_info := 'PRIMARY_REQUIRES_FINANCIAL_KIND';
   ELSIF p_itype = 1 AND p_cus_marker IS NOT NULL AND p_pack_num IS NULL THEN
      p_cres_info := 'PACK_NUM_REQUIRED_FOR_PRIMARY_MARKER';
   ELSIF p_itype = 2 AND p_irsn_corr = c_reason_fns
         AND p_cus_marker IS NULL THEN
      p_cres_info := 'MARKER_REQUIRED_FOR_FNS_CORRECTION';
   ELSIF p_itype = 3 AND p_cus_marker IS NULL THEN
      p_cres_info := 'MARKER_REQUIRED_FOR_CANCELLATION';
   END IF;

   IF p_cres_info IS NOT NULL THEN
      CALL MI_logger.exit_f(
         p_logger_name  => cLogger,
         p_message_text => p_cres_info,
         p_inf_id       => p_inf_id
      );
      RETURN;
   END IF;

   ---------------------------------------------------------------------------
   -- Неблокирующая защита. Частичный уникальный индекс остаётся вторым уровнем
   -- защиты для путей выполнения вне этого пакета.
   ---------------------------------------------------------------------------
   IF NOT pg_catalog.pg_try_advisory_xact_lock(
      pg_catalog.hashtext('mi_0008.prepare_report')::int4,
      p_iyear::int4
   ) THEN
      p_ires_code := c_result_busy;
      p_cres_info := format('BUSY: inf_id=%s, year=%s', p_inf_id, p_iyear);
      CALL MI_logger.exit_f(
         p_logger_name  => cLogger,
         p_message_text => p_cres_info,
         p_inf_id       => p_inf_id
      );
      RETURN;
   END IF;

   INSERT INTO xxi.mi_0008_lsr
   (
      itype, iyear, irsn_corr, ireq_kind,
      status_cd, stage_cd, started_at
   )
   VALUES
   (
      p_itype, p_iyear, p_irsn_corr, p_ireq_kind,
      'RUNNING', 'CREATED', clock_timestamp()
   )
   ON CONFLICT (iyear) WHERE finished_at IS NULL DO NOTHING
   RETURNING lsr_id INTO p_lsr_id;

   IF NOT FOUND THEN
      p_ires_code := c_result_busy;
      p_cres_info := format('BUSY: active LSR for year=%s', p_iyear);
      CALL MI_logger.exit_f(
         p_logger_name  => cLogger,
         p_message_text => p_cres_info,
         p_inf_id       => p_inf_id
      );
      RETURN;
   END IF;

   l_ctx := ROW(
      p_lsr_id, p_inf_id, p_iyear, p_itype, p_irsn_corr, p_ireq_kind,
      p_cus_marker, p_pack_num, false
   )::mi_0008_api.run_context_t;

   CALL mi_0008_api.create_Temp_Tables();

   CALL mi_0008_api.build_Scope(l_ctx, l_scope_all, l_scope_count);
   l_ctx.scope_all := l_scope_all;

   UPDATE xxi.mi_0008_lsr SET stage_cd = 'SOURCE_CALC'
    WHERE lsr_id = p_lsr_id;

   IF p_itype IN (1, 2) AND p_ireq_kind = c_kind_sum THEN
      CALL mi_0008_api.load_Sources(l_ctx);
   END IF;

   -- Целевые финансовые режимы, уточнение данных клиента и аннулирование должны
   -- сохранять кандидатов, даже если расчёт источников не вернул сумм.
   IF NOT l_scope_all THEN
      INSERT INTO pg_temp.mi_0008_acc_tmp (s_icusnum)
      SELECT s.s_icusnum
        FROM pg_temp.mi_0008_scope_tmp AS s
       WHERE s.in_scope AND NOT s.is_excluded
      ON CONFLICT (s_icusnum) DO NOTHING;
   END IF;

   SELECT count(*) INTO l_acc_count FROM pg_temp.mi_0008_acc_tmp;

   IF l_acc_count = 0 THEN
      p_ires_code := c_result_no_data;
      p_cres_info := format('NO_DATA: candidate_scope=%s, accumulator=0',
                            l_scope_count);
      CALL mi_0008_api.finish_Run(
         l_ctx, 'COMPLETED', NULL, p_ires_code, p_cres_info
      );
      CALL MI_logger.exit_f(
         p_logger_name  => cLogger,
         p_message_text => p_cres_info,
         p_inf_id       => p_inf_id,
         p_object_id    => p_lsr_id
      );
      RETURN;
   END IF;

   ANALYZE pg_temp.mi_0008_acc_tmp;

   UPDATE xxi.mi_0008_lsr SET stage_cd = 'SANITARIUM'
    WHERE lsr_id = p_lsr_id;

   CALL mi_0008_san.resolve_Cus (
      l_ctx.lsr_id,
      l_ctx.inf_id,
      l_san_code,
      l_san_info
   );

   IF l_san_code IS DISTINCT FROM ret_OK THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#SAN_FAILED',
         p_result_info => coalesce(l_san_info, 'Sanitarium failed')
      );
   END IF;

   CALL mi_0008_api.collapse_To_Roots();

   CALL mi_0008_san.validate_Root_Cus(
      p_lsr_id       => l_ctx.lsr_id,
      p_inf_id       => l_ctx.inf_id,
      p_iyear        => l_ctx.iyear,
      p_launch_itype => l_ctx.launch_itype,
      p_irsn_corr    => l_ctx.irsn_corr,
      p_ireq_kind    => l_ctx.ireq_kind,
      p_ires_code    => l_san_code,
      p_cres_info    => l_san_info
   );

   IF l_san_code IS DISTINCT FROM ret_OK THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#ROOT_SAN_FAILED',
         p_result_info => coalesce(l_san_info, 'Root validation failed')
      );
   END IF;

   UPDATE xxi.mi_0008_lsr
      SET stage_cd = 'FINAL_WRITE'
    WHERE lsr_id = p_lsr_id;


   CALL mi_0008_api.write_Report(
      l_ctx, p_ctaxreq_id, l_req_id, l_write_code, l_write_info
   );

   IF l_write_code NOT IN (ret_Ok, c_result_no_data)
      OR (l_write_code = ret_Ok AND l_req_id IS NULL)
      OR (l_write_code <> ret_Ok AND l_req_id IS NOT NULL)
   THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#BAD_WRITE_RESULT',
         p_result_info => format('code=%s, req_id=%s', l_write_code, l_req_id)
      );
   END IF;

   p_req_id := l_req_id;
   p_ires_code := l_write_code;
   p_cres_info := l_write_info;

   CALL mi_0008_api.finish_Run(
      l_ctx, 'COMPLETED', p_req_id, p_ires_code, p_cres_info
   );

   CALL MI_logger.exit_f(
      p_logger_name  => cLogger,
      p_message_text => p_cres_info,
      p_inf_id       => p_inf_id,
      p_req_id       => p_req_id,
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
            p_req_id        => p_req_id,
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

/* Конец пакета */
;

COMMENT ON SCHEMA mi_0008_api IS
   'MI-edo. MI_0008 report preparation API 1.2.0 {$Id$}'
;



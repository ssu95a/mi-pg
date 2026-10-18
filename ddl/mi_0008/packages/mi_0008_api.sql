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

   c_reason_fns      CONSTANT numeric := 2;
   c_kind_person     CONSTANT numeric := 1;
   c_kind_sum        CONSTANT numeric := 2;

BEGIN
   RAISE DEBUG 'Package "%" - % - initialized', cPkg_Name, cVersion;
END;
$init$


/* */
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
 * Единый рабочий набор текущего запуска.
 *
 * До collapse_To_Roots:
 *   одна строка = один исходный/source клиент.
 *
 * После collapse_To_Roots:
 *   одна строка = один итоговый canonical/root клиент.
 */
CREATE PROCEDURE create_Temp_Tables( )
AS
$procedure$
   #package
   #private
BEGIN

   DROP TABLE IF EXISTS pg_temp.mi_0008_scope_tmp;
   DROP TABLE IF EXISTS pg_temp.mi_0008_acc_tmp;

   CREATE TEMPORARY TABLE mi_0008_acc_tmp
   (
      s_icusnum numeric(12) NOT NULL,

      /*
       * Scope текущего запуска.
       */
      in_scope     boolean NOT NULL DEFAULT false,
      is_requested boolean NOT NULL DEFAULT false,
      is_excluded  boolean NOT NULL DEFAULT false,
      source_seen  boolean NOT NULL DEFAULT false,

      /*
       * Финансовый accumulator.
       */
      msum_f_dep numeric(22,2),
      msum_i_dep numeric(22,2),
      msum_f_crd numeric(22,2),
      msum_i_crd numeric(22,2),
      msum_f_acc numeric(22,2),
      msum_i_acc numeric(22,2),

      /*
       * Решение Sanitarium.
       */
      r_icusnum       numeric(12),
      san_result_code varchar(50),
      san_result_info text,
      san_result_data text,

      /*
       * Последняя допустимая историческая запись.
       *
       * Суммы и person-поля истории сюда не копируются:
       * они доступны по hist_itm_id / hist_person_id.
       */
      has_primary    boolean NOT NULL DEFAULT false,
      hist_itm_id    numeric(12),
      hist_icorr     numeric(2),
      hist_inum      numeric(12),
      hist_person_id numeric(12),

      /*
       * Текущий immutable person snapshot.
       *
       * Заполняется один раз после collapse_To_Roots.
       * Эти же данные проверяет Sanitarium и позднее сохраняет mi_person.
       */
      cus_exists boolean,

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
       * Итоговые суммы будущей строки отчёта.
       */
      out_msum_f_dep numeric(22,2),
      out_msum_i_dep numeric(22,2),
      out_msum_f_crd numeric(22,2),
      out_msum_i_crd numeric(22,2),
      out_msum_f_acc numeric(22,2),
      out_msum_i_acc numeric(22,2),

      /*
       * Расчётный номер корректировки.
       * Значение 100 допустимо только как технический результат:
       * в xxi.mi_0008 оно никогда не записывается.
       */
      target_icorr numeric(3),

      /*
       * Итоговое решение по root-клиенту.
       */
      decision_code varchar(50),

      /*
       * Созданный immutable person snapshot.
       */
      person_id numeric(12),

      CONSTRAINT pk_mi_0008_acc_tmp
         PRIMARY KEY (s_icusnum)
   )
   ON COMMIT DROP;

END;
$procedure$


/*
 * Один раз формирует текущий person snapshot для итоговых root-клиентов.
 *
 * Выбранные здесь данные:
 *   - используются validate_Root_Cus;
 *   - сравниваются с историческим mi_person;
 *   - сохраняются как новый immutable mi_person snapshot.
 *
 * Повторное чтение CUS/CUS_DOCUM в дальнейших стадиях запрещено.
 */
CREATE PROCEDURE project_Current_Person()
AS
$procedure$
   #package
   #private
DECLARE
   l_projected_count bigint;
   l_updated_count   bigint;
BEGIN

   WITH person_data AS MATERIALIZED
   (
      SELECT work.s_icusnum,

             c.icusnum IS NOT NULL
                AS cus_exists,

             /*
              * Сохраняем текущее поведение write_Report:
              * обязательные ФИО получают техническое значение,
              * если в CUS они отсутствуют.
              */
             coalesce(
                c.ccusfirst_name,
                'отсутствует'
             )::varchar(50) AS first_name,

             coalesce(
                c.ccuslast_name,
                'отсутствует'
             )::varchar(50) AS last_name,

             c.ccusmiddle_name::varchar(50)
                AS middle_name,

             /*
              * Сначала гражданство из CUS,
              * затем fallback из выбранного ДУЛ.
              */
             coalesce(
                cus_country.cdigital,
                doc_country.cdigital
             )::varchar(10) AS ctzn_country_code,

             c.ccusnumnal::varchar(13)
                AS inn,

             /*
              * Preferred-документ используется, только если его тип
              * удалось распознать. Иначе выбирается действующий fallback.
              */
             coalesce(
                pref_doc.doc_type_id,
                alt_doc.doc_type_id
             ) AS doc_type_id,

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

        FROM pg_temp.mi_0008_acc_tmp AS work

        LEFT JOIN xxi."CUS" AS c
          ON c.icusnum = work.s_icusnum

        /*
         * Последний preferred ДУЛ.
         *
         * Как и в Oracle, срок действия preferred-документа здесь
         * дополнительно не проверяется.
         */
        LEFT JOIN LATERAL
        (
           SELECT CASE
                     WHEN btrim(p.cpudcode9) ~ '^[0-9]{1,3}$'
                        THEN btrim(p.cpudcode9)::numeric(3)
                     ELSE NULL::numeric(3)
                  END AS doc_type_id,

                  NULLIF(
                     btrim(p.cpudcode9),
                     ''
                  )::varchar(20) AS doc_type_code,

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

            WHERE d.icusnum = work.s_icusnum
              AND d.pref = 'Y'

            ORDER BY d.doc_date DESC NULLS LAST,
                     d.id_doc DESC

            LIMIT 1
        ) AS pref_doc
          ON true

        /*
         * Fallback — последний действующий non-preferred ДУЛ.
         */
        LEFT JOIN LATERAL
        (
           SELECT CASE
                     WHEN btrim(p.cpudcode9) ~ '^[0-9]{1,3}$'
                        THEN btrim(p.cpudcode9)::numeric(3)
                     ELSE NULL::numeric(3)
                  END AS doc_type_id,

                  NULLIF(
                     btrim(p.cpudcode9),
                     ''
                  )::varchar(20) AS doc_type_code,

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

            WHERE d.icusnum = work.s_icusnum
              AND coalesce(d.pref, 'N') = 'N'
              AND coalesce(
                     d.doc_period,
                     CURRENT_DATE
                  ) >= CURRENT_DATE

            ORDER BY d.doc_date DESC NULLS LAST,
                     d.id_doc DESC

            LIMIT 1
        ) AS alt_doc
          ON true

        LEFT JOIN LATERAL
        (
           SELECT country.cdigital
             FROM xxi.ok_sm AS country
            WHERE country.calfa_2 = c.ccuscountry1
            LIMIT 1
        ) AS cus_country
          ON true

        LEFT JOIN LATERAL
        (
           SELECT country.cdigital
             FROM xxi.ok_sm AS country
            WHERE country.calfa_3 =
                  CASE
                     WHEN pref_doc.doc_type_id IS NOT NULL
                        THEN pref_doc.doc_cnt
                     ELSE alt_doc.doc_cnt
                  END
            LIMIT 1
        ) AS doc_country
          ON true

       /*
        * После collapse здесь находятся только итоговые root-строки.
        * Повторный вызов после validation не должен переобрабатывать rejects.
        */
       WHERE work.san_result_code IS NULL
   ),
   updated AS
   (
      UPDATE pg_temp.mi_0008_acc_tmp AS work
         SET cus_exists = person.cus_exists,

             first_name        = person.first_name,
             last_name         = person.last_name,
             middle_name       = person.middle_name,
             ctzn_country_code = person.ctzn_country_code,
             inn               = person.inn,

             doc_type_id     = person.doc_type_id,
             doc_type_code   = person.doc_type_code,
             doc_ser         = person.doc_ser,
             doc_num         = person.doc_num,
             doc_issue_date  = person.doc_issue_date,
             doc_issuer_code = person.doc_issuer_code,
             doc_expire_date = person.doc_expire_date,
             doc_issuer_name = person.doc_issuer_name,

             birth_date = person.birth_date

        FROM person_data AS person

       WHERE work.s_icusnum = person.s_icusnum

      RETURNING work.s_icusnum
   )
   SELECT
      (SELECT count(*) FROM person_data),
      (SELECT count(*) FROM updated)

     INTO l_projected_count,
          l_updated_count;

   IF l_updated_count <> l_projected_count THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#PERSON_PROJECTION_CARDINALITY',
         p_result_info => format(
            'Expected %s projected persons, updated %s',
            l_projected_count,
            l_updated_count
         )
      );
   END IF;

END;
$procedure$


/*
 * Формирует итоговые суммы и расчётный icorr для каждого root-клиента.
 *
 * До вызова должны быть выполнены:
 *
 *   - project_Current_Person;
 *   - validate_Root_Cus;
 *   - prune_Rejected_Roots;
 *   - resolve_History.
 *
 * Правила:
 *
 *   cancellation:
 *      все итоговые суммы NULL, target_icorr = 99;
 *
 *   person correction:
 *      суммы копируются из последней исторической строки;
 *
 *   FNS financial correction:
 *      если явно запрошенный клиент не пришёл ни из одного источника,
 *      используются исторические суммы;
 *
 *   остальные режимы:
 *      используются текущие рассчитанные суммы;
 *
 *   primary:
 *      target_icorr = 0;
 *
 *   correction без истории:
 *      target_icorr = 0;
 *
 *   correction с историей:
 *      target_icorr = hist_icorr + 1.
 */
CREATE PROCEDURE resolve_Output_Amounts(
   IN p_ctx mi_0008_api.run_context_t
)
AS
$procedure$
   #package
   #private
DECLARE
   l_candidate_count       bigint;
   l_updated_count         bigint;
   l_missing_history_count bigint;
BEGIN

   WITH base AS MATERIALIZED
   (
      SELECT work.s_icusnum,

             work.hist_itm_id,
             work.hist_icorr,

             work.msum_f_dep,
             work.msum_i_dep,
             work.msum_f_crd,
             work.msum_i_crd,
             work.msum_f_acc,
             work.msum_i_acc,

             history.msum_f_dep AS hist_msum_f_dep,
             history.msum_i_dep AS hist_msum_i_dep,
             history.msum_f_crd AS hist_msum_f_crd,
             history.msum_i_crd AS hist_msum_i_crd,
             history.msum_f_acc AS hist_msum_f_acc,
             history.msum_i_acc AS hist_msum_i_acc,

             /*
              * Для cancellation финансовые данные всегда очищаются.
              */
             p_ctx.launch_itype = 3
                AS is_cancellation,

             /*
              * В этих режимах итоговые суммы берутся из history:
              *
              *   - любое person-уточнение;
              *   - запрос ФНС по финансовым данным, если клиент
              *     не пришёл из текущих источников.
              */
             p_ctx.launch_itype = 2
             AND
             (
                p_ctx.ireq_kind = c_kind_person

                OR

                (
                   p_ctx.ireq_kind = c_kind_sum
                   AND p_ctx.irsn_corr = c_reason_fns
                   AND work.is_requested
                   AND NOT work.source_seen
                )
             ) AS use_history,

             /*
              * hist_itm_id был получен из xxi.mi_0008.
              * Если строка внезапно исчезла, это нарушение внутреннего
              * контракта, а не нормальное отсутствие истории.
              */
             work.hist_itm_id IS NOT NULL
             AND history.itm_id IS NULL
                AS history_missing

        FROM pg_temp.mi_0008_acc_tmp AS work

        LEFT JOIN xxi.mi_0008 AS history
          ON history.itm_id = work.hist_itm_id

       /*
        * После prune_Rejected_Roots здесь обычно все строки accepted.
        * Условие оставлено как дополнительная защита контракта.
        */
       WHERE work.san_result_code IS NULL
   ),
   calculated AS MATERIALIZED
   (
      SELECT b.s_icusnum,

             CASE
                WHEN b.is_cancellation
                   THEN NULL

                WHEN b.use_history
                   THEN b.hist_msum_f_dep

                ELSE b.msum_f_dep
             END::numeric(22,2) AS out_msum_f_dep,

             CASE
                WHEN b.is_cancellation
                   THEN NULL

                WHEN b.use_history
                   THEN b.hist_msum_i_dep

                ELSE b.msum_i_dep
             END::numeric(22,2) AS out_msum_i_dep,

             CASE
                WHEN b.is_cancellation
                   THEN NULL

                WHEN b.use_history
                   THEN b.hist_msum_f_crd

                ELSE b.msum_f_crd
             END::numeric(22,2) AS out_msum_f_crd,

             CASE
                WHEN b.is_cancellation
                   THEN NULL

                WHEN b.use_history
                   THEN b.hist_msum_i_crd

                ELSE b.msum_i_crd
             END::numeric(22,2) AS out_msum_i_crd,

             CASE
                WHEN b.is_cancellation
                   THEN NULL

                WHEN b.use_history
                   THEN b.hist_msum_f_acc

                ELSE b.msum_f_acc
             END::numeric(22,2) AS out_msum_f_acc,

             CASE
                WHEN b.is_cancellation
                   THEN NULL

                WHEN b.use_history
                   THEN b.hist_msum_i_acc

                ELSE b.msum_i_acc
             END::numeric(22,2) AS out_msum_i_acc,

             CASE
                WHEN p_ctx.launch_itype = 1
                   THEN 0

                WHEN p_ctx.launch_itype = 3
                   THEN 99

                WHEN b.hist_itm_id IS NULL
                   THEN 0

                ELSE b.hist_icorr + 1
             END::numeric(3) AS target_icorr,

             b.history_missing

        FROM base AS b
   ),
   updated AS
   (
      UPDATE pg_temp.mi_0008_acc_tmp AS work
         SET out_msum_f_dep = result.out_msum_f_dep,
             out_msum_i_dep = result.out_msum_i_dep,
             out_msum_f_crd = result.out_msum_f_crd,
             out_msum_i_crd = result.out_msum_i_crd,
             out_msum_f_acc = result.out_msum_f_acc,
             out_msum_i_acc = result.out_msum_i_acc,

             target_icorr = result.target_icorr

        FROM calculated AS result

       WHERE work.s_icusnum = result.s_icusnum
         AND NOT result.history_missing

      RETURNING work.s_icusnum
   )
   SELECT
      (
         SELECT count(*)
           FROM calculated
      ),

      (
         SELECT count(*)
           FROM calculated
          WHERE history_missing
      ),

      (
         SELECT count(*)
           FROM updated
      )

     INTO l_candidate_count,
          l_missing_history_count,
          l_updated_count;

   /*
    * Ссылка на существовавшую history-строку не должна становиться битой
    * внутри того же формирования отчёта.
    */
   IF l_missing_history_count > 0 THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#HISTORY_ITEM_NOT_FOUND',
         p_result_info => format(
            'Не найдено исторических строк по hist_itm_id: %s',
            l_missing_history_count
         )
      );

   END IF;

   /*
    * Для каждого принятого root-клиента должна быть рассчитана
    * ровно одна итоговая строка сумм.
    */
   IF l_updated_count <> l_candidate_count THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#OUTPUT_CARDINALITY',
         p_result_info => format(
            'Ожидалось рассчитанных строк: %s, обновлено: %s',
            l_candidate_count,
            l_updated_count
         )
      );

   END IF;

END;
$procedure$


/*
 * Формирует область клиентов текущего запуска и расширяет её
 * по активным связям типа 17.
 *
 * Для полного primary-run p_scope_all = true:
 * рабочая таблица заранее всеми клиентами не заполняется;
 * в неё записываются только исключения.
 *
 * Для marker/correction/cancellation:
 * каждая строка области заранее создаётся в mi_0008_acc_tmp.
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

   p_scope_all :=  p_ctx.launch_itype = 1 AND p_ctx.cus_marker IS NULL;

   ---------------------------------------------------------------------------
   -- Исходные клиенты, явно заданные параметрами запуска.
   ---------------------------------------------------------------------------
   IF p_ctx.launch_itype = 1
      AND p_ctx.cus_marker IS NOT NULL
   THEN

      /*
       * Первичная пакетная обработка:
       * IDROW  — клиент;
       * IDAROW — номер пакета.
       */
      INSERT INTO pg_temp.mi_0008_acc_tmp
      (
         s_icusnum,
         in_scope,
         is_requested
      )
      SELECT DISTINCT
             m.idrow,
             true,
             true
        FROM xxi.mrk_id2 AS m
       WHERE m.idmarker = p_ctx.cus_marker
         AND m.idarow   = p_ctx.pack_num
         AND m.idrow IS NOT NULL

      ON CONFLICT (s_icusnum) DO UPDATE
         SET in_scope     = true,
             is_requested = true;

   ELSIF p_ctx.launch_itype IN (2, 3)
      AND p_ctx.cus_marker IS NOT NULL
   THEN

      /*
       * Коррекция или аннулирование:
       * IDAROW — клиент.
       */
      INSERT INTO pg_temp.mi_0008_acc_tmp
      (
         s_icusnum,
         in_scope,
         is_requested
      )
      SELECT DISTINCT
             m.idarow,
             true,
             true
        FROM xxi.mrk_id2 AS m
       WHERE m.idmarker = p_ctx.cus_marker
         AND m.idarow IS NOT NULL

      ON CONFLICT (s_icusnum) DO UPDATE
         SET in_scope     = true,
             is_requested = true;

   ELSIF p_ctx.launch_itype = 2
      AND p_ctx.cus_marker IS NULL
   THEN

      /*
       * Банковский поиск изменений.
       *
       * Для финансовой корректировки исходной областью служат клиенты,
       * имеющие допустимую первичную строку.
       *
       * Для person-коррекции подходит любая допустимая история.
       */
      INSERT INTO pg_temp.mi_0008_acc_tmp
      (
         s_icusnum,
         in_scope,
         is_requested
      )
      SELECT DISTINCT
             i.icusnum,
             true,
             true
        FROM xxi.mi_0008 AS i

        JOIN xxi.mi_req AS q
          ON q.req_id = i.req_id

       WHERE q.inf_id = p_ctx.inf_id
         AND q.status_cd IN (1, 2, 3)
         AND i.iyear = p_ctx.iyear
         AND (
                p_ctx.ireq_kind = c_kind_person
                OR i.icorr = 0
             )

      ON CONFLICT (s_icusnum) DO UPDATE
         SET in_scope     = true,
             is_requested = true;

   END IF;

   ---------------------------------------------------------------------------
   -- Расширяем ограниченную область на всю слабую компоненту relation 17.
   --
   -- Направление связи здесь игнорируется только для определения охвата.
   -- Выбор canonical/root клиента выполняет Sanitarium.
   ---------------------------------------------------------------------------
   WITH RECURSIVE walk(icusnum) AS
   (
      SELECT a.s_icusnum
        FROM pg_temp.mi_0008_acc_tmp AS a
       WHERE a.in_scope

      UNION

      SELECT CASE
                WHEN l.id_cus_parent = w.icusnum
                   THEN l.id_cus_child
                ELSE l.id_cus_parent
             END

        FROM walk AS w

        JOIN xxi.cus_lnk AS l
          ON l.id_cus_parent = w.icusnum
          OR l.id_cus_child  = w.icusnum

       WHERE l.id_lnk_type = 17
         AND (
                l.date_end IS NULL
                OR l.date_end >= CURRENT_DATE
             )
   )
   INSERT INTO pg_temp.mi_0008_acc_tmp
   (
      s_icusnum,
      in_scope
   )
   SELECT w.icusnum,
          true
     FROM walk AS w

   ON CONFLICT (s_icusnum) DO UPDATE
      SET in_scope = true;

   ---------------------------------------------------------------------------
   -- Для первичного запуска исключаем клиентов, уже представленных
   -- допустимой первичной строкой этого inf_id и года.
   ---------------------------------------------------------------------------
   IF p_ctx.launch_itype = 1 THEN

      INSERT INTO pg_temp.mi_0008_acc_tmp
      (
         s_icusnum,
         is_excluded
      )
      SELECT DISTINCT
             i.icusnum,
             true
        FROM xxi.mi_0008 AS i

        JOIN xxi.mi_req AS q
          ON q.req_id = i.req_id

       WHERE q.inf_id = p_ctx.inf_id
         AND q.status_cd IN (1, 2, 3)
         AND i.iyear = p_ctx.iyear
         AND i.icorr = 0

      ON CONFLICT (s_icusnum) DO UPDATE
         SET is_excluded = true;

      /*
       * Исключение распространяется на всю weak component:
       * child не должен повторно попасть в отчёт через уже представленный root.
       */
      WITH RECURSIVE excluded_walk(icusnum) AS
      (
         SELECT a.s_icusnum
           FROM pg_temp.mi_0008_acc_tmp AS a
          WHERE a.is_excluded

         UNION

         SELECT CASE
                   WHEN l.id_cus_parent = w.icusnum
                      THEN l.id_cus_child
                   ELSE l.id_cus_parent
                END

           FROM excluded_walk AS w

           JOIN xxi.cus_lnk AS l
             ON l.id_cus_parent = w.icusnum
             OR l.id_cus_child  = w.icusnum

          WHERE l.id_lnk_type = 17
            AND (
                   l.date_end IS NULL
                   OR l.date_end >= CURRENT_DATE
                )
      )
      INSERT INTO pg_temp.mi_0008_acc_tmp
      (
         s_icusnum,
         is_excluded
      )
      SELECT w.icusnum,
             true
        FROM excluded_walk AS w

      ON CONFLICT (s_icusnum) DO UPDATE
         SET is_excluded = true;

   END IF;

   SELECT count(*)
     INTO p_scope_count
     FROM pg_temp.mi_0008_acc_tmp AS a
    WHERE a.in_scope
      AND NOT a.is_excluded;

END;
$procedure$



/* */
CREATE PROCEDURE load_Sources(
   IN p_ctx mi_0008_api.run_context_t
)
AS
$procedure$
   #package
   #private
BEGIN

   CALL mi_0008_src.prepare_Dep(
      p_inf_id       => p_ctx.inf_id,
      p_iyear        => p_ctx.iyear,
      p_launch_itype => p_ctx.launch_itype,
      p_irsn_corr    => p_ctx.irsn_corr,
      p_cus_marker   => p_ctx.cus_marker,
      p_pack_num     => p_ctx.pack_num,
      p_scope_all    => p_ctx.scope_all
   );

   CALL mi_0008_src.prepare_Crd(
      p_inf_id       => p_ctx.inf_id,
      p_iyear        => p_ctx.iyear,
      p_launch_itype => p_ctx.launch_itype,
      p_irsn_corr    => p_ctx.irsn_corr,
      p_cus_marker   => p_ctx.cus_marker,
      p_pack_num     => p_ctx.pack_num,
      p_scope_all    => p_ctx.scope_all
   );

   CALL mi_0008_src.prepare_Acc(
      p_inf_id       => p_ctx.inf_id,
      p_iyear        => p_ctx.iyear,
      p_launch_itype => p_ctx.launch_itype,
      p_irsn_corr    => p_ctx.irsn_corr,
      p_cus_marker   => p_ctx.cus_marker,
      p_pack_num     => p_ctx.pack_num,
      p_scope_all    => p_ctx.scope_all
   );

END;
$procedure$


/* */
CREATE PROCEDURE prune_Excluded()
AS
$procedure$
   #package
   #private
BEGIN

   DELETE
     FROM pg_temp.mi_0008_acc_tmp
    WHERE 
          is_excluded;
END;
$procedure$


/*
 * Принятые строки источников сворачиваются к canonical/root клиентам
 * в том же рабочем наборе.
 *
 * До процедуры:
 *   одна строка = один source CUS.
 *
 * После процедуры:
 *   одна строка = один canonical/root CUS.
 *
 * Это единственное место, где допускается сложение сумм
 * разных клиентов.
 */
CREATE PROCEDURE collapse_To_Roots()
AS
$procedure$
   #package
   #private
BEGIN

   INSERT INTO pg_temp.mi_0008_acc_tmp AS work
   (
      s_icusnum,

      in_scope,
      is_requested,
      is_excluded,
      source_seen,

      msum_f_dep,
      msum_i_dep,
      msum_f_crd,
      msum_i_crd,
      msum_f_acc,
      msum_i_acc,

      r_icusnum,
      san_result_code,
      san_result_info,
      san_result_data
   )
   SELECT coalesce( a.r_icusnum, a.s_icusnum ) AS root_icusnum,

          bool_or(a.in_scope),
          bool_or(a.is_requested),
          false,
          bool_or(a.source_seen),

          NULLIF(
             sum(a.msum_f_dep),
             0
          )::numeric(22,2),

          NULLIF(
             sum(a.msum_i_dep),
             0
          )::numeric(22,2),

          NULLIF(
             sum(a.msum_f_crd),
             0
          )::numeric(22,2),

          NULLIF(
             sum(a.msum_i_crd),
             0
          )::numeric(22,2),

          NULLIF(
             sum(a.msum_f_acc),
             0
          )::numeric(22,2),

          NULLIF(
             sum(a.msum_i_acc),
             0
          )::numeric(22,2),

          /*
           * После collapse строка уже является root-строкой.
           * Предыдущее graph-решение ей больше не требуется.
           */
          NULL::numeric,
          NULL::varchar,
          NULL::text,
          NULL::text

     FROM pg_temp.mi_0008_acc_tmp AS a

    WHERE a.san_result_code IS NULL
       OR a.san_result_code = 'CUS_MAP'
    GROUP BY coalesce( a.r_icusnum, a.s_icusnum )

       ON CONFLICT (s_icusnum) 
       DO UPDATE
      SET in_scope     = EXCLUDED.in_scope,
          is_requested = EXCLUDED.is_requested,
          is_excluded  = false,
          source_seen  = EXCLUDED.source_seen,

          msum_f_dep = EXCLUDED.msum_f_dep,
          msum_i_dep = EXCLUDED.msum_i_dep,
          msum_f_crd = EXCLUDED.msum_f_crd,
          msum_i_crd = EXCLUDED.msum_i_crd,
          msum_f_acc = EXCLUDED.msum_f_acc,
          msum_i_acc = EXCLUDED.msum_i_acc,

          r_icusnum       = NULL,
          san_result_code = NULL,
          san_result_info = NULL,
          san_result_data = NULL;

   /*
    * К этому моменту:
    *
    *   - root-строки созданы или обновлены;
    *   - CUS_MAP children уже включены в суммы root;
    *   - graph rejects уже сохранены в mi_0008_lsr_itm.
    *
    * Поэтому все special source-строки удаляются.
    */
   DELETE
     FROM pg_temp.mi_0008_acc_tmp
    WHERE 
          san_result_code IS NOT NULL;

END;
$procedure$


/*
 * Находит последнюю допустимую историю для каждого итогового клиента.
 *
 * History определяется по:
 *   - тому же inf_id;
 *   - тому же отчётному году;
 *   - status_cd IN (1, 2, 3).
 *
 * Latest выбирается по фактическому порядку создания request/item,
 * а не через MAX(icorr).
 */
CREATE PROCEDURE resolve_History(
   IN p_ctx mi_0008_api.run_context_t
)
AS
$procedure$
   #package
   #private
BEGIN

   /*
    * Процедура должна быть идемпотентной внутри одной сессии:
    * повторный вызов полностью заменяет результат history resolution.
    */
   UPDATE pg_temp.mi_0008_acc_tmp
      SET has_primary    = false,
          hist_itm_id    = NULL,
          hist_icorr     = NULL,
          hist_inum      = NULL,
          hist_person_id = NULL;


   WITH latest AS MATERIALIZED
   (
      SELECT DISTINCT ON (work.s_icusnum)
             work.s_icusnum,

             bool_or(item.icorr = 0)
                OVER (
                   PARTITION BY work.s_icusnum
                ) AS has_primary,

             item.itm_id,
             item.icorr,
             item.inum,
             item.person_id

        FROM pg_temp.mi_0008_acc_tmp AS work

        JOIN xxi.mi_0008 AS item
          ON item.icusnum = work.s_icusnum
         AND item.iyear   = p_ctx.iyear

        JOIN xxi.mi_req AS request
          ON request.req_id = item.req_id
         AND request.inf_id = p_ctx.inf_id
         AND request.status_cd IN (1, 2, 3)

       ORDER BY work.s_icusnum,
                request.created_at DESC,
                request.req_id DESC,
                item.itm_id DESC
   )
   UPDATE pg_temp.mi_0008_acc_tmp AS work
      SET has_primary    = history.has_primary,
          hist_itm_id    = history.itm_id,
          hist_icorr     = history.icorr,
          hist_inum      = history.inum,
          hist_person_id = history.person_id

     FROM latest AS history

    WHERE work.s_icusnum = history.s_icusnum;

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
 * Определяет итоговое действие по каждому принятому root-клиенту.
 *
 * До вызова должны быть выполнены:
 *
 *   - resolve_History;
 *   - resolve_Output_Amounts.
 *
 * Текущие person-данные уже находятся в mi_0008_acc_tmp.
 * Исторические суммы и person snapshot читаются по сохранённым ссылкам.
 *
 * Процедура не создаёт request, person или строки отчёта.
 */
CREATE PROCEDURE resolve_Decisions(
   IN p_ctx mi_0008_api.run_context_t
)
AS
$procedure$
   #package
   #private
DECLARE
   l_candidate_count bigint;
   l_updated_count   bigint;
BEGIN

   /*
    * Повторный вызов полностью пересчитывает решения.
    */
   UPDATE pg_temp.mi_0008_acc_tmp
      SET decision_code = NULL;

   WITH facts AS MATERIALIZED
   (
      SELECT work.s_icusnum,

             work.has_primary,
             work.hist_itm_id,
             work.hist_icorr,
             work.target_icorr,

             /*
              * Итоговые суммы уже рассчитаны
              * resolve_Output_Amounts.
              */
             work.out_msum_f_dep,
             work.out_msum_i_dep,
             work.out_msum_f_crd,
             work.out_msum_i_crd,
             work.out_msum_f_acc,
             work.out_msum_i_acc,

             /*
              * Общая сумма нужна только для проверки
              * неположительного финансового результата.
              */
               coalesce(work.out_msum_f_dep, 0)
             + coalesce(work.out_msum_i_dep, 0)
             + coalesce(work.out_msum_f_crd, 0)
             + coalesce(work.out_msum_i_crd, 0)
             + coalesce(work.out_msum_f_acc, 0)
             + coalesce(work.out_msum_i_acc, 0)
                AS financial_total,

             /*
              * NULL-safe сравнение всех шести сумм.
              */
             work.out_msum_f_dep
                IS NOT DISTINCT FROM history.msum_f_dep

             AND work.out_msum_i_dep
                IS NOT DISTINCT FROM history.msum_i_dep

             AND work.out_msum_f_crd
                IS NOT DISTINCT FROM history.msum_f_crd

             AND work.out_msum_i_crd
                IS NOT DISTINCT FROM history.msum_i_crd

             AND work.out_msum_f_acc
                IS NOT DISTINCT FROM history.msum_f_acc

             AND work.out_msum_i_acc
                IS NOT DISTINCT FROM history.msum_i_acc

                AS financial_unchanged,

             /*
              * Oracle-набор полей для определения изменения person.
              *
              * Расширенные поля документа здесь намеренно
              * не участвуют.
              */
             work.first_name
                IS NOT DISTINCT FROM old_person.first_name

             AND work.last_name
                IS NOT DISTINCT FROM old_person.last_name

             AND work.middle_name
                IS NOT DISTINCT FROM old_person.middle_name

             AND work.ctzn_country_code
                IS NOT DISTINCT FROM old_person.ctzn_country_code

             AND work.birth_date
                IS NOT DISTINCT FROM old_person.birth_date

             AND work.inn
                IS NOT DISTINCT FROM old_person.inn

             AND work.doc_type_id
                IS NOT DISTINCT FROM old_person.doc_type_id

             AND work.doc_ser
                IS NOT DISTINCT FROM old_person.doc_ser

             AND work.doc_num
                IS NOT DISTINCT FROM old_person.doc_num

             AND work.doc_issue_date
                IS NOT DISTINCT FROM old_person.doc_issue_date

                AS person_unchanged

        FROM pg_temp.mi_0008_acc_tmp AS work

        LEFT JOIN xxi.mi_0008 AS history
          ON history.itm_id = work.hist_itm_id

        LEFT JOIN xxi.mi_person AS old_person
          ON old_person.person_id = work.hist_person_id

       WHERE work.san_result_code IS NULL
   ),
   decisions AS MATERIALIZED
   (
      SELECT facts.s_icusnum,

             CASE
                /*
                 * Аннулирование является terminal state.
                 */
                WHEN facts.hist_icorr = 99
                   THEN 'ICORR_AFTER_CANCEL'

                /*
                 * Повторная primary-строка для того же
                 * inf_id и года не создаётся.
                 */
                WHEN p_ctx.launch_itype = 1
                 AND facts.has_primary
                   THEN 'ALREADY_PRIMARY'

                /*
                 * Person correction невозможна без истории.
                 */
                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_person
                 AND facts.hist_itm_id IS NULL
                   THEN 'PERSON_NO_HISTORY'

                /*
                 * Обычные corrections не используют
                 * зарезервированные icorr 98 и 99.
                 *
                 * Явное cancellation может сформировать 99
                 * после legacy icorr=98.
                 */
                WHEN p_ctx.launch_itype = 2
                 AND facts.hist_icorr IN (97, 98)
                   THEN 'ICORR_EXHAUSTED'

                /*
                 * Неположительная сумма не превращается
                 * автоматически в cancellation.
                 */
                WHEN p_ctx.launch_itype IN (1, 2)
                 AND p_ctx.ireq_kind = c_kind_sum
                 AND facts.financial_total <= 0
                   THEN 'NONPOSITIVE_TOTAL'

                /*
                 * Банк не создаёт финансовую correction,
                 * если суммы не изменились.
                 *
                 * Для ФНС строка создаётся даже без изменений.
                 */
                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_sum
                 AND p_ctx.irsn_corr <> c_reason_fns
                 AND facts.hist_itm_id IS NOT NULL
                 AND facts.financial_unchanged
                   THEN 'UNCHANGED_FINANCIAL'

                /*
                 * Банк не создаёт person correction,
                 * если значимые person-поля не изменились.
                 *
                 * Для ФНС строка создаётся даже без изменений.
                 */
                WHEN p_ctx.launch_itype = 2
                 AND p_ctx.ireq_kind = c_kind_person
                 AND p_ctx.irsn_corr <> c_reason_fns
                 AND facts.person_unchanged
                   THEN 'UNCHANGED_PERSON'

                /*
                 * Физический unique-key таблицы не содержит inf_id,
                 * поэтому проверяется вся xxi.mi_0008.
                 */
                WHEN EXISTS
                     (
                        SELECT 1
                          FROM xxi.mi_0008 AS occupied
                         WHERE occupied.icusnum =
                               facts.s_icusnum

                           AND occupied.iyear =
                               p_ctx.iyear

                           AND occupied.icorr =
                               facts.target_icorr
                     )
                   THEN 'ITEM_KEY_EXISTS'

                ELSE 'EMIT'
             END::varchar(50) AS decision_code

        FROM facts
   ),
   updated AS
   (
      UPDATE pg_temp.mi_0008_acc_tmp AS work
         SET decision_code = decision.decision_code

        FROM decisions AS decision

       WHERE work.s_icusnum = decision.s_icusnum

      RETURNING work.s_icusnum
   )
   SELECT
      (
         SELECT count(*)
           FROM decisions
      ),

      (
         SELECT count(*)
           FROM updated
      )

     INTO l_candidate_count,
          l_updated_count;

   IF l_updated_count <> l_candidate_count THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#DECISION_CARDINALITY',
         p_result_info => format(
            'Ожидалось решений: %s, обновлено: %s',
            l_candidate_count,
            l_updated_count
         )
      );

   END IF;

END;
$procedure$


/*
 * Сохраняет исключительные результаты final-decision в протокол LSR.
 *
 * Обычные business-skips:
 *
 *   - ALREADY_PRIMARY;
 *   - NONPOSITIVE_TOTAL;
 *   - UNCHANGED_FINANCIAL;
 *   - UNCHANGED_PERSON;
 *
 * в mi_0008_lsr_itm не записываются.
 *
 * Процедура не изменяет рабочий набор и возвращает:
 *
 *   p_diag_count       — общее количество сохранённых диагностик;
 *   p_icorr_diag_count — количество диагностик границы icorr.
 */
CREATE PROCEDURE persist_Decision_Diagnostics(
   IN  p_ctx                mi_0008_api.run_context_t,
   OUT p_diag_count         bigint,
   OUT p_icorr_diag_count   bigint
)
AS
$procedure$
   #package
   #private
DECLARE
   l_written_count bigint;
BEGIN

   p_diag_count       := 0;
   p_icorr_diag_count := 0;
   l_written_count    := 0;

   WITH diagnostics AS MATERIALIZED
   (
      SELECT work.s_icusnum,

             work.decision_code
                AS result_code,

             CASE work.decision_code

                WHEN 'ICORR_EXHAUSTED' THEN
                   format(
                      'Обычная коррекция после icorr=%s попадает в зарезервированный диапазон',
                      work.hist_icorr
                   )

                WHEN 'ICORR_AFTER_CANCEL' THEN
                   'Последняя допустимая историческая строка является аннулированием icorr=99'

                WHEN 'PERSON_NO_HISTORY' THEN
                   'Для уточнения сведений о физическом лице отсутствует допустимая историческая строка'

                WHEN 'ITEM_KEY_EXISTS' THEN
                   format(
                      'Итоговый ключ строки уже существует: год=%s, icorr=%s',
                      p_ctx.iyear,
                      work.target_icorr
                   )

                ELSE
                   work.decision_code
             END AS result_info,

             jsonb_strip_nulls(
                jsonb_build_object(
                   'history_itm_id',
                   work.hist_itm_id,

                   'history_icorr',
                   work.hist_icorr,

                   'target_icorr',
                   work.target_icorr
                )
             )::text AS result_data

        FROM pg_temp.mi_0008_acc_tmp AS work

       WHERE work.decision_code IN
             (
                'ICORR_EXHAUSTED',
                'ICORR_AFTER_CANCEL',
                'PERSON_NO_HISTORY',
                'ITEM_KEY_EXISTS'
             )
   ),
   written AS
   (
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
             diag.s_icusnum,
             diag.s_icusnum,
             diag.result_code,
             diag.result_info,
             diag.result_data

        FROM diagnostics AS diag

      ON CONFLICT (lsr_id, s_icusnum) DO UPDATE
         SET r_icusnum   = EXCLUDED.r_icusnum,
             result_code = EXCLUDED.result_code,
             result_info = EXCLUDED.result_info,
             result_data = EXCLUDED.result_data

      RETURNING 1
   )
   SELECT count(*),

          count(*) FILTER
          (
             WHERE diag.result_code IN
                   (
                      'ICORR_EXHAUSTED',
                      'ICORR_AFTER_CANCEL'
                   )
          ),

          (
             SELECT count(*)
               FROM written
          )

     INTO p_diag_count,
          p_icorr_diag_count,
          l_written_count

     FROM diagnostics AS diag;

   /*
    * INSERT и ON CONFLICT DO UPDATE должны обработать
    * ровно одну строку на каждую диагностику.
    */
   IF l_written_count <> p_diag_count THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#DIAGNOSTIC_CARDINALITY',
         p_result_info => format(
            'Ожидалось диагностических записей: %s, сохранено: %s',
            p_diag_count,
            l_written_count
         )
      );

   END IF;

END;
$procedure$


/*
 * Создаёт immutable mi_person snapshots для строк с решением EMIT
 * и связывает их с фактическим inf_id запуска.
 *
 * До вызова должны быть выполнены:
 *
 *   - project_Current_Person;
 *   - resolve_Decisions.
 *
 * Процедура:
 *
 *   - не перечитывает CUS/CUS_DOCUM;
 *   - не переиспользует существующие mi_person;
 *   - создаёт ровно один новый snapshot на одну строку EMIT;
 *   - записывает созданный person_id обратно в mi_0008_acc_tmp;
 *   - создаёт связь person/inf в xxi.mi_p2i.
 *
 * Повторный вызов в рамках одного запуска запрещён:
 * immutable snapshots не должны дублироваться.
 */
CREATE PROCEDURE create_Person_Snapshots(
   IN  p_ctx            mi_0008_api.run_context_t,
   OUT p_person_count   bigint,
   OUT p_linked_count   bigint
)
AS
$procedure$
   #package
   #private
DECLARE
   l_emit_count          bigint;
   l_existing_count      bigint;
   l_missing_person_count bigint;
BEGIN

   p_person_count := 0;
   p_linked_count := 0;

   SELECT count(*),

          count(*) FILTER
          (
             WHERE work.person_id IS NOT NULL
          )

     INTO l_emit_count,
          l_existing_count

     FROM pg_temp.mi_0008_acc_tmp AS work

    WHERE work.decision_code = 'EMIT';

   /*
    * Пустой набор — нормальный результат.
    * Request в этом случае оркестратор не создаёт.
    */
   IF l_emit_count = 0 THEN
      RETURN;
   END IF;

   /*
    * Защита от случайного повторного вызова:
    * второй immutable snapshot создавать нельзя.
    */
   IF l_existing_count > 0 THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#PERSON_ALREADY_CREATED',
         p_result_info => format(
            'Для %s строк EMIT уже задан person_id',
            l_existing_count
         )
      );

   END IF;

   /*
    * Создаём новый snapshot для каждой строки EMIT.
    *
    * RETURNING icusnum используется только как ключ обратного
    * сопоставления с одной root-строкой рабочего набора.
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
      SELECT work.s_icusnum,

             work.first_name,
             work.last_name,
             work.middle_name,

             work.ctzn_country_code,
             work.inn,

             work.doc_type_id,
             work.doc_type_code,
             work.doc_ser,
             work.doc_num,
             work.doc_issue_date,
             work.doc_issuer_code,
             work.doc_expire_date,
             work.doc_issuer_name,

             work.birth_date

        FROM pg_temp.mi_0008_acc_tmp AS work

       WHERE work.decision_code = 'EMIT'

      RETURNING person_id,
                icusnum
   )
   UPDATE pg_temp.mi_0008_acc_tmp AS work
      SET person_id = person.person_id

     FROM inserted_person AS person

    WHERE work.s_icusnum = person.icusnum
      AND work.decision_code = 'EMIT';

   GET DIAGNOSTICS p_person_count = ROW_COUNT;

   /*
    * На каждую EMIT-строку должен быть создан и сопоставлен
    * ровно один immutable snapshot.
    */
   IF p_person_count <> l_emit_count THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#PERSON_CARDINALITY',
         p_result_info => format(
            'Ожидалось снимков физического лица: %s, создано: %s',
            l_emit_count,
            p_person_count
         )
      );

   END IF;

   /*
    * Дополнительная проверка результата UPDATE:
    * EMIT без person_id дальше записываться не может.
    */
   SELECT count(*)
     INTO l_missing_person_count
     FROM pg_temp.mi_0008_acc_tmp AS work
    WHERE work.decision_code = 'EMIT'
      AND work.person_id IS NULL;

   IF l_missing_person_count > 0 THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#PERSON_ID_MISSING',
         p_result_info => format(
            'После создания snapshots отсутствует person_id для %s строк EMIT',
            l_missing_person_count
         )
      );

   END IF;

   /*
    * Новый snapshot связывается с видом сведений,
    * для которого выполняется текущий запуск.
    */
   INSERT INTO xxi.mi_p2i
   (
      person_id,
      inf_id
   )
   SELECT work.person_id,
          p_ctx.inf_id

     FROM pg_temp.mi_0008_acc_tmp AS work

    WHERE work.decision_code = 'EMIT'

   ON CONFLICT (person_id, inf_id) DO NOTHING;

   GET DIAGNOSTICS p_linked_count = ROW_COUNT;

   /*
    * Person IDs только что созданы, поэтому конфликт здесь
    * означает нарушение внутреннего контракта.
    */
   IF p_linked_count <> l_emit_count THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#PERSON_LINK_CARDINALITY',
         p_result_info => format(
            'Ожидалось связей person/inf: %s, создано: %s',
            l_emit_count,
            p_linked_count
         )
      );

   END IF;

END;
$procedure$


/*
 * Записывает итоговые строки MI_0008 из единого рабочего набора.
 *
 * До вызова должны быть выполнены:
 *
 *   - resolve_History;
 *   - resolve_Output_Amounts;
 *   - resolve_Decisions;
 *   - create_Person_Snapshots.
 *
 * Процедура:
 *
 *   - обрабатывает только decision_code = 'EMIT';
 *   - не принимает бизнес-решений;
 *   - не создаёт request;
 *   - не создаёт mi_person;
 *   - сохраняет historical inum либо создаёт новый;
 *   - проверяет cardinality итоговой вставки.
 */
CREATE PROCEDURE write_Items(
   IN  p_ctx             mi_0008_api.run_context_t,
   IN  p_req_id          numeric,
   OUT p_written_count   bigint
)
AS
$procedure$
   #package
   #private
DECLARE
   l_emit_count    bigint;
   l_invalid_count bigint;
BEGIN

   p_written_count := 0;

   IF p_req_id IS NULL THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#REQUEST_ID_REQUIRED',
         p_result_info => 'Для записи строк MI_0008 не задан req_id'
      );

   END IF;

   /*
    * Проверяем готовность всех строк EMIT.
    *
    * target_icorr=100 может существовать только как промежуточный
    * расчётный результат и никогда не должен попасть в xxi.mi_0008.
    */
   SELECT count(*) FILTER
          (
             WHERE work.decision_code = 'EMIT'
          ),

          count(*) FILTER
          (
             WHERE work.decision_code = 'EMIT'
               AND
               (
                  work.person_id IS NULL

                  OR work.target_icorr IS NULL

                  OR work.target_icorr NOT BETWEEN 0 AND 99
               )
          )

     INTO l_emit_count,
          l_invalid_count

     FROM pg_temp.mi_0008_acc_tmp AS work;

   /*
    * write_Items вызывается только после проверки emit_count
    * и создания заголовка запроса.
    */
   IF l_emit_count = 0 THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#NO_ITEMS_TO_WRITE',
         p_result_info => format(
            'Для req_id=%s отсутствуют строки EMIT',
            p_req_id
         )
      );

   END IF;

   IF l_invalid_count > 0 THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#ITEM_NOT_READY',
         p_result_info => format(
            'Не готовы к записи строки EMIT: %s',
            l_invalid_count
         )
      );

   END IF;

   /*
    * Для correction/cancellation сохраняется historical inum.
    *
    * Если истории нет, создаётся новый inum. COALESCE вычисляет
    * nextval только для строк с hist_inum IS NULL.
    *
    * Возможный конфликт физического ключа не подавляется:
    * unique constraint должен остановить весь запуск, если между
    * resolve_Decisions и INSERT ключ оказался занят.
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
          work.s_icusnum,
          p_ctx.iyear,
          work.target_icorr,

          coalesce(
             work.hist_inum,
             nextval('xxi.s_mi_0008__inum')
          ),

          work.person_id,

          work.out_msum_f_dep,
          work.out_msum_i_dep,
          work.out_msum_f_crd,
          work.out_msum_i_crd,
          work.out_msum_f_acc,
          work.out_msum_i_acc

     FROM pg_temp.mi_0008_acc_tmp AS work

    WHERE work.decision_code = 'EMIT';

   GET DIAGNOSTICS p_written_count = ROW_COUNT;

   IF p_written_count <> l_emit_count THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#WRITE_CARDINALITY',
         p_result_info => format(
            'Ожидалось строк отчёта: %s, записано: %s',
            l_emit_count,
            p_written_count
         )
      );

   END IF;

END;
$procedure$


/*
 * Финальный persistence-конвейер MI_0008.
 *
 * До вызова должны быть выполнены:
 *
 *   - project_Current_Person;
 *   - validate_Root_Cus;
 *   - prune_Rejected_Roots;
 *   - resolve_History;
 *   - resolve_Output_Amounts;
 *   - resolve_Decisions.
 *
 * Процедура:
 *
 *   - не читает CUS/CUS_DOCUM;
 *   - не перечитывает историю;
 *   - не пересчитывает суммы;
 *   - не принимает повторно business-решения;
 *   - не создаёт дополнительные временные таблицы;
 *   - создаёт request только при наличии строк EMIT;
 *   - создаёт immutable person snapshots;
 *   - записывает итоговые строки MI_0008.
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
   l_candidate_count   bigint := 0;
   l_emit_count        bigint := 0;
   l_unchanged_count   bigint := 0;
   l_unresolved_count  bigint := 0;

   l_diag_count        bigint := 0;
   l_icorr_diag_count  bigint := 0;
   l_san_reject_count  bigint := 0;

   l_person_count      bigint := 0;
   l_linked_count      bigint := 0;
   l_written_count     bigint := 0;
BEGIN

   p_req_id    := NULL;
   p_ires_code := c_result_no_data;
   p_cres_info := NULL;

   /*
    * Решения уже сформированы resolve_Decisions.
    *
    * Здесь только собирается итоговая статистика и проверяется,
    * что для каждой принятой root-строки решение действительно принято.
    */
   SELECT count(*),

          count(*) FILTER
          (
             WHERE work.decision_code = 'EMIT'
          ),

          count(*) FILTER
          (
             WHERE work.decision_code IN
                   (
                      'UNCHANGED_FINANCIAL',
                      'UNCHANGED_PERSON'
                   )
          ),

          count(*) FILTER
          (
             WHERE work.decision_code IS NULL
          )

     INTO l_candidate_count,
          l_emit_count,
          l_unchanged_count,
          l_unresolved_count

     FROM pg_temp.mi_0008_acc_tmp AS work;

   /*
    * Ни одна принятая root-строка не должна дойти до persistence
    * без результата resolve_Decisions.
    */
   IF l_unresolved_count > 0 THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#DECISION_NOT_RESOLVED',
         p_result_info => format(
            'Отсутствует итоговое решение для %s root-клиентов',
            l_unresolved_count
         )
      );

   END IF;

   /*
    * Сохраняем только редкие final-decision diagnostics:
    *
    *   ICORR_EXHAUSTED;
    *   ICORR_AFTER_CANCEL;
    *   PERSON_NO_HISTORY;
    *   ITEM_KEY_EXISTS.
    */
   CALL mi_0008_api.persist_Decision_Diagnostics(
      p_ctx              => p_ctx,
      p_diag_count       => l_diag_count,
      p_icorr_diag_count => l_icorr_diag_count
   );

   /*
    * В статистику входят все отклонения Sanitarium:
    *
    *   - graph rejects;
    *   - отсутствующий CUS;
    *   - некорректный ИНН;
    *   - отсутствующие дата рождения или ДУЛ;
    *   - ДУЛ после отчётного периода.
    *
    * CUS_MAP не начинается с SAN и сюда не входит.
    */
   SELECT count(*)
     INTO l_san_reject_count
     FROM xxi.mi_0008_lsr_itm AS item
    WHERE item.lsr_id = p_ctx.lsr_id
      AND item.result_code LIKE 'SAN%';

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
    * Пустой request не создаём.
    *
    * Все diagnostics уже сохранены, поэтому NO_DATA не теряет
    * информацию о причинах исключения клиентов.
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
    * Заголовок создаётся только после подтверждения наличия строк EMIT.
    *
    * Общий report-level itype для MI_0008 не используется:
    * тип каждой строки определяется через icorr.
    */
   p_req_id := MI_Request_Api.create_Request(
      p_inf_id     => p_ctx.inf_id,
      p_ctaxreq_id => NULLIF(
                         btrim(p_ctaxreq_id),
                         ''
                      ),
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
    * Создаём один immutable mi_person snapshot на каждую строку EMIT
    * и связываем его с фактическим inf_id запуска.
    */
   CALL mi_0008_api.create_Person_Snapshots(
      p_ctx          => p_ctx,
      p_person_count => l_person_count,
      p_linked_count => l_linked_count
   );

   /*
    * Записываем готовые строки отчёта непосредственно из acc_tmp.
    */
   CALL mi_0008_api.write_Items(
      p_ctx           => p_ctx,
      p_req_id        => p_req_id,
      p_written_count => l_written_count
   );

   /*
    * Дополнительная финальная защита.
    *
    * create_Person_Snapshots и write_Items уже проверяют собственную
    * cardinality, но итоговый оркестратор также фиксирует общий контракт.
    */
   IF l_person_count <> l_emit_count
      OR l_linked_count <> l_emit_count
      OR l_written_count <> l_emit_count
   THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_API#FINAL_CARDINALITY',
         p_result_info => format(
            'EMIT=%s, persons=%s, person_links=%s, items=%s',
            l_emit_count,
            l_person_count,
            l_linked_count,
            l_written_count
         )
      );

   END IF;

   p_ires_code := ret_OK;

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


/* */
CREATE PROCEDURE prune_Rejected_Roots()
AS
$procedure$
   #package
   #private
BEGIN

   DELETE
     FROM pg_temp.mi_0008_acc_tmp
    WHERE san_result_code IS NOT NULL;

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

   /*
    * Person correction и cancellation не запускают источники,
    * но их кандидаты уже были созданы build_Scope.
    */
   CALL mi_0008_api.prune_Excluded( );


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

   CALL mi_0008_api.project_Current_Person();

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

   CALL mi_0008_api.prune_Rejected_Roots();

   CALL mi_0008_api.resolve_History(
      p_ctx => l_ctx
   );

   CALL mi_0008_api.resolve_Output_Amounts(
      p_ctx => l_ctx
   );

   CALL mi_0008_api.resolve_Decisions(
      p_ctx => l_ctx
   );

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



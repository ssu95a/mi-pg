--
-- Пакет      : mi_0008_src
-- Назначение : подготовка исходных расчётных данных для MI_0008
-- Версия     : 0.1.0
--
-- В текущей версии процедуры являются заглушками: они создают пустые
-- сессионные таблицы с контрактной структурой. Расчёт и заполнение таблиц
-- должны быть реализованы внутри соответствующих процедур prepare_*.
--
CREATE OR REPLACE PACKAGE mi_0008_src

CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
   #export off
DECLARE
   cVersion  CONSTANT varchar(100) := '0.1.0';
   cPkg_Name CONSTANT varchar(20)  := 'mi_0008_src';
BEGIN
   RAISE DEBUG 'Package "%" - % - initialized', cPkg_Name, cVersion;
END;
$init$


/* Версия пакета. */
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
 * Подготавливает данные по депозитам.
 *
 * Процедура всегда заменяет снимок текущей сессии и создаёт таблицу даже при
 * отсутствии данных. В заглушке таблица остаётся пустой.
 */
CREATE PROCEDURE prepare_Dep(
   IN p_inf_id       numeric,
   IN p_iyear        numeric,
   IN p_launch_itype numeric,
   IN p_irsn_corr    numeric,
   IN p_cus_marker   numeric,
   IN p_pack_num     numeric,
   IN p_scope_all    boolean
)
AS
$procedure$
   #package
BEGIN

   INSERT INTO pg_temp.mi_0008_acc_tmp AS work
   (
      s_icusnum,
      in_scope,
      source_seen,
      msum_f_dep,
      msum_i_dep
   )
   SELECT d.icusnum,
          true,
          true,

          NULLIF(
             sum(d.sumprocfizonly),
             0
          )::numeric(22,2),

          NULLIF(
             sum(d.sumprocind),
             0
          )::numeric(22,2)

     FROM dj_v_prc_to_Client AS d

     LEFT JOIN pg_temp.mi_0008_acc_tmp AS scope
       ON scope.s_icusnum = d.icusnum

    WHERE d.icusnum IS NOT NULL

      AND (
             d.year IS NULL
             OR d.year = p_iyear
          )

      AND CASE
             WHEN p_scope_all THEN
                NOT coalesce(scope.is_excluded, false)

             ELSE
                coalesce(scope.in_scope, false)
                AND NOT coalesce(scope.is_excluded, false)
          END

    GROUP BY d.icusnum

   HAVING count(d.sumprocfizonly) > 0
       OR count(d.sumprocind) > 0

   ON CONFLICT (s_icusnum) DO UPDATE
      SET in_scope    = true,
          source_seen = true,

          msum_f_dep = EXCLUDED.msum_f_dep,
          msum_i_dep = EXCLUDED.msum_i_dep;

END;
$procedure$


/*
 * Подготавливает данные CRD и сразу записывает агрегированный
 * результат в единый рабочий набор MI_0008.
 *
 * CRD владеет только:
 *   msum_f_crd — доход физического лица, source itype = 1;
 *   msum_i_crd — доход индивидуального предпринимателя, itype = 2.
 *
 * Сырые строки и промежуточная source-table не создаются.
 */
CREATE PROCEDURE prepare_Crd(
   IN p_inf_id       numeric,
   IN p_iyear        numeric,
   IN p_launch_itype numeric,
   IN p_irsn_corr    numeric,
   IN p_cus_marker   numeric,
   IN p_pack_num     numeric,
   IN p_scope_all    boolean
)
AS
$procedure$
   #package
BEGIN

   INSERT INTO pg_temp.mi_0008_acc_tmp AS work
   (
      s_icusnum,

      in_scope,
      source_seen,

      msum_f_crd,
      msum_i_crd
   )
   SELECT src.icusnum,
          true,
          true,

          /*
           * itype в SM_008_ED_TMP — тип суммы источника,
           * а не режим формирования отчёта.
           */
          NULLIF(
             sum(src.msum) FILTER (
                WHERE src.itype = 1
             ),
             0
          )::numeric(22,2) AS msum_f_crd,

          NULLIF(
             sum(src.msum) FILTER (
                WHERE src.itype = 2
             ),
             0
          )::numeric(22,2) AS msum_i_crd

     FROM sm_008_ed_tmp AS src

     LEFT JOIN pg_temp.mi_0008_acc_tmp AS scope
       ON scope.s_icusnum = src.icusnum

    WHERE src.icusnum IS NOT NULL
      AND src.itype IN (1, 2)
      AND src.msum IS NOT NULL

      /*
       * Полный запуск:
       *   отсутствие строки в work означает обычного нового клиента;
       *   ранее помеченные исключения не загружаются.
       *
       * Ограниченный запуск:
       *   берём только клиентов рассчитанного scope.
       */
      AND CASE
             WHEN p_scope_all THEN
                NOT coalesce(
                   scope.is_excluded,
                   false
                )

             ELSE
                coalesce(
                   scope.in_scope,
                   false
                )
                AND NOT coalesce(
                   scope.is_excluded,
                   false
                )
          END

    GROUP BY src.icusnum

   /*
    * После WHERE src.msum IS NOT NULL условие обычно истинно,
    * но явно фиксирует контракт: пустой contribution строку не создаёт.
    */
   HAVING count(src.msum) > 0

   ON CONFLICT (s_icusnum) DO UPDATE
      SET in_scope    = true,
          source_seen = true,

          /*
           * Повторная подготовка заменяет snapshot CRD.
           * Значения не складываются с предыдущим результатом.
           *
           * DEP/ACC-колонки процедура не изменяет.
           */
          msum_f_crd = EXCLUDED.msum_f_crd,
          msum_i_crd = EXCLUDED.msum_i_crd;

END;
$procedure$


/*
 * Подготавливает данные ACC и сразу записывает агрегированный
 * результат в единый рабочий набор MI_0008.
 *
 * ACC владеет только:
 *   msum_f_acc — доход физического лица, source msum2;
 *   msum_i_acc — доход индивидуального предпринимателя, source msum1.
 *
 * Дополнительная source-table не создаётся.
 */
CREATE PROCEDURE prepare_Acc(
   IN p_inf_id       numeric,
   IN p_iyear        numeric,
   IN p_launch_itype numeric,
   IN p_irsn_corr    numeric,
   IN p_cus_marker   numeric,
   IN p_pack_num     numeric,
   IN p_scope_all    boolean
)
AS
$procedure$
   #package
BEGIN

   INSERT INTO pg_temp.mi_0008_acc_tmp AS work
   (
      s_icusnum,

      in_scope,
      source_seen,

      msum_f_acc,
      msum_i_acc
   )
   SELECT src.inum,
          true,
          true,

          /*
           * Oracle-compatible mapping:
           *
           *   msum2 → физическое лицо;
           *   msum1 → индивидуальный предприниматель.
           */
          NULLIF(
             sum(src.msum2),
             0
          )::numeric(22,2) AS msum_f_acc,

          NULLIF(
             sum(src.msum1),
             0
          )::numeric(22,2) AS msum_i_acc

     FROM perc_temp AS src

     LEFT JOIN pg_temp.mi_0008_acc_tmp AS scope
       ON scope.s_icusnum = src.inum

    WHERE src.inum IS NOT NULL

      /*
       * Полный запуск:
       *   берём всех клиентов source, кроме уже исключённых.
       *
       * Ограниченный запуск:
       *   берём только клиентов рассчитанного scope.
       */
      AND CASE
             WHEN p_scope_all THEN
                NOT coalesce(
                   scope.is_excluded,
                   false
                )

             ELSE
                coalesce(
                   scope.in_scope,
                   false
                )
                AND NOT coalesce(
                   scope.is_excluded,
                   false
                )
          END

    GROUP BY src.inum

   /*
    * Полностью отсутствующий contribution строку не создаёт.
    *
    * Если source содержал нули, строка создаётся:
    * итоговая сумма станет NULL, но source_seen будет true.
    */
   HAVING count(src.msum1) > 0
       OR count(src.msum2) > 0

   ON CONFLICT (s_icusnum) DO UPDATE
      SET in_scope    = true,
          source_seen = true,

          /*
           * Повторный вызов заменяет ACC snapshot,
           * а не складывает его с предыдущим результатом.
           *
           * DEP и CRD колонки не изменяются.
           */
          msum_f_acc = EXCLUDED.msum_f_acc,
          msum_i_acc = EXCLUDED.msum_i_acc;

END;
$procedure$

/* Конец пакета. */
;

COMMENT ON SCHEMA mi_0008_src IS
   'MI-edo. Подготовка исходных расчётных данных MI_0008, версия 0.1.0 {$Id$}'
;

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
   DROP TABLE IF EXISTS pg_temp.mi_0008_dep_src;

   CREATE TEMPORARY TABLE mi_0008_dep_src
   (
      icusnum        numeric(12),
      year           numeric(4),
      sumprocfizonly numeric(22,2),
      sumprocind     numeric(22,2)
   )
   ON COMMIT DROP;

   /*
    * TODO: реализовать расчёт DEP и заполнить pg_temp.mi_0008_dep_src.
    *
    * При p_scope_all = false рассчитываются строки из
    * pg_temp.mi_0008_scope_tmp, для которых in_scope = true и
    * is_excluded = false. При p_scope_all = true рассчитывается весь
    * допустимый набор, кроме строк с is_excluded = true.
    */
END;
$procedure$


/*
 * Подготавливает данные по кредитам.
 *
 * Процедура всегда заменяет снимок текущей сессии и создаёт таблицу даже при
 * отсутствии данных. В заглушке таблица остаётся пустой.
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
   DROP TABLE IF EXISTS pg_temp.mi_0008_crd_src;

   CREATE TEMPORARY TABLE mi_0008_crd_src
   (
      icusnum numeric(12),
      itype   numeric(2),
      msum    numeric(22,2)
   )
   ON COMMIT DROP;

   /*
    * TODO: реализовать расчёт CRD и заполнить pg_temp.mi_0008_crd_src.
    *
    * itype = 1 — сумма физического лица.
    * itype = 2 — сумма индивидуального предпринимателя.
    * Остальные значения потребителем игнорируются.
    *
    * Правила ограничения набора клиентов совпадают с prepare_Dep.
    */
END;
$procedure$


/*
 * Подготавливает данные по счетам.
 *
 * Процедура всегда заменяет снимок текущей сессии и создаёт таблицу даже при
 * отсутствии данных. В заглушке таблица остаётся пустой.
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
   DROP TABLE IF EXISTS pg_temp.mi_0008_acc_src;

   CREATE TEMPORARY TABLE mi_0008_acc_src
   (
      inum  numeric(12),
      msum1 numeric(22,2),
      msum2 numeric(22,2)
   )
   ON COMMIT DROP;

   /*
    * TODO: реализовать расчёт ACC и заполнить pg_temp.mi_0008_acc_src.
    *
    * msum1 — доход индивидуального предпринимателя.
    * msum2 — доход физического лица.
    *
    * Правила ограничения набора клиентов совпадают с prepare_Dep.
    */
END;
$procedure$


/* Конец пакета. */
;

COMMENT ON SCHEMA mi_0008_src IS
   'MI-edo. Подготовка исходных расчётных данных MI_0008, версия 0.1.0 {$Id$}'
;

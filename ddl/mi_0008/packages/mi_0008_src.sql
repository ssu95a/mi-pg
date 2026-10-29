--
-- Пакет      : mi_0008_src
-- Назначение : подготовка исходных расчётных данных для MI_0008
-- Версия     : 0.1.0
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


/* */
CREATE PROCEDURE assert_Result (
   IN p_source varchar,
   IN p_result ts.t_intRetCode
)
AS
$procedure$
   #package
   #private
BEGIN

   /* NULL retcode тоже считается ошибкой. */
   IF p_result.iretcode IS DISTINCT FROM 0 THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => 'MI_0008_SRC#' || upper(p_source) || '_FAILED',
         p_result_info => format( '%s: code=%s, error=%s', p_source, coalesce(p_result.iretcode::text, '<NULL>'), coalesce(p_result.cerrormsg, '<empty>') )
      );

   END IF;

END;
$procedure$


/*
 * Подготавливает данные по депозитам.
 * 
 * Процедура всегда заменяет снимок текущей сессии и создаёт таблицу
 * даже при отсутствии данных. 
 */
CREATE PROCEDURE prepare_Dep (
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
DECLARE
   l_dBeg date := make_date( p_iyear::int,     1, 1);
   l_dEnd date := make_date( p_iyear::int + 1, 1, 1) - 1;

   l_calc_ret ts.t_intRetCode;

BEGIN

   l_calc_ret := DJ_api.fill_TableTemp_Prc_To_Client( l_dBeg, l_dEnd, coalesce(p_cus_marker,0)::bigint, null::bigint, null::bigint, false );

   CALL mi_0008_src.assert_Result( p_source => 'DEP', p_result => l_calc_ret );

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
          NULLIF( sum(d.sumprocfizonly), 0 )::numeric(22,2),
          NULLIF( sum(d.sumprocind), 0     )::numeric(22,2)
     FROM 
          xxi.dj_v_prc_to_Client AS d
     LEFT JOIN pg_temp.mi_0008_acc_tmp AS scope
       ON scope.s_icusnum = d.icusnum
    WHERE 
          d.icusnum IS NOT NULL
      AND ( d.year IS NULL OR d.year::numeric(4) = p_iyear )
      AND CASE
             WHEN p_scope_all THEN NOT coalesce( scope.is_excluded, false )
             ELSE
                  coalesce( scope.in_scope, false ) AND NOT coalesce( scope.is_excluded, false )
          END
    GROUP BY 
          d.icusnum
   HAVING 
          count(d.sumprocfizonly) > 0 OR count(d.sumprocind) > 0
       ON 
 CONFLICT (s_icusnum) 
       DO UPDATE
      SET in_scope    = true,
          source_seen = true,
          msum_f_dep  = EXCLUDED.msum_f_dep,
          msum_i_dep  = EXCLUDED.msum_i_dep;
END;
$procedure$


/*
 * Подготавливает данные CRD
 */
CREATE PROCEDURE prepare_Crd (
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
DECLARE
   l_ret varchar(2000);
BEGIN

   CREATE TEMP TABLE IF NOT EXISTS mi_0008_ed_tmp
   (
      icusnum  numeric(12),
      itype    numeric(2),
      msum     numeric(22,2)
   )
   ON COMMIT PRESERVE ROWS
   ;

   truncate table pg_temp.mi_0008_ed_tmp;


   l_ret := AC.Get_Value2 (
      cDefint  => 'SMEV3.SM008.Load_ExtData'::VARCHAR,
      tabParam => array[ p_iyear::VARCHAR, p_launch_itype::varchar ]
   );


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
          true
          ,
          NULLIF( sum(src.msum) FILTER ( WHERE src.itype = 1 ), 0 )::numeric(22,2) AS msum_f_crd,
          NULLIF( sum(src.msum) FILTER ( WHERE src.itype = 2 ), 0 )::numeric(22,2) AS msum_i_crd
     FROM pg_temp.mi_0008_ed_tmp AS src
     LEFT 
          JOIN pg_temp.mi_0008_acc_tmp AS scope
       ON 
          scope.s_icusnum = src.icusnum
    WHERE 
          src.icusnum IS NOT NULL AND src.itype IN (1, 2) AND src.msum IS NOT NULL
      /*
       * Полный запуск:
       *   отсутствие строки в work означает обычного нового клиента;
       *   ранее помеченные исключения не загружаются.
       *
       * Ограниченный запуск:
       *   берём только клиентов рассчитанного scope.
       */
      AND CASE 
            WHEN p_scope_all THEN NOT coalesce( scope.is_excluded, false )
            ELSE coalesce( scope.in_scope, false ) AND NOT coalesce( scope.is_excluded, false )
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
CREATE PROCEDURE prepare_Acc (
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
DECLARE

   l_calc_ret ts.t_intRetCode;

   l_dbeg date := make_date( p_iyear::int,     1, 1);
   l_dend date := make_date( p_iyear::int + 1, 1, 1) - 1;

BEGIN

   l_calc_ret := Perc_Core.calcCusIncome( p_cus_marker, l_dbeg, l_dend, CASE p_launch_itype WHEN 1 THEN 'Y' ELSE 'N' END );

   CALL mi_0008_src.assert_Result( p_source => 'ACC', p_result => l_calc_ret );

   /*
    * читаем perc_temp.
    */
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

          NULLIF(sum(src.msum2), 0)::numeric(22,2),

          NULLIF(sum(src.msum1), 0)::numeric(22,2)

     FROM pg_temp.perc_temp AS src

     LEFT JOIN pg_temp.mi_0008_acc_tmp AS scope
       ON scope.s_icusnum = src.inum

    WHERE src.inum IS NOT NULL

      AND CASE
             WHEN p_scope_all THEN
                NOT coalesce(scope.is_excluded, false)

             ELSE
                coalesce(scope.in_scope, false)
                AND NOT coalesce(scope.is_excluded, false)
          END

    GROUP BY src.inum

   HAVING count(src.msum1) > 0
       OR count(src.msum2) > 0

   ON CONFLICT (s_icusnum) DO UPDATE
      SET in_scope    = true,
          source_seen = true,
          msum_f_acc  = EXCLUDED.msum_f_acc,
          msum_i_acc  = EXCLUDED.msum_i_acc;

END;
$procedure$


/* end_Of_Package */
;

COMMENT ON SCHEMA mi_0008_src IS
   'MI-edo. Подготовка исходных расчётных данных MI_0008, версия 0.1.0 {$Id$}'
;

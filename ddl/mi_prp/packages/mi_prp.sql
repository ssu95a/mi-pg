create or replace package MI_prp
CREATE FUNCTION __init__()
   RETURNS 
      void
as
$init$
declare
   /*
      Пакет службы свойств
   */
   cVersion CONSTANT VARCHAR( 100 ) := '$Id: {1.0.1} {06.10.2026} Sulimoff$';

   ret_OK      Constant INTEGER := 0;
   ret_Fail    Constant INTEGER := -1;
   ret_No_Data Constant INTEGER := 1;

begin
   raise debug 'Package "MI_prp" - % - initialized', cVersion;
end;
$init$


/* */
create function get_Version()
   returns
      varchar
AS 
$function$
   #package
begin
   return cVersion;
end;
$function$


/* */
create function make_Prpoperty_Name (  
   in p_objId NUMERIC, -- Id модуля
   in p_prpId VARCHAR  -- Id свойства    
)
   RETURNS
      VARCHAR
AS
$function$
   #private
   #package
begin

   if p_objId is null or p_prpId is null then
      return p_prpId;
   end if;

   if p_objId = 0::numeric then
      return concat_Ws( '_', 'mi'::varchar, 'sys'::varchar, null::varchar, p_prpId );
   end if;

   if p_objId < 0::numeric then
      return concat_Ws( '_', 'mi'::varchar, 'w'::varchar || abs( p_objId )::varchar, '#'::varchar, p_prpId );
   end if;

   declare
      l_wspId varchar;
   begin

      select 'w_' || wsp_id 
        into l_wspId strict 
        from xxi.mi_inf where inf_Id = p_objId;

      return concat_Ws( '_', 'mi'::varchar, l_wspId, 'i_' || p_objId::varchar, p_prpId );

   end;   

end;
$function$


/* Получение свойства АРМ модуля */
CREATE FUNCTION get_Property (
  in p_objId    NUMERIC, -- Id модуля
  in p_prpId    VARCHAR, -- Id свойства    
  in p_defValue VARCHAR DEFAULT NULL::VARCHAR
)
   RETURNS
      VARCHAR
   LANGUAGE
      plPGsql
AS
$function$
   #private
   #package
declare
   l_retValue varchar;
begin

   select 
      pref.Get_Global_Preference( MI_prp.make_Prpoperty_Name( $1, $2 ) )
   into
      l_retValue;

   RETURN coalesce( l_retValue, $3 );

END;
$function$


/* Установка свойства АРМ модуля */
CREATE PROCEDURE set_Property (
   in p_objId  NUMERIC, -- Id модуля
   in p_prpId  VARCHAR, -- Id свойства    
   in p_value  VARCHAR  -- значение свойства
)
AS
$procedure$
   #private
   #package
begin
   call pref.set_Global_Preference( MI_prp.make_Prpoperty_Name( $1, $2 ), $3 );
END;
$procedure$


/* Получение свойства АРМ модуля */
CREATE FUNCTION get_Wsp_Property (
  in p_wspId    NUMERIC, -- Id модуля
  in p_prpId    VARCHAR, -- Id свойства    
  in p_defValue VARCHAR DEFAULT NULL::VARCHAR
)
   RETURNS
      VARCHAR
AS
$function$
   #package
declare
   l_retValue varchar;
begin
   return MI_prp.get_Property( p_wspId * -1, p_prpId, p_defValue );
END;
$function$


/* Установка свойства АРМ модуля */
CREATE PROCEDURE set_Wsp_Property (
  in p_wspId NUMERIC, -- Id модуля
  in p_prpId VARCHAR, -- Id свойства    
  in p_value VARCHAR
)
AS
$procedure$
   #package
begin
   call MI_prp.set_Property( p_wspId * -1, p_prpId, p_value );
END;
$procedure$


/* Получение свойства модуля */
CREATE FUNCTION get_Inf_Property (
  in p_infId    NUMERIC, -- Id модуля
  in p_prpId    VARCHAR, -- Id свойства    
  in p_defValue VARCHAR DEFAULT NULL::VARCHAR
)
   RETURNS
      VARCHAR
   LANGUAGE
      plPGsql
AS
$function$
   #package
declare
   l_retValue varchar;
begin
   return MI_prp.get_Property( p_infId, p_prpId, p_defValue );
END;
$function$


/* Установка свойства модуля */
CREATE PROCEDURE set_Inf_Property (
  in p_infId NUMERIC, -- Id модуля
  in p_prpId VARCHAR, -- Id свойства    
  in p_value VARCHAR
)
AS
$procedure$
   #package
begin
   call MI_prp.set_Property( p_infId, p_prpId, p_value );
END;
$procedure$


/* Получение свойства системы*/
CREATE FUNCTION get_Sys_Property (
  in p_prpId    VARCHAR, -- Id свойства    
  in p_defValue VARCHAR DEFAULT NULL::VARCHAR
)
   RETURNS
      VARCHAR
   LANGUAGE
      plPGsql
AS
$function$
   #package
declare
   l_retValue varchar;
begin
   return MI_prp.get_Property( 0, p_prpId, p_defValue );
END;
$function$


/* Установка свойства системы*/
CREATE PROCEDURE set_Sys_Property (
  in p_prpId VARCHAR, -- Id свойства    
  in p_value VARCHAR
)
AS
$procedure$
   #package
begin
   call MI_prp.set_Property( 0, p_prpId, p_value );
END;
$procedure$

-- end_Of_Package
;

COMMENT ON SCHEMA MI_prp IS 'Package MI_prp {$Id$}'
;

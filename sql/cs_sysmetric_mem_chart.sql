----------------------------------------------------------------------------------------
--
-- File name:   cs_sysmetric_mem_chart.sql
--
-- Purpose:     System Metrics Summary Chart from Memory
--
-- Author:      Carlos Sierra
--
-- Version:     2019/03/24
--
-- Usage:       Execute connected to CDB or PDB
--
--              Enter filters when requested.
--
-- Example:     $ sqlplus / as sysdba
--              SQL> @cs_sysmetric_mem_chart.sql
--
-- Notes:       Developed and tested on 12.1.0.2.
--
---------------------------------------------------------------------------------------
--
@@cs_internal/cs_primary.sql
@@cs_internal/cs_set.sql
@@cs_internal/cs_def.sql
@@cs_internal/cs_file_prefix.sql
--
DEF cs_script_name = 'cs_sysmetric_mem_chart';
--
--ALTER SESSION SET container = CDB$ROOT;
--
COL metric_name FOR A45 TRUN;
COL metric_unit FOR A41 TRUN;
SELECT DISTINCT
       metric_name,
       metric_unit
  FROM v$sysmetric
 ORDER BY
       metric_name
/
PRO
PRO 1. Filter on Metric Name or Unit (e.g. sessions, blocks, undo, commit, transaction, bytes, %):
DEF metric_filter = '&1.';
--
SELECT DISTINCT
       metric_name,
       metric_unit
  FROM v$sysmetric
 WHERE CASE '&&metric_filter.'
       WHEN '%' THEN CASE WHEN metric_name||metric_unit LIKE '%\%%' ESCAPE '\' THEN 1 END
       ELSE CASE WHEN UPPER(metric_name||metric_unit) LIKE UPPER('%&&metric_filter.%') THEN 1 END
       END = 1
 ORDER BY
       metric_name
/
PRO
PRO 2. Metric Name (1):
DEF metric_name_1 = '&2.';
--
COL cs_metric_unit_1 NEW_V cs_metric_unit_1 NOPRI;
SELECT metric_unit cs_metric_unit_1 FROM v$sysmetric WHERE metric_name = '&&metric_name_1.' AND ROWNUM = 1
/
--
SELECT DISTINCT
       metric_name,
       metric_unit
  FROM v$sysmetric
 WHERE UPPER(metric_unit) LIKE UPPER('%&&cs_metric_unit_1.%') 
   AND metric_name NOT IN ('&&metric_name_1.')
 ORDER BY
       metric_name
/
PRO
PRO Enter additional optional Metric Names, consistent with Metric Unit of "&&cs_metric_unit_1."
PRO
PRO 3. Metric Name (2):
DEF metric_name_2 = '&3.';
--
COL cs_metric_unit_2 NEW_V cs_metric_unit_2 NOPRI;
SELECT metric_unit cs_metric_unit_2 FROM v$sysmetric WHERE metric_name = '&&metric_name_2.' AND ROWNUM = 1
/
--
SELECT DISTINCT
       metric_name,
       metric_unit
  FROM v$sysmetric
 WHERE (UPPER(metric_unit) LIKE UPPER('%&&cs_metric_unit_1.%') OR UPPER(metric_unit) LIKE UPPER('%&&cs_metric_unit_2.%'))
   AND metric_name NOT IN ('&&metric_name_1.', '&&metric_name_2.')
 ORDER BY
       metric_name
/
PRO
PRO 4. Metric Name (3):
DEF metric_name_3 = '&4.';
--
COL cs_metric_unit_3 NEW_V cs_metric_unit_3 NOPRI;
SELECT metric_unit cs_metric_unit_3 FROM v$sysmetric WHERE metric_name = '&&metric_name_3.' AND ROWNUM = 1
/
--
SELECT DISTINCT
       metric_name,
       metric_unit
  FROM v$sysmetric
 WHERE (UPPER(metric_unit) LIKE UPPER('%&&cs_metric_unit_1.%') OR UPPER(metric_unit) LIKE UPPER('%&&cs_metric_unit_2.%') OR UPPER(metric_unit) LIKE UPPER('%&&cs_metric_unit_3.%'))
   AND metric_name NOT IN ('&&metric_name_1.', '&&metric_name_2.', '&&metric_name_3.')
 ORDER BY
       metric_name
/
PRO
PRO 5. Metric Name (4):
DEF metric_name_4 = '&5.';
--
SELECT '&&cs_file_prefix._&&cs_script_name.' cs_file_name FROM DUAL;
--
DEF report_title = "System Metrics (value)";
DEF chart_title = "System Metrics (value)";
DEF xaxis_title = "";
DEF vaxis_title = "&&cs_metric_unit_1.";
--
-- (isStacked is true and baseline is null) or (not isStacked and baseline >= 0)
--DEF is_stacked = "isStacked: false,";
DEF is_stacked = "isStacked: true,";
--DEF vaxis_baseline = ", baseline:&&cs_num_cpu_cores., baselineColor:'red'";
DEF vaxis_baseline = "";
DEF chart_foot_note_2 = "<br>2)";
DEF chart_foot_note_3 = "";
DEF chart_foot_note_4 = "";
DEF report_foot_note = "&&cs_script_name..sql";
--
@@cs_internal/cs_spool_head_chart.sql
--
PRO ,'&&metric_name_1.'        
PRO ,'&&metric_name_2.'        
PRO ,'&&metric_name_3.'        
PRO ,'&&metric_name_4.'        
PRO ]
--
SET HEA OFF PAGES 0;
/****************************************************************************************/
WITH
sysmetric_history AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       end_time,
       metric_name, 
       value
  FROM v$sysmetric_history
 WHERE metric_name IN ('&&metric_name_1.', '&&metric_name_2.', '&&metric_name_3.', '&&metric_name_4.')
   AND group_id = 2 -- 1 minute
),
my_query AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       end_time time,
       SUM(CASE metric_name WHEN '&&metric_name_1.' THEN value ELSE 0 END) metric_name_1,
       SUM(CASE metric_name WHEN '&&metric_name_2.' THEN value ELSE 0 END) metric_name_2,
       SUM(CASE metric_name WHEN '&&metric_name_3.' THEN value ELSE 0 END) metric_name_3,
       SUM(CASE metric_name WHEN '&&metric_name_4.' THEN value ELSE 0 END) metric_name_4
  FROM sysmetric_history
 GROUP BY
       end_time
)
SELECT ', [new Date('||
       TO_CHAR(q.time, 'YYYY')|| /* year */
       ','||(TO_NUMBER(TO_CHAR(q.time, 'MM')) - 1)|| /* month - 1 */
       ','||TO_CHAR(q.time, 'DD')|| /* day */
       ','||TO_CHAR(q.time, 'HH24')|| /* hour */
       ','||TO_CHAR(q.time, 'MI')|| /* minute */
       ','||TO_CHAR(q.time, 'SS')|| /* second */
       ')'||
       ','||q.metric_name_1|| 
       ','||q.metric_name_2|| 
       ','||q.metric_name_3|| 
       ','||q.metric_name_4|| 
       ']'
  FROM my_query q
 ORDER BY
       q.time
/
/****************************************************************************************/
SET HEA ON PAGES 100;
--
-- [Line|Area|Scatter]
DEF cs_chart_type = 'Line';
-- disable explorer with "//" when using Pie
DEF cs_chart_option_explorer = '';
-- enable pie options with "" when using Pie
DEF cs_chart_option_pie = '//';
-- use oem colors
DEF cs_oem_colors_series = '//';
DEF cs_oem_colors_slices = '//';
-- for line charts
DEF cs_curve_type = '';
--
@@cs_internal/cs_spool_id_chart.sql
@@cs_internal/cs_spool_tail_chart.sql
PRO
PRO SQL> @&&cs_script_name..sql "&&metric_filter." "&&metric_name_1." "&&metric_name_2." "&&metric_name_3." "&&metric_name_4."
--
--ALTER SESSION SET CONTAINER = &&cs_con_name.;
--
@@cs_internal/cs_undef.sql
@@cs_internal/cs_reset.sql
--
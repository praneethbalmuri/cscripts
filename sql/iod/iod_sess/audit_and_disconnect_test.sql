--CREATE TABLE system.KIEVTRANSACTORHOSTS AS SELECT * FROM KIEV_BACKGROUND.KievTransactorHosts;
--LOCK TABLE system.KievTransactorHosts IN EXCLUSIVE MODE;
--Replace ' c_' with ' :c_'

VAR c_lock_secs_thres   NUMBER;
VAR c_inac_secs_thres   NUMBER;
VAR c_snip_secs_thres   NUMBER;
VAR c_snip_idle_profile VARCHAR2;
VAR c_snip_candidates   VARCHAR2;
VAR c_sniped_sessions   VARCHAR2;
VAR c_tm_locks          VARCHAR2;
VAR c_tx_locks          VARCHAR2;

EXEC :c_lock_secs_thres  := 15;
EXEC :c_inac_secs_thres  := 3600;
EXEC :c_snip_secs_thres  := 600;
EXEC :c_snip_idle_profile:= 'APP_PROFILE';
EXEC :c_snip_candidates  := 'Y';
EXEC :c_sniped_sessions  := 'Y';
EXEC :c_tm_locks         := 'Y'
EXEC :c_tx_locks         := 'Y';

    WITH /* &&1.iod_sess.audit_and_disconnect */
    s_v$session AS (
    SELECT /*+ MATERIALIZE NO_MERGE */
           s.sid,
           s.serial#,
           s.paddr,
           s.type,
           s.user#,
           s.status,
           s.logon_time,
           s.last_call_et,
           s.service_name,
           s.machine,
           s.osuser,
           s.program,
           s.module,
           s.client_info,
           s.sql_id,
           s.sql_exec_start,
           s.prev_sql_id,
           s.prev_exec_start,
           s.username,
           s.con_id,
           s.row_wait_obj#
      FROM v$session s
     WHERE s.type = 'USER'
       --AND s.user# > 0 -- skip SYS
       --AND s.last_call_et >= LEAST( :c_lock_secs_thres, :c_inac_secs_thres, :c_snip_secs_thres) -- removed so we can see them all, including s.last_call_et = 0
    ),
    s_v$process AS (
    SELECT /*+ MATERIALIZE NO_MERGE */
           p.addr,
           p.spid,
           p.con_id
      FROM v$process p
    ),
    s_cdb_users AS (
    SELECT /*+ MATERIALIZE NO_MERGE */
           u.username,
           u.oracle_maintained,
           u.profile,
           u.con_id
      FROM cdb_users u
     WHERE u.profile = :c_snip_idle_profile 
       --AND u.oracle_maintained = 'N'
    ),
    s_v$containers AS (
    SELECT /*+ MATERIALIZE NO_MERGE */
           c.name,
           c.con_id,
           c.open_mode
      FROM v$containers c
     WHERE c.open_mode = 'READ WRITE'
    ),
    s_v$lock AS (
    SELECT /*+ MATERIALIZE NO_MERGE */
           l.type,
           l.ctime,
           l.block,
           l.sid,
           l.lmode,
           l.request,
           l.con_id,
           l.id1,
           l.id2
      FROM v$lock l
     WHERE l.type IN ('TM', 'TX')
       --AND l.ctime >= :c_lock_secs_thres -- removed so we can see them all, including l.ctime = 0
    ),
    s_cdb_objects AS (
    SELECT /*+ MATERIALIZE NO_MERGE */
           o.object_name,
           o.object_type,
           o.temporary,
           o.oracle_maintained,
           o.object_id,
           o.con_id
      FROM cdb_objects o
     WHERE o.owner <> 'SYS'
       AND o.object_name IN ('KIEVTRANSACTIONS', 'KIEVTRANSACTORHOSTS') -- (DBPERFOCI-36)
       AND o.object_type = 'TABLE'
       AND o.temporary = 'N'
       --AND o.oracle_maintained = 'N'
    ),
    main_query AS (
    -- 
    -- Inactive sessions to be killed, similar SNIPPED sessions due to DBA_PROFILE IDLE_TIME (regardless of table)
    --
    SELECT /*+ ORDERED */
           CASE WHEN s.last_call_et >= :c_inac_secs_thres THEN 'Y' ELSE 'N' END death_row,
           s.sid,
           s.serial#,
           p.spid,
           s.status,
           s.logon_time,
           --SYSDATE snap_time,
           s.last_call_et,
           TO_NUMBER(NULL) ctime,
           NULL type,
           TO_NUMBER(NULL) lmode,
           s.service_name,
           s.machine,
           s.osuser,
           s.program,
           s.module,
           s.client_info,
           s.sql_id,
           s.sql_exec_start,
           s.prev_sql_id,
           s.prev_exec_start,
           s.username,
           TO_NUMBER(NULL) object_id,
           s.con_id,
           c.name pdb_name,
           --'INACTIVE > '|| :c_inac_secs_thres||'s' reason,
           'INACTIVE '|| s.last_call_et||'s' reason,
           3 pty
      FROM s_v$session    s,
           s_v$process    p,
           s_cdb_users    u,
           s_v$containers c
     WHERE :c_snip_candidates IN ('Y', 'T') -- (Y)es or (T)rue
       AND s.status = 'INACTIVE'
       AND s.type = 'USER'
       --AND s.user# > 0 -- skip SYS
       AND s.last_call_et >= :c_inac_secs_thres -- seconds since became inactive
       AND p.con_id = s.con_id
       AND p.addr = s.paddr
       AND u.con_id = s.con_id
       AND u.username = s.username
       --AND u.oracle_maintained = 'N' -- redundant
       AND u.profile = :c_snip_idle_profile
       AND c.con_id = s.con_id
       AND c.open_mode = 'READ WRITE' -- redundant
       AND p.con_id = u.con_id -- adding transitive join predicate
       AND c.con_id = u.con_id -- adding transitive join predicate
       AND c.con_id = p.con_id -- adding transitive join predicate
     UNION ALL
    -- 
    -- Sniped sessions due to DBA_PROFILE IDLE_TIME (regardless of table)
    --
    SELECT /*+ ORDERED */
           CASE WHEN s.last_call_et >= :c_snip_secs_thres THEN 'Y' ELSE 'N' END death_row,
           s.sid,
           s.serial#,
           p.spid,
           s.status,
           s.logon_time,
           --SYSDATE snap_time,
           s.last_call_et,
           TO_NUMBER(NULL) ctime,
           NULL type,
           TO_NUMBER(NULL) lmode,
           s.service_name,
           s.machine,
           s.osuser,
           s.program,
           s.module,
           s.client_info,
           s.sql_id,
           s.sql_exec_start,
           s.prev_sql_id,
           s.prev_exec_start,
           s.username,
           TO_NUMBER(NULL) object_id,
           s.con_id,
           c.name pdb_name,
           --'SNIPED' reason,
           'SNIPED '|| s.last_call_et||'s' reason,
           4 pty
      FROM s_v$session    s,
           s_v$process    p,
           s_v$containers c
     WHERE :c_sniped_sessions IN ('Y', 'T') -- (Y)es or (T)rue
       AND s.status = 'SNIPED'
       AND s.type = 'USER'
       --AND s.user# > 0 -- skip SYS
       AND s.last_call_et >= :c_snip_secs_thres -- seconds since became inactive
       AND p.con_id = s.con_id
       AND p.addr = s.paddr
       AND c.con_id = s.con_id
       AND c.open_mode = 'READ WRITE' -- redundant
       AND c.con_id = p.con_id -- adding transitive join predicate
     UNION ALL
    --
    -- TM DML enqueue locks on specific table (or table lock)
    --
    SELECT /*+ ORDERED */
           CASE 
             WHEN s.status = 'INACTIVE' AND l.ctime >= :c_lock_secs_thres AND s.last_call_et >= :c_lock_secs_thres THEN 'Y' 
             WHEN /* CHANGE-77369 s.status = 'INACTIVE' AND */ LOWER(s.osuser) NOT IN ('root', '?', 'nobody', 'bgpagent', 'bgpserver') AND LOWER(s.machine)||'.' LIKE '%-mac.%' AND l.ctime >= 1 THEN 'Y' -- ODSI-1333
             ELSE 'N' 
           END death_row,
           s.sid,
           s.serial#,
           p.spid,
           s.status,
           s.logon_time,
           --SYSDATE snap_time,
           s.last_call_et,
           l.ctime,
           l.type,
           l.lmode,
           s.service_name,
           s.machine,
           s.osuser,
           s.program,
           s.module,
           s.client_info,
           s.sql_id,
           s.sql_exec_start,
           s.prev_sql_id,
           s.prev_exec_start,
           s.username,
           o.object_id,
           s.con_id,
           c.name pdb_name,
           --'TM LOCK AND INACTIVE > '|| :c_lock_secs_thres||'s' reason,
           'TM LOCK AND INACTIVE '|| s.last_call_et||'s' reason,
           2 pty
      FROM s_v$lock       l,
           s_v$session    s,
           s_v$process    p,
           s_cdb_objects  o,
           s_v$containers c
     WHERE :c_tm_locks IN ('Y', 'T') -- (Y)es or (T)rue
       AND l.type = 'TM' -- DML enqueue
       --AND l.ctime >= :c_lock_secs_thres -- lock duration in seconds
       AND l.block = 1 -- blocking oher session(s) on this instance
       AND s.con_id = l.con_id -- <> 0
       AND s.sid = l.sid
       --AND s.status = 'INACTIVE' -- collect also ACTIVE or KILLED
       AND s.type = 'USER'
       --AND s.user# > 0 -- skip SYS
       --AND s.last_call_et >= :c_lock_secs_thres -- seconds since became inactive
       AND p.con_id = s.con_id
       AND p.addr = s.paddr
       AND o.con_id = l.con_id
       AND o.object_id = l.id1
       AND o.object_name IN ('KIEVTRANSACTIONS', 'KIEVTRANSACTORHOSTS') -- redundant -- (DBPERFOCI-36)
       AND o.object_type = 'TABLE' -- redundant
       AND o.temporary = 'N' -- redundant
       --AND o.oracle_maintained = 'N' -- redundant
       AND c.con_id = s.con_id
       AND c.open_mode = 'READ WRITE' -- redundant
       AND p.con_id = c.con_id -- adding transitive join predicate
       AND p.con_id = l.con_id -- adding transitive join predicate
       AND p.con_id = o.con_id -- adding transitive join predicate
       AND c.con_id = l.con_id -- adding transitive join predicate
       AND c.con_id = o.con_id -- adding transitive join predicate
       AND o.con_id = s.con_id -- adding transitive join predicate
     UNION ALL
    --
    -- TX Transaction enqueue locks on specific table (row lock)
    --
    SELECT /*+ ORDERED */
           DISTINCT -- needed since one session could be blocking several others (thus expecting duplicates)
           CASE 
             WHEN bs.status = 'INACTIVE' AND b.ctime >= :c_lock_secs_thres AND bs.last_call_et >= :c_lock_secs_thres AND w.ctime >= :c_lock_secs_thres AND ws.last_call_et >= :c_lock_secs_thres THEN 'Y' 
             WHEN /* CHANGE-77369 bs.status = 'INACTIVE' AND */ LOWER(bs.osuser) NOT IN ('root', '?', 'nobody', 'bgpagent', 'bgpserver') AND LOWER(bs.machine)||'.' LIKE '%-mac.%' AND b.ctime >= 1 THEN 'Y' -- ODSI-1333
             ELSE 'N' 
           END death_row,
           bs.sid,
           bs.serial#,
           bp.spid,
           bs.status,
           bs.logon_time,
           --SYSDATE snap_time,
           bs.last_call_et,
           b.ctime,
           b.type,
           b.lmode,
           bs.service_name,
           bs.machine,
           bs.osuser,
           bs.program,
           bs.module,
           bs.client_info,
           bs.sql_id,
           bs.sql_exec_start,
           bs.prev_sql_id,
           bs.prev_exec_start,
           bs.username,
           wo.object_id,
           bs.con_id,
           bc.name pdb_name,
           --'TX LOCK AND INACTIVE > '|| :c_lock_secs_thres||'s' reason,
           'TX LOCK AND INACTIVE '|| bs.last_call_et||'s' reason,
           1 pty
      FROM s_v$lock       b,  -- blockers
           s_v$session    bs, -- sessions blocking others (blocker)
           s_v$process    bp, -- processes for sessions blocking others (blocker)
           s_v$containers bc,
           s_v$lock       w,  -- waiters (blockees)
           s_v$session    ws, -- sessions waiting (blockees)
           s_cdb_objects  wo  -- objects for which sessions are waiting on
     WHERE :c_tx_locks IN ('Y', 'T') -- (Y)es or (T)rue
       AND b.type = 'TX' -- transaction enqueue
       --AND b.ctime >= :c_lock_secs_thres -- lock duration in seconds
       AND b.block = 1 -- blocking oher session(s) on this instance
       --AND bs.con_id = b.con_id -- bs.con_id <> 0 and b.con_id = 0
       AND bs.sid = b.sid
       --AND bs.status = 'INACTIVE' -- blocker could potentially being doing some work if it were ACTIVE. collect also ACTIVE or KILLED
       AND bs.type = 'USER'
       --AND bs.user# > 0 -- skip SYS
       --AND bs.last_call_et >= :c_lock_secs_thres -- seconds since inactive (blocking)
       AND bp.con_id = bs.con_id -- bp.con_id <> 0 and bs.con_id <> 0
       AND bp.addr = bs.paddr
       AND bc.con_id = bs.con_id
       AND bc.open_mode = 'READ WRITE' -- redundant
       AND w.type = 'TX' -- transaction enqueue
       --AND w.ctime >= :c_lock_secs_thres -- wait duration in seconds
       --AND w.block = 0 -- the waiter could potentially be blocking others as well
       AND w.request > 0 -- requesting a lock on some resource
       AND w.con_id = b.con_id -- w.con_id = 0 and b.con_id = 0
       AND w.id1 = b.id1 -- rollback segment
       AND w.id2 = b.id2 -- transaction table entries
       --AND ws.con_id = w.con_id -- ws.con_id <> 0 and w.con_id = 0
       AND ws.sid = w.sid
       AND ws.status = 'ACTIVE'
       AND ws.type = 'USER'
       --AND ws.user# > 0 -- skip SYS
       --AND ws.last_call_et >= :c_lock_secs_thres -- seconds since active (waiting)
       AND wo.con_id = ws.con_id -- wo.con_id <> 0 and ws.con_id <> 0
       AND wo.object_id = ws.row_wait_obj#
       AND wo.object_name IN ('KIEVTRANSACTIONS', 'KIEVTRANSACTORHOSTS') -- redundant -- (DBPERFOCI-36)
       AND wo.object_type = 'TABLE' -- redundant
       AND wo.temporary = 'N' -- redundant
       --AND wo.oracle_maintained = 'N' -- redundant
       AND bp.con_id = bc.con_id -- adding transitive join predicate (con_id <> 0)
       AND wo.con_id = bp.con_id -- adding transitive join predicate (con_id <> 0)
       AND wo.con_id = bs.con_id -- adding transitive join predicate (con_id <> 0)
       AND wo.con_id = bc.con_id -- adding transitive join predicate (con_id <> 0)
       AND ws.con_id = bp.con_id -- adding transitive join predicate (con_id <> 0)
       AND ws.con_id = bs.con_id -- adding transitive join predicate (con_id <> 0)
       AND ws.con_id = bc.con_id -- adding transitive join predicate (con_id <> 0)
    )
    SELECT m.pty,
           m.death_row,
           m.sid,
           m.serial#,
           m.spid,
           m.status,
           m.logon_time,
           --SYSDATE snap_time,
           m.last_call_et,
           m.ctime,
           m.type,
           m.lmode,
           m.service_name,
           m.machine,
           m.osuser,
           m.program,
           m.module,
           m.client_info,
           m.sql_id,
           m.sql_exec_start,
           m.prev_sql_id,
           m.prev_exec_start,
           m.username,
           m.object_id,
           m.con_id,
           m.pdb_name,
           m.reason
      FROM main_query m
     ORDER BY
           m.pty,
           m.sid,
           m.serial#
/



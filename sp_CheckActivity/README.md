# sp_CheckActivity

`sp_CheckActivity` shows the current activity of any sessions that have a currently executing request or an open transaction. It is a quick, low-resource way to see the active state of a SQL Server instance. It is not meant to be a full replacement for `sp_WhoIsActive` (which has many more features), but it is handy for a fast snapshot. It is part of the free [Straight Path IT Solutions](https://straightpathsql.com/) `sp_Check*` suite.

> Note: The suite build installs `sp_CheckActivity` into the `master` database, not `DB_Administration` like the rest of the suite. The procedure can be created in any database, but if you plan to use the `@TableName` parameter to send results to a table, you must use a 3 part reference (DB.Schema.Table) to that table.

## Features

- Shows a **snapshot of active sessions and requests**: elapsed time, session id, the currently executing statement and its parent batch or procedure, status, wait type and time, blocking session, CPU, reads, writes, tempdb usage, row count, transaction count, memory grant, isolation level, login, host, program, and session timing.
- Optionally includes the **query plan** for the currently running statement (`@Plans`).
- Reports **tempdb consumption(GB) per session**, both for the currently running statement and the historical allocation since the session started.
- Has a dedicated **blocking mode** (`@ShowBlocking`) that returns lead blockers and the sessions blocked by them, including blocking chains.
- Has a dedicated **progress mode** (`@ShowProgress`) that estimates completion time for any operation that reports percent complete (Backup, Restore, DBCC, Recovery, RollBack, TDE Encryption, Reorganize), filtering out everything else.
- Can **filter** by login account, one or more session ids, and sleeping-session behavior, and can show the top-most procedure for nested calls (`@ShowTopProc`).
- Can **persist results to a table** for later analysis (`@TableName`), and offers a raw (unformatted) output option for programmatic use (`@Raw`).
- Includes basic **SQL injection guards** on the `@Account` and `@TableName` parameters.

## Requirements

- **SQL Server version:** Designed for **SQL Server 2016 (13.x) or higher**. It also runs on **SQL Server 2012 (11.x)** and **2014 (12.x)**, but some data is not available before 2016 and is returned as NULL on those versions (specifically the `[DOP]` and `[Workers]` columns); the procedure also switches between `DATEDIFF` and `DATEDIFF_BIG` based on version. Execution is aborted on versions older than 2012 (`@SQLVersionMajor < 11`).
- **Permissions:** Effectively **sysadmin**, or at minimum `VIEW SERVER STATE` to see other sessions. The procedure reads execution DMVs (`sys.dm_exec_sessions`, `sys.dm_exec_requests`, `sys.dm_exec_sql_text`, `sys.dm_exec_input_buffer`, `sys.dm_exec_text_query_plan`) and tempdb space-usage DMVs. When `@TableName` is supplied, the caller also needs INSERT permission on the target table.
- **`@TableName` target:** The table will be created if it does not already exist, must be fully qualified (`[DB].[Schema].[Table]`), and is validated and rejected if malformed or containing injection characters. The blocking (`@ShowBlocking`) and progress (`@ShowProgress`) modes do not support output to a table.

## Parameters

| Name | Data Type | Default | Description |
|------|-----------|---------|-------------|
| `@Account` | `NVARCHAR(128)` | `NULL` | The account used to log in to SQL Server (`Domain\User`). Returns all requests for this account. Rejected if it contains common injection characters. |
| `@SessionID` | `NVARCHAR(200)` | `NULL` | A specific SPID, or a comma-delimited list of SPIDs, to report on. More than one SPID must be passed as a string. |
| `@Plans` | `BIT` | `0` | `1` = include the query plan for the currently running statement. |
| `@FilterSleeping` | `TINYINT` | `1` | `0` = do not show any sleeping sessions; `1` = show sleeping sessions with open transactions; `2` = show all non-system sessions. |
| `@ShowTopProc` | `BIT` | `0` | `1` = show the top-most procedure when procedure calls are nested. |
| `@TableName` | `NVARCHAR(256)` | `NULL` | Fully qualified table (`[DB Name].[schema].[Table Name]`) to insert the results into. |
| `@Help` | `BIT` | `0` | `1` = print the help for this procedure and exit. |
| `@Raw` | `BIT` | `0` | `1` = perform no formatting on the output; otherwise some numeric columns are converted to character and formatted for readability and alignment. |
| `@ShowProgress` | `BIT` | `0` | `1` = show the estimated completion time for any operation that supports percent complete (Backup, Restore, DBCC, Recovery, and similar). Filters everything else out. |
| `@ShowBlocking` | `BIT` | `0` | `1` = show any sessions that are blocking or being blocked, including the lead blocker. |
| `@VersionCheck` | `BIT` | `0` | `1` = return the current version of this procedure, then exit. |

This procedure has no `OUTPUT` parameters. It can be run with no parameters (the default), with all parameters, or most combinations.

## Usage

```sql
-- Snapshot of current activity: active requests plus sleeping sessions with open transactions
EXEC master.dbo.sp_CheckActivity;

-- Show only blocking: lead blockers and the sessions they block
EXEC master.dbo.sp_CheckActivity
      @ShowBlocking = 1;

-- Estimate completion time for long-running backup/restore/DBCC/recovery commands
EXEC master.dbo.sp_CheckActivity
      @ShowProgress = 1;

-- Output the results in a Raw (Unformatted) output and show the Query Plans
EXEC master.dbo.sp_CheckActivity
      @Raw = 1
    , @Plans = 1;
```

## Priority System

Not applicable. `sp_CheckActivity` is a live activity monitor and does not produce prioritized findings. The shared 0-3 Importance model used elsewhere in the suite is shown here for reference only:

| Priority | Meaning |
|----------|---------|
| 0 | Informational |
| 1 | High |
| 2 | Medium |
| 3 | Low |

## Checks

Not applicable. `sp_CheckActivity` does not use the CheckID-based findings framework of the other `sp_Check*` procedures. Instead of evaluating checks, it returns the live state of sessions and requests. See Results Organization for the columns returned in each mode.

## Results Organization

`sp_CheckActivity` returns a single result set whose shape depends on the mode flags. There is no CheckID series index.

### Default result set

One row per qualifying session. The `@FilterSleeping`, `@Account`, and `@SessionID` parameters narrow which rows are returned; system sessions and the calling session are excluded. Note that some metrics such as CPU, Reads, Writes and Elapsed Time are at the Request (Batch / Procedure) level where as others such as Wait time, Estimated Completion, % Complete etc. are at the Statement level due to how the metrics are reported by the DMV's. The descriptions below outline which level is used for each column.

| Column | Description |
|--------|-------------|
| `[hhh:mm:ss]` | Elapsed time as Hours:Minutes:Seconds of the request. |
| `[SessionID]` | The session id (SPID). |
| `[Executed Statement]` | The individual statement in the batch, function, or procedure that is currently running. |
| `[Batch or Procedure]` | The direct parent batch, function, or procedure (if not a standalone statement). |
| `[Query Plan]` | Query plan for the statement (NULL when `@Plans = 0`). |
| `[Blocking ID]` | NULL or the session id that is blocking the currently running request. |
| `[CPU ms]` | CPU time in ms of the currently running request, or the entire session if there is no active request. |
| `[Logical Reads]` | Pages read by the currently running request, or the entire session if there is no active request. |
| `[Writes]` | Pages written by the currently running request, or the entire session if there is no active request. |
| `[Status]` | Status of the currently running request, or the entire session if there is no active request. |
| `[Wait Type]` | Wait type of the currently running request, or the entire session if there is no active request. |
| `[Wait ms]` | Milliseconds the currently running request has been waiting on the most recent wait type. |
| `[C Tempdb GB]` | tempdb space being used by the currently running statement. |
| `[H Tempdb GB]` | tempdb allocations minus any deallocations used by the session since it started. |
| `[% Complete]` | Percent complete as reported by SQL Server. |
| `[DB Name]` | Database name. |
| `[Program Name]` | Program name. |
| `[Login Name]` | Login name. |
| `[Host Name]` | Host name. |
| `[Row Count]` | Number of rows returned to the client by this request. |
| `[Tran Count]` | Transaction count. |
| `[DOP]` | Degree of parallelism for the currently running statement (NULL before SQL Server 2016). |
| `[Workers]` | Reserved parallel workers if this is a parallel query (NULL before SQL Server 2016). |
| `[Memory Grant MB]` | Query memory allocated to the executing statement. |
| `[ISO Level]` | Transaction isolation level. |
| `[CaptureDT]` | Date and time the snapshot was taken. |
| `[Login Mins]` | Minutes since the session started. |
| `[Login DT]` | Date and time the session started. |
| `[Top Procedure]` | The top-most procedure when calls are nested (only shown when `@ShowTopProc = 1`). |

### Additional columns with `@ShowProgress = 1`

This mode filters out any session not actively running an operation that supports percent complete, and adds:

| Column | Description |
|--------|-------------|
| `[StartTime]` | Date and time the request began executing. |
| `[Run Time]` | Minutes the request has been running so far, as hhh:mm:ss. |
| `[Est Compl Time]` | Estimated time until completion, as hhh:mm:ss for the current statement. |
| `[% Complete]` | Percent complete as reported by SQL Server. |

### Blocking result set with `@ShowBlocking = 1`

A completely different result set. Only rows that are lead blockers, or that are blocked directly by a lead blocker or are part of a blocking chain caused by the lead blockers, are returned. Each row is labeled by block type (`Lead Blocker` or `Blocked`) and includes session id, blocking id, timing, command, status, wait type and time, last wait type, transaction count, isolation level, executed statement, batch or procedure, CPU, reads, writes, host, login, database, and program. This mode does not support output to a table (`@TableName`).

### Output to a table (`@TableName`)

When `@TableName` is supplied, the default result set is inserted into the specified table instead of being returned. If the table does not exist it will be automatically created using the following DDL (with supplied object names) that works with both formatted and raw (`@Raw`) output. The table will be created in the database specified in the `@TableName` parameter and will use the default file locations. 

```sql
CREATE TABLE [database].[schema].[table](
    [hhh:mm:ss] [char](9) NULL,
    [SessionID] [smallint] NOT NULL,
    [Executed Statement] [xml] NULL,
    [Batch or Procedure] [xml] NULL,
    [Query Plan] [xml] NULL,
    [Blocking ID] [smallint] NOT NULL,
    [CPU ms] [nvarchar](40) NULL,
    [Logical Reads] [nvarchar](40) NULL,
    [Writes] [nvarchar](40) NULL,
    [Status] [nvarchar](30) NOT NULL,
    [Wait Type] [nvarchar](60) NULL,
    [Wait ms] [nvarchar](40) NULL,
    [C Tempdb GB] [nvarchar](40) NULL,
    [H Tempdb GB] [nvarchar](40) NULL,
    [% Complete] [decimal](5,2) NULL,
    [DB Name] [nvarchar](128) NULL,
    [Program Name] [nvarchar](128) NULL,
    [Login Name] [nvarchar](128) NOT NULL,
    [Host Name] [nvarchar](128) NULL,
    [Row Count] [nvarchar](40) NULL,
    [Tran Count] [int] NULL,
    [DOP] [int] NULL,
    [Workers] [int] NULL,
    [Memory Grant MB] [nvarchar](40) NULL,
    [ISO Level] [varchar](30) NULL,
    [CaptureDT] [datetime] NOT NULL,
    [Login Mins] [decimal](10, 1) NULL,
    [Login DT] [datetime] NOT NULL,
    [Top Procedure] [nvarchar](4000) NULL
) ;
GO
CREATE CLUSTERED INDEX CIX_Table__CaptureDT
ON [database].[schema].[table]([CaptureDT])
WITH (DATA_COMPRESSION = PAGE) ;
```

Output formatting is controlled by `@Raw`: by default several numeric columns are converted to aligned, formatted strings for readability; with `@Raw = 1` they are returned as their native numeric values.

## Documentation

Full documentation: <https://straightpathsql.com/sp_check/sp_checkactivity/>

## Credits

Provided by **Straight Path IT Solutions, LLC**, <https://straightpathsql.com/>

Licensed under the MIT License. Copyright 2026 Straight Path IT Solutions, LLC.

# sp_Check

A suite of free T-SQL diagnostic stored procedures from [Straight Path Solutions](https://straightpathsql.com). Each `sp_Check*` procedure is a standalone, read-only script a DBA runs against a SQL Server instance to surface issues in one domain and return an ordered, plain-English list of findings with action steps and links to read more.

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![SQL Server](https://img.shields.io/badge/SQL%20Server-2016%20and%20later-CC2927?logo=microsoftsqlserver&logoColor=white)
![T-SQL](https://img.shields.io/badge/language-T--SQL-blue.svg)

## Navigation

| Procedure | What it checks |
| --- | --- |
| [sp_CheckActivity](#sp_checkactivity) | Live snapshot of active sessions, blocking, and long-running operation progress |
| [sp_CheckAG](#sp_checkag) | Availability Group configuration and failover readiness |
| [sp_CheckBackup](#sp_checkbackup) | Backup history, backup chains, and RPO gaps |
| [sp_CheckHealth](#sp_checkhealth) | General instance health across recoverability, security, availability, integrity, reliability, and performance |
| [sp_CheckSecurity](#sp_checksecurity) | Instance, login, and configuration vulnerabilities |
| [sp_CheckTempdb](#sp_checktempdb) | tempdb sizing, configuration, and IO stalls |

## Who are these scripts for?

These are for database administrators (and the accidental DBA) who want a fast, honest read on the state of a SQL Server instance without installing anything permanent or changing server state. Every procedure:

- Is **read-only** and safe to run in production. It runs with `SET NOCOUNT ON`, `READ UNCOMMITTED`, and `WITH RECOMPILE`, and does not modify server state.
- Returns findings ranked by **importance** (High, Medium, Low) with an `Issue`, `Details`, an `ActionStep`, and a `ReadMoreURL` for each item.
- Supports `@Help = 1` to print full documentation and the MIT license, and `@VersionCheck = 1` to return the version number and date.
- Uses a shared `@Mode` convention: `0` returns only problems, and `99` (the default) returns instance information plus all problems.

`sp_CheckActivity` is the one exception to the findings and `@Mode` conventions above. It is a live activity monitor that returns a snapshot of current sessions rather than prioritized findings.

They target **SQL Server 2016 and later**. Several checks also run on 2012 and 2014 (and, where noted, 2008 R2), and are skipped automatically on versions where the underlying feature does not exist. Azure SQL Managed Instance is detected and handled where relevant.

Installation is just running the `.sql` file for the procedure you want. You can create them in any database.

## sp_CheckActivity

Script: [sp_CheckActivity/sp_CheckActivity.sql](sp_CheckActivity/sp_CheckActivity.sql) &nbsp;|&nbsp; Documentation: [straightpathsql.com/sp_check/sp_checkactivity](https://straightpathsql.com/sp_check/sp_checkactivity/)

`sp_CheckActivity` shows the current activity of any sessions that have a currently executing request or an open transaction. It is a quick, low-resource snapshot of what is happening on an instance right now, and it is not meant to replace `sp_WhoIsActive`. Unlike the other procedures, it is a live activity monitor and does not return prioritized findings, so it has no `@Mode` and no CheckIDs. It covers areas such as:

- Active sessions and requests: elapsed time, the currently executing statement and its parent batch or procedure, status, wait type and time, blocking session, CPU, reads, writes, row count, transaction count, memory grant, isolation level, login, host, program, and session timing.
- tempdb consumption: space used per session by the current statement and the historical allocation since the session started.
- Blocking: a dedicated mode (`@ShowBlocking`) that returns lead blockers and the sessions they block, including blocking chains.
- Progress: a dedicated mode (`@ShowProgress`) that estimates completion time for backup, restore, DBCC, recovery, rollback, TDE encryption, and reorganize operations.
- Query plans for the currently running statement (`@Plans`), filtering by login or session ID, and saving results to a table (`@TableName`) for later analysis.

The suite build installs `sp_CheckActivity` in the `master` database rather than `DB_Administration`; it can be created in any database, but when using `@TableName` the table must be fully qualified (`[DB].[Schema].[Table]`) and is created if it does not exist. It is designed for SQL Server 2016 and later, runs on 2012 and 2014 (the `[DOP]` and `[Workers]` columns return NULL), and stops on earlier versions. The minimum permission required is `VIEW SERVER STATE`, plus `INSERT` on the target table when using `@TableName`.

### Parameters

| Parameter | Data type | Description | Valid inputs | Default |
| --- | --- | --- | --- | --- |
| `@Account` | NVARCHAR(128) | Return all requests for a login account | a login (`Domain\User`), or `NULL` for all | `NULL` |
| `@SessionID` | NVARCHAR(200) | Limit results to specific sessions | a SPID, or a comma-delimited string of SPIDs, or `NULL` for all | `NULL` |
| `@Plans` | BIT | Include the query plan for the currently running statement | `0`, `1` | `0` |
| `@FilterSleeping` | TINYINT | Which sleeping sessions to show | `0` = none, `1` = sleeping sessions with open transactions, `2` = all non-system sessions | `1` |
| `@ShowTopProc` | BIT | Show the top-most procedure when procedure calls are nested | `0`, `1` | `0` |
| `@TableName` | NVARCHAR(256) | Fully qualified table to insert the results into (created if it does not exist; not supported with `@ShowBlocking` or `@ShowProgress`) | `[DB].[Schema].[Table]`, or `NULL` | `NULL` |
| `@Raw` | BIT | Return unformatted output (numeric columns are not converted to formatted text) | `0`, `1` | `0` |
| `@ShowProgress` | BIT | Show only operations that report percent complete, with estimated completion time | `0`, `1` | `0` |
| `@ShowBlocking` | BIT | Show sessions that are blocking or being blocked, including the lead blocker | `0`, `1` | `0` |
| `@Help` | BIT | Print help and the MIT license, then return | `0`, `1` | `0` |
| `@VersionCheck` | BIT | Return the version number and date, then return | `0`, `1` | `0` |

[Back to top](#sp_check)

## sp_CheckAG

Script: [sp_CheckAG/sp_CheckAG.sql](sp_CheckAG/sp_CheckAG.sql) &nbsp;|&nbsp; Documentation: [straightpathsql.com/sp_check/sp_checkag](https://straightpathsql.com/sp_check/sp_checkag/)

`sp_CheckAG` checks your Availability Group(s) for problems and can also return a comprehensive set of information about them. It covers areas such as:

- Failover readiness: replicas and databases that are not failover ready, synchronous replicas that are not synchronized, disconnected replicas, and databases that are not joined or have data movement suspended.
- Cluster health: quorum member and vote counts, offline cluster members, and quorum configuration.
- Configuration drift: session timeouts at or below the default, backup preference not set to primary, mismatched seeding or failover modes, and Health Check Timeout values.
- Endpoints and certificates: endpoint ownership, stopped endpoints, and endpoint certificates that are expiring.
- Integrity and events: suspect pages, automatic page repair activity, high `HADR_SYNC_COMMIT` waits, secondary lag, and recent AG state changes.

With `@Mode = 1` or `99` it returns detailed result sets for the server, cluster, cluster members, endpoints, availability groups, listeners, replicas, and databases. Requires SQL Server 2016 or later. The minimum permissions required are `VIEW SERVER STATE` and `VIEW ANY DEFINITION`; some checks are skipped unless the executing user is a member of the `sysadmin` role.

### Parameters

| Parameter | Data type | Description | Valid inputs | Default |
| --- | --- | --- | --- | --- |
| `@Mode` | TINYINT | Which result set to return | `0` = problematic issues only, `1` = availability group information only, `2` = availability group history of events, `99` = information plus problematic issues | `99` |
| `@AGName` | NVARCHAR(128) | Limit results to a specific availability group | an availability group name, or `NULL` for all | `NULL` |
| `@LocalOnly` | BIT | Reduce results to local replicas and databases only | `1` = local only, `NULL` = all replicas | `NULL` |
| `@Help` | BIT | Print help and the MIT license, then return | `0`, `1` | `0` |
| `@VersionCheck` | BIT | Return the version number and date, then return | `0`, `1` | `0` |

[Back to top](#sp_check)

## sp_CheckBackup

Script: [sp_CheckBackup/sp_CheckBackup.sql](sp_CheckBackup/sp_CheckBackup.sql) &nbsp;|&nbsp; Documentation: [straightpathsql.com/sp_check/sp_checkbackup](https://straightpathsql.com/sp_check/sp_checkbackup/)

`sp_CheckBackup` reviews your SQL Server backup history for problems and lets you review that history in several ways. It covers areas such as:

- Missing coverage: databases with no full or log backups, and no recent full or log backups.
- Recovery Point Objective: databases that have not been backed up within an RPO you specify (in minutes).
- Backup chain integrity: split backup chains (backups landing in more than one location) and log backups written to the `NUL` device.
- Backup hygiene: compression and checksum settings, backups taken without checksum, and unpurged backup history in `msdb`.
- Recoverability: TDE and backup certificate backups and expirations, high VLF counts, integrity-check age, a stopped SQL Server Agent, and I/O freezes.

Availability Group backup preferences are respected so a non-preferred replica is not flagged for missing backups. The minimum permission required is `VIEW SERVER STATE`; some checks are skipped unless the executing user is a member of the `sysadmin` role.

### Parameters

| Parameter | Data type | Description | Valid inputs | Default |
| --- | --- | --- | --- | --- |
| `@Mode` | TINYINT | Which result set to return | `0` = issues only, `1` = one summary row per database, `2` = full backup history detail, `3` = backup chain check (look for any count greater than 1), `4` = results of 1, 2, and 3, `5` = restore history, `99` = results of 1 and 0 | `99` |
| `@ShowCopyOnly` | BIT | Filter copy-only backups | `0` = hide copy-only, `1` = only copy-only, `NULL` = all | `NULL` |
| `@DatabaseName` | NVARCHAR(128) | Limit results to a single database | a database name, or `NULL` for all | `NULL` |
| `@BackupType` | CHAR(1) | Filter by backup type | `'F'` = Full, `'D'` = Differential, `'L'` = Log | `NULL` |
| `@DeviceType` | VARCHAR(30) | Filter by backup device | `'Disk'`, `'Tape'`, `'Virtual Device'`, `'Azure Storage'` | `NULL` |
| `@StartDate` | DATETIME | Start of the date range to examine | any datetime | 7 days before now |
| `@EndDate` | DATETIME | End of the date range to examine | any datetime | now |
| `@RPO` | INT | Recovery Point Objective in minutes; flags databases not backed up within it | a number of minutes, or `NULL` to skip | `NULL` |
| `@Override` | BIT | Allow the checks to run on instances with more than 50 databases | `0`, `1` | `0` |
| `@Help` | BIT | Print help and the MIT license, then return | `0`, `1` | `0` |
| `@VersionCheck` | BIT | Return the version number and date, then return | `0`, `1` | `0` |

[Back to top](#sp_check)

## sp_CheckHealth

Script: [sp_CheckHealth/sp_CheckHealth.sql](sp_CheckHealth/sp_CheckHealth.sql) &nbsp;|&nbsp; Documentation: [straightpathsql.com/sp_check/sp_checkhealth](https://straightpathsql.com/sp_check/sp_checkhealth/)

`sp_CheckHealth` checks a SQL Server instance for a broad range of problems and returns a prioritized list of findings with action items, and can also return a comprehensive set of instance information on its own. It covers areas such as:

- Recoverability: missing or stale full and log backups, failed backups, compression and checksum defaults, TDE and backup-certificate backups and expirations, unpurged backup history, and high VLF counts.
- Security: invalid Windows logins, unknown or mismatched database owners, an enabled `sa` account, and remote admin connections.
- Availability and integrity: databases in single-user, restricted-user, read-only, offline, or suspect states, endpoint and Availability Group ownership, page verification not set to CHECKSUM, missing alerts, missing `DBCC CHECKDB`, and recorded corruption.
- Reliability: missing updates, unsupported versions, long uptime, files on the C drive, file growth and placement, SQL Agent job and service health, memory configuration, drive space, replication, and pending configuration changes.
- Performance: parallelism settings, auto shrink/close, compatibility level, trace flag recommendations, tempdb file configuration and I/O stalls, power plan, instant file initialization, lock pages in memory, Resource Governor, delayed durability, and I/O freezes.

With `@Mode = 1` or `11` it returns instance discovery information (server and instance name, version, edition, build, paths, CPU, memory, OS, service accounts, and more), the one-row mode being useful for inventory collection. The minimum permissions required are `VIEW SERVER STATE` and `VIEW ANY DEFINITION`; some checks are skipped unless the executing user is a member of the `sysadmin` role.

### Parameters

| Parameter | Data type | Description | Valid inputs | Default |
| --- | --- | --- | --- | --- |
| `@Mode` | TINYINT | Which result set to return | `0` = problematic issues only, `1` = instance information only, `11` = instance information only in one row, `99` = information plus problematic issues, as two result sets | `99` |
| `@DatabaseName` | NVARCHAR(255) | Limit database-specific checks to a single database | a database name, or `NULL` for all | `NULL` |
| `@Override` | BIT | Allow the checks to run on instances with more than 50 databases | `0`, `1` | `0` |
| `@Help` | BIT | Print help and the MIT license, then return | `0`, `1` | `0` |
| `@VersionCheck` | BIT | Return the version number and date, then return | `0`, `1` | `0` |

[Back to top](#sp_check)

## sp_CheckSecurity

Script: [sp_CheckSecurity/sp_CheckSecurity.sql](sp_CheckSecurity/sp_CheckSecurity.sql) &nbsp;|&nbsp; Documentation: [straightpathsql.com/sp_check/sp_checksecurity](https://straightpathsql.com/sp_check/sp_checksecurity/)

`sp_CheckSecurity` checks your SQL Server for several dozen possible vulnerabilities and returns an ordered list with explanations and action items. It covers areas such as:

- Elevated access: members of `sysadmin` and `securityadmin`, `CONTROL SERVER`, `IMPERSONATE ANY LOGIN`, and `ALTER ANY LOGIN`.
- Login weaknesses: an enabled `sa`, blank or weak passwords, invalid Windows logins, and failed-login auditing.
- Risky configuration: CLR, OLE Automation, cross-database ownership chaining, ad hoc distributed queries, and Configuration Manager settings (Hide Instance, Force Encryption, Extended Protection).
- Ownership and trust: `TRUSTWORTHY` databases, database and job ownership, linked server security context, and TDE certificate backups.
- Service accounts: service accounts in the `sysadmin` role, in the local Administrators group, or running as a built-in elevated account.

The executing user must be a member of the `sysadmin` role; the procedure aborts otherwise.

### Parameters

| Parameter | Data type | Description | Valid inputs | Default |
| --- | --- | --- | --- | --- |
| `@Mode` | TINYINT | Which result set to return | `0` = all discovered vulnerabilities, `1` = instance information only, `2` = high-importance only, `99` = information plus all vulnerabilities | `99` |
| `@CheckLocalAdmin` | BIT | Read the members of the local Administrators group. If `BUILTIN\Administrators` is not already a login, it is added inside an explicit transaction that **always rolls back**. | `0` = do not check, `1` = check | `0` |
| `@PreferredDBOwner` | NVARCHAR(255) | The login you expect to own your databases; flags any database owned by something else | a login name, or `NULL` to skip the check | `NULL` |
| `@Override` | BIT | Allow the checks to run on instances with more than 50 databases | `0`, `1` | `0` |
| `@Help` | BIT | Print help and the MIT license, then return | `0`, `1` | `0` |
| `@VersionCheck` | BIT | Return the version number and date, then return | `0`, `1` | `0` |

[Back to top](#sp_check)

## sp_CheckTempdb

Script: [sp_CheckTempdb/sp_CheckTempdb.sql](sp_CheckTempdb/sp_CheckTempdb.sql) &nbsp;|&nbsp; Documentation: [straightpathsql.com/sp_check/sp_checktempdb](https://straightpathsql.com/sp_check/sp_checktempdb/)

`sp_CheckTempdb` checks your tempdb database for problems and provides findings with action items, or lets you review the current state of tempdb in a few ways for troubleshooting. It covers areas such as:

- File layout: data file count versus CPU cores, more than 16 data files, unevenly sized files, uneven growth settings, multiple log files, and files on the C drive.
- Growth and limits: percentage growth rates, growth increments smaller than 64 MB, files with no growth allowed, and maximum size limits.
- Performance and contention: high file usage, slow read and write stalls, allocation and metadata contention (SQL Server 2019 and later), and trace flags 1117 and 1118 on older versions.
- Configuration: memory-optimized tempdb metadata, Resource Governor limits on tempdb, Accelerated Database Recovery, and whether tempdb is encrypted.

With `@Mode = 2` it summarizes what is currently consuming tempdb space and log, by session and by transaction. The minimum permissions required are `VIEW SERVER STATE` and `VIEW ANY DEFINITION`.

### Parameters

| Parameter | Data type | Description | Valid inputs | Default |
| --- | --- | --- | --- | --- |
| `@Mode` | TINYINT | Which result set to return | `0` = problematic issues only, `1` = summary of all tempdb files, `2` = what is currently using tempdb space (data and log), `3` = tempdb contention (SQL Server 2019 and later only), `99` = results of 1 and 0 | `99` |
| `@Size` | CHAR(2) | Units used to display sizes for `@Mode = 2` | `'MB'`, `'GB'` | `'MB'` |
| `@UsagePercent` | TINYINT | Usage percentage of a tempdb file at which to flag it | `0` to `100` | `50` |
| `@AvgReadStallMs` | INT | Average read stall in milliseconds to report on if exceeded | `0` or greater | `100` |
| `@AvgWriteStallMs` | INT | Average write stall in milliseconds to report on if exceeded | `0` or greater | `100` |
| `@VersionStorePercent` | TINYINT | Percentage of the tempdb data file size used by the version store at which to flag it (at least 1 GB must be reserved) | `0` to `100` | `25` |
| `@Help` | BIT | Print help and the MIT license, then return | `0`, `1` | `0` |
| `@VersionCheck` | BIT | Return the version number and date, then return | `0`, `1` | `0` |

[Back to top](#sp_check)

## License

These procedures are provided under the MIT License. See the license text printed by each procedure with `@Help = 1`. Portions of some procedures are copyright their original authors (Microsoft's tigertoolbox and Brent Ozar Unlimited's sp_Blitz) and are used under the MIT License. All other copyrights are held by Straight Path IT Solutions, LLC.

[Back to top](#sp_check)

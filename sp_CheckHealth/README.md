# sp_CheckHealth

`sp_CheckHealth` checks a SQL Server instance for a broad range of recoverability, security, availability, integrity, reliability, and performance issues and returns a prioritized list of findings with action items. It can also return a comprehensive set of instance information on its own. It is part of the free [Straight Path IT Solutions](https://straightpathsql.com/) `sp_Check*` suite.

## Features

- Collects **instance discovery information**: server and instance name, version, edition, build, error log location, default data/log/backup paths, trace flags, protocol, last restart, CPU, memory, OS, service accounts, instance count, IP address, and server type.
- Checks **recoverability**: missing or stale full and log backups, failed backups, backup compression and checksum defaults, TDE and backup-certificate backup and expiration, unpurged backup history, and high VLF counts.
- Checks **security**: invalid Windows logins, unknown or mismatched database owners, an enabled `sa` account, and remote admin connections.
- Checks **availability**: databases in single-user, restricted-user, read-only, offline, or suspect states, and endpoint and Availability Group ownership.
- Checks **integrity**: page verification not set to CHECKSUM, missing severity/error alerts, missing `DBCC CHECKDB`, recorded corruption, and disabled alerts.
- Checks **reliability**: missing updates, unsupported versions, long uptime, files on the C drive, file growth and placement, SQL Agent job and service health, memory configuration, drive space, replication, snapshots, pending config changes, memory dumps, and more.
- Checks **performance**: parallelism settings, auto shrink/close, compatibility level, trace flag recommendations, tempdb file configuration and I/O stalls, power plan, instant file initialization, lock pages in memory, statistics settings, Resource Governor, triggers, change tracking / CDC, delayed durability, custom Extended Events, and I/O freezes.
- Supports filtering to a single database and a one-row instance information mode for inventory collection.

## Requirements

- **SQL Server version:** Designed for **SQL Server 2014 (12.x) or later**. It runs on earlier versions but skips some checks (there is no hard version abort; the version guard is commented out in the code). Version-gated checks include:
  - Database-backup-certificate checks require **SQL Server 2014 (12.x)+** (`>= 12`).
  - High VLF count check requires **SQL Server 2016 (13.x)+** (`>= 13`).
  - Availability Group ownership check requires **SQL Server 2012 (11.x)+** (`>= 11`).
  - Trace flag recommendations vary by version (2371 below 2016; 7752 on 2016/2017; 7745 on 2016+; 1117 / 1118 below 2016).
  - Memory-optimized tempdb metadata check requires **SQL Server 2019 (15.x)+** (`>= 15`).
  - Alert and edition-specific checks key off `SERVERPROPERTY('EngineEdition')`, and several checks skip Azure SQL Managed Instance (EngineEdition 8).
- **Permissions:** The minimum required is **VIEW SERVER STATE** and **VIEW ANY DEFINITION**. Note that some checks will be skipped unless executed by a member of **sysadmin**.
- **Database count guard:** Instances with **more than 50 databases** require `@Override = 1` (this guard is skipped for `@Mode = 11`), since gathering backup history can be resource-intensive.

## Parameters

| Name | Data Type | Default | Description |
|------|-----------|---------|-------------|
| `@Mode` | `TINYINT` | `99` | Output mode. `0` = problem findings only (unfiltered); `1` = instance information only; `11` = instance information only as a single row; `99` = instance information and problem findings (default). |
| `@DatabaseName` | `NVARCHAR(255)` | `NULL` | Restrict database-specific checks to a single database. |
| `@Override` | `BIT` | `0` | Set to `1` to proceed on instances with more than 50 databases. |
| `@Help` | `BIT` | `0` | Print help text (purpose, parameters, license) and exit. |
| `@VersionCheck` | `BIT` | `0` | Return the procedure's version number and date, then exit. |

This procedure has no `OUTPUT` parameters.

## Usage

```sql
-- Default run: instance information plus all problem findings
EXEC dbo.sp_CheckHealth;

-- Problem findings only, scoped to a single database
EXEC dbo.sp_CheckHealth
      @Mode = 0
    , @DatabaseName = N'Sales';

-- One-row instance information snapshot (useful for inventory collection)
EXEC dbo.sp_CheckHealth
      @Mode = 11;
```

## Priority System

Every finding is assigned a priority (the `Importance` column):

| Priority | Meaning |
|----------|---------|
| 0 | Informational |
| 1 | High |
| 2 | Medium |
| 3 | Low |

## Checks

Findings are returned in modes `0` and `99`. CheckIDs are grouped into series by category (`2xx` = Recoverability, `3xx` = Security, `4xx` = Availability, `5xx` = Integrity, `6xx` = Reliability, `7xx` = Performance). Series `1xx` is Discovery (instance information shown in modes `1`, `11`, and `99`, not problem findings).

### 2xx - Recoverability

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 203 | [Missing full backup](https://straightpathsql.com/check/missing-backups) | 1 (High) | A database has never had a full backup. |
| 204 | [Missing log backup](https://straightpathsql.com/check/missing-backups) | 1 (High) | A database in Full or Bulk-Logged recovery has never had a transaction log backup. |
| 205 | [No recent full backup](https://straightpathsql.com/check/recovery-point-objective) | 1 (High) | A database has had no full backup in the last 7 days. |
| 206 | [No recent log backup](https://straightpathsql.com/check/recovery-point-objective) | 1 (High) | A database in Full or Bulk-Logged recovery has had no log backup in the last 24 hours. |
| 207 | [Failed database backups](https://straightpathsql.com/check/failed-backup) | 1 (High) | The SQL Server error log shows a backup failure. |
| 208 | [Backup compression](https://straightpathsql.com/check/backup-compression) | 2 (Medium) | The `backup compression` / `backup compression default` configuration is not enabled. |
| 209 | [Backup checksum](https://straightpathsql.com/check/backup-checksum) | 2 (Medium) | The `backup checksum` / `backup checksum default` configuration is not enabled. |
| 210 | [Database backup certificate (never / not recently backed up)](https://straightpathsql.com/check/missing-database-backup-certificate-backup) | 1 (High) | A certificate used to encrypt database backups has never been backed up, or not in the last 90 days (SQL Server 2014+). |
| 211 | [TDE certificate (never / not recently backed up)](https://straightpathsql.com/check/no-recent-tde-certificate-backup) | 1 (High) | A TDE certificate required for restoring has never been backed up, or not in the last 90 days. |
| 212 | [Database backup certificate set to expire](https://straightpathsql.com/check/database-backup-certificate-expiration-date) | 1 (High) | A certificate used to encrypt database backups is set to expire (SQL Server 2014+). |
| 213 | [TDE certificate set to expire](https://straightpathsql.com/check/tde-certificate-expiration-date) | 2 (Medium) | A TDE certificate required for restoring is set to expire. |
| 216 | [Backup history not purged](https://straightpathsql.com/check/backup-history-not-purged) | 2 (Medium) | `msdb` backup history is retained beyond 90 days, which can bloat `msdb`. |
| 217 | [High VLF count](https://straightpathsql.com/check/virtual-log-files) | 2 (Medium) | A database's transaction log has more than 200 virtual log files (SQL Server 2016+). |

### 3xx - Security

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 304 | [Invalid login with Windows Authentication](https://straightpathsql.com/check/invalid-windows-login) | 3 (Low) | A login with permissions is no longer mapped to a valid Windows user or group. |
| 305 | [Database Owner is Unknown](https://straightpathsql.com/check/database-owner-blank) | 3 (Low) | A database owner SID does not resolve to a login (blank owner). |
| 306 | [Database owner discrepancy](https://straightpathsql.com/check/database-owner-discrepancy) | 3 (Low) | The database owner differs from the owner recorded in master. |
| 307 | [Enabled sa account](https://straightpathsql.com/check/sa-login-enabled) | 1 (High) | The `sa` login is enabled for connections. |
| 310 | [Remote admin connection](https://straightpathsql.com/check/remote-dedicated-admin-connections) | 2 (Medium) | The `remote admin connections` configuration is not enabled. |

### 4xx - Availability

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 401 | [Database in single user mode](https://straightpathsql.com/check/single-user-mode) | 1 (High) | A database is set to SINGLE_USER. |
| 402 | [Database in restricted user mode](https://straightpathsql.com/check/restricted-user-mode) | 1 (High) | A database is set to RESTRICTED_USER. |
| 403 | [Database in read-only mode](https://straightpathsql.com/check/read-only-mode) | 2 (Medium) | A database is read-only and cannot accept transactions. |
| 404 | [Database offline](https://straightpathsql.com/check/database-offline) | 2 (Medium) | A database is offline. |
| 405 | [Database suspect](https://straightpathsql.com/check/suspect-status) | 1 (High) | A database is in a suspect state, possibly from hardware failure or corruption. |
| 406 | [Endpoint owner](https://straightpathsql.com/check/endpoint-ownership) | 1 (High) | An endpoint is owned by a login other than sa. |
| 407 | [Availability Group owner](https://straightpathsql.com/check/availability-group-ownership) | 1 (High) | An Availability Group is owned by a login other than sa (SQL Server 2012+). |

### 5xx - Integrity

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 501 | [Page verification not set to CHECKSUM](https://straightpathsql.com/check/database-page-verification) | 1 (High) | A database uses a page verification option other than CHECKSUM. |
| 502 | [Alert missing](https://straightpathsql.com/check/alerts) | 1 (High) | An alert is missing for a severity (19-25) or message (823, 824, 825) error (Developer, Standard, Enterprise, or Managed Instance). |
| 503 | [Missing integrity checks](https://straightpathsql.com/check/missing-integrity-checks) | 1 (High) | A database has not had a successful `DBCC CHECKDB` in the last 2 weeks. |
| 504 | [Corruption detected](https://straightpathsql.com/check/database-corruption) | 1 (High) | A database has at least one corrupt page recorded in the last 30 days. |
| 505 | [Disabled alerts](https://straightpathsql.com/check/alerts) | 2 (Medium) | A SQL Agent alert is currently disabled. |

### 6xx - Reliability

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 601 | [SQL Server update available](https://straightpathsql.com/check/security-update) | 1 (High) | A recent cumulative update or GDR has not been applied (not Azure SQL Managed Instance). |
| 602 | [Unsupported version of SQL Server](https://straightpathsql.com/check/unsupported-versions) | 1 (High) | The SQL Server version is out of the support life cycle (not Azure SQL Managed Instance). |
| 603 | [Instance online over 180 days](https://straightpathsql.com/check/instance-uptime) | 3 (Low) | The instance has not been restarted in over 180 days. |
| 604 | [tempdb files on the C drive](https://straightpathsql.com/check/tempdb-files-on-c-drive) | 1 (High) | A tempdb file is on the C drive while other drives are available. |
| 605 | [tempdb file with no growth allowed](https://straightpathsql.com/check/tempdb-no-growth-allowed) | 2 (Medium) | A tempdb file is not allowed to grow beyond its current size. |
| 606 | [User database file on the C drive](https://straightpathsql.com/check/database-files-best-practice) | 1 (High) | A user database file is on the C drive while other drives are available. |
| 607 | [User database file with no growth allowed](https://straightpathsql.com/check/database-files-best-practice) | 2 (Medium) | A user database file is not allowed to grow beyond its current size. |
| 608 | [User database log and data files are on the same drive](https://straightpathsql.com/check/database-files-best-practice) | 2 (Medium) | A database has both log and data files on the same (non-C) drive. |
| 609 | [SQL Agent job schedule is disabled](https://straightpathsql.com/check/sql-agent-job-schedule) | 2 (Medium) | An enabled SQL Agent job has one or more disabled schedules. |
| 610 | [SQL Agent job is enabled without a schedule](https://straightpathsql.com/check/sql-agent-job-schedule) | 2 (Medium) | An enabled SQL Agent job has no schedule. |
| 611 | [SQL Agent jobs owned by users](https://straightpathsql.com/check/sql-agent-jobs-owned-by-users) | 2 (Medium) | An enabled SQL Agent job is owned by a user login rather than sa. |
| 612 | [Default data file path is on the C drive](https://straightpathsql.com/check/default-file-path) | 2 (Medium) | The instance default data file path is on the C drive while other drives are available. |
| 613 | [Default log file path is on the C drive](https://straightpathsql.com/check/default-file-path) | 2 (Medium) | The instance default log file path is on the C drive while other drives are available. |
| 614 | [Default backup file path is on the C drive](https://straightpathsql.com/check/default-file-path) | 2 (Medium) | The instance default backup file path is on the C drive while other drives are available. |
| 615 | [Min and max memory settings](https://straightpathsql.com/check/memory-best-practices) | 2 (Medium) | The min and max server memory settings are equal. |
| 616 | [Max memory setting](https://straightpathsql.com/check/memory-best-practices) | 2 (Medium) | Max server memory is at the default of 2 PB, allowing SQL Server to consume all memory. |
| 617 | [Server name discrepancy](https://straightpathsql.com/check/server-name) | 2 (Medium) | `@@SERVERNAME` does not match `SERVERPROPERTY('ServerName')`. |
| 618 | [Low drive space](https://straightpathsql.com/check/low-drive-space) | 1 (High) | A drive has less than 10 percent free space. |
| 620 | [Database file with max size set](https://straightpathsql.com/check/database-max-file-size) | 2 (Medium) | A user database file has a max size set below the 2 TB default (excludes tempdb and DB_Administration). |
| 621 | [Evaluation Edition](https://straightpathsql.com/check/evaluation-edition) | 1 (High) | The instance is running an Evaluation edition that will expire. |
| 622 | [Number of error logs](https://straightpathsql.com/check/number-of-sql-server-error-log-files) | 2 (Medium) | The instance is configured to retain 6 or fewer error logs. |
| 623 | [Replication enabled](https://straightpathsql.com/check/replication) | 2 (Medium) | A database is configured as a replication publisher, subscriber, merge publisher, or distributor. |
| 624 | [Low available physical memory](https://straightpathsql.com/check/memory-best-practices) | 1 (High) | The server has less than 1 GB of available physical memory. |
| 625 | [Database Snapshot found](https://straightpathsql.com/check/database-snapshot) | 2 (Medium) | A database snapshot exists, whose files grow as the source database changes. |
| 626 | [Pending configuration change](https://straightpathsql.com/check/instance-configurations) | 2 (Medium) | A configuration value differs from the value in use and has not been applied with RECONFIGURE. |
| 627 | [Unusual database state](https://straightpathsql.com/check/unusual-database-state) | 2 (Medium) | A database is in a state other than ONLINE or OFFLINE (for example, RESTORING). |
| 628 | [SQL Server Agent offline](https://straightpathsql.com/check/sql-agent-offline) | 1 (High) | The SQL Server Agent service is not running (excluding Express Edition). |
| 629 | [Recent memory dumps](https://straightpathsql.com/check/memory-dumps) | 1 (High) | SQL Server has produced memory dumps in the last 90 days, a sign of instability. |
| 630 | [User database with logical file named 'master'](https://desertdba.com/failovers-cant-serve-two-masters/) | 1 (High) | A non-master database has a file with the logical name 'master', which can break SQL Server updates. |
| 631 | [Priority Boost enabled](https://straightpathsql.com/check/priority-boost) | 1 (High) | The priority boost configuration is enabled, which Microsoft recommends disabling. |
| 632 | [System database below installed compatibility level](https://straightpathsql.com/check/system-database-compatibility-level) | 1 (High) | A system database has a compatibility level below the installed version. |

### 7xx - Performance

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 701 | [Cost threshold for parallelism](https://straightpathsql.com/check/cost-threshold-for-parallelism) | 2 (Medium) | Cost threshold for parallelism is at the default of 5. |
| 702 | [Max degree of parallelism](https://straightpathsql.com/check/max-degree-of-parallelism) | 2 (Medium) | MAXDOP is at the default of 0, or is set to 1. |
| 703 | [Auto shrink enabled](https://straightpathsql.com/check/auto-shrink) | 2 (Medium) | A database has AUTO_SHRINK enabled. |
| 704 | [Auto close enabled](https://straightpathsql.com/check/auto-close) | 2 (Medium) | A database has AUTO_CLOSE enabled. |
| 705 | [Lower compatibility level](https://straightpathsql.com/check/compatibility-level) | 2 (Medium) | A database has a compatibility level below the instance level. |
| 706 | [Trace flag recommendations](https://straightpathsql.com/check/trace-flags) | 2 (Medium) | A recommended trace flag is not enabled globally (2371 below 2016; 7752 on 2016/2017; 7745 on 2016+; 3226 on all versions). |
| 707 | [Number of tempdb data files not recommended](https://straightpathsql.com/check/tempdb-data-file-growth) | 1 (High) | The tempdb data file count does not match Microsoft's guidance (equal to CPU cores up to 8). |
| 708 | [Unequally sized tempdb data files](https://straightpathsql.com/check/tempdb-data-file-size) | 1 (High) | tempdb data files are not all the same size. |
| 709 | [Uneven tempdb growth rates](https://straightpathsql.com/check/tempdb-data-file-growth) | 1 (High) | tempdb data files have differing growth settings. |
| 710 | [tempdb log file larger than data files](https://straightpathsql.com/check/tempdb-log-file-size) | 2 (Medium) | The tempdb log file is larger than its data files. |
| 711 | [tempdb file with percentage growth rates](https://straightpathsql.com/check/tempdb-data-file-growth) | 1 (High) | A tempdb file uses percentage growth. |
| 712 | [tempdb file with growth rates less than 64 MB](https://straightpathsql.com/check/tempdb-data-file-growth) | 1 (High) | A tempdb file has a fixed growth rate under 64 MB. |
| 713 | [Multiple log files (tempdb)](https://straightpathsql.com/check/tempdb-multiple-log-files) | 1 (High) | tempdb has more than one log file. |
| 714 | [tempdb file with high usage](https://straightpathsql.com/check/tempdb-files-with-high-usage) | 1 (High) | A tempdb file exceeds 50 percent space usage. |
| 715 | [Trace Flag 1117](https://straightpathsql.com/check/trace-flag-1117) | 2 (Medium) | Trace flag 1117 is not enabled globally (versions before SQL Server 2016). |
| 716 | [Trace Flag 1118](https://straightpathsql.com/check/trace-flag-1118) | 2 (Medium) | Trace flag 1118 is not enabled globally (versions before SQL Server 2016). |
| 717 | [Memory-optimized tempdb metadata](https://straightpathsql.com/check/tempdb-memory-optimized) | 2 (Medium) | Memory-optimized tempdb metadata is enabled (SQL Server 2019+). |
| 718 | [Slow reads](https://straightpathsql.com/check/tempdb-slow-reads-and-writes) | 1 (High) | A tempdb file has an average read stall above 100 ms. |
| 719 | [Slow writes](https://straightpathsql.com/check/tempdb-slow-reads-and-writes) | 1 (High) | A tempdb file has an average write stall above 100 ms. |
| 720 | [Database log file larger than data files](https://straightpathsql.com/check/database-log-file-size) | 2 (Medium) | A user database has a log file larger than its data files (and larger than 100 MB). |
| 721 | [Database file with percentage growth rates](https://straightpathsql.com/check/database-file-growth) | 1 (High) | A user database file uses percentage growth. |
| 722 | [Database file with growth rates less than 64 MB](https://straightpathsql.com/check/database-file-growth) | 1 (High) | A user database file has a fixed growth rate under 64 MB (excludes master and msdb). |
| 723 | [Multiple log files](https://straightpathsql.com/check/database-multiple-log-files) | 1 (High) | A database has more than one log file. |
| 724 | [Power plan not optimal](https://straightpathsql.com/check/power-plan) | 1 (High) | The Windows power plan is not set to High Performance. |
| 725 | [Instant file initialization](https://straightpathsql.com/check/instant-file-initialization) | 1 (High) | Instant file initialization is not enabled. |
| 726 | [Lock pages in memory](https://straightpathsql.com/check/lock-pages-in-memory) | 2 (Medium) | The instance has pages locked in memory, a non-default setting. |
| 728 | [Auto create statistics is disabled](https://straightpathsql.com/check/auto-create-statistics) | 2 (Medium) | A database has auto creation of statistics disabled. |
| 729 | [Offline CPU schedulers](https://straightpathsql.com/check/offline-cpu-schedulers) | 1 (High) | SQL Server is not using all available CPU cores due to licensing or configuration. |
| 731 | [Resource Governor enabled](https://straightpathsql.com/check/resource-governor) | 2 (Medium) | The Resource Governor feature is enabled. |
| 732 | [Enabled server-level triggers](https://straightpathsql.com/check/server-level-triggers) | 2 (Medium) | A non-shipped server-level trigger is enabled. |
| 733 | [Change Tracking enabled](https://straightpathsql.com/check/change-tracking) | 2 (Medium) | A database has tables with Change Tracking enabled. |
| 734 | [Recursive triggers enabled](https://straightpathsql.com/check/recursive-triggers) | 2 (Medium) | A database has recursive triggers enabled. |
| 735 | [Forced parameterization enabled](https://straightpathsql.com/check/forced-parameterization) | 2 (Medium) | A database has forced parameterization enabled. |
| 736 | [Change Data Capture enabled](https://straightpathsql.com/check/change-data-capture) | 2 (Medium) | A database has Change Data Capture (CDC) enabled. |
| 737 | [Delayed durability enabled](https://straightpathsql.com/check/delayed-durability) | 2 (Medium) | A database has delayed durability enabled, risking transaction loss on a crash. |
| 738 | [Custom Extended Events running](https://straightpathsql.com/check/extended-events) | 2 (Medium) | A non-default Extended Events session is running. |
| 739 | [I/O freeze detected](https://straightpathsql.com/check/i-o-freeze) | 2 (Medium) | The error log shows I/O freeze/resume events, usually from VSS-based backups. |
| 740 | [Auto update statistics is disabled](https://straightpathsql.com/check/auto-update-statistics) | 2 (Medium) | A database has auto update of statistics disabled. |
| 742 | [Locked Pages In Memory with max memory at default](https://straightpathsql.com/check/lock-pages-in-memory) | 2 (Medium) | The instance has pages locked in memory while maximum server memory is at the default, so SQL Server can lock all physical memory and starve the operating system. |

## Results Organization

CheckID series map to categories: **1xx Discovery**, **2xx Recoverability**, **3xx Security**, **4xx Availability**, **5xx Integrity**, **6xx Reliability**, **7xx Performance**. The result set(s) returned depend on `@Mode`:

- **Instance information and findings** (modes `0`, `1`, `99`): a single result set from the `#Results` table joined to categories, ordered by Importance, then category, CheckID, issue, and database. Columns: `CategoryName`, `Importance`, `CheckName`, `Issue`, `DatabaseName`, `Details`, `ActionStep`, `ReadMoreURL`, `CheckID`. Mode `1` returns only the Discovery rows; mode `0` returns only the problem findings; mode `99` returns both.
- **One-row instance information** (mode `11`): a single pivoted row of instance information (server name, instance name, version, edition, build, error log location, default paths, trace flags in use, protocol, last restart, CPU, memory, OS, server type, service accounts, IP address), suitable for inventory collection.

## Documentation

Full documentation: <https://straightpathsql.com/sp_check/sp_checkhealth/>

## Credits

Provided by **Straight Path IT Solutions, LLC**, <https://straightpathsql.com/>

Portions are derived from `sp_Blitz` (Brent Ozar Unlimited) and are used under the MIT License. Licensed under the MIT License. Copyright 2026 Straight Path IT Solutions, LLC.

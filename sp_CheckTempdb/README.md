# sp_CheckTempdb

`sp_CheckTempdb` checks your SQL Server `tempdb` database for configuration and performance issues and returns a list of findings with action items, or lets you review the current state of `tempdb` in several different ways when you need to troubleshoot. It is part of the free [Straight Path IT Solutions](https://straightpathsql.com/) `sp_Check*` suite.

## Features

- Flags **data file count** problems: not matching CPU cores (up to 8), more than 16 files, unequally sized files, and uneven growth settings.
- Detects risky **file growth configuration**: no growth allowed, a max size set, percentage growth rates, and fixed growth rates under 64 MB.
- Surfaces **file placement and log issues**: tempdb files on the C drive, multiple log files, and a log file larger than the data files.
- Reports **I/O performance**: files exceeding configurable average read and write stall thresholds, and files exceeding a configurable usage percentage.
- Checks **version-specific configuration**: trace flags 1117 / 1118 (pre-2016), memory-optimized tempdb metadata (2019+), and Resource Governor tempdb limits plus Accelerated Database Recovery (2025+).
- Notes **instance hygiene**: tempdb encryption (inherited from TDE) and an instance online more than 180 days.
- Provides review modes for tempdb **file properties**, current **space usage** (by file, session, and transaction, in MB or GB), and **allocation / metadata contention** (2019+).

## Requirements

- **SQL Server version:** Designed for **SQL Server 2016 (13.x) or later**. It runs on **SQL Server 2012 (11.x)+** and on Azure SQL Managed Instance; execution is aborted on anything older (`@SQLVersionMajor < 11` and not Azure SQL Managed Instance). Some checks are version-gated:
  - Trace flag 1117 / 1118 checks apply only to **versions before SQL Server 2016** (`< 13`) and not Azure SQL Managed Instance.
  - Memory-optimized tempdb metadata check requires **SQL Server 2019 (15.x)+** (`>= 15`).
  - Resource Governor tempdb-limit and Accelerated Database Recovery checks require **SQL Server 2025 (17.x)+** (`>= 17`).
  - `@Mode = 3` (contention) requires **SQL Server 2019 (15.x)+** or Azure SQL Managed Instance; it is aborted on older versions.
- **Permissions:** `VIEW SERVER STATE` and `VIEW ANY DEFINITION` are required.
- Azure SQL Managed Instance is handled specially: the service tier is read from `sys.server_resource_stats`, the data-file-count checks are skipped (Managed Instance defaults to 12 files), and the log max-size ceiling is adjusted for the General Purpose tier.

## Parameters

| Name | Data Type | Default | Description |
|------|-----------|---------|-------------|
| `@Mode` | `TINYINT` | `99` | Output mode. `0` = problem findings only (unfiltered); `1` = summary properties for all tempdb files; `2` = what is currently using space in tempdb (data and log files); `3` = tempdb contention check (SQL Server 2019+ only); `99` = modes 1 and 0 combined (default). |
| `@Size` | `CHAR(2)` | `'MB'` | Unit for `@Mode = 2` sizes: `'MB'` (megabytes) or `'GB'` (gigabytes). Any other value falls back to `'MB'`. |
| `@UsagePercent` | `TINYINT` | `50` | Usage percentage (0-100) of a tempdb file at which to raise the high-usage finding (CheckID 714). Values over 100 are clamped to 100. |
| `@AvgReadStallMs` | `INT` | `100` | Average read stall in milliseconds above which a file is reported as having slow reads (CheckID 718). Negative values are clamped to 0. |
| `@AvgWriteStallMs` | `INT` | `100` | Average write stall in milliseconds above which a file is reported as having slow writes (CheckID 719). Negative values are clamped to 0. |
| `@Help` | `BIT` | `0` | Print help text (purpose, parameters, license) and exit. |
| `@VersionCheck` | `BIT` | `0` | Return the procedure's version number and date, then exit. |

This procedure has no `OUTPUT` parameters.

## Usage

```sql
-- Default run: tempdb file properties plus a list of tempdb problems
EXEC dbo.sp_CheckTempdb;

-- See what is currently consuming tempdb space, reported in gigabytes
EXEC dbo.sp_CheckTempdb
      @Mode = 2
    , @Size = 'GB';

-- Problem findings only, with stricter usage and I/O stall thresholds
EXEC dbo.sp_CheckTempdb
      @Mode = 0
    , @UsagePercent = 80
    , @AvgReadStallMs = 50
    , @AvgWriteStallMs = 50;
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

Findings are returned in modes `0` and `99`. CheckIDs are grouped into series by category (`3xx` = Security, `6xx` = Reliability, `7xx` = Performance).

### 3xx - Security

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 356 | [tempdb encrypted](https://straightpathsql.com/check/tempdb-encrypted) | 3 (Low) | tempdb is encrypted, which happens automatically when any user database has TDE enabled. Not necessarily a problem, but encryption can affect performance. |

### 6xx - Reliability

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 603 | [Instance online over 180 days](https://straightpathsql.com/check/instance-uptime) | 3 (Low) | The instance (tempdb create date) has not been restarted in over 180 days, so it is probably missing important updates. |
| 604 | [tempdb files on the C drive](https://straightpathsql.com/check/tempdb-files-on-c-drive) | 1 (High) | A tempdb file is on the C drive (when files span more than one drive letter), risking the OS freezing if the drive fills. |
| 605 | [tempdb file with no growth allowed](https://straightpathsql.com/check/tempdb-no-growth-allowed) | 2 (Medium) | A tempdb file is not allowed to grow beyond its current size, so transactions may freeze or fail if more space is needed. |
| 619 | [tempdb file with max size set](https://straightpathsql.com/check/tempdb-max-file-size) | 1 (High) | A tempdb file has a maximum size set (data files: any max; log files: only below the tier ceiling), so transactions may freeze or fail if it reaches that limit. |

### 7xx - Performance

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 707 | [Number of tempdb data files not recommended](https://straightpathsql.com/check/tempdb-data-file-growth) | 1 (High) | The number of tempdb data files does not match Microsoft's guidance (equal to CPU core count up to 8). Skipped on Azure SQL Managed Instance. |
| 708 | [Unequally sized tempdb data files](https://straightpathsql.com/check/tempdb-data-file-size) | 1 (High) | tempdb data files are not all the same size, causing uneven usage distribution. |
| 709 | [Uneven tempdb growth rates](https://straightpathsql.com/check/tempdb-data-file-growth) | 1 (High) | tempdb data files have differing growth settings, which leads to unequally sized files and uneven usage. |
| 710 | [tempdb log file larger than data files](https://straightpathsql.com/check/tempdb-log-file-size) | 2 (Medium) | The tempdb log file is larger than the data files, which may indicate a very large transaction occurred. |
| 711 | [tempdb file with percentage growth rates](https://straightpathsql.com/check/tempdb-data-file-growth) | 1 (High) | A tempdb file uses percentage growth, which leads to a high number of growth events. A fixed rate of 64 MB or greater is recommended. |
| 712 | [tempdb file with growth rates less than 64 MB](https://straightpathsql.com/check/tempdb-data-file-growth) | 1 (High) | A tempdb file has a fixed growth rate under 64 MB (between 1 and 8191 pages), which can cause many growth events. |
| 713 | [Multiple log files](https://straightpathsql.com/check/tempdb-multiple-log-files) | 1 (High) | tempdb has more than one log file, which is neither needed nor wanted. |
| 714 | [tempdb file with high usage](https://straightpathsql.com/check/tempdb-files-with-high-usage) | 1 (High) | A tempdb file exceeds `@UsagePercent` space usage. Use `@Mode = 2` to see what is consuming the space. |
| 715 | [Trace Flag 1117](https://straightpathsql.com/check/trace-flag-1117) | 2 (Medium) | Trace flag 1117 (grow all files in a filegroup together) is not enabled globally, recommended on versions before SQL Server 2016. |
| 716 | [Trace Flag 1118](https://straightpathsql.com/check/trace-flag-1118) | 2 (Medium) | Trace flag 1118 (reduce SGAM allocation-page waits) is not enabled globally, recommended on versions before SQL Server 2016. |
| 717 | [Memory-optimized tempdb metadata](https://straightpathsql.com/check/tempdb-memory-optimized) | 2 (Medium) | Memory-optimized tempdb metadata is enabled (SQL Server 2019+). Confirm this was intentional. |
| 718 | [Slow reads](https://straightpathsql.com/check/tempdb-slow-reads-and-writes) | 1 (High) | A tempdb file has an average read stall above `@AvgReadStallMs`, possibly indicating an I/O subsystem issue or read-heavy queries. |
| 719 | [Slow writes](https://straightpathsql.com/check/tempdb-slow-reads-and-writes) | 1 (High) | A tempdb file has an average write stall above `@AvgWriteStallMs`, possibly indicating an I/O subsystem issue or write-heavy queries. |
| 727 | [Resource Governor limits used for tempdb](https://learn.microsoft.com/en-us/sql/relational-databases/resource-governor/tempdb-space-resource-governance?view=sql-server-ver17) | 2 (Medium) | A Resource Governor workload group has a fixed tempdb limit (in MB or percent), which can break legitimate workloads with error 1138 (SQL Server 2025+). |
| 730 | [More than 16 tempdb data files](https://straightpathsql.com/check/tempdb-data-file-growth) | 1 (High) | tempdb has more than 16 data files, exceeding Microsoft's recommendation. |
| 741 | [Accelerated Database Recovery](https://learn.microsoft.com/en-us/sql/relational-databases/accelerated-database-recovery-management?view=sql-server-ver17) | 2 (Medium) | tempdb has Accelerated Database Recovery (ADR) enabled, which can add excessive overhead for some workloads (SQL Server 2025+). |

## Results Organization

CheckID series map to categories: **3xx Security**, **6xx Reliability**, **7xx Performance**. The result set(s) returned depend on `@Mode`:

- **File properties** (modes `1`, `99`): one row per tempdb file with file id, logical name, file type, filegroup, initial and current size in MB, autogrowth setting, max size, and physical name.
- **Space usage** (mode `2`): three result sets, reported in MB or GB per `@Size`: a usage summary (total, used, free, user-object, internal-object, version-store, and log space); current data usage per session (session and running allocation, login, statement text); and current log usage per transaction (transaction start time, log records, log used and reserved, statement text, and query plan).
- **Contention** (mode `3`, SQL Server 2019+ or Azure SQL Managed Instance): sessions waiting on `PAGELATCH` against tempdb, classified as ALLOCATION or METADATA contention, with wait type, wait resource, object, blocking session, command, statement text, and page details.
- **Issues** (modes `0`, `99`): the findings from the Checks tables above, ordered by Importance, then category, CheckID, issue, and database. Columns: `Importance`, `CheckName`, `Issue`, `DatabaseName`, `Details`, `ActionStep`, `ReadMoreURL`, `CheckID`.

## Documentation

Full documentation: <https://straightpathsql.com/sp_check/sp_checktempdb/>

## Credits

Provided by **Straight Path IT Solutions, LLC**, <https://straightpathsql.com/>

Portions are derived from `sp_Blitz` (Brent Ozar Unlimited) and are used under the MIT License. Licensed under the MIT License. Copyright 2026 Straight Path IT Solutions, LLC.

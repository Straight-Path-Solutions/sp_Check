# sp_CheckAG

`sp_CheckAG` checks your Availability Group(s) for failover-readiness and configuration issues and returns a prioritized list of findings with action items. It can also return a comprehensive set of information about your Availability Groups, cluster, replicas, listeners, and databases. It is part of the free [Straight Path IT Solutions](https://straightpathsql.com/) `sp_Check*` suite.

## Features

- Reports **Availability Group information**: server and instance details, cluster and quorum state, cluster members, endpoints, AG configuration, listeners, replicas, and databases.
- Flags **ownership issues**: endpoints and Availability Groups owned by a login other than sa.
- Checks **cluster and quorum health**: fewer than 3 online quorum members, fewer than 3 quorum votes, and offline cluster members.
- Checks **replica and database health**: databases not joined, suspended data movement, replicas not failover ready, synchronous replicas not synchronized, and disconnected replicas.
- Checks **endpoints and listeners**: endpoints not started, endpoints using an expiring certificate, and offline listeners.
- Checks **configuration consistency**: session timeouts at or below default, backup preference not Primary, seeding mode differences or AUTOMATIC seeding, mismatched failover modes, default or low health check timeout, and relevant trace flags (9567, 1800).
- Checks **performance and integrity**: high `HADR_SYNC_COMMIT` waits, high secondary lag, suspect pages, and automatic page repair activity.
- Surfaces **recent state changes** and confirms the `AlwaysOn_health` Extended Events session is running.
- Supports filtering to a specific Availability Group and to local replicas and databases only.

## Requirements

- **SQL Server version:** **SQL Server 2016 (13.x) or later** only. Execution is aborted on older versions (`@SQLVersionMajor < 13`). Some informational columns are populated only on newer versions (DTC support and database-level health detection on 2016+, external cluster type on 2017+, contained AGs and secondary lag on 2019+, automatic seeding mode on 2016+).
- **Availability Groups required:** Execution is aborted if the instance has no Availability Groups.
- **Permissions:** The minimum required is **VIEW SERVER STATE** and **VIEW ANY DEFINITION**. Note that some checks will be skipped unless executed by a member of **sysadmin**.

## Parameters

| Name | Data Type | Default | Description |
|------|-----------|---------|-------------|
| `@Mode` | `TINYINT` | `99` | Output mode. `0` = problem findings only (unfiltered); `1` = Availability Group information only; `2` = Availability Group history of events (state changes); `99` = information and problem findings (default). |
| `@AGName` | `NVARCHAR(128)` | `NULL` | Restrict output to a specific Availability Group (short for `@AvailabilityGroupName`). |
| `@LocalOnly` | `BIT` | `NULL` | Set to `1` to reduce results to only local replicas and databases. |
| `@Help` | `BIT` | `0` | Print help text (purpose, parameters, license) and exit. |
| `@VersionCheck` | `BIT` | `0` | Return the procedure's version number and date, then exit. |

This procedure has no `OUTPUT` parameters.

## Usage

```sql
-- Default run: AG information plus all problem findings
EXEC dbo.sp_CheckAG;

-- Problem findings only, for one Availability Group
EXEC dbo.sp_CheckAG
      @Mode = 0
    , @AGName = N'AG_Production';

-- Review the recent history of AG state-change events
EXEC dbo.sp_CheckAG
      @Mode = 2;
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

Findings are returned in modes `0` and `99` (the recent-state-change check, 426, is populated in modes `0`, `2`, and `99`). CheckIDs are grouped into series by category (`4xx` = Availability, `5xx` = Integrity, `6xx` = Reliability). Series `1xx` is Discovery (instance and AG information shown in modes `1` and `99`, not problem findings).

### 4xx - Availability

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 406 | [Endpoint owner](https://straightpathsql.com/check/endpoint-ownership) | 1 (High) | An endpoint is owned by a login other than sa, risking failover if that login becomes inaccessible. |
| 407 | [Availability Group owner](https://straightpathsql.com/check/availability-group-ownership) | 1 (High) | An Availability Group is owned by a login other than sa. |
| 408 | [Less than 3 quorum members online](https://straightpathsql.com/check/cluster-quorum-members) | 1 (High) | Fewer than 3 voting cluster members are online, increasing the risk the cluster goes offline. |
| 409 | [Less than 3 quorum votes among members](https://straightpathsql.com/check/cluster-quorum-members) | 1 (High) | The cluster has fewer than 3 quorum votes among its members. |
| 410 | [Offline cluster member](https://straightpathsql.com/check/cluster-quorum-members) | 1 (High) | A cluster member is not in the UP state. |
| 411 | [Endpoint not started](https://straightpathsql.com/check/endpoint-not-started) | 1 (High) | A database mirroring endpoint is not STARTED, which can drive the AG into a RESOLVING state. |
| 412 | [Seeding mode different among members](https://straightpathsql.com/check/availability-group-seeding-mode) | 2 (Medium) | Replicas in an AG have different seeding modes. |
| 413 | [Replica database not joined](https://straightpathsql.com/check/replica-not-joined) | 1 (High) | A database on this replica is not joined to the Availability Group. |
| 414 | [Data movement suspended](https://straightpathsql.com/check/availability-group-data-movement) | 1 (High) | Data movement for a database is suspended, so secondaries are not updated. |
| 415 | [Session timeout at default / below default](https://straightpathsql.com/check/availability-group-session-timeout) | 2 (Medium) | A replica session timeout is at the default of 10 seconds or lower, which can trigger unexpected AG events. |
| 416 | [Backup preference not Primary](https://straightpathsql.com/check/availability-group-backup-preference) | 2 (Medium) | The AG automated backup preference is not PRIMARY. |
| 417 | [Listener offline](https://straightpathsql.com/check/listener-offline) | 1 (High) | A listener IP is not ONLINE, which can cause connection failures. |
| 418 | [Seeding mode set to AUTOMATIC](https://straightpathsql.com/check/availability-group-seeding-mode) | 2 (Medium) | A replica seeding mode is AUTOMATIC, which can cause unnecessary checks and disconnects after seeding. |
| 419 | [Trace flag 9567 enabled](https://straightpathsql.com/check/trace-flag-9567) | 3 (Low) | Trace flag 9567 (compress the AG data stream during automatic seeding) is enabled globally. |
| 420 | [Endpoint using expiring certificate](https://straightpathsql.com/check/endpoint-using-expiring-certificate) | 2 (Medium) | An endpoint uses a certificate with an expiration date. |
| 421 | [Replica is not failover ready](https://straightpathsql.com/check/replica-not-failover-ready) | 1 (High) | A database is not failover ready on a replica configured for automatic failover. |
| 422 | [High HADR_SYNC_COMMIT waits](https://straightpathsql.com/check/hadr_sync_commit) | 2 (Medium) | The average `HADR_SYNC_COMMIT` wait exceeds 5 ms, which can affect OLTP performance. |
| 423 | [High secondary lag](https://straightpathsql.com/check/secondary-lag) | 2 (Medium) | A database has secondary lag over 5 seconds to a replica. |
| 424 | [Health Check Timeout at / below default value](https://straightpathsql.com/check/health-check-timeout) | 2 (Medium) | The cluster health check timeout is at the default of 30000 ms or lower, which can be overly aggressive. |
| 425 | [Trace flag 1800 enabled](https://straightpathsql.com/check/trace-flag-1800) | 3 (Low) | Trace flag 1800 (optimization for differing log disk sector sizes) is enabled globally. |
| 426 | [Recent state change](https://straightpathsql.com/check/availability-group-state-change) | 2 (Medium) | An AG state change occurred on this replica in the last 24 hours (requires the `AlwaysOn_health` session; populated in modes 0, 2, 99). |
| 427 | [Different failover modes - same AG](https://straightpathsql.com/check/availability-group-failover-mode) | 2 (Medium) | Replicas in the same Availability Group use different failover modes. |
| 428 | [Different failover modes - same instance](https://straightpathsql.com/check/availability-group-failover-mode) | 2 (Medium) | Availability Groups on the same instance use different failover modes. |
| 429 | [AlwaysOn_health XE stopped](https://straightpathsql.com/check/alwayson-health-extended-event) | 1 (High) | The `AlwaysOn_health` Extended Events session is stopped, so vital AG events are not recorded. |
| 430 | [Synchronous replica not synchronized](https://straightpathsql.com/check/synchronous-replica-not-synchronized) | 1 (High) | A database on a synchronous-commit replica is not in a SYNCHRONIZED state, so zero data loss is not guaranteed. |
| 431 | [Replica disconnected](https://straightpathsql.com/check/replica-disconnected) | 1 (High) | A replica is DISCONNECTED from the primary and is not a valid failover target. |
| 432 | [SQL Server Service endpoint permission](https://straightpathsql.com/check/endpoint-connect-permission) | 1 (High) | The SQL Server service account (and it is not sysadmin) has not been granted CONNECT permission on the database mirroring endpoint, so replicas cannot communicate. |

### 5xx - Integrity

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 504 | [Suspect pages detected](https://straightpathsql.com/check/database-corruption) | 1 (High) | A local AG database has entries in `msdb.dbo.suspect_pages` (823/824 errors, bad checksums, or torn pages), indicating physical corruption. |
| 506 | [Automatic page repair activity](https://straightpathsql.com/check/automatic-page-repair) | 2 (Medium) | The AG performed automatic page repair on a database, a strong signal of failing storage on this replica. |

### 6xx - Reliability

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 617 | [Server name discrepancy](https://straightpathsql.com/check/server-name) | 2 (Medium) | `@@SERVERNAME` does not match `SERVERPROPERTY('ServerName')`, which can cause features to not work. |

## Results Organization

CheckID series map to categories: **1xx Discovery**, **4xx Availability**, **5xx Integrity**, **6xx Reliability**. The result set(s) returned depend on `@Mode`:

- **Availability Group information** (modes `1`, `99`): eight result sets, in order: server and instance (pivoted), cluster (name, quorum type and state), cluster members, endpoints, Availability Group configuration, listeners, replicas, and databases. The pivoted server and instance result set includes a `Can connect to Endpoint` indicator (`Yes`, `No`, or `Unknown`) showing whether the SQL Server service account has CONNECT permission on the database mirroring endpoint. The endpoints result set includes an `EndpointOwnerIsSysadmin` indicator (`Yes` or `No`) showing whether the endpoint owner is a member of the sysadmin role.
- **Issues** (modes `0`, `99`): the findings from the Checks tables above, ordered by Importance, then category, CheckID, issue, and database. Columns: `Importance`, `CheckName`, `Issue`, `DatabaseName`, `Details`, `ActionStep`, `ReadMoreURL`, `CheckID`.
- **State change history** (mode `2`): the recent `availability_replica_state_change` events read from the `AlwaysOn_health` Extended Events target, with instance name, object name, event timestamp, AG name, previous state, and current state, ordered most recent first.

## Documentation

Full documentation: <https://straightpathsql.com/sp_check/sp_checkag/>

## Credits

Provided by **Straight Path IT Solutions, LLC**, <https://straightpathsql.com/>

Licensed under the MIT License. Copyright 2026 Straight Path IT Solutions, LLC.

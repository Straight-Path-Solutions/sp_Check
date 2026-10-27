# sp_CheckSecurity

`sp_CheckSecurity` checks a SQL Server instance for several dozen possible security vulnerabilities and returns an ordered list of findings with explanations and action items. It is part of the free [Straight Path IT Solutions](https://straightpathsql.com/) `sp_Check*` suite.

## Features

- Audits **privileged access**: members of the sysadmin and securityadmin roles, logins with CONTROL SERVER, IMPERSONATE ANY LOGIN, and ALTER ANY LOGIN, and (optionally) members of the local Administrators group.
- Checks **login and password risks**: an enabled or renamed `sa` account, blank passwords, passwords matching the login, the password "password", and invalid Windows logins.
- Reviews **service account exposure**: SQL Server and SQL Agent services running as a built-in elevated account or as a member of the sysadmin role, and service accounts in the local Administrators group.
- Flags **risky instance configurations**: `xp_cmdshell`, CLR, OLE Automation Procedures, cross-database ownership chaining, Ad Hoc Distributed Queries, Database Mail XPs, remote admin connections, remote access, C2 audit mode, common criteria compliance, and contained database authentication.
- Reviews **Configuration Manager settings**: Hide Instance, Extended Protection, and Force Encryption.
- Checks **database-level risks**: TRUSTWORTHY databases, db_owner and unusual database role membership, roles within roles, orphaned users, database owner problems, contained databases, and explicit permissions granted to the public role.
- Reviews **surface area and connectivity**: linked servers by security context, startup stored procedures and jobs, running SQL Server Audits, endpoints owned by users, and SQL Agent jobs owned by users.
- Checks **encryption and recoverability**: TDE and backup certificates that have never been backed up, not backed up recently, or set to expire.
- Checks **auditing and patching**: whether failed logins are audited, recent failed logins, error log retention, missing security updates, and unsupported versions.
- Collects **instance discovery information** and supports filtering to only high-importance findings.

## Requirements

- **SQL Server version:** Designed for **SQL Server 2016 (13.x) or later**. It runs on **SQL Server 2012 (11.x)** and **2014 (12.x)** but skips a few checks; on SQL Server 2008 R2 or older it only prints a message and exits (unless `@Override = 1` is used to bypass the version gate). Version-gated checks include:
  - Database-backup-certificate checks and the public-role-permissions check require **SQL Server 2014 (12.x)+** (`>= 12`).
  - The contained-database check requires **SQL Server 2012 (11.x)+** (`>= 11`).
  - The CLR remediation guidance changes on **SQL Server 2017 (14.x)+**.
  - Version and security-update checks skip Azure SQL Managed Instance (`EngineEdition` 8).
- **Permissions:** The executing user must be a member of the sysadmin role; the procedure aborts otherwise.
- **Database count guard:** Instances with **more than 50 databases** require `@Override = 1`, since gathering backup history can be resource-intensive.
- **`@CheckLocalAdmin` warning:** When set to `1`, if `BUILTIN\Administrators` is not already a login, the procedure adds it inside an explicit transaction, reads its members with `xp_logininfo`, and then rolls the transaction back to remove it. Be aware of this if you have triggers or auditing that track login creation.

## Parameters

| Name | Data Type | Default | Description |
|------|-----------|---------|-------------|
| `@Mode` | `TINYINT` | `99` | Output mode. `0` = all discovered vulnerabilities; `1` = instance information only; `2` = only high-importance items; `99` = information plus all discovered vulnerabilities (default). |
| `@CheckLocalAdmin` | `BIT` | `0` | `1` = check (and record) the members of the local Administrators group; `0` = do not (default). See the warning in Requirements. |
| `@PreferredDBOwner` | `NVARCHAR(255)` | `NULL` | The login you prefer to own your databases. When supplied, databases not owned by this login (system databases not owned by sa) are flagged (CheckID 327). |
| `@Override` | `BIT` | `0` | Set to `1` to proceed on instances with more than 50 databases, and to bypass the unsupported-version gate. |
| `@Help` | `BIT` | `0` | Print help text (purpose, parameters, license) and exit. |
| `@VersionCheck` | `BIT` | `0` | Return the procedure's version number and date, then exit. |

This procedure has no `OUTPUT` parameters.

## Usage

```sql
-- Default run: instance information plus all discovered vulnerabilities
EXEC dbo.sp_CheckSecurity;

-- Only high-importance vulnerabilities
EXEC dbo.sp_CheckSecurity
      @Mode = 2;

-- Include local Administrators membership and flag databases not owned by a preferred login
EXEC dbo.sp_CheckSecurity
      @CheckLocalAdmin = 1
    , @PreferredDBOwner = N'sa';
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

Findings are returned in modes `0`, `1`, and `99`. CheckIDs are grouped into series by category (`2xx` = Recoverability, `3xx` = Security, `4xx` = Availability, `6xx` = Reliability). Series `1xx` is Discovery (instance information shown in mode `99`, not vulnerability findings).

### 2xx - Recoverability

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 210 | [Database backup certificate (never / not recently backed up)](https://straightpathsql.com/check/missing-database-backup-certificate-backup) | 1 (High), 2 (Medium) | A certificate used to encrypt database backups has never been backed up (High), or not in the last 90 days (Medium). Requires SQL Server 2014+. |
| 211 | [TDE certificate (never / not recently backed up)](https://straightpathsql.com/check/no-recent-tde-certificate-backup) | 1 (High), 2 (Medium) | A TDE certificate has never been backed up (High), or not in the last 90 days (Medium). |
| 212 | [Database backup certificate set to expire](https://straightpathsql.com/check/database-backup-certificate-expiration-date) | 2 (Medium) | A certificate used to encrypt database backups is set to expire (SQL Server 2014+). |
| 213 | [TDE certificate set to expire](https://straightpathsql.com/check/tde-certificate-expiration-date) | 2 (Medium) | A TDE certificate is set to expire. |
| 219 | [Backups not encrypted](https://straightpathsql.com/check/backups-not-encrypted) | 2 (Medium) | A database has unencrypted full backups in the last 7 days (SQL Server 2014+). |
| 220 | [Backups written to a local drive](https://straightpathsql.com/check/backups-local-drive) | 2 (Medium) | A database has full backups in the last 7 days written to a drive letter rather than a network share or object storage. |

### 3xx - Security

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 301 | [sysadmin role members](https://straightpathsql.com/check/sysadmin) | 1 (High) | Lists logins in the sysadmin role, which can do anything on the instance. |
| 302 | [securityadmin role members](https://straightpathsql.com/check/securityadmin) | 1 (High) | Lists logins in the securityadmin role, which can grant any permission. |
| 303 | [CONTROL SERVER permissions](https://straightpathsql.com/check/control-server) | 1 (High) | Lists logins granted CONTROL SERVER, equivalent to sysadmin. |
| 304 | [Invalid login with Windows Authentication](https://straightpathsql.com/check/invalid-windows-login) | 3 (Low) | A login with permissions is no longer mapped to a valid Windows user or group. |
| 305 | [Database Owner is Unknown](https://straightpathsql.com/check/database-owner-is-unknown) | 2 (Medium) | A database owner SID does not resolve to a login (blank owner). |
| 306 | [Database owner discrepancy](https://straightpathsql.com/check/database-owner-is-unknown) | 3 (Low) | The database owner differs from the owner recorded in master. |
| 307 | [Enabled sa account](https://straightpathsql.com/check/enabled-sa-login) | 1 (High) | The `sa` login is enabled for connections. |
| 308 | [TRUSTWORTHY database owned by sysadmin](https://straightpathsql.com/check/trustworthy-database) | 1 (High) | A TRUSTWORTHY database is owned by a sysadmin, allowing any user to execute commands as a sysadmin. |
| 309 | [Configuration: clr enabled](https://straightpathsql.com/check/clr-enabled) | 2 (Medium) | The `clr enabled` configuration is on, allowing assembly execution in the SQL Server account context. |
| 310 | [Configuration: Remote admin connections](https://straightpathsql.com/check/remote-dedicated-admin-connections) | 2 (Medium) | Remote admin connections are DISABLED (recommended to be enabled for troubleshooting). The current setting is also shown in the instance information. |
| 311 | [Configuration: Database Mail XPs](https://straightpathsql.com/check/database-mail-xps) | 2 (Medium) | Database Mail XPs are ENABLED. The current setting is also shown in the instance information. |
| 312 | [Encrypted / Unencrypted database](https://straightpathsql.com/check/encrypted-databases) | 2 (Medium) | Reports databases using SQL Server encryption, and databases that are not encrypted. |
| 313 | [Stored procedure run at Startup](https://straightpathsql.com/check/stored-procedures-that-run-at-startup) | 2 (Medium) | A stored procedure is set to run automatically at startup. |
| 314 | [SQL Agent job run at Startup](https://straightpathsql.com/check/sql-agent-jobs-that-run-at-startup) | 2 (Medium) | A SQL Agent job is scheduled to run at SQL Server Agent startup. |
| 315 | [local Administrators](https://straightpathsql.com/check/local-administrators) | 1 (High) | Lists members of the local Administrators Windows group (requires `@CheckLocalAdmin = 1`). |
| 316 | [Password blank](https://straightpathsql.com/check/password-vulnerabilities) | 1 (High) | A SQL login has a blank password. |
| 317 | [Password is same as login](https://straightpathsql.com/check/password-vulnerabilities) | 1 (High) | A SQL login has a password equal to the login name. |
| 318 | [Password is password](https://straightpathsql.com/check/password-vulnerabilities) | 1 (High) | A SQL login has a password of "password". |
| 319 | [Configuration: xp_cmdshell](https://straightpathsql.com/check/xp_cmdshell) | 2 (Medium) | The `xp_cmdshell` configuration is ENABLED. The current setting is also shown in the instance information. |
| 320 | [Configuration: Ole Automation Procedures](https://straightpathsql.com/check/ole-automation-procedures) | 2 (Medium) | The `Ole Automation Procedures` configuration is enabled. |
| 321 | [Configuration: Cross-database ownership chaining](https://straightpathsql.com/check/cross-database-ownership-chaining) | 2 (Medium) | The `cross db ownership chaining` configuration is enabled. |
| 322 | [Configuration: Ad Hoc Distributed Queries](https://straightpathsql.com/check/ad-hoc-distributed-queries) | 2 (Medium) | The `Ad Hoc Distributed Queries` configuration is enabled. |
| 323 | [Linked Server configured with sa](https://straightpathsql.com/check/linked-server) | 1 (High) | A linked server connects using the security context of the sa login. |
| 324 | [Linked Server configured with fixed login](https://straightpathsql.com/check/linked-server) | 2 (Medium) | A linked server connects using the security context of a fixed login. |
| 325 | [Linked Server](https://straightpathsql.com/check/linked-server) | 2 (Medium) | A linked server uses the login's current security context, self credentials, a remote login, or no security context. |
| 326 | [SQL Server Audit running](https://straightpathsql.com/check/sql-server-audit) | 2 (Medium) | A SQL Server Audit is currently running. |
| 327 | [Database owner is not preferred](https://straightpathsql.com/check/database-owner-is-not-preferred-owner) | 2 (Medium) | A database is not owned by the preferred owner (requires `@PreferredDBOwner`). |
| 328 | [Database owner is a sysadmin](https://www.insidesql.org/blogs/andreaswolter/2014/06/sql-server-database-ownership-survey-results-recommendations) | 2 (Medium) | A user database is owned by a member of the sysadmin role. |
| 329 | [SQL Server / SQL Agent service using built-in elevated account](https://straightpathsql.com/check/service-account-permissions) | 1 (High) | The SQL Server or SQL Agent service runs as LocalSystem or NT AUTHORITY\SYSTEM. |
| 330 | [No audit of failed logins](https://straightpathsql.com/check/sql-login-audit-does-not-include-failed-logins) | 1 (High) | The SQL login audit setting does not capture failed logins. |
| 331 | [Failed logins](https://straightpathsql.com/check/failed-logins) | 1 (High) | Recent failed logins are present in the error log. |
| 332 | [TRUSTWORTHY database](https://straightpathsql.com/check/trustworthy-enabled) | 2 (Medium) | A database has TRUSTWORTHY enabled (owner not a sysadmin). |
| 333 | [db_owner role member](https://straightpathsql.com/check/db_owner-role-members) | 2 (Medium) | A user is a member of the db_owner role in a database. |
| 334 | [db_owner role member - system databases](https://straightpathsql.com/check/db_owner-role-members) | 1 (High) | A user is a member of the db_owner role in master or msdb. |
| 335 | [Unusual database permissions](https://straightpathsql.com/check/unusual-database-permissions) | 2 (Medium) | A user holds db_accessadmin, db_securityadmin, or db_ddladmin in a database. |
| 336 | [Unusual database permissions - system databases](https://straightpathsql.com/check/unusual-database-permissions) | 1 (High) | A user holds one of those elevated roles in master or msdb. |
| 337 | [Roles within roles](https://straightpathsql.com/check/database-roles-within-roles) | 3 (Low) | A database role is a member of another role, which can lead to unintended privilege escalation. |
| 338 | [Orphaned database user](https://straightpathsql.com/check/orphaned-users) | 3 (Low) | A database user has no corresponding login at the instance level. |
| 339 | [Public permissions](https://straightpathsql.com/check/explicit-permissions-for-public) | 2 (Medium) | Explicit permissions have been granted to the public role (SQL Server 2014+). |
| 340 | [Renamed sa account](https://straightpathsql.com/check/sa-login-renamed) | 2 (Medium) | The sa login has been renamed (which is less important than disabling it). |
| 341 | [Configuration: C2 audit mode](https://straightpathsql.com/check/c2-audit-mode) | 2 (Medium) | C2 audit mode is ENABLED. The current setting is also shown in the instance information. |
| 342 | [Configuration: Common Criteria Compliance](https://straightpathsql.com/check/common-criteria-compliance) | 2 (Medium) | Common criteria compliance is ENABLED. The current setting is also shown in the instance information. |
| 343 | [Configuration: Contained Database Authentication](https://straightpathsql.com/check/contained-database) | 2 (Medium) | Contained database authentication is ENABLED. The current setting is also shown in the instance information. |
| 344 | [contained database](https://straightpathsql.com/check/contained-database) | 2 (Medium) | A database is configured as CONTAINED (SQL Server 2012+). |
| 345 | [Configuration: Remote Access](https://straightpathsql.com/check/remote-access) | 2 (Medium) | The remote access configuration is ENABLED. The current setting is also shown in the instance information. |
| 346 | [Database owned by Windows account](https://straightpathsql.com/check/database-owner-is-not-preferred-owner) | 2 (Medium) | A database is owned by a Windows account, a privilege-escalation path. |
| 347 | [Configuration Manager: Hide Instance](https://straightpathsql.com/check/hide-instance) | 2 (Medium) | Hide Instance is ENABLED in Configuration Manager. The current setting is also shown in the instance information. |
| 348 | [Configuration Manager: Extended Protection](https://straightpathsql.com/check/extended-protection) | 2 (Medium) | Extended Protection is ENABLED in Configuration Manager. The current setting is also shown in the instance information. |
| 349 | [Configuration Manager: Force Encryption](https://straightpathsql.com/check/force-encryption) | 2 (Medium) | Force Encryption is ENABLED in Configuration Manager. The current setting is also shown in the instance information. |
| 350 | [SQL Server / SQL Agent service account in sysadmin](https://straightpathsql.com/check/service-account-permissions) | 2 (Medium) | The SQL Server or SQL Agent service account is a member of the sysadmin role. |
| 351 | [Service account in local Administrators](https://straightpathsql.com/check/service-account-permissions) | 1 (High) | The SQL Server or SQL Agent service account is in the local Administrators group (requires `@CheckLocalAdmin = 1`). |
| 352 | [SQL Agent proxy account in sysadmin](https://straightpathsql.com/check/proxy-account-in-sysadmin) | 2 (Medium) | A SQL Agent proxy maps to a credential whose account is in the sysadmin role. |
| 353 | [xp_cmdshell proxy account exists](https://straightpathsql.com/check/xp_cmdshell) | 1 (High) | The `##xp_cmdshell_proxy_account##` credential exists, letting non-sysadmins run OS commands. |
| 354 | [Server-level permissions granted to login](https://straightpathsql.com/check/server-level-permissions) | 1 (High) | A login has been granted a server-level permission (ALTER ANY LOGIN, IMPERSONATE ANY LOGIN, ALTER ANY SERVER ROLE, ALTER ANY CREDENTIAL, or ALTER ANY LINKED SERVER) that provides a path to elevated privilege. |
| 355 | [Orphaned database user with elevated permissions](https://straightpathsql.com/check/orphaned-user-elevated-permissions) | 1 (High) | A database user has no matching server login and holds an elevated database role or permission. |
| 357 | [NTLM authentication in use](https://straightpathsql.com/check/ntlm-authentication) | 2 (Medium) | More than 10% of active user sessions authenticate with NTLM instead of Kerberos. |
| 358 | [SPN registration failed](https://straightpathsql.com/check/spn-registration) | 1 (High) | The current error log shows SQL Server could not register its Service Principal Name. |
| 359 | [Legacy password hash algorithm](https://straightpathsql.com/check/legacy-password-hash) | 1 (High) | An enabled SQL login still uses the pre-2012 SHA-1 password hash. |
| 360 | [SQL authentication in use](https://straightpathsql.com/check/sql-authentication) | 2 (Medium) | More than 10% of active user sessions use SQL logins rather than Windows authentication. |
| 361 | [Guest user has CONNECT permission](https://straightpathsql.com/check/guest-user-connect) | 2 (Medium) | The guest user has CONNECT in a user database, letting any login enter it. |
| 362 | [Contained database users](https://straightpathsql.com/check/contained-database-users) | 2 (Medium) | A database has contained users that authenticate directly, bypassing server-level login controls. |
| 363 | [Application roles detected](https://straightpathsql.com/check/application-roles) | 2 (Medium) | A database contains application roles, which activate with a shared password. |
| 364 | [Certificate or asymmetric key mapped login](https://straightpathsql.com/check/certificate-mapped-logins) | 2 (Medium) | A login is mapped to a certificate or asymmetric key. |
| 365 | [Server role membership with escalation path](https://straightpathsql.com/check/server-role-escalation) | 1 (High) | A login belongs to serveradmin, dbcreator, or setupadmin, each a route to elevated privilege. |
| 366 | [Custom server role with elevated permissions](https://straightpathsql.com/check/custom-server-role-permissions) | 1 (High) | A user-defined server role holds a permission that provides a path to elevated privilege. |
| 367 | [BUILTIN\Administrators exists as a login](https://straightpathsql.com/check/builtin-administrators-login) | 2 (Medium) | The local Windows Administrators group is present as a SQL Server login, granting every local admin instance access. |
| 368 | [ALTER ANY SERVER AUDIT granted to login](https://straightpathsql.com/check/alter-any-server-audit) | 1 (High) | A non-sysadmin login can alter, disable, or drop server audits and audit specifications. |
| 369 | [Configuration: external scripts enabled](https://straightpathsql.com/check/external-scripts-enabled) | 2 (Medium) | The external scripts enabled setting is on, allowing sp_execute_external_script to run R, Python, or Java code. |
| 370 | [ALTER SETTINGS granted to login](https://straightpathsql.com/check/alter-settings-permission) | 1 (High) | A non-sysadmin login can run sp_configure and change any server configuration option. |
| 371 | [Unsigned assembly with elevated permission set](https://straightpathsql.com/check/unsigned-assembly-trustworthy) | 1 (High) | An unsigned EXTERNAL_ACCESS or UNSAFE CLR assembly exists in a database that allows escalation to the server security context. |
| 372 | [Assembly creation permission granted to login](https://straightpathsql.com/check/assembly-permissions) | 1 (High) | A non-sysadmin login holds UNSAFE ASSEMBLY or EXTERNAL ACCESS ASSEMBLY, letting it create assemblies that run outside the sandbox. |
| 373 | [Trusted assembly registered](https://straightpathsql.com/check/trusted-assemblies) | 1 (High) | An assembly is registered in sys.trusted_assemblies, letting it load unsigned even when clr strict security is enabled. |
| 374 | [Agent proxy accessible to non-sysadmin](https://straightpathsql.com/check/agent-proxies) | 1 (High) | A SQL Server Agent proxy can be used by non-sysadmin principals to run job steps as the proxy's Windows account. |
| 375 | [SQLAgentOperatorRole membership](https://straightpathsql.com/check/agent-operator-role) | 1 (High) | A non-sysadmin login can create, run, and modify SQL Server Agent jobs. |
| 376 | [Logon trigger](https://straightpathsql.com/check/logon-triggers) | 2 (Medium) | A logon trigger executes code on every connection attempt, in the security context of its creator. |
| 377 | [Extended stored procedure registered](https://straightpathsql.com/check/extended-stored-procedures) | 2 (Medium) | A user-registered extended stored procedure loads native code into the SQL Server process. |
| 378 | [Always Encrypted column master key on database server](https://straightpathsql.com/check/always-encrypted-key-location) | 1 (High) | An Always Encrypted column master key is stored in the local machine certificate store on the SQL Server host (SQL Server 2016+). |
| 379 | [SQL Server Audit not capturing security actions](https://straightpathsql.com/check/sql-server-audit-coverage) | 2 (Medium) | No enabled server audit exists, or an enabled audit omits the security-relevant action groups. |
| 380 | [Endpoint encryption](https://straightpathsql.com/check/endpoint-encryption) | 2 (Medium) | A database mirroring endpoint uses RC4 or no encryption (including the mixed AES RC4 setting) instead of AES. |

### 4xx - Availability

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 406 | [Endpoint owner](https://straightpathsql.com/check/endpoint-ownership) | 1 (High) | An endpoint is owned by a user login rather than the service account, risking high availability if that login becomes unavailable. |

### 6xx - Reliability

| CheckID | Finding | Priority | Description |
|---------|---------|----------|-------------|
| 601 | [Security update available](https://straightpathsql.com/check/security-update) | 1 (High) | A security update from Microsoft has not been applied (not Azure SQL Managed Instance). |
| 602 | [Unsupported version of SQL Server](https://straightpathsql.com/check/unsupported-versions) | 1 (High) | The SQL Server version is no longer supported by Microsoft (not Azure SQL Managed Instance). |
| 611 | [SQL Agent jobs owned by users](https://straightpathsql.com/check/sql-agent-jobs-owned-by-users) | 2 (Medium) | An enabled SQL Agent job is owned by a user login rather than sa. |
| 622 | [Too few SQL Server error log files](https://straightpathsql.com/check/number-of-sql-server-error-log-files) | 2 (Medium) | Error log retention is at or below 7 archive files, limiting history for spotting login-failure patterns. |
| 633 | [Configuration: default trace disabled](https://straightpathsql.com/check/default-trace-disabled) | 1 (High) | The default trace is disabled, removing the built-in short-window record of configuration and security changes. |

## Results Organization

CheckID series map to categories: **1xx Discovery**, **2xx Recoverability**, **3xx Security**, **4xx Availability**, **6xx Reliability**. The procedure returns a single result set whose rows depend on `@Mode`:

- **Instance information only** (mode `1`): only the Discovery (1xx) instance information rows. This also includes the current state (Importance 0) of ten instance configuration settings, using their CheckIDs (310, 311, 319, 341, 342, 343, 345, 347, 348, 349): remote admin connections, Database Mail XPs, xp_cmdshell, C2 audit mode, common criteria compliance, contained database authentication, remote access, Hide Instance, Extended Protection, and Force Encryption. These settings appear as findings only when enabled (remote admin connections only when disabled).
- **High-importance findings** (mode `2`): only findings with Importance 1 (High).
- **All vulnerabilities** (mode `0`): all findings outside the Discovery category (excludes the informational discovery rows).
- **Information and all vulnerabilities** (mode `99`): all rows, including the Discovery (1xx) instance information (capture date, server name, instance name, version, edition, build, SQL Server and SQL Agent service accounts, and IP address).

In every mode the result set is ordered by Importance, then CheckName, DatabaseName, and Details. Columns: `Importance`, `CheckName`, `Issue`, `DatabaseName`, `Details`, `ActionStep`, `ReadMoreURL`, `CheckID`.

## Documentation

Full documentation: <https://straightpathsql.com/sp_check/sp_checksecurity/>

## Credits

Provided by **Straight Path IT Solutions, LLC**, <https://straightpathsql.com/>

Portions are derived from Microsoft's tigertoolbox and from `sp_Blitz` (Brent Ozar Unlimited) and are used under the MIT License. Licensed under the MIT License. Copyright 2026 Straight Path IT Solutions, LLC.

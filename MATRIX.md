# sp_Check Matrix

This matrix lists every check in the sp_Check suite and shows which procedures perform it. It replaces the former Matrix.xlsx content, which was out of date. It was last reviewed against the procedure code on 2026-10-23 (procedure version 2026.10.1).

Procedures reviewed: sp_CheckAG, sp_CheckBackup, sp_CheckHealth, sp_CheckSecurity, and sp_CheckTempdb. sp_CheckActivity does not use CheckIDs and is not included.

## How to read this matrix

- **CheckID**: the stable numeric ID of the check. The hundreds digit is the category (1xx Discovery, 2xx Recoverability, 3xx Security, 4xx Availability, 5xx Integrity, 6xx Reliability, 7xx Performance). The same ID is shared by procedures that report the same finding, but check IDs are only unique within a procedure, so always key on the procedure and the CheckID.
- **Importance**: 0 = Information, 1 = High, 2 = Medium, 3 = Low. A value such as 1/2 means the importance depends on the variant of the finding (for example, a never-backed-up item is rated higher than a stale one).
- **x**: the procedure performs the check.
- **Check**: a short description of the finding, linked to the Straight Path page that explains it (a few link to Microsoft or other documentation, and some discovery items have no page). Some IDs cover several variants of the same finding.

## Checks

| Category | CheckID | Importance | Check | sp_CheckAG | sp_CheckBackup | sp_CheckHealth | sp_CheckSecurity | sp_CheckTempdb |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | :---: |
| Discovery | 100 | 0 | Capture date |  |  |  | x |  |
| Discovery | 101 | 0 | server name | x |  | x | x |  |
| Discovery | 102 | 0 | instance name | x |  | x | x |  |
| Discovery | 103 | 0 | instance version | x |  | x | x |  |
| Discovery | 104 | 0 | instance edition | x |  | x | x |  |
| Discovery | 105 | 0 | instance build | x |  | x | x |  |
| Discovery | 106 | 0 | Error log location |  |  | x |  |  |
| Discovery | 107 | 0 | default data file path |  |  | x |  |  |
| Discovery | 108 | 0 | default log file path |  |  | x |  |  |
| Discovery | 109 | 0 | default backup path |  |  | x |  |  |
| Discovery | 110 | 0 | trace flags in use | x |  | x |  |  |
| Discovery | 111 | 0 | communication protocol | x |  | x |  |  |
| Discovery | 112 | 0 | last restart time |  |  | x |  |  |
| Discovery | 113 | 0 | number of CPU cores and NUMA nodes | x |  | x |  |  |
| Discovery | 114 | 0 | server memory | x |  | x |  |  |
| Discovery | 115 | 0 | virtual machine check | x |  | x |  |  |
| Discovery | 116 | 0 | sql server account | x |  | x | x |  |
| Discovery | 117 | 0 | sql agent account |  |  | x | x |  |
| Discovery | 118 | 0 | count of instances on the server |  |  | x |  |  |
| Discovery | 119 | 0 | [IP address](https://straightpathsql.com/check/ip-address) | x |  | x | x |  |
| Discovery | 120 | 0 | Server Type | x |  | x |  |  |
| Discovery | 198 | 0 | Can connect to Endpoint | x |  |  |  |  |
| Discovery | 199 | 0 | SQL Server service is sysadmin | x |  |  |  |  |
| Recoverability | 201 | 1 | [split backup chain](https://straightpathsql.com/check/split-backup-chain) |  | x |  |  |  |
| Recoverability | 202 | 2 | [backups without checksum](https://straightpathsql.com/check/backup-checksum) |  | x |  | x |  |
| Recoverability | 203 | 1 | [missing full backup](https://straightpathsql.com/check/missing-backups) |  | x | x |  |  |
| Recoverability | 204 | 1 | [missing log backup](https://straightpathsql.com/check/missing-backups) |  | x | x |  |  |
| Recoverability | 205 | 1 | [no recent full backup](https://straightpathsql.com/check/recovery-point-objective) |  | x | x |  |  |
| Recoverability | 206 | 1 | [no recent log backup](https://straightpathsql.com/check/recovery-point-objective) |  | x | x |  |  |
| Recoverability | 207 | 1 | [failed backups](https://straightpathsql.com/check/failed-backup) |  | x | x |  |  |
| Recoverability | 208 | 2 | [backup compression](https://straightpathsql.com/check/backup-compression) |  | x | x |  |  |
| Recoverability | 209 | 2 | [backup checksum](https://straightpathsql.com/check/backup-checksum) |  | x | x |  |  |
| Recoverability | 210 | 1/2 | [backup certificate has not been backed up (never or in the last 90 days)](https://straightpathsql.com/check/missing-database-backup-certificate-backup) |  | x | x | x |  |
| Recoverability | 211 | 1 | [TDE certificate has not been backed up (never or in the last 90 days)](https://straightpathsql.com/check/no-recent-tde-certificate-backup) |  | x | x | x |  |
| Recoverability | 212 | 1/2 | [backup certificate set to expire](https://straightpathsql.com/check/database-backup-certificate-expiration-date) |  | x | x | x |  |
| Recoverability | 213 | 2 | [TDE certificate set to expire](https://straightpathsql.com/check/tde-certificate-expiration-date) |  | x | x | x |  |
| Recoverability | 214 | 1 | [recovery point objective](https://straightpathsql.com/check/recovery-point-objective) |  | x |  |  |  |
| Recoverability | 215 | 2 | [password protected backups](https://straightpathsql.com/check/password-protected-backup) |  | x |  |  |  |
| Recoverability | 216 | 2 | [backup history not purged](https://straightpathsql.com/check/backup-history-not-purged) |  | x | x |  |  |
| Recoverability | 217 | 2 | [high VLF count](https://straightpathsql.com/check/virtual-log-files) |  | x | x |  |  |
| Recoverability | 218 | 1 | [log backups to NUL](https://straightpathsql.com/check/backup-to-nul) |  | x |  |  |  |
| Recoverability | 219 | 2 | [Backups not encrypted](https://straightpathsql.com/check/backups-not-encrypted) |  | x |  | x |  |
| Recoverability | 220 | 2 | [Backups written to a local drive](https://straightpathsql.com/check/backups-local-drive) |  | x |  | x |  |
| Security | 301 | 1 | [sysadmin members](https://straightpathsql.com/check/sysadmin) |  |  |  | x |  |
| Security | 302 | 1 | [securityadmin members](https://straightpathsql.com/check/securityadmin) |  |  |  | x |  |
| Security | 303 | 1 | [logins with CONTROL SERVER](https://straightpathsql.com/check/control-server) |  |  |  | x |  |
| Security | 304 | 3 | [invalid Windows login](https://straightpathsql.com/check/invalid-windows-login) |  |  | x | x |  |
| Security | 305 | 2/3 | [database owner is unknown](https://straightpathsql.com/check/database-owner-is-unknown) |  |  | x | x |  |
| Security | 306 | 3 | [database with mismatched owner in master](https://straightpathsql.com/check/database-owner-is-unknown) |  |  | x | x |  |
| Security | 307 | 1 | [sa account enabled](https://straightpathsql.com/check/enabled-sa-login) |  |  | x | x |  |
| Security | 308 | 1 | [database with TRUSTWORTHY enabled owned by sysadmin](https://straightpathsql.com/check/trustworthy-database) |  |  |  | x |  |
| Security | 309 | 1 | [CLR enabled](https://straightpathsql.com/check/clr-enabled) |  |  |  | x |  |
| Security | 310 | 2 | [Remote admin connections](https://straightpathsql.com/check/remote-dedicated-admin-connections) |  |  | x | x |  |
| Security | 311 | 2 | [Database Mail XPs](https://straightpathsql.com/check/database-mail-xps) |  |  |  | x |  |
| Security | 312 | 2 | [Encrypted databases](https://straightpathsql.com/check/encrypted-databases) |  |  |  | x |  |
| Security | 313 | 2 | [stored procedures run at startup](https://straightpathsql.com/check/stored-procedures-that-run-at-startup) |  |  |  | x |  |
| Security | 314 | 2 | [jobs that run at startup](https://straightpathsql.com/check/sql-agent-jobs-that-run-at-startup) |  |  |  | x |  |
| Security | 315 | 1 | [local Administrators](https://straightpathsql.com/check/local-administrators) |  |  |  | x |  |
| Security | 316 | 1 | [password is blank](https://straightpathsql.com/check/password-vulnerabilities) |  |  |  | x |  |
| Security | 317 | 1 | [password is same as login](https://straightpathsql.com/check/password-vulnerabilities) |  |  |  | x |  |
| Security | 318 | 1 | [password is password](https://straightpathsql.com/check/password-vulnerabilities) |  |  |  | x |  |
| Security | 319 | 2 | [xp_cmdshell enabled](https://straightpathsql.com/check/xp_cmdshell) |  |  |  | x |  |
| Security | 320 | 2 | [Ole Automation Procedures enabled](https://straightpathsql.com/check/ole-automation-procedures) |  |  |  | x |  |
| Security | 321 | 2 | [cross-database ownership chaining enabled (instance level)](https://straightpathsql.com/check/cross-database-ownership-chaining) |  |  |  | x |  |
| Security | 322 | 2 | [ad hoc distributed queries enabled](https://straightpathsql.com/check/ad-hoc-distributed-queries) |  |  |  | x |  |
| Security | 323 | 1 | [linked server using the sa login](https://straightpathsql.com/check/linked-server) |  |  |  | x |  |
| Security | 324 | 2 | [linked server using fixed login](https://straightpathsql.com/check/linked-server) |  |  |  | x |  |
| Security | 325 | 2 | [linked server not using fixed login](https://straightpathsql.com/check/linked-server) |  |  |  | x |  |
| Security | 326 | 2 | [SQL Server Audit running](https://straightpathsql.com/check/sql-server-audit) |  |  |  | x |  |
| Security | 327 | 2 | [database owner is not preferred owner](https://straightpathsql.com/check/database-owner-is-not-preferred-owner) |  |  |  | x |  |
| Security | 328 | 2 | [database owner is a sysadmin](https://www.insidesql.org/blogs/andreaswolter/2014/06/sql-server-database-ownership-survey-results-recommendations) |  |  |  | x |  |
| Security | 329 | 1 | [SQL Server service using built-in elevated account](https://straightpathsql.com/check/service-account-permissions) |  |  |  | x |  |
| Security | 330 | 1 | [no audit of failed logins](https://straightpathsql.com/check/sql-login-audit-does-not-include-failed-logins) |  |  |  | x |  |
| Security | 331 | 1 | [recent failed logins](https://straightpathsql.com/check/failed-logins) |  |  |  | x |  |
| Security | 332 | 2 | [database with TRUSTWORTHY enabled](https://straightpathsql.com/check/trustworthy-enabled) |  |  |  | x |  |
| Security | 333 | 2 | [db_owner role member](https://straightpathsql.com/check/db_owner-role-members) |  |  |  | x |  |
| Security | 334 | 1 | [db_owner role member - system database](https://straightpathsql.com/check/db_owner-role-members) |  |  |  | x |  |
| Security | 335 | 2 | [unusual database permissions](https://straightpathsql.com/check/unusual-database-permissions) |  |  |  | x |  |
| Security | 336 | 1 | [unusual database permissions - system database](https://straightpathsql.com/check/unusual-database-permissions) |  |  |  | x |  |
| Security | 337 | 3 | [roles within roles](https://straightpathsql.com/check/database-roles-within-roles) |  |  |  | x |  |
| Security | 338 | 3 | [orphaned database users](https://straightpathsql.com/check/orphaned-users) |  |  |  | x |  |
| Security | 339 | 2 | [public role permissions](https://straightpathsql.com/check/explicit-permissions-for-public) |  |  |  | x |  |
| Security | 340 | 2 | [sa login has been renamed](https://straightpathsql.com/check/sa-login-renamed) |  |  |  | x |  |
| Security | 341 | 2 | [C2 audit mode enabled](https://straightpathsql.com/check/c2-audit-mode) |  |  |  | x |  |
| Security | 342 | 2 | [Common Criteria Compliance enabled](https://straightpathsql.com/check/common-criteria-compliance) |  |  |  | x |  |
| Security | 343 | 2 | [Contained Database Authentication enabled](https://straightpathsql.com/check/contained-database) |  |  |  | x |  |
| Security | 344 | 2 | [contained databases](https://straightpathsql.com/check/contained-database) |  |  |  | x |  |
| Security | 345 | 2 | [Remote Access is enabled](https://straightpathsql.com/check/remote-access) |  |  |  | x |  |
| Security | 346 | 2 | [databases owned by Windows logins](https://straightpathsql.com/check/database-owner-is-not-preferred-owner) |  |  |  | x |  |
| Security | 347 | 2 | [Hide Instance is enabled](https://straightpathsql.com/check/hide-instance) |  |  |  | x |  |
| Security | 348 | 2 | [Extended Protection is enabled](https://straightpathsql.com/check/extended-protection) |  |  |  | x |  |
| Security | 349 | 2 | [Force Encryption is enabled](https://straightpathsql.com/check/force-encryption) |  |  |  | x |  |
| Security | 350 | 2 | [service account in sysadmin role](https://straightpathsql.com/check/service-account-permissions) |  |  |  | x |  |
| Security | 351 | 1 | [service account in local Administrators group](https://straightpathsql.com/check/service-account-permissions) |  |  |  | x |  |
| Security | 352 | 2 | [SQL Agent proxy account in sysadmin](https://straightpathsql.com/check/proxy-account-in-sysadmin) |  |  |  | x |  |
| Security | 353 | 1 | [xp_cmdshell proxy account exists](https://straightpathsql.com/check/xp_cmdshell) |  |  |  | x |  |
| Security | 354 | 1 | [server-level permissions granted to login (ALTER..., IMPERSONATE...)](https://straightpathsql.com/check/server-level-permissions) |  |  |  | x |  |
| Security | 355 | 1 | [orphaned database user with elevated permissions](https://straightpathsql.com/check/orphaned-user-elevated-permissions) |  |  |  | x |  |
| Security | 356 | 3 | [tempdb encrypted](https://straightpathsql.com/check/tempdb-encrypted) |  |  |  |  | x |
| Security | 357 | 2 | [NTLM authentication in use](https://straightpathsql.com/check/ntlm-authentication) |  |  |  | x |  |
| Security | 358 | 1 | [SPN registration failed](https://straightpathsql.com/check/spn-registration) |  |  | x | x |  |
| Security | 359 | 1 | [Legacy password hash algorithm](https://straightpathsql.com/check/legacy-password-hash) |  |  |  | x |  |
| Security | 360 | 2 | [SQL authentication in use](https://straightpathsql.com/check/sql-authentication) |  |  |  | x |  |
| Security | 361 | 2 | [Guest user has CONNECT permission](https://straightpathsql.com/check/guest-user-connect) |  |  |  | x |  |
| Security | 362 | 2 | [Contained database users](https://straightpathsql.com/check/contained-database-users) |  |  |  | x |  |
| Security | 363 | 2 | [Application roles detected](https://straightpathsql.com/check/application-roles) |  |  |  | x |  |
| Security | 364 | 2 | [Certificate or asymmetric key mapped login](https://straightpathsql.com/check/certificate-mapped-logins) |  |  |  | x |  |
| Security | 365 | 1 | [Server role membership with escalation path](https://straightpathsql.com/check/server-role-escalation) |  |  |  | x |  |
| Security | 366 | 1 | [Custom server role with elevated permissions](https://straightpathsql.com/check/custom-server-role-permissions) |  |  |  | x |  |
| Security | 367 | 2 | [BUILTIN\Administrators exists as a login](https://straightpathsql.com/check/builtin-administrators-login) |  |  |  | x |  |
| Security | 368 | 1 | [ALTER ANY SERVER AUDIT granted to login](https://straightpathsql.com/check/alter-any-server-audit) |  |  |  | x |  |
| Security | 369 | 2 | [Configuration: external scripts enabled](https://straightpathsql.com/check/external-scripts-enabled) |  |  |  | x |  |
| Security | 370 | 1 | [ALTER SETTINGS granted to login](https://straightpathsql.com/check/alter-settings-permission) |  |  |  | x |  |
| Security | 371 | 1 | [Unsigned assembly with elevated permission set](https://straightpathsql.com/check/unsigned-assembly-trustworthy) |  |  |  | x |  |
| Security | 372 | 1 | [Assembly creation permission granted to login](https://straightpathsql.com/check/assembly-permissions) |  |  |  | x |  |
| Security | 373 | 1 | [Trusted assembly registered](https://straightpathsql.com/check/trusted-assembly) |  |  |  | x |  |
| Security | 374 | 1 | [Agent proxy accessible to non-sysadmin](https://straightpathsql.com/check/agent-proxy) |  |  |  | x |  |
| Security | 375 | 1 | [SQLAgentOperatorRole membership](https://straightpathsql.com/check/agent-operator-role) |  |  | x | x |  |
| Security | 376 | 2 | [Logon trigger](https://straightpathsql.com/check/logon-trigger) |  |  |  | x |  |
| Security | 377 | 2 | [Extended stored procedure registered](https://straightpathsql.com/check/extended-stored-procedure) |  |  |  | x |  |
| Security | 378 | 1 | [Always Encrypted column master key on database server](https://straightpathsql.com/check/always-encrypted-key-location) |  |  | x | x |  |
| Security | 379 | 2 | [SQL Server Audit not capturing security actions](https://straightpathsql.com/check/sql-server-audit-coverage) |  |  |  | x |  |
| Security | 380 | 2 | [Endpoint encryption](https://straightpathsql.com/check/endpoint-encryption) | x |  |  | x |  |
| Availability | 401 | 1 | [database in single user mode](https://straightpathsql.com/check/single-user-mode) |  |  | x |  |  |
| Availability | 402 | 1 | [database in restricted user mode](https://straightpathsql.com/check/restricted-user-mode) |  |  | x |  |  |
| Availability | 403 | 2 | [database in read-only mode](https://straightpathsql.com/check/read-only-mode) |  |  | x |  |  |
| Availability | 404 | 2 | [database offline](https://straightpathsql.com/check/database-offline) |  |  | x |  |  |
| Availability | 405 | 1 | [database in suspect status](https://straightpathsql.com/check/suspect-status) |  |  | x |  |  |
| Availability | 406 | 1 | [endpoint owned by user](https://straightpathsql.com/check/endpoint-ownership) | x |  | x | x |  |
| Availability | 407 | 1 | [AG owned by user](https://straightpathsql.com/check/availability-group-ownership) | x |  | x |  |  |
| Availability | 408 | 1 | [Less than 3 quorum members online](https://straightpathsql.com/check/cluster-quorum-members) | x |  |  |  |  |
| Availability | 409 | 1 | [Less than 3 quorum votes among members](https://straightpathsql.com/check/cluster-quorum-members) | x |  |  |  |  |
| Availability | 410 | 1 | [Offline cluster member](https://straightpathsql.com/check/cluster-quorum-members) | x |  |  |  |  |
| Availability | 411 | 1 | [Endpoint not started](https://straightpathsql.com/check/endpoint-not-started) | x |  |  |  |  |
| Availability | 412 | 2 | [Seeding mode different among members](https://straightpathsql.com/check/availability-group-seeding-mode) | x |  |  |  |  |
| Availability | 413 | 1 | [Replica not joined](https://straightpathsql.com/check/replica-not-joined) | x |  |  |  |  |
| Availability | 414 | 1 | [Database data movement suspended](https://straightpathsql.com/check/availability-group-data-movement) | x |  |  |  |  |
| Availability | 415 | 2 | [Session timeout at default or less](https://straightpathsql.com/check/availability-group-session-timeout) | x |  |  |  |  |
| Availability | 416 | 2 | [AG backup preference not Primary](https://straightpathsql.com/check/availability-group-backup-preference) | x |  |  |  |  |
| Availability | 417 | 1 | [Listener offline](https://straightpathsql.com/check/listener-offline) | x |  |  |  |  |
| Availability | 418 | 2 | [Seeding mode set to Automatic (not Manual)](https://straightpathsql.com/check/availability-group-seeding-mode) | x |  |  |  |  |
| Availability | 419 | 3 | [Trace flag 9567 enabled](https://straightpathsql.com/check/trace-flag-9567) | x |  |  |  |  |
| Availability | 420 | 2 | [Endpoint using expiring certificate](https://straightpathsql.com/check/endpoint-using-expiring-certificate) | x |  |  |  |  |
| Availability | 421 | 1 | [Replica is not failover ready](https://straightpathsql.com/check/replica-not-failover-ready) | x |  |  |  |  |
| Availability | 422 | 2 | [High HADR_SYNC_COMMIT waits](https://straightpathsql.com/check/hadr_sync_commit) | x |  |  |  |  |
| Availability | 423 | 2 | [High secondary lag](https://straightpathsql.com/check/secondary-lag) | x |  |  |  |  |
| Availability | 424 | 2 | [Health Check Timeout at default](https://straightpathsql.com/check/health-check-timeout) | x |  |  |  |  |
| Availability | 425 | 3 | [Trace flag 1800 enabled](https://straightpathsql.com/check/trace-flag-1800) | x |  |  |  |  |
| Availability | 426 | 2 | [Recent state change](https://straightpathsql.com/check/availability-group-state-change) | x |  |  |  |  |
| Availability | 427 | 2 | [Different failover modes - same AG](https://straightpathsql.com/check/availability-group-failover-mode) | x |  |  |  |  |
| Availability | 428 | 2 | [Different failover modes - same instance](https://straightpathsql.com/check/availability-group-failover-mode) | x |  |  |  |  |
| Availability | 429 | 1 | [AlwaysOn_health XE stopped](https://straightpathsql.com/check/alwayson-health-extended-event) | x |  |  |  |  |
| Availability | 430 | 1 | [Database not synchronized on a synchronous replica](https://straightpathsql.com/check/synchronous-replica-not-synchronized) | x |  |  |  |  |
| Availability | 431 | 1 | [replica disconnected](https://straightpathsql.com/check/replica-disconnected) | x |  |  |  |  |
| Availability | 432 | 1 | [service account does not have CONNECT permission on the endpoint](https://straightpathsql.com/check/endpoint-connect-permission) | x |  |  |  |  |
| Integrity | 501 | 1 | [databases with page verification not CHECKSUM](https://straightpathsql.com/check/database-page-verification) |  |  | x |  |  |
| Integrity | 502 | 1 | [alerts 19-25 or 823-825 not set](https://straightpathsql.com/check/alerts) |  |  | x |  |  |
| Integrity | 503 | 1 | [databases with missing integrity checks](https://straightpathsql.com/check/missing-integrity-checks) |  | x | x |  |  |
| Integrity | 504 | 1 | [databases with corruption detected](https://straightpathsql.com/check/database-corruption) | x |  | x |  |  |
| Integrity | 505 | 2 | [disabled alerts](https://straightpathsql.com/check/alerts) |  |  | x |  |  |
| Integrity | 506 | 2 | [automatic page repair activity](https://straightpathsql.com/check/automatic-page-repair) | x |  |  |  |  |
| Reliability | 601 | 1 | [approved SQL Server update available](https://straightpathsql.com/check/security-update) |  |  | x | x |  |
| Reliability | 602 | 1 | [SQL version out of support](https://straightpathsql.com/check/unsupported-versions) |  |  | x | x |  |
| Reliability | 603 | 3 | [instance online over 180 days](https://straightpathsql.com/check/instance-uptime) |  |  | x |  | x |
| Reliability | 604 | 1 | [tempdb on C:\ and more than 1 drive is on server](https://straightpathsql.com/check/tempdb-files-on-c-drive) |  |  | x |  | x |
| Reliability | 605 | 2 | [tempdb database files with no growth allowed](https://straightpathsql.com/check/tempdb-no-growth-allowed) |  |  | x |  | x |
| Reliability | 606 | 1 | [user database files are on C:\ and more than 1 disk on server (not tempdb)](https://straightpathsql.com/check/database-files-best-practice) |  |  | x |  |  |
| Reliability | 607 | 2 | [user database files with no growth allowed (not tempdb)](https://straightpathsql.com/check/database-files-best-practice) |  |  | x |  |  |
| Reliability | 608 | 2 | [user database log and data files are on the same drive (not tempdb)](https://straightpathsql.com/check/database-files-best-practice) |  |  | x |  |  |
| Reliability | 609 | 2 | [agent job is enabled but schedule is disabled](https://straightpathsql.com/check/sql-agent-job-schedule) |  |  | x |  |  |
| Reliability | 610 | 2 | [agent job is enabled but there is no schedule](https://straightpathsql.com/check/sql-agent-job-schedule) |  |  | x |  |  |
| Reliability | 611 | 2 | [jobs owned by user](https://straightpathsql.com/check/sql-agent-jobs-owned-by-users) |  |  | x | x |  |
| Reliability | 612 | 2 | [default data file path is on C:\ and more than 1 disk is on server](https://straightpathsql.com/check/default-file-path) |  |  | x |  |  |
| Reliability | 613 | 2 | [default data log path is on C:\ and more than 1 disk is on server](https://straightpathsql.com/check/default-file-path) |  |  | x |  |  |
| Reliability | 614 | 2 | [default backup path is on C:\ and more than 1 disk is on server](https://straightpathsql.com/check/default-file-path) |  |  | x |  |  |
| Reliability | 615 | 2 | [min mem >= max mem](https://straightpathsql.com/check/memory-best-practices) |  |  | x |  |  |
| Reliability | 616 | 2 | [max memory at default](https://straightpathsql.com/check/memory-best-practices) |  |  | x |  |  |
| Reliability | 617 | 2 | [SERVERPROPERTY('servername') and @@servername alignment](https://straightpathsql.com/check/server-name) | x |  | x |  |  |
| Reliability | 618 | 1 | [10% or less available drive space](https://straightpathsql.com/check/low-drive-space) |  |  | x |  |  |
| Reliability | 619 | 1 | [tempdb file with max file size set](https://straightpathsql.com/check/tempdb-max-file-size) |  |  |  |  | x |
| Reliability | 620 | 2 | [database file (not tempdb) with max file size set](https://straightpathsql.com/check/database-max-file-size) |  |  | x |  |  |
| Reliability | 621 | 1 | [Evaluation Edition](https://straightpathsql.com/check/evaluation-edition) |  |  | x |  |  |
| Reliability | 622 | 2 | [error log retention is at default](https://straightpathsql.com/check/number-of-sql-server-error-log-files) |  |  | x | x |  |
| Reliability | 623 | 2 | [replication in use](https://straightpathsql.com/check/replication) |  |  | x |  |  |
| Reliability | 624 | 1 | [low available physical memory](https://straightpathsql.com/check/memory-best-practices) |  |  | x |  |  |
| Reliability | 625 | 2 | [database snapshot](https://straightpathsql.com/check/database-snapshot) |  |  | x |  |  |
| Reliability | 626 | 2 | [pending configuration change](https://straightpathsql.com/check/instance-configurations) |  |  | x |  |  |
| Reliability | 627 | 2 | [unusual database state](https://straightpathsql.com/check/unusual-database-state) |  |  | x |  |  |
| Reliability | 628 | 1 | [SQL Agent offline](https://straightpathsql.com/check/sql-agent-offline) |  | x | x |  |  |
| Reliability | 629 | 1 | [memory dumps](https://straightpathsql.com/check/memory-dumps) |  |  | x |  |  |
| Reliability | 630 | 1 | [user database with file named master](https://desertdba.com/failovers-cant-serve-two-masters/) |  |  | x |  |  |
| Reliability | 631 | 1 | [priority boost](https://straightpathsql.com/check/priority-boost) |  |  | x |  |  |
| Reliability | 632 | 1 | [system databases below installed compatibility level](https://straightpathsql.com/check/system-database-compatibility-level) |  |  | x |  |  |
| Reliability | 633 | 1 | [Configuration: default trace disabled](https://straightpathsql.com/check/default-trace-disabled) |  |  | x | x |  |
| Performance | 701 | 2 | [cost threshold for parallelism at default](https://straightpathsql.com/check/cost-threshold-for-parallelism) |  |  | x |  |  |
| Performance | 702 | 2 | [MAXDOP at default or 1](https://straightpathsql.com/check/max-degree-of-parallelism) |  |  | x |  |  |
| Performance | 703 | 2 | [database with auto shrink enabled](https://straightpathsql.com/check/auto-shrink) |  |  | x |  |  |
| Performance | 704 | 2 | [database auto close enabled](https://straightpathsql.com/check/auto-close) |  |  | x |  |  |
| Performance | 705 | 2 | [database with lower compatibility level](https://straightpathsql.com/check/compatibility-level) |  |  | x |  |  |
| Performance | 706 | 2 | [trace flag recommendations (not 1117 & 1118)](https://straightpathsql.com/check/trace-flags) |  |  | x |  |  |
| Performance | 707 | 1 | [tempdb number of files](https://straightpathsql.com/check/tempdb-data-file-growth) |  |  | x |  | x |
| Performance | 708 | 1 | [tempdb unequal/different file sizes](https://straightpathsql.com/check/tempdb-data-file-size) |  |  | x |  | x |
| Performance | 709 | 1 | [tempdb data files with uneven growth rates](https://straightpathsql.com/check/tempdb-data-file-growth) |  |  | x |  | x |
| Performance | 710 | 2 | [tempdb log file larger than data file](https://straightpathsql.com/check/tempdb-log-file-size) |  |  | x |  | x |
| Performance | 711 | 1 | [tempdb database files with % growth](https://straightpathsql.com/check/tempdb-data-file-growth) |  |  | x |  | x |
| Performance | 712 | 1 | [tempdb database files with < 64 MB growth](https://straightpathsql.com/check/tempdb-data-file-growth) |  |  | x |  | x |
| Performance | 713 | 1 | [tempdb database has more than 1 log file](https://straightpathsql.com/check/tempdb-multiple-log-files) |  |  | x |  | x |
| Performance | 714 | 1 | [tempdb data or log files with high percent usage](https://straightpathsql.com/check/tempdb-files-with-high-usage) |  |  | x |  | x |
| Performance | 715 | 2 | [trace flag 1117 not enabled (SQL Server 2014 and earlier)](https://straightpathsql.com/check/trace-flag-1117) |  |  | x |  | x |
| Performance | 716 | 2 | [trace flag 1118 not enabled (SQL Server 2014 and earlier)](https://straightpathsql.com/check/trace-flag-1118) |  |  | x |  | x |
| Performance | 717 | 2 | [tempdb in-memory metadata enabled in SQL Server 2019 or later](https://straightpathsql.com/check/tempdb-memory-optimized) |  |  | x |  | x |
| Performance | 718 | 1 | [tempdb slow reads](https://straightpathsql.com/check/tempdb-slow-reads-and-writes) |  |  | x |  | x |
| Performance | 719 | 1 | [tempdb slow writes](https://straightpathsql.com/check/tempdb-slow-reads-and-writes) |  |  | x |  | x |
| Performance | 720 | 2 | [log file larger than data file (not tempdb)](https://straightpathsql.com/check/database-log-file-size) |  |  | x |  |  |
| Performance | 721 | 1 | [database files with % growth (not tempdb)](https://straightpathsql.com/check/database-file-growth) |  |  | x |  |  |
| Performance | 722 | 1 | [database files with < 64 MB growth (not tempdb)](https://straightpathsql.com/check/database-file-growth) |  |  | x |  |  |
| Performance | 723 | 1 | [database has more than 1 log file (not tempdb)](https://straightpathsql.com/check/database-multiple-log-files) |  |  | x |  |  |
| Performance | 724 | 1 | [power plan check](https://straightpathsql.com/check/power-plan) |  |  | x |  |  |
| Performance | 725 | 1 | [instant file initialization check](https://straightpathsql.com/check/instant-file-initialization) |  |  | x |  |  |
| Performance | 726 | 2 | [locked pages in memory in use](https://straightpathsql.com/check/lock-pages-in-memory) |  |  | x |  |  |
| Performance | 727 | 2 | [Resource Governor used for tempdb](https://learn.microsoft.com/en-us/sql/relational-databases/resource-governor/tempdb-space-resource-governance?view=sql-server-ver17) |  |  |  |  | x |
| Performance | 728 | 2 | [auto create stats disabled](https://straightpathsql.com/check/auto-create-statistics) |  |  | x |  |  |
| Performance | 729 | 1 | [unused CPU cores with VM socket and core configuration](https://straightpathsql.com/check/offline-cpu-schedulers) |  |  | x |  |  |
| Performance | 730 | 1 | [tempdb has more than 16 data files](https://straightpathsql.com/check/tempdb-data-file-growth) |  |  |  |  | x |
| Performance | 731 | 2 | [resource governor enabled](https://straightpathsql.com/check/resource-governor) |  |  | x |  |  |
| Performance | 732 | 2 | [enabled server-level triggers](https://straightpathsql.com/check/server-level-triggers) |  |  | x |  |  |
| Performance | 733 | 2 | [change tracking enabled](https://straightpathsql.com/check/change-tracking) |  |  | x |  |  |
| Performance | 734 | 2 | [recursive triggers enabled](https://straightpathsql.com/check/recursive-triggers) |  |  | x |  |  |
| Performance | 735 | 2 | [forced parameterization enabled](https://straightpathsql.com/check/forced-parameterization) |  |  | x |  |  |
| Performance | 736 | 2 | [change data capture enabled](https://straightpathsql.com/check/change-data-capture) |  |  | x |  |  |
| Performance | 737 | 2 | [delayed durability enabled](https://straightpathsql.com/check/delayed-durability) |  |  | x |  |  |
| Performance | 738 | 2 | [custom extended events running](https://straightpathsql.com/check/extended-events) |  |  | x |  |  |
| Performance | 739 | 2 | [I/O freeze detected](https://straightpathsql.com/check/i-o-freeze) |  | x | x |  |  |
| Performance | 740 | 2 | [auto update stats disabled](https://straightpathsql.com/check/auto-update-statistics) |  |  | x |  |  |
| Performance | 741 | 2 | [Accelerated Database Recovery used for tempdb](https://learn.microsoft.com/en-us/sql/relational-databases/accelerated-database-recovery-management?view=sql-server-ver17) |  |  |  |  | x |
| Performance | 742 | 2 | [locked pages in memory with no max memory set](https://straightpathsql.com/check/lock-pages-in-memory) |  |  | x |  |  |
| Performance | 743 | 1/2 | [Large version store](https://straightpathsql.com/check/tempdb-version-store) |  |  |  |  | x |

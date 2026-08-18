IF OBJECT_ID('dbo.sp_CheckHealth') IS NULL
  EXEC ('CREATE PROCEDURE dbo.sp_CheckHealth AS RETURN 0;');
GO


ALTER PROCEDURE dbo.sp_CheckHealth
	@Mode TINYINT = 99
	, @DatabaseName NVARCHAR(255) = NULL
	, @Override BIT = 0
	, @Help BIT = 0
	, @VersionCheck BIT = 0

WITH RECOMPILE
AS
SET NOCOUNT ON;

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE
    @Version VARCHAR(10) = NULL
	, @VersionDate DATETIME = NULL

SELECT
    @Version = '2026.8.2'
    , @VersionDate = '20260811';

/* Version check */
IF @VersionCheck = 1 BEGIN

	SELECT
		@Version AS VersionNumber
		, @VersionDate AS VersionDate

	RETURN;
	END;  

/* @Help = 1 */
IF @Help = 1 BEGIN
	PRINT '
/*
    sp_CheckHealth from https://straightpathsql.com/

	Version: ' + @Version + ' updated ' + CONVERT(VARCHAR(10), @VersionDate, 101) + '
    	
    This stored procedure checks your SQL Server for all kinds of issues and 
    provides a list of findings with action items. It also can be used to provide
    a comprehensive set of information about your instance.
    
    Known limitations of this version:
    - sp_CheckHealth only works Microsoft-supported versions of SQL Server, so 
    that means SQL Server 2014 or later.
    - sp_CheckHealth will work with some earlier versions of SQL Server, but it 
    will skip a few checks. The results should still be valid and helpful, but you
    should really consider upgrading to a newer version.

    Permissions:
    - The minimum required is VIEW SERVER STATE and VIEW ANY DEFINITION. Note that
    some checks will be skipped unless executed by a member of sysadmin.

    Parameters:

    @Mode  0=Show only problematic issues, unfiltered
           1=Show instance information only
		   11=Show instance information only in one row
		   99=Show instance information and problematic issues (default)
    @DatabaseName  use to provide info on a specific database
    MIT License
    
    Copyright for portions of sp_CheckHealth are also held by Brent Ozar Unlimited
    as part of sp_Blitz and are provided under the MIT license:
    https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/
    	
    All other copyrights for sp_CheckHealth are held by Straight Path Solutions.
    
    Copyright 2026 Straight Path IT Solutions, LLC
    
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

*/';
	RETURN;
	END;  

/* Check if @Override needed for too many databases */
IF @Override = 0 
	AND @Mode <> 11
	AND ((SELECT COUNT(database_id) from sys.databases where source_database_id IS NULL) > 50) BEGIN
	PRINT '
	You have over 50 databases, so you could have a lot of backup history.

	If you want to proceed, and you understand this procedure could use
	substantial resources to get your backup history, use @Override = 1.

	Godspeed, my friend.
'
	RETURN;
	END;  

/* set some defaults */
DECLARE 
	@SQL NVARCHAR(MAX)
    , @SQLParameters NVARCHAR(500)
	, @SQLVersion NVARCHAR(128)
	, @SQLVersionMajor DECIMAL(10,2)
	, @SQLVersionMinor DECIMAL(10,2)
	, @ComputerNamePhysicalNetBIOS NVARCHAR(128)
	, @ServerZeroName sysname
	, @InstanceName NVARCHAR(128)
	, @DatabaseID INT
	, @Edition NVARCHAR(128)
    , @physical_memory_in_MB numeric(18,0)
	, @MinMemoryMB NUMERIC(18,0)
	, @MaxMemoryMB NUMERIC(18,0)
	, @NumberOfDataFiles INT
    , @NumberOfCPUCores INT
    , @NumberOfCPUSockets INT
	, @NumberOfDrivesOtherThanC INT
	, @DefaultDataPath NVARCHAR(4000)
	, @DefaultLogPath NVARCHAR(4000)
	, @DefaultBackupPath NVARCHAR(4000)
	, @PowerPlan VARCHAR(36)
	, @NumberOfErrorLogs INT
	, @UsagePercent TINYINT = 50
	, @AvgReadStallMs INT = 100
	, @AvgWriteStallMs INT = 100
	, @IsSysadmin BIT = ISNULL(IS_SRVROLEMEMBER('sysadmin'), 0); /* some checks read the error log, registry, SQL Agent metadata, or run sp_validatelogins, all of which require sysadmin; they are skipped when this is 0 */

DECLARE @ServerType NVARCHAR(1000);

DECLARE @ServerTypeText TABLE (
	LogDate DATETIME
	, ProcessInfo NVARCHAR(100)
	, LogText NVARCHAR(1000)
	);

DECLARE @OperatingSystem NVARCHAR(1000)

DECLARE @OperatingSystemText TABLE (
	LogDate DATETIME
	, ProcessInfo NVARCHAR(100)
	, LogText NVARCHAR(1000)
	);

DECLARE @IFIEnabled CHAR(1) = NULL
       , @IFIDetermined BIT = 0;

DECLARE @IFIErrorLog TABLE (
	LogDate DATETIME
	, ProcessInfo NVARCHAR(100)
	, LogText NVARCHAR(1000)
	);

IF OBJECT_ID('tempdb..#Category') IS NOT NULL
	DROP TABLE #Category;

CREATE TABLE #Category (
    CategoryID TINYINT
	, CategoryName VARCHAR(50)
	);

INSERT #Category (CategoryID, CategoryName)
VALUES
    (0, '')
	, (1, 'Discovery')
    , (2, 'Recoverability')
    , (3, 'Security')
    , (4, 'Availability')
    , (5, 'Integrity')
    , (6, 'Reliability')
    , (7, 'Performance');

IF OBJECT_ID('tempdb..#Results') IS NOT NULL
	DROP TABLE #Results;

CREATE TABLE #Results (
	CategoryID TINYINT
	, CheckID INT
	, [Importance] TINYINT
	, CheckName VARCHAR(100)
	, Issue NVARCHAR(MAX)
	, DatabaseName NVARCHAR(255)
	, Details NVARCHAR(MAX)
	, ActionStep NVARCHAR(MAX)
	, ReadMoreURL XML
	);

INSERT #Results
	SELECT
		0
		, 0
		, 0
		, 'sp_CheckHealth'
		, 'Provided by Straight Path IT Solutions, LLC'
		, NULL
		, '(Information captured on ' + CONVERT(VARCHAR(100), GETDATE(), 101) + ' using version ' + @Version + ')'
		, 'Use this FREE tool to check your SQL Server databases for all sorts of issues!'
		, 'https://straightpathsql.com/tool/sp_checkhealth/'

IF OBJECT_ID('tempdb..#Database') IS NOT NULL
	DROP TABLE #Database;

CREATE TABLE #Database (
	DatabaseID INT
	, DatabaseName NVARCHAR(255)
	, Checked BIT
	);

INSERT #Database (DatabaseID, DatabaseName, Checked)
SELECT 
	database_id
	, [name]
	, 0
FROM master.sys.databases
WHERE [state] = 0 /* database is online */
	AND database_id > 4
	AND [name] = COALESCE(@DatabaseName, [name]);


IF OBJECT_ID('tempdb..#SQLVersions') IS NOT NULL
	DROP TABLE #SQLVersions;

CREATE TABLE #SQLVersions (
	VersionName VARCHAR(10)
	, VersionNumber DECIMAL(10,2)
	);

INSERT #SQLVersions
VALUES
	('2008', 10)
	, ('2008 R2', 10.5)
	, ('2012', 11)
	, ('2014', 12)
	, ('2016', 13)
	, ('2017', 14)
	, ('2019', 15)
	, ('2022', 16)
	, ('2025', 17);

/* SQL Server version */
SELECT @SQLVersion = CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128));

SELECT 
	@SQLVersionMajor = SUBSTRING(@SQLVersion, 1,CHARINDEX('.', @SQLVersion) + 1 )
	, @SQLVersionMinor = PARSENAME(CONVERT(varchar(32), @SQLVersion), 2);

--/* check for unsupported version */	
--IF @SQLVersionMajor < 12 BEGIN
--	PRINT '
--/*
--	*** Unsupported SQL Server Version ***

--	sp_CheckHealth is supported only for execution on SQL Server 2014 and later.

--	For more information about the limitations of sp_CheckHealth, execute
--	using @Help = 1

--	*** EXECUTION ABORTED ***
    	   
--*/';
--	RETURN;
--	END; 

SELECT 
	@NumberOfCPUCores = cpu_count
	, @NumberOfCPUSockets = (cpu_count/hyperthread_ratio)
FROM sys.dm_os_sys_info;

SELECT
	@ComputerNamePhysicalNetBIOS = CAST(SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS NVARCHAR(128))
	, @InstanceName = CAST(SERVERPROPERTY('InstanceName') AS NVARCHAR(128))
	, @Edition = CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128));

SELECT @ServerZeroName = [name]
FROM sys.servers
WHERE server_id = 0


/* trace flags in use globally */
IF OBJECT_ID('tempdb..#TraceFlag') IS NOT NULL
	DROP TABLE #TraceFlag;

CREATE TABLE #TraceFlag
	(
		TraceFlag VARCHAR(10) ,
		Status BIT ,
		Global BIT ,
		Session BIT
	);

INSERT #TraceFlag
EXEC ('DBCC TRACESTATUS(-1) WITH NO_INFOMSGS');

SELECT
	@DefaultDataPath = CONVERT(NVARCHAR(4000), SERVERPROPERTY('InstanceDefaultDataPath'))
	, @DefaultLogPath = CONVERT(NVARCHAR(4000), SERVERPROPERTY('InstanceDefaultLogPath'))
	, @DefaultBackupPath = CONVERT(NVARCHAR(4000), SERVERPROPERTY('InstanceDefaultBackupPath'))

IF OBJECT_ID('tempdb..#Drives') IS NOT NULL
	DROP TABLE #Drives;

CREATE TABLE #Drives (
	Drive NVARCHAR(2)
	, LogicalVolumeName NVARCHAR(36)
	, TotalMB DECIMAL(18,0)
	, FreeMB DECIMAL(18,0)
	, UsedPercent DECIMAL(18,2)
	);

INSERT INTO #Drives	(Drive, FreeMB )
EXEC master..xp_fixeddrives;
								
IF EXISTS (SELECT * FROM sys.all_objects WHERE [name] = 'dm_os_volume_stats') BEGIN
	SET @SQL = 'Update #Drives
	SET
		LogicalVolumeName = v.LogicalVolumeName,
		TotalMB = v.TotalMB,
		UsedPercent = v.UsedPercent
	FROM #Drives
	INNER JOIN (
		SELECT DISTINCT
			SUBSTRING(volume_mount_point, 1, 1) AS VolumeMountPoint
			, CASE WHEN ISNULL(logical_volume_name,'''') = '''' THEN '''' ELSE ''('' + logical_volume_name + '')'' END AS LogicalVolumeName
			, total_bytes/1024/1024 AS TotalMB
			, available_bytes/1024/1024 AS FreeMB
			, (CONVERT(DECIMAL(5,2),(total_bytes/1.0 - available_bytes)/total_bytes * 100)) AS UsedPercent
		FROM
			(SELECT TOP 1 WITH TIES 
				database_id
				, file_id
				, SUBSTRING(physical_name,1,1) AS Drive
				FROM sys.master_files
				ORDER BY ROW_NUMBER() OVER(PARTITION BY SUBSTRING(physical_name,1,1) ORDER BY database_id)
			) f
		CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.file_id)
	) as v
		ON #Drives.Drive = v.VolumeMountPoint;';

	EXEC sp_executesql @SQL;

	END;

SET @NumberOfDrivesOtherThanC = (
	SELECT COUNT(Drive)
	FROM #Drives
	WHERE Drive <> 'C');

/*
Endpoints
*/

IF OBJECT_ID('tempdb..#Endpoints') IS NOT NULL
	DROP TABLE #Endpoints;

CREATE TABLE #Endpoints (
	EndpointName NVARCHAR(128)
	, EndpointOwner NVARCHAR(128)
	, EndpointOwnerSID VARBINARY(85)
	, EndpointState NVARCHAR(60)
	, AuthenticationType NVARCHAR(60)
	, CertificateName NVARCHAR(128)
	, CertificateExpiration DATETIME
	);

INSERT #Endpoints
SELECT
	e.[name] /* EndpointName */
	, sp.[name] /* EndpointOwner */
	, sp.[sid] /* EndpointOwnerSID */
	, REPLACE(e.state_desc, '_',' ')
	, dme.connection_auth_desc
	, COALESCE(c.name, '(Windows Authentication)')
	, c.expiry_date
FROM master.sys.endpoints e
INNER JOIN sys.server_principals sp
	ON e.principal_id = sp.principal_id
INNER JOIN sys.database_mirroring_endpoints dme
	ON e.endpoint_id = dme.endpoint_id
LEFT JOIN sys.certificates c
	ON dme.certificate_id = c.certificate_id
WHERE e.[type] = 4; /*Database Mirroring*/


/* 
Discovery
*/
IF @Mode IN (1, 11, 99) BEGIN /* Collect instance info */
	/* server name */
	INSERT #Results
	SELECT 
		1
		, 101
		, 0
		, 'Server Name'
		, 'Server Name'
		, NULL
		, COALESCE(@ComputerNamePhysicalNetBIOS,'')
		, NULL
		, '';

	/* instance name */
	INSERT #Results
	SELECT
		 1
		, 102
		, 0
		, 'Instance Name'
		, 'Instance Name'
		, NULL
		, COALESCE(@InstanceName, '(default instance)')
		, NULL
		, '';

	/* instance version */
	INSERT #Results
	SELECT 
		 1
		, 103
		, 0
		, 'Instance Version'
		, 'Instance Version'
		, NULL
		, 'SQL Server ' + VersionName
		, NULL
		, ''
	FROM #SQLVersions
	WHERE VersionNumber = @SQLVersionMajor;

	/* instance edition */
	INSERT #Results
	SELECT 
		 1
		, 104
		, 0
		, 'Instance Edition'
		, 'Instance Edition'
		, NULL
		, @Edition
		, NULL
		, '';

	/* instance build */
	INSERT #Results
	SELECT 
		 1
		, 105
		, 0
		, 'Instance Build'
		, 'Instance Build'
		, NULL
		, @SQLVersion
		, NULL
		, '';

	/* error log location */
	IF OBJECT_ID('tempdb..#ErrorLogLoc') IS NOT NULL
		DROP TABLE #ErrorLogLoc;

	CREATE TABLE #ErrorLogLoc (
		LogDate datetime2
		, ProcessInfo VARCHAR(50)
		, ErrorLogText VARCHAR(1000)
		);

	/* reading the error log requires sysadmin; skip when the caller is not a member */
	IF @IsSysadmin = 1 BEGIN
		INSERT #ErrorLogLoc (LogDate, ProcessInfo, ErrorLogText)
		EXEC master.sys.xp_readerrorlog 0, 1, N'Logging SQL Server messages in file', NULL, NULL, NULL, N'asc';
	END;


	INSERT #Results
	SELECT 
		 1
		, 106
		, 0
		, 'Error Log Location'
		, 'Error Log Location'
		, NULL
		, REPLACE(REPLACE(ErrorLogText, '''.',''), 'Logging SQL Server messages in file ''', '')
		, NULL
		, ''
	FROM #ErrorLogLoc;

	/* default data file path */
	INSERT #Results
	SELECT 
		 1
		, 107
		, 0
		, 'Default Data File Path'
		, 'Default Data File Path'
		, NULL
		, @DefaultDataPath
		, NULL
		, '';

	/* default log file path */
	INSERT #Results
	SELECT 
		 1
		, 108
		, 0
		, 'Default Log File Path'
		, 'Default Log File Path'
		, NULL
		, @DefaultLogPath
		, NULL
		, '';

	/* default backup file path */
	INSERT #Results
	SELECT 
		 1
		, 109
		, 0
		, 'Default Backup File Path'
		, 'Default Backup File Path'
		, NULL
		, @DefaultBackupPath
		, NULL
		, '';

	INSERT #Results
	SELECT 
		 1
		, 110
		, 0
		, 'Trace Flag In Use'
		, 'Trace Flag ' + TraceFlag + ' is enabled globally'
		, NULL
		, CASE TraceFlag
			WHEN '1117' THEN '1117 enables all files in a filegroup to grow at the same time.'
			WHEN '1118' THEN '1118 avoids the use of mixed extents so each object has its own 64 KB data space.'
			WHEN '2371' THEN '2371 lowers the auto update statistics threshold for large tables.'
			WHEN '3226' THEN '3226 suppresses successful backup messages from the error log.'
			WHEN '7745' THEN '7745 prevents Query Store data from being written to disk during failover or shutdown.'
			WHEN '7752' THEN '7752 enables asynchronous loading of Query Store data.'
			ELSE 'Look up this trace flag.'
			END
		, NULL
		, ''
	FROM #TraceFlag;

	/* communication protocol */
	INSERT #Results
	SELECT 
		 1
		, 111
		, 0
		, 'Communication Protocol'
		, 'Communication Protocol'
		, NULL
		, CONVERT(VARCHAR(20),CONNECTIONPROPERTY('net_transport')) + CASE
			WHEN CONVERT(VARCHAR(10),CONNECTIONPROPERTY('net_transport')) = 'TCP' THEN ' on port ' + CONVERT(VARCHAR(10),CONNECTIONPROPERTY('local_tcp_port')) 
			ELSE '' END
		, NULL
		, '';

	/* last restart time */
	INSERT #Results
	SELECT 
		 1
		, 112
		, 0
		, 'Last Restart Time'
		, 'Last Restart Time'
		, NULL
		, CONVERT(VARCHAR(50),sqlserver_start_time, 121)
		, NULL
		, ''
	 FROM sys.dm_os_sys_info;

	/* CPU configuration */
	INSERT #Results
	SELECT 
		 1
		, 113
		, 0
		, 'CPU Configuration'
		, 'CPU Configuration'
		, NULL
		, CONVERT(VARCHAR(4), cpu_count) + ' core(s) across ' + CONVERT(VARCHAR(4), (cpu_count/hyperthread_ratio)) + ' NUMA node(s)'
		, NULL
		, ''
	 FROM sys.dm_os_sys_info;
 
	/* server memory */
	IF @SQLVersionMajor < 11.0 BEGIN
		SET @SQL = 'SELECT @physical_memory_in_MB_out = (SELECT physical_memory_in_bytes/(1024 * 1024) FROM sys.dm_os_sys_info)';

		SET @SQLParameters = '@physical_memory_in_MB_out NUMERIC(18,0) OUTPUT'
	
		EXEC sp_executesql @SQL, @SQLParameters, @physical_memory_in_MB_out = @physical_memory_in_MB OUTPUT

		END

	IF @SQLVersionMajor >= 11.0 BEGIN
		SET @SQL = 'SELECT @physical_memory_in_MB_out = (SELECT physical_memory_kb/1024 FROM sys.dm_os_sys_info)';

		SET @SQLParameters = '@physical_memory_in_MB_out NUMERIC(18,0) OUTPUT'
	
		EXEC sp_executesql @SQL, @SQLParameters, @physical_memory_in_MB_out = @physical_memory_in_MB OUTPUT

		END

	INSERT #Results
	SELECT 
		 1
		, 114
		, 0
		, 'Server Memory in MB'
		, 'Server Memory in MB'
		, NULL
		, @physical_memory_in_MB
		, NULL
		, '';

	/* operating system */
	INSERT @OperatingSystemText
	EXEC sp_readerrorlog 0, 1, 'Copyright';

	SELECT @OperatingSystem = SUBSTRING (LogText, CHARINDEX ('Windows', LogText), LEN(LogText))
	FROM @OperatingSystemText

	INSERT #Results
	SELECT 
		 1
		, 115
		, 0
		, 'Operating System'
		, 'Operating System'
		, NULL
		, @OperatingSystem
		, NULL
		, ''

	/* SQL Server service account */
	INSERT #Results
	SELECT 
		 1
		, 116
		, 0
		, 'SQL Server Service Account'
		, 'SQL Server Service Account'
		, NULL
		, service_account
		, NULL
		, ''
	FROM sys.dm_server_services 
	WHERE servicename like 'SQL Server (%';

	/* SQL Agent service account */
	INSERT #Results
	SELECT 
		 1
		, 117
		, 0
		, 'SQL Agent Service Account'
		, 'SQL Agent Service Account'
		, NULL
		, service_account
		, NULL
		, ''
	FROM sys.dm_server_services 
	WHERE servicename like 'SQL Server Agent%';

	/* instance count */
	IF OBJECT_ID('tempdb..#Instances') IS NOT NULL
		DROP TABLE #Instances;

	CREATE TABLE #Instances (
		InstanceItem NVARCHAR(1000) 
		, InstanceName NVARCHAR(1000)
		, SomeData NVARCHAR(1000)
		);

	/* the registry read requires sysadmin; skip when the caller is not a member
	   (xp_regread under a non-sysadmin also emits a token stream that .NET
	   SqlClient/SSMS aborts on with "A severe error occurred on the current command") */
	IF @IsSysadmin = 1 BEGIN
		INSERT #Instances (InstanceItem, InstanceName, SomeData)
		EXEC master.sys.xp_regread
			@rootkey = 'HKEY_LOCAL_MACHINE',
			@key = 'SOFTWARE\Microsoft\Microsoft SQL Server',
			@value_name = 'InstalledInstances'

		INSERT #Results
		SELECT
			 1
			, 118
			, 0
			, 'Instance count'
			, 'Instance count'
			, NULL
			, COUNT(InstanceName)
			, NULL
			, ''
		FROM #Instances;
	END;

	/* IP address */
	INSERT #Results
	SELECT 
		1
		, 119
		, 0
		, 'IP address'
		, 'IP address'
		, NULL
		, COALESCE(CONVERT(VARCHAR(15), CONNECTIONPROPERTY('local_net_address')), 'UNKNOWN')
		, ''
		, '';

	/* server info */
	INSERT @ServerTypeText
	EXEC sp_readerrorlog 0, 1, 'System Manufacturer:';

	SELECT @ServerType = REPLACE(REPLACE(REPLACE(LogText, 'System Manufacturer: ''', ''), ''', System Model: ''',': '), '''.', '')
	FROM @ServerTypeText

	INSERT #Results
	SELECT 
		 1
		, 120
		, 0
		, 'Server Type'
		, 'Server Type'
		, NULL
		, @ServerType
		, NULL
		, ''

		END;

IF @Mode IN (0, 99) BEGIN /* Collect issue info */

	/* grab databases and availability group info */
	IF OBJECT_ID('tempdb..#AvailabilityGroup') IS NOT NULL
		DROP TABLE #AvailabilityGroup;

	CREATE TABLE #AvailabilityGroup (
		DatabaseID INT
		, DatabaseName NVARCHAR(255)
		, GroupID UNIQUEIDENTIFIER
		, GroupName NVARCHAR(255)
		, IsPreferredBackupReplica BIT
		);

	/* Get Availability Group info for SQL Server 2012 and later */
	IF SERVERPROPERTY('EngineEdition') <> 8 /* Azure Managed Instances */ BEGIN
		IF @SQLVersionMajor >= 11 BEGIN
			SET @SQL = '
			SELECT
				d.database_id
				, d.[name]
				, ag.group_id
				, ag.[name]
        		, CASE COALESCE(ag.[name],'''')
        			WHEN '''' THEN NULL
        			ELSE sys.fn_hadr_backup_is_preferred_replica (adc.database_name) 
        			END
			FROM sys.databases d
			LEFT JOIN sys.availability_databases_cluster adc
				ON d.[name] = adc.database_name
			LEFT JOIN sys.availability_groups  ag
				ON adc.group_id = ag.group_id
			WHERE d.database_id <> 2 
        		AND d.state NOT IN (1, 6, 10) 
        		AND d.is_in_standby = 0 
        		AND d.source_database_id IS NULL;'
			END

		/* For instances that exist prior to availability groups */
		IF @SQLVersionMajor < 11 BEGIN
			SET @SQL = '
			SELECT
				d.database_id
				, d.[name]
				, NULL
				, NULL
        		, NULL
			FROM sys.databases d
			WHERE d.database_id <> 2 
        		AND d.state NOT IN (1, 6, 10) 
        		AND d.is_in_standby = 0 
        		AND d.source_database_id IS NULL;'
			END

			INSERT #AvailabilityGroup
			EXEC sp_executesql @SQL
		END;


/* 
Recoverability 
*/

		IF OBJECT_ID('tempdb..#LastBackup') IS NOT NULL
			DROP TABLE #LastBackup;

		CREATE TABLE #LastBackup (
			DatabaseName NVARCHAR(128)
			, InstanceName NVARCHAR(128)
			, BackupType CHAR(1)
			, LastBackupDate DATETIME
			);

		INSERT #LastBackup
		SELECT
			[database_name]
			, server_name
			, [type]
			, max(backup_start_date)
		FROM msdb.dbo.backupset
		WHERE backup_finish_date is not null
			AND database_name = COALESCE(@DatabaseName, database_name)
		GROUP BY [database_name], server_name, [type];

		CREATE CLUSTERED INDEX PK_LastBackup
		ON #LastBackup (DatabaseName, InstanceName, BackupType);

		/* Missing Full backups */
		INSERT #Results
		SELECT
			2
			, 203
			, 1
			, 'Missing full backup'
			, 'Database missing full backups'
			, d.[name]
			, 'The database ' + d.[name] + ' has not had any full backups.'
			, 'If the data in this database is important, you need to make a full backup to recover the data.'
			, 'https://straightpathsql.com/check/missing-backups'
		FROM master.sys.databases d
		INNER JOIN #AvailabilityGroup ag
			ON d.database_id = ag.DatabaseID
		LEFT JOIN #LastBackup lb 
			ON d.name COLLATE SQL_Latin1_General_CP1_CI_AS = lb.DatabaseName COLLATE SQL_Latin1_General_CP1_CI_AS
			AND lb.BackupType = 'D'
			AND lb.InstanceName = SERVERPROPERTY('ServerName') /*Backupset ran on current server  */
		WHERE d.database_id <> 2  /* exclude tempdb */
			AND d.[name] = COALESCE(@DatabaseName, d.[name])
			AND d.state NOT IN (1, 6, 10) /* not currently offline or restoring, like log shipping databases */
			AND d.is_in_standby = 0 /* Not a log shipping target database */
			AND d.source_database_id IS NULL /* Excludes database snapshots */
			AND lb.LastBackupDate IS NULL
			AND COALESCE(ag.IsPreferredBackupReplica, 1) = 1;

		/* Missing log backups */
		INSERT #Results
		SELECT
			2
			, 204
			, 1
			, 'Missing log backup'
			, 'Database missing log backups'
			, d.[name]
			, 'The database ' + d.[name] + ' is in Full or Bulk Logged recovery model but has not had any transaction log backups.'
			, 'If point in time recovery is important to you, you need to take regular log backups.'
			, 'https://straightpathsql.com/check/missing-backups'
		FROM master.sys.databases d
		INNER JOIN #AvailabilityGroup ag
			ON d.database_id = ag.DatabaseID
		LEFT JOIN #LastBackup lb 
			ON d.name COLLATE SQL_Latin1_General_CP1_CI_AS = lb.DatabaseName COLLATE SQL_Latin1_General_CP1_CI_AS
			AND lb.BackupType = 'L'
			AND lb.InstanceName = SERVERPROPERTY('ServerName') /*Backupset ran on current server  */
		WHERE d.database_id <> 2  /* exclude tempdb */
			AND d.[name] = COALESCE(@DatabaseName, d.[name])
			AND d.state NOT IN (1, 6, 10) /* not currently offline or restoring, like log shipping databases */
			AND d.is_in_standby = 0 /* Not a log shipping target database */
			AND d.source_database_id IS NULL /* Excludes database snapshots */
			AND lb.LastBackupDate IS NULL
			AND d.recovery_model_desc <> 'SIMPLE'
			AND COALESCE(ag.IsPreferredBackupReplica, 1) = 1;

		/* No recent Full backups */
		INSERT #Results
		SELECT
			2
			, 205
			, 1
			, 'No recent full backup'
			, 'No full backup in the last 7 days'
			, d.[name]
			, 'The database ' + d.[name] + ' has not had any full backups in over a week.'
			, 'If the data in this database is important, you need to make regular full backups to recover the data.'
			, 'https://straightpathsql.com/check/recovery-point-objective'
		FROM master.sys.databases d
		INNER JOIN #LastBackup lb
			ON d.name COLLATE SQL_Latin1_General_CP1_CI_AS = lb.DatabaseName COLLATE SQL_Latin1_General_CP1_CI_AS
			AND lb.BackupType = 'D'
			AND lb.InstanceName = SERVERPROPERTY('ServerName') /*Backupset ran on current server  */
		INNER JOIN #AvailabilityGroup ag
			ON d.database_id = ag.DatabaseID
		WHERE d.database_id <> 2  /* exclude tempdb */
			AND d.[name] = COALESCE(@DatabaseName, d.[name])
			AND d.state NOT IN (1, 6, 10) /* not currently offline or restoring, like log shipping databases */
			AND d.is_in_standby = 0 /* Not a log shipping target database */
			AND COALESCE(ag.IsPreferredBackupReplica, 1) = 1
			AND lb.LastBackupDate <= DATEADD(dd, -7, GETDATE());

		/* No recent log backups */
		INSERT #Results
		SELECT
			2
			, 206
			, 1
			, 'No recent log backup'
			, 'No log backup in the last day'
			, d.[name]
			, 'The database ' + d.[name] + ' is in Full or Bulk Logged recovery model but has not had any transaction log backups in the last day.'
			, 'If point in time recovery is important to you, you need to take regular log backups.'
			, 'https://straightpathsql.com/check/recovery-point-objective'
		FROM master.sys.databases d
		INNER JOIN #AvailabilityGroup ag
			ON d.database_id = ag.DatabaseID
		INNER JOIN #LastBackup lb
			ON d.name COLLATE SQL_Latin1_General_CP1_CI_AS = lb.DatabaseName COLLATE SQL_Latin1_General_CP1_CI_AS
			AND lb.BackupType = 'L'
			AND lb.InstanceName = SERVERPROPERTY('ServerName') /*Backupset ran on current server  */
		WHERE d.database_id <> 2  /* exclude tempdb */
			AND lb.DatabaseName = COALESCE(@DatabaseName, lb.DatabaseName)
			AND d.state NOT IN (1, 6, 10) /* not currently offline or restoring, like log shipping databases */
			AND d.is_in_standby = 0 /* Not a log shipping target database */
			AND d.source_database_id IS NULL /* Excludes database snapshots */
			AND d.recovery_model_desc <> 'SIMPLE'
			AND COALESCE(ag.IsPreferredBackupReplica, 1) = 1
			AND lb.LastBackupDate <= DATEADD(hh, -24, GETDATE());

		
	/* check for failed backups */
	IF OBJECT_ID('tempdb..#FailedBackups') IS NOT NULL
		DROP TABLE #FailedBackups;

	CREATE TABLE #FailedBackups (
		LogDate DATETIME
		, Processinfo VARCHAR(255)
        , LogText VARCHAR(1000)
		);

    SET @SQL = 'EXEC master.sys.sp_readerrorlog 0, 1, N''BACKUP failed to complete the command BACKUP'''

	INSERT #FailedBackups
	EXEC sp_executesql @SQL

	;WITH FailedBackupRaw AS (
		SELECT
			fb.LogDate
			, fb.LogText
			, CASE
				WHEN fb.LogText LIKE '%BACKUP DATABASE %'
					THEN CHARINDEX('BACKUP DATABASE ', fb.LogText) + 16   /* length of 'BACKUP DATABASE ' */
				WHEN fb.LogText LIKE '%BACKUP LOG %'
					THEN CHARINDEX('BACKUP LOG ', fb.LogText) + 11        /* length of 'BACKUP LOG ' */
				END AS NameStart
		FROM #FailedBackups fb
		WHERE (fb.LogText LIKE '%BACKUP DATABASE %' OR fb.LogText LIKE '%BACKUP LOG %')
	),
	FailedBackupParsed AS (
		SELECT
			LogDate
			, LogText
			, NameStart
			, NULLIF(CHARINDEX('.', LogText, NameStart), 0) AS NameEnd   /* first period after the name begins */
		FROM FailedBackupRaw
		WHERE NameStart IS NOT NULL
	),
	FailedBackup AS (
		SELECT DISTINCT
			LogDate
			, LEFT(LogText, NameEnd) AS Issue
			, REPLACE(REPLACE(LTRIM(RTRIM(SUBSTRING(LogText, NameStart, NameEnd - NameStart))), '[', ''), ']', '') AS DatabaseName
		FROM FailedBackupParsed
		WHERE NameEnd IS NOT NULL
			AND NameEnd > NameStart   /* guarantees a positive SUBSTRING length */
	)

	INSERT #Results
	SELECT
		2
		, 207
		, 1
		, 'Failed database backups'
		, 'Failed backup occurred on ' + CONVERT(VARCHAR(10), fb.LogDate, 101)
		, fb.DatabaseName
		, fb.Issue
		, 'Review the SQL Server Log to find out more about any failed backups.'
		, 'https://straightpathsql.com/check/failed-backup'
	FROM FailedBackup fb
	WHERE fb.DatabaseName = COALESCE(@DatabaseName, fb.DatabaseName);

		/* Backup Compression not enabled */
		INSERT #Results
		SELECT 
			2
			, 208
			, 2
			, 'Backup compression'
			, 'Configuration ' + [name] + ' not enabled'
			, NULL
			, 'Backup compression allows for smaller and faster backup files.'
			, 'Unless there is blob, image, or XML data in your database, we recommend enabling ' + [name] + ' to get the benefits of compression.'
			, 'https://straightpathsql.com/check/backup-compression'
		FROM master.sys.configurations
		WHERE [name] IN (
			'backup compression'
			, 'backup compression default'
			)
			AND value_in_use = 0;

		/* Backup Checksum not enabled */
		INSERT #Results
		SELECT 
			2
			, 209
			, 2
			, 'Backup checksum'
			, 'Configuration ' + [name] + ' not enabled'
			, NULL
			, 'Backup checksum helps validate the consistency of backup files.'
			, 'We recommend enabling ' + [name] + ' to complete checksum verification by default and reduce the likelihood of any corrupted backup files.'
			, 'https://straightpathsql.com/check/backup-checksum'
		FROM master.sys.configurations
		WHERE [name] IN (
			'backup checksum'
			, 'backup checksum default'
			)
			AND value_in_use = 0;


		/* check for TDE certificate backup */
		INSERT #Results
		SELECT
			2
			, 211
			, 1
			, 'TDE certificate not backed up recently'
			, 'The transparent data encryption (TDE) certificate required for restoring has never been backed up.'
			, db_name(d.database_id)
			, 'The certificate ' + c.name + ' used to encrypt database ' + db_name(d.database_id) + ' has never been backed up'
			, 'Make a backup of your current certificate and store it in a secure location in case you need to restore this encrypted database.'
			, 'https://straightpathsql.com/check/no-recent-tde-certificate-backup'
		FROM master.sys.certificates c 
		INNER JOIN master.sys.dm_database_encryption_keys d 
			ON c.thumbprint = d.encryptor_thumbprint
		WHERE c.pvt_key_last_backup_date IS NULL;

		INSERT #Results
		SELECT
			2
			, 211
			, 1
			, 'TDE certificate not backed up recently'
			, 'The transparent data encryption (TDE) certificate required for restoring has not been backed up in the last 90 days.'
			, db_name(d.database_id)
			, 'The certificate ' + c.name + ' used to encrypt database ' + db_name(d.database_id) + ' has not been backed up since: ' + CAST(c.pvt_key_last_backup_date AS VARCHAR(100))
			, 'Make sure you have a recent backup of your certificate in a secure location in case you need to restore your encrypted database.'
			, 'https://straightpathsql.com/check/no-recent-tde-certificate-backup'
		FROM master.sys.certificates c 
		INNER JOIN master.sys.dm_database_encryption_keys d 
			ON c.thumbprint = d.encryptor_thumbprint
		WHERE c.pvt_key_last_backup_date <= DATEADD(dd, -90, GETDATE());


		/* check TDE certificate expiration dates */
		INSERT #Results
		SELECT
			2
			, 213
			, 2
			, 'TDE certificate set to expire'
			, 'The transparent data encryption (TDE) certificate required for restoring is set to expire.'
			, db_name(d.database_id)
			, 'The certificate ' + c.name + ' used to encrypt database ' + db_name(d.database_id) + ' is set to expire on: ' + CAST(c.expiry_date AS VARCHAR(100))
			, 'Although you will still be able to backup or restore your encrypted database with an expired certificate, these should be changed regularly like passwords.'
			, 'https://straightpathsql.com/check/tde-certificate-expiration-date'
		FROM master.sys.certificates c 
		INNER JOIN master.sys.dm_database_encryption_keys d 
			ON c.thumbprint = d.encryptor_thumbprint;


		/* check for database backup certificate backup */
		IF @SQLVersionMajor >= 12 BEGIN

			SET @SQL = '
			SELECT DISTINCT
				2
				, 210
				, 1
				, ''Database backup certificate never been backed up.''
				, ''A certificate used for backups has never been backed up.''
				, b.[database_name]
				, ''The certificate '' + c.name + '' used to encrypt database backups for '' + b.[database_name] + '' has never been backed up.''
				, ''Make sure you have a recent backup of your certificate in a secure location in case you need to restore encrypted database backups.''
				, ''https://straightpathsql.com/check/missing-database-backup-certificate-backup''
			FROM master.sys.certificates c 
			INNER JOIN msdb.dbo.backupset b
				ON c.thumbprint = b.encryptor_thumbprint
			WHERE c.pvt_key_last_backup_date IS NULL;';

			INSERT #Results
			EXEC sp_executesql @SQL


			SET @SQL = '
			SELECT DISTINCT
				2
				, 210
				, 1
				, ''Database backup certificate not backed up recently.''
				, ''A certificate used for backups has not been backed up in the last 90 days.''
				, b.[database_name]
				, ''The certificate '' + c.name + '' used to encrypt database backups for '' + b.[database_name] + '' has not been backed up since: '' + CAST(c.pvt_key_last_backup_date AS VARCHAR(100))
				, ''Make sure you have a recent backup of your certificate in a secure location in case you need to restore encrypted database backups.''
				, ''https://straightpathsql.com/check/missing-database-backup-certificate-backup''
			FROM master.sys.certificates c 
			INNER JOIN msdb.dbo.backupset b
				ON c.thumbprint = b.encryptor_thumbprint
			WHERE c.pvt_key_last_backup_date <= DATEADD(dd, -90, GETDATE());';

			INSERT #Results
			EXEC sp_executesql @SQL


		/* check for database backup certificate expiration dates */
			SET @SQL = '
			SELECT DISTINCT
				2
				, 212
				, 1
				, ''Database backup certificate set to expire.''
				, ''A certificate used for backups is set to expire.''
				, b.[database_name]
				, ''The certificate '' + c.name + '' used to encrypt database '' + b.[database_name] + '' is set to expire on: '' + CAST(c.expiry_date AS VARCHAR(100))
				, ''You will not be able to backup or restore your encrypted database backups with an expired certificate, so these should be changed regularly like passwords.''
				, ''https://straightpathsql.com/check/database-backup-certificate-expiration-date''
			FROM master.sys.certificates c 
			INNER JOIN msdb.dbo.backupset b
				ON c.thumbprint = b.encryptor_thumbprint;';

			INSERT #Results
			EXEC sp_executesql @SQL

			END

		/* backup history not purged */
		INSERT #Results
		SELECT TOP 1
			2
			, 216
			, 2
			, 'Backup history not purged'
			, 'The backup history in msdb is retained back to ['
				+ CAST(backup_start_date AS VARCHAR(20)) + '].'
			, 'msdb'
			, 'Not purging the backup history can cause the msdb database to grow significantly over time, and can make it difficult to find recent backup and restore history.'
			, 'Schedule a process like a SQL Agent job to purge your backup history periodically using [sp_delete_backuphistory].'
			, 'https://straightpathsql.com/check/backup-history-not-purged'
		FROM msdb.dbo.backupset
		WHERE backup_start_date <= DATEADD(dd, -90, GETDATE())
		ORDER BY backup_start_date ASC;

		/* check for high VLF count */
		IF @SQLVersionMajor >= 13 BEGIN
			INSERT #Results
			SELECT
				2
				, 217
				, 2
				, 'High VLF count'
				, 'The database ' + d.[name] + ' has ' + CONVERT(VARCHAR(10), ls.total_vlf_count) + ' virtual log files.'
				, d.[name]
				, 'A high number of VLFs can cause performance issues, especially for backup/restore operations and failovers.'
				, 'Consider resizing the log file to reduce the number of VLFs, and then grow it back out to an appropriate size with less VLFs.'
				, 'https://straightpathsql.com/check/virtual-log-files'
			FROM sys.databases d
			CROSS APPLY sys.dm_db_log_stats(d.database_id) ls
			WHERE ls.total_vlf_count > 200;
		
			END;

/*
Security
*/
		/* check for invalid Windows logins */
		IF OBJECT_ID('tempdb..#InvalidLogins') IS NOT NULL
			DROP TABLE #InvalidLogins;
	
		CREATE TABLE #InvalidLogins (
			LoginSID VARBINARY(85)
			, LoginName VARCHAR(256)
			);

		/* sp_validatelogins requires membership in sysadmin; skip when the caller is not a member */
		IF @IsSysadmin = 1 BEGIN
			INSERT INTO #InvalidLogins
			EXEC sp_validatelogins;
		END;
                        
		INSERT #Results
		SELECT
			3
			, 304 
			, 3
			, 'Invalid login with Windows Authentication'
			, 'There is a login with database permissions that appears to be dropped/disabled in Windows.'
			, NULL
			, QUOTENAME(LoginName) + ' is an invalid Windows user or group that is mapped to a SQL Server principal.'
			, 'Verify the account no longer exists and carefully remove all SQL Server permissions.'
			, 'https://straightpathsql.com/check/invalid-windows-login'
		FROM #InvalidLogins
		;

		/* database owner is unknown */
		INSERT #Results
		SELECT
			2
			, 305
			, 3
			, 'Database Owner is Unknown'  
			, 'The owner of the database ' + [name] + ' is unknown.'
			, [name]
			, ( 'Database name: ' + [name] + '   '
				+ 'Owner name: ' + ISNULL(SUSER_SNAME(owner_sid),'~~ UNKNOWN ~~') )
			, 'Assign an owner to this database, preferably sa if possible.'
			, 'https://straightpathsql.com/check/database-owner-blank'
		FROM master.sys.databases
		WHERE SUSER_SNAME(owner_sid) is NULL

		/* database owner is different from owner in master */
		/*
		Iterate databases with an explicit cursor and switch context using
		QUOTENAME so a database name containing ] or a quote cannot break the
		batch. sp_MSforeachdb is undocumented and substitutes the name for ?
		with no quoting.
		*/
		DECLARE @OwnerCheckDatabaseName sysname;

		DECLARE OwnerCheckDatabases CURSOR LOCAL FAST_FORWARD FOR
			SELECT [name]
			FROM master.sys.databases
			WHERE [name] <> 'tempdb'
				AND [state] = 0 /* database is online */
				AND source_database_id IS NULL /* exclude snapshot databases */
				AND HAS_DBACCESS([name]) = 1 /* skip databases the current login cannot access */
				AND DATABASEPROPERTYEX([name], 'Updateability') = 'READ_WRITE'; /* skip read-only databases and non-readable AG secondaries (USE would raise error 976) */

		OPEN OwnerCheckDatabases;

		FETCH NEXT FROM OwnerCheckDatabases INTO @OwnerCheckDatabaseName;

		WHILE @@FETCH_STATUS = 0 BEGIN
			SET @SQL = N'USE ' + QUOTENAME(@OwnerCheckDatabaseName) + N';
			SELECT 3, 306, 3
			, ''Database owner discrepancy''
			, ''Database has an issue with the owner''
			, db_name()
			, ''The database owner ['' + dbprs.name COLLATE SQL_Latin1_General_CP1_CI_AS + ''] is different than the owner listed in master ['' + ssp.name COLLATE SQL_Latin1_General_CP1_CI_AS + ''].''
			, ''Use sp_changedbowner to set the database owner to the correct login.''
			, ''https://straightpathsql.com/check/database-owner-discrepancy''
			FROM sys.database_principals AS dbprs
			INNER JOIN sys.databases AS dbs
			 ON dbprs.sid != dbs.owner_sid
			JOIN sys.server_principals ssp
			 ON dbs.owner_sid = ssp.sid
			WHERE dbs.database_id = Db_id()
			AND dbprs.principal_id = 1;';

			INSERT #Results
			EXECUTE sp_executesql @SQL;

			FETCH NEXT FROM OwnerCheckDatabases INTO @OwnerCheckDatabaseName;
			END;

		CLOSE OwnerCheckDatabases;
		DEALLOCATE OwnerCheckDatabases;

		/* sa is enabled */
		INSERT #Results
		SELECT 
			3
			, 307
			, 1
			, 'Enabled sa account'
			, 'The sa login is enabled'
			, NULL
			, 'The sa account is enabled for connections. Hackers commonly use the [sa] account for malicious activity since it in the [sysadmin] role.'
			, 'Disable the sa account. Disabling only prevents sa from being used as a login for connections, as it can still own databases, jobs, etc.'
			, 'https://straightpathsql.com/check/sa-login-enabled'
		FROM sys.sql_logins
		WHERE sid = 0x01
		AND is_disabled = 0;

	/* Remote admin connections not enabled */
	INSERT #Results
	SELECT 
		3
		, 310
		, 2
		, 'Configuration: Remote admin connection'
		, 'Configuration ' + [name] + ' not enabled'
		, NULL
		, 'The remote admin connection allows one member of the sysadmin role to use a reserved CPU thread for connectivity.'
		, 'We recommend enabling ' + [name] + ' to allow sysadmin members to troubleshoot during periods of excessively high CPU activity.'
		, 'https://straightpathsql.com/check/remote-dedicated-admin-connections'
	FROM master.sys.configurations
	WHERE [name] IN ('remote admin connections')
		AND value_in_use = 0;

/*
Availability
*/
		INSERT #Results
		SELECT
			4
			, 401
			, 1
			, 'Database in single user mode'
			, 'The database ' + [name] + ' is currently in single user mode'
			, [name]
			, 'This database can only be used by one connection.'
			, 'Use ALTER DATABASE to set this database to MULTI_USER.'
			, 'https://straightpathsql.com/check/single-user-mode'
		FROM master.sys.databases
		WHERE user_access_desc = 'SINGLE_USER';

		INSERT #Results
		SELECT
			4
			, 402
			, 1
			, 'Database in restricted user mode'
			, 'The database ' + [name] + ' is currently in restricted user mode'
			, [name]
			, 'This database can only be used by members of the db_owner, dbcreator, or sysadmin role.'
			, 'Use ALTER DATABASE to set this database to MULTI_USER.'
			, 'https://straightpathsql.com/check/restricted-user-mode'
		FROM master.sys.databases
		WHERE user_access_desc = 'RESTRICTED_USER';

		INSERT #Results
		SELECT
			4
			, 403
			, 2
			, 'Database in read-only mode'
			, 'The database ' + [name] + ' is currently in read-only mode'
			, [name]
			, 'This database cannot accept any transactions.'
			, 'Use ALTER DATABASE to set this database to READ_WRITE.'
			, 'https://straightpathsql.com/check/read-only-mode'
		FROM master.sys.databases
		WHERE is_read_only = 1
			AND source_database_id IS NULL; /* exclude snapshot databases */

		INSERT #Results
		SELECT
			4
			, 404
			, 2
			, 'Database offline'
			, 'The database ' + [name] + ' is currently offline'
			, [name]
			, 'This database cannot accept any connections or queries.'
			, 'Use ALTER DATABASE to set this database ONLINE.'
			, 'https://straightpathsql.com/check/database-offline'
		FROM master.sys.databases
		WHERE [state] = 6;

		INSERT #Results
		SELECT
			4
			, 405
			, 1
			, 'Database suspect'
			, 'The database ' + [name] + ' is in a suspect state'
			, [name]
			, 'Uh oh. This could be due to hardware failure, inaccessible files, or corruption.'
			, 'It might be time to restore some backups.'
			, 'https://straightpathsql.com/check/suspect-status'
		FROM master.sys.databases
		WHERE [state] = 4;

		INSERT #Results
		SELECT
			4
			, 406
			, 1
			, 'Endpoint owner'
			, 'The endpoint [' + EndpointName + '] is owned by the login [' + EndpointOwner + '].'
			, NULL
			, 'If this login becomes inaccessible or unable to be verified, the endpoint could cease to work.'
			, 'We recommend setting endpoint ownership to ''sa'' to avoid connection issues.'
			, 'https://straightpathsql.com/check/endpoint-ownership'
		FROM #Endpoints
		WHERE EndpointOwnerSID <> 0x01;


		IF @SQLVersionMajor >= 11.0 BEGIN
			SET @SQL = 'SELECT ag.[name], p.[name]
						FROM sys.availability_groups ag 
						INNER JOIN sys.availability_replicas r ON ag.group_id = r.group_id
						INNER JOIN sys.server_principals p ON r.owner_sid = p.[sid]
						WHERE p.SID <> 0x01;';

			IF OBJECT_ID('tempdb..#AGOwner') IS NOT NULL
				DROP TABLE #AGOwner;

			CREATE TABLE #AGOwner (AGName sysname, OwnerName sysname)

			INSERT #AGOwner
			EXEC sp_executesql @SQL

			INSERT #Results
			SELECT
				4
				, 407
				, 1
				, 'Availability Group owner'
				, 'The availability group ' + AGName + ' is owned by the login ' + OwnerName
				, NULL
				, 'If this login becomes inaccessible or unable to be verified, the availability group could cease to work.'
				, 'We recommend setting availability group ownership to ''sa'' to avoid connection issues.'
				, 'https://straightpathsql.com/check/availability-group-ownership'
			FROM #AGOwner;
			END

/*
Integrity
*/
	/* Databases with page verification not set to CHECKSUM */
		INSERT #Results
		SELECT
			5
			, 501
			, 1
			, 'Page verification not set to CHECKSUM'
			, 'The database ' + d.[name] + ' is using page verification [' + d.page_verify_option_desc + '].'
			, d.[name]
			, 'Page verification of [' + d.page_verify_option_desc + '] is not optimal for data integrity.'
			, 'We recommend setting page verification to [CHECKSUM] for all databases.'
			, 'https://straightpathsql.com/check/database-page-verification'		
		FROM master.sys.databases d
		INNER JOIN #Database x
			ON d.[name] = x.DatabaseName
		WHERE d.page_verify_option_desc <> 'CHECKSUM';

	/* Missing alerts for severity 19-25 and messages 823-825 */
		IF SERVERPROPERTY('EngineEdition') IN (2,3,8) -- Developer, Standard, Enterprise, or Managed Instance
			AND @IsSysadmin = 1 BEGIN /* reading SQL Agent alert metadata (msdb.dbo.sysalerts) requires sysadmin */
			IF NOT EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE severity = 19)
				INSERT #Results
				SELECT 
					5
					, 502
					, 1
					, 'Alert missing'
					, 'Missing an alert for error 19'
					, NULL
					, 'Alerts for severity error 19 notify of Fatal Errors in resource.'
					, 'We strongly recommend enabling Alerts for these errors.'
					, 'https://straightpathsql.com/check/alerts'

			IF NOT EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE severity = 20)
				INSERT #Results
				SELECT 
					5
					, 502
					, 1
					, 'Alert missing'
					, 'Missing an alert for error 20'
					, NULL
					, 'Alerts for severity error 20 notify of Fatal Errors in the current process.'
					, 'We strongly recommend enabling Alerts for these errors.'
					, 'https://straightpathsql.com/check/alerts'

			IF NOT EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE severity = 21)
				INSERT #Results
				SELECT 
					5
					, 502
					, 1
					, 'Alert missing'
					, 'Missing an alert for error 21'
					, NULL
					, 'Alerts for severity error 21 notify of Fatal Errors in a database process.'
					, 'We strongly recommend enabling Alerts for these errors.'
					, 'https://straightpathsql.com/check/alerts'

			IF NOT EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE severity = 22)
				INSERT #Results
				SELECT 
					5
					, 502
					, 1
					, 'Alert missing'
					, 'Missing an alert for error 22'
					, NULL
					, 'Alerts for severity error 22 notify of Fatal Errors in table integrity.'
					, 'We strongly recommend enabling Alerts for these errors.'
					, 'https://straightpathsql.com/check/alerts'

			IF NOT EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE severity = 23)
				INSERT #Results
				SELECT 
					5
					, 502
					, 1
					, 'Alert missing'
					, 'Missing an alert for error 23'
					, NULL
					, 'Alerts for severity error 23 notify of Fatal Errors in database integrity.'
					, 'We strongly recommend enabling Alerts for these errors.'
					, ''

			IF NOT EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE severity = 24)
				INSERT #Results
				SELECT 
					5
					, 502
					, 1
					, 'Alert missing'
					, 'Missing an alert for error 24'
					, NULL
					, 'Alerts for severity error 24 notify of Fatal Errors in hardware.'
					, 'We strongly recommend enabling Alerts for these errors.'
					, 'https://straightpathsql.com/check/alerts'

			IF NOT EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE severity = 25)
				INSERT #Results
				SELECT 
					5
					, 502
					, 1
					, 'Alert missing'
					, 'Missing an alert for error 25'
					, NULL
					, 'Alerts for severity error 25 notify of Fatal Errors in general.'
					, 'We strongly recommend enabling Alerts for these errors.'
					, 'https://straightpathsql.com/check/alerts'

			IF NOT EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE message_id = 823)
				INSERT #Results
				SELECT 
					5
					, 502
					, 1
					, 'Alert missing'
					, 'Missing an alert for message 823'
					, NULL
					, 'Alerts for message 823 notify of Windows I/O errors.'
					, 'We strongly recommend enabling Alerts for these errors.'
					, 'https://straightpathsql.com/check/alerts'

			IF NOT EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE message_id = 824)
				INSERT #Results
				SELECT 
					5
					, 502
					, 1
					, 'Alert missing'
					, 'Missing an alert for message 824'
					, NULL
					, 'Alerts for message 824 notify of logical consistency errors.'
					, 'We strongly recommend enabling Alerts for these errors.'
					, 'https://straightpathsql.com/check/alerts'

			IF NOT EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE message_id = 825)
				INSERT #Results
				SELECT 
					5
					, 502
					, 1
					, 'Alert missing'
					, 'Missing an alert for message 825'
					, NULL
					, 'Alerts for message 825 notify of read operation retries, indicating a problem with disk hardware.'
					, 'We strongly recommend enabling Alerts for these errors.'
					, 'https://straightpathsql.com/check/alerts'
			END

		IF OBJECT_ID('tempdb..#DBINFO') IS NOT NULL
			DROP TABLE #DBINFO;

		CREATE TABLE #DBINFO (
			  ID INT IDENTITY(1, 1) PRIMARY KEY 
			  , ParentObject VARCHAR(255)
			  , [Object] VARCHAR(255)
			  , Field VARCHAR(255) 
			  , [Value] VARCHAR(255) 
			  , DatabaseName NVARCHAR(128) NULL
			);

		/*
		Iterate databases with an explicit cursor and switch context using
		QUOTENAME. The database name is passed to the UPDATE as a bound
		parameter (@DbInfoName) rather than substituted into the text, so a
		name containing ] or a quote cannot break the batch or inject.
		*/
		DECLARE @DbInfoDatabaseName sysname;

		DECLARE DbInfoDatabases CURSOR LOCAL FAST_FORWARD FOR
			SELECT [name]
			FROM master.sys.databases
			WHERE [state] = 0 /* database is online */
				AND source_database_id IS NULL /* exclude snapshot databases */
				AND HAS_DBACCESS([name]) = 1 /* skip databases the current login cannot access */
				AND DATABASEPROPERTYEX([name], 'Updateability') = 'READ_WRITE'; /* skip read-only databases and non-readable AG secondaries (USE would raise error 976) */

		OPEN DbInfoDatabases;

		FETCH NEXT FROM DbInfoDatabases INTO @DbInfoDatabaseName;

		WHILE @@FETCH_STATUS = 0 BEGIN
			SET @SQL = N'USE ' + QUOTENAME(@DbInfoDatabaseName) + N';
			SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
			INSERT #DBINFO (ParentObject, Object, Field, Value)
			EXECUTE (''DBCC DBINFO() With TableResults, NO_INFOMSGS'');
			UPDATE #DBINFO SET DatabaseName = @DbInfoName WHERE DatabaseName IS NULL OPTION (RECOMPILE);';

			EXECUTE sp_executesql @SQL, N'@DbInfoName sysname', @DbInfoName = @DbInfoDatabaseName;

			FETCH NEXT FROM DbInfoDatabases INTO @DbInfoDatabaseName;
			END;

		CLOSE DbInfoDatabases;
		DEALLOCATE DbInfoDatabases;

		WITH CHECKDB AS (
			SELECT DISTINCT
				Field ,
				Value ,
				DatabaseName
			FROM #DBINFO x
			INNER JOIN master.sys.databases d ON x.DatabaseName = d.name
			WHERE Field = 'dbi_dbccLastKnownGood'
			)

		INSERT #Results
		SELECT
			5
			, 503
			, 1
			, 'Missing integrity checks'
			, 'Database missing recent integrity checks'
			, DatabaseName
			, 'The database ' + DatabaseName + ' has not had any integrity checks in the last 2 weeks.'
			, 'Regularly run DBCC CHECKDB to check for integrity issues that could indicate corruption.'
			, 'https://straightpathsql.com/check/missing-integrity-checks'		
		FROM CHECKDB
		WHERE DatabaseName <> 'tempdb'
			AND DatabaseName NOT IN ( SELECT [name] FROM master.sys.databases WHERE is_read_only = 1)
			AND CONVERT(DATETIME, CHECKDB.[Value], 121) < DATEADD(DD, -14, CURRENT_TIMESTAMP)
			AND DatabaseName = COALESCE(@DatabaseName, DatabaseName);

	/* Pages with corruption */
		INSERT #Results
		SELECT
			5
			, 504
			, 1
			, 'Suspect pages detected'
			, 'Database pages found to be corrupt'
			, d.[name]
			, 'The database ' + d.[name] + ' has been found to have at least one corrupt page in the last 30 days.'
			, 'Query the table msdb.dbo.suspect_pages for more information.'
			, 'https://straightpathsql.com/check/database-corruption'		
		  FROM msdb.dbo.suspect_pages sp
		  INNER JOIN master.sys.databases d
			ON sp.database_id = d.database_id
		  WHERE sp.last_update_date >= DATEADD(dd, -30, GETDATE())  OPTION (RECOMPILE);

	/* disabled alerts (reading msdb.dbo.sysalerts requires sysadmin) */
	IF @IsSysadmin = 1
		INSERT #Results
		SELECT
			5
			, 505
			, 2
			, 'Disabled alerts'
			, 'The alert [' + [name] + '] is currently disabled.'
			, NULL
			, 'Review to see if you intended to have this alert disabled.'
			, 'We recommend that you enable the alert if desired, or delete the alert.'
			, 'https://straightpathsql.com/check/alerts'		
		FROM msdb.dbo.sysalerts
		WHERE [enabled] = 0;

/*
Reliability
*/
	
	/* check for recent update */
	IF SERVERPROPERTY('EngineEdition') <> 8 /* Azure Managed Instances */ BEGIN
		IF ((@SQLVersionMajor = 11 AND @SQLVersionMinor < 7507) OR
			(@SQLVersionMajor = 12 AND @SQLVersionMinor < 6449) OR
			(@SQLVersionMajor = 13 AND @SQLVersionMinor < 6500) OR
			(@SQLVersionMajor = 14 AND @SQLVersionMinor < 3540) OR
			(@SQLVersionMajor = 15 AND @SQLVersionMinor < 4480) OR
			(@SQLVersionMajor = 16 AND @SQLVersionMinor < 4262) OR
			(@SQLVersionMajor = 17 AND @SQLVersionMinor < 4060) )

		INSERT #Results
		SELECT 
			6
			, 601
			, 1
			, '*Security update available'
			, 'There are security updates from Microsoft that have not been applied to this instance.'
			, NULL
			, 'There is at least one security update available for SQL Server ' +  VersionName + ' that has not been applied.'
			, 'Apply the most recent cumulative update or GDR for SQL Server ' +  VersionName + '.' 
			, 'https://straightpathsql.com/check/security-update'
		FROM #SQLVersions
		WHERE VersionNumber = @SQLVersionMajor
		END

	/* check for unsupported versions */
	IF SERVERPROPERTY('EngineEdition') <> 8 /* Azure Managed Instances */ BEGIN
		IF @SQLVersionMajor < 13
		INSERT #Results
		SELECT 
			6
			, 602
			, 1
			, '*Unsupported version of SQL Server'
			, 'This version of SQL Server is out of the support life cycle'
			, NULL
			, 'SQL Server ' +  VersionName + ' is no longer supported, so there will be no future security updates.'
			, 'Upgrade to SQL Server 2016 or higher.'
			, 'https://straightpathsql.com/check/unsupported-versions'
		FROM #SQLVersions
		WHERE VersionNumber = @SQLVersionMajor
		END

	/* Instance online over 180 days */
    IF (
        SELECT create_date 
        FROM master.sys.databases 
        WHERE database_id = 2
        ) < (
        SELECT DATEADD(dd, -180, CURRENT_TIMESTAMP)
        )

    INSERT #Results
    SELECT
        6
        , 603
        , 3
		, 'Instance online over 180 days'
        , 'Over 180 days since last SQL Server restart.'
	    , NULL
	    , 'Your SQL Server instance hasn''t been restarted since ' + CONVERT(VARCHAR(20), create_date, 101) + '. You are probably missing some important updates.'
	    , 'Schedule a time to update your SQL Server instance, and maybe the operating system as well.'
	    , 'https://straightpathsql.com/check/instance-uptime'
    FROM master.sys.databases
    WHERE database_id = 2;

	/* tempdb file on the C drive */
    INSERT #Results
    SELECT
        6
        , 604
        , 1
		, 'tempdb files on the C drive'
        , 'The file [' + [name] + '] is on the C drive.'
		, 'tempdb'
		, 'One poorly written query can cause all space on the C drive to be used, which could cause the operating system to freeze.'
		, 'When possible, create tempdb files on drives other than the C drive.'
		, 'https://straightpathsql.com/check/tempdb-files-on-c-drive'
    FROM tempdb.sys.database_files
    WHERE [Physical_Name] LIKE 'C:\%'
	    --AND (SELECT COUNT(DISTINCT SUBSTRING ([Physical_Name], 1, 1)) FROM tempdb.sys.database_files) > 1
		AND @NumberOfDrivesOtherThanC > 0;

	/* tempdb file with no growth allowed */
    INSERT #Results
    SELECT
        6
        , 605
        , 2
		, 'tempdb file with no growth allowed'
        , 'The file [' + [name] + '] is not allowed to grow beyond its current size.'
		, 'tempdb'
		, 'If you need more space than the current file size, your transactions may freeze or fail.'
		, 'Review the current file size and usage to see if you want to allow for growth.'
		, 'https://straightpathsql.com/check/tempdb-no-growth-allowed'
    FROM tempdb.sys.database_files
	WHERE [growth] = 0;
	

	/* user database file on the C drive */
    INSERT #Results
    SELECT
        6
        , 606
        , 1
		, 'User database file on the C drive'
        , 'In [' + DB_NAME(database_id) + '] the file ' + [name] + ' is on the C drive.'
		, DB_NAME(database_id)
		, 'One poorly written query can cause all space on the C drive to be used, which could cause the operating system to freeze.'
		, 'When possible, create database files on drives other than the C drive.'
		, 'https://straightpathsql.com/check/database-files-best-practice'
    FROM master.sys.master_files
    WHERE [Physical_Name] LIKE 'C:\%'
		AND database_id > 4
		AND @NumberOfDrivesOtherThanC > 0;

	/* user database files with no growth allowed */
    INSERT #Results
    SELECT
        6
        , 607
        , 2
		, 'User database file with no growth allowed'
        , 'In [' + DB_NAME(database_id) + '] the file [' + [name] + '] is not allowed to grow beyond its current size.'
		, DB_NAME(database_id)
		, 'If you need more space than the current file size, your transactions may freeze or fail.'
		, 'Review the current file size and usage to see if you want to allow for growth.'
		, 'https://straightpathsql.com/check/database-files-best-practice'
    FROM master.sys.master_files
	WHERE [growth] = 0
		AND database_id > 4;

	/* user database log and data files are on the same drive */
	IF @NumberOfDrivesOtherThanC >= 2 BEGIN
		WITH FileDrives AS (
			SELECT
				d.[name] AS DatabaseName
				, mf.[type_desc] AS FileType
				, LEFT(mf.physical_name, 1) AS DriveLetter
			FROM sys.databases d
			JOIN sys.master_files mf 
				ON d.database_id = mf.database_id
			WHERE d.database_id > 4  /* Exclude system databases */
				AND d.state_desc = 'ONLINE' /* Only check online databases */
				AND LEFT(mf.physical_name, 1) <> 'C' /* If on C drive then will be flagged in another check */
			)
		, DataDrives AS (
			SELECT
				DatabaseName
				, DriveLetter AS DataDrive
			FROM FileDrives
			WHERE FileType = 'ROWS'
			)
		, LogDrives AS (
			SELECT 
				DatabaseName
				, DriveLetter AS LogDrive
			FROM FileDrives
			WHERE FileType = 'LOG'
			)
		INSERT #Results
		SELECT DISTINCT
			6
			, 608
			, 2
			, 'User database log and data files are on the same drive'
			, 'The database [' + d.DatabaseName + '] has both log and data files on the [' + d.DataDrive + '] drive.'
			, d.DatabaseName
			, 'Having log and data files on the same drive can negatively impact performance.'
			, 'We recommend splitting data and log files onto separate drives.'
			, 'https://straightpathsql.com/check/database-files-best-practice'		FROM DataDrives d
		JOIN LogDrives l 
			ON d.DatabaseName = l.DatabaseName
			AND d.DataDrive = l.LogDrive;
		END;

	/* the SQL Agent job checks read msdb.dbo.sysjobs / sysjobschedules / sysschedules, which requires sysadmin */
	IF @IsSysadmin = 1 BEGIN

	/* SQL Agent job is enabled but schedule is disabled */
        INSERT #Results
        SELECT
            6
            , 609
            , 2
			, 'SQL Agent job schedule is disabled'
            , 'The job [' + j.[name] + '] is enabled but has one or more schedules disabled'
			, NULL
			, 'Disabled job schedules do not get automatically run as scheduled.'
			, 'Verify the schedules for this job to confirm this is intentional.'
			, 'https://straightpathsql.com/check/sql-agent-job-schedule'
		FROM msdb.dbo.sysjobs j
		INNER JOIN msdb.dbo.sysjobschedules js 
			ON j.job_id = js.job_id
		INNER JOIN msdb.dbo.sysschedules s 
			ON js.schedule_id = s.schedule_id
		WHERE j.enabled = 1
			AND s.enabled = 0;

	/* SQL Agent job is enabled but has no schedule */
    INSERT #Results
    SELECT
        6
        , 610
        , 2
		, 'SQL Agent job is enabled without a schedule'
        , 'The job [' + j.[name] + '] is enabled but has no schedules'
		, NULL
		, 'Jobs without schedules do not get automatically run.'
		, 'Verify there should not be any schedules for this job to confirm this is intentional.'
		, 'https://straightpathsql.com/check/sql-agent-job-schedule'
	FROM msdb.dbo.sysjobs j
	LEFT JOIN msdb.dbo.sysjobschedules js 
		ON j.job_id = js.job_id
	LEFT JOIN msdb.dbo.sysschedules s 
		ON js.schedule_id = s.schedule_id
	WHERE j.enabled = 1
		AND s.enabled IS NULL;

	/* SQL Agent jobs owned by users */
	INSERT #Results
	SELECT
        6
        , 611
        , 2
		, 'SQL Agent jobs owned by users' 
		, 'Job [' + j.name + '] is owned by [' + SUSER_SNAME(j.owner_sid) + ']'
		, NULL
		, 'If this login is disabled or not available due to Active Directory problems, the job will stop working.' 
		, 'Verify this login is the correct owner for the job. If possible, see if the job can be owned by sa.'
		, 'https://straightpathsql.com/check/sql-agent-jobs-owned-by-users'
	FROM msdb.dbo.sysjobs j
	WHERE j.enabled = 1
	AND SUSER_SNAME(j.owner_sid) <> SUSER_SNAME(0x01)
	AND SUSER_SNAME(j.owner_sid) not like '##%';

	END; /* @IsSysadmin gate for the SQL Agent job checks */

	/* default data path */
	IF LEFT(@DefaultDataPath, 1) = 'C' AND @NumberOfDrivesOtherThanC > 0
		INSERT #Results
		SELECT
			6
			, 612
			, 2
			, 'Default data file path is on the C drive' 
			, 'The default data file path is: ' + LEFT(@DefaultDataPath, 950)
			, NULL
			, 'If data files grow unexpectedly they could cause the operating system to freeze and/or the server to crash.' 
			, 'It looks like you have other drives available, so consider creating data files on another drive.' 
			, 'https://straightpathsql.com/check/default-file-path'

	/* default log path */
	IF LEFT(@DefaultLogPath, 1) = 'C' AND @NumberOfDrivesOtherThanC > 0
		INSERT #Results
		SELECT
			6
			, 613
			, 2
			, 'Default log file path is on the C drive' 
			, 'The default log file path is: ' + LEFT(@DefaultLogPath, 950)
			, NULL
			, 'If log files grow unexpectedly they could cause the operating system to freeze and/or the server to crash.' 
			, 'It looks like you have other drives available, so consider creating data files on another drive.' 
			, 'https://straightpathsql.com/check/default-file-path'

	/* default backup path */
	IF LEFT(@DefaultBackupPath, 1) = 'C' AND @NumberOfDrivesOtherThanC > 0
		INSERT #Results
		SELECT
			6
			, 614
			, 2
			, 'Default backup file path is on the C drive' 
			, 'The default backup file path is: ' + LEFT(@DefaultBackupPath, 950)
			, NULL
			, 'If backup files grow unexpectedly they could cause the operating system to freeze and/or the server to crash.' 
			, 'It looks like you have other drives available, so consider creating data files on another drive.' 
			, 'https://straightpathsql.com/check/default-file-path'

	/* min and max memory configurations */
	SELECT @MinMemoryMB = CONVERT(NUMERIC (18,0), value_in_use)
	FROM master.sys.configurations
	WHERE name  = 'min server memory (MB)';

	SELECT @MaxMemoryMB = CONVERT(NUMERIC (18,0), value_in_use)
	FROM master.sys.configurations
	WHERE name  = 'max server memory (MB)';

	IF @MinMemoryMB = @MaxMemoryMB
		INSERT #Results
		SELECT
			6
			, 615
			, 2
			, 'Min and max memory settings'
			, 'The minimum and maximum memory settings for this instance are the same'
			, NULL
			, 'This is not recommended by Microsoft, as it can cause instability.'
			, 'We recommend setting min memory lower than max memory, preferably leaving it at the default of 0.'
			, 'https://straightpathsql.com/check/memory-best-practices';

	IF @MaxMemoryMB = 2147483647
		INSERT #Results
		SELECT
			6
			, 616
			, 2
			, 'Max memory setting'
			, 'The maximum memory setting for this instance is at the default of 2 PB'
			, NULL
			, 'At this setting, SQL Server could consume all available memory, causing issues for other processes.'
			, 'We recommend setting max memory to allow room for the operating system and other applications.'
			, 'https://straightpathsql.com/check/memory-best-practices';

	/* server name disrcrepancy */
	IF (SELECT CONVERT(NVARCHAR(128),@@SERVERNAME)) 
	<> (SELECT CONVERT(NVARCHAR(128),SERVERPROPERTY ('ServerName')))		INSERT #Results
		SELECT
			6
			, 617
			, 2
			, 'Server name discrepancy'
			, 'Server name properties do not match'
			, NULL
			, 'The value for @@SERVERNAME does not match the value for SERVERPROPERTY (''ServerName''), which can cause features to not work.'
			, 'Check to see if there has been an update to the network name of this computer.'
			, 'https://straightpathsql.com/check/server-name';

	/* low drive space */
	INSERT #Results
	SELECT
		6
		, 618
		, 1
		, 'Low drive space'
		, 'The [' + Drive + '] drive has less than 10 percent free space'
		, NULL
		, 'If you run out of available space then SQL Server and other process can stop working as expected.'
		, 'Check to see if you can make more space available on this drive.'
		, 'https://straightpathsql.com/check/low-drive-space'
	FROM #Drives
	WHERE UsedPercent > 90.0;

/* database files with max size set */
    INSERT #Results
    SELECT
        6
        , 620
        , 2
        , 'Database file with max size set'
        , 'The file [' + [name] + '] is not allowed to grow beyond ' + CONVERT(NVARCHAR(50), [max_size]/128) + ' MB.'
        , DB_NAME(database_id)
        , 'If this file grows to the max size, your transactions may freeze or fail.'
        , 'If this database is not read only, change the file growth settings to allow for unlimited growth.'
        , 'https://straightpathsql.com/check/database-max-file-size'
    FROM master.sys.master_files
    WHERE [growth] > 0
        AND [max_size] NOT IN (0, -1)
		AND [max_size] < 268435456 /* 2 TB default max size */
		AND [type_desc] IN ('ROWS', 'LOG') /* only data and log files */
		AND database_id <> 2 /* exclude tempdb */
		AND DB_NAME(database_id) <> N'DB_Administration'; /* exclude DB_Administration */

	/* Evaluation edition */
	INSERT #Results
	SELECT 6
		, 621
		, 1
		, 'Evaluation Edition'
		, 'This instance of SQL Server is running an Evaluation edition'
		, NULL
		, 'This instance will stop working on: [' + CAST(CONVERT(DATETIME, DATEADD(DD, 180, create_date), 102) AS VARCHAR(100)) + '].'
		, 'We HIGHLY recommend purchasing and applying a valid license key, or migrating to a licensed edition before the expiration date.'
		, 'https://straightpathsql.com/check/evaluation-edition'	
	FROM sys.server_principals
	WHERE sid = 0x010100000000000512000000
	AND CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) LIKE '%Evaluation%'; 

	/* Error log retention (the registry read requires sysadmin) */
	IF @IsSysadmin = 1 BEGIN
	EXEC master.dbo.xp_instance_regread
		N'HKEY_LOCAL_MACHINE', 
        N'Software\Microsoft\MSSQLServer\MSSQLServer',
        N'NumErrorLogs', 
        @NumberOfErrorLogs OUTPUT

	IF @NumberOfErrorLogs <= 6
		INSERT #Results
		SELECT 
			6
			, 622
			, 2
			, 'Number of error logs'
			, 'This instance is configured for ' + CAST(@NumberOfErrorLogs AS VARCHAR(100)) + ' error logs'
			, NULL
			, 'If you don''t have enough error logs, you might not have enough error history to effectively troubleshoot issues.'
			, 'We recommend setting this value to 52 and running sp_cycle_errorlog weekly to have enough manageable error log files.'
			, 'https://straightpathsql.com/check/number-of-sql-server-error-log-files'

	END; /* @IsSysadmin gate for the error log retention registry read */


	/* replication enabled */
    INSERT #Results
	SELECT
		6
		, 623
		, 2
		, 'Replication enabled: publisher'
		, 'The database [' + [name] + '] is a replication publisher.'
		, [name]
		, 'Replication can negatively impact backups, index maintenance, code deployments, and more.'
		, 'Review this publication to make sure it is necessary.'
		, 'https://straightpathsql.com/check/replication'
	FROM sys.databases
	WHERE is_published = 1
	UNION
	SELECT
		6
		, 623
		, 2
		, 'Replication enabled: subscriber'
		, 'The database [' + [name] + '] is a replication subscriber.'
		, [name]
		, 'Replication can negatively impact backups, index maintenance, code deployments, and more.'
		, 'Review this subscription to make sure it is necessary.'
		, 'https://straightpathsql.com/check/replication'
	FROM sys.databases
	WHERE is_subscribed = 1
	UNION
	SELECT
		6
		, 623
		, 2
		, 'Replication enabled: merge replication'
		, 'The database [' + [name] + '] is configured for merge replication.'
		, [name]
		, 'Replication can negatively impact backups, index maintenance, code deployments, and more.'
		, 'Merge replication can be, well, unpleasant, so make sure it is necessary.'
		, 'https://straightpathsql.com/check/replication'
	FROM sys.databases
	WHERE is_merge_published = 1
	UNION
	SELECT
		6
		, 623
		, 2
		, 'Replication enabled: distribution'
		, 'The database [' + [name] + '] is configured for replication distribution.'
		, [name]
		, 'Replication can negatively impact backups, index maintenance, code deployments, and more.'
		, 'Review any publications and subscriptions associated with this distribution database to make sure they are necessary.'
		, 'https://straightpathsql.com/check/replication'
	FROM sys.databases
	WHERE is_distributor = 1;

	/* low available physical memory, less than 1 GB */
    INSERT #Results
	SELECT
		6
		, 624
		, 1
		, 'Low available physical memory'
		, 'This server has ' 
			+ CAST(( CAST(total_physical_memory_kb AS BIGINT) / 1024) AS VARCHAR(20)) 
			+ ' MB of physical memory, but only ' 
			+ CAST(( CAST(available_physical_memory_kb AS BIGINT) / 1024) AS VARCHAR(20))
		  	+ ' MB are available.'
		, NULL
		, 'If the operating system has no memory available then it will start using the page file, resulting in poor system performance.'
		, 'Review max memory for SQL Server to see if it is set too high before you simply add more memory to the server.'
		, 'https://straightpathsql.com/check/memory-best-practices'
	FROM sys.dm_os_sys_memory
	WHERE CAST(available_physical_memory_kb AS BIGINT) < 1048576 /* less than 1 GB */ 
	OPTION (RECOMPILE);

	/* database snapshot */
    INSERT #Results
	SELECT
		6
		, 625
		, 2
		, 'Database Snapshot found'
		, 'The database [' + snapdb.[name]
			+ '] was created as a snapshot of ['
			+ sourcedb.[name]
			+ '] on [' + CAST(snapdb.create_date AS VARCHAR(20)) + '].'
		, snapdb.[name]
		, 'Database snapshot files grow as the source database changes.'
		, 'Monitor the amount of drive space used by the snapshot database, and drop it if it is unused.'
		, 'https://straightpathsql.com/check/database-snapshot'
	FROM sys.databases snapdb 
	INNER JOIN sys.databases sourcedb
		ON snapdb.source_database_id = sourcedb.database_id

	/* pending configuration changes */
    INSERT #Results
    SELECT
        6
        , 626
        , 2
        , 'Pending configuration change'
        , 'The configuration [' 
			+ [name] 
			+ '] has a pending change from [' 
			+ CAST(value_in_use AS VARCHAR(100))
			+ '] to ['
			+ CAST([value] AS VARCHAR(100))
			+ '] that has not been applied yet.' 
        , NULL
        , 'When someone executes ''RECONFIGURE'' or restarts the instance, this setting will take effect.'
        , 'Review if you want this configuration to take effect, and if so run ''RECONFIGURE''.'
        , 'https://straightpathsql.com/check/instance-configurations'
	FROM sys.configurations
	WHERE [value] <> value_in_use
    AND NOT ([name] = 'min server memory (MB)' AND [value] IN (0,16) AND value_in_use IN (0,16)); /* SQL Server is weird about min memory */

	/* unusual database state */
    INSERT #Results
	SELECT
		6
		, 627
		, 2
		, 'Unusual database state'
	    , 'The database [' + [name] COLLATE DATABASE_DEFAULT + '] has a current state of [' + state_desc COLLATE DATABASE_DEFAULT + '].'
		, [name]
		, 'Since this database is not ONLINE, it may be in need of repair.'
		, 'Review to see if this is intended, like a RESTORING database.'
		, 'https://straightpathsql.com/check/unusual-database-state'
	FROM sys.databases
	WHERE [state] NOT IN (0, 6) /* exclude ONLINE, OFFLINE) */

	/* stopped SQL Agent */
	INSERT #Results
	SELECT
		6
		, 628
		, 1
		, 'SQL Server Agent offline'
		, 'The [' + servicename + '] service is currently offline.' 
		, NULL
		, 'This service is often responsible for running scheduled jobs, including backups and maintenance tasks. If it is offline, these tasks will not run.'
		, 'Review the service status in Configuration Manager and start it if desired. The current startup type is [' + startup_type_desc + '].'
		, 'https://straightpathsql.com/check/sql-agent-offline'
	FROM master.sys.dm_server_services
	WHERE servicename LIKE 'SQL Server Agent%'
	AND status_desc <> 'Running'
	AND CAST(SERVERPROPERTY('Edition') AS VARCHAR(1000)) NOT LIKE '%xpress%'; /* exclude Express Edition, which doesn't have SQL Agent */

	/* memory dumps */
	IF EXISTS (SELECT 1 FROM sys.dm_server_memory_dumps WHERE [creation_time] >= DATEADD(day, -90, GETDATE()))
		INSERT #Results
		SELECT
			6
			, 629
			, 1
			, 'Recent memory dumps'
			, 'SQL Server has had ' + CAST(COUNT(*) AS VARCHAR(100)) + ' memory dumps in the last 90 days.'
			, NULL
			, 'Memory dumps can be a sign of server instability.'
			, 'The most recent memory dump occurred on [' + CAST(CAST(MAX([creation_time]) AS DATETIME) AS VARCHAR(100)) + ']. Check the SQL Server error log for more information.'
			, 'https://straightpathsql.com/check/memory-dumps'
		FROM sys.dm_server_memory_dumps
		WHERE [creation_time] >= DATEADD(day, -90, GETDATE());

	/* user database with logical file named 'master' */
	INSERT #Results
	SELECT
		6
		, 630
		, 1
		, 'User database with logical file named ''master'''
		, 'The database ' + '[' + [name] + ']' + ' has a file with the logical name of ''master''.'
		, NULL
		, 'Having a database other than [master] with a file named ''master'' is known to cause SQL Server updates to fail.'
		, 'Change the logical file name to something else before you attempt to apply SQL Server updates.'
		, 'https://desertdba.com/failovers-cant-serve-two-masters/'
	FROM master.sys.master_files 
	WHERE ([name] = N'master')
	AND database_id > 4
	AND db_name(database_id) <> 'master';

	/* priority boost enabled */
	INSERT #Results
	SELECT
		6
		, 631
		, 1
		, 'Priority Boost enabled'
		, 'This instance has Priority Boost enabled.'
		, NULL
		, 'Because Priority Boost drains resources from Windows and can lead to crashes, Microsoft recommends disabling it.'
		, 'Disable Priority Boost and restart your SQL Server service.'
		, 'https://straightpathsql.com/check/priority-boost'
	FROM master.sys.configurations 
	WHERE name = 'priority boost' AND (value = 1 OR value_in_use = 1);

	/* system databases below installed compatibility level */
	INSERT #Results
	SELECT
		6
		, 632
		, 1
		, 'System database below installed compatibility level'
		, 'The database [' + d.[name] + '] has compatibility level of [' + CONVERT(VARCHAR(5),[compatibility_level]) + '].'
		, d.[name]
		, 'You can get unexpected errors if the system databases have a compatibility level below the installation.'
		, 'Raise the compatibility level for this database. This change does not require a restart.'
		, 'https://straightpathsql.com/check/system-database-compatibility-level'
	FROM master.sys.databases AS d
	WHERE d.database_id <= 4   -- master, tempdb, model, msdb
	  AND d.[compatibility_level] < CAST(PARSENAME(CONVERT(NVARCHAR(128), SERVERPROPERTY('ProductVersion')), 4) AS INT) * 10;


/*
Performance
*/

	/* Cost threshold for parallelism at default */	
	INSERT #Results
	SELECT
		7
		, 701
		, 2
		, 'Cost threshold for parallelism'
		, 'The cost threshold for parallelism configuration is set to the default of 5'
		, NULL
		, 'This default is low and can cause excessive CPU usage.'
		, 'We recommend setting this to 50 as a starting point.'
		, 'https://straightpathsql.com/check/cost-threshold-for-parallelism'
	FROM sys.configurations
	WHERE [name] = 'cost threshold for parallelism'
		AND value_in_use = 5;

	/* Max degree of parallelism set to default */
	INSERT #Results
	SELECT
		7
		, 702
		, 2
		, 'Max degree of parallelism'
		, 'The max degree of parallelism is set to the default of 0'
		, NULL
		, 'This default can cause excessive CPU usage.'
		, 'We recommend setting this to a specific value, typically an even number around half of all CPU cores.'
		, 'https://straightpathsql.com/check/max-degree-of-parallelism'
	FROM sys.configurations
	WHERE [name] = 'max degree of parallelism'
		AND value_in_use = 0;

	/* Max degree of parallelism set to 1 */
	INSERT #Results
	SELECT
		7
		, 702
		, 2
		, 'Max degree of parallelism'
		, 'The max degree of parallelism is set to 1'
		, NULL
		, 'This removes the opportunity for parallelism and can lead to poor performance.'
		, 'We recommend setting this to a specific value, typically an even number around half of all CPU cores.'
		, 'https://straightpathsql.com/check/max-degree-of-parallelism'
	FROM master.sys.configurations
	WHERE [name] = 'max degree of parallelism'
		AND value_in_use = 1;

	/* Auto shrink enabled */
	INSERT #Results
	SELECT
		7
		, 703
		, 2
		, 'Auto shrink enabled'
		, 'The database ' + d.[name] COLLATE DATABASE_DEFAULT + ' has auto shrink enabled' 
		, d.[name]
		, 'This setting can cause unexpected performance problems with random shrink events.'
		, 'We recommend using ALTER DATABASE to set AUTO_SHRINK off.'
		, 'https://straightpathsql.com/check/auto-shrink'
	FROM master.sys.databases d
	INNER JOIN #Database x
		ON d.[name] = x.DatabaseName
	WHERE d.is_auto_shrink_on = 1;

	/* Auto close enabled */
	INSERT #Results
	SELECT
		7
		, 704
		, 2
		, 'Auto close enabled'
		, 'The database ' + d.[name] COLLATE DATABASE_DEFAULT + ' has auto close enabled' 
		, d.[name]
		, 'This setting can cause unexpected connection issues.'
		, 'We recommend using ALTER DATABASE to set AUTO_CLOSE off.'
		, 'https://straightpathsql.com/check/auto-close'
	FROM master.sys.databases d
	INNER JOIN #Database x
		ON d.[name] = x.DatabaseName
	WHERE d.is_auto_close_on = 1;

	/* Low compatibility level */
	INSERT #Results
	SELECT
		7
		, 705
		, 2
		, 'Lower compatibility level'
		, 'The database ' + d.[name] COLLATE DATABASE_DEFAULT + ' has compatibility level set at ' + CONVERT(VARCHAR(5), d.compatibility_level) + ' which is below the instance level of ' + CONVERT(VARCHAR(5), (CONVERT(INT, @SQLVersionMajor * 10))) + '.'
		, d.[name]
		, 'Databases with a lower compatibility level cannot take advantage of newer features and enhancements.'
		, 'We recommend using ALTER DATABASE to set COMPATIBILITY_LEVEL to ' + CONVERT(VARCHAR(5), (CONVERT(INT, @SQLVersionMajor * 10))) + '.'
		, 'https://straightpathsql.com/check/compatibility-level'
	FROM master.sys.databases d
	INNER JOIN #Database x
		ON d.[name] = x.DatabaseName
	WHERE d.compatibility_level < (@SQLVersionMajor * 10);

	/* Trace flag recommendations (not 1117 and 1118) */
    IF @SQLVersionMajor < 13 BEGIN
		IF NOT EXISTS (SELECT * FROM #TraceFlag WHERE TraceFlag = '2371')    
			INSERT #Results
            SELECT
                7
				, 706
                , 2
				, 'Trace Flag not enabled'
                , 'Trace flag 2371 not enabled globally.'
        		, NULL
        		, 'For this version of SQL Server, we recommend enabling trace flag 2371 to lower the auto update statistics threshold for large tables.'
        		, 'Enable this trace flag in the startup parameters of the SQL Server instance.'
        		, 'https://straightpathsql.com/check/trace-flags';
		END;

    IF @SQLVersionMajor IN (13, 14) BEGIN
		IF NOT EXISTS (SELECT * FROM #TraceFlag WHERE TraceFlag = '7752')    
			INSERT #Results
			SELECT
				7
				, 706
				, 2
				, 'Trace Flag not enabled'
				, 'Trace flag 7752 not enabled globally.'
        		, NULL
        		, 'For this version of SQL Server, we recommend enabling trace flag 7752 to enable asynchronous loading of Query Store data.'
        		, 'Enable this trace flag in the startup parameters of the SQL Server instance.'
        		, 'https://straightpathsql.com/check/trace-flags';
		END;

    IF @SQLVersionMajor >= 13 BEGIN
		IF NOT EXISTS (SELECT * FROM #TraceFlag WHERE TraceFlag = '7745')    
			INSERT #Results
			SELECT
				7
				, 706
				, 2
				, 'Trace Flag not enabled'
				, 'Trace flag 7745 not enabled globally.'
        		, NULL
        		, 'For this version of SQL Server, we recommend enabling trace flag 7745 to prevent Query Store data from being written to disk during failover or shutdown.'
        		, 'Enable this trace flag in the startup parameters of the SQL Server instance.'
        		, 'https://straightpathsql.com/check/trace-flags';
			END;

	IF NOT EXISTS (SELECT * FROM #TraceFlag WHERE TraceFlag = '3226')    
		INSERT #Results
		SELECT
			7
			, 706
			, 2
			, 'Trace Flag not enabled'
			, 'Trace flag 3226 not enabled globally.'
        	, NULL
        	, 'For this version of SQL Server, we recommend enabling trace flag 3226 to suppress successful backup messages from the error log.'
        	, 'Enable this trace flag in the startup parameters of the SQL Server instance.'
        	, 'https://straightpathsql.com/check/trace-flags';


	/* Number of tempdb data files not recommended */
	SELECT @NumberOfDataFiles = COUNT([file_id])
	FROM tempdb.sys.database_files
	WHERE [type] = 0;

    IF @NumberOfCPUCores < 8 
    
            INSERT #Results
            SELECT
                7
                , 707
                , 1
				, 'Number of tempdb data files not recommended'
                , 'There are ' + CONVERT(VARCHAR(3), @NumberOfDataFiles) + ' tempdb data files on a server with ' + CONVERT(VARCHAR(3), @NumberOfCPUCores) + ' CPU cores.'
    			, 'tempdb'
    			, 'Microsoft recommends having the same number of data files as CPU cores (up to 8) to reduce file contention.'
    			, 'Configure tempdb to have ' + CONVERT(VARCHAR(3), @NumberOfCPUCores) + ' evenly sized data files.'
    			, 'https://straightpathsql.com/check/tempdb-data-file-growth'
            WHERE @NumberOfDataFiles <> @NumberOfCPUCores;
    
    IF @NumberOfCPUCores >= 8 
    
            INSERT #Results
            SELECT
                7
				, 707
                , 1
				, 'Number of tempdb data files not recommended'
                , 'There are ' + CONVERT(VARCHAR(3), @NumberOfDataFiles) + ' tempdb data files on a server with ' + CONVERT(VARCHAR(3), @NumberOfCPUCores) + ' CPU cores.'
    			, 'tempdb'
    			, 'Microsoft recommends having the same number of data files as CPU cores (up to 8) to reduce file contention.'
    			, 'If this configuration was not intentional, configure tempdb to have 8 evenly sized data files.'
    			, 'https://straightpathsql.com/check/tempdb-data-file-growth'
            WHERE @NumberOfDataFiles <> 8;

	/* Unevenly sized tempdb data files */
	IF (
        SELECT COUNT(DISTINCT([size]))
        FROM tempdb.sys.database_files
        WHERE [type] = 0
        ) > 1

        INSERT #Results
        SELECT
            7
			, 708
            , 1
			, 'Unequally sized tempdb data files'
            , 'tempdb has unequally sized data files'
			, 'tempdb'
			, 'Unequally sized data files result in an uneven distribution of usage among the data files.'
			, 'Make sure all tempdb data files are sized equally and have the same growth settings.'
			, 'https://straightpathsql.com/check/tempdb-data-file-size';

	/* Uneven tempdb growth settings */
	IF EXISTS (
		SELECT 1
		FROM tempdb.sys.database_files
		WHERE [type_desc] = 'ROWS'
		GROUP BY data_space_id
		HAVING COUNT(DISTINCT growth) > 1
			OR COUNT(DISTINCT is_percent_growth) > 1
		)

        INSERT #Results
        SELECT
            7
			, 709
            , 1
			, 'Uneven tempdb growth rates'
            , 'tempdb data files have uneven growth rates'
			, 'tempdb'
			, 'Uneven growth rates result in uneven sized data files, which result in an uneven distribution of usage among the data files.'
			, 'Make sure all tempdb data files are sized equally and have the same growth settings.'
			, 'https://straightpathsql.com/check/tempdb-data-file-growth';

	/* Log file larger than data files (tempdb) */
     IF (
         SELECT SUM(CAST([size] AS BIGINT))
         FROM sys.master_files
         WHERE [database_id] = 2
         AND [type] = 1
         ) > (
         SELECT SUM(CAST([size] AS BIGINT))
         FROM sys.master_files
         WHERE [database_id] = 2
         AND [type] = 0
		 )

        INSERT #Results
        SELECT
            7
			, 710
            , 2
			, 'tempdb log file larger than data files'
            , 'tempdb has a log file larger than the data file'
			, 'tempdb'
			, 'This may indicate you have or had a very large transaction.'
			, 'Use a tool like sp_CheckActivity to make sure you don''t have any runaway transactions in tempdb.'
			, 'https://straightpathsql.com/check/tempdb-log-file-size';


	/* Files with percentage growth rates (tempdb) */
	IF EXISTS (
        SELECT *
        FROM tempdb.sys.database_files
        WHERE [is_percent_growth] = 1
        )

        INSERT #Results
        SELECT
            7
			, 711
            , 1
			, 'tempdb file with percentage growth rates'
            , 'The file ' + [name] + ' has a percentage growth rate'
			, 'tempdb'
			, 'Percentage growth rates will lead to a high number of growth events.'
			, 'This can lead to slow performance during growths, so we recommend using a fixed growth rate of 64 MB or greater.'
			, 'https://straightpathsql.com/check/tempdb-data-file-growth'
        FROM tempdb.sys.database_files
        WHERE [is_percent_growth] = 1;

	/* Files with growth rates less than 64 MB (tempdb) */
	IF EXISTS (
        SELECT *
        FROM tempdb.sys.database_files
        WHERE [is_percent_growth] = 0
        AND [growth] BETWEEN 1 AND 8191
        )

        INSERT #Results
        SELECT
            7
			, 712
            , 1
			, 'tempdb file with growth rates less than 64 MB'
            , 'The file ' + [name] + ' has a growth rate of only ' + CONVERT(NVARCHAR(50), [growth]/128) + ' MB'
			, 'tempdb'
			, 'Small growth rates can lead to a high number of growth events.'
			, 'Microsoft sets default growth rates of 64 MB, so we recommend that as a minimum.'
			, 'https://straightpathsql.com/check/tempdb-data-file-growth'
        FROM tempdb.sys.database_files
        WHERE [is_percent_growth] = 0
        AND [growth] BETWEEN 1 AND 8191;

	/* Multiple log files (tempdb) */
	IF (
        SELECT COUNT([file_id])
        FROM tempdb.sys.database_files
        WHERE [type] = 1
        ) > 1

        INSERT #Results
        SELECT
            7
			, 713
            , 1
			, 'Multiple log files'
            , 'tempdb has multiple log files'
			, 'tempdb'
			, 'You don''t need (or want) multiple log files in a SQL Server database.'
			, 'Empty and remove any extra log files.'
			, 'https://straightpathsql.com/check/tempdb-multiple-log-files';

	/* Files with high usage (tempdb) */
	IF EXISTS (
        SELECT *
        FROM tempdb.sys.database_files
        WHERE ((CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT) * 1.)/([size]* 1.) * 100) > @UsagePercent
        )

        INSERT #Results
        SELECT
            7
			, 714
            , 1
			, 'tempdb file with high usage'
            , 'The file ' + [name] + ' has more than ' + CONVERT(VARCHAR(3), @UsagePercent) + ' percent usage.'
			, 'tempdb'
			, 'Is this amount of tempdb activity expected?'
			, 'Use sp_CheckTempdb @Mode = 2 to see what kinds of data are in tempdb, and what sessions are using tempdb.'
			, 'https://straightpathsql.com/check/tempdb-files-with-high-usage'
        FROM tempdb.sys.database_files
        WHERE ((CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT) * 1.)/([size]* 1.) * 100) > @UsagePercent;

	/* Trace Flag 1117 and 1118 */
    IF @SQLVersionMajor < 13 BEGIN
    
        IF NOT EXISTS (SELECT * FROM #TraceFlag WHERE TraceFlag = '1117')    
                INSERT #Results
                SELECT
                    7
					, 715
                    , 2
					, 'Trace Flag 1117'
                    , 'Trace flag 1117 not enabled globally.'
        			, 'tempdb'
        			, 'For this version of SQL Server, we recommend enabling trace flag 1117 to grow all files in a filegroup at the same time.'
        			, 'Enable this trace flag in the startup parameters of the SQL Server instance.'
        			, 'https://straightpathsql.com/check/trace-flag-1117';
    
        IF NOT EXISTS (SELECT * FROM #TraceFlag WHERE TraceFlag = '1118')    
                INSERT #Results
                SELECT
                    7
					, 716
                    , 2
					, 'Trace Flag 1118'
                    , 'Trace flag 1118 not enabled globally.'
        			, 'tempdb'
        			, 'For this version of SQL Server, we recommend enabling trace flag 1118 to reduce SGAM (allocation page) waits.'
        			, 'Enable this trace flag in the startup parameters of the SQL Server instance.'
        			, 'https://straightpathsql.com/check/trace-flag-1118';
    
        END;

	/* Memory-optimized tempdb metadata */
    IF @SQLVersionMajor >= 15 BEGIN
    
        IF (SELECT value_in_use FROM sys.configurations WHERE [name] = 'tempdb metadata memory-optimized') = 1   
                INSERT #Results
                SELECT
                    7
					, 717
                    , 2
					, 'Memory-optimized tempdb metadata'
                    , 'Memory-optimized tempdb metadata is enabled.'
        			, 'tempdb'
        			, 'This feature moves some of the most commonly used system tables in tempdb to memory-optimized tables.'
        			, 'Please be sure you meant to enable this feature.'
        			, 'https://straightpathsql.com/check/tempdb-memory-optimized';
        END;

	/* Slow reads and writes to files (tempdb) */
    IF OBJECT_ID('tempdb..#AvgStall') IS NOT NULL
    	DROP TABLE #AvgStall; 

    CREATE TABLE #AvgStall (
        FileId INT
        , LogicalName sysname
        , FileType NVARCHAR(60)
        , AvgReadStallMs INT
        , AvgWriteStallMs INT
		);

    INSERT #AvgStall
    SELECT
        f.[file_id]
        , f.[name]
        , f.[type_desc]
        , CAST(s.io_stall_read_ms / ( 1.0 * s.num_of_reads ) AS INT)
        , CAST(s.io_stall_write_ms / ( 1.0 * s.num_of_writes ) AS INT)
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) s
    INNER JOIN sys.master_files f
        ON s.file_id = f.file_id
        AND s.database_id = f.database_id
    WHERE s.num_of_reads > 0
        AND s.num_of_writes > 0
        AND s.database_id = 2

    INSERT #Results
    SELECT
        7
		, 718
        , 1
		, 'Slow reads'
        , 'The file [' + LogicalName + '] has an average read stall time of ' + CONVERT(VARCHAR(10), AvgReadStallMs) + 'ms.'
        , 'tempdb'
        , 'This may be an indicator of issues with your I/O subsystem, or that you have queries requiring too many reads.'
        , 'Review your I/O performance and SQL Server''s wait statistics, as this may not actually be a problem.'
        , 'https://straightpathsql.com/check/tempdb-slow-reads-and-writes'
    FROM #AvgStall
    WHERE AvgReadStallMs > @AvgReadStallMs;

    INSERT #Results
    SELECT
        7
		, 719
        , 1
		, 'Slow writes'
        , 'The file [' + LogicalName + '] has an average write stall time of ' + CONVERT(VARCHAR(10), AvgWriteStallMs) + 'ms.'
        , 'tempdb'
        , 'This may be an indicator of issues with your I/O subsystem, or that you have queries requiring too many writes.'
        , 'Review your I/O performance and SQL Server''s wait statistics, as this may not actually be a problem.'
        , 'https://straightpathsql.com/check/tempdb-slow-reads-and-writes'
    FROM #AvgStall
    WHERE AvgWriteStallMs > @AvgWriteStallMs;

	/* Log file larger than data files (user databases) */
	INSERT #Results
	SELECT
		7
		, 720
		, 2
		, 'Database log file larger than data files'
		, 'The database [' + d.[name] + '] has a log file larger than the data file'
		, d.[name]
		, 'This may indicate you have or had a very large transaction.'
		, 'Use a tool like sp_WhoIsActive to make sure you don''t have any runaway transactions in this database.'
		, 'https://straightpathsql.com/check/database-log-file-size'
	FROM sys.databases d
	JOIN sys.master_files mf ON d.database_id = mf.database_id
	WHERE mf.[type] IN (0,1)
		AND d.database_id <> 2 /* exclude tempdb */
	GROUP BY d.[name]
	HAVING
		SUM(CASE WHEN mf.type = 1 THEN mf.size END) >
		SUM(CASE WHEN mf.type = 0 THEN mf.size END)
		AND SUM(CASE WHEN mf.type = 1 THEN mf.size END) > 12800; /* log > 100 MB */;

	/* Files with percentage growth rates (not tempdb) */
	INSERT #Results
	SELECT
		7
		, 721
		, 1
		, 'Database file with percentage growth rates'
		, 'The file [' + [name] + '] has a percentage growth rate.'
		, DB_NAME(database_id) 
		, 'Percentage growth rates will lead to a high number of growth events.'
		, 'This can lead to slow performance during growths, so we recommend using a fixed growth rate of 64 MB or greater.'
		, 'https://straightpathsql.com/check/database-file-growth'
	FROM sys.master_files 
	WHERE [is_percent_growth] = 1
		AND [type] IN (0,1)
		AND database_id <> 2; /* exclude tempdb */

	/* Files with growth rates less than 64 MB */
	INSERT #Results
	SELECT
		7
		, 722
		, 1
		, 'Database file with growth rates less than 64 MB'
		, 'The file [' + [name] + '] has a growth rate of only ' + CONVERT(NVARCHAR(50), [growth]/128) + ' MB.'
		, DB_NAME(database_id) 
		, 'Small growth rates can lead to a high number of growth events.'
		, 'Microsoft sets default growth rates of 64 MB, so we recommend that as a minimum.'
		, 'https://straightpathsql.com/check/database-file-growth'
	FROM sys.master_files
	WHERE [type] IN (0,1)
		AND [is_percent_growth] = 0
		AND [growth] BETWEEN 1 AND 8191
		AND database_id NOT IN (1, 4); /* exclude master, msdb */


	/* Multiple log files (not tempdb) */
	INSERT #Results
	SELECT
		7
		, 723
		, 1
		, 'Multiple log files'
		, 'Database has multiple log files'
		, DB_NAME(database_id)
		, 'You don''t need (or want) multiple log files in a SQL Server database.'
		, 'Empty and remove any extra log files.'
		, 'https://straightpathsql.com/check/database-multiple-log-files'
	FROM sys.master_files
	WHERE [type_desc] = 'LOG'
	GROUP BY database_id
	HAVING COUNT([file_id]) > 1;

	/* Power plan (the registry reads require sysadmin) */
	IF @IsSysadmin = 1 BEGIN
		/* Get power plan if set by group policy */						
		EXEC xp_regread
			@rootkey = N'HKEY_LOCAL_MACHINE',
			@key = N'SOFTWARE\Policies\Microsoft\Power\PowerSettings',
			@value_name = N'ActivePowerScheme',
			@value = @PowerPlan OUTPUT,
			@no_output = N'no_output';

		/* If power plan not set by group policy, get local value */
		IF @PowerPlan IS NULL 
			EXEC xp_regread 
				@rootkey = N'HKEY_LOCAL_MACHINE',
				@key = N'SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes',
				@value_name = N'ActivePowerScheme',
				@value = @PowerPlan OUTPUT;

		IF @PowerPlan <> '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
			INSERT #Results
			SELECT
				7
				, 724
				, 1
				, 'Power plan not optimal'
				, 'The Windows power plan is currently set to: ' + CASE @PowerPlan
					WHEN 'a1841308-3541-4fab-bc81-f71556f20b4a' THEN 'power saving'
					WHEN '381b4222-f694-41f0-9685-ff5bb260df2e' THEN 'balanced power'
					ELSE 'an unknown power mode'
					END
				, NULL
				, 'In this mode Windows may throttle down CPU performance, leading to performance issues.'
				, 'We recommend setting power mode for the server (and the host level if this is a virtual machine) to High Performance.'
				, 'https://straightpathsql.com/check/power-plan'

	END; /* @IsSysadmin gate for the power plan registry reads */

	/* Instant file initialization */

	/* IFI: try sys.dm_server_services */
	IF EXISTS
		(
		SELECT 1
		FROM sys.all_columns
		WHERE [object_id] = OBJECT_ID(N'[sys].[dm_server_services]')
		AND [name] = N'instant_file_initialization_enabled'
		)
	BEGIN
		BEGIN TRY
			SET @SQL = 
				N'SELECT @IFIEnabled = instant_file_initialization_enabled
				  FROM sys.dm_server_services
				  WHERE filename LIKE ''%sqlservr.exe%''
				  OPTION (RECOMPILE);';

			EXEC dbo.sp_executesql
				@SQL
			   , N'@IFIEnabled CHAR(1) OUTPUT'
			   , @IFIEnabled = @IFIEnabled OUTPUT;

			SET @IFIDetermined = 1;
		END TRY
		BEGIN CATCH
			SET @IFIDetermined = 0;
		END CATCH
	END

	/* IFI: try the error log */
	IF @IFIDetermined = 0
	BEGIN

		/* check for Amazon RDS */
		IF LEFT(CAST(SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS varchar(8000)), 8) = 'EC2AMAZ-'
		AND LEFT(CAST(SERVERPROPERTY('MachineName') AS varchar(8000)), 8) = 'EC2AMAZ-'
		AND DB_ID('rdsadmin') IS NOT NULL
		AND EXISTS ( 
			SELECT 1
			FROM master.sys.all_objects
			WHERE name IN ('rds_startup_tasks', 'rds_help_revlogin', 'rds_hexadecimal', 'rds_failover_tracking', 'rds_database_tracking', 'rds_track_change')
			)
		BEGIN
			INSERT INTO @IFIErrorLog
			EXEC rdsadmin.dbo.rds_read_error_log 0, 1, N'Database Instant File Initialization: enabled';
		END
		ELSE
		BEGIN
			BEGIN TRY
				INSERT INTO @IFIErrorLog
				EXEC sys.xp_readerrorlog 0, 1, N'Database Instant File Initialization: enabled';
			END TRY
			BEGIN CATCH
				/* Failure due to insufficient permissions to read the error log */
				SET @IFIEnabled = NULL;
			END CATCH
		END

		IF @IFIEnabled IS NOT NULL
		BEGIN
			IF EXISTS (
				SELECT 1 
				FROM @IFIErrorLog
				WHERE [LogText] LIKE N'Database Instant File Initialization: enabled%' 
				)
				SET @IFIEnabled = 'Y';
			ELSE
				SET @IFIEnabled = 'N';
		END

	END

	IF @IFIEnabled = 'N'
		INSERT #Results
		SELECT
			7
			, 725
			, 1
			, 'Instant file initialization'
			, 'Instant file initialization is not enabled' 
			, NULL
			, 'Without enabling instant file initialization (IFI), all pages must be zeroes out during file growth.'
			, 'We recommend enabling IFI to speed performance of file growth events.'
			, 'https://straightpathsql.com/check/instant-file-initialization';

	/* Locked pages in memory */
		INSERT #Results
		SELECT
			7
			, 726
			, 2
			, 'Lock pages in memory'
			, 'This instance has ' + CASE 
				WHEN locked_page_allocations_kb/1024./1024. > 0 THEN CAST(locked_page_allocations_kb/1024/ 1024 AS VARCHAR(100)) + ' GB'
				ELSE CAST(locked_page_allocations_kb/1024 AS VARCHAR(100)) + ' MB'
				END + ' of pages locked in memory.'
			, NULL
			, 'This is not a default setting, which can both increase performance or (if misconfigured) hinder performance.'
			, 'If you do not know why this setting was enabled, check with your colleagues to make sure it was intentional.'
			, 'https://straightpathsql.com/check/lock-pages-in-memory'
		FROM master.sys.dm_os_process_memory
		WHERE locked_page_allocations_kb > 0;

	/* Locked pages in memory with max server memory at the default */
	IF @MaxMemoryMB = 2147483647
		INSERT #Results
		SELECT
			7
			, 742
			, 2
			, 'Locked Pages In Memory with max memory at default'
			, 'This instance has pages locked in memory while the maximum server memory setting is at the default of 2 PB.'
			, NULL
			, 'With Lock Pages in Memory enabled and no maximum memory limit set, SQL Server can lock all available physical memory and starve the operating system, which can cause the server to become unresponsive.'
			, 'We recommend setting a maximum server memory value that leaves enough memory for the operating system and other processes.'
			, 'https://straightpathsql.com/check/lock-pages-in-memory'
		FROM master.sys.dm_os_process_memory
		WHERE locked_page_allocations_kb > 0;

	/* Auto create stats disabled */
	INSERT #Results
	SELECT
		7
		, 728
		, 2
		, 'Auto create statistics is disabled'
		, 'The database ' + d.[name] + ' has the auto creation of statistics disabled' 
		, d.[name]
		, 'This setting will suppress the automatic creation of statistics for your data.'
		, 'If this isn''t a SharePoint database, chances are this setting should be enabled.'
		, 'https://straightpathsql.com/check/auto-create-statistics'
	FROM master.sys.databases d
	INNER JOIN #Database x
		ON d.[name] = x.DatabaseName
	WHERE d.is_auto_create_stats_on = 0;

	/* offline CPU schedulers */
	INSERT #Results
	SELECT
		7
		, 729
		, 1
		, 'Offline CPU schedulers'
		, 'SQL Server is not using ' + CAST(ofl.offline_schedulers AS VARCHAR(100)) + ' CPUs' 
		, NULL
		, 'Due to licensing restrictions and/or CPU configuration, SQL Server is not using all available CPU cores.'
		, 'Stop your server and reconfigure your CPU core assignment to 1 or 2 sockets.'
		, 'https://straightpathsql.com/check/offline-cpu-schedulers'
	FROM sys.dm_os_nodes n
	INNER JOIN sys.dm_os_memory_nodes m 
		ON n.memory_node_id = m.memory_node_id
	OUTER APPLY (
		SELECT
		COUNT(*) AS [offline_schedulers]
		FROM sys.dm_os_schedulers dos
		WHERE n.node_id = dos.parent_node_id
			AND dos.status = 'VISIBLE OFFLINE'
	) ofl
	WHERE n.node_state_desc NOT LIKE '%DAC%'
		AND ofl.offline_schedulers > 0;

/* Resource Governor enabled */
	INSERT #Results
	SELECT
		7
		, 731
		, 2
		, 'Resource Governor enabled'
		, 'The Resource Governor feature is enabled.'
		, NULL
		, 'Resource Governor throttles resources for queries, which often degrades performance.'
		, 'Review why you have Resource Governor configured, and test the related classifier function.'
		, 'https://straightpathsql.com/check/resource-governor'
	FROM sys.resource_governor_configuration 
	WHERE is_enabled = 1 
	OPTION (RECOMPILE);

/* enabled server-level triggers */
	INSERT #Results
	SELECT
		7
		, 732
		, 2
		, 'Enabled server-level triggers'
		, 'Server Trigger [' + [name] + '] is enabled.'
		, NULL
		, 'Server-level triggers can cause unexpected performance problems, especially if they contain cursors, cross-server queries, or excessive logging.'
		, 'Review any server-level triggers to make sure they are necessary.'
		, 'https://straightpathsql.com/check/server-level-triggers'
		FROM sys.server_triggers
		WHERE is_disabled = 0 
			AND is_ms_shipped = 0 
			AND [name] NOT LIKE 'rds^_%' /* exclude Amazon RDS triggers */
		OPTION (RECOMPILE);

/* change tracking enabled */
	INSERT #Results
	SELECT
		7
		, 733
		, 2
		, 'Change Tracking enabled'
		, 'The database [' + d.[name] COLLATE DATABASE_DEFAULT + '] has tables with Change Tracking enabled.'
		, d.[name]
		, 'Tracking changes in tables have some performance impact.'
		, 'Review the tables with Change Tracking to make sure this feature is required for them.'
		, 'https://straightpathsql.com/check/change-tracking'
	FROM sys.change_tracking_databases AS ctd 
	INNER JOIN sys.databases AS d 
	ON ctd.database_id = d.database_id 
	OPTION (RECOMPILE);

/* is_recursive_triggers_on enabled */
IF EXISTS (
	SELECT 1
	FROM sys.all_columns
	 WHERE [name] = 'is_recursive_triggers_on' 
	 AND object_id = OBJECT_ID('sys.databases')
	)
	INSERT #Results
	SELECT
		7
		, 734
		, 2
		, 'Recursive triggers enabled'
		, 'The database ' + d.[name] COLLATE DATABASE_DEFAULT + ' has recursive triggers enabled.' 
		, d.[name]
		, 'With this setting enabled, if a trigger modifies its own table, it can cause itself to fire again, and then again, and then...you get the idea.'
		, 'Review to see if you can stop the insanity and disable this setting.'
		, 'https://straightpathsql.com/check/recursive-triggers'
	FROM master.sys.databases d
	INNER JOIN #Database x
		ON d.[name] = x.DatabaseName
	WHERE d.is_recursive_triggers_on = 1

/* is_parameterization_forced enabled */
IF EXISTS (
	SELECT 1
	FROM sys.all_columns
	 WHERE [name] = 'is_parameterization_forced' 
	 AND object_id = OBJECT_ID('sys.databases')
	)
	INSERT #Results
	SELECT
		7
		, 735
		, 2
		, 'Forced parameterization enabled'
		, 'The database ' + d.[name] COLLATE DATABASE_DEFAULT + ' has forced parameterization enabled.' 
		, d.[name]
		, 'With this setting enabled, most literal values are treated as parameterized values so the same execution plan can be reused for different values.'
		, 'Review to see if this was intended, as forced parameterization can sometimes lead to suboptimal plans.'
		, 'https://straightpathsql.com/check/forced-parameterization'
	FROM master.sys.databases d
	INNER JOIN #Database x
		ON d.[name] = x.DatabaseName
	WHERE d.is_parameterization_forced = 1

/* is_cdc_enabled enabled */
IF EXISTS (
	SELECT 1
	FROM sys.all_columns
	 WHERE [name] = 'is_cdc_enabled' 
	 AND object_id = OBJECT_ID('sys.databases')
	)
	INSERT #Results
	SELECT
		7
		, 736
		, 2
		, 'Change Data Capture enabled'
		, 'The database ' + d.[name] COLLATE DATABASE_DEFAULT + ' has Change Data Capture (CDC) enabled.' 
		, d.[name]
		, 'Enabling CDC can have some performance impact, as it involves a lot of extra writes.'
		, 'Review the tables with CDC enabled to make sure this feature is required for them.'
		, 'https://straightpathsql.com/check/change-data-capture'
	FROM master.sys.databases d
	INNER JOIN #Database x
		ON d.[name] = x.DatabaseName
	WHERE d.is_cdc_enabled = 1

/* delayed_durability enabled */
IF EXISTS (
	SELECT 1
	FROM sys.all_columns
	 WHERE [name] = 'delayed_durability' 
	 AND object_id = OBJECT_ID('sys.databases')
	)
	INSERT #Results
	SELECT
		7
		, 737
		, 2
		, 'Delayed durability enabled'
		, 'The database ' + d.[name] COLLATE DATABASE_DEFAULT + ' has delayed durability enabled.' 
		, d.[name]
		, 'Since delayed durability commits changes before flushing them to disk, transactions can be lost in the event of a shutdown or crash.'
		, 'Review with your colleagues if data loss is acceptable for this database.'
		, 'https://straightpathsql.com/check/delayed-durability'
	FROM master.sys.databases d
	INNER JOIN #Database x
		ON d.[name] = x.DatabaseName
	WHERE d.delayed_durability <> 0;

	/* custom Extended Events running */
	INSERT #Results
	SELECT
		7
		, 738
		, 2
		, 'Custom Extended Events running'
		, 'The Extended Event ' + '[' + [name] + ']' + ' is running.'
		, NULL
		, 'Extended Events can be very helpful, but be mindful of the resources they are using.'
		, 'If this Extended Event is not required, investigate and stop the session.'
		, 'https://straightpathsql.com/check/extended-events'
	FROM sys.dm_xe_sessions
	WHERE [name] NOT IN
		('AlwaysOn_health', 'system_health', 'telemetry_xevents', 'sp_server_diagnostics', 'sp_server_diagnostics session', 'hkenginexesession')
		AND name NOT LIKE '%$A%';
		
	/* Check for I/O freezes */
	IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL
		DROP TABLE #ErrorLog;

	CREATE TABLE #ErrorLog (
		LogDate datetime2
		, ProcessInfo VARCHAR(50)
		, ErrorLogText VARCHAR(1000)
		);

	/* reading the error log requires sysadmin; skip the I/O freeze check when the caller is not a member */
	IF @IsSysadmin = 1 BEGIN
		INSERT INTO #ErrorLog
		EXEC sys.xp_readerrorlog 0, 1;
	END;

	WITH Events AS (
		SELECT
			LogDate,
			ErrorLogText,
			/* normalize message and extract database name */
			CASE
				WHEN ErrorLogText LIKE 'I/O is frozen on database %' THEN
					LTRIM(RTRIM(SUBSTRING(ErrorLogText, CHARINDEX('I/O is frozen on database', ErrorLogText) + 26,
						CHARINDEX('.', ErrorLogText, CHARINDEX('I/O is frozen on database', ErrorLogText)) 
						- (CHARINDEX('I/O is frozen on database', ErrorLogText) + 26))))
				WHEN ErrorLogText LIKE 'I/O was resumed on database %' THEN
					LTRIM(RTRIM(SUBSTRING(ErrorLogText, CHARINDEX('I/O was resumed on database', ErrorLogText) + 28,
						CHARINDEX('.', ErrorLogText, CHARINDEX('I/O was resumed on database', ErrorLogText)) 
						- (CHARINDEX('I/O was resumed on database', ErrorLogText) + 28))))
				ELSE NULL
			END AS DatabaseName,
			CASE
				WHEN ErrorLogText LIKE 'I/O is frozen on database %' THEN 'Frozen'
				WHEN ErrorLogText LIKE 'I/O was resumed on database %' THEN 'Resumed'
				ELSE NULL
			END AS EventType
		FROM #ErrorLog
		WHERE ErrorLogText LIKE 'I/O is frozen on database %' OR ErrorLogText LIKE 'I/O was resumed on database %'
	),

	Paired AS (
		/* for each Frozen event find the next Resumed event for the same database */
		SELECT
			f.DatabaseName,
			f.LogDate AS FrozenAt,
			r.LogDate AS ResumedAt,
			DATEDIFF(MILLISECOND, f.LogDate, r.LogDate) AS DurationMs
		FROM Events f
		OUTER APPLY (
			SELECT TOP (1) r.LogDate
			FROM Events r
			WHERE r.EventType = 'Resumed'
			  AND r.DatabaseName = f.DatabaseName
			  AND r.LogDate > f.LogDate
			ORDER BY r.LogDate ASC
		) r
		WHERE f.EventType = 'Frozen'
		  AND r.LogDate IS NOT NULL
	)

	INSERT #Results
	SELECT
		7
		, 739
		, 2
		, 'I/O freeze detected'
		, 'There have been at least ' + CAST(COUNT(1) AS VARCHAR(4)) + ' I/O freeze(s) against the [' + DatabaseName + '] database with an average duration of '+ CAST(AVG(CAST(DurationMs AS FLOAT)) AS VARCHAR(10)) + ' milliseconds.'
		, DatabaseName
		, 'I/O freezes can negatively impact your database performance. These are usually caused by VM backups or other backups that use Volume Shadowcopy Services (VSS).'
		, 'Ensure you understand how VSS backups are used in your environment.'
		, 'https://straightpathsql.com/check/i-o-freeze'
	FROM Paired
	GROUP BY DatabaseName;

	/* Auto update stats disabled */
	INSERT #Results
	SELECT
		7
		, 740
		, 2
		, 'Auto update statistics is disabled'
		, 'The database ' + d.[name] + ' has the auto update of statistics disabled' 
		, d.[name]
		, 'This setting will suppress the automatic update of statistics for your data.'
		, 'If this isn''t a SharePoint database, chances are this setting should be enabled.'
		, 'https://straightpathsql.com/check/auto-update-statistics'
	FROM master.sys.databases d
	INNER JOIN #Database x
		ON d.[name] = x.DatabaseName
	WHERE d.is_auto_update_stats_on = 0;

/* Database-level checks */
/*
	WHILE EXISTS (SELECT DatabaseName FROM #Database WHERE Checked = 0) BEGIN

		SET @DatabaseName = (SELECT TOP 1 DatabaseName FROM #Database WHERE Checked = 0 ORDER BY DatabaseName);
		
		SELECT @DatabaseID = DatabaseID
		FROM #Database
		WHERE @DatabaseName = DatabaseName;

		UPDATE #Database
		SET Checked = 1
		WHERE DatabaseName = @DatabaseName
		END;
*/
	END;


/*
Results returned
*/
IF @Mode IN (0, 1, 99) BEGIN /* display results */
	SELECT
		c.CategoryName
		, r.[Importance]
		, r.CheckName
		, r.Issue
		, r.DatabaseName
		, r.Details
		, r.ActionStep    
		, r.ReadMoreURL
		, r.CheckID
	FROM #Results r
	INNER JOIN #Category c
		ON r.CategoryID = c.CategoryID
	ORDER BY
		r.[Importance]
		, c.CategoryID
		, r.CheckID
		, r.Issue
		, r.DatabaseName;

		END;

IF @Mode IN (11) /* single row instance info */ BEGIN

	SELECT * FROM (
		SELECT
			r.CheckName
			, r.Details
		FROM #Results r
		WHERE r.CategoryID = 1
			AND r.CheckID NOT IN (110)
	UNION
	/*
		SELECT
			'Trace Flag In Use'
			, STRING_AGG(CONVERT (NVARCHAR (MAX), t.TraceFlag), ', ')
		FROM #TraceFlag t
	*/
	SELECT 
			'Trace Flag In Use'
			, STUFF( (
				SELECT ', ' + CAST(TraceFlag AS VARCHAR(10))
				FROM #TraceFlag t
				ORDER BY TraceFlag
				FOR XML PATH ('')
				), 1, 1, ''	)
		) r1
	PIVOT (
		MIN (Details)
		FOR CheckName IN (
		[Server Name]
		, [Instance Name]
		, [Instance Version]
		, [Instance Edition]
		, [Instance Build]
		, [Error Log Location]
		, [Default Data File Path]
		, [Default Log File Path]
		, [Default Backup File Path]
		, [Trace Flag In Use]
		, [Communication Protocol]
		, [Last Restart Time]
		, [CPU Configuration]
		, [Server Memory in MB]
		, [Operating System]
		, [Server Type]
		, [SQL Server Service Account]
		, [SQL Agent Service Account]
		, [IP Address]
		)
	) AS PivotTable;
	
	END;

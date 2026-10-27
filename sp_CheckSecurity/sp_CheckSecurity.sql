IF OBJECT_ID('dbo.sp_CheckSecurity') IS NULL
  EXEC ('CREATE PROCEDURE dbo.sp_CheckSecurity AS RETURN 0;');
GO


ALTER PROCEDURE dbo.sp_CheckSecurity
	@Mode TINYINT = 99
	, @CheckLocalAdmin BIT = 0
	, @PreferredDBOwner NVARCHAR(255) = NULL
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
    @Version = '2026.10.1'
    , @VersionDate = '20261023';

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
    sp_CheckSecurity from https://straightpathsql.com/

	Version: ' + @Version + ' updated ' + CONVERT(VARCHAR(10), @VersionDate, 101) + '
    	
    This script checks your SQL Server for several dozen possible vulnerabilities
    and gives you an ordered list with explanations and action items.
    
    Known limitations of this version:
    - sp_CheckSecurity only works on SQL Server 2016 or later.
    - sp_CheckSecurity will work with SQL Server 2012 and 2014, but it will skip
    a few checks. The results should still be valid and helpful, but you should
    really consider upgrading to a newer version by now.
    - If you attempt to execute sp_CheckSecurity on SQL Server 2008 R2 or older,
    then you will only receive an output message saying this will not run on your
    version. I''m sorry. No really, I''m sorry you have to support a version of
    SQL Server that old.
    - If a database name has a question mark in it, then certain checks will fail
    due to the usage of sp_MSforeachdb.

    Permissions:
    - The executing user must be a member of the sysadmin role; the procedure
    aborts otherwise.

    Parameters:
    @Mode   0=All discovered vulnerabilities
			1=Instance information only
			2=Only high vulnerability items will be shown
			99=Information and all discovered vulnerabilities shown(DEFAULT)
    
	@CheckLocalAdmin 1=Check members of local Administrators
                     0=Do NOT check members of local Administrators(DEFAULT)
    
	@PreferredDBOwner (This can be whatever login you prefer to have as the owner
                       of your databases. By default, it will be NULL and will
                       not check unless you provide a preferred owner login.)
    
	@Override for allowing checks on instances of over 50 databases


    *** WARNING FOR @CheckLocalAdmin usage ***

    If you execute sp_CheckSecurity with @CheckLocalAdmin = 1, then sp_CheckSecurity
    will attempt to read and record the members of the BUILTIN\Administrators
    group. If BUILTIN\Administrators is not currently a member of the Logins,
    then sp_CheckSecurity will proceed with the following logic.
    
    1. BEGIN an explicit transaction.
    2. Add BUILTIN\Administrators as a Login.
    3. Read and record the members of BUILTIN\Administrators.
    4. ROLLBACK the transaction, removing BUILTIN\Administrators from Logins.
    
    If you have ANY database level triggers or other fun features enabled to track 
    the addition of members to Logins then you, dear user, assume any responsibility 
    for any subsequent action from this brief addition.
    
    Please don''t say we didn''t warn you.

    *** End of WARNING FOR @CheckLocalAdmin usage ***


    MIT License
    	
    Copyright for portions of sp_CheckSecurity are held by Microsoft as part of project
    tigertoolbox and are provided under the MIT license:
    https://github.com/Microsoft/tigertoolbox
    
    Copyright for portions of sp_CheckSecurity are also held by Brent Ozar Unlimited
    as part of sp_Blitz and are provided under the MIT license:
    https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/
    	
    All other copyrights for sp_CheckSecurity are held by Straight Path Solutions.
    
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
IF @Override = 0 AND ((SELECT COUNT(database_id) from sys.databases where source_database_id IS NULL) > 50) BEGIN
	PRINT '
	You have over 50 databases, so you could have a lot of backup history.

	If you want to proceed, and you understand this procedure could use
	substantial resources to get your backup history, use @Override = 1.

	Godspeed, my friend.
'
	RETURN;
	END;  

/* check that user is in the sysadmin role */
IF IS_SRVROLEMEMBER ('sysadmin') = 0 BEGIN
	PRINT '
/*
    *** Executing user is NOT in the sysadmin role ***

    sp_CheckSecurity is designed only for database administrators, so the user
    must be a member of the sysadmin role to complete the checks.

	For more information about the limitations of sp_CheckSecurity, execute
    using @Help = 1

    *** EXECUTION ABORTED ***
    	   
*/';
	RETURN;
	END; 

DECLARE 
	@SQL NVARCHAR(MAX)
	, @SQLVersion NVARCHAR(128)
	, @SQLVersionMajor DECIMAL(10,2)
	, @SQLVersionMinor DECIMAL(10,2)
	, @ComputerNamePhysicalNetBIOS NVARCHAR(128)
	, @ServerZeroName sysname
	, @SQLServerService NVARCHAR(256)
	, @SQLAgentService NVARCHAR(256)
	, @InstanceName NVARCHAR(128)
	, @Edition NVARCHAR(128);

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
	, 'sp_CheckSecurity'
	, 'Provided by Straight Path IT Solutions, LLC'
	, NULL
	, '(Information captured on ' + CONVERT(VARCHAR(100), GETDATE(), 101) + ' using version ' + @Version + ')'
	, 'Use this FREE tool to check your SQL Server instance for security issues!'
	, 'https://straightpathsql.com/tool/sp_checksecurity/';


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

/* check for unsupported version */	
IF @Override = 0 AND @SQLVersionMajor < 11 BEGIN
	PRINT '
/*
    *** Unsupported SQL Server Version ***

    sp_CheckSecurity is supported only for execution on SQL Server 2012 and later.

	For more information about the limitations of sp_CheckSecurity, execute
    using @Help = 1

    *** EXECUTION ABORTED ***
    	   
*/';
	RETURN;
	END; 

SELECT
	@ComputerNamePhysicalNetBIOS = CAST(SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS NVARCHAR(128))
	, @InstanceName = CAST(SERVERPROPERTY('InstanceName') AS NVARCHAR(128))
	, @Edition = CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128));


SELECT @ServerZeroName = [name]
FROM sys.servers
WHERE server_id = 0;

SELECT @SQLServerService = service_account
FROM sys.dm_server_services 
WHERE servicename LIKE 'SQL Server (%';

SELECT @SQLAgentService = service_account
FROM sys.dm_server_services 
WHERE servicename LIKE 'SQL Server Agent%';

/*
Configuration Manager settings, read once because they are used by both the instance information and the issues
*/
DECLARE @HideInstance int = NULL
	, @ExtendedProtection int = NULL
	, @ForceEncryption int = NULL;

EXECUTE master.dbo.xp_instance_regread
	@rootkey = 'HKEY_LOCAL_MACHINE'
	, @key = 'Software\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib'
	, @value_name = 'HideInstance'
	, @value = @HideInstance OUTPUT
	, @no_output = 'no_output';

EXECUTE master.dbo.xp_instance_regread
	@rootkey = 'HKEY_LOCAL_MACHINE'
	, @key = 'Software\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib'
	, @value_name = 'ExtendedProtection'
	, @value = @ExtendedProtection OUTPUT
	, @no_output = 'no_output';

EXECUTE master.dbo.xp_instance_regread
	@rootkey = 'HKEY_LOCAL_MACHINE'
	, @key = 'Software\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib'
	, @value_name = 'ForceEncryption'
	, @value = @ForceEncryption OUTPUT
	, @no_output = 'no_output';

/*
Discovery
*/
IF @Mode IN (1, 99) BEGIN /* Collect instance info */
	/* capture date */
	INSERT #Results
	SELECT 
		1
		, 100
		, 0
		, 'Capture date'
		, 'Capture date'
		, NULL
		, '(Information captured on ' + CONVERT(VARCHAR(100), GETDATE(), 101) + ' using version ' + @Version + ')'
		, NULL
		, '';

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
		, 'Check to make sure this is not an externally-facing server and this IP address cannot be reached outside your network.'
		, 'https://straightpathsql.com/check/ip-address';

	/* remote admin connections */
	INSERT #Results
	SELECT
		1
		, 310
		, 0
		, 'Configuration: Remote admin connections'
		, 'Remote admin connections'
		, NULL
		, 'Remote admin connections are currently '
			+  CASE value_in_use
				WHEN 1 THEN 'ENABLED.'
				ELSE 'DISABLED.'
				END
		, NULL
		, 'https://straightpathsql.com/check/remote-dedicated-admin-connections'
	FROM sys.configurations
	WHERE [name] = 'remote admin connections';

	/* Database Mail XPs */
	INSERT #Results
	SELECT
		1
		, 311
		, 0
		, 'Configuration: Database Mail XPs'
		, 'Database Mail XPs'
		, NULL
		, 'Database Mail XPs are currently '
			+  CASE value_in_use
				WHEN 1 THEN 'ENABLED.'
				ELSE 'DISABLED.'
				END
		, NULL
		, 'https://straightpathsql.com/check/database-mail-xps'
	FROM sys.configurations
	WHERE [name] = 'Database Mail XPs';

	/* xp_cmdshell */
	INSERT #Results
	SELECT
		1
		, 319
		, 0
		, 'Configuration: xp_cmdshell'
		, 'xp_cmdshell'
		, NULL
		, 'xp_cmdshell is currently '
			+  CASE value_in_use
				WHEN 1 THEN 'ENABLED.'
				ELSE 'DISABLED.'
				END
		, NULL
		, 'https://straightpathsql.com/check/xp_cmdshell'
	FROM master.sys.configurations
	WHERE [name] = 'xp_cmdshell';

	/* C2 audit mode */
	INSERT #Results
	SELECT
		1
		, 341
		, 0
		, 'Configuration: C2 audit mode'
		, 'C2 audit mode'
		, NULL
		, 'C2 audit mode is currently '
			+  CASE value_in_use
				WHEN 1 THEN 'ENABLED.'
				ELSE 'DISABLED.'
				END
		, NULL
		, 'https://straightpathsql.com/check/c2-audit-mode'
	FROM sys.configurations
	WHERE [name] = 'c2 audit mode';

	/* common criteria compliance */
	INSERT #Results
	SELECT
		1
		, 342
		, 0
		, 'Configuration: Common Criteria Compliance'
		, 'Common Criteria Compliance'
		, NULL
		, 'Common Criteria Compliance is currently '
			+  CASE value_in_use
				WHEN 1 THEN 'ENABLED.'
				ELSE 'DISABLED.'
				END
		, NULL
		, 'https://straightpathsql.com/check/common-criteria-compliance'
	FROM sys.configurations
	WHERE [name] = 'common criteria compliance enabled';

	/* contained database authentication */
	INSERT #Results
	SELECT
		1
		, 343
		, 0
		, 'Configuration: Contained Database Authentication'
		, 'Contained Database Authentication'
		, NULL
		, 'Contained Database Authentication is currently '
			+  CASE value_in_use
				WHEN 1 THEN 'ENABLED.'
				ELSE 'DISABLED.'
				END
		, NULL
		, 'https://straightpathsql.com/check/contained-database'
	FROM sys.configurations
	WHERE [name] = 'contained database authentication';

	/* remote access */
	INSERT #Results
	SELECT
		1
		, 345
		, 0
		, 'Configuration: Remote Access'
		, 'Remote Access'
		, NULL
		, 'Remote Access is currently '
			+  CASE value_in_use
				WHEN 1 THEN 'ENABLED.'
				ELSE 'DISABLED.'
				END
		, NULL
		, 'https://straightpathsql.com/check/remote-access'
	FROM sys.configurations
	WHERE [name] = 'remote access';

	/* Hide instance */
	INSERT #Results
	SELECT
		1
		, 347
		, 0
		, 'Configuration Manager: Hide Instance'
		, 'Hide Instance'
		, NULL
		, 'Hide Instance is currently '
			+  CASE @HideInstance
				WHEN 1 THEN 'ENABLED.'
				WHEN 0 THEN 'DISABLED.'
				ELSE 'UNKNOWN.'
				END
		, NULL
		, 'https://straightpathsql.com/check/hide-instance';

	/* Extended protection */
	INSERT #Results
	SELECT
		1
		, 348
		, 0
		, 'Configuration Manager: Extended Protection'
		, 'Extended Protection'
		, NULL
		, 'Extended Protection is currently '
			+  CASE @ExtendedProtection
				WHEN 1 THEN 'ENABLED.'
				WHEN 0 THEN 'DISABLED.'
				ELSE 'UNKNOWN.'
				END
		, NULL
		, 'https://straightpathsql.com/check/extended-protection';

	/* Force encryption */
	INSERT #Results
	SELECT
		1
		, 349
		, 0
		, 'Configuration Manager: Force Encryption'
		, 'Force Encryption'
		, NULL
		, 'Force Encryption is currently '
			+  CASE @ForceEncryption
				WHEN 1 THEN 'ENABLED.'
				WHEN 0 THEN 'DISABLED.'
				ELSE 'UNKNOWN.'
				END
		, NULL
		, 'https://straightpathsql.com/check/force-encryption';

	END;


IF @Mode IN (0, 2, 99) BEGIN /* Collect issues info */

	/* remote admin connections */
	INSERT #Results
	SELECT 
		3
		, 310
		, 2
		, 'Configuration: Remote admin connections'
		, 'Remote admin connections are currently DISABLED.'
		, NULL
		, 'Remote admin connections are currently DISABLED.'
		, 'We recommend ''remote admin connections'' be ENABLED as a troubleshooting option for sysadmin role members.'
		, 'https://straightpathsql.com/check/remote-dedicated-admin-connections'
	FROM sys.configurations
	WHERE [name] = 'remote admin connections'
		AND value_in_use = 0; /* flagged only when disabled */


	/* Database Mail XPs */
	INSERT #Results
	SELECT 
		3
		, 311
		, 2
		, 'Configuration: Database Mail XPs'
		, 'Database Mail XPs'
		, NULL
		, 'Database Mail XPs are currently ENABLED.'
		, 'Enabling Database Mail XPs can be useful, but be aware if your instance is breached they could be used to initiate a Denial Of Service attack.'
		, 'https://straightpathsql.com/check/database-mail-xps'
		FROM sys.configurations
		WHERE [name] = 'Database Mail XPs'
			AND value_in_use = 1;


	/* check for supported versions */
	IF SERVERPROPERTY('EngineEdition') <> 8 /* Azure Managed Instances */ BEGIN
		IF @SQLVersionMajor < 13 BEGIN

			INSERT #Results
			SELECT 
				6
				, 602
				, 1
				, '*Unsupported version of SQL Server'
				, 'This version of SQL Server is no longer supported by Microsoft.'
				, NULL
				, 'SQL Server ' +  VersionName + ' is no longer supported, so there will be no future security updates.'
				, 'Upgrade to SQL Server 2016 or higher.'
				, 'https://straightpathsql.com/check/unsupported-versions'
			FROM #SQLVersions
			WHERE VersionNumber = @SQLVersionMajor
			END;
		END;
	

	/* check for security update */
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
		END;


	/* check for encrypted databases */
	INSERT #Results
	SELECT 
		3
		, 312
		, 2
		, 'Encrypted databases' 
		, 'One or more databases are using SQL Server encryption.' 
		, NULL
		, 'This instance has ' + CONVERT(VARCHAR(10), COUNT(database_id)) + ' encrypted databases using ' + key_algorithm + ' ' + CONVERT(VARCHAR(5), key_length) + '.'
		, 'Having encrypted databases is good, but make sure you have backed up your encryption keys to a secure location.'
		, 'https://straightpathsql.com/check/encrypted-databases'
	FROM sys.dm_database_encryption_keys
	WHERE database_id > 4
	GROUP BY 
		key_algorithm
		, key_length;

	/* check for unencrypted databases */
		INSERT #Results
	SELECT 
		3
		, 312
		, 2
		, 'Encrypted databases' 
		, 'One or more databases are NOT using SQL Server encryption.' 
		, NULL
		, 'This instance has ' + CONVERT(VARCHAR(10), COUNT(database_id)) + ' unencrypted databases.' 
		, 'Having unencrypted databases isn''t necessarily bad, but make sure you don''t need to have these user databases encrypted.'
		, 'https://straightpathsql.com/check/unencrypted-databases'
	FROM sys.databases d
	WHERE database_id > 4
		AND NOT EXISTS (SELECT 1 from sys.dm_database_encryption_keys dek where d.database_id = dek.database_id)
		AND d.source_database_id IS NULL; /* exclude snapshot databases */


/***** Login settings *****/

	/* sa is enabled */
	INSERT #Results
	SELECT 
		3
		, 307
		, 1
		, 'Enabled sa account'
		, 'The sa login is enabled.' 
		, NULL
		, 'The sa account is enabled for connections. Hackers commonly use the [sa] account for malicious activity since it is in the [sysadmin] role.'
		, 'Disable the sa account. Disabling only prevents sa from being used as a login for connections, as it can still own databases, jobs, etc.'
		, 'https://straightpathsql.com/check/enabled-sa-login'
	FROM sys.sql_logins
	WHERE sid = 0x01
	AND is_disabled = 0;

	/* sa has been renamed */
	INSERT #Results
	SELECT 
		3
		, 340
		, 2
		, 'Renamed sa account'
		, 'The sa login has been renamed.' 
		, NULL
		, 'The sa account has been renamed, but the new name can be easily determined by any other login.'
		, 'Did you mean to rename this? It''s more important that this login is disabled than renamed.'
		, 'https://straightpathsql.com/check/sa-login-renamed'
	FROM sys.sql_logins
	WHERE sid = 0x01
	AND [name] <> 'sa';

	/* local Administrators group members */
	DECLARE @LocalAdmin TABLE (
		AccountName VARCHAR(1000)
		, AccountType VARCHAR(8)
		, AccountPrivilege VARCHAR(9)
		, MappedLoginName VARCHAR(1000)
		, PermissionPath VARCHAR(1000)
		);
 
	 IF @CheckLocalAdmin = 1 BEGIN
		BEGIN TRAN
			IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE [name] = 'BUILTIN\Administrators')
				CREATE LOGIN [BUILTIN\Administrators] FROM WINDOWS WITH DEFAULT_DATABASE=[master];
 
			INSERT @LocalAdmin (AccountName, AccountType, AccountPrivilege, MappedLoginName, PermissionPath)
			EXEC xp_logininfo 'BUILTIN\Administrators', 'members'
 
			ROLLBACK

		INSERT #Results
		SELECT 
			3
			, 315
			, 1
			, 'local Administrators'
			, 'Members of the local Administrators Windows group.' 
			, NULL
			, 'The ' + AccountType + ' ' + AccountName + ' is in the local Administrator group. They can add themselves to the sysadmin role and then do anything in SQL Server, including dropping databases or changing other permissions.' 
			, 'Review all users and groups in the local Administrators group to verify they require these elevated permissions.' 
			, 'https://straightpathsql.com/check/local-administrators'
		FROM @LocalAdmin
		
		INSERT #Results
		SELECT 
			3
			, 351
			, 1
			, 'Service account in local Administrators'
			, 'The SQL Server service account is a member of the local Administrators Windows group.' 
			, NULL
			, 'The account [' + AccountName + '] is in the local Administrator group, so anyone with xp_cmdshell access can do anything on this server.' 
			, 'We recommend removing the service account from the local Administrators group to adhere to the principle of least privilege.'
			, 'https://straightpathsql.com/check/service-account-permissions'
		FROM @LocalAdmin
		WHERE AccountName = @SQLServerService;

		INSERT #Results
		SELECT 
			3
			, 351
			, 1
			, 'Service account in local Administrators'
			, 'The SQL Agent service account is a member of the local Administrators Windows group.' 
			, NULL
			, 'The account [' + AccountName + '] is in the local Administrator group, so anyone with xp_cmdshell access can do anything on this server.' 
			, 'We recommend removing the service account from the local Administrators group to adhere to the principle of least privilege.'
			, 'https://straightpathsql.com/check/service-account-permissions'
		FROM @LocalAdmin
		WHERE AccountName = @SQLAgentService;
		END;


	/* sysadmin members */
	INSERT #Results
	SELECT 
		3
		, 301
		, 1
		, 'sysadmin role members'
		, 'Members of the sysadmin role.'
		, NULL
		, 'Login [' + l.name + '] is a sysadmin. They can do anything in SQL Server, including dropping databases or changing other permissions.' 
		, 'Review the list of logins and groups in the sysadmin role to verify they require these elevated permissions.'
		, 'https://straightpathsql.com/check/sysadmin'
	FROM master.sys.syslogins l
	WHERE l.sysadmin = 1
	AND l.name <> SUSER_SNAME(0x01)
	AND l.denylogin = 0
	AND l.name NOT LIKE 'NT SERVICE\%'
	AND l.name <> 'l_certSignSmDetach'; /* Added in SQL 2016 */


	/* securityadmin members */
	INSERT #Results
	SELECT 
		3
		, 302
		, 1
		, 'securityadmin role members'
		, 'Members of the securityadmin role.'
		, NULL
		, 'Login [' + l.name + '] is a security admin. They can create other logins that do anything in SQL Server, including dropping databases or changing other permissions.' 
		, 'Review the list of logins and groups in the securityadmin role to verify they require these elevated permissions.'
		, 'https://straightpathsql.com/check/securityadmin'
	FROM master.sys.syslogins l
	WHERE l.securityadmin = 1
	AND l.name <> SUSER_SNAME(0x01)
	AND l.denylogin = 0;


	/* CONTROL SERVER permissions */
	INSERT #Results
	SELECT 
		3
		, 303
		, 1
		, 'CONTROL SERVER permissions'
		, 'Logins with CONTROL SERVER permissions.'
		, NULL
		, 'Login [' + pri.[name]+ '] has the CONTROL SERVER permission. They can do anything in SQL Server, including dropping databases or changing permissions.'
		, 'Review the list of logins and groups with CONTROL SERVER permission to verify they require these elevated permissions.'
		, 'https://straightpathsql.com/check/control-server'
	FROM sys.server_principals AS pri
	WHERE pri.[principal_id] IN (
		SELECT p.[grantee_principal_id]
		FROM sys.server_permissions AS p
		WHERE p.[state] IN ( 'G', 'W' )
		AND p.[class] = 100
		AND p.[type] = 'CL' )
		AND pri.[name] NOT LIKE '##%##';

	/* check for SQL Agent proxy account in sysadmin role */
	INSERT #Results
	SELECT 
		3
		, 352
		, 2
		, 'SQL Agent proxy account in sysadmin'
		, 'The SQL Agent proxy [' + p.[name] + '] uses the account [' + c.credential_identity + '], which is in the sysadmin role.'
		, NULL
		, 'Anyone granted use of this proxy can run job steps (CmdExec, PowerShell, SSIS, etc.) under an account that can do anything on the server, which is a privilege escalation path.'
		, 'We recommend mapping this proxy to a credential for an account that is not in the sysadmin role to adhere to the principle of least privilege.'
		, 'https://straightpathsql.com/check/proxy-account-in-sysadmin'
	FROM msdb.dbo.sysproxies AS p
	INNER JOIN sys.credentials AS c
		ON p.credential_id = c.credential_id
	WHERE IS_SRVROLEMEMBER('sysadmin', c.credential_identity) = 1
		AND p.[enabled] = 1;

	/* check for xp_cmdshell proxy account credential */
	INSERT #Results
	SELECT 
		3
		, 353
		, 1
		, 'xp_cmdshell proxy account exists'
		, 'The xp_cmdshell proxy account credential exists.'
		, NULL
		, 'The credential [##xp_cmdshell_proxy_account##] exists, which lets logins that are NOT in the sysadmin role run operating system commands via xp_cmdshell using the Windows account [' + credential_identity + ']. '
		, 'Verify that non-sysadmin OS command execution is intended. If not, remove the proxy.'
		, 'https://straightpathsql.com/check/xp_cmdshell'
	FROM sys.credentials
	WHERE name = '##xp_cmdshell_proxy_account##';

	/* Agent proxies accessible to principals that are not sysadmins */
	INSERT #Results
	SELECT
		3
		, 374
		, 1
		, 'Agent proxy accessible to non-sysadmin'
		, 'One or more SQL Server Agent proxies can be used by principals that are not sysadmins.'
		, NULL
		, 'The proxy ' + QUOTENAME(p.[name]) + ' runs as the Windows account ' + QUOTENAME(c.credential_identity) + ' and is authorized for the ' + COALESCE(subs.list, '(none)') + ' subsystem(s). It is granted to ' + prins.list + '. Any principal with access to this proxy can create or run Agent job steps that execute as that Windows account, so its effective permissions are those of the credential rather than those of the login.'
		, 'Confirm the proxy is required and that the principals granted to it still need it. Review the privileges held by the Windows account in the credential, since that account determines what any job step using this proxy can reach. Proxies granted to public should be narrowed to specific principals.'
		, 'https://straightpathsql.com/check/agent-proxy'
	FROM msdb.dbo.sysproxies AS p
	INNER JOIN sys.credentials AS c
		ON p.credential_id = c.credential_id
	/* subsystems the proxy is authorized for */
	CROSS APPLY (
		SELECT list = STUFF((
			SELECT ', ' + ss.subsystem COLLATE DATABASE_DEFAULT
			FROM msdb.dbo.sysproxysubsystem AS pss
			INNER JOIN msdb.dbo.syssubsystems AS ss
				ON ss.subsystem_id = pss.subsystem_id
			WHERE pss.proxy_id = p.proxy_id
			ORDER BY ss.subsystem COLLATE DATABASE_DEFAULT
			FOR XML PATH('')
		), 1, 2, '')
	) subs
	/* principals the proxy is granted to: server logins, msdb roles, or the public role */
	CROSS APPLY (
		SELECT list = STUFF((
			SELECT ', ' + COALESCE(sp.[name] COLLATE DATABASE_DEFAULT, mdp.[name] COLLATE DATABASE_DEFAULT, CONVERT(varchar(100), spl.sid, 1))
			FROM msdb.dbo.sysproxylogin AS spl
			LEFT JOIN sys.server_principals AS sp
				ON sp.sid = spl.sid
			LEFT JOIN msdb.sys.database_principals AS mdp
				ON mdp.sid = spl.sid
			WHERE spl.proxy_id = p.proxy_id
			ORDER BY COALESCE(sp.[name] COLLATE DATABASE_DEFAULT, mdp.[name] COLLATE DATABASE_DEFAULT)
			FOR XML PATH('')
		), 1, 2, '')
	) prins
	/* include only proxies that have at least one grantee who is not a sysadmin; a server login grantee is excluded when it is in sysadmin, while msdb roles and public are always non-sysadmin grantees */
	WHERE EXISTS (
		SELECT 1
		FROM msdb.dbo.sysproxylogin AS spl
		LEFT JOIN sys.server_principals AS sp
			ON sp.sid = spl.sid
		WHERE spl.proxy_id = p.proxy_id
			AND COALESCE(CASE WHEN sp.[name] IS NOT NULL THEN IS_SRVROLEMEMBER('sysadmin', sp.[name]) END, 0) = 0
	);

	/* SQLAgentOperatorRole membership by principals that are not sysadmins */
	INSERT #Results
	SELECT
		3
		, 375
		, 1
		, 'SQLAgentOperatorRole membership'
		, 'One or more logins that are not sysadmins can create, run, and modify SQL Server Agent jobs.'
		, NULL
		, 'The login ' + QUOTENAME(sp.[name]) + ' is a member of SQLAgentOperatorRole in msdb. This is the most permissive of the Agent fixed database roles, allowing the member to create jobs, and to start, stop, and modify jobs owned by others, providing a path to running code on the server without holding permissions inside SQL Server.'
		, 'Confirm this membership is required. Where the login only needs to view or run its own jobs, SQLAgentReaderRole or SQLAgentUserRole may be sufficient. Review which proxies these principals can use, since the proxy credential determines what any job step they create can reach.'
		, 'https://straightpathsql.com/check/agent-operator-role'
	FROM msdb.sys.database_role_members AS drm
	INNER JOIN msdb.sys.database_principals AS rp
		ON rp.principal_id = drm.role_principal_id
	INNER JOIN msdb.sys.database_principals AS mp
		ON mp.principal_id = drm.member_principal_id
	/* resolve the msdb role member back to a server login by SID */
	INNER JOIN sys.server_principals AS sp
		ON sp.sid = mp.sid
	WHERE rp.[name] = 'SQLAgentOperatorRole'
		AND sp.[name] NOT LIKE '##%'
		AND COALESCE(IS_SRVROLEMEMBER('sysadmin', sp.[name]), 0) = 0;

	/* logon triggers */
	INSERT #Results
	SELECT
		3
		, 376
		, 2
		, 'Logon trigger'
		, 'One or more logon triggers exist, executing code on every connection attempt to the instance.'
		, NULL
		, 'The logon trigger ' + QUOTENAME(t.[name]) + ' is ' + CASE t.is_disabled WHEN 1 THEN 'disabled' ELSE 'enabled' END + '. Logon triggers fire on every connection before the session is established, and execute in the security context of the login that created them rather than the connecting login. This means code runs with the creator''s privileges on every connection, and nothing in a review of permissions or role membership indicates it exists.'
			+ CASE WHEN ssm.definition IS NULL THEN ' The definition of this trigger is encrypted and cannot be reviewed.' ELSE '' END
		, 'Review what this trigger does and confirm it is intended. Logon triggers are a known persistence mechanism, and a trigger that cannot be accounted for should be investigated. Note that a logon trigger which errors or denies connections too broadly can lock out all logins including sysadmins, requiring recovery through the dedicated administrator connection in single-user mode.'
		, 'https://straightpathsql.com/check/logon-trigger'
	FROM sys.server_triggers AS t
	/* definition IS NULL indicates the trigger is encrypted (WITH ENCRYPTION) */
	LEFT JOIN sys.server_sql_modules AS ssm
		ON ssm.object_id = t.object_id
	WHERE t.parent_class_desc = 'LOGON'
		AND t.is_ms_shipped = 0;

	/* user-registered extended stored procedures (only relevant in master; sys.extended_procedures returns nothing from any other database context, and dll_name gives the backing DLL directly) */
	INSERT #Results
	SELECT
		3
		, 377
		, 2
		, 'Extended stored procedure registered'
		, 'One or more user-registered extended stored procedures exist, loading native code into the SQL Server process.'
		, NULL
		, 'The extended stored procedure ' + QUOTENAME([name]) + ' is registered and backed by the DLL ' + COALESCE(NULLIF(dll_name COLLATE DATABASE_DEFAULT, ''), '(unknown)') + '. A fault in the DLL can destabilize the instance, and the code has the same access to the operating system as the service account itself.'
		, 'Confirm what this procedure is and whether it is still required. Extended stored procedures have been deprecated since SQL Server 2005.'
		, 'https://straightpathsql.com/check/extended-stored-procedure'
	FROM master.sys.extended_procedures
	WHERE is_ms_shipped = 0;

	/* SQL Server Audit not capturing security-relevant actions. Server audits require Enterprise before SQL Server 2016 SP1 (build 4001); EngineEdition 3 = Enterprise/Developer/Evaluation, EngineEdition 8 = Azure SQL Managed Instance, both of which support it */
	IF (SERVERPROPERTY('EngineEdition') IN (3, 8)
		OR @SQLVersionMajor >= 14
		OR (@SQLVersionMajor = 13 AND @SQLVersionMinor >= 4001))
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM sys.server_audits WHERE is_state_enabled = 1)
			/* case 1: no enabled server audit at all */
			INSERT #Results
			SELECT
				3
				, 379
				, 2
				, 'SQL Server Audit not capturing security actions'
				, 'SQL Server Audit is not capturing the actions needed to detect and investigate a security incident.'
				, NULL
				, 'No enabled server audit exists on this instance. Without an audit, changes to logins, permissions, and role membership leave no durable record, and failed authentication attempts are not captured beyond whatever the error log retains.'
				, 'Configure a server audit with a server audit specification that includes at minimum FAILED_LOGIN_GROUP, SERVER_ROLE_MEMBER_CHANGE_GROUP, SERVER_PERMISSION_CHANGE_GROUP, SERVER_PRINCIPAL_CHANGE_GROUP, and AUDIT_CHANGE_GROUP. Confirm the audit target has sufficient space and that its files are retained long enough to be useful during an investigation.'
				, 'https://straightpathsql.com/check/sql-server-audit-coverage';
		ELSE
		BEGIN
			/* case 2: an enabled audit exists, but check whether an enabled specification under an enabled audit covers the security action groups */
			DECLARE @MissingAuditGroups nvarchar(max);

			;WITH RequiredGroups (grp) AS (
				SELECT 'FAILED_LOGIN_GROUP'
				UNION ALL SELECT 'SERVER_ROLE_MEMBER_CHANGE_GROUP'
				UNION ALL SELECT 'SERVER_PERMISSION_CHANGE_GROUP'
				UNION ALL SELECT 'SERVER_PRINCIPAL_CHANGE_GROUP'
				UNION ALL SELECT 'AUDIT_CHANGE_GROUP'
			)
			SELECT @MissingAuditGroups = COALESCE(@MissingAuditGroups + ', ', '') + rg.grp
			FROM RequiredGroups rg
			WHERE NOT EXISTS (
				SELECT 1
				FROM sys.server_audit_specifications AS sas
				INNER JOIN sys.server_audit_specification_details AS sasd
					ON sasd.server_specification_id = sas.server_specification_id
				INNER JOIN sys.server_audits AS sa
					ON sa.audit_guid = sas.audit_guid
				WHERE sas.is_state_enabled = 1
					AND sa.is_state_enabled = 1
					AND sasd.audit_action_name = rg.grp
			)
			ORDER BY rg.grp;

			IF @MissingAuditGroups IS NOT NULL
				INSERT #Results
				SELECT
					3
					, 379
					, 2
					, 'SQL Server Audit not capturing security actions'
					, 'SQL Server Audit is not capturing the actions needed to detect and investigate a security incident.'
					, NULL
					, 'An enabled server audit exists but does not capture the following action groups: ' + @MissingAuditGroups + '. An audit that omits these does not record failed logins, changes to server role membership and permissions, changes to logins, or changes to the audit configuration itself, so the actions most relevant to a security investigation are not being captured.'
					, 'Configure a server audit with a server audit specification that includes at minimum FAILED_LOGIN_GROUP, SERVER_ROLE_MEMBER_CHANGE_GROUP, SERVER_PERMISSION_CHANGE_GROUP, SERVER_PRINCIPAL_CHANGE_GROUP, and AUDIT_CHANGE_GROUP. Confirm the audit target has sufficient space and that its files are retained long enough to be useful during an investigation.'
					, 'https://straightpathsql.com/check/sql-server-audit-coverage';
		END;
	END;

	/* server-level permissions with an escalation path */
	INSERT #Results
	SELECT
		3
		, 354
		, 1
		, 'Server-level permissions granted to login'
		, 'One or more logins have been granted a server-level permission that provides a path to elevated privilege.'
		, NULL
		, 'The login ' + QUOTENAME(pri.[name]) + ' has been granted ' + p.[permission_name] COLLATE DATABASE_DEFAULT + '. Permissions of this type allow a login to modify other logins, act as another principal, change server role membership, manage stored credentials, or configure linked servers, each of which can be used to acquire privileges beyond those the login was intended to have.'
		, 'Confirm this grant is required and revoke it if it is not. Where the login needs a narrower capability, grant permission on the specific object rather than at the server level.'
		, 'https://straightpathsql.com/check/server-level-permissions'
	FROM sys.server_permissions AS p
	INNER JOIN sys.server_principals AS pri
		ON p.[grantee_principal_id] = pri.[principal_id]
	WHERE p.[state] IN ( 'G', 'W' ) /* G = granted, W = granted WITH GRANT OPTION */
		AND p.[class] = 100 /* server-level permission */
		AND p.[permission_name] IN (
			'ALTER ANY LOGIN'
			, 'IMPERSONATE ANY LOGIN'
			, 'ALTER ANY SERVER ROLE'
			, 'ALTER ANY CREDENTIAL'
			, 'ALTER ANY LINKED SERVER' )
		AND pri.[name] NOT LIKE '##%'
		/* exclude grantees that are already members of sysadmin; COALESCE keeps grantees that are not resolvable logins (server roles, certificate principals) in the results */
		AND COALESCE(IS_SRVROLEMEMBER('sysadmin', pri.[name]), 0) = 0;


	/* check for invalid Windows logins */
	IF OBJECT_ID('tempdb..#InvalidLogins') IS NOT NULL
		DROP TABLE #InvalidLogins;
	
	CREATE TABLE #InvalidLogins (
		LoginSID VARBINARY(85)
		, LoginName VARCHAR(256)
		);

	INSERT INTO #InvalidLogins
	EXEC sp_validatelogins;

	INSERT #Results
	SELECT 
		3
		, 304
		, 3
		, 'Invalid login with Windows Authentication'
		, 'There is a login with permissions that is no longer mapped to a valid Windows user.'
		, NULL
		, QUOTENAME(LoginName) + ' is an invalid Windows user or group that is mapped to a SQL Server principal.'
		, 'Verify the account no longer exists and carefully remove all SQL Server permissions.'
		, 'https://straightpathsql.com/check/invalid-windows-login'
	FROM #InvalidLogins;


	/* blank passwords */
	INSERT #Results
	SELECT 
		3
		, 316
		, 1
		, 'Password blank'
		, 'A SQL Server login has a blank password.'
		, NULL
		, 'Login [' + name + '] has a blank password.'
		, 'Change the password to something more secure. Logins with blank passwords are easy to hack.'
		, 'https://straightpathsql.com/check/password-vulnerabilities'
	FROM sys.sql_logins
	WHERE PWDCOMPARE('',password_hash)=1;

	/* password same as login */
	INSERT #Results
	SELECT 
		3
		, 317
		, 1
		, 'Password is same as login'
		, 'A SQL Server login has a password that is the same as the login.'
		, NULL
		, 'Login [' + name + '] has a password that is the same as the login.'
		, 'Change the password to something more secure. Logins with matching passwords are easy to hack.'
		, 'https://straightpathsql.com/check/password-vulnerabilities'
	FROM sys.sql_logins
	WHERE PWDCOMPARE(name,password_hash)=1;

	/* passwords is password */
	INSERT #Results
	SELECT 
		3
		, 318
		, 1
		, 'Password is password'
		, 'A SQL Server login has a password that is the word "password".'
		, NULL
		, 'Login [' + name + '] has a password that is the word "password".'
		, 'Change the password to this login to something more secure.'
		, 'https://straightpathsql.com/check/password-vulnerabilities'
	FROM sys.sql_logins
	WHERE PWDCOMPARE('password',password_hash)=1;


/***** Instance settings *****/

	/* CLR configuration */
	DECLARE @ClrEnabled bit
		, @ClrStrictSecurity bit;

	SELECT @ClrEnabled = CONVERT(bit, value_in_use)
	FROM master.sys.configurations
	WHERE [name] = 'clr enabled';

	/* clr strict security only exists on SQL Server 2017 and later; the row is absent on earlier versions, leaving this NULL */
	SELECT @ClrStrictSecurity = CONVERT(bit, value_in_use)
	FROM master.sys.configurations
	WHERE [name] = 'clr strict security';

	/* clr enabled on with clr strict security disabled (SQL Server 2017 and later); this is a finding regardless of SSISDB, since the disabled security default stands on its own */
	IF @SQLVersionMajor >= 14
		AND @ClrEnabled = 1
		AND @ClrStrictSecurity = 0
		INSERT #Results
		SELECT
			3
			, 309
			, 1
			, 'Configuration: clr enabled'
			, 'CLR is enabled and clr strict security has been disabled.'
			, NULL
			, 'The clr enabled setting is on and clr strict security is off. Disabling strict security restores the pre-2017 behavior where an assembly declared with PERMISSION_SET = SAFE is trusted, even though such an assembly may still access external system resources, call unmanaged code, and acquire sysadmin privileges. This is a security default that has been deliberately turned off.'
			, 'Enable clr strict security and sign any assemblies that fail to load with a certificate or asymmetric key that has a corresponding login granted UNSAFE ASSEMBLY.'
			, 'https://straightpathsql.com/check/clr-enabled';

	/* clr enabled on (SQL Server 2016 and earlier, where there is no clr strict security option); excluded when SSISDB exists because SSIS requires CLR */
	IF @SQLVersionMajor <= 13
		AND @ClrEnabled = 1
		AND NOT EXISTS (SELECT 1 FROM sys.databases WHERE [name] = 'SSISDB')
		INSERT #Results
		SELECT
			3
			, 309
			, 1
			, 'Configuration: clr enabled'
			, 'CLR is enabled.'
			, NULL
			, 'The clr enabled setting is on, allowing assemblies to execute in the context of the SQL Server service account. On this version there is no clr strict security option, so an assembly created with PERMISSION_SET = SAFE may still access external system resources, call unmanaged code, and acquire sysadmin privileges.'
			, 'Confirm CLR is still required and review the assemblies present.'
			, 'https://straightpathsql.com/check/clr-enabled';


	/* xp_cmdshell enabled */
	INSERT #Results
	SELECT 
		3
		, 319
		, 2
		, 'Configuration: xp_cmdshell'  
		, 'The "xp_cmdshell" configuration is enabled.'
		, NULL
		, 'xp_cmdshell allows for the execution of operating system commands in the context of the SQL Server account by members of the sysadmin role.' 
		, 'If you do not have any code requiring xp_cmdshell, disable this configuration option.'
		, 'https://straightpathsql.com/check/xp_cmdshell'
	FROM master.sys.configurations
	WHERE [name] = 'xp_cmdshell'
	AND value_in_use = 1;

	/* external scripts enabled (SQL Server 2016 and later; the configuration row does not exist on earlier versions) */
	IF @SQLVersionMajor >= 13
		INSERT #Results
		SELECT
			3
			, 369
			, 2
			, 'Configuration: external scripts enabled'
			, 'The external scripts enabled setting is on, allowing execution of external scripts through sp_execute_external_script.'
			, NULL
			, 'The external scripts enabled setting is on. This permits sp_execute_external_script to run code written in R, Python, or Java, depending on which Machine Learning Services components are installed. External scripts run outside the SQL Server process under the Launchpad service, but they can still read and write files, make network calls, and have been the subject of known vulnerabilities.'
			, 'Confirm that Machine Learning Services is actually in use. If it is not, disable the setting with sp_configure ''external scripts enabled'', 0 and restart the SQL Server service, since this option requires a restart to take effect.'
			, 'https://straightpathsql.com/check/external-scripts-enabled'
		FROM master.sys.configurations
		WHERE [name] = 'external scripts enabled'
		AND value_in_use = 1;

	/* Ole Automation Procedures enabled */
	INSERT #Results
	SELECT 
		3
		, 320
		, 2
		, 'Configuration: Ole Automation Procedures'  
		, 'The "Ole Automation Procedures" configuration is enabled.'
		, NULL
		, 'The ''Ole Automation Procedures'' configuration allows a call to create and execute functions in the context of SQL Server.' 
		, 'If you do not have any code requiring OLE Automation objects, disable this configuration option.'
		, 'https://straightpathsql.com/check/ole-automation-procedures'
	FROM master.sys.configurations
	WHERE [name] = 'Ole Automation Procedures'
	AND value_in_use = 1;


	/* cross-database ownership chaining */
	INSERT #Results
	SELECT 
		3
		, 321
		, 2
		, 'Configuration: Cross-database ownership chaining'  
		, 'The "cross-database ownership chaining" configuration is enabled.'
		, NULL
		, 'Cross-database ownership chaining allows database owners and members of the db_ddladmin and db_owner database roles to create objects that are owned by other users.' 
		, 'Since enabling this setting allows certain users to create objects that can potentially target objects in other databases, this configuration option should be enabled only at the database level.'
		, 'https://straightpathsql.com/check/cross-database-ownership-chaining'
	FROM master.sys.configurations
	WHERE [name] = 'cross db ownership chaining'
	AND value_in_use = 1;


	/* ad hoc distributed queries */
	INSERT #Results
	SELECT 
		3
		, 322
		, 2
		, 'Configuration: Ad Hoc Distributed Queries'
		, 'The "Ad Hoc Distributed Queries" configuration is enabled.'
		, NULL
		, 'Ad hoc distributed queries use the OPENROWSET and OPENDATASOURCE functions to connect to remote data sources that use OLE DB.' 
		, 'If a malicious user was able to utilize SQL injection, having this option enabled would allow them to read data files of their choosing.'
		, 'https://straightpathsql.com/check/ad-hoc-distributed-queries'
	FROM sys.configurations 
	WHERE [name] = 'Ad Hoc Distributed Queries'
	AND value_in_use = 1;

	/* jobs owned by users */
	INSERT #Results
	SELECT 
		6
		, 611
		, 2
		, 'SQL Agent jobs owned by users'
		, 'There are jobs that appear to be owned by user logins.'
		, NULL
		, 'Job [' + j.name + '] is owned by [' + SUSER_SNAME(j.owner_sid) + ']. If this login is disabled or not available due to Active Directory problems, the job will stop working.' 
		, 'Verify this login is the correct owner for the job. If possible, see if the job can be owned by sa.'
		, 'https://straightpathsql.com/check/sql-agent-jobs-owned-by-users'
	FROM msdb.dbo.sysjobs j
	WHERE j.enabled = 1
	AND SUSER_SNAME(j.owner_sid) <> SUSER_SNAME(0x01)
	AND SUSER_SNAME(j.owner_sid) not like '##%';

	/* stored procedures that run at startup */
	INSERT #Results
	SELECT 
		3
		, 313
		, 2
		, 'Stored procedure run at Startup' 
		, 'There is a stored procedure scheduled to run on startup.'
		, NULL
		, 'Stored procedure [master].[' + r.SPECIFIC_SCHEMA + '].[' + r.SPECIFIC_NAME + '] runs automatically when SQL Server starts up.'
		, 'Verify you and your team know exactly what this stored procedure is doing, because if not then it could pose a security risk.' 
		, 'https://straightpathsql.com/check/stored-procedures-that-run-at-startup'
	FROM master.INFORMATION_SCHEMA.ROUTINES r
	WHERE OBJECTPROPERTY(OBJECT_ID(ROUTINE_NAME), 'ExecIsStartup') = 1;

	/* jobs that run at startup */
	INSERT #Results
	SELECT 
		3
		, 314
		, 2
		, 'SQL Agent job run at Startup' 
		, 'There is a job scheduled to run on startup.'
		, NULL
		, 'Job [' + j.name + '] runs automatically when SQL Server Agent starts up.'
		, 'Verify you and your team know exactly what this job is doing, because it could pose a security risk.' 
		, 'https://straightpathsql.com/check/sql-agent-jobs-that-run-at-startup'
	FROM msdb.dbo.sysschedules s
	JOIN msdb.dbo.sysjobschedules js ON s.schedule_id = js.schedule_id
	JOIN msdb.dbo.sysjobs j ON js.job_id = j.job_id
	WHERE s.freq_type = 64
		AND s.enabled = 1
		AND j.enabled = 1;


	/* check for TDE certificate backup */
	INSERT #Results
	SELECT 
		2
		, 211
		, 1
		, 'TDE certificate not backed up recently'
		, 'There is a certificate used for TDE that has never been backed up.'
		, db_name(d.database_id)
		, 'The certificate ' + c.name + ' used to encrypt database ' + db_name(d.database_id) + ' has never been backed up.'
		, 'Make a backup of your current certificate and store it in a secure location in case you need to restore this encrypted database.'
		, 'https://straightpathsql.com/check/no-recent-tde-certificate-backup'
	FROM sys.certificates c 
	INNER JOIN sys.dm_database_encryption_keys d 
		ON c.thumbprint = d.encryptor_thumbprint
	WHERE c.pvt_key_last_backup_date IS NULL;

	INSERT #Results
	SELECT 
		2
		, 211
		, 1
		, 'TDE certificate not backed up recently'
		, 'There is a certificate used for TDE that has not been backed up recently.'
		, db_name(d.database_id)
		, 'The certificate ' + c.name + ' used to encrypt database ' + db_name(d.database_id) + ' has not been backed up since: ' + CAST(c.pvt_key_last_backup_date AS VARCHAR(100))
		, 'Make sure you have a recent backup of your certificate in a secure location in case you need to restore your encrypted database.'
		, 'https://straightpathsql.com/check/no-recent-tde-certificate-backup'
	FROM sys.certificates c 
	INNER JOIN sys.dm_database_encryption_keys d 
		ON c.thumbprint = d.encryptor_thumbprint
	WHERE c.pvt_key_last_backup_date <= DATEADD(dd, -90, GETDATE());

	/* check TDE certificate expiration dates */
	INSERT #Results
	SELECT 
		2
		, 213
		, 2
		, 'TDE certificate set to expire'
		, 'There is a certificate used for TDE that is set to expire.'
		, db_name(d.database_id)
		, 'The certificate ' + c.name + ' used to encrypt database ' + db_name(d.database_id) + ' is set to expire on: ' + CAST(c.expiry_date AS VARCHAR(100))
		, 'Although you will still be able to backup or restore your encrypted database with an expired certificate, these should be changed regularly like passwords.'
		, 'https://straightpathsql.com/check/tde-certificate-expiration-date'
	FROM sys.certificates c 
	INNER JOIN sys.dm_database_encryption_keys d 
		ON c.thumbprint = d.encryptor_thumbprint;


	/* check for database backup certificate backup */
	IF @SQLVersionMajor >= 12 BEGIN

		SET @SQL = '
		SELECT DISTINCT
			2
			, 210
			, 1
			, ''Database backup certificate never been backed up.''
			, ''There is a certificate used for backups that has never been backed up.''
			, b.[database_name]
			, ''The certificate '' + c.name + '' used to encrypt database backups for '' + b.[database_name] + '' has never been backed up.''
			, ''Make sure you have a recent backup of your certificate in a secure location in case you need to restore encrypted database backups.''
			, ''https://straightpathsql.com/check/missing-database-backup-certificate-backup''
		FROM sys.certificates c 
		INNER JOIN msdb.dbo.backupset b
			ON c.thumbprint = b.encryptor_thumbprint
		WHERE c.pvt_key_last_backup_date IS NULL
			AND b.encryptor_thumbprint IS NOT NULL;';

		INSERT #Results
		EXEC sp_executesql @SQL;

		SET @SQL = '
		SELECT DISTINCT
			2
			, 210
			, 2
			, ''Database backup certificate not backed up recently.''
			, ''There is a certificate used for backups that has not been backed up recently.''
			, b.[database_name]
			, ''The certificate '' + c.name + '' used to encrypt database backups for '' + b.[database_name] + '' has not been backed up since: '' + CAST(c.pvt_key_last_backup_date AS VARCHAR(100))
			, ''Make sure you have a recent backup of your certificate in a secure location in case you need to restore encrypted database backups.''
			, ''https://straightpathsql.com/check/missing-database-backup-certificate-backup''
		FROM sys.certificates c 
		INNER JOIN msdb.dbo.backupset b
			ON c.thumbprint = b.encryptor_thumbprint
		WHERE c.pvt_key_last_backup_date <= DATEADD(dd, -90, GETDATE());';

		INSERT #Results
		EXEC sp_executesql @SQL;


	/* check for database backup certificate expiration dates */
		SET @SQL = '
		SELECT DISTINCT
			2
			, 212
			, 2
			, ''Database backup certificate set to expire.''
			, ''There is a certificate used for backups that is set to expire.''
			, b.[database_name]
			, ''The certificate '' + c.name + '' used to encrypt database '' + b.[database_name] + '' is set to expire on: '' + CAST(c.expiry_date AS VARCHAR(100))
			, ''You will not be able to backup or restore your encrypted database backups with an expired certificate, so these should be changed regularly like passwords.''
			, ''https://straightpathsql.com/check/database-backup-certificate-expiration-date''
		FROM sys.certificates c 
		INNER JOIN msdb.dbo.backupset b
			ON c.thumbprint = b.encryptor_thumbprint';

		INSERT #Results
		EXEC sp_executesql @SQL;
	
		END;


	/* build a single list of full backups taken in the last 7 days, shared by the encryption (219) and local-drive (220) checks so msdb is queried once */
	IF OBJECT_ID('tempdb..#FullBackups') IS NOT NULL
		DROP TABLE #FullBackups;

	CREATE TABLE #FullBackups (
		backup_set_id INT
		, [database_name] sysname
		, physical_device_name nvarchar(260)
		, device_type TINYINT
		, key_algorithm nvarchar(50) NULL
		, has_backup_checksums BIT
		, is_copy_only BIT
		, backup_start_date DATETIME
		);

	/* key_algorithm only exists on SQL Server 2014 and later, so it is selected conditionally; the date range is filtered first so the seek uses the backup_start_date index rather than scanning all history */
	SET @SQL = '
	SELECT
		b.backup_set_id
		, b.[database_name]
		, mf.physical_device_name
		, mf.device_type
		, ' + CASE WHEN @SQLVersionMajor >= 12 THEN 'b.key_algorithm' ELSE 'NULL' END + '
		, b.has_backup_checksums
		, b.is_copy_only
		, b.backup_start_date
	FROM msdb.dbo.backupset b
	INNER JOIN msdb.dbo.backupmediafamily mf
		ON mf.media_set_id = b.media_set_id
	WHERE b.backup_start_date >= DATEADD(dd, -7, GETDATE())
		AND b.[type] = ''D'';';

	INSERT #FullBackups (backup_set_id, [database_name], physical_device_name, device_type, key_algorithm, has_backup_checksums, is_copy_only, backup_start_date)
	EXEC sp_executesql @SQL;


	/* unencrypted full backups (a NULL key_algorithm means the backup is unencrypted; the encryption columns exist only on SQL Server 2014 and later) */
	IF @SQLVersionMajor >= 12
		INSERT #Results
		SELECT
			2
			, 219
			, 2
			, 'Backups not encrypted'
			, 'Full backups for one or more databases are not encrypted.'
			, fb.[database_name]
			, 'This database has one or more unencrypted full backups in the last 7 days. An unencrypted backup file contains the entire database in a portable form, and can be restored on any instance where the person holding the file is a sysadmin.'
			, 'Enable backup encryption using a certificate or asymmetric key, and confirm that the certificate used has been backed up separately from the backup files themselves.'
			, 'https://straightpathsql.com/check/backups-not-encrypted'
		FROM #FullBackups fb
		WHERE fb.key_algorithm IS NULL
		GROUP BY fb.[database_name];


	/* full backups written to a local drive letter (a single letter, colon, backslash), excluding UNC paths, URL device backups (device_type 9), and cluster shared volumes */
	INSERT #Results
	SELECT
		2
		, 220
		, 2
		, 'Backups written to a local drive'
		, 'Full backups for one or more databases are written to a drive letter rather than to a network share or object storage.'
		, fb.[database_name]
		, 'This database has ' + CAST(COUNT(DISTINCT fb.backup_set_id) AS VARCHAR(20)) + ' full backups in the last 7 days written to '
			+ STUFF((
				SELECT DISTINCT ', ' + fb2.physical_device_name COLLATE DATABASE_DEFAULT
				FROM #FullBackups fb2
				WHERE fb2.[database_name] = fb.[database_name]
					AND fb2.physical_device_name LIKE '[A-Z]:\%'
					AND fb2.physical_device_name NOT LIKE '\\%'
					AND fb2.device_type <> 9
					AND fb2.physical_device_name NOT LIKE 'C:\ClusterStorage\%'
				FOR XML PATH('')
			), 1, 2, '')
			+ '. Backups on a drive letter are typically on storage attached to the same server as the database files, so the loss of the server or its storage takes the backups with it.'
		, 'Write backups to a network share, object storage, or another target that does not depend on this server, or copy them there immediately after the backup completes. Confirm at least one copy exists that would survive the loss of this server.'
		, 'https://straightpathsql.com/check/backups-local-drive'
	FROM #FullBackups fb
	WHERE fb.physical_device_name LIKE '[A-Z]:\%'
		AND fb.physical_device_name NOT LIKE '\\%'
		AND fb.device_type <> 9
		AND fb.physical_device_name NOT LIKE 'C:\ClusterStorage\%'
	GROUP BY fb.[database_name];


	/* full backups created without a checksum (values and logic shared with sp_CheckBackup CheckID 202, including its SQL Server 2014 and later gate) */
	IF @SQLVersionMajor > 11
		INSERT #Results
		SELECT
			2
			, 202
			, 2
			, 'Backups without checksum'
			, 'Recent backups created without using checksum'
			, fb.[database_name]
			, 'The database ' + fb.[database_name] COLLATE DATABASE_DEFAULT + ' has had ' + CAST(COUNT(DISTINCT fb.backup_set_id) AS VARCHAR(9)) + ' recent backups without a checksum.'
			, 'We recommend verifying all backups with checksum to reduce the likelihood of any corrupted backup files.'
			, 'https://straightpathsql.com/check/backup-checksum'
		FROM #FullBackups fb
		WHERE fb.has_backup_checksums = 0
			AND fb.is_copy_only = 0
		GROUP BY fb.[database_name];


	/* linked server check */
 	INSERT #Results
	SELECT 
		3
		, 323
		, 1
		, 'Linked Server configured with sa'
		, 'There is a linked Server configured with the sa login.'
		, NULL
		, 'The linked server ' + s.name + ' connects to the source ' + s.data_source + ' (' + COALESCE(s.product, s.provider) + ') using the security context of the sa login, which allows any user to perform any action on the linked server.'
		, 'Change the security configuration of the linked server to use a more secure context.'
		, 'https://straightpathsql.com/check/linked-server'
	FROM sys.servers s
	INNER JOIN sys.linked_logins l
	 ON s.server_id = l.server_id
	WHERE s.is_linked = 1
	 AND l.local_principal_id = 0
	 AND l.uses_self_credential = 0
	 AND l.remote_name = 'sa';

 	INSERT #Results
	SELECT 
		3
		, 324
		, 2
		, 'Linked Server configured with fixed login'
		, 'There is a linked Server configured with a fixed login.'
		, NULL
		, 'The linked server ' + s.name + ' connects to the source ' + s.data_source + ' (' + COALESCE(s.product, s.provider) + ') using the security context of the login: [' + l.remote_name + '].'
		, 'Check the security configuration to make sure this login is not in the sysadmin role, which would allow any user to perform any action on the linked server.'
		, 'https://straightpathsql.com/check/linked-server'
	FROM sys.servers s
	INNER JOIN sys.linked_logins l
	 ON s.server_id = l.server_id
	WHERE s.is_linked = 1
	 AND l.local_principal_id = 0
	 AND l.uses_self_credential = 0
	 AND l.remote_name IS NOT NULL
	 AND l.remote_name <> 'sa';

  	INSERT #Results
	SELECT 
		3
		, 325
		, 2
		, 'Linked Server'
		, 'There is a linked Server configured using the login''s current security context.'
		, NULL
		, 'The linked server ' + s.name + ' connects to the source ' + s.data_source + ' (' + COALESCE(s.product, s.provider) + ') using the login''s current security context.'
		, 'This security context is probably not an issue, but we note it in case this linked server is no longer needed.'
		, 'https://straightpathsql.com/check/linked-server'
	FROM sys.servers s
	INNER JOIN sys.linked_logins l
	 ON s.server_id = l.server_id
	WHERE s.is_linked = 1
	 AND l.local_principal_id = 0
	 AND l.uses_self_credential = 1
	 AND l.remote_name IS NULL;

  	INSERT #Results
	SELECT 
		3
		, 325
		, 2
		, 'Linked Server'
		, 'There is a linked Server configured without a security context.'
		, NULL
		, 'The linked server ' + s.name + ' connects to the source ' + s.data_source + ' (' + COALESCE(s.product, s.provider) + ') without a security context (denied).'
		, 'This security context is probably not an issue, but we note it in case this linked server is no longer needed.'
		, 'https://straightpathsql.com/check/linked-server'
	FROM sys.servers s
	INNER JOIN sys.linked_logins l
	 ON s.server_id = l.server_id
	WHERE s.is_linked = 1
	 AND l.local_principal_id = 0
	 AND l.uses_self_credential = 0
	 AND l.remote_name IS NULL;

  	INSERT #Results
	SELECT 
		3
		, 325
		, 2
		, 'Linked Server'
		, 'There is a linked Server configured with the security context of a remote login.'
		, NULL
		, 'The linked server ' + s.name + ' connects to the source ' + s.data_source + ' (' + COALESCE(s.product, s.provider) + ') for [' + p.name + '] using the security context of the remote name: [' + l.remote_name + '].'
		, 'Check the security configuration to make sure this login is not in the sysadmin role, which would allow any user to perform any action on the linked server.'
		, 'https://straightpathsql.com/check/linked-server'
	FROM sys.servers s
	INNER JOIN sys.linked_logins l
	 ON s.server_id = l.server_id
	INNER JOIN sys.server_principals p
		ON l.local_principal_id = p.principal_id
	WHERE s.is_linked = 1
	 AND l.local_principal_id <> 0
	 AND l.uses_self_credential = 0
	 AND l.remote_name IS NOT NULL;

  	INSERT #Results
	SELECT 
		3
		, 325
		, 2
		, 'Linked Server'
		, 'There is a linked Server configured with self credentials.'
		, NULL
		, 'The linked server ' + s.name + ' connects to the source ' + s.data_source + ' (' + COALESCE(s.product, s.provider) + ') for [' + p.name + '] using their own self credentials.'
		, 'This security context is probably not an issue, but we note it in case this linked server is no longer needed.'
		, 'https://straightpathsql.com/check/linked-server'
	FROM sys.servers s
	INNER JOIN sys.linked_logins l
	 ON s.server_id = l.server_id
	INNER JOIN sys.server_principals p
		ON l.local_principal_id = p.principal_id
	WHERE s.is_linked = 1
	 AND l.local_principal_id <> 0
	 AND l.uses_self_credential = 1;

  
	/* endpoint owner */
  	INSERT #Results
	SELECT 
		4
		, 406
		, 1
		, 'Endpoint owner' 
		, 'There is an endpoint owned by a user login.'
		, NULL
		, 'Endpoint ' + ep.[name] + ' is owned by ' + SUSER_NAME(ep.principal_id) + '. If the endpoint owner login is disabled or not available due to Active Directory problems, then high availability will stop working.'
		, 'Verify this is the correct owner of this endpoint, and if it is not then assign ownership to sa.'
		, 'https://straightpathsql.com/check/endpoint-ownership'
	FROM sys.database_mirroring_endpoints ep
	LEFT OUTER JOIN sys.dm_server_services s
	 ON SUSER_NAME(ep.principal_id) = s.service_account
	WHERE s.service_account IS NULL AND ep.principal_id <> 1;


	/* endpoint encryption is weak or disabled */
	INSERT #Results
	SELECT
		3
		, 380
		, 2
		, 'Endpoint encryption'
		, 'The endpoint [' + ep.[name] + '] does not require AES encryption.'
		, NULL
		, 'The database mirroring endpoint [' + ep.[name] + '] uses the encryption algorithm ' + ep.encryption_algorithm_desc + '. RC4 is deprecated and considered weak, and an endpoint with no encryption sends availability group data across the network in the clear.'
		, 'We recommend altering the endpoint to use AES encryption, for example ALTER ENDPOINT [' + ep.[name] + '] FOR DATABASE_MIRRORING (ENCRYPTION = REQUIRED ALGORITHM AES). Make the change on every replica.'
		, 'https://straightpathsql.com/check/endpoint-encryption'
	FROM sys.database_mirroring_endpoints ep
	WHERE ep.encryption_algorithm_desc IN ('NONE', 'RC4', 'AES RC4', 'RC4 AES');


	/* check for audits */
  	INSERT #Results
	SELECT 
		3
		, 326
		, 2
		, 'SQL Server Audit running'
		, 'There is a SQL Server Audit running.'
		, NULL
		, [name] + ' is a SQL Server Audit that is currently running.'
		, 'Verify this audit needs to be running, and if so any output files are in a secure directory.'
		, 'https://straightpathsql.com/check/sql-server-audit'
	FROM sys.dm_server_audit_status
	WHERE status = 1
	AND [name] NOT LIKE '%SQLBeacon%'; /* for SQL Beacon */


	/* database owner is not preferred owner */
	IF @PreferredDBOwner IS NOT NULL BEGIN

		INSERT #Results
		SELECT 
			3
			, 327
			, 2
			, 'Database owner is not preferred'
			, 'The database owner is not the preferred owner.'
			, [name]
			, 'The database ' + [name]
				+ ' is owned by ' + SUSER_SNAME(owner_sid) 
			, 'Verify this is the correct owner, because if this login is disabled or not available due to Active Directory problems then database accessibility could be affected.'
			, 'https://straightpathsql.com/check/database-owner-is-not-preferred-owner'
		FROM sys.databases
		WHERE (((SUSER_SNAME(owner_sid) <> SUSER_SNAME(0x01)) AND (name IN (N'master', N'model', N'msdb', N'tempdb')))
		OR ((SUSER_SNAME(owner_sid) <> @PreferredDBOwner) AND (name NOT IN (N'master', N'model', N'msdb', N'tempdb'))))
			AND source_database_id IS NULL; /* exclude snapshot databases */

		END;

	/* database owner is member of sysadmin role */
	INSERT #Results
	SELECT 
		3
		, 328
		, 2
		, 'Database owner is a sysadmin'
		, 'The database owner is a member of the sysadmin role.'
		, d.[name]
		, 'Members of the db_owner role in the database ' + d.[name] + ' can execute commands as the ' + l.[name] + ' login that owns the database.' 
		, 'Unless you are OK with db_owner role members using EXECUTE AS OWNER to do nearly anything on this instance, we recommend changing the database owner to a login not in the sysadmin role.'
		, 'https://www.insidesql.org/blogs/andreaswolter/2014/06/sql-server-database-ownership-survey-results-recommendations'
	FROM master.sys.databases d
	INNER JOIN master.sys.syslogins l
		ON d.owner_sid = l.sid
	WHERE l.sysadmin = 1
		AND d.database_id > 4
		AND d.source_database_id IS NULL; /* exclude snapshot databases */

	/* database owner is unknown */
	INSERT #Results
	SELECT 
		3
		, 305
		, 2
		, 'Database Owner is Unknown'  
		, 'The database owner is unknown (blank).'
		, [name]
		, ( 'Database name: ' + [name] + '   '
			+ 'Owner name: ' + ISNULL(SUSER_SNAME(owner_sid),'~~ UNKNOWN ~~') ) AS Details
		, 'Assign an owner to this database, preferably sa if possible.'
		, 'https://straightpathsql.com/check/database-owner-is-unknown'
	FROM sys.databases
	WHERE SUSER_SNAME(owner_sid) is NULL
		AND source_database_id IS NULL; /* exclude snapshot databases */


	/* check for SQL Server services using built-in elevated account */
	INSERT #Results
	SELECT 
		3
		, 329
		, 1
		, 'Service using built-in elevated account'
		, 'The SQL Server service is using a local elevated account.'
		, NULL
		, 'The SQL Server service is using an account that allows anyone with access to xp_cmdshell to do anything on the server.'
		, 'We recommend using a service account and not "LocalSystem" or "NT AUTHORITY\SYSTEM" for SQL Server services.'
		, 'https://straightpathsql.com/check/service-account-permissions'
	FROM sys.dm_server_services
	WHERE (service_account = 'LocalSystem' OR UPPER(service_account) = 'NT AUTHORITY\SYSTEM')
		AND servicename LIKE 'SQL Server%'
		AND servicename NOT LIKE 'SQL Server Agent%';

	INSERT #Results
	SELECT 
		3
		, 329
		, 1
		, 'Service using built-in elevated account'
		, 'The SQL Agent service is using a local elevated account.'
		, NULL
		, 'The SQL Agent service is using an account that allows anyone with access to jobs to do anything on the server.'
		, 'We recommend using a service account and not "LocalSystem" or "NT AUTHORITY\SYSTEM" for SQL Server services.'
		, 'https://straightpathsql.com/check/service-account-permissions'
	FROM sys.dm_server_services
	WHERE (service_account = 'LocalSystem' OR UPPER(service_account) = 'NT AUTHORITY\SYSTEM')
		AND servicename LIKE 'SQL Server Agent%';


	/* check for SQL Server service account in sysadmin role */
	INSERT #Results
	SELECT 
		3
		, 350
		, 2
		, 'Service account in sysadmin'
		, 'The SQL Server service is using account [' + service_account + '], which is in the sysadmin role.'
		, NULL
		, 'The SQL Server service has permissions to do anything on the server. This could result in privilege escalation via a stored procedure or job.'
		, 'We recommend removing the service account from the sysadmin role to adhere to the principle of least privilege.'
		, 'https://straightpathsql.com/check/service-account-permissions'
	FROM sys.dm_server_services 
	WHERE servicename like 'SQL Server (%'
		AND IS_SRVROLEMEMBER ('sysadmin', service_account) = 1;

	INSERT #Results
	SELECT 
		3
		, 350
		, 2
		, 'Service account in sysadmin'
		, 'The SQL Agent service is using account [' + service_account + '], which is in the sysadmin role.'
		, NULL
		, 'The SQL Agent service has permissions to do anything on the server. This could result in privilege escalation via a stored procedure or job.'
		, 'We recommend removing the service account from the sysadmin role to adhere to the principle of least privilege.'
		, 'https://straightpathsql.com/check/service-account-permissions'
	FROM sys.dm_server_services 
	WHERE servicename like 'SQL Server Agent%'
		AND IS_SRVROLEMEMBER ('sysadmin', service_account) = 1;


	/* Check that SQL Login Audit includes failed logins */
	DECLARE @AuditValue int = NULL;

	EXEC master.dbo.xp_instance_regread 
		@rootkey = 'HKEY_LOCAL_MACHINE'
		, @key = 'SOFTWARE\Microsoft\MSSQLServer\MSSQLServer'
		, @value_name = 'AuditLevel'
		, @value = @AuditValue OUTPUT
		, @no_output = 'no_output';

	IF @AuditValue < 2
		INSERT #Results
		SELECT 
			3
			, 330
			, 1
			, 'No audit of failed logins'
			, 'Failed logins are not being logged.'
			, NULL
			, 'The current SQL Login Audit settings do not include failed logins.'
			, 'SQL Error logs should capture failed login for review, since these may indicate hacking attempts.'
			,'https://straightpathsql.com/check/sql-login-audit-does-not-include-failed-logins';


	/* Failed logins */
	DECLARE @ErrorLog TABLE (
		LogDate datetime2
		, ProcessInfo nvarchar(255)
		, [Text] nvarchar(max)
		)
 
	INSERT @ErrorLog
	EXEC sp_readerrorlog 0, 1, 'Login failed'

	DECLARE @FailedLogins bigint

	SET @FailedLogins = (SELECT COUNT(*) FROM @ErrorLog)

	IF @FailedLogins > 0

		INSERT #Results
		SELECT 
			3
			, 331
			, 1
			, 'Failed logins'
			, 'Recent failed logins have occurred.'
			, NULL
			, 'There have been at least ' + CONVERT(VARCHAR(10), @FailedLogins) + ' failed logins recently.'
			, 'Review the SQL Server error log for patterns of login failures or suspect IP addresses which may indicate hacking attempts.'
			,'https://straightpathsql.com/check/failed-logins';

	/* NTLM authentication in use */
	DECLARE @NTLMSessions bigint
		, @NTLMTotalSessions bigint
		, @NTLMPercent decimal(5,2)

	/* Shared memory always reports NTLM, so exclude it to make the number meaningful */
	SELECT
		@NTLMSessions = SUM(CASE WHEN c.auth_scheme = 'NTLM' THEN 1 ELSE 0 END)
		, @NTLMTotalSessions = COUNT(*)
	FROM sys.dm_exec_connections c
	INNER JOIN sys.dm_exec_sessions s
		ON c.session_id = s.session_id
	WHERE s.is_user_process = 1
		AND c.net_transport <> 'Shared memory';

	SET @NTLMPercent = (@NTLMSessions * 100.0) / NULLIF(@NTLMTotalSessions, 0);

	IF @NTLMPercent > 10

		INSERT #Results
		SELECT
			3
			, 357
			, 2
			, 'NTLM authentication in use'
			, 'NTLM is deprecated and vulnerable to relay attacks.'
			, NULL
			, 'NTLM authentication is used by ' + CONVERT(VARCHAR(10), @NTLMPercent) + '% of active user sessions (' + CONVERT(VARCHAR(20), @NTLMSessions) + ' of ' + CONVERT(VARCHAR(20), @NTLMTotalSessions) + ' sessions).'
			, 'The usual cause is a missing or misregistered SPN for the SQL Server service account. Check the error log for messages containing ''Service Principal Name''.'
			, 'https://straightpathsql.com/check/ntlm-authentication';

	/* failed SPN registration */
	IF OBJECT_ID('tempdb..#SPNErrors') IS NOT NULL DROP TABLE #SPNErrors;

	CREATE TABLE #SPNErrors (
		LogDate datetime2
		, ProcessInfo nvarchar(255)
		, LogText nvarchar(max)
		);

	/* current error log only; return code 0x2098 means the service account cannot self-register the SPN */
	INSERT #SPNErrors
	EXEC sys.xp_readerrorlog 0, 1, N'could not register the Service Principal Name';

	DECLARE @SPNFailures bigint
		, @SPNList nvarchar(max)

	SET @SPNFailures = (SELECT COUNT(*) FROM #SPNErrors);

	IF @SPNFailures > 0
	BEGIN
		/* extract the SPN names from between the brackets in each message */
		SELECT @SPNList = COALESCE(@SPNList + ', ', '') + SpnName
		FROM (
			SELECT DISTINCT
				LTRIM(RTRIM(SUBSTRING(
					LogText
					, CHARINDEX('[', LogText) + 1
					, CHARINDEX(']', LogText) - CHARINDEX('[', LogText) - 1))) AS SpnName
			FROM #SPNErrors
			WHERE CHARINDEX('[', LogText) > 0
				AND CHARINDEX(']', LogText) > CHARINDEX('[', LogText)
			) x
		ORDER BY SpnName;

		INSERT #Results
		SELECT
			3
			, 358
			, 1
			, 'SPN registration failed'
			, 'The usual cause is a missing or misregistered SPN for the SQL Server service account. Check the error log for messages containing ''Service Principal Name''.'
			, NULL
			, 'SQL Server failed to register the following Service Principal Name(s) in the current error log: ' + COALESCE(@SPNList, '(SPN name could not be parsed)') + '.'
			, 'The service account lacks permission to register the SPN on its own Active Directory object, which is the normal state when SQL Server runs as a domain account. Someone with rights on that account needs to register the SPNs manually.'
			, 'https://straightpathsql.com/check/spn-registration';
	END;

	/* legacy password hash algorithm */
	INSERT #Results
	SELECT
		3
		, 359
		, 1
		, 'Legacy password hash algorithm'
		, 'One or more SQL logins still use the SHA-1 password hash algorithm from SQL Server 2008 R2 and earlier, which is significantly faster to crack.'
		, NULL
		, 'The SQL login ' + QUOTENAME([name]) + ' is using the legacy SHA-1 password hash, so this password was last set on an instance of SQL Server 2008 R2 or earlier.'
		, 'Change the password for this login to convert it to the current SHA-512 algorithm.'
		, 'https://straightpathsql.com/check/legacy-password-hash'
	FROM sys.sql_logins
	WHERE is_disabled = 0
		AND password_hash IS NOT NULL
		AND [name] NOT LIKE '##%'
		AND SUBSTRING(password_hash, 1, 2) = 0x0100 /* pre-2012 SHA-1 version marker; SHA-512 is 0x0200 */;

	/* SQL authentication in use */
	DECLARE @SQLAuthSessions bigint
		, @SQLAuthTotalSessions bigint
		, @SQLAuthPercent decimal(5,2)

	SELECT
		@SQLAuthSessions = SUM(CASE WHEN c.auth_scheme = 'SQL' THEN 1 ELSE 0 END)
		, @SQLAuthTotalSessions = COUNT(*)
	FROM sys.dm_exec_connections c
	INNER JOIN sys.dm_exec_sessions s
		ON c.session_id = s.session_id
	WHERE s.is_user_process = 1
		AND c.net_transport <> 'Shared memory';

	SET @SQLAuthPercent = (@SQLAuthSessions * 100.0) / NULLIF(@SQLAuthTotalSessions, 0);

	IF @SQLAuthPercent > 10

		INSERT #Results
		SELECT
			3
			, 360
			, 2
			, 'SQL authentication in use'
			, 'A significant portion of connections are using SQL logins, which rely on a name and password that can be used by anyone who has them.'
			, NULL
			, 'SQL authentication accounts for ' + CONVERT(VARCHAR(10), @SQLAuthPercent) + '% of current sessions (' + CONVERT(VARCHAR(20), @SQLAuthSessions) + ' of ' + CONVERT(VARCHAR(20), @SQLAuthTotalSessions) + ').'
			, 'Review which applications require SQL logins and whether they can be moved to Windows authentication. For any that must remain, verify that password policy enforcement is enabled.'
			, 'https://straightpathsql.com/check/sql-authentication';

	/* logins mapped to certificates or asymmetric keys */
	INSERT #Results
	SELECT
		3
		, 364
		, 2
		, 'Certificate or asymmetric key mapped login'
		, 'One or more logins are mapped to a certificate or asymmetric key rather than to a Windows account or a password.'
		, NULL
		, 'The login ' + QUOTENAME([name]) + ' is mapped to a ' + CASE [type] WHEN 'C' THEN 'certificate' WHEN 'K' THEN 'asymmetric key' END + '. These logins cannot be used to connect to the instance, but they can hold server-level permissions that are inherited by any module signed with the same certificate or key.'
		, 'Confirm the login is intentional and review what permissions it holds. Module signing is a legitimate way to grant elevated permissions to specific code without granting them to users.'
		, 'https://straightpathsql.com/check/certificate-mapped-logins'
	FROM sys.server_principals
	WHERE [type] IN ('C', 'K') /* C = certificate mapped, K = asymmetric key mapped */
		AND [name] NOT LIKE '##%'; /* exclude built-in Microsoft principals */

	/* membership in server roles with direct escalation paths */
	INSERT #Results
	SELECT
		3
		, 365
		, 1
		, 'Server role membership with escalation path'
		, 'One or more logins are members of a fixed server role that can be used to gain sysadmin-equivalent access.'
		, NULL
		, 'The login ' + QUOTENAME(mp.name) + ' is a member of the ' + QUOTENAME(rp.name) + ' fixed server role. Members of serveradmin can change any sp_configure setting, including enabling xp_cmdshell, CLR, and OLE Automation, and can shut down the instance. Members of dbcreator can create, alter, drop, and restore databases, and become the owner of databases they create. Members of setupadmin can create and configure linked servers, including those with fixed remote logins.'
		, 'Confirm this membership is required. Where the login only needs a specific capability, grant that permission directly rather than adding the login to a role that carries a route to elevated privilege.'
		, 'https://straightpathsql.com/check/server-role-escalation'
	FROM sys.server_role_members AS srm
	INNER JOIN sys.server_principals AS rp
		ON srm.role_principal_id = rp.principal_id
	INNER JOIN sys.server_principals AS mp
		ON srm.member_principal_id = mp.principal_id
	/* the ##MS_* granular server roles from SQL Server 2022 are excluded by this fixed-role list */
	WHERE rp.name IN ('serveradmin', 'dbcreator', 'setupadmin')
		AND mp.name NOT LIKE '##%'
		/* exclude members already in sysadmin, for whom these roles add nothing */
		AND NOT EXISTS (
			SELECT 1
			FROM sys.server_role_members AS sa
			INNER JOIN sys.server_principals AS sarp
				ON sa.role_principal_id = sarp.principal_id
			WHERE sarp.name = 'sysadmin'
				AND sa.member_principal_id = srm.member_principal_id
			);

	/* user-defined server roles holding escalation-capable permissions (SQL Server 2012 and later; user-defined server roles and the is_fixed_role column do not exist on earlier versions, so this is wrapped in dynamic SQL) */
	IF @SQLVersionMajor >= 11
	BEGIN
		SET @SQL = '
		SELECT
			3
			, 366
			, 1
			, ''Custom server role with elevated permissions''
			, ''One or more user-defined server roles hold permissions that provide a path to elevated privilege.''
			, NULL
			, ''The user-defined server role '' + QUOTENAME(rp.[name]) + '' has been granted '' + p.[permission_name] COLLATE DATABASE_DEFAULT + '' and has '' + CONVERT(VARCHAR(20), (SELECT COUNT(*) FROM sys.server_role_members AS srm WHERE srm.role_principal_id = rp.[principal_id])) + '' members. Permissions granted to a role do not appear when reviewing permissions granted directly to logins, so members of this role hold elevated privileges that are not visible in a review of login permissions or fixed server role membership.''
			, ''Review what this role is used for and whether its permissions can be narrowed. Confirm that every member requires the access the role provides.''
			, ''https://straightpathsql.com/check/custom-server-role-permissions''
		FROM sys.server_principals AS rp
		INNER JOIN sys.server_permissions AS p
			ON p.[grantee_principal_id] = rp.[principal_id]
		WHERE rp.[type] = ''R'' /* server role */
			AND rp.[is_fixed_role] = 0 /* isolates user-defined roles from the fixed server roles, which are also type R */
			AND rp.[name] NOT LIKE ''##%''
			AND p.[state] IN ( ''G'', ''W'' ) /* G = granted, W = granted WITH GRANT OPTION */
			AND p.[permission_name] IN (
				''CONTROL SERVER''
				, ''ALTER ANY LOGIN''
				, ''IMPERSONATE ANY LOGIN''
				, ''ALTER ANY SERVER ROLE''
				, ''ALTER ANY CREDENTIAL''
				, ''ALTER ANY LINKED SERVER''
				, ''ALTER SETTINGS'' );';

		INSERT #Results
		EXECUTE sp_executesql @SQL;
	END;

	/* BUILTIN\Administrators exists as a login */
	IF EXISTS (SELECT 1 FROM sys.server_principals WHERE [name] = 'BUILTIN\Administrators' AND [type] = 'G')
	BEGIN
		DECLARE @BuiltinAdminRoles nvarchar(max)
			, @BuiltinAdminDisabled bit;

		SELECT @BuiltinAdminDisabled = is_disabled
		FROM sys.server_principals
		WHERE [name] = 'BUILTIN\Administrators'
			AND [type] = 'G';

		/* the public role is implicit and not stored in sys.server_role_members, so a NULL result means public only */
		SELECT @BuiltinAdminRoles = COALESCE(@BuiltinAdminRoles + ', ', '') + rp.[name]
		FROM sys.server_role_members AS srm
		INNER JOIN sys.server_principals AS rp
			ON rp.principal_id = srm.role_principal_id
		INNER JOIN sys.server_principals AS mp
			ON mp.principal_id = srm.member_principal_id
		WHERE mp.[name] = 'BUILTIN\Administrators'
		ORDER BY rp.[name];

		INSERT #Results
		SELECT
			3
			, 367
			, 2
			, 'BUILTIN\Administrators exists as a login'
			, 'The local Windows Administrators group is present as a SQL Server login, granting instance access to every local administrator on the server.'
			, NULL
			, 'The login BUILTIN\Administrators exists on this instance, is currently ' + CASE @BuiltinAdminDisabled WHEN 1 THEN 'disabled' ELSE 'enabled' END + ', and is a member of ' + COALESCE(@BuiltinAdminRoles, 'the public role only') + '. This login was created by default in SQL Server 2005 and earlier and is not added by modern installations, so it typically survives from an in-place upgrade.'
			, 'Confirm whether anything depends on this login before removing it. Where local administrators require SQL Server access, grant it to named accounts or a specific Windows group so that access is visible and can be reviewed.'
			, 'https://straightpathsql.com/check/builtin-administrators-login';
	END;

	/* ALTER ANY SERVER AUDIT granted to non-sysadmin logins */
	INSERT #Results
	SELECT
		3
		, 368
		, 1
		, 'ALTER ANY SERVER AUDIT granted to login'
		, 'One or more logins can modify or disable SQL Server Audit without being a sysadmin.'
		, NULL
		, 'The login ' + QUOTENAME(pri.[name]) + ' has been granted ALTER ANY SERVER AUDIT. This permission allows the login to alter, disable, or drop server audits and audit specifications, removing the record of its own activity and any other activity the audit was configured to capture.'
		, 'Revoke this permission unless the login is responsible for managing audit configuration. Auditing is most effective when the accounts being audited cannot change what is being captured.'
		, 'https://straightpathsql.com/check/alter-any-server-audit'
	FROM sys.server_permissions AS p
	INNER JOIN sys.server_principals AS pri
		ON p.[grantee_principal_id] = pri.[principal_id]
	WHERE p.[permission_name] = 'ALTER ANY SERVER AUDIT'
		AND p.[state] IN ( 'G', 'W' ) /* G = granted, W = granted WITH GRANT OPTION */
		AND pri.[name] NOT LIKE '##%'
		/* exclude grantees that are already members of sysadmin; COALESCE keeps grantees that are not resolvable logins (server roles, certificate principals) in the results */
		AND COALESCE(IS_SRVROLEMEMBER('sysadmin', pri.[name]), 0) = 0;

	/* ALTER SETTINGS granted to non-sysadmin logins */
	INSERT #Results
	SELECT
		3
		, 370
		, 1
		, 'ALTER SETTINGS granted to login'
		, 'One or more logins can change server configuration options without being a sysadmin.'
		, NULL
		, 'The login ' + QUOTENAME(pri.[name]) + ' has been granted ALTER SETTINGS. This permission allows the login to run sp_configure and change any server configuration option, including enabling xp_cmdshell, OLE Automation Procedures, CLR, Ad Hoc Distributed Queries, and external scripts.'
		, 'Revoke this permission unless the login is responsible for server configuration. Disabling a dangerous configuration option provides little protection while a non-sysadmin retains the ability to re-enable it.'
		, 'https://straightpathsql.com/check/alter-settings-permission'
	FROM sys.server_permissions AS p
	INNER JOIN sys.server_principals AS pri
		ON p.[grantee_principal_id] = pri.[principal_id]
	WHERE p.[permission_name] = 'ALTER SETTINGS'
		AND p.[state] IN ( 'G', 'W' ) /* G = granted, W = granted WITH GRANT OPTION */
		AND pri.[name] NOT LIKE '##%'
		/* exclude grantees that are already members of sysadmin; COALESCE keeps grantees that are not resolvable logins (server roles, certificate principals) in the results */
		AND COALESCE(IS_SRVROLEMEMBER('sysadmin', pri.[name]), 0) = 0;

	/* UNSAFE ASSEMBLY / EXTERNAL ACCESS ASSEMBLY granted to non-sysadmin logins */
	INSERT #Results
	SELECT
		3
		, 372
		, 1
		, 'Assembly creation permission granted to login'
		, 'One or more logins can create CLR assemblies that run outside the SQL Server sandbox.'
		, NULL
		, 'The login ' + QUOTENAME(pri.[name]) + ' (a ' + CASE pri.[type]
			WHEN 'S' THEN 'SQL login'
			WHEN 'U' THEN 'Windows login'
			WHEN 'G' THEN 'Windows group'
			WHEN 'C' THEN 'certificate-mapped login'
			WHEN 'K' THEN 'asymmetric key-mapped login'
			WHEN 'R' THEN 'server role'
			ELSE 'principal'
			END + ') has been granted ' + p.[permission_name] COLLATE DATABASE_DEFAULT + '. EXTERNAL ACCESS ASSEMBLY allows creating assemblies that can reach the file system, the network, and the registry. UNSAFE ASSEMBLY allows creating assemblies with no restrictions at all, including calling unmanaged code. Assemblies run in the context of the SQL Server service account regardless of the permissions held by the login that invokes them.'
		, 'Revoke this permission unless the login exists specifically to sign assemblies. Where assemblies are required, grant the permission to a certificate-mapped login used only for module signing rather than to a login used by a person or an application.'
		, 'https://straightpathsql.com/check/assembly-permissions'
	FROM sys.server_permissions AS p
	INNER JOIN sys.server_principals AS pri
		ON p.[grantee_principal_id] = pri.[principal_id]
	WHERE p.[permission_name] IN ( 'UNSAFE ASSEMBLY', 'EXTERNAL ACCESS ASSEMBLY' )
		AND p.[state] IN ( 'G', 'W' ) /* G = granted, W = granted WITH GRANT OPTION */
		/* exclude the built-in Microsoft certificate principals, which hold these permissions legitimately */
		AND pri.[name] NOT LIKE '##%'
		/* exclude grantees that are already members of sysadmin; COALESCE keeps grantees that are not resolvable logins (server roles, certificate principals) in the results */
		AND COALESCE(IS_SRVROLEMEMBER('sysadmin', pri.[name]), 0) = 0;

	/* trusted assemblies registered (SQL Server 2017 and later; sys.trusted_assemblies does not exist on earlier versions, so this is wrapped in dynamic SQL. A clean instance has no default entries, so every row is a deliberate registration) */
	IF @SQLVersionMajor >= 14
	BEGIN
		SET @SQL = '
		SELECT
			3
			, 373
			, 1
			, ''Trusted assembly registered''
			, ''One or more assemblies are registered in sys.trusted_assemblies, allowing them to load without being signed.''
			, NULL
			, ''The assembly '' + COALESCE(NULLIF(LTRIM(RTRIM([description] COLLATE DATABASE_DEFAULT)), ''''), CONVERT(varchar(130), [hash], 1)) + '' is registered as a trusted assembly, added on '' + CONVERT(varchar(20), create_date, 120) + COALESCE('' by '' + created_by COLLATE DATABASE_DEFAULT, '''') + ''. Entries in sys.trusted_assemblies bypass clr strict security, so any assembly matching the registered hash loads without a certificate or asymmetric key signature. This means unsigned assemblies can load even when clr strict security is enabled, so the setting alone does not confirm that assemblies are being validated.''
			, ''Confirm what each registered assembly is and whether it is still in use. Sign the assembly with a certificate or asymmetric key that has a corresponding login granted UNSAFE ASSEMBLY, then remove the entry with sp_drop_trusted_assembly. Entries whose purpose cannot be established should be investigated, since registration requires deliberate action by a sysadmin.''
			, ''https://straightpathsql.com/check/trusted-assembly''
		FROM sys.trusted_assemblies;';

		INSERT #Results
		EXECUTE sp_executesql @SQL;
	END;

	/* number of error logs */
	DECLARE @NumErrorLogs INT = NULL;

	EXEC master.dbo.xp_instance_regread
		@rootkey = N'HKEY_LOCAL_MACHINE'
		, @key = N'Software\Microsoft\MSSQLServer\MSSQLServer'
		, @value_name = N'NumErrorLogs'
		, @value = @NumErrorLogs OUTPUT
		, @no_output = 'no_output';

	IF (SELECT ISNULL(@NumErrorLogs, 12)) <= 7

		INSERT #Results
		SELECT 
			6
			, 622
			, 2
			, 'Number of error logs'
			, 'Error log retention is at the default value of 6 archive files.'
			, NULL
			, 'This instance is configured for only ' + CONVERT(VARCHAR(10), (ISNULL(@NumErrorLogs, -1))) + ' SQL Server error log files.'
			, 'We recommend having between 12 and 52 SQL Server error log files to review for patterns of login failures or suspect IP addresses which may indicate hacking attempts.'
			, 'https://straightpathsql.com/check/number-of-sql-server-error-log-files';


	/* default trace disabled */
	INSERT #Results
	SELECT
		6
		, 633
		, 1
		, 'Default trace disabled'
		, 'The default trace is disabled, removing the built-in record of configuration and security changes.'
		, NULL
		, 'The default trace enabled setting is off. The default trace records events including database creation and deletion, changes to server configuration, login and role membership changes, permission changes, and object DDL. It is enabled by default, so disabling it is a deliberate change.'
		, 'Enable the default trace with sp_configure ''default trace enabled'', 1 followed by RECONFIGURE. Note that the default trace retains only five rollover files of 20 MB each, so it is a short window rather than a durable record, and it should not be relied on as a substitute for SQL Server Audit.'
		, 'https://straightpathsql.com/check/default-trace-disabled'
	FROM master.sys.configurations
	WHERE [name] = 'default trace enabled'
	AND value_in_use = 0;


	/* C2 audit mode */
	INSERT #Results
	SELECT 
		3
		, 341
		, 2
		, 'Configuration: C2 audit mode'
		, 'C2 audit mode'
		, NULL
		, 'C2 audit mode is currently ENABLED.'
		, 'Enabling C2 audit mode collects failed and successful attempts to access objects, but it also saves a large amount of event information to the log file. If the data directory in which logs are being saved runs out of space, SQL Server shuts itself down.'
		, 'https://straightpathsql.com/check/c2-audit-mode'
		FROM sys.configurations
		WHERE [name] = 'c2 audit mode'
			AND value_in_use = 1;


	/* common criteria compliance */
	INSERT #Results
	SELECT 
		3
		, 342
		, 2
		, 'Configuration: Common Criteria Compliance'
		, 'Common Criteria Compliance'
		, NULL
		, 'Common Criteria Compliance is currently ENABLED.'
		, 'Common Criteria Compliance is an Enterprise-only feature that helps meet requirements for the Common Criteria for Information Technology Security Evaluation. It does have performance impacts, though.'
		, 'https://straightpathsql.com/check/common-criteria-compliance'
		FROM sys.configurations
		WHERE [name] = 'common criteria compliance enabled'
			AND value_in_use = 1;


	/* contained database authentication */
	INSERT #Results
	SELECT 
		3
		, 343
		, 2
		, 'Configuration: Contained Database Authentication'
		, 'Contained Database Authentication'
		, NULL
		, 'Contained Database Authentication is currently ENABLED.'
		, 'Contained Database Authentication is required to install contained databases. A separate check will look for any contained databases.'
		, 'https://straightpathsql.com/check/contained-database'
		FROM sys.configurations
		WHERE [name] = 'contained database authentication'
			AND value_in_use = 1;


	/* remote access */
	INSERT #Results
	SELECT 
		3
		, 345
		, 2
		, 'Configuration: Remote Access'
		, 'Remote Access'
		, NULL
		, 'Remote Access is currently ENABLED.'
		, 'Remote Access allows for the execution of stored procedures from remote instances. This only needs to be enabled to use linked servers and/or log shipping.'
		, 'https://straightpathsql.com/check/remote-access'
		FROM sys.configurations
		WHERE [name] = 'remote access'
			AND value_in_use = 1;


	/*  Hide instance  */
	INSERT #Results
	SELECT
		3
		, 347
		, 2
		, 'Configuration Manager: Hide Instance'
		, 'Hide Instance'
		, NULL
		, 'Hide Instance is currently ENABLED.'
		, 'Hiding an instance prevents it from being seen by anyone browsing your network, however all connections must specify the port number.'
		, 'https://straightpathsql.com/check/hide-instance'
	WHERE @HideInstance = 1;


	/*  Extended protection  */
	INSERT #Results
	SELECT
		3
		, 348
		, 2
		, 'Configuration Manager: Extended Protection'
		, 'Extended Protection'
		, NULL
		, 'Extended Protection is currently ENABLED.'
		, 'Extended Protection uses service binding and channel binding to help prevent an authentication relay attack.'
		, 'https://straightpathsql.com/check/extended-protection'
	WHERE @ExtendedProtection = 1;


	/*  Force encryption  */
	INSERT #Results
	SELECT
		3
		, 349
		, 2
		, 'Configuration Manager: Force Encryption'
		, 'Force Encryption'
		, NULL
		, 'Force Encryption is currently ENABLED.'
		, 'Force Encryption ensures data in transit is encrypted, requiring all clients to use SSL/TLS encryption.'
		, 'https://straightpathsql.com/check/force-encryption'
	WHERE @ForceEncryption = 1;




/***** Database settings *****/

	/* contained databases */
	IF @SQLVersionMajor >= 11 BEGIN
/*
	INSERT #Results
	SELECT 
		3
		, 344
		, 2
		, 'contained database'
		, 'A contained database has certain security implications.'
		, db_name(database_id)
		, 'The database ' + db_name(database_id) + ' is set as CONTAINED.'
		, 'Although by design contained databases are isolated, be aware of other security implication of any contained database.'
		, 'https://straightpathsql.com/check/contained-database'
	FROM sys.databases
	WHERE containment > 0;
*/
		SET @SQL = '
		SELECT DISTINCT
			3
			, 344
			, 2
			, ''contained database''
			, ''The database ['' + db_name(database_id) + ''] is set as CONTAINED.''
			, db_name(database_id)
			, ''Although by design contained databases are isolated, be aware of other security implication of any contained database.''
			, ''Verify this database needs to be contained, and review the contained database users to ensure they have appropriate permissions.''
			, ''https://straightpathsql.com/check/contained-database''
			FROM sys.databases
			WHERE containment > 0;';

		INSERT #Results
		EXEC sp_executesql @SQL;

		END;

	/* database owned by Windows account */
	INSERT #Results
	SELECT 
		3
		, 346
		, 2
		, 'Database owned by Windows account'
		, 'The database [' + db_name(d.database_id) + '] is owned by the Windows account [' + sp.[name] + '].'
		, db_name(d.database_id)
		, 'Members of the db_owner role could execute queries in the context of this Windows account.'
		, 'We recommend databases be owned by disabled SQL logins with minimal permissions to prevent privilege escalation.'
		, 'https://straightpathsql.com/check/database-owner-is-not-preferred-owner'
	FROM sys.databases d
	INNER JOIN sys.server_principals sp
		ON d.owner_sid = sp.sid
	WHERE sp.[type] = 'U'
		AND d.source_database_id IS NULL; /* exclude snapshot databases */


	/* TRUSTWORTHY setting check */
	INSERT #Results
	SELECT 
		3
		, 308
		, 1
		, 'TRUSTWORTHY database owned by sysadmin'
		, 'A database with TRUSTWORTHY enabled is owned by a member of the sysadmin role.'
		, db_name(database_id)
		, 'The database ' + db_name(database_id) + ' has the TRUSTWORTHY setting enabled and is owned by a member of the sysadmin role.'
		, 'With TRUSTWORTHY setting enabled and a sysadmin database owner, any user can execute commands as a sysadmin.'
		, 'https://straightpathsql.com/check/trustworthy-database'
	FROM sys.databases
	WHERE database_id > 4
		AND is_trustworthy_on = 1
		AND IS_SRVROLEMEMBER ('sysadmin', SUSER_SNAME(owner_sid)) = 1;

	INSERT #Results
	SELECT 
		3
		, 332
		, 2
		, 'TRUSTWORTHY database'
		, 'A database has the TRUSTWORTHY configuration enabled.'
		, db_name(database_id)
		, 'The database ' + db_name(database_id) + ' has the TRUSTWORTHY setting enabled.'
		, 'With this setting ON, any code in the database is allowed to be "trusted" in usage outside the context of the database.'
		, 'https://straightpathsql.com/check/trustworthy-enabled'
	FROM sys.databases
	WHERE database_id > 4
		AND is_trustworthy_on = 1
		AND IS_SRVROLEMEMBER ('sysadmin', SUSER_SNAME(owner_sid)) = 0;


	/*
	Build one filtered list of databases for the per-database checks below.
	Only online, non-snapshot databases are included. Each check switches
	context with QUOTENAME instead of sp_MSforeachdb, which does an unquoted
	? substitution.
	*/
	IF OBJECT_ID('tempdb..#DatabaseList') IS NOT NULL
		DROP TABLE #DatabaseList;

	CREATE TABLE #DatabaseList (
		DatabaseID INT
		, DatabaseName sysname
		);

	INSERT #DatabaseList (DatabaseID, DatabaseName)
	SELECT
		database_id
		, [name]
	FROM master.sys.databases
	WHERE state = 0 /* online */
		AND source_database_id IS NULL; /* exclude snapshot databases */

	/*
	Remove non-readable availability group secondaries from the list. Entering
	one with USE raises error 976, which would abort the per-database cursors
	below. This mirrors the exclusion the public role cursor already applies.
	The availability group catalog views only exist on SQL Server 2012 and later,
	so guard on HADR being enabled (deferred name resolution keeps the procedure
	valid where the views are absent).
	*/
	IF SERVERPROPERTY('IsHadrEnabled') = 1
		DELETE #DatabaseList
		WHERE DatabaseName IN (
			SELECT adc.database_name
			FROM sys.availability_replicas AS ar
			INNER JOIN sys.availability_databases_cluster adc
				ON adc.group_id = ar.group_id
			WHERE ar.secondary_role_allow_connections = 0
				AND ar.replica_server_name = @@SERVERNAME
				AND sys.fn_hadr_is_primary_replica(adc.database_name) = 0
			);

	DECLARE @CurrentDBName VARCHAR(256);


	/* db_owner role member */
	DECLARE DbOwnerRoleCursor CURSOR LOCAL FAST_FORWARD FOR
		SELECT DatabaseName FROM #DatabaseList;

	OPEN DbOwnerRoleCursor;
	FETCH NEXT FROM DbOwnerRoleCursor INTO @CurrentDBName;

	WHILE @@FETCH_STATUS = 0 BEGIN
		SET @SQL = 'USE ' + QUOTENAME(@CurrentDBName) + ';
		SELECT 3, 333, 2
		, ''db_owner role member''
		, ''db_owner role member''
		, DB_NAME()
		, (''In ['' + DB_NAME() + ''], user ['' + u.name + '']  has the role ['' + g.name + ''].  This user can perform any function in this database including changing permissions for other users.'')
		, ''Verify these elevated database permissions are required for this user.''
		, ''https://straightpathsql.com/check/db_owner-role-members''
		FROM (SELECT memberuid = convert(int, member_principal_id), groupuid = convert(int, role_principal_id) FROM ' + QUOTENAME(@CurrentDBName) + '.sys.database_role_members) m inner join ' + QUOTENAME(@CurrentDBName) + '.dbo.sysusers u on m.memberuid = u.uid inner join sysusers g on m.groupuid = g.uid where u.name <> ''dbo'' and g.name in (''db_owner'') OPTION (RECOMPILE);';

		INSERT #Results
		EXECUTE sp_executesql @SQL;

		FETCH NEXT FROM DbOwnerRoleCursor INTO @CurrentDBName;
		END;

	CLOSE DbOwnerRoleCursor;
	DEALLOCATE DbOwnerRoleCursor;

	UPDATE #Results
	SET
		CheckID = 334
		, [Importance] = 1
		, Issue = 'db_owner role member - system databases'
		, CheckName = 'db_owner role member - system databases'
	WHERE CheckID = 333
	AND DatabaseName IN ('master','msdb');


	/* unusual database permissions */
	DECLARE UnusualPermsCursor CURSOR LOCAL FAST_FORWARD FOR
		SELECT DatabaseName FROM #DatabaseList;

	OPEN UnusualPermsCursor;
	FETCH NEXT FROM UnusualPermsCursor INTO @CurrentDBName;

	WHILE @@FETCH_STATUS = 0 BEGIN
		SET @SQL = 'USE ' + QUOTENAME(@CurrentDBName) + ';
		SELECT 3, 335, 2
		, ''Unusual database permissions''
		, ''Unusual database permissions''
		, DB_NAME()
		, (''In ['' + DB_NAME() + ''], user ['' + u.name + '']  has the role ['' + g.name + ''].  This is an unusual database role with elevated permissions, but it is redundant if this user is also in the db_owner role.'')
		, ''Verify these elevated database permissions are required for this user.''
		, ''https://straightpathsql.com/check/unusual-database-permissions''
		FROM (SELECT memberuid = convert(int, member_principal_id), groupuid = convert(int, role_principal_id) FROM ' + QUOTENAME(@CurrentDBName) + '.sys.database_role_members) m inner join ' + QUOTENAME(@CurrentDBName) + '.dbo.sysusers u on m.memberuid = u.uid inner join sysusers g on m.groupuid = g.uid where u.name <> ''dbo'' and g.name in (''db_accessadmin'' , ''db_securityadmin'' , ''db_ddladmin'') OPTION (RECOMPILE);';

		INSERT #Results
		EXECUTE sp_executesql @SQL;

		FETCH NEXT FROM UnusualPermsCursor INTO @CurrentDBName;
		END;

	CLOSE UnusualPermsCursor;
	DEALLOCATE UnusualPermsCursor;

	UPDATE #Results
	SET
		CheckID = 336
		, [Importance] = 1
		, Issue = 'Unusual database permissions - system databases'
		, CheckName = 'Unusual database permissions - system databases'
	WHERE CheckID = 335
	AND DatabaseName IN ('master','msdb');


	/* find roles within roles in each database */
	DECLARE RolesInRolesCursor CURSOR LOCAL FAST_FORWARD FOR
		SELECT DatabaseName FROM #DatabaseList;

	OPEN RolesInRolesCursor;
	FETCH NEXT FROM RolesInRolesCursor INTO @CurrentDBName;

	WHILE @@FETCH_STATUS = 0 BEGIN
		SET @SQL = '
		USE ' + QUOTENAME(@CurrentDBName) + '
		IF DB_Name() NOT IN (''tempdb'') BEGIN
		SELECT 3, 337, 3
		, ''Roles within roles''
		, ''Roles within roles''
		, db_name() as [DatabaseName]
		, ''The role ['' + user_name(roles.member_principal_id) + ''] is a member of the role ['' + user_name(roles.role_principal_id)
		 + '']. Including roles in other roles can lead to unintended privilege escalation.''
		, ''Remove ['' + user_name(roles.member_principal_id) + ''] from the role ['' + user_name(roles.role_principal_id) + ''] and explicitly assign it required permissions''
		, ''https://straightpathsql.com/check/database-roles-within-roles''
		FROM sys.database_role_members AS roles, sys.database_principals users
		WHERE roles.member_principal_id = users.principal_id
		AND user_name(roles.member_principal_id) <> ''RSExecRole''
		AND ( roles.role_principal_id >= 16384 AND roles.role_principal_id <= 16393)
		AND users.type = ''R''
		END';

		INSERT #Results
		EXECUTE sp_executesql @SQL;

		FETCH NEXT FROM RolesInRolesCursor INTO @CurrentDBName;
		END;

	CLOSE RolesInRolesCursor;
	DEALLOCATE RolesInRolesCursor;


	/* find orphan user in each database */
	DECLARE OrphanUserCursor CURSOR LOCAL FAST_FORWARD FOR
		SELECT DatabaseName FROM #DatabaseList;

	OPEN OrphanUserCursor;
	FETCH NEXT FROM OrphanUserCursor INTO @CurrentDBName;

	WHILE @@FETCH_STATUS = 0 BEGIN
		SET @SQL = '
		USE ' + QUOTENAME(@CurrentDBName) + '
		IF DB_Name() NOT IN (''tempdb'') BEGIN
		SELECT 3, 338, 3
		, ''Orphaned database user''
		, ''Orphaned database user''
		, db_name() as [DatabaseName]
		, ''The database user ['' + [NAME] + ''] is orphaned, meaning it has no corresponding login at the instance level.''
		, ''Reconnect the user to an existing login using sp_change_users_login, or drop the user.''
		, ''https://straightpathsql.com/check/orphaned-users''
		FROM sys.database_principals
		WHERE sid NOT IN (SELECT sid FROM sys.server_principals)
		AND type = ''S''
		AND principal_id != 2
		AND DATALENGTH(sid) <= 28'
		+ CASE
			WHEN @SQLVersionMajor >= 12 THEN ' AND authentication_type_desc = ''INSTANCE'''
			END
		+ ' END';

		INSERT #Results
		EXECUTE sp_executesql @SQL;

		FETCH NEXT FROM OrphanUserCursor INTO @CurrentDBName;
		END;

	CLOSE OrphanUserCursor;
	DEALLOCATE OrphanUserCursor;


	/* orphaned database users holding elevated permissions */
	DECLARE OrphanElevatedCursor CURSOR LOCAL FAST_FORWARD FOR
		SELECT DatabaseName FROM #DatabaseList;

	OPEN OrphanElevatedCursor;
	FETCH NEXT FROM OrphanElevatedCursor INTO @CurrentDBName;

	WHILE @@FETCH_STATUS = 0 BEGIN
		/* DB_ID() > 4 restricts this to user databases (skips master, tempdb, model, msdb) */
		SET @SQL = '
		USE ' + QUOTENAME(@CurrentDBName) + '
		IF DB_ID() > 4 BEGIN
		SELECT
			3
			, 355
			, 1
			, ''Orphaned database user with elevated permissions''
			, ''One or more database users have no matching server login and hold elevated permissions within the database.''
			, DB_NAME()
			, ''The user '' + QUOTENAME(dp.name) + '' in this database has no corresponding server login and holds '' + e.elevated + ''. If a login is later created with a matching SID, whoever controls that login inherits these permissions without any explicit grant being made.''
			, ''Determine whether the user is still needed. Drop the user if it is not, or remap it to the correct login with ALTER USER '' + QUOTENAME(dp.name) + '' WITH LOGIN = [login] if the login exists under a different SID.''
			, ''https://straightpathsql.com/check/orphaned-user-elevated-permissions''
		FROM sys.database_principals AS dp
		/* build the list of elevated role memberships and permissions as two separate FOR XML aggregations, because FOR XML cannot be applied directly to a UNION */
		CROSS APPLY (
			SELECT roles = STUFF((
				SELECT '', membership in the '' + r.name COLLATE DATABASE_DEFAULT + '' role''
				FROM sys.database_role_members AS drm
				INNER JOIN sys.database_principals AS r
					ON r.principal_id = drm.role_principal_id
				WHERE drm.member_principal_id = dp.principal_id
					AND r.name IN (''db_owner'', ''db_securityadmin'', ''db_accessadmin'', ''db_ddladmin'')
				FOR XML PATH('''')
			), 1, 2, '''')
		) rr
		CROSS APPLY (
			SELECT perms = STUFF((
				SELECT '', the '' + perm.permission_name COLLATE DATABASE_DEFAULT + '' permission''
				FROM sys.database_permissions AS perm
				WHERE perm.grantee_principal_id = dp.principal_id
					AND perm.state IN ( ''G'', ''W'' )
					AND perm.permission_name IN ( ''CONTROL'', ''ALTER ANY USER'', ''ALTER ANY ROLE'', ''IMPERSONATE'', ''TAKE OWNERSHIP'' )
				FOR XML PATH('''')
			), 1, 2, '''')
		) pp
		CROSS APPLY (
			SELECT elevated = CASE
				WHEN rr.roles IS NOT NULL AND pp.perms IS NOT NULL THEN rr.roles + '', '' + pp.perms
				ELSE COALESCE(rr.roles, pp.perms)
				END
		) e
		WHERE dp.type = ''S''
			AND dp.name NOT IN ( ''guest'', ''dbo'', ''INFORMATION_SCHEMA'', ''sys'' )
			AND dp.name NOT LIKE ''##%''
			AND NOT EXISTS (SELECT 1 FROM sys.server_principals AS sp WHERE sp.sid = dp.sid)'
		/* authentication_type exists on SQL Server 2012 and later; type 2 is a contained user, covered by CheckID 362 */
		+ CASE WHEN @SQLVersionMajor >= 11 THEN ' AND dp.authentication_type <> 2' ELSE '' END
		+ '
			AND e.elevated IS NOT NULL
		END';

		INSERT #Results
		EXECUTE sp_executesql @SQL;

		FETCH NEXT FROM OrphanElevatedCursor INTO @CurrentDBName;
		END;

	CLOSE OrphanElevatedCursor;
	DEALLOCATE OrphanElevatedCursor;


	/* database owner is different from owner in master */ -- has issues with mismatched collation
	DECLARE OwnerDiscrepancyCursor CURSOR LOCAL FAST_FORWARD FOR
		SELECT DatabaseName FROM #DatabaseList;

	OPEN OwnerDiscrepancyCursor;
	FETCH NEXT FROM OwnerDiscrepancyCursor INTO @CurrentDBName;

	WHILE @@FETCH_STATUS = 0 BEGIN
		SET @SQL = '
		USE ' + QUOTENAME(@CurrentDBName) + '
		IF DB_Name() NOT IN (''tempdb'') BEGIN
		SELECT 3, 306, 3
		, ''Database owner discrepancy''
		, ''Database owner discrepancy''
		, db_name() as [DatabaseName]
		, ''The database owner ['' + dbprs.name COLLATE SQL_Latin1_General_CP1_CI_AS + ''] is different than the owner listed in master ['' + ssp.name COLLATE SQL_Latin1_General_CP1_CI_AS + ''].''
		, ''Use ALTER AUTHORIZATION ON DATABASE to set the database owner to the correct login.''
		, ''https://straightpathsql.com/check/database-owner-is-unknown''
		FROM   sys.database_principals AS dbprs
		INNER JOIN sys.databases AS dbs
		 ON dbprs.sid != dbs.owner_sid
		JOIN sys.server_principals ssp
		 ON dbs.owner_sid = ssp.sid
		WHERE dbs.database_id = Db_id()
		AND dbprs.principal_id = 1
		AND dbs.state_desc = ''ONLINE''
		END';

		INSERT #Results
		EXECUTE sp_executesql @SQL;

		FETCH NEXT FROM OwnerDiscrepancyCursor INTO @CurrentDBName;
		END;

	CLOSE OwnerDiscrepancyCursor;
	DEALLOCATE OwnerDiscrepancyCursor;


	/* guest user has CONNECT permission */
	DECLARE GuestConnectCursor CURSOR LOCAL FAST_FORWARD FOR
		SELECT DatabaseName FROM #DatabaseList;

	OPEN GuestConnectCursor;
	FETCH NEXT FROM GuestConnectCursor INTO @CurrentDBName;

	WHILE @@FETCH_STATUS = 0 BEGIN
		/* master, msdb, and tempdb grant guest CONNECT by default and require it; model is checked because enabling guest there propagates to every database created afterward */
		SET @SQL = '
		USE ' + QUOTENAME(@CurrentDBName) + '
		IF DB_NAME() NOT IN (''master'', ''msdb'', ''tempdb'') BEGIN
		SELECT 3, 361, 2
		, ''Guest user has CONNECT permission''
		, ''The guest user has CONNECT permission in one or more databases, allowing any login on the instance to access them without an explicit grant.''
		, DB_NAME()
		, ''The guest user has CONNECT permission in this database, so any login can enter it and use whatever permissions are granted to the public role, without appearing as a database user.''
		, ''Revoke access with REVOKE CONNECT FROM guest in this database unless an application specifically depends on it.''
		, ''https://straightpathsql.com/check/guest-user-connect''
		FROM sys.database_permissions AS perm
		INNER JOIN sys.database_principals AS prin
			ON perm.grantee_principal_id = prin.principal_id
		WHERE prin.name = ''guest''
			AND perm.permission_name = ''CONNECT''
			AND perm.class = 0
			AND perm.state IN (''G'', ''W'')
		END';

		INSERT #Results
		EXECUTE sp_executesql @SQL;

		FETCH NEXT FROM GuestConnectCursor INTO @CurrentDBName;
		END;

	CLOSE GuestConnectCursor;
	DEALLOCATE GuestConnectCursor;


	/* contained database users (SQL Server 2012 and later; contained databases do not exist on earlier versions, so the check is not applicable there) */
	IF @SQLVersionMajor >= 11 BEGIN
		DECLARE ContainedUserCursor CURSOR LOCAL FAST_FORWARD FOR
			SELECT DatabaseName FROM #DatabaseList;

		OPEN ContainedUserCursor;
		FETCH NEXT FROM ContainedUserCursor INTO @CurrentDBName;

		WHILE @@FETCH_STATUS = 0 BEGIN
			/* DB_ID() > 4 skips the system databases (master, tempdb, model, msdb) */
			SET @SQL = '
			USE ' + QUOTENAME(@CurrentDBName) + '
			IF DB_ID() > 4 BEGIN
			SELECT 3, 362, 2
			, ''Contained database users''
			, ''One or more databases have contained users that authenticate directly against the database, bypassing server-level login controls.''
			, DB_NAME()
			, ''This database has '' + CONVERT(VARCHAR(20), x.cnt) + '' contained users. These users connect without a corresponding server login, so they do not appear in sys.server_principals and are not subject to server-level auditing, login triggers, or password policy managed at the instance level.''
			, ''Confirm that contained users are intentional and required, typically for Availability Group portability or Azure SQL Database compatibility.''
			, ''https://straightpathsql.com/check/contained-database-users''
			FROM (
				SELECT COUNT(*) AS cnt
				FROM sys.database_principals
				WHERE authentication_type IN (2) /* 2 = DATABASE (contained user with its own password) */
					AND name NOT LIKE ''##%''
				) x
			WHERE x.cnt > 0
			END';

			INSERT #Results
			EXECUTE sp_executesql @SQL;

			FETCH NEXT FROM ContainedUserCursor INTO @CurrentDBName;
			END;

		CLOSE ContainedUserCursor;
		DEALLOCATE ContainedUserCursor;
	END;


	/* application roles */
	DECLARE AppRoleCursor CURSOR LOCAL FAST_FORWARD FOR
		SELECT DatabaseName FROM #DatabaseList;

	OPEN AppRoleCursor;
	FETCH NEXT FROM AppRoleCursor INTO @CurrentDBName;

	WHILE @@FETCH_STATUS = 0 BEGIN
		/* DB_ID() > 4 skips the system databases (master, tempdb, model, msdb) */
		SET @SQL = '
		USE ' + QUOTENAME(@CurrentDBName) + '
		IF DB_ID() > 4 BEGIN
		DECLARE @AppRoleList nvarchar(max);

		SELECT @AppRoleList = COALESCE(@AppRoleList + '', '', '''') + QUOTENAME(name)
		FROM sys.database_principals
		WHERE type = ''A'' /* application role */
		ORDER BY name;

		IF @AppRoleList IS NOT NULL
		SELECT 3, 363, 2
		, ''Application roles detected''
		, ''One or more databases contain application roles, which activate with a password and replace the connected user''''s permissions for the rest of the session.''
		, DB_NAME()
		, ''This database contains the application role(s) '' + @AppRoleList + ''. An application role is activated with sp_setapprole using a password that must be stored somewhere the application can read it, such as a configuration file or connection string. Once activated, the session operates with the role''''s permissions and the original user identity is no longer available for auditing.''
		, ''Confirm the application role is still in use and review what permissions it holds, along with where its password is stored and whether it has ever been changed. Where possible, replace application roles with module signing or EXECUTE AS, which do not require a shared password.''
		, ''https://straightpathsql.com/check/application-roles''
		END';

		INSERT #Results
		EXECUTE sp_executesql @SQL;

		FETCH NEXT FROM AppRoleCursor INTO @CurrentDBName;
		END;

	CLOSE AppRoleCursor;
	DEALLOCATE AppRoleCursor;


	/* unsigned CLR assemblies with an elevated permission set in databases that provide an escalation path */
	DECLARE UnsignedAssemblyCursor CURSOR LOCAL FAST_FORWARD FOR
		SELECT DatabaseName FROM #DatabaseList;

	OPEN UnsignedAssemblyCursor;
	FETCH NEXT FROM UnsignedAssemblyCursor INTO @CurrentDBName;

	WHILE @@FETCH_STATUS = 0 BEGIN
		/* DB_ID() > 4 restricts this to user databases (skips master, tempdb, model, msdb) */
		SET @SQL = '
		USE ' + QUOTENAME(@CurrentDBName) + '
		IF DB_ID() > 4 BEGIN
		SELECT
			3
			, 371
			, 1
			, ''Unsigned assembly with elevated permission set''
			, ''One or more unsigned CLR assemblies with an elevated permission set exist in a database that allows escalation to the server security context.''
			, DB_NAME()
			, ''The assembly '' + QUOTENAME(a.name) + '' has a permission set of '' + CASE a.permission_set WHEN 2 THEN ''EXTERNAL_ACCESS'' WHEN 3 THEN ''UNSAFE'' END + '' and is not signed with a certificate or asymmetric key. This database is '' + esc.reason + '', which allows code running in the database to execute in the server security context. Together these mean the assembly can reach outside SQL Server and acquire sysadmin privileges.''
			, ''Sign the assembly with a certificate or asymmetric key that has a corresponding login granted UNSAFE ASSEMBLY, then turn off TRUSTWORTHY or change the database owner to a login that is not a sysadmin. Module signing grants the assembly the permissions it needs without extending trust to everything in the database.''
			, ''https://straightpathsql.com/check/unsigned-assembly-trustworthy''
		FROM sys.assemblies AS a
		/* the escalation path is a database-level fact, evaluated once for the current database */
		CROSS APPLY (
			SELECT reason = CASE
				WHEN d.is_trustworthy_on = 1 AND EXISTS (SELECT 1 FROM sys.server_principals AS sp WHERE sp.sid = d.owner_sid AND IS_SRVROLEMEMBER(''sysadmin'', sp.name) = 1) THEN ''TRUSTWORTHY and owned by a sysadmin''
				WHEN d.is_trustworthy_on = 1 THEN ''TRUSTWORTHY''
				WHEN EXISTS (SELECT 1 FROM sys.server_principals AS sp WHERE sp.sid = d.owner_sid AND IS_SRVROLEMEMBER(''sysadmin'', sp.name) = 1) THEN ''owned by a sysadmin''
				ELSE NULL
				END
			FROM sys.databases AS d
			WHERE d.database_id = DB_ID()
		) esc
		WHERE a.permission_set IN (2, 3) /* 2 = EXTERNAL_ACCESS, 3 = UNSAFE */
			AND a.is_user_defined = 1 /* excludes the Microsoft-supplied assemblies present in every database */
			AND NOT EXISTS (SELECT 1 FROM sys.crypt_properties AS cp WHERE cp.class = 5 AND cp.major_id = a.assembly_id) /* class 5 = assembly signature; absence means unsigned */
			AND esc.reason IS NOT NULL
		END';

		INSERT #Results
		EXECUTE sp_executesql @SQL;

		FETCH NEXT FROM UnsignedAssemblyCursor INTO @CurrentDBName;
		END;

	CLOSE UnsignedAssemblyCursor;
	DEALLOCATE UnsignedAssemblyCursor;


	/* Always Encrypted column master keys stored on the SQL Server host (SQL Server 2016 and later; sys.column_master_keys does not exist on earlier versions) */
	IF @SQLVersionMajor >= 13 BEGIN
		DECLARE ColumnMasterKeyCursor CURSOR LOCAL FAST_FORWARD FOR
			SELECT DatabaseName FROM #DatabaseList;

		OPEN ColumnMasterKeyCursor;
		FETCH NEXT FROM ColumnMasterKeyCursor INTO @CurrentDBName;

		WHILE @@FETCH_STATUS = 0 BEGIN
			/* DB_ID() > 4 restricts this to user databases (skips master, tempdb, model, msdb) */
			SET @SQL = '
			USE ' + QUOTENAME(@CurrentDBName) + '
			IF DB_ID() > 4 BEGIN
			SELECT
				3
				, 378
				, 1
				, ''Always Encrypted column master key on database server''
				, ''An Always Encrypted column master key is stored in the local machine certificate store on the SQL Server host.''
				, DB_NAME()
				, ''The column master key '' + QUOTENAME(name) + '' uses the certificate store provider with the path '' + key_path COLLATE DATABASE_DEFAULT + ''. Storing the column master key in the local machine store on the database server places the encrypted data and the key that unlocks it on the same host, so anyone with administrative access to this server can decrypt the protected columns.''
				, ''Move the column master key to a store the database server cannot reach, such as Azure Key Vault, a hardware security module, or a certificate store on the application servers that need it. Rotate the key after moving it, since it should be considered exposed while it has been accessible from the database host.''
				, ''https://straightpathsql.com/check/always-encrypted-key-location''
			FROM sys.column_master_keys
			/* MSSQL_CERTIFICATE_STORE with a LocalMachine/ path is on the database server; CurrentUser/ paths and the external providers (AZURE_KEY_VAULT, MSSQL_CNG_STORE, MSSQL_CSP_PROVIDER) are not flagged */
			WHERE key_store_provider_name = ''MSSQL_CERTIFICATE_STORE''
				AND key_path LIKE ''LocalMachine/%''
			END';

			INSERT #Results
			EXECUTE sp_executesql @SQL;

			FETCH NEXT FROM ColumnMasterKeyCursor INTO @CurrentDBName;
			END;

		CLOSE ColumnMasterKeyCursor;
		DEALLOCATE ColumnMasterKeyCursor;
	END;


	/* explicit permissions granted to the Public role */
	IF @SQLVersionMajor >= 12 BEGIN
		DECLARE @DB_Name VARCHAR(256) 

		DECLARE public_cursor CURSOR FOR
			SELECT name 
			FROM master.sys.databases
			WHERE database_id > 4 
				AND state = 0
				AND source_database_id IS NULL /* exclude snapshot databases */
				AND [name] NOT IN (
					SELECT adc.database_name
					FROM sys.availability_replicas AS ar
				   JOIN sys.availability_databases_cluster adc ON adc.group_id = ar.group_id
					WHERE ar.secondary_role_allow_connections = 0
				   AND ar.replica_server_name = @@SERVERNAME
				   AND sys.fn_hadr_is_primary_replica(adc.database_name) = 0 
					)

		OPEN public_cursor 
		FETCH NEXT FROM public_cursor INTO @DB_Name 

		WHILE @@FETCH_STATUS = 0 
		BEGIN 

		SET @SQL = 'USE ' + QUOTENAME(@DB_Name) + '; ' +
		'SELECT 3, 339, 2
		, ''Public permissions''
		, ''Permissions for the public role''
		, db_name() as [DatabaseName]
		, ''The [public] role has been granted the permission ['' + per.permission_name + ''] on the object [''
		+ CASE
		WHEN per.class = 0 THEN db_name()
		WHEN per.class = 3 THEN schema_name(major_id)
		WHEN per.class = 4 THEN printarget.NAME
		WHEN per.class = 5 THEN asm.NAME
		WHEN per.class = 6 THEN type_name(major_id)
		WHEN per.class = 10 THEN xmlsc.NAME
		WHEN per.class = 15 THEN msgt.NAME COLLATE DATABASE_DEFAULT
		WHEN per.class = 16 THEN svcc.NAME COLLATE DATABASE_DEFAULT
		WHEN per.class = 17 THEN svcs.NAME COLLATE DATABASE_DEFAULT
		WHEN per.class = 18 THEN rsb.NAME COLLATE DATABASE_DEFAULT
		WHEN per.class = 19 THEN rts.NAME COLLATE DATABASE_DEFAULT
		WHEN per.class = 23 THEN ftc.NAME
		WHEN per.class = 24 THEN sym.NAME
		WHEN per.class = 25 THEN crt.NAME
		WHEN per.class = 26 THEN asym.NAME
		END + ''].''
		, ''Because these permissions are available to anyone who can connect to your instance, they should be revoked and granted to users, groups, or roles other than public.''
		, ''https://straightpathsql.com/check/explicit-permissions-for-public''
		FROM sys.database_permissions AS per
		LEFT JOIN sys.database_principals AS prin ON per.grantee_principal_id = prin.principal_id
		LEFT JOIN sys.assemblies AS asm ON per.major_id = asm.assembly_id
		LEFT JOIN sys.xml_schema_collections AS xmlsc ON per.major_id = xmlsc.xml_collection_id
		LEFT JOIN sys.service_message_types AS msgt ON per.major_id = msgt.message_type_id
		LEFT JOIN sys.service_contracts AS svcc ON per.major_id = svcc.service_contract_id
		LEFT JOIN sys.services AS svcs ON per.major_id = svcs.service_id
		LEFT JOIN sys.remote_service_bindings AS rsb ON per.major_id = rsb.remote_service_binding_id
		LEFT JOIN sys.routes AS rts ON per.major_id = rts.route_id
		LEFT JOIN sys.database_principals AS printarget ON per.major_id = printarget.principal_id
		LEFT JOIN sys.symmetric_keys AS sym ON per.major_id = sym.symmetric_key_id
		LEFT JOIN sys.asymmetric_keys AS asym ON per.major_id = asym.asymmetric_key_id
		LEFT JOIN sys.certificates AS crt ON per.major_id = crt.certificate_id
		LEFT JOIN sys.fulltext_catalogs AS ftc ON per.major_id = ftc.fulltext_catalog_id
		WHERE per.grantee_principal_id = DATABASE_PRINCIPAL_ID(''public'')
			AND class != 1 -- Object or Columns (class = 1) are handled by VA1054 and have different remediation syntax
			AND [state] IN (''G'',''W'')
			AND NOT (
				per.class = 0
				AND prin.NAME = ''public''
				AND per.major_id = 0
				AND per.minor_id = 0
				AND permission_name IN (
					''VIEW ANY COLUMN ENCRYPTION KEY DEFINITION''
					,''VIEW ANY COLUMN MASTER KEY DEFINITION''
					)
				)';
		
			INSERT #Results
			EXEC sp_executesql @SQL ;

			/* iterate the cursor to the next database name */
			FETCH NEXT FROM public_cursor INTO @DB_Name;
		END 
		CLOSE public_cursor;
		DEALLOCATE public_cursor;
		END;

	END;

/* results */
IF @Mode = 1 /* instance information only */
	SELECT
		[Importance]
        , CheckName
        , Issue
        , DatabaseName
        , Details
        , ActionStep
        , ReadMoreURL
		, CheckID
    FROM #Results
    WHERE CategoryID = 1
    ORDER BY
        CheckID;


IF @Mode = 2
	SELECT
		[Importance]
        , CheckName
        , Issue
        , DatabaseName
        , Details
        , ActionStep
        , ReadMoreURL
		, CheckID
    FROM #Results
    WHERE [Importance] = 1
    ORDER BY
        [Importance]
		, CheckName
        , DatabaseName
        , Details;


IF @Mode = 0
	SELECT
		[Importance]
        , CheckName
        , Issue
        , DatabaseName
        , Details
        , ActionStep
        , ReadMoreURL
		, CheckID
    FROM #Results
    WHERE CategoryID <> 1
    ORDER BY
        [Importance]
		, CheckName
        , DatabaseName
        , Details;

  IF @Mode = 99
  BEGIN
	/* instance information only */
	SELECT
		[Importance]
        , CheckName
        , Issue
        , DatabaseName
        , Details
        , ActionStep
        , ReadMoreURL
		, CheckID
    FROM #Results
    WHERE CategoryID = 1
    ORDER BY
        CheckID;

	/* all discovered vulnerabilities */
	SELECT
		[Importance]
        , CheckName
        , Issue
        , DatabaseName
        , Details
        , ActionStep
        , ReadMoreURL
		, CheckID
    FROM #Results
    WHERE CategoryID <> 1
    ORDER BY
        [Importance]
		, CheckName
        , DatabaseName
        , Details;
  END;
GO
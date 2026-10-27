GO
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('dbo.sp_CheckActivity') IS NULL
  EXEC ('CREATE PROCEDURE dbo.sp_CheckActivity AS RETURN 0;');
GO
ALTER PROCEDURE [dbo].[sp_CheckActivity]
  @Account NVARCHAR(128) = NULL
, @SessionID NVARCHAR(200) = NULL
, @Plans BIT = 0
, @FilterSleeping TINYINT = 1
, @ShowTopProc BIT = 0
, @TableName NVARCHAR(256) = NULL -- Must be fully qualified (DB.Schema.Table)
, @Help BIT = 0
, @Raw BIT = 0
, @ShowProgress BIT = 0
, @ShowBlocking BIT = 0
, @VersionCheck BIT = 0
  
AS

SET NOCOUNT ON ; 

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

BEGIN TRY

    DECLARE @SQL NVARCHAR(MAX), @ErrorMessage NVARCHAR(2048), @CaptureDT DATETIME2(0) = GETDATE() ;
    DECLARE @Version VARCHAR(10) = NULL, @VersionDate DATE = NULL, @VerDATEDIFF NVARCHAR(40), @VerDOP NVARCHAR(100) ;
    DECLARE @SQLVersion NVARCHAR(128), @SQLVersionMajor DECIMAL(10,2), @SQLVersionMinor DECIMAL(10,2), @BRD NVARCHAR(1000);
    DECLARE @FmtorRaw1 NVARCHAR(2000),@FmtorRaw2 NVARCHAR(2000),@FmtorRaw3 NVARCHAR(2000),@FmtorRaw4 NVARCHAR(2000),@FmtorRaw5 NVARCHAR(2000) ;
 
    SET @Version = '2026.10.1' ;
    SET @VersionDate = '20261019';

    /* Version check  */
    IF @VersionCheck = 1 
    BEGIN

        SELECT @Version AS VersionNumber, @VersionDate AS [VersionDate] ;

        RETURN;
    END;  

    /* SQL Server version */
    SELECT @SQLVersion = CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)),
        @SQLVersionMajor = SUBSTRING(@SQLVersion, 1,CHARINDEX('.', @SQLVersion) + 1 )
        , @SQLVersionMinor = PARSENAME(CONVERT(varchar(32), @SQLVersion), 2);



    /* @Help = 1 */
    IF @Help = 1 
    BEGIN
	    PRINT '
        /*
            sp_CheckActivity from https://straightpathsql.com/

	        Version: ' + @Version + ' updated ' + CONVERT(VARCHAR(10), @VersionDate, 101) + '
    	
            This stored procedure shows a snapshot of the current activity in the SQL Server 
            instance allowing for some filtering and the ability to populate a table with
            the results.
    
            Known limitations of this version:
            - sp_CheckActivity only works with versions of SQL Server 2012 and later however 
                some data is not avalaible prior to 2016 and are replaced with NULL values on older versions
    
            Parameters:

            @Account         The account used to Login to SQL Server (Domain\User). Returns all requests for this account
            @SessionID       A specific SPID or comma delimited list of SPIDs you wish to report on
                             If more than 1 SPID is passed in it must be in a string form
            @Plans           1 = Include the query plan for the currently running statement
            @FilterSleeping  0 = Do not show any sleeping sessions, 1 = Show sleeping w Open Trans, 2 = Show all non-system sessions 
            @ShowTopProc     1 = Shows the top most procedure when procedure calls are nested
            @TableName       The name of the table to insert the results into ([DB Name].[schema].[Table Name])
            @Help            1 = Prints out the help for this procedure
            @Raw             1 = Specifies that no formatting is done to the output otherwise some numeric columns are 
                                 converted to character and formatted for readability and alignment
            @ShowProgress    1 = Show the estimated completion time for any BRD (Backup, Restore or DBCC) command. Filters all else out
            @ShowBlocking    1 = Shows any sessions that are blocking or being blocked including the lead blocker
            @VersionCheck    1 = Return the current version of this procedure

            MIT License
    	
            All copyrights for sp_CheckActivity are held by Straight Path Solutions.
    
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

	/* check for unsupported version */	
    IF @SQLVersionMajor < 11 
    BEGIN
	    PRINT '
        /*
            *** Unsupported SQL Server Version ***

            sp_CheckActivity is supported only for execution on SQL Server 2012 and later.

	        For more information about the limitations of sp_CheckActivity, execute
            using @Help = 1

            *** EXECUTION ABORTED ***
    	   
        */';
	    RETURN;
	END; 


    --  Reject if some common potential injection characters are passed in.
    IF @Account IS NOT NULL
    BEGIN
        IF @Account LIKE N'%;%' OR @Account LIKE N'%=%' OR @Account LIKE N'%''''%' OR @Account LIKE N'%"%' OR @Account LIKE N'%[_][_]%' OR @Account LIKE N'%*%' OR @Account LIKE N'%UNION%' OR @Account LIKE N'%EXEC %' OR @Account LIKE N'%EXECUTE %'
        BEGIN
            SET @ErrorMessage = N'Please specify a valid account name.' ;
            THROW 51000, @ErrorMessage,1 ;
        END ;
    END ;

    -- Check the table name if specified to be sure it exists
    IF @TableName IS NOT NULL
    BEGIN
        SET @TableName = REPLACE(REPLACE(@TableName,'[',''),']','')

        IF (@TableName LIKE N'%;%' OR @TableName LIKE N'%=%' OR @TableName LIKE N'%''''%' OR @TableName LIKE N'%"%' OR @TableName LIKE N'%[_][_]%' OR @TableName LIKE N'%*%' OR @TableName LIKE N'%UNION%' OR @TableName LIKE N'%EXEC %' OR @TableName LIKE N'%EXECUTE %')
        BEGIN
            SET @ErrorMessage = N'The table name specified is not in the format ([DB].[Schema].[Table]) or (DB.Schema.Table).' ;
            THROW 51000, @ErrorMessage,1 ;
        END ;
    END ;

    -- This is needed to run on SQL2012 and SQL2014 since these features were only introduced in SQL2016
    IF @SQLVersionMajor > 12 
    BEGIN
        SET @VerDATEDIFF = 'DATEDIFF_BIG' ;
        SET @VerDOP = 'r.dop AS [DOP], r.parallel_worker_count AS [Workers],' ;
    END 
    ELSE
    BEGIN
        SET @VerDATEDIFF = 'DATEDIFF' ;
        SET @VerDOP = 'NULL AS [DOP], NULL AS [Workers],' ;
    END ;

    -- If the table name is specified check to be sure it exists. If not then create it
    IF @TableName IS NOT NULL
    BEGIN

        DECLARE @DBPart NVARCHAR(128),@SchemaPart NVARCHAR(128), @TablePart NVARCHAR(128)
        DECLARE @Pos1 INT, @Pos2 INT, @FQDNName NVARCHAR(256) ;

        SET @Pos1 = CHARINDEX('.',@TableName) ;
        SET @Pos2 = CHARINDEX('.',@TableName,@Pos1 + 1) ;

        SET @DBPart = SUBSTRING(@TableName,1,@Pos1 -1)
        SET @SchemaPart = SUBSTRING(@TableName,@Pos1 + 1,@Pos2 - @Pos1 - 1)
        SET @TablePart = SUBSTRING(@TableName,@Pos2 + 1, LEN(@TableName) - (@Pos2 ) )

        SET @FQDNName = QUOTENAME(@DBPart) + '.' + QUOTENAME(@SchemaPart) + '.' +QUOTENAME(@TablePart) ;

        IF OBJECT_ID(@FQDNName,N'U') IS NULL 
        BEGIN

            DECLARE @CreateTableSQL NVARCHAR(4000) ;

            SET @CreateTableSQL = N'
            CREATE TABLE <*FQDN*>(
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
            ' ;

            SET @CreateTableSQL = REPLACE(@CreateTableSQL,'<*FQDN*>',@FQDNName) ;

            EXEC(@CreateTableSQL) ;

            SET @CreateTableSQL = N'
            CREATE CLUSTERED INDEX CIX_<*table*>__CaptureDT
            ON <*FQDN*>([CaptureDT])
            WITH (DATA_COMPRESSION = PAGE) ; ' ;

            SET @CreateTableSQL = REPLACE(@CreateTableSQL,'<*table*>',@TablePart) ;
            SET @CreateTableSQL = REPLACE(@CreateTableSQL,'<*FQDN*>',@FQDNName) ;

            EXEC(@CreateTableSQL) ;

        END ;
    END ;


    IF @Raw = 0
    BEGIN
        SET @FmtorRaw1 = N' 
        CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), ISNULL(r.cpu_time,s.cpu_time)))) OVER() - LEN(CONVERT(NVARCHAR(40), ISNULL(r.cpu_time,s.cpu_time)))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, ISNULL(r.cpu_time,s.cpu_time)), 1), 19)) AS [CPU ms],
        CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), ISNULL(r.logical_reads,s.logical_reads)))) OVER() - LEN(CONVERT(NVARCHAR(40), ISNULL(r.logical_reads,s.logical_reads)))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, ISNULL(r.logical_reads,s.logical_reads)), 1), 19)) AS [Logical Reads],
        CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), ISNULL(r.writes,s.writes)))) OVER() - LEN(CONVERT(NVARCHAR(40), ISNULL(r.writes,s.writes)))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, ISNULL(r.writes,s.writes)), 1), 19)) AS [Writes],
        '  ;

        SET @FmtorRaw2 = N'
        CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), r.wait_time))) OVER() - LEN(CONVERT(NVARCHAR(40), r.wait_time))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, r.wait_time), 1), 19)) AS [Wait ms],
        CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), ISNULL(tdb.[C Tempdb GB],0)))) OVER() - LEN(CONVERT(NVARCHAR(40), ISNULL(tdb.[C Tempdb GB],0)))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, ISNULL(tdb.[C Tempdb GB],0)), 2), 19)) AS [C Tempdb GB],
        CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), ISNULL(tdb.[H Tempdb GB],0)))) OVER() - LEN(CONVERT(NVARCHAR(40), ISNULL(tdb.[H Tempdb GB],0)))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, ISNULL(tdb.[H Tempdb GB],0)), 2), 19)) AS [H Tempdb GB],
        ' ;
        SET @FmtorRaw3 = N'
        CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), ISNULL(r.row_count,s.row_count)))) OVER() - LEN(CONVERT(NVARCHAR(40), ISNULL(r.row_count,s.row_count)))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, ISNULL(r.row_count,s.row_count)), 1), 19)) AS [Row Count], ' ;

        SET @FmtorRaw4 = N'
        CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), CAST(r.granted_query_memory / 128.0 AS DECIMAL(10,2))))) OVER() - LEN(CONVERT(NVARCHAR(40), CAST(r.granted_query_memory / 128.0 AS DECIMAL(10,2))))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY,CAST(r.granted_query_memory / 128.0 AS DECIMAL(10,2))), 1), 19)) AS [Memory Grant MB],
        ' ;
    END 
    ELSE
    BEGIN
        SET @FmtorRaw1 = N'
            ISNULL(r.cpu_time,s.cpu_time) AS [CPU ms], 
            ISNULL(r.logical_reads,s.logical_reads) AS [Logical Reads], ISNULL(r.writes,s.writes) AS [Writes], ' ; 

        SET @FmtorRaw2 = N'
            r.wait_time AS [Wait ms], 
            ISNULL(tdb.[C Tempdb GB],0) AS [C Tempdb GB], ISNULL(tdb.[H Tempdb GB],0) AS [H Tempdb GB],' ;

        SET @FmtorRaw3 = N'
            ISNULL(r.row_count,s.row_count) AS [Row Count], ' ;

        SET @FmtorRaw4 = N'
            CAST(r.granted_query_memory / 128.0 AS DECIMAL(10,2)) AS [Memory Grant MB], ' ;
    END ;



IF @ShowBlocking = 1
BEGIN

    IF @Raw = 0
    BEGIN

    WITH cte_LeadBlockers
    AS (

    SELECT b.blocking_session_id, r2.blocking_session_id AS [x] FROM (
        SELECT DISTINCT r1.blocking_session_id
        FROM sys.dm_exec_requests AS r1
        WHERE r1.blocking_session_id <> 0
                    ) AS b
    LEFT JOIN sys.dm_exec_requests AS r2 ON b.blocking_session_id = r2.[session_id]
    WHERE r2.blocking_session_id IS NULL OR r2.blocking_session_id = 0
        )


    SELECT 'Lead Blocker' AS [Block Type], s.[session_id] AS [SessionID], r.[blocking_session_id] AS [BlockingID]
        ,RIGHT('00' + CONVERT(VARCHAR(5),DATEDIFF_BIG(MI,CASE WHEN s.last_request_end_time >= s.last_request_start_time THEN s.last_request_end_time ELSE s.last_request_start_time END,GETDATE()) / 60) + 
            RIGHT(CONVERT(CHAR(8),DATEADD(ss,DATEDIFF_BIG(ss,CASE WHEN s.last_request_end_time >= s.last_request_start_time THEN s.last_request_end_time ELSE s.last_request_start_time END,GETDATE()),CONVERT(DATETIME,CONVERT(DATE,getdate()))),108),6),9) AS [hhh:mm:ss] 
        ,r.[command] AS [Command]
        ,ISNULL(r.[status], s.[status]) AS [Status],  CASE WHEN ISNULL(r.[status], s.[status]) = 'sleeping' AND ISNULL(r.[open_transaction_count],s.[open_transaction_count]) > 0 THEN '- open tran -' ELSE r.wait_type END  AS [Wait Type]
        ,CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), r.wait_time))) OVER() - LEN(CONVERT(NVARCHAR(40), r.wait_time))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, r.wait_time), 1), 19)) AS [Wait ms]
        ,r.[last_wait_type] AS [Last Wait Type]
        ,ISNULL(r.[open_transaction_count],s.[open_transaction_count]) AS [Tran Count]
        ,CASE s.[transaction_isolation_level] WHEN 0 THEN 'Unspecified' WHEN 1 THEN 'ReadUncommitted' WHEN 2 THEN 'ReadCommitted' WHEN 3 THEN 'RepeatableRead' WHEN 4 THEN 'Serializable' WHEN 5 THEN 'Snapshot' ELSE 'Unknow' END AS [ISO Level]
        ,TRY_CONVERT(XML,CONVERT(NVARCHAR(MAX),'<?query --' + CHAR(13) + CHAR(10) + ISNULL(SUBSTRING(t.[text], (r.[statement_start_offset]/2) + 1,
                 ((CASE r.[statement_end_offset] WHEN -1 THEN DATALENGTH(t.[text]) ELSE r.[statement_end_offset] END - r.[statement_start_offset])/2) + 1),d.event_info) + CHAR(13) + CHAR(10) + '--?>')) AS [Executed Statement] 
        ,TRY_CONVERT(XML,CONVERT(NVARCHAR(MAX),'<?query --'+CHAR(13)+CHAR(10) + ISNULL(t.[text],d.[event_info]) + CHAR(13)+CHAR(10) + '--?>')) AS [Batch or Procedure] 
        ,CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), ISNULL(r.cpu_time,s.cpu_time)))) OVER() - LEN(CONVERT(NVARCHAR(40), ISNULL(r.cpu_time,s.cpu_time)))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, ISNULL(r.cpu_time,s.cpu_time)), 1), 19)) AS [CPU ms]
        ,CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), ISNULL(r.logical_reads,s.logical_reads)))) OVER() - LEN(CONVERT(NVARCHAR(40), ISNULL(r.logical_reads,s.logical_reads)))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, ISNULL(r.logical_reads,s.logical_reads)), 1), 19)) AS [Logical Reads]
        ,CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), ISNULL(r.writes,s.writes)))) OVER() - LEN(CONVERT(NVARCHAR(40), ISNULL(r.writes,s.writes)))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, ISNULL(r.writes,s.writes)), 1), 19)) AS [Writes]
        ,s.[host_name] AS [Host Name],s.[login_name] AS [Login Name],DB_NAME(s.[database_id]) AS [DB Name],s.[program_name] AS [Program Name]
    FROM sys.dm_exec_sessions AS s INNER JOIN cte_LeadBlockers AS l ON s.[session_id] = l.[blocking_session_id]
        LEFT JOIN sys.dm_exec_requests AS r ON l.blocking_session_id =  r.[session_id]
        OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
        OUTER APPLY sys.dm_exec_input_buffer(s.[session_id],null) AS d

    UNION ALL

    SELECT 'Blocked' AS [Block Type], s.[session_id] AS [SessionID], r.[blocking_session_id] AS [BlockingID]
        ,RIGHT('00' + CONVERT(VARCHAR(5),DATEDIFF_BIG(MI,CASE WHEN s.last_request_end_time >= s.last_request_start_time THEN s.last_request_end_time ELSE s.last_request_start_time END,GETDATE()) / 60) + 
            RIGHT(CONVERT(CHAR(8),DATEADD(ss,DATEDIFF_BIG(ss,CASE WHEN s.last_request_end_time >= s.last_request_start_time THEN s.last_request_end_time ELSE s.last_request_start_time END,GETDATE()),CONVERT(DATETIME,CONVERT(DATE,getdate()))),108),6),9) AS [hhh:mm:ss] 
        ,r.[command] AS [Command]
        ,ISNULL(r.[status], s.[status]) AS [Status],  CASE WHEN ISNULL(r.[status], s.[status]) = 'sleeping' AND ISNULL(r.[open_transaction_count],s.[open_transaction_count]) > 0 THEN '- open tran -' ELSE r.wait_type END  AS [Wait Type]
        ,CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), r.wait_time))) OVER() - LEN(CONVERT(NVARCHAR(40), r.wait_time))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, r.wait_time), 1), 19)) AS [Wait ms]
        ,r.[last_wait_type] AS [Last Wait Type]
        ,ISNULL(r.[open_transaction_count],s.[open_transaction_count]) AS [Tran Count]
        ,CASE s.[transaction_isolation_level] WHEN 0 THEN 'Unspecified' WHEN 1 THEN 'ReadUncommitted' WHEN 2 THEN 'ReadCommitted' WHEN 3 THEN 'RepeatableRead' WHEN 4 THEN 'Serializable' WHEN 5 THEN 'Snapshot' ELSE 'Unknow' END AS [ISO Level]
        ,TRY_CONVERT(XML,CONVERT(NVARCHAR(MAX),'<?query --' + CHAR(13) + CHAR(10) + ISNULL(SUBSTRING(t.[text], (r.[statement_start_offset]/2) + 1,
                 ((CASE r.[statement_end_offset] WHEN -1 THEN DATALENGTH(t.[text]) ELSE r.[statement_end_offset] END - r.[statement_start_offset])/2) + 1),d.event_info) + CHAR(13) + CHAR(10) + '--?>')) AS [Executed Statement] 
        ,TRY_CONVERT(XML,CONVERT(NVARCHAR(MAX),'<?query --'+CHAR(13)+CHAR(10) + ISNULL(t.[text],d.[event_info]) + CHAR(13)+CHAR(10) + '--?>')) AS [Batch or Procedure] 
        ,CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), ISNULL(r.cpu_time,s.cpu_time)))) OVER() - LEN(CONVERT(NVARCHAR(40), ISNULL(r.cpu_time,s.cpu_time)))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, ISNULL(r.cpu_time,s.cpu_time)), 1), 19)) AS [CPU ms]
        ,CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), ISNULL(r.logical_reads,s.logical_reads)))) OVER() - LEN(CONVERT(NVARCHAR(40), ISNULL(r.logical_reads,s.logical_reads)))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, ISNULL(r.logical_reads,s.logical_reads)), 1), 19)) AS [Logical Reads]
        ,CONVERT(NVARCHAR(40), SPACE(MAX(LEN(CONVERT(NVARCHAR(40), ISNULL(r.writes,s.writes)))) OVER() - LEN(CONVERT(NVARCHAR(40), ISNULL(r.writes,s.writes)))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, ISNULL(r.writes,s.writes)), 1), 19)) AS [Writes]
        ,s.[host_name] AS [Host Name],s.[login_name] AS [Login Name],DB_NAME(s.[database_id]) AS [DB Name],s.[program_name] AS [Program Name]
    FROM sys.dm_exec_requests AS r INNER JOIN sys.dm_exec_sessions AS s ON s.[session_id] = r.[session_id]
        OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
        OUTER APPLY sys.dm_exec_input_buffer(s.[session_id],null) AS d
    WHERE r.blocking_session_id <> 0 AND r.[session_id] NOT IN (SELECT blocking_session_id FROM cte_LeadBlockers AS lb)
        ORDER BY [Block Type] DESC, s.[session_id] ;

    END 
    ELSE
    BEGIN
        -- Get the lead blocker spids
        ;
        WITH cte_LeadBlockers
        AS
        (SELECT r2.[session_id] 
                FROM sys.dm_exec_requests AS r2
        WHERE r2.[session_id] IN (
                SELECT DISTINCT r1.blocking_session_id
                FROM sys.dm_exec_requests AS r1
                WHERE r1.blocking_session_id <> 0
        )
        AND r2.blocking_session_id = 0
        )

        SELECT 'Lead Blocker' AS [Block Type], r.[session_id] AS [SessionID], r.[blocking_session_id] AS [BlockingID]
        ,RIGHT('00' + CONVERT(VARCHAR(5),DATEDIFF_BIG(MI,CASE WHEN s.last_request_end_time >= s.last_request_start_time THEN s.last_request_end_time ELSE s.last_request_start_time END,GETDATE()) / 60) + 
            RIGHT(CONVERT(CHAR(8),DATEADD(ss,DATEDIFF_BIG(ss,CASE WHEN s.last_request_end_time >= s.last_request_start_time THEN s.last_request_end_time ELSE s.last_request_start_time END,GETDATE()),CONVERT(DATETIME,CONVERT(DATE,getdate()))),108),6),9) AS [hhh:mm:ss] 
            ,r.[command] AS [Command]
            ,ISNULL(r.[status], s.[status]) AS [Status],  CASE WHEN ISNULL(r.[status], s.[status]) = 'sleeping' AND s.open_transaction_count > 0 THEN '- open tran -' ELSE r.wait_type END  AS [Wait Type]
            ,r.wait_time AS [Wait ms]
            ,r.[last_wait_type] AS [Last Wait Type]
            ,r.[open_transaction_count] AS [Tran Count]
            ,CASE s.[transaction_isolation_level] WHEN 0 THEN 'Unspecified' WHEN 1 THEN 'ReadUncommitted' WHEN 2 THEN 'ReadCommitted' WHEN 3 THEN 'RepeatableRead' WHEN 4 THEN 'Serializable' WHEN 5 THEN 'Snapshot' ELSE 'Unknow' END AS [ISO Level]
            ,TRY_CONVERT(XML,CONVERT(NVARCHAR(MAX),'<?query --' + CHAR(13) + CHAR(10) + ISNULL(SUBSTRING(t.[text], (r.[statement_start_offset]/2) + 1,
                     ((CASE r.[statement_end_offset] WHEN -1 THEN DATALENGTH(t.[text]) ELSE r.[statement_end_offset] END - r.[statement_start_offset])/2) + 1),d.event_info) + CHAR(13) + CHAR(10) + '--?>')) AS [Executed Statement] 
            ,TRY_CONVERT(XML,CONVERT(NVARCHAR(MAX),'<?query --'+CHAR(13)+CHAR(10) + ISNULL(t.[text],d.[event_info]) + CHAR(13)+CHAR(10) + '--?>')) AS [Batch or Procedure] 
            ,r.cpu_time,s.cpu_time AS [CPU ms]
            ,r.logical_reads AS [Logical Reads]
            ,s.writes AS [Writes]
            ,s.[host_name] AS [Host Name],s.[login_name] AS [Login Name],DB_NAME(r.[database_id]) AS [DB Name],s.[program_name] AS [Program Name]
        FROM cte_LeadBlockers AS l INNER JOIN sys.dm_exec_requests AS r ON l.[session_id] =  r.[session_id]
        INNER JOIN sys.dm_exec_sessions AS s ON s.[session_id] = r.[session_id]
        CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
            OUTER APPLY sys.dm_exec_input_buffer(s.[session_id],null) AS d
        UNION ALL
        SELECT 'Blocked' AS [Block Type], r.[session_id] AS [SessionID], r.[blocking_session_id] AS [BlockingID]
        ,RIGHT('00' + CONVERT(VARCHAR(5),DATEDIFF_BIG(MI,CASE WHEN s.last_request_end_time >= s.last_request_start_time THEN s.last_request_end_time ELSE s.last_request_start_time END,GETDATE()) / 60) + 
            RIGHT(CONVERT(CHAR(8),DATEADD(ss,DATEDIFF_BIG(ss,CASE WHEN s.last_request_end_time >= s.last_request_start_time THEN s.last_request_end_time ELSE s.last_request_start_time END,GETDATE()),CONVERT(DATETIME,CONVERT(DATE,getdate()))),108),6),9) AS [hhh:mm:ss] 
            ,r.[command] AS [Command]
            ,ISNULL(r.[status], s.[status]) AS [Status],  CASE WHEN ISNULL(r.[status], s.[status]) = 'sleeping' AND s.open_transaction_count > 0 THEN '- open tran -' ELSE r.wait_type END  AS [Wait Type]
            ,r.wait_time AS [Wait ms]
            ,r.[last_wait_type] AS [Last Wait Type]
            ,r.[open_transaction_count] AS [Tran Count]
            ,CASE s.[transaction_isolation_level] WHEN 0 THEN 'Unspecified' WHEN 1 THEN 'ReadUncommitted' WHEN 2 THEN 'ReadCommitted' WHEN 3 THEN 'RepeatableRead' WHEN 4 THEN 'Serializable' WHEN 5 THEN 'Snapshot' ELSE 'Unknow' END AS [ISO Level]
            ,TRY_CONVERT(XML,CONVERT(NVARCHAR(MAX),'<?query --' + CHAR(13) + CHAR(10) + ISNULL(SUBSTRING(t.[text], (r.[statement_start_offset]/2) + 1,
                     ((CASE r.[statement_end_offset] WHEN -1 THEN DATALENGTH(t.[text]) ELSE r.[statement_end_offset] END - r.[statement_start_offset])/2) + 1),d.event_info) + CHAR(13) + CHAR(10) + '--?>')) AS [Executed Statement] 
            ,TRY_CONVERT(XML,CONVERT(NVARCHAR(MAX),'<?query --'+CHAR(13)+CHAR(10) + ISNULL(t.[text],d.[event_info]) + CHAR(13)+CHAR(10) + '--?>')) AS [Batch or Procedure] 
            ,r.cpu_time,s.cpu_time AS [CPU ms]
            ,r.logical_reads AS [Logical Reads]
            ,s.writes AS [Writes]
            ,s.[host_name] AS [Host Name],s.[login_name] AS [Login Name],DB_NAME(r.[database_id]) AS [DB Name],s.[program_name] AS [Program Name]
        FROM sys.dm_exec_requests AS r INNER JOIN sys.dm_exec_sessions AS s ON s.[session_id] = r.[session_id]
            CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
            OUTER APPLY sys.dm_exec_input_buffer(s.[session_id],null) AS d
        WHERE r.blocking_session_id <> 0 AND r.[session_id] NOT IN (SELECT session_id FROM cte_LeadBlockers AS lb)
            ORDER BY [Block Type] DESC, r.[session_id] ;

    END ;

END ;  -- END ShowBlocking

ELSE

BEGIN  -- Main non-blocking code

    IF @ShowProgress = 1
    BEGIN
        SET @BRD = ' r.[start_time] AS [StartTime]
        ,CASE r.[percent_complete] WHEN 0 THEN ''UNDETERMINED'' ELSE CONVERT(VARCHAR(8), DATEADD(SECOND, r.[estimated_completion_time] / 1000, 0), 108) END AS [Est Compl Time]
        ,CONVERT(DECIMAL(5,2),r.[percent_complete]) AS [% Complete], 

 ' ;
    END 
    ELSE
    BEGIN
        SET @BRD = N'' ;
    END ;

    SET @SQL = CASE WHEN @TableName IS NULL THEN N'' ELSE N'INSERT INTO ' + @TableName + N' 
    ' END ;

    SET @SQL = @SQL + 
    N'SELECT 
        RIGHT(''00'' + CONVERT(VARCHAR(5),<#VerDATEDIFF#>(MI,CASE WHEN s.last_request_end_time >= s.last_request_start_time THEN s.last_request_end_time ELSE s.last_request_start_time END,GETDATE()) / 60) + 
                RIGHT(CONVERT(CHAR(8),DATEADD(ss,<#VerDATEDIFF#>(ss,CASE WHEN s.last_request_end_time >= s.last_request_start_time THEN s.last_request_end_time ELSE s.last_request_start_time END,GETDATE()),CONVERT(DATETIME,CONVERT(DATE,getdate()))),108),6),9) AS [hhh:mm:ss] ,
        s.[session_id] AS [SessionID], ' + @BRD +
        'TRY_CONVERT(XML,CONVERT(NVARCHAR(MAX),''<?query --''+CHAR(13)+CHAR(10) + 	ISNULL(SUBSTRING(t.[text], (r.[statement_start_offset]/2) + 1,
                                ((CASE r.[statement_end_offset] WHEN -1 THEN DATALENGTH(t.[text]) ELSE r.[statement_end_offset] END - r.[statement_start_offset])/2) + 1),d.event_info)
            + CHAR(13)+CHAR(10)+''--?>'')) AS [Executed Statement] ,
        TRY_CONVERT(XML,CONVERT(NVARCHAR(MAX),''<?query --''+CHAR(13)+CHAR(10) + ISNULL(t.[text],d.[event_info]) + CHAR(13)+CHAR(10)+''--?>'')) AS [Batch or Procedure] ,
        ' + CASE WHEN @Plans = 1 THEN N'      TRY_CONVERT(XML,qp.query_plan) AS [Query Plan] ' ELSE ' NULL AS [Query Plan] ' END + ', ISNULL(r.blocking_session_id,0) AS [Blocking ID],' +
        @FmtorRaw1 + 
        ' ISNULL(r.[status], s.[status]) AS [Status],  CASE WHEN ISNULL(r.[status], s.[status]) = ''sleeping'' AND s.open_transaction_count > 0 THEN ''- open tran -'' ELSE r.wait_type END  AS [Wait Type], '
            +
        @FmtorRaw2 +
        N'CONVERT(DECIMAL(5,2),percent_complete) AS [% Complete], 
        DB_NAME(s.database_id) AS [DB Name], s.[program_name] AS [Program Name], s.login_name AS [Login Name], s.[host_name] AS [Host Name], '
            +
        @FmtorRaw3 +
        N'
        s.open_transaction_count AS [Tran Count],
        <#VerDOP#> '
        +
        @FmtorRaw4 +
        N'CASE s.transaction_isolation_level WHEN 0 THEN ''Unspecified'' WHEN 1 THEN ''ReadUncommitted'' WHEN 2 THEN ''ReadCommitted'' WHEN 3 THEN ''RepeatableRead'' WHEN 4 THEN ''Serializable'' WHEN 5 THEN ''Snapshot'' ELSE ''Unknow'' END AS [ISO Level], 
        GETDATE() AS [CaptureDT],
        CONVERT(DECIMAL(10,1),<#VerDATEDIFF#>(SS,s.login_time,GETDATE()) / 60.0) AS [Login Mins],
        s.login_time AS [Login DT],
        ' + CASE WHEN @ShowTopProc = 1 THEN ' LEFT(ISNULL(i.[event_info],''''),500)  AS [Top Procedure] ' ELSE N' NULL AS [Top Procedure]' END + N'
    FROM sys.dm_exec_sessions AS s LEFT JOIN sys.dm_exec_requests AS r ON s.[session_id] = r.[session_id]
        LEFT JOIN #TempdbSpace AS tdb ON s.[session_id] = tdb.[session_id]
        OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
        OUTER APPLY sys.dm_exec_input_buffer(s.[session_id],null) AS d
        ' + CASE WHEN @ShowTopProc = 1 THEN 'OUTER APPLY sys.dm_exec_input_buffer(s.[session_id],0) AS i ' ELSE N'' END 
        + CASE WHEN @Plans IS NOT NULL THEN N'    OUTER APPLY sys.dm_exec_text_query_plan  (r.plan_handle,r.statement_start_offset,r.statement_end_offset) AS qp ' ELSE N'' END +
        + CASE WHEN @Account IS NOT NULL THEN 
            N'WHERE s.is_user_process = 1  AND s.login_name = N''' + @Account + N''''
        ELSE N'        WHERE s.is_user_process = 1  
    ' END + CASE WHEN @ShowProgress = 0 THEN N'' ELSE N' AND (UPPER(r.[command]) LIKE ''%BACKUP%''  OR UPPER(r.[command]) LIKE ''%RESTOR%'' OR UPPER(r.[command]) LIKE ''%RECOVERY%'' OR UPPER(r.[command]) LIKE ''%ROLLBACK%'' OR UPPER(r.[command]) LIKE ''%TDE ENCRYPTION%'' OR UPPER(r.[command]) LIKE ''%REORGANIZE%'' OR UPPER(r.[command]) LIKE ''%DBCC%'')' END +
    CASE @FilterSleeping WHEN 0 THEN N' AND s.status <> ''sleeping''' WHEN 1 THEN N' AND (s.open_transaction_count > 0 OR r.[session_id] IS NOT NULL )' WHEN 2 THEN N'' END +
    CASE WHEN @SessionID IS NULL THEN '' ELSE N' AND s.[session_id] IN (' + @SessionID + ') ' END +
    N'      AND s.login_name NOT IN (''NT AUTHORITY\SYSTEM'') AND s.[session_id] <> @@SPID
            ORDER BY <#VerDATEDIFF#>(ss,CASE WHEN s.last_request_end_time >= s.last_request_start_time THEN s.last_request_end_time ELSE s.last_request_start_time END,GETDATE()) DESC, s.[session_id] DESC ; ' ;

    -- Make it version compatable
    SET @SQL = REPLACE(@SQL,'<#VerDATEDIFF#>',@VerDATEDIFF) ;
    SET @SQL = REPLACE(@SQL,'<#VerDOP#>',@VerDOP) ;


    --  Get the tempdb usage first
    WITH CTE_Current AS
    (
    SELECT TOP (35)  * FROM (
       SELECT session_id AS [Session ID],  
          CAST((SUM(user_objects_alloc_page_count) -
          SUM(user_objects_dealloc_page_count)) / 131072.0 AS DECIMAL(10,2)) 
        + CAST((SUM(internal_objects_alloc_page_count) -
          SUM(internal_objects_dealloc_page_count)) / 131072.0 AS DECIMAL(10,2)) AS [Current GB]
	    FROM tempdb.sys.dm_db_task_space_usage 
		    GROUP BY [session_id]
		    HAVING (SUM(internal_objects_alloc_page_count) - SUM(internal_objects_dealloc_page_count) > 0)
			    OR (SUM(user_objects_alloc_page_count) - SUM(user_objects_dealloc_page_count) > 0)) AS [SessionCounts]
    ORDER BY [Current GB] DESC 
    ),

    CTE_Historical AS
    (
    SELECT TOP (100) 
        session_id AS [Session ID], 
              CAST((user_objects_alloc_page_count/131072.0) AS DECIMAL(10,2)) - CAST(((user_objects_dealloc_page_count + user_objects_deferred_dealloc_page_count) /131072.0) AS DECIMAL(10,2)) AS [Current User Space GB],
              CAST((user_objects_alloc_page_count/131072.0) AS DECIMAL(10,2)) + CAST((internal_objects_alloc_page_count/131072.0) AS DECIMAL(10,2)) AS [Allocated GB]
    FROM tempdb.sys.dm_db_session_space_usage AS su
    ORDER BY ((user_objects_alloc_page_count - (user_objects_dealloc_page_count + user_objects_deferred_dealloc_page_count)) + (internal_objects_alloc_page_count - internal_objects_dealloc_page_count)) DESC )

    SELECT ISNULL(c.[Session ID], h.[Session ID]) AS [session_id], ISNULL(c.[Current GB],0) + ISNULL(h.[Current User Space GB],0) AS [C Tempdb GB], ISNULL(h.[Allocated GB],0) AS [H Tempdb GB]
    INTO #TempdbSpace
    FROM CTE_Current AS c FULL OUTER JOIN CTE_Historical AS h ON c.[Session ID] = h.[Session ID]
    ;

    EXEC sp_executesql @SQL ;

END ;

END TRY
BEGIN CATCH

    THROW ;

END CATCH ;

GO


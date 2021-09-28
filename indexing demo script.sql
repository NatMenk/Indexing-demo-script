USE AdventureWorks2019 
GO
--create a "heap" table copy of person.Person (no clustered index defined)
CREATE TABLE [Person].[People](
	[BusinessEntityID] [int] NOT NULL,
	[PersonType] [nchar](2) NOT NULL,
	[NameStyle] [dbo].[NameStyle] NOT NULL,
	[Title] [nvarchar](8) NULL,
	[FirstName] [dbo].[Name] NOT NULL,
	[MiddleName] [dbo].[Name] NULL,
	[LastName] [dbo].[Name] NOT NULL,
	[Suffix] [nvarchar](10) NULL )

--load all the people from person.person into the new table
INSERT INTO Person.People 
SELECT BusinessEntityID, PersonType, NameStyle, Title, FirstName
	,MiddleName, LastName, Suffix
FROM Person.Person --19972

SELECT * FROM Person.People WHERE BusinessEntityID = 10000
SELECT * FROM Person.People WHERE LastName = 'Smith'

--query shows the data page breakdown of a table
SELECT t.NAME AS TableName,
    p.rows AS RowCounts,
    SUM(a.total_pages) AS TotalPages, 
    SUM(a.used_pages) AS UsedPages, 
    (SUM(a.total_pages) - SUM(a.used_pages)) AS UnusedPages
FROM sys.tables t
INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE 
    t.NAME = 'People' AND t.is_ms_shipped = 0 AND i.OBJECT_ID > 255 
GROUP BY t.Name, p.Rows
ORDER BY t.Name

---------------------------------------------------------------------------------------
--clustered index

--create 2 copies of the SalesOrderDetail table
SELECT * INTO SalesOrderDetail_index FROM Sales.SalesOrderDetail
SELECT * INTO SalesOrderDetail_noindex FROM Sales.SalesOrderDetail

--create a clustered index on the first table
CREATE CLUSTERED INDEX IX_SalesOrderDetail_index_SalesOrderID
	ON dbo.SalesOrderDetail_index (SalesOrderID ASC) --ascending order is default DESC = descending order

SET STATISTICS IO ON --input/output (disk) related information
SET STATISTICS TIME ON --time related stats

SET STATISTICS IO OFF --input/output (disk) related information
SET STATISTICS TIME OFF --time related stats

--check if index makes a difference in scenario where no column specifics and no WHERE
SELECT * FROM SalesOrderDetail_index WHERE SalesOrderID = 43671
SELECT * FROM SalesOrderDetail_noindex WHERE SalesOrderID = 43671

--this lists the number of data pages in the database that the tables are consuming
SELECT  OBJECT_SCHEMA_NAME(s.object_id) schema_name,
        OBJECT_NAME(s.object_id) table_name,
        SUM(s.used_page_count) used_pages,
        SUM(s.reserved_page_count) reserved_pages
FROM    sys.dm_db_partition_stats s JOIN    sys.tables t ON s.object_id = t.object_id
GROUP BY s.object_id
ORDER BY schema_name, table_name

-----------------------------------------------------------------------------------
--non-clustered indexes
SELECT * FROM SalesOrderDetail_index WHERE ProductID = 755
SELECT * FROM SalesOrderDetail_noindex WHERE ProductID = 755

CREATE NONCLUSTERED INDEX IX_SalesOrderID_ProductID
	ON dbo.SalesOrderDetail_index (ProductID)

	--rerun the queries with the NCI in place
SELECT * FROM SalesOrderDetail_index WHERE ProductID = 755
SELECT * FROM SalesOrderDetail_noindex WHERE ProductID = 755

--what about this?
SELECT * FROM SalesOrderDetail_index WHERE ProductID = 755 AND OrderQty = 1
SELECT * FROM SalesOrderDetail_noindex WHERE ProductID = 755 AND OrderQty = 1

--another NCI example using a different set of data
--heap table + non-clustered index
SELECT * INTO dbo.Person_index FROM Person.Person
SELECT * INTO dbo.Person_noindex FROM Person.Person

SELECT * FROM dbo.Person_index WHERE LastName = 'Price'
SELECT * FROM dbo.Person_noindex WHERE LastName = 'Price'

--create a non-clustered index on LastName
CREATE NONCLUSTERED INDEX IX_Person_LastName
ON dbo.Person_index (LastName)

--rerun the queries
SELECT * FROM dbo.Person_index WHERE LastName = 'Price'
SELECT * FROM dbo.Person_noindex WHERE LastName = 'Price'

SELECT * FROM Person_index WHERE LastName = 'Price' AND FirstName = 'Paige'
SELECT * FROM Person_noindex WHERE LastName = 'Price' AND FirstName = 'Paige'

--create a composite non-clustered index on LastName and FirstName
CREATE NONCLUSTERED INDEX IX_Person_LastNameFirstName_ix
ON dbo.Person_index (LastName, FirstName)

--rerun with the composite index in place
SELECT * FROM Person_index WHERE LastName = 'Price' AND FirstName = 'Paige'
SELECT * FROM Person_noindex WHERE LastName = 'Price' AND FirstName = 'Paige'

--create a non-clustered index that can be crafted to improve specific queries being executed on the data
SELECT ProductID, CarrierTrackingNumber, UnitPrice, ModifiedDate
FROM SalesOrderDetail_index WHERE ProductID = 755 AND OrderQty = 1

SELECT ProductID, CarrierTrackingNumber, UnitPrice, ModifiedDate
FROM SalesOrderDetail_noindex WHERE ProductID = 755 AND OrderQty = 1

--create a covering index
CREATE NONCLUSTERED INDEX IX_SalesOrderDetail_ProductIDQuantity
ON dbo.SalesOrderDetail_index (ProductID, OrderQty)
INCLUDE (CarrierTrackingNumber, UnitPrice, ModifiedDate)

--rerun the same queries with the covering index in place
SELECT ProductID, CarrierTrackingNumber, UnitPrice, ModifiedDate
FROM SalesOrderDetail_index WHERE ProductID = 755 AND OrderQty = 1

SELECT ProductID, CarrierTrackingNumber, UnitPrice, ModifiedDate
FROM SalesOrderDetail_noindex WHERE ProductID = 755 AND OrderQty = 1

--index maintenance
--internal fragmention 

SELECT IX.Name AS [Name],
	PS.index_level AS [Level],
	PS.page_count AS Pages,
	PS.avg_page_space_used_in_percent AS 'Page Fullness (%)'
FROM sys.dm_db_index_physical_stats (DB_ID(), OBJECT_ID('Sales.SalesOrderDetail'), 
		DEFAULT, DEFAULT, 'DETAILED') PS
	JOIN sys.indexes AS IX ON IX.object_id = PS.object_id AND IX.index_id = PS.index_id 

--external fragmentation
SELECT IX.Name AS [Name],
	PS.index_level AS [Level],
	PS.page_count AS Pages,
	PS.avg_fragmentation_in_percent AS 'External Fragmentation (%)',
	PS.fragment_count AS 'Fragments',
	PS.avg_fragment_size_in_pages AS 'Avg Fragment Size'
FROM sys.dm_db_index_physical_stats (DB_ID(), OBJECT_ID('Sales.SalesOrderDetail'), 
		DEFAULT, DEFAULT, 'DETAILED') PS
	JOIN sys.indexes AS IX ON IX.object_id = PS.object_id AND IX.index_id = PS.index_id 

--if an index is fragmented between 5%-30%, MS recommends and INDEX REORGANIZE
--if an index is fragmented greater than 30%, MS recommends and INDEX REBUILD

--reorganize
ALTER INDEX ALL /* index name */ ON Sales.SalesOrderDetail REORGANIZE

--rebuild
ALTER INDEX ALL /* index name */ ON Sales.SalesOrderDetail REBUILD

------------------------------------------------------------------------
--fillfactor demo
CREATE TABLE dbo.RandomValue70(num INT IDENTITY, i CHAR(36), j CHAR(36));
INSERT INTO dbo.RandomValue70 (i, j) SELECT TOP 100000 NEWID(), NEWID() FROM sys.all_columns CROSS JOIN sys.columns;
CREATE UNIQUE CLUSTERED INDEX PK_RandomValue70 ON dbo.RandomValue70(i) WITH (FILLFACTOR=70, PAD_INDEX=ON)
GO
CREATE TABLE dbo.RandomValue80(num INT IDENTITY, i CHAR(36), j CHAR(36));
INSERT INTO dbo.RandomValue80 (i, j) SELECT i, j FROM dbo.RandomValue70;
CREATE UNIQUE CLUSTERED INDEX PK_RandomValue80 ON dbo.RandomValue80(i) WITH (FILLFACTOR=80, PAD_INDEX=ON)
GO
CREATE TABLE dbo.RandomValue90(num INT IDENTITY, i CHAR(36), j CHAR(36));
INSERT INTO dbo.RandomValue90 (i, j) SELECT i, j FROM dbo.RandomValue70;
CREATE UNIQUE CLUSTERED INDEX PK_RandomValue90 ON dbo.RandomValue90(i) WITH (FILLFACTOR=90, PAD_INDEX=ON)
GO 
CREATE TABLE dbo.RandomValue99(num INT IDENTITY, i CHAR(36), j CHAR(36));
INSERT INTO dbo.RandomValue99 (i, j) SELECT i, j FROM dbo.RandomValue70;
CREATE UNIQUE CLUSTERED INDEX PK_RandomValue99 ON dbo.RandomValue99(i) WITH (FILLFACTOR=99, PAD_INDEX=ON)

SELECT
  tbl.name TableName
, idx.name IndexName, idx.fill_factor
, CAST(Fragmentation.avg_page_space_used_in_percent AS DECIMAL(4,1)) ActualFillFactor
, CAST(Fragmentation.avg_fragmentation_in_percent AS DECIMAL(4,1)) CurrentFragmentation
FROM
  sys.tables tbl
    INNER JOIN
  sys.indexes idx ON tbl.object_id = idx.object_id
    CROSS APPLY
  sys.dm_db_index_physical_stats(DB_ID(), tbl.object_id, idx.index_id, 0, 'SAMPLED') Fragmentation
WHERE 
  tbl.name LIKE 'RandomValue[0-9]%';	

SET STATISTICS IO ON;
SET NOCOUNT ON;
SELECT COUNT(*) FROM dbo.RandomValue70 WHERE i BETWEEN '001' AND '199';
SELECT COUNT(*) FROM dbo.RandomValue80 WHERE i BETWEEN '001' AND '199';
SELECT COUNT(*) FROM dbo.RandomValue90 WHERE i BETWEEN '001' AND '199';
SELECT COUNT(*) FROM dbo.RandomValue99 WHERE i BETWEEN '001' AND '199';	


--insert 5000 random records into the table
INSERT INTO dbo.RandomValue70 (i, j) SELECT TOP 5000 NEWID(), NEWID() FROM dbo.RandomValue70;
INSERT INTO dbo.RandomValue80 (i, j) SELECT i, j FROM dbo.RandomValue70 WHERE num > 100000;
INSERT INTO dbo.RandomValue90 (i, j) SELECT i, j FROM dbo.RandomValue70 WHERE num > 100000;
INSERT INTO dbo.RandomValue99 (i, j) SELECT i, j FROM dbo.RandomValue70 WHERE num > 100000;	

--recheck the fragmentation levels
SELECT
  tbl.name TableName
, idx.name IndexName, idx.fill_factor
, CAST(Fragmentation.avg_page_space_used_in_percent AS DECIMAL(4,1)) ActualFillFactor
, CAST(Fragmentation.avg_fragmentation_in_percent AS DECIMAL(4,1)) CurrentFragmentation
FROM
  sys.tables tbl
    INNER JOIN
  sys.indexes idx ON tbl.object_id = idx.object_id
    CROSS APPLY
  sys.dm_db_index_physical_stats(DB_ID(), tbl.object_id, idx.index_id, 0, 'SAMPLED') Fragmentation
WHERE 
  tbl.name LIKE 'RandomValue[0-9]%';
  
  --update some records
  DECLARE @Mod INT, @Remainder INT;
SELECT @Mod = 15, @Remainder = 2;
UPDATE dbo.RandomValue70 SET i = NEWID() WHERE num % @Mod = @Remainder;
UPDATE R80 SET i = R70.i FROM dbo.RandomValue80 R80 INNER JOIN dbo.RandomValue70 R70 ON R80.num = R70.num WHERE R70.num % @Mod = @Remainder;
UPDATE R90 SET i = R70.i FROM dbo.RandomValue90 R90 INNER JOIN dbo.RandomValue70 R70 ON R90.num = R70.num WHERE R70.num % @Mod = @Remainder;
UPDATE R99 SET i = R70.i FROM dbo.RandomValue99 R99 INNER JOIN dbo.RandomValue70 R70 ON R99.num = R70.num WHERE R70.num % @Mod = @Remainder;

--recheck the frag
SELECT
  tbl.name TableName
, idx.name IndexName, idx.fill_factor
, CAST(Fragmentation.avg_page_space_used_in_percent AS DECIMAL(4,1)) ActualFillFactor
, CAST(Fragmentation.avg_fragmentation_in_percent AS DECIMAL(4,1)) CurrentFragmentation
FROM
  sys.tables tbl
    INNER JOIN
  sys.indexes idx ON tbl.object_id = idx.object_id
    CROSS APPLY
  sys.dm_db_index_physical_stats(DB_ID(), tbl.object_id, idx.index_id, 0, 'SAMPLED') Fragmentation
WHERE 
  tbl.name LIKE 'RandomValue[0-9]%';	

--update some records again
  DECLARE @Mod INT, @Remainder INT;
SELECT @Mod = 11, @Remainder = 2;
UPDATE dbo.RandomValue70 SET i = NEWID() WHERE num % @Mod = @Remainder;
UPDATE R80 SET i = R70.i FROM dbo.RandomValue80 R80 INNER JOIN dbo.RandomValue70 R70 ON R80.num = R70.num WHERE R70.num % @Mod = @Remainder;
UPDATE R90 SET i = R70.i FROM dbo.RandomValue90 R90 INNER JOIN dbo.RandomValue70 R70 ON R90.num = R70.num WHERE R70.num % @Mod = @Remainder;
UPDATE R99 SET i = R70.i FROM dbo.RandomValue99 R99 INNER JOIN dbo.RandomValue70 R70 ON R99.num = R70.num WHERE R70.num % @Mod = @Remainder;

--recheck the frag
SELECT
  tbl.name TableName
, idx.name IndexName, idx.fill_factor
, CAST(Fragmentation.avg_page_space_used_in_percent AS DECIMAL(4,1)) ActualFillFactor
, CAST(Fragmentation.avg_fragmentation_in_percent AS DECIMAL(4,1)) CurrentFragmentation
FROM
  sys.tables tbl
    INNER JOIN
  sys.indexes idx ON tbl.object_id = idx.object_id
    CROSS APPLY
  sys.dm_db_index_physical_stats(DB_ID(), tbl.object_id, idx.index_id, 0, 'SAMPLED') Fragmentation
WHERE 
  tbl.name LIKE 'RandomValue[0-9]%';







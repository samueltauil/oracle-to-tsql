---
applyTo: "tsql-output/**"
---

# T-SQL Output File Instructions

When working with files in the `tsql-output/` directory, these are **converted T-SQL files** generated from Oracle SQL source files.

## Context

- Each file here corresponds to a source file in `oracle-sql/` with the same relative path and name
- These files should be valid T-SQL targeting Microsoft SQL Server 2019+ (or as specified)
- They should preserve the original business logic while using T-SQL idioms

## T-SQL Output Standards

### File Header
Every converted file must start with a header block:

```sql
/*
 * Source: oracle-sql/<original_filename>.sql
 * Converted: <date>
 * Description: <brief description of what this object does>
 * Migration Notes: <any critical notes about behavioral differences>
 */
```

### Stored Procedures and Functions

```sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[procedure_name]
    @param1 NVARCHAR(100),
    @param2 INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- Converted logic here
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
```

### Tables

```sql
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[table_name]') AND type = N'U')
BEGIN
    CREATE TABLE [dbo].[table_name] (
        -- columns
    );
END;
GO
```

## Migration Notes Format

Use inline comments for migration annotations:

```sql
-- MIGRATION NOTE: Oracle NVL replaced with COALESCE for ANSI compliance
-- MIGRATION NOTE: CONNECT BY hierarchy replaced with recursive CTE
-- MIGRATION NOTE: Autonomous transaction simulated with separate connection pattern
-- MIGRATION WARNING: Oracle DECODE with NULL comparison - behavior may differ, verify logic
-- MIGRATION TODO: Oracle DBMS_OUTPUT calls converted to PRINT - review if logging framework needed
```

## Quality Requirements

- Must compile without errors on SQL Server 2019+
- Must use schema-qualified names (`[dbo].[object_name]`)
- Must include `GO` batch separators between DDL statements
- Must use `SET NOCOUNT ON` in all procedures
- Must use `BEGIN TRY/CATCH` for error handling
- Must preserve original business logic semantics
- Must not use deprecated T-SQL features (`SET ROWCOUNT`, `*=` joins, etc.)

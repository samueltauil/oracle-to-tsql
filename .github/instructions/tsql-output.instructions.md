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

## Schema Qualification Rules

All object references must be fully qualified using the following mapping. If a table/function is already fully qualified, leave it unchanged.

| Object Type | Condition | Qualified Schema |
|-------------|-----------|------------------|
| Table | Name contains `CHIRPS` or `TIPPS` | `[CHSTObjects].[CHIRPS_TIPPS]` |
| Table | Name begins with `SF_` | `[CHSTObjects].[PHOA]` |
| Table | Name begins with `PIECES_` | `[CHSTObjects].[PHOA]` |
| Function | Name begins with `EFN_` | `[Clarity_Report].[EPIC_UTIL]` |
| All others | Default | `[Clarity_Report].[dbo]` |

**Examples:**
```sql
-- Table containing 'CHIRPS': [CHSTObjects].[CHIRPS_TIPPS].[CHIRPS_EVENTS]
-- Table starting with 'SF_':  [CHSTObjects].[PHOA].[SF_PATIENT_DATA]
-- Table starting with 'PIECES_': [CHSTObjects].[PHOA].[PIECES_DETAIL]
-- Function starting with 'EFN_': [Clarity_Report].[EPIC_UTIL].[EFN_GET_VALUE]
-- Any other object:            [Clarity_Report].[dbo].[EMPLOYEES]
```

## Quality Requirements

- Must compile without errors on SQL Server 2019+
- Must use schema-qualified names per the Schema Qualification Rules above
- Must include `GO` batch separators between DDL statements
- Must use `SET NOCOUNT ON` in all procedures
- Must use `BEGIN TRY/CATCH` for error handling
- Must preserve original business logic semantics
- Must not use deprecated T-SQL features (`SET ROWCOUNT`, `*=` joins, etc.)

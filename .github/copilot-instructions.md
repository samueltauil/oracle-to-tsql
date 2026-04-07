# Oracle to T-SQL Migration Project

## Project Overview

This project facilitates the migration of Oracle SQL (PL/SQL) code to Microsoft SQL Server T-SQL. Oracle SQL files are placed in the `oracle-sql/` directory for analysis and conversion.

## Directory Structure

```
oracle-sql/          → Drop Oracle SQL files here (source input)
tsql-output/         → Converted T-SQL files (generated output)
migration-reports/   → Evaluation, validation, and performance reports
```

## Custom Agents

Use the following agents for the migration workflow:

| Agent | Purpose |
|-------|---------|
| `@oracle-evaluator` | Evaluate Oracle SQL files for migration complexity and readiness |
| `@oracle-to-tsql` | Convert Oracle SQL to T-SQL with best practices |
| `@tsql-validator` | Validate converted T-SQL for correctness and equivalence |
| `@performance-analyzer` | Analyze performance implications and optimize queries |

## Workflow

1. **Drop** Oracle SQL files into `oracle-sql/`
2. **Evaluate** with `@oracle-evaluator` to assess complexity and identify issues
3. **Convert** with `@oracle-to-tsql` to generate T-SQL equivalents
4. **Validate** with `@tsql-validator` to verify correctness
5. **Optimize** with `@performance-analyzer` to ensure performance

## Key Oracle → T-SQL Differences Reference

### Data Types
| Oracle | T-SQL |
|--------|-------|
| `VARCHAR2(n)` | `NVARCHAR(n)` or `VARCHAR(n)` |
| `NUMBER` | `INT`, `BIGINT`, `DECIMAL(p,s)`, or `NUMERIC(p,s)` |
| `NUMBER(1)` | `TINYINT` (safe default; use `BIT` only if confirmed 0/1 only) |
| `NUMBER(p)` | `INT` (p≤9), `BIGINT` (p≤18), `DECIMAL(p)` |
| `NUMBER(p,s)` | `DECIMAL(p,s)` |
| `DATE` | `DATETIME2` (includes time) or `DATE` (date only) |
| `TIMESTAMP` | `DATETIME2` or `DATETIMEOFFSET` |
| `CLOB` | `NVARCHAR(MAX)` or `VARCHAR(MAX)` |
| `BLOB` | `VARBINARY(MAX)` |
| `RAW(n)` | `VARBINARY(n)` |
| `LONG` | `NVARCHAR(MAX)` |
| `BOOLEAN` (PL/SQL) | `BIT` |
| `BINARY_FLOAT` | `REAL` |
| `BINARY_DOUBLE` | `FLOAT` |
| `XMLTYPE` | `XML` |
| `INTERVAL` | No direct equivalent — use computed columns or `DATEDIFF` |

### Functions
| Oracle | T-SQL |
|--------|-------|
| `NVL(a, b)` | `ISNULL(a, b)` or `COALESCE(a, b)` |
| `NVL2(a, b, c)` | `IIF(a IS NOT NULL, b, c)` or `CASE WHEN a IS NOT NULL THEN b ELSE c END` |
| `DECODE(a, b, c, d)` | `CASE a WHEN b THEN c ELSE d END` |
| `SYSDATE` | `GETDATE()` or `SYSDATETIME()` |
| `SYSTIMESTAMP` | `SYSDATETIMEOFFSET()` |
| `TO_DATE(s, fmt)` | `CONVERT(DATETIME2, s, style)` or `TRY_PARSE(s AS DATE)` |
| `TO_CHAR(d, fmt)` | `FORMAT(d, fmt)` or `CONVERT(VARCHAR, d, style)` |
| `TO_NUMBER(s)` | `CAST(s AS DECIMAL)` or `TRY_CAST(s AS DECIMAL)` |
| `SUBSTR(s, p, n)` | `SUBSTRING(s, p, n)` |
| `INSTR(s, sub)` | `CHARINDEX(sub, s)` |
| `LENGTH(s)` | `LEN(s)` |
| `LENGTHB(s)` | `DATALENGTH(s)` |
| `TRIM(s)` | `LTRIM(RTRIM(s))` or `TRIM(s)` (SQL 2017+) |
| `LPAD(s, n, c)` | `RIGHT(REPLICATE(c, n) + s, n)` |
| `RPAD(s, n, c)` | `LEFT(s + REPLICATE(c, n), n)` |
| `\|\|` (concatenation) | `+` or `CONCAT()` |
| `ROWNUM` | `ROW_NUMBER() OVER (ORDER BY ...)` |
| `ROWID` | No direct equivalent — use primary key |
| `SEQUENCE.NEXTVAL` | `NEXT VALUE FOR sequence_name` |
| `SEQUENCE.CURRVAL` | No direct equivalent — capture NEXT VALUE in variable |
| `LISTAGG()` | `STRING_AGG()` (SQL 2017+) |
| `REGEXP_LIKE` | `LIKE` with patterns or CLR functions |
| `MONTHS_BETWEEN` | `DATEDIFF(MONTH, d1, d2)` |
| `ADD_MONTHS` | `DATEADD(MONTH, n, d)` |
| `TRUNC(date)` | `CAST(date AS DATE)` |
| `MOD(a, b)` | `a % b` |
| `GREATEST(a,b,c)` | Nested `IIF` or `VALUES` clause (SQL 2022: `GREATEST`) |
| `LEAST(a,b,c)` | Nested `IIF` or `VALUES` clause (SQL 2022: `LEAST`) |

### Syntax and Constructs
| Oracle | T-SQL |
|--------|-------|
| `MINUS` | `EXCEPT` |
| `CONNECT BY / START WITH` | Recursive `CTE` (`WITH ... AS`) |
| `LEVEL` (hierarchical) | CTE level column with `UNION ALL` |
| `DUAL` table | Not needed — `SELECT 1` works without `FROM` |
| `CREATE OR REPLACE` | `CREATE OR ALTER` (SQL 2016 SP1+) or `DROP IF EXISTS` + `CREATE` |
| `EXIT WHEN` (loop) | `BREAK` inside `IF` |
| `FOR ... LOOP` | `WHILE` loop |
| `CURSOR FOR LOOP` | `DECLARE CURSOR` + `FETCH` + `WHILE @@FETCH_STATUS = 0` |
| `BULK COLLECT` | Table variables or temp tables |
| `FORALL` | Set-based operations |
| `EXECUTE IMMEDIATE` | `EXEC sp_executesql` |
| `DBMS_OUTPUT.PUT_LINE` | `PRINT` or `RAISERROR` with severity 0 |
| `RAISE_APPLICATION_ERROR` | `THROW` or `RAISERROR` |
| `PRAGMA AUTONOMOUS_TRANSACTION` | Separate connection or `INSERT ... EXEC` pattern |
| `%TYPE / %ROWTYPE` | Explicit type declarations |
| `EXCEPTION WHEN ... THEN` | `BEGIN TRY ... END TRY BEGIN CATCH ... END CATCH` |
| Packages | Schemas + individual procedures/functions |
| Table of records | Table-valued parameters or temp tables |
| Nested tables / VARRAYs | Table variables or temp tables |
| `RETURNING INTO` | `OUTPUT` clause |
| `MERGE ... USING` | `MERGE ... USING` (similar but different syntax) |
| Materialized views | Indexed views or manual refresh pattern |
| Database links | Linked servers |
| `REF CURSOR` / `SYS_REFCURSOR` | Result sets returned directly from procedures |
| `GRANT EXECUTE ON package` | `GRANT EXECUTE ON SCHEMA::schema_name` |

## Coding Standards

- Use `NVARCHAR` over `VARCHAR` for Unicode support unless explicitly not needed
- Prefer `COALESCE` over `ISNULL` for ANSI compliance and multi-argument support
- Use `DATETIME2` over `DATETIME` for better precision and range
- Use `TRY_CAST`/`TRY_CONVERT` for safe type conversions
- Use `THROW` over `RAISERROR` for new code
- Use `CREATE OR ALTER` when targeting SQL Server 2016 SP1+
- Use schema-qualified object names (e.g., `dbo.TableName`)
- Include `SET NOCOUNT ON` in stored procedures
- Use `BEGIN TRY/CATCH` for error handling in all procedures
- Preserve original Oracle comments and add migration notes where behavior differs
- Add `-- MIGRATION NOTE:` comments where conversion is non-trivial or behavior differs

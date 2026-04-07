# Oracle to T-SQL Migration Project

## Project Overview

This project facilitates the migration of Oracle SQL (PL/SQL) code to Microsoft SQL Server T-SQL. Oracle SQL files are placed in the `oracle-sql/` directory for analysis and conversion through a 4-phase pipeline: **evaluate → convert → validate → optimize**.

**Target Platform**: Microsoft SQL Server 2019+ (compatible with Azure SQL Database where noted)

## Directory Structure

```
oracle-sql/          → Drop Oracle SQL files here (source input, read-only)
tsql-output/         → Converted T-SQL files (generated output)
migration-reports/   → Evaluation, validation, and performance reports
```

## Custom Agents

| Agent | Purpose | When to use |
|-------|---------|-------------|
| `@oracle-evaluator` | Assess migration complexity and risks | Before converting — understand what you're dealing with |
| `@oracle-to-tsql` | Convert Oracle SQL to T-SQL | After evaluation — produce the T-SQL output |
| `@tsql-validator` | Validate correctness and semantic equivalence | After conversion — catch bugs before deployment |
| `@performance-analyzer` | Analyze performance and optimize | After validation — ensure production readiness |
| `@migration-orchestrator` | Batch process multiple files in parallel | When migrating many files at once |

## Workflow

1. **Drop** Oracle SQL files into `oracle-sql/`
2. **Evaluate** with `@oracle-evaluator` to assess complexity and identify issues
3. **Convert** with `@oracle-to-tsql` to generate T-SQL equivalents
4. **Validate** with `@tsql-validator` to verify correctness
5. **Optimize** with `@performance-analyzer` to ensure performance

For batch operations: `@migration-orchestrator migrate all`

---

## ⚠️ Critical Semantic Differences

These are the most dangerous differences between Oracle and SQL Server. They cause **silent behavioral changes** — the code runs without errors but produces different results.

### 1. Empty String = NULL (🔴 HIGHEST RISK)

Oracle treats `''` (empty string) as `NULL`. SQL Server does **NOT**.

| Expression | Oracle Result | SQL Server Result |
|-----------|---------------|-------------------|
| `'' IS NULL` | `TRUE` | `FALSE` |
| `LENGTH('')` | `NULL` | `0` |
| `NVL('', 'default')` | `'default'` | `''` |
| `'abc' \|\| NULL \|\| 'def'` | `'abcdef'` | `NULL` (with `+`) |
| `WHERE name = ''` | No rows ('' is NULL) | Rows with empty string |
| `INSERT INTO t VALUES ('')` | Inserts `NULL` | Inserts `''` |

**Migration pattern**: Use `NULLIF(column, N'')` to convert empty strings to NULL before comparison:
```sql
-- Oracle: NVL(first_name, 'Unknown')
-- T-SQL:  COALESCE(NULLIF(first_name, N''), N'Unknown')
```

### 2. DECODE NULL Matching (🔴 HIGH RISK)

Oracle `DECODE(x, NULL, 'match')` matches when `x IS NULL`. T-SQL `CASE x WHEN NULL` does **NOT**.

```sql
-- Oracle:  DECODE(status, NULL, 'Unknown', status)
-- WRONG:   CASE status WHEN NULL THEN 'Unknown' ELSE status END   ← NEVER matches NULL
-- CORRECT: CASE WHEN status IS NULL THEN 'Unknown' ELSE status END
```

### 3. Date Includes Time (🟡 MEDIUM RISK)

Oracle `DATE` stores both date and time. If you map to T-SQL `DATE`, you lose the time component.

```sql
-- Oracle DATE = 2024-01-15 14:30:00
-- T-SQL DATE = 2024-01-15 (time lost!)
-- T-SQL DATETIME2(0) = 2024-01-15 14:30:00 (correct)
```

**Rule**: Default to `DATETIME2(0)` unless you've confirmed time is never used.

### 4. String Concatenation NULL Propagation (🟡 MEDIUM RISK)

Oracle `||` ignores NULL operands. T-SQL `+` propagates NULL (entire result becomes NULL).

```sql
-- Oracle:  'Hello' || NULL || 'World' = 'HelloWorld'
-- T-SQL:   'Hello' + NULL + 'World'   = NULL
-- T-SQL:   CONCAT('Hello', NULL, 'World') = 'HelloWorld'  ← Use CONCAT()
```

### 5. NULL Sorting Order

Oracle sorts NULLs **last** by default. SQL Server sorts NULLs **first**.

```sql
-- To match Oracle behavior in T-SQL:
ORDER BY CASE WHEN column IS NULL THEN 1 ELSE 0 END, column
```

### 6. Integer Division

Oracle: `5 / 2 = 2.5` (numeric division). SQL Server: `5 / 2 = 2` (integer truncation).

```sql
-- Fix: CAST(a AS DECIMAL(18,2)) / b  or  a * 1.0 / b
```

### 7. Transaction Behavior

Oracle uses implicit transactions (every DML is in a transaction). SQL Server uses **autocommit** by default.

Oracle `COMMIT` inside a procedure may commit the **caller's transaction** in SQL Server.

**Pattern**: Use `@@TRANCOUNT` to check for existing transactions:
```sql
DECLARE @own_tran BIT = 0;
IF @@TRANCOUNT = 0 BEGIN BEGIN TRANSACTION; SET @own_tran = 1; END;
-- ... work ...
IF @own_tran = 1 COMMIT TRANSACTION;
```

### 8. ROWNUM Evaluation Order

Oracle assigns `ROWNUM` **before** `ORDER BY`. This means:
```sql
-- Oracle: This does NOT return top 5 highest salaries!
SELECT * FROM employees WHERE ROWNUM <= 5 ORDER BY salary DESC;
-- It picks 5 arbitrary rows, THEN sorts them.
```

---

## Data Type Mapping Reference

### Numeric Types
| Oracle | T-SQL | Notes |
|--------|-------|-------|
| `NUMBER` | `DECIMAL(18,0)` | Or context-appropriate INT/BIGINT/DECIMAL |
| `NUMBER(1)` | `TINYINT` | Safe default; `BIT` only if confirmed 0/1 |
| `NUMBER(p)` p≤9 | `INT` | |
| `NUMBER(p)` p≤18 | `BIGINT` | |
| `NUMBER(p,s)` | `DECIMAL(p,s)` | |
| `BINARY_FLOAT` | `REAL` | |
| `BINARY_DOUBLE` | `FLOAT` | |
| `PLS_INTEGER` | `INT` | PL/SQL only |

### String Types
| Oracle | T-SQL | Notes |
|--------|-------|-------|
| `VARCHAR2(n)` | `NVARCHAR(n)` | Prefer NVARCHAR for Unicode; VARCHAR if confirmed ASCII |
| `NVARCHAR2(n)` | `NVARCHAR(n)` | Direct mapping |
| `CHAR(n)` | `CHAR(n)` / `NCHAR(n)` | Watch blank-padding comparison differences |
| `CLOB` | `NVARCHAR(MAX)` | |
| `NCLOB` | `NVARCHAR(MAX)` | |
| `LONG` | `NVARCHAR(MAX)` | Deprecated in Oracle |

### Date/Time Types
| Oracle | T-SQL | Notes |
|--------|-------|-------|
| `DATE` | `DATETIME2(0)` | ⚠️ Oracle DATE includes time! |
| `TIMESTAMP` | `DATETIME2` | |
| `TIMESTAMP WITH TIME ZONE` | `DATETIMEOFFSET` | |
| `INTERVAL YEAR TO MONTH` | `INT` (months) | No direct equivalent |
| `INTERVAL DAY TO SECOND` | `BIGINT` (seconds) | No direct equivalent |

### Binary/LOB Types
| Oracle | T-SQL | Notes |
|--------|-------|-------|
| `BLOB` | `VARBINARY(MAX)` | |
| `RAW(n)` | `VARBINARY(n)` | |
| `LONG RAW` | `VARBINARY(MAX)` | Deprecated in Oracle |
| `BFILE` | `VARBINARY(MAX)` | External file → inline storage |

### Other Types
| Oracle | T-SQL | Notes |
|--------|-------|-------|
| `BOOLEAN` (PL/SQL) | `BIT` | |
| `XMLTYPE` | `XML` | |
| `ROWID` / `UROWID` | Remove | Use primary key instead |
| `%TYPE` | Explicit type | Look up the actual column type |
| `%ROWTYPE` | Explicit columns | Declare individual variables |

---

## Function Mapping Reference

### NULL Handling
| Oracle | T-SQL | ⚠️ Gotcha |
|--------|-------|-----------|
| `NVL(a, b)` | `COALESCE(a, b)` | COALESCE prefers for ANSI + multi-arg |
| `NVL2(a, b, c)` | `IIF(a IS NOT NULL, b, c)` | |
| `DECODE(a, b, c, d)` | `CASE a WHEN b THEN c ELSE d END` | ⚠️ DECODE(x, NULL, ...) needs `CASE WHEN x IS NULL` |
| `NULLIF(a, b)` | `NULLIF(a, b)` | Same behavior |

### String Functions
| Oracle | T-SQL | ⚠️ Gotcha |
|--------|-------|-----------|
| `\|\|` | `CONCAT()` | ⚠️ Use CONCAT, not `+` (NULL propagation) |
| `SUBSTR(s, p, n)` | `SUBSTRING(s, p, n)` | ⚠️ Negative pos: Oracle counts from end, SUBSTRING does not |
| `INSTR(s, sub)` | `CHARINDEX(sub, s)` | ⚠️ Argument order is reversed |
| `INSTR(s, sub, pos, nth)` | Custom logic | No native nth-occurrence support |
| `LENGTH(s)` | `LEN(s)` | ⚠️ LEN trims trailing spaces; use DATALENGTH for bytes |
| `LENGTHB(s)` | `DATALENGTH(s)` | |
| `LPAD(s, n, c)` | `RIGHT(REPLICATE(c, n) + s, n)` | |
| `RPAD(s, n, c)` | `LEFT(s + REPLICATE(c, n), n)` | |
| `TRIM(s)` | `TRIM(s)` (2017+) or `LTRIM(RTRIM(s))` | |
| `REPLACE(s, a, b)` | `REPLACE(s, a, b)` | Same behavior |
| `TRANSLATE(s, from, to)` | `TRANSLATE(s, from, to)` (2017+) | |
| `LISTAGG(col, sep)` | `STRING_AGG(col, sep)` (2017+) | WITHIN GROUP ORDER BY needs 2022+ |
| `REGEXP_LIKE(s, p)` | `s LIKE pattern` or CLR | No native regex |
| `REGEXP_REPLACE` | Nested `REPLACE` or CLR | No native regex |
| `REGEXP_SUBSTR` | `SUBSTRING` + `PATINDEX` or CLR | No native regex |

### Date/Time Functions
| Oracle | T-SQL | ⚠️ Gotcha |
|--------|-------|-----------|
| `SYSDATE` | `GETDATE()` | |
| `SYSTIMESTAMP` | `SYSDATETIMEOFFSET()` | |
| `TRUNC(date)` | `CAST(date AS DATE)` | |
| `TRUNC(date, 'MM')` | `DATEADD(MONTH, DATEDIFF(MONTH, 0, d), 0)` | 2022+: `DATETRUNC(MONTH, d)` |
| `ADD_MONTHS(d, n)` | `DATEADD(MONTH, n, d)` | |
| `MONTHS_BETWEEN(d1, d2)` | `DATEDIFF(MONTH, d2, d1)` | ⚠️ Oracle returns fractional; DATEDIFF returns integer |
| `LAST_DAY(d)` | `EOMONTH(d)` | |
| `NEXT_DAY(d, 'MON')` | `DATEADD(DAY, ...)` + weekday math | ⚠️ Depends on `@@DATEFIRST` setting |
| `date + n` (add days) | `DATEADD(DAY, n, date)` | ⚠️ Oracle allows arithmetic; T-SQL needs DATEADD |
| `TO_DATE(s, fmt)` | `TRY_CONVERT(DATETIME2, s, style)` | |
| `TO_CHAR(d, fmt)` | `FORMAT(d, dotnet_fmt)` | ⚠️ Format strings differ (see table below) |
| `TO_NUMBER(s)` | `TRY_CAST(s AS DECIMAL)` | |
| `ROUND(date, fmt)` | Custom `DATEADD`/`DATEDIFF` logic | |

### Oracle → .NET Format Strings (for `FORMAT()`)
| Oracle | .NET | Example |
|--------|------|---------|
| `YYYY` | `yyyy` | 2024 |
| `MM` | `MM` | 01 |
| `DD` | `dd` | 15 |
| `HH24` | `HH` | 14 |
| `HH` / `HH12` | `hh` | 02 |
| `MI` | `mm` | 30 |
| `SS` | `ss` | 45 |
| `FF` / `FF3` | `fff` | 123 |
| `DAY` | `dddd` | Monday |
| `DY` | `ddd` | Mon |
| `MON` | `MMM` | Jan |
| `MONTH` | `MMMM` | January |
| `AM`/`PM` | `tt` | PM |

### Numeric Functions
| Oracle | T-SQL | ⚠️ Gotcha |
|--------|-------|-----------|
| `MOD(a, b)` | `a % b` | ⚠️ Negative number handling may differ |
| `TRUNC(n, d)` | `ROUND(n, d, 1)` | Third arg `1` = truncate mode |
| `GREATEST(a,b,c)` | `(SELECT MAX(v) FROM (VALUES(a),(b),(c)) T(v))` | 2022+: `GREATEST()` native |
| `LEAST(a,b,c)` | `(SELECT MIN(v) FROM (VALUES(a),(b),(c)) T(v))` | 2022+: `LEAST()` native |
| `POWER(a, b)` | `POWER(a, b)` | Same |
| `ABS(n)` | `ABS(n)` | Same |
| `CEIL(n)` | `CEILING(n)` | |
| `FLOOR(n)` | `FLOOR(n)` | Same |
| `SIGN(n)` | `SIGN(n)` | Same |

### Aggregate Functions
| Oracle | T-SQL | ⚠️ Gotcha |
|--------|-------|-----------|
| `LISTAGG(col, sep) WITHIN GROUP (ORDER BY x)` | `STRING_AGG(col, sep) WITHIN GROUP (ORDER BY x)` | ORDER BY within STRING_AGG needs 2022+ |
| `MEDIAN(col)` | `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY col) OVER ()` | |
| `RATIO_TO_REPORT(col) OVER ()` | `col * 1.0 / SUM(col) OVER ()` | |

---

## Syntax and Construct Mapping Reference

### Query Syntax
| Oracle | T-SQL | ⚠️ Gotcha |
|--------|-------|-----------|
| `SELECT ... FROM DUAL` | `SELECT ...` (no FROM needed) | |
| `MINUS` | `EXCEPT` | |
| `ROWNUM` | `ROW_NUMBER() OVER(ORDER BY ...)` | ⚠️ ROWNUM assigned before ORDER BY in Oracle |
| `ROWNUM <= N` | `TOP N` or `OFFSET 0 ROWS FETCH NEXT N ROWS ONLY` | |
| `CONNECT BY` / `START WITH` | Recursive CTE | See hierarchical query pattern below |
| `LEVEL` | CTE level counter | |
| `SYS_CONNECT_BY_PATH` | String accumulation in CTE | |
| `CONNECT_BY_ROOT` | Anchor value carried through CTE | |
| `CONNECT_BY_ISLEAF` | `NOT EXISTS` subquery | |
| `ORDER SIBLINGS BY` | Sort path column in CTE | No direct equivalent |
| `(+)` outer join | `LEFT JOIN` / `RIGHT JOIN` | ⚠️ Filter conditions must move to ON clause |
| `PIVOT` | `PIVOT` | Similar but different syntax |
| `MODEL` clause | No equivalent | Requires complete rewrite |
| Oracle hints `/*+ ... */` | T-SQL hints `OPTION(...)` or `WITH(...)` | Different hint system |

### PL/SQL → T-SQL
| Oracle PL/SQL | T-SQL | ⚠️ Gotcha |
|---------------|-------|-----------|
| `CREATE OR REPLACE PROCEDURE` | `CREATE OR ALTER PROCEDURE` (2016 SP1+) | |
| `p_name IN NUMBER` | `@p_name INT` | @ prefix required, no IN/OUT keyword for input |
| `p_name OUT VARCHAR2` | `@p_name NVARCHAR(100) OUTPUT` | OUTPUT keyword |
| `p_name IN OUT NUMBER` | `@p_name INT OUTPUT` | Same as OUT in T-SQL |
| `v_name VARCHAR2(100) := 'x'` | `DECLARE @v_name NVARCHAR(100) = N'x'` | DECLARE keyword, @ prefix |
| `:= assignment` | `SET @var = value` or `SELECT @var = value` | |
| `v_name table.col%TYPE` | `DECLARE @v_name <actual_type>` | Look up the real type |
| `CURSOR c IS SELECT ...` | `DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT ...` | |
| `FOR rec IN c LOOP ... END LOOP` | `OPEN/FETCH/WHILE @@FETCH_STATUS=0/CLOSE/DEALLOCATE` | ⚠️ Consider set-based rewrite |
| `BULK COLLECT INTO` | Table variable or temp table | |
| `FORALL` | Single set-based DML statement | Preferred over cursor |
| `EXECUTE IMMEDIATE` | `EXEC sp_executesql` | ⚠️ Use QUOTENAME for identifiers |
| `RETURNING INTO` | `OUTPUT` clause with table variable | |
| `DBMS_OUTPUT.PUT_LINE` | `PRINT` | Or `RAISERROR(msg, 0, 1) WITH NOWAIT` for immediate |
| `RAISE_APPLICATION_ERROR(-20xxx, msg)` | `THROW 5xxxx, msg, 1` | Error numbers ≥ 50000 |
| `EXCEPTION WHEN NO_DATA_FOUND` | `IF @@ROWCOUNT = 0` after SELECT | ⚠️ No direct equivalent |
| `EXCEPTION WHEN TOO_MANY_ROWS` | `IF @@ROWCOUNT > 1` or `SELECT TOP 2` | |
| `EXCEPTION WHEN DUP_VAL_ON_INDEX` | `ERROR_NUMBER() IN (2627, 2601)` in CATCH | |
| `EXCEPTION WHEN OTHERS` | `BEGIN CATCH ... END CATCH` | |
| `SQLERRM` | `ERROR_MESSAGE()` | |
| `SQLCODE` | `ERROR_NUMBER()` | |
| `SQL%ROWCOUNT` | `@@ROWCOUNT` | ⚠️ Must read immediately — reset by next statement |
| `PRAGMA AUTONOMOUS_TRANSACTION` | No equivalent | ⚠️ Requires architectural redesign |

### Package Conversion
| Oracle Package | T-SQL Equivalent | ⚠️ Gotcha |
|---------------|-----------------|-----------|
| `CREATE PACKAGE spec` | `CREATE SCHEMA` | Schema for namespace |
| `CREATE PACKAGE BODY` | Individual `CREATE PROCEDURE` / `FUNCTION` | One per package member |
| Package constants | Local variables in each proc, or config table | No shared constants |
| Package variables | No equivalent | ⚠️ Session state is lost |
| Package initialization block | No equivalent | Must be called explicitly |
| Private procedures | Schema member with `_` prefix convention | All schema members are public |
| `TYPE ... IS TABLE OF` | Table variable type or temp table | |
| `TYPE ... IS RECORD` | Table variable or individual variables | |
| `REF CURSOR` return | Procedure returning result set | |
| `GRANT EXECUTE ON PACKAGE` | `GRANT EXECUTE ON SCHEMA::name` | |

### DBMS Package Replacements
| Oracle Package | T-SQL Equivalent |
|---------------|-----------------|
| `DBMS_OUTPUT.PUT_LINE` | `PRINT` |
| `DBMS_LOB.GETLENGTH` | `DATALENGTH()` |
| `DBMS_LOB.SUBSTR` | `SUBSTRING()` |
| `DBMS_SQL` | `sp_executesql` |
| `DBMS_SCHEDULER` | SQL Server Agent jobs |
| `DBMS_CRYPTO` | `HASHBYTES`, `ENCRYPTBYKEY` |
| `DBMS_METADATA` | `sys.sql_modules`, `OBJECT_DEFINITION()` |
| `UTL_FILE` | `xp_cmdshell` + `OPENROWSET`, SSIS, or CLR |
| `UTL_HTTP` | CLR, SSIS, or `sp_OACreate` |
| `UTL_MAIL` | Database Mail (`sp_send_dbmail`) |
| `DBMS_JOB` | SQL Server Agent |
| `DBMS_LOCK.SLEEP` | `WAITFOR DELAY` |
| `DBMS_RANDOM` | `NEWID()`, `RAND()`, `CRYPT_GEN_RANDOM()` |
| `DBMS_APPLICATION_INFO` | `sp_set_session_context` (2016+) |

---

## Common Conversion Patterns

### Hierarchical Query (CONNECT BY → Recursive CTE)

```sql
-- Oracle:
SELECT employee_id, manager_id, LEVEL
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id;

-- T-SQL:
WITH EmployeeCTE AS (
    SELECT employee_id, manager_id, 1 AS level
    FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.employee_id, e.manager_id, c.level + 1
    FROM employees e
    INNER JOIN EmployeeCTE c ON e.manager_id = c.employee_id
)
SELECT employee_id, manager_id, level
FROM EmployeeCTE
OPTION (MAXRECURSION 100);
```

### Pagination (ROWNUM → OFFSET/FETCH)

```sql
-- Oracle:
SELECT * FROM (
    SELECT t.*, ROWNUM rn FROM (
        SELECT * FROM employees ORDER BY salary DESC
    ) t WHERE ROWNUM <= 30
) WHERE rn > 20;

-- T-SQL:
SELECT * FROM employees
ORDER BY salary DESC
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```

### RETURNING INTO → OUTPUT

```sql
-- Oracle:
INSERT INTO employees (...) VALUES (...)
RETURNING employee_id INTO v_id;

-- T-SQL:
DECLARE @inserted TABLE (id BIGINT);
INSERT INTO employees (...)
OUTPUT inserted.employee_id INTO @inserted
VALUES (...);
SELECT @v_id = id FROM @inserted;
```

### Dynamic SQL Safety

```sql
-- Oracle:
EXECUTE IMMEDIATE 'SELECT * FROM ' || p_table_name;

-- T-SQL (with safety):
IF OBJECT_ID(@p_table_name, 'U') IS NULL
    THROW 50001, N'Table does not exist', 1;
DECLARE @sql NVARCHAR(4000) = N'SELECT * FROM ' + QUOTENAME(@p_table_name);
EXEC sp_executesql @sql;
```

---

## Coding Standards

### General
- Target **SQL Server 2019+** unless otherwise specified
- Use `NVARCHAR` over `VARCHAR` for Unicode support unless confirmed ASCII-only
- Use schema-qualified object names: `[dbo].[TableName]`
- Include `GO` batch separators between DDL statements
- Use `SET ANSI_NULLS ON` and `SET QUOTED_IDENTIFIER ON` at the start of each file

### Procedures and Functions
- Include `SET NOCOUNT ON` as the first statement
- Use `BEGIN TRY` / `BEGIN CATCH` for all error handling
- Use `THROW` over `RAISERROR` for new code
- Use `CREATE OR ALTER` (SQL Server 2016 SP1+)
- Use `@@TRANCOUNT` checks before `BEGIN TRANSACTION` to avoid nested transaction issues

### Type Conversions
- Prefer `COALESCE` over `ISNULL` (ANSI compliance, multi-argument support)
- Use `DATETIME2` over `DATETIME` (better precision and range)
- Use `TRY_CAST` / `TRY_CONVERT` for safe type conversions
- Use `TINYINT` for `NUMBER(1)` unless confirmed boolean

### Migration Annotations
- `-- MIGRATION NOTE:` — Documents non-trivial conversions or behavioral differences
- `-- MIGRATION WARNING:` — Flags areas needing human review or testing
- `-- MIGRATION TODO:` — Marks incomplete items requiring additional work
- Preserve original Oracle comments — they often contain business logic context

### What NOT to Use (deprecated or problematic)
- ❌ `SET ROWCOUNT` — use `TOP` instead
- ❌ `*=` / `=*` joins — use `LEFT JOIN` / `RIGHT JOIN`
- ❌ `DATETIME` — use `DATETIME2`
- ❌ `NTEXT` / `TEXT` / `IMAGE` — use `NVARCHAR(MAX)` / `VARBINARY(MAX)`
- ❌ `sp_rename` for constraint names in migration — use `DROP` + `CREATE`
- ❌ `NOLOCK` hints as a blanket fix — use RCSI instead

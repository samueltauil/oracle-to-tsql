# Migration Evaluation: 04_tricky_patterns.sql

**Source**: `oracle-sql/04_tricky_patterns.sql`
**Date**: 2025-07-15
**Overall Complexity**: 🔴 Critical

## Summary

This file is a deliberate collection of the trickiest Oracle-specific patterns including hierarchical queries (`CONNECT BY`), old-style `(+)` outer joins, empty-string-as-NULL semantics, `DECODE` NULL handling, `ROWNUM` evaluation traps, `RETURNING INTO`, dynamic SQL (`EXECUTE IMMEDIATE`), and `BULK COLLECT`/`FORALL`. Nearly every section requires manual semantic rewrite and careful behavioral validation — not just syntactic translation.

## Object Inventory

| Object | Type | Schema | Lines |
|--------|------|--------|-------|
| Hierarchical Employee Query | SCRIPT (SELECT) | — | 8–20 |
| Old-Style Outer Joins (3 queries) | SCRIPT (SELECT) | — | 27–41 |
| Empty String Semantics (6 statements) | SCRIPT (mixed SELECT/DML) | — | 51–65 |
| DECODE NULL Pattern | SCRIPT (SELECT) | — | 72–77 |
| ROWNUM Patterns (3 queries) | SCRIPT (SELECT) | — | 85–107 |
| RETURNING INTO Block | SCRIPT (PL/SQL Anonymous Block) | — | 113–122 |
| `archive_old_records` | PROCEDURE | — | 128–155 |
| BULK COLLECT Block | SCRIPT (PL/SQL Anonymous Block) | — | 161–180 |

## Oracle-Specific Features Found

### Data Types
- `VARCHAR2` — lines 129, 133, 137 → convert to `NVARCHAR`
- `NUMBER` — lines 114, 130, 134 → convert to `INT`, `BIGINT`, or `DECIMAL(p,s)` depending on usage
- `%TYPE` — lines 162, 163 → no T-SQL equivalent; must use explicit type declarations

### Functions
- `NVL(expr, default)` — line 58 → `COALESCE()` or `ISNULL()`
- `DECODE(expr, search, result, ...)` — lines 74–76 → `CASE WHEN` (with special NULL handling)
- `SYSDATE` — lines 55, 117, 138, 146, 150 → `GETDATE()` or `SYSDATETIME()`
- `LPAD(s, n, c)` — line 14 → `RIGHT(REPLICATE(c, n) + s, n)`
- `LEVEL` — lines 12, 14 → recursive CTE level column
- `SYS_CONNECT_BY_PATH(col, sep)` — line 13 → manual path accumulation in recursive CTE
- `CONNECT_BY_ISLEAF` — line 15 → no direct equivalent; requires subquery/NOT EXISTS check
- `CONNECT_BY_ROOT` — line 16 → anchor column carried through recursive CTE
- `ROWNUM` — lines 87, 96, 101, 107 → `TOP`, `ROW_NUMBER()`, or `OFFSET ... FETCH`
- `DBMS_OUTPUT.PUT_LINE` — lines 121, 141, 177 → `PRINT` or `RAISERROR(..., 0, 1) WITH NOWAIT`

### PL/SQL Constructs
- `DECLARE ... BEGIN ... END` anonymous blocks — lines 113–122, 161–180
- `CREATE OR REPLACE PROCEDURE` — line 128 → `CREATE OR ALTER PROCEDURE`
- `%TYPE` attribute — lines 162, 163 → explicit type declarations required
- `RETURNING INTO` — line 118 → `OUTPUT` clause
- `EXECUTE IMMEDIATE ... INTO ... USING` — lines 139, 147, 151 → `sp_executesql` with output and input parameters
- `BULK COLLECT INTO` — line 168 → set-based operation or temp table
- `FORALL` — line 172 → single set-based `UPDATE` statement
- `SQL%ROWCOUNT` — line 177 → `@@ROWCOUNT`
- `TYPE ... IS TABLE OF` (collection types) — lines 162–163 → table variables or temp tables
- Sequence `.NEXTVAL` — line 117 → `NEXT VALUE FOR`
- `COMMIT` — lines 153, 178 → transaction management design decision

### Syntax
- `CONNECT BY` / `START WITH` — lines 18–19 → recursive CTE
- `ORDER SIBLINGS BY` — line 20 → **no direct T-SQL equivalent**; requires custom sort path in CTE
- `(+)` outer join syntax — lines 29, 34, 39–41 → ANSI `LEFT JOIN` / `RIGHT JOIN`
- `:=` assignment operator — lines 137, 144, 149 → `SET @var =` or `SELECT @var =`
- `||` string concatenation — lines 10, 14, 55, 65, 76, 121, 137–151, 177 → `+` or `CONCAT()`
- `CREATE OR REPLACE` — line 128 → `CREATE OR ALTER` (SQL 2016 SP1+)
- `/` block terminator — lines 122, 155, 180 → not needed in T-SQL; use `GO` batch separator
- Empty string = NULL semantics — lines 47–65 → **fundamental behavioral difference**

## Critical Semantic Differences

### 1. Empty String = NULL (🔴 Highest Risk)
**Lines 47–65.** Oracle treats `''` as `NULL`. This affects:
- `IS NULL` checks silently include empty strings in Oracle but not in SQL Server
- `INSERT ... VALUES (999, '', ...)` inserts `NULL` in Oracle but `''` in SQL Server
- `NVL('', 'default')` returns `'default'` in Oracle; `COALESCE('', 'default')` returns `''` in SQL Server
- `WHERE first_name = ''` is always false in Oracle (because `'' IS NULL`) but matches empty strings in SQL Server
- String concatenation: Oracle `||` ignores NULL operands; SQL Server `+` propagates NULL (entire result becomes NULL). `CONCAT()` treats NULL as empty string, which is closer but not identical.

Every query touching string columns must be audited for this difference.

### 2. DECODE NULL Handling (🔴 High Risk)
**Lines 72–77.** `DECODE(x, NULL, result)` matches when `x IS NULL`. The naïve T-SQL conversion `CASE x WHEN NULL THEN result` does **not** match NULLs. Must convert to `CASE WHEN x IS NULL THEN result`.

### 3. ROWNUM Evaluation Order (🟠 Medium-High Risk)
**Lines 85–107.** Oracle assigns `ROWNUM` before `ORDER BY`, so `WHERE ROWNUM <= 5 ORDER BY salary DESC` does NOT return the top-5 highest salaries. The file includes the correct subquery pattern too. Migration must determine: preserve Oracle's actual behavior, or fix to the developer's likely intent?

### 4. DATE Includes Time (🟡 Medium Risk)
`SYSDATE` (lines 55, 117, 138, 146, 150) includes a time component. Date arithmetic like `SYSDATE - :days` works identically with `GETDATE()`, but downstream comparisons on date-only columns may differ.

### 5. Transaction Ownership (🟠 Medium-High Risk)
**Lines 153, 178.** Explicit `COMMIT` inside procedures/blocks. In SQL Server, if the procedure is called within a caller-owned transaction, an internal `COMMIT` can commit the caller's transaction prematurely. This requires a transaction management design decision (e.g., `@@TRANCOUNT` checks, `SAVE TRANSACTION` patterns).

### 6. NULL Sorting
`ORDER SIBLINGS BY` (line 20): Oracle sorts NULLs last by default; SQL Server sorts NULLs first. May produce different ordering.

## Dependencies

| Dependency | Type | Notes |
|------------|------|-------|
| `employees` | Table | Referenced throughout (SELECT, INSERT, UPDATE, DELETE) |
| `departments` | Table | Lines 28, 33, 38 (outer join examples) |
| `locations` | Table | Line 38 (multi-table outer join) |
| `emp_seq` | Sequence | Line 117 (NEXTVAL for employee ID generation) |
| `DBMS_OUTPUT` | Package | Lines 121, 141, 177 (debug output) |
| `<p_table_name>` | Dynamic Table(s) | Lines 137–151 (runtime-determined table names) |
| `<p_table_name>_archive` | Dynamic Table(s) | Line 144 (archive target tables, runtime-determined) |
| `created_at` column | Column | Lines 138, 146, 150 (assumed on all dynamic target tables) |

## Risk Assessment

| Risk | Severity | Description |
|------|----------|-------------|
| CONNECT BY → Recursive CTE | 🔴 Critical | Full hierarchical query with `LEVEL`, `SYS_CONNECT_BY_PATH`, `CONNECT_BY_ISLEAF`, `CONNECT_BY_ROOT`, and `ORDER SIBLINGS BY`. No direct T-SQL equivalent for `ORDER SIBLINGS BY`; requires custom sort-path column. Must also handle `MAXRECURSION` (default 100 in SQL Server). |
| Empty string = NULL | 🔴 Critical | Pervasive semantic difference. Silent behavior change in every string comparison, IS NULL check, NVL/COALESCE, INSERT, and concatenation. Requires full audit of all string-handling code. |
| DECODE NULL matching | 🔴 Critical | `DECODE(x, NULL, ...)` must become `CASE WHEN x IS NULL ...`, not `CASE x WHEN NULL ...`. Easy to get wrong in bulk conversion. |
| Dynamic SQL identifier safety | 🔴 Critical | `p_table_name` is concatenated directly into SQL. `sp_executesql` cannot parameterize identifiers. Requires `QUOTENAME()` and ideally a whitelist to prevent SQL injection. |
| Concatenation NULL propagation | 🟠 High | Oracle `\|\|` effectively ignores NULL; SQL Server `+` propagates NULL. Must decide between `CONCAT()` (treats NULL as empty) or explicit `COALESCE` wrapping. |
| `(+)` outer join predicate placement | 🟠 High | Multi-table `(+)` with filter conditions (line 41: `l.country_id(+) = 'US'`) must be placed in the `ON` clause, not `WHERE`, or the outer join silently becomes inner. |
| Transaction COMMIT in procedures | 🟠 High | `COMMIT` inside `archive_old_records` and the BULK COLLECT block may interfere with caller-owned transactions. Needs `@@TRANCOUNT` / `SAVE TRANSACTION` pattern. |
| ROWNUM → TOP / OFFSET-FETCH | 🟡 Moderate | Straightforward conversion, but must recognize intent: the first ROWNUM example is deliberately wrong in Oracle. Pagination pattern maps to `OFFSET ... FETCH NEXT`. |
| EXECUTE IMMEDIATE → sp_executesql | 🟡 Moderate | `INTO` becomes an `OUTPUT` parameter; `USING` becomes `sp_executesql` parameters. Mechanical but must be careful with bind variable mapping. |
| BULK COLLECT / FORALL | 🟡 Moderate | This specific example collapses cleanly to a single set-based `UPDATE ... SET salary = salary * 1.1 WHERE department_id = 10`. The real effort is recognizing that set-based rewrite. |
| RETURNING INTO → OUTPUT | 🟡 Moderate | Maps to `OUTPUT inserted.employee_id` clause. Sequence `.NEXTVAL` maps to `NEXT VALUE FOR`. |
| DBMS_OUTPUT → PRINT | 🟢 Low | Simple replacement. `DBMS_OUTPUT.PUT_LINE(...)` → `PRINT ...`. |

## Migration Recommendations

1. **CONNECT BY hierarchical query (Section 1)**: Rewrite as a recursive CTE with:
   - Anchor member for `WHERE manager_id IS NULL`
   - Recursive member joining `employee_id = manager_id`
   - Carry `LEVEL` as an incrementing integer column
   - Build `SYS_CONNECT_BY_PATH` equivalent via string concatenation in the recursive member
   - Emulate `CONNECT_BY_ROOT` by carrying the anchor's `last_name` through all levels
   - Emulate `CONNECT_BY_ISLEAF` with a `NOT EXISTS` subquery against children
   - Emulate `ORDER SIBLINGS BY` with a hierarchical sort-path column (e.g., zero-padded `last_name` concatenated at each level)
   - Set `OPTION (MAXRECURSION 0)` or an appropriate limit if deep hierarchies are expected

2. **Old-style outer joins (Section 2)**: Convert to ANSI `LEFT JOIN` / `RIGHT JOIN` syntax. Pay special attention to the multi-table query: the `l.country_id(+) = 'US'` filter must be placed in the `ON` clause of the `LEFT JOIN`, not the `WHERE` clause.

3. **Empty string = NULL (Section 3)**: For each statement:
   - `WHERE first_name IS NULL` → `WHERE first_name IS NULL OR first_name = ''` (if preserving Oracle semantics)
   - `INSERT ... VALUES (..., '', ...)` → `INSERT ... VALUES (..., NULL, ...)` (if preserving Oracle semantics)
   - `NVL('', 'default')` → `COALESCE(NULLIF(first_name, ''), 'No Name')` to treat empty as NULL
   - `WHERE first_name = ''` → keep as-is (never true in Oracle, never true with NULL in SQL Server) or remove
   - All `||` concatenation → use `CONCAT()` which handles NULLs similarly to Oracle's `||`
   - Add `-- MIGRATION NOTE:` comments explaining the semantic difference at each location

4. **DECODE NULL (Section 4)**: Convert each `DECODE` to `CASE`:
   - `DECODE(manager_id, NULL, 'CEO', 'Has Manager')` → `CASE WHEN manager_id IS NULL THEN 'CEO' ELSE 'Has Manager' END`
   - Do **not** use `CASE manager_id WHEN NULL THEN ...` as this will never match

5. **ROWNUM (Section 5)**: Convert the three patterns:
   - Incorrect ROWNUM query → `SELECT TOP 5 ... ORDER BY salary DESC` (preserving the bug, or fix with a comment)
   - Subquery pattern → `SELECT TOP 5 ... ORDER BY salary DESC`
   - Pagination → `ORDER BY salary DESC OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY`

6. **RETURNING INTO (Section 6)**: Use `OUTPUT inserted.employee_id` with a table variable to capture the value. Replace `emp_seq.NEXTVAL` with `NEXT VALUE FOR dbo.emp_seq`.

7. **Dynamic SQL (Section 7)**: Convert to `sp_executesql`. Wrap `p_table_name` with `QUOTENAME()` for identifier safety. Consider adding a whitelist validation. Remove `COMMIT` or wrap with `@@TRANCOUNT` guard. Replace `SYSDATE - :days` with `DATEADD(DAY, -@p_days_old, GETDATE())`.

8. **BULK COLLECT / FORALL (Section 8)**: Replace the entire block with a single set-based statement:
   ```sql
   UPDATE employees SET salary = salary * 1.1 WHERE department_id = 10;
   PRINT 'Updated ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' employees';
   ```
   Remove `COMMIT` or wrap with transaction guard.

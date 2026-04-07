# Migration Evaluation: 01_datatypes_table.sql

**Source**: `oracle-sql/01_datatypes_table.sql`
**Date**: 2025-07-14
**Overall Complexity**: 🟢 Simple

## Summary

This file creates a single `employees` table exercising all major Oracle data types, a sequence, and three indexes. It contains no PL/SQL logic — only DDL — making it a straightforward type-mapping migration.

## Object Inventory

| Object | Type | Schema | Lines |
|--------|------|--------|-------|
| `employees` | TABLE | *(none specified)* | 4–30 |
| `emp_seq` | SEQUENCE | *(none specified)* | 32 |
| `idx_emp_dept` | INDEX | *(none specified)* | 34 |
| `idx_emp_hire` | INDEX | *(none specified)* | 35 |
| `idx_emp_name` | INDEX | *(none specified)* | 36 |

## Oracle-Specific Features Found

### Data Types

| Oracle Type | Column(s) | T-SQL Mapping |
|-------------|-----------|---------------|
| `NUMBER(10)` | `employee_id` | `BIGINT` (p > 9) |
| `NUMBER(10,2)` | `salary` | `DECIMAL(10,2)` |
| `NUMBER(4,2)` | `commission_pct` | `DECIMAL(4,2)` |
| `NUMBER(5)` | `department_id` | `INT` (p ≤ 9) |
| `NUMBER(1)` | `is_active` | `BIT` (boolean-style usage) |
| `VARCHAR2(n)` | `first_name`, `last_name`, `phone_number` | `NVARCHAR(n)` |
| `NVARCHAR2(200)` | `email` | `NVARCHAR(200)` |
| `DATE` | `hire_date` | `DATETIME2` (Oracle DATE includes time) |
| `CLOB` | `notes` | `NVARCHAR(MAX)` |
| `NCLOB` | `resume` | `NVARCHAR(MAX)` |
| `BLOB` | `photo` | `VARBINARY(MAX)` |
| `RAW(16)` | `badge_raw` | `VARBINARY(16)` |
| `TIMESTAMP` | `created_at` | `DATETIME2` |
| `TIMESTAMP WITH TIME ZONE` | `updated_at` | `DATETIMEOFFSET` |
| `BINARY_FLOAT` | `yearly_bonus` | `REAL` |
| `BINARY_DOUBLE` | `lifetime_value` | `FLOAT` |
| `XMLTYPE` | `metadata` | `XML` |
| `LONG` | `legacy_desc` | `NVARCHAR(MAX)` |

### Functions

| Oracle Function | Location | T-SQL Equivalent |
|-----------------|----------|------------------|
| `SYSTIMESTAMP` | `created_at` DEFAULT | `SYSDATETIMEOFFSET()` |

### PL/SQL Constructs

*None found.*

### Syntax

| Oracle Syntax | Location | Notes |
|---------------|----------|-------|
| `CREATE SEQUENCE ... NOCACHE NOCYCLE` | Line 32 | T-SQL `CREATE SEQUENCE` supports `NO CACHE` / `NO CYCLE` with slightly different keywords |

## Critical Semantic Differences

| Difference | Affected Column(s) | Impact |
|------------|---------------------|--------|
| **Oracle DATE includes time** | `hire_date` | Oracle `DATE` stores date + time. If existing data uses the time component, mapping to T-SQL `DATE` loses it. `DATETIME2` is safer; use `DATE` only if time is confirmed unused. |
| **Empty string = NULL** | All `VARCHAR2` / `NVARCHAR2` columns | If application logic relies on Oracle treating `''` as `NULL`, uniqueness constraints (e.g., `uq_employees_email`) and `NOT NULL` constraints may behave differently in SQL Server. |
| **NUMBER(1) as boolean** | `is_active` | Oracle allows values other than 0/1 in `NUMBER(1)` (e.g., −9 to 9). T-SQL `BIT` restricts to 0/1/NULL. Verify data before mapping to `BIT`. |

## Dependencies

| Dependency | Type | Notes |
|------------|------|-------|
| `departments` | TABLE (FK reference) | `fk_dept` references `departments(department_id)` — must exist before this table is created |

## Risk Assessment

| Risk | Severity | Description |
|------|----------|-------------|
| `DATE` ↔ time semantics | 🟡 Medium | If `hire_date` stores time data, choosing `DATE` vs `DATETIME2` in T-SQL changes query behavior and index usage |
| Empty-string / NULL uniqueness | 🟡 Medium | SQL Server treats `''` as a distinct value from `NULL`; the `UNIQUE` constraint on `email` allows only one `NULL` by default (unless a filtered index is used) |
| `NUMBER(1)` → `BIT` data range | 🟢 Low | Only a concern if existing data contains values outside 0/1 |
| `LONG` deprecated type | 🟢 Low | `LONG` is deprecated in Oracle; maps cleanly to `NVARCHAR(MAX)` but confirm no LOB streaming dependencies |
| Missing schema qualifier | 🟢 Low | No schema specified; target should use explicit `dbo.` schema per coding standards |
| Dependency ordering | 🟢 Low | `departments` table must be created first due to the foreign-key constraint |

## Migration Recommendations

1. **Map all data types** using the reference table above. Prefer `NVARCHAR` over `VARCHAR` per project coding standards for Unicode support.
2. **Use `DATETIME2`** for `hire_date` unless the time component is confirmed unused — this preserves Oracle `DATE` semantics.
3. **Verify `is_active` data range** before choosing `BIT`. If values outside 0/1 exist, use `TINYINT` instead.
4. **Replace `SYSTIMESTAMP`** with `SYSDATETIMEOFFSET()` in the `created_at` default.
5. **Adjust sequence syntax**: T-SQL uses `NO CACHE` / `NO CYCLE` (with a space) instead of `NOCACHE` / `NOCYCLE`.
6. **Add schema prefix** (`dbo.`) to all object names per project coding standards.
7. **Use `CREATE OR ALTER`** (SQL Server 2016 SP1+) or `DROP TABLE IF EXISTS` + `CREATE TABLE` pattern per project standards.
8. **Ensure `departments` table** is migrated and created before this file is executed.

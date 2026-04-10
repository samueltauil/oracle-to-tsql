---
applyTo: "pbi-output/**"
---

# Power BI M-Language Output File Instructions

When working with files in the `pbi-output/` directory, these are **Power Query M code files** generated from T-SQL output (which was converted from Oracle SQL source files).

## Context

- Each `.pq` file here is Power Query M code that enables Power BI reports to connect to SQL Server instead of Oracle
- These files are derived from the T-SQL conversions in `tsql-output/`, which themselves were converted from Oracle SQL in `oracle-sql/`
- They should preserve the original business logic semantics while using Power Query M idioms

## File Naming Convention

- **Single-object files**: `<source-slug>.pq`
- **Multi-object (decomposed)**: `<source-slug>--<object-name>.pq`
- Example: `05_package_conversion--hire_employee.pq`

## File Header Standard

Every `.pq` file must start with a header block:

```m
// Source: oracle-sql/<original_filename>.sql
// T-SQL Source: tsql-output/<original_filename>.sql
// Object: <object_name>
// Mode: Native M | Native Query Wrapper
// Generated: <date>
// Description: <brief description>
```

## Connection Pattern

Always use parameterized connections — never hardcode server or database names:

```m
let
    ServerName = "server_placeholder",
    DatabaseName = "database_placeholder",
    Source = Sql.Database(ServerName, DatabaseName),
    ...
in
    Result
```

## Two Conversion Modes

### Native M

Uses query folding with M transformations. Preferred when the query logic can be expressed with standard M functions:

- `Table.SelectRows` for filtering
- `Table.Sort` for ordering
- `Table.TransformColumns` for column transformations
- `Table.Join` for joins
- `Table.Group` for aggregations

### Native Query Wrapper

Wraps T-SQL via `Value.NativeQuery()` for complex queries that cannot be folded natively:

```m
let
    ServerName = "server_placeholder",
    DatabaseName = "database_placeholder",
    Source = Sql.Database(ServerName, DatabaseName),
    Result = Value.NativeQuery(Source, "
        SELECT column1, column2
        FROM [dbo].[table_name]
        WHERE condition = @param
    ", [param = paramValue])
in
    Result
```

## Migration Notes Format

Use M-style inline comments for migration annotations:

```m
// MIGRATION NOTE: Oracle NVL chain replaced with native M null coalescing
// MIGRATION NOTE: CONNECT BY hierarchy handled via recursive T-SQL in native query
// MIGRATION WARNING: Oracle empty-string semantics — verify null handling in filters
// MIGRATION TODO: Review if Power BI parameter should replace hardcoded filter value
```

## Quality Requirements

- Must be valid Power Query M syntax
- Must use parameterized connections (no hardcoded server or database names)
- Must include migration annotations as M comments (`// MIGRATION NOTE:`)
- Must preserve original business logic semantics
- Must specify the conversion mode (Native M or Native Query Wrapper) in the file header

## Do NOT

- Hardcode server names or database names
- Modify files in `oracle-sql/` or `tsql-output/`
- Use deprecated M functions
- Assume Oracle SQL is the direct input — always reference the T-SQL intermediate output

---
applyTo: "oracle-sql/**"
---

# Oracle SQL Source File Instructions

When working with files in the `oracle-sql/` directory, these are **source Oracle SQL/PL/SQL files** intended for migration to T-SQL.

## Context

- These files are the **original source** and should NOT be modified
- They may contain: DDL, DML, PL/SQL procedures/functions/packages, triggers, views, sequences, synonyms, types, and scripts
- Analyze them for migration complexity and conversion requirements

## When Analyzing Oracle SQL Files

1. **Identify the object type**: Table, View, Procedure, Function, Package, Trigger, Sequence, Type, Script
2. **Catalog Oracle-specific features** used:
   - PL/SQL constructs (packages, nested blocks, autonomous transactions)
   - Oracle-specific functions (NVL, DECODE, CONNECT BY, ROWNUM, etc.)
   - Oracle data types (VARCHAR2, NUMBER, CLOB, BLOB, etc.)
   - Oracle-specific syntax (CREATE OR REPLACE, DUAL, := assignment, %TYPE/%ROWTYPE)
   - Oracle built-in packages (DBMS_OUTPUT, DBMS_LOB, UTL_FILE, etc.)
3. **Note dependencies**: References to other objects, synonyms, database links, sequences
4. **Flag potential issues**: Autonomous transactions, CONNECT BY hierarchies, custom types, bulk operations, REF CURSORs

## Naming Convention for Output

When a file `oracle-sql/my_procedure.sql` is converted, the output should be saved as `tsql-output/my_procedure.sql` (same name, same folder structure relative to root).

## Do NOT

- Modify files in `oracle-sql/` — they are read-only source material
- Assume Oracle SQL is syntactically valid without checking
- Ignore comments in the original — they often contain business logic context

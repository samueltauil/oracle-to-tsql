# Sample Oracle SQL Files

These are sample Oracle SQL files for testing the migration toolkit. They cover increasing complexity levels:

| File | Complexity | What It Tests |
|------|-----------|---------------|
| `01_datatypes_table.sql` | 🟢 Simple | All major Oracle data types, SEQUENCE, constraints, indexes |
| `02_function_conversions.sql` | 🟡 Moderate | NVL, DECODE, string/date functions, ROWNUM, DUAL, LISTAGG, MINUS |
| `03_plsql_procedure.sql` | 🟡 Moderate | Cursor FOR LOOP, %TYPE, exception handling, DBMS_OUTPUT |
| `04_tricky_patterns.sql` | 🔴 Critical | CONNECT BY, (+) joins, empty-string=NULL, RETURNING INTO, BULK COLLECT |
| `05_package_conversion.sql` | 🔴 Critical | Full package spec+body, REF CURSOR, session state, initialization block |

## How to Test

### Step 1: Copy samples to the input folder

```bash
cp samples/*.sql oracle-sql/
```

### Step 2: Run the full migration pipeline

Using the batch orchestrator (processes all files in parallel):

```
@migration-orchestrator migrate all
```

Or run each phase individually:

```
@migration-orchestrator evaluate all
@migration-orchestrator convert all
@migration-orchestrator validate all
@migration-orchestrator analyze all
```

### Step 3: Check status

```
@migration-orchestrator status
```

### Step 4: Review results

- **Evaluation reports**: `migration-reports/evaluation-*.md`
- **Converted T-SQL**: `tsql-output/*.sql`
- **Validation reports**: `migration-reports/validation-*.md`
- **Performance reports**: `migration-reports/performance-*.md`

### Step 5: Clean up (optional)

To reset and start fresh:

```bash
rm oracle-sql/*.sql tsql-output/*.sql migration-reports/*.md
rm -f migration-reports/.migration-state.json
```

## Single File Testing

To test one file at a time with individual agents:

```bash
# Copy one file
cp samples/04_tricky_patterns.sql oracle-sql/

# Run each phase
@oracle-evaluator evaluate oracle-sql/04_tricky_patterns.sql
@oracle-to-tsql convert oracle-sql/04_tricky_patterns.sql
@tsql-validator validate tsql-output/04_tricky_patterns.sql
@performance-analyzer analyze tsql-output/04_tricky_patterns.sql
```

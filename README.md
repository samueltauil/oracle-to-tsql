# Oracle to T-SQL Migration Project

A GitHub Copilot-powered toolkit for migrating Oracle SQL/PL/SQL code to Microsoft SQL Server T-SQL.

## Quick Start

1. **Drop** Oracle SQL files into `oracle-sql/`
2. **Evaluate**: `@oracle-evaluator evaluate all files in oracle-sql/`
3. **Convert**: `@oracle-to-tsql convert oracle-sql/my_procedure.sql`
4. **Validate**: `@tsql-validator validate tsql-output/my_procedure.sql`
5. **Optimize**: `@performance-analyzer analyze tsql-output/my_procedure.sql`

## Project Structure

```
oracle-sql/              ← Drop Oracle SQL files here (source, read-only)
tsql-output/             ← Converted T-SQL output (auto-generated)
migration-reports/       ← Evaluation, validation & performance reports
.github/
  ├── copilot-instructions.md          ← Global conversion reference
  ├── instructions/
  │   ├── oracle-sql.instructions.md   ← Context for Oracle files
  │   ├── tsql-output.instructions.md  ← Standards for T-SQL output
  │   └── migration-reports.instructions.md
  ├── agents/
  │   ├── oracle-evaluator.md          ← @oracle-evaluator agent
  │   ├── oracle-to-tsql.md            ← @oracle-to-tsql agent
  │   ├── tsql-validator.md            ← @tsql-validator agent
  │   └── performance-analyzer.md      ← @performance-analyzer agent
  └── extensions/
      └── oracle-migration/
          └── extension.mjs            ← Custom tools (scan, status, reports)
```

## Custom Agents

| Agent | Purpose | Example Usage |
|-------|---------|---------------|
| `@oracle-evaluator` | Assess migration complexity | `@oracle-evaluator evaluate oracle-sql/pkg_orders.sql` |
| `@oracle-to-tsql` | Convert Oracle → T-SQL | `@oracle-to-tsql convert oracle-sql/pkg_orders.sql` |
| `@tsql-validator` | Validate converted T-SQL | `@tsql-validator validate tsql-output/pkg_orders.sql` |
| `@performance-analyzer` | Performance optimization | `@performance-analyzer analyze tsql-output/pkg_orders.sql` |

## Custom Tools

| Tool | Description |
|------|-------------|
| `scan_oracle_files` | Lists all Oracle SQL files with metadata |
| `migration_status` | Shows evaluation/conversion/validation status per file |
| `list_migration_reports` | Lists all generated reports |
| `init_migration_project` | Creates project directory structure |

## Workflow

```
┌─────────────┐     ┌──────────────┐     ┌───────────────┐     ┌────────────────────┐
│   Drop SQL  │────►│   Evaluate   │────►│    Convert    │────►│     Validate       │
│  oracle-sql/│     │ @oracle-eval │     │ @oracle-to-   │     │  @tsql-validator   │
│             │     │              │     │    tsql       │     │                    │
└─────────────┘     └──────┬───────┘     └───────┬───────┘     └─────────┬──────────┘
                           │                     │                       │
                           ▼                     ▼                       ▼
                    migration-reports/     tsql-output/           migration-reports/
                    evaluation-*.md        *.sql                  validation-*.md
                                                                        │
                                                                        ▼
                                                              ┌────────────────────┐
                                                              │  Perf Analyze      │
                                                              │ @performance-      │
                                                              │    analyzer        │
                                                              └────────┬───────────┘
                                                                       │
                                                                       ▼
                                                                migration-reports/
                                                                performance-*.md
```

## Supported Oracle File Types

| Extension | Description |
|-----------|-------------|
| `.sql` | General SQL scripts |
| `.pls` | PL/SQL source |
| `.pks` | Package specification |
| `.pkb` | Package body |
| `.trg` | Trigger |
| `.vw` | View |
| `.fnc` | Function |
| `.prc` | Procedure |
| `.typ` | Type definition |

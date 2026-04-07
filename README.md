# Oracle to T-SQL Migration Toolkit

A GitHub Copilot-powered toolkit for migrating Oracle SQL/PL/SQL code to Microsoft SQL Server T-SQL. Uses custom agents, instructions, and extensions to evaluate, convert, validate, and optimize your SQL migration — with full support for batch processing across many files.

## Quick Start

1. **Copy sample files** (or drop your own Oracle SQL files) into `oracle-sql/`:
   ```bash
   cp samples/*.sql oracle-sql/
   ```
2. **Run the full pipeline**: `@migration-orchestrator migrate all`
3. **Check status**: `@migration-orchestrator status`
4. **Review results** in `tsql-output/` and `migration-reports/`

> See [samples/README.md](samples/README.md) for detailed testing instructions.

## Project Structure

```
samples/                 ← Sample Oracle SQL files for testing (5 files, 🟢→🔴)
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
  │   ├── performance-analyzer.md      ← @performance-analyzer agent
  │   └── migration-orchestrator.md    ← @migration-orchestrator agent
  └── extensions/
      └── oracle-migration/
          └── extension.mjs            ← Custom tools (scan, status, batch, state)
```

## Migration Pipeline

```mermaid
flowchart LR
    A["📂 Drop SQL files\noracle-sql/"] --> B["🔍 Evaluate\n@oracle-evaluator"]
    B --> C["🔄 Convert\n@oracle-to-tsql"]
    C --> D["✅ Validate\n@tsql-validator"]
    D --> E["⚡ Analyze\n@performance-analyzer"]

    B -->|report| R1["migration-reports/\nevaluation-*.md"]
    C -->|output| R2["tsql-output/\n*.sql"]
    D -->|report| R3["migration-reports/\nvalidation-*.md"]
    E -->|report| R4["migration-reports/\nperformance-*.md"]
```

## Custom Agents

| Agent | Purpose | Example Usage |
|-------|---------|---------------|
| `@oracle-evaluator` | Assess migration complexity and risks | `@oracle-evaluator evaluate oracle-sql/pkg_orders.sql` |
| `@oracle-to-tsql` | Convert Oracle SQL → T-SQL | `@oracle-to-tsql convert oracle-sql/pkg_orders.sql` |
| `@tsql-validator` | Validate converted T-SQL correctness | `@tsql-validator validate tsql-output/pkg_orders.sql` |
| `@performance-analyzer` | Performance analysis and optimization | `@performance-analyzer analyze tsql-output/pkg_orders.sql` |
| `@migration-orchestrator` | Batch orchestration with parallel sub-agents | `@migration-orchestrator migrate all` |

## Custom Tools

### Discovery & Status
| Tool | Description |
|------|-------------|
| `scan_oracle_files` | Discovers Oracle SQL files, returns structured JSON with metadata |
| `migration_status` | Per-file status across all phases (pending/in_progress/done/failed) |
| `list_migration_reports` | Lists all generated reports with type classification |
| `init_migration_project` | Creates project directories and initializes state |

### Batch Orchestration
| Tool | Description |
|------|-------------|
| `generate_batch_plan` | Generates dispatch plan with sub-agent prompts per file+phase |
| `claim_work_item` | Locks a file+phase as in_progress before dispatching |
| `complete_work_item` | Marks file+phase as done after sub-agent succeeds |
| `fail_work_item` | Records failure with error message for retry |
| `reset_work_item` | Resets a file+phase to pending for retry |

## Workflow

### Single File (use individual agents)

```
@oracle-evaluator evaluate oracle-sql/my_proc.sql
@oracle-to-tsql convert oracle-sql/my_proc.sql
@tsql-validator validate tsql-output/my_proc.sql
@performance-analyzer analyze tsql-output/my_proc.sql
```

### Batch Migration (use orchestrator with parallel sub-agents)

```
@migration-orchestrator evaluate all
@migration-orchestrator convert all
@migration-orchestrator migrate all    ← full pipeline
@migration-orchestrator status
@migration-orchestrator retry failed
```

The orchestrator dispatches one sub-agent per file (up to 5 in parallel), tracks state via the extension, and aggregates results.

```mermaid
flowchart TB
    O["@migration-orchestrator\nscan → plan → dispatch → collect"]
    O --> S1["sub-agent 1\nfile_a.sql"]
    O --> S2["sub-agent 2\nfile_b.sql"]
    O --> S3["sub-agent 3\nfile_c.sql"]
    O --> SN["sub-agent N\nfile_n.sql"]

    S1 --> P1["evaluate → convert → validate → analyze"]
    S2 --> P2["evaluate → convert → validate → analyze"]
    S3 --> P3["evaluate → convert → validate → analyze"]
    SN --> PN["evaluate → convert → validate → analyze"]
```

### Work Item State Machine

```mermaid
stateDiagram-v2
    [*] --> pending: scan_oracle_files
    pending --> in_progress: claim_work_item
    in_progress --> done: complete_work_item
    in_progress --> failed: fail_work_item
    failed --> pending: reset_work_item
    done --> pending: reset_work_item
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

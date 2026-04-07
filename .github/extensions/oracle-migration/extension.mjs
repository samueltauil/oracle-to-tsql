import { joinSession } from "@github/copilot-sdk/extension";
import { readdir, stat, readFile, writeFile, mkdir } from "node:fs/promises";
import { join, relative, basename, extname, dirname } from "node:path";
import { existsSync } from "node:fs";

const CWD = process.cwd();
const ORACLE_DIR = join(CWD, "oracle-sql");
const TSQL_DIR = join(CWD, "tsql-output");
const REPORTS_DIR = join(CWD, "migration-reports");
const STATE_FILE = join(REPORTS_DIR, ".migration-state.json");

const SQL_EXTENSIONS = new Set([".sql", ".pls", ".pks", ".pkb", ".trg", ".vw", ".fnc", ".prc", ".typ"]);
const PHASES = ["evaluate", "convert", "validate", "analyze"];
const PHASE_AGENTS = {
    evaluate: "oracle-evaluator.md",
    convert: "oracle-to-tsql.md",
    validate: "tsql-validator.md",
    analyze: "performance-analyzer.md",
};

// --- File discovery ---

async function collectSqlFiles(dir) {
    const results = [];
    if (!existsSync(dir)) return results;
    const entries = await readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
        const fullPath = join(dir, entry.name);
        if (entry.isDirectory()) {
            results.push(...(await collectSqlFiles(fullPath)));
        } else if (entry.isFile() && SQL_EXTENSIONS.has(extname(entry.name).toLowerCase())) {
            const stats = await stat(fullPath);
            const content = await readFile(fullPath, "utf-8");
            results.push({
                relPath: relative(dir, fullPath),
                size: stats.size,
                lines: content.split("\n").length,
                modified: stats.mtime.toISOString(),
            });
        }
    }
    return results;
}

// Relative path → slug for report filenames (preserves subdirs as dashes)
function pathToSlug(relPath) {
    return relPath.replace(/[\\/]/g, "--").replace(/\.[^.]+$/, "");
}

// --- Persistent state ---

async function loadState() {
    if (!existsSync(STATE_FILE)) return {};
    try {
        return JSON.parse(await readFile(STATE_FILE, "utf-8"));
    } catch {
        return {};
    }
}

async function saveState(state) {
    if (!existsSync(REPORTS_DIR)) await mkdir(REPORTS_DIR, { recursive: true });
    await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
}

// Ensure a work item exists for a file, return its entry
function ensureItem(state, relPath) {
    if (!state[relPath]) {
        state[relPath] = {
            evaluate: "pending",
            convert: "pending",
            validate: "pending",
            analyze: "pending",
        };
    }
    return state[relPath];
}

// --- Artifact paths ---

function oraclePath(relPath) {
    return join("oracle-sql", relPath);
}
function tsqlPath(relPath) {
    return join("tsql-output", relPath);
}
function reportPath(phase, relPath) {
    return join("migration-reports", `${phase}-${pathToSlug(relPath)}.md`);
}

// --- Session ---

const session = await joinSession({
    hooks: {
        onSessionStart: async () => {
            await session.log("Oracle→T-SQL Migration toolkit loaded (batch mode)");
        },
        onUserPromptSubmitted: async (input) => {
            const prompt = input.prompt.toLowerCase();
            if (
                prompt.includes("oracle") || prompt.includes("tsql") || prompt.includes("t-sql") ||
                prompt.includes("migrat") || prompt.includes("convert") ||
                prompt.includes("evaluat") || prompt.includes("validat") || prompt.includes("orchestrat")
            ) {
                const oracleFiles = await collectSqlFiles(ORACLE_DIR);
                const tsqlFiles = await collectSqlFiles(TSQL_DIR);
                if (oracleFiles.length > 0 || tsqlFiles.length > 0) {
                    return {
                        additionalContext: `Project status: ${oracleFiles.length} Oracle SQL source file(s), ${tsqlFiles.length} T-SQL output file(s). Use migration_status for detailed per-file state.`,
                    };
                }
            }
        },
    },
    tools: [
        // ── Discovery ──
        {
            name: "scan_oracle_files",
            description:
                "Scans oracle-sql/ and returns structured JSON array of all Oracle SQL files with relative path, size, lines, and modified date. Also syncs migration state for any new files.",
            parameters: { type: "object", properties: {} },
            handler: async () => {
                const files = await collectSqlFiles(ORACLE_DIR);
                if (files.length === 0) {
                    return JSON.stringify({ files: [], message: "No SQL files in oracle-sql/. Drop files there to begin." });
                }
                // Sync state for any newly discovered files
                const state = await loadState();
                for (const f of files) ensureItem(state, f.relPath);
                await saveState(state);

                return JSON.stringify({
                    count: files.length,
                    totalLines: files.reduce((s, f) => s + f.lines, 0),
                    totalSizeKB: +(files.reduce((s, f) => s + f.size, 0) / 1024).toFixed(1),
                    files: files.map((f) => ({
                        relPath: f.relPath,
                        lines: f.lines,
                        sizeKB: +(f.size / 1024).toFixed(1),
                        modified: f.modified.split("T")[0],
                    })),
                });
            },
        },

        // ── Status ──
        {
            name: "migration_status",
            description:
                "Returns structured JSON migration status for every tracked file across all phases (evaluate/convert/validate/analyze). Statuses: pending, in_progress, done, failed.",
            parameters: { type: "object", properties: {} },
            handler: async () => {
                const state = await loadState();
                const keys = Object.keys(state);
                if (keys.length === 0) {
                    return JSON.stringify({ files: [], message: "No files tracked. Run scan_oracle_files first." });
                }

                const summary = { total: keys.length, evaluate: {}, convert: {}, validate: {}, analyze: {} };
                for (const phase of PHASES) {
                    summary[phase] = { pending: 0, in_progress: 0, done: 0, failed: 0 };
                }

                const items = keys.map((relPath) => {
                    const item = state[relPath];
                    for (const phase of PHASES) summary[phase][item[phase] || "pending"]++;
                    return { relPath, ...item };
                });

                return JSON.stringify({ summary, files: items });
            },
        },

        // ── Batch planning ──
        {
            name: "generate_batch_plan",
            description:
                "Generates a batch execution plan for a given phase. Returns structured JSON with: list of work items (files needing processing), the agent prompt file to read, source/output paths for each file, and a ready-to-use sub-agent prompt template per file. Use phase 'full' to plan evaluate→convert→validate→analyze pipeline.",
            parameters: {
                type: "object",
                properties: {
                    phase: {
                        type: "string",
                        description: "Migration phase: 'evaluate', 'convert', 'validate', 'analyze', or 'full' for the complete pipeline.",
                        enum: ["evaluate", "convert", "validate", "analyze", "full"],
                    },
                },
                required: ["phase"],
            },
            handler: async (args) => {
                const state = await loadState();
                const keys = Object.keys(state);
                if (keys.length === 0) {
                    return JSON.stringify({ error: "No files tracked. Run scan_oracle_files first." });
                }

                const phases = args.phase === "full" ? PHASES : [args.phase];
                const plan = { phase: args.phase, batches: [] };

                for (const phase of phases) {
                    // Find files pending for this phase
                    // For convert/validate/analyze, require the prior phase to be done
                    const priorPhase = { convert: "evaluate", validate: "convert", analyze: "validate" }[phase];
                    const pending = keys.filter((relPath) => {
                        const item = state[relPath];
                        if ((item[phase] || "pending") !== "pending") return false;
                        if (priorPhase && item[priorPhase] !== "done") return false;
                        return true;
                    });

                    if (pending.length === 0) continue;

                    const workItems = pending.map((relPath) => {
                        const slug = pathToSlug(relPath);
                        const agentFile = `.github/agents/${PHASE_AGENTS[phase]}`;
                        const src = oraclePath(relPath);
                        const out =
                            phase === "convert"
                                ? tsqlPath(relPath)
                                : reportPath(phase, relPath);

                        // Build the sub-agent prompt
                        const priorArtifacts = [];
                        if (phase !== "evaluate") {
                            priorArtifacts.push(`- Evaluation report: ${reportPath("evaluate", relPath)}`);
                        }
                        if (phase === "validate" || phase === "analyze") {
                            priorArtifacts.push(`- Converted T-SQL: ${tsqlPath(relPath)}`);
                        }
                        if (phase === "analyze") {
                            priorArtifacts.push(`- Validation report: ${reportPath("validate", relPath)}`);
                        }

                        const prompt = [
                            `You are working on an Oracle SQL to T-SQL migration project.`,
                            ``,
                            `## Your Task`,
                            `${phase.charAt(0).toUpperCase() + phase.slice(1)} the file: \`${src}\``,
                            ``,
                            `## Instructions`,
                            `1. Read the rules file: \`.github/agents/${PHASE_AGENTS[phase]}\` — follow ALL rules described there.`,
                            `2. Read the reference tables: \`.github/copilot-instructions.md\``,
                            `3. Read the source Oracle SQL: \`${src}\``,
                            ...(priorArtifacts.length
                                ? [`4. Read prior artifacts (if they exist):`, ...priorArtifacts]
                                : []),
                            `${priorArtifacts.length ? priorArtifacts.length + 5 : 4}. Perform the ${phase} following the rules.`,
                            `${priorArtifacts.length ? priorArtifacts.length + 6 : 5}. Save output to: \`${out}\``,
                            ``,
                            `## Output Path`,
                            `\`${out}\``,
                            ...(phase === "convert"
                                ? [``, `Ensure parent directories exist before writing (use mkdir -p if needed).`]
                                : []),
                        ].join("\n");

                        return {
                            relPath,
                            phase,
                            agentFile,
                            sourcePath: src,
                            outputPath: out,
                            subAgentName: `${phase}-${slug}`,
                            subAgentDescription: `${phase.charAt(0).toUpperCase() + phase.slice(1)} ${relPath}`,
                            subAgentPrompt: prompt,
                        };
                    });

                    plan.batches.push({
                        phase,
                        fileCount: workItems.length,
                        items: workItems,
                    });
                }

                plan.totalFiles = plan.batches.reduce((s, b) => s + b.fileCount, 0);
                return JSON.stringify(plan, null, 2);
            },
        },

        // ── Work item lifecycle ──
        {
            name: "claim_work_item",
            description:
                "Marks a file+phase as 'in_progress'. Call this before dispatching a sub-agent for a file. Prevents duplicate work. Returns the work item details.",
            parameters: {
                type: "object",
                properties: {
                    relPath: { type: "string", description: "Relative path of the Oracle SQL file (e.g., 'pkg_orders.sql' or 'schemas/hr/emp.sql')." },
                    phase: { type: "string", enum: ["evaluate", "convert", "validate", "analyze"] },
                },
                required: ["relPath", "phase"],
            },
            handler: async (args) => {
                const state = await loadState();
                const item = ensureItem(state, args.relPath);
                const current = item[args.phase] || "pending";

                if (current === "in_progress") {
                    return JSON.stringify({ status: "already_claimed", relPath: args.relPath, phase: args.phase });
                }
                if (current === "done") {
                    return JSON.stringify({ status: "already_done", relPath: args.relPath, phase: args.phase });
                }

                item[args.phase] = "in_progress";
                await saveState(state);
                return JSON.stringify({ status: "claimed", relPath: args.relPath, phase: args.phase });
            },
        },
        {
            name: "complete_work_item",
            description:
                "Marks a file+phase as 'done' after a sub-agent finishes successfully. Records the output artifact path.",
            parameters: {
                type: "object",
                properties: {
                    relPath: { type: "string", description: "Relative path of the Oracle SQL file." },
                    phase: { type: "string", enum: ["evaluate", "convert", "validate", "analyze"] },
                    artifactPath: { type: "string", description: "Path to the generated output file (report or T-SQL)." },
                },
                required: ["relPath", "phase"],
            },
            handler: async (args) => {
                const state = await loadState();
                const item = ensureItem(state, args.relPath);
                item[args.phase] = "done";
                if (!item.artifacts) item.artifacts = {};
                item.artifacts[args.phase] = args.artifactPath || "";
                await saveState(state);
                return JSON.stringify({ status: "completed", relPath: args.relPath, phase: args.phase });
            },
        },
        {
            name: "fail_work_item",
            description:
                "Marks a file+phase as 'failed' when a sub-agent errors. Records the error message. The item can be retried later.",
            parameters: {
                type: "object",
                properties: {
                    relPath: { type: "string", description: "Relative path of the Oracle SQL file." },
                    phase: { type: "string", enum: ["evaluate", "convert", "validate", "analyze"] },
                    error: { type: "string", description: "Error message or reason for failure." },
                },
                required: ["relPath", "phase", "error"],
            },
            handler: async (args) => {
                const state = await loadState();
                const item = ensureItem(state, args.relPath);
                item[args.phase] = "failed";
                if (!item.errors) item.errors = {};
                item.errors[args.phase] = args.error;
                await saveState(state);
                return JSON.stringify({ status: "failed", relPath: args.relPath, phase: args.phase, error: args.error });
            },
        },
        {
            name: "reset_work_item",
            description:
                "Resets a file+phase back to 'pending' so it can be retried. Use after fixing issues or to re-run a phase.",
            parameters: {
                type: "object",
                properties: {
                    relPath: { type: "string", description: "Relative path of the Oracle SQL file." },
                    phase: { type: "string", enum: ["evaluate", "convert", "validate", "analyze"] },
                },
                required: ["relPath", "phase"],
            },
            handler: async (args) => {
                const state = await loadState();
                const item = ensureItem(state, args.relPath);
                item[args.phase] = "pending";
                if (item.errors) delete item.errors[args.phase];
                await saveState(state);
                return JSON.stringify({ status: "reset", relPath: args.relPath, phase: args.phase });
            },
        },

        // ── Reports ──
        {
            name: "list_migration_reports",
            description:
                "Lists all migration reports in migration-reports/ as structured JSON with type classification.",
            parameters: { type: "object", properties: {} },
            handler: async () => {
                if (!existsSync(REPORTS_DIR)) return JSON.stringify({ reports: [] });
                const entries = await readdir(REPORTS_DIR);
                const reports = entries
                    .filter((e) => e.endsWith(".md"))
                    .map((name) => {
                        let type = "unknown";
                        if (name.startsWith("evaluation-")) type = "evaluation";
                        else if (name.startsWith("validation-")) type = "validation";
                        else if (name.startsWith("performance-")) type = "performance";
                        else if (name.includes("summary")) type = "summary";
                        return { name, type, path: join("migration-reports", name) };
                    });
                return JSON.stringify({ count: reports.length, reports });
            },
        },

        // ── Init ──
        {
            name: "init_migration_project",
            description: "Creates oracle-sql/, tsql-output/, migration-reports/ directories and initializes empty migration state.",
            parameters: { type: "object", properties: {} },
            handler: async () => {
                const dirs = [ORACLE_DIR, TSQL_DIR, REPORTS_DIR];
                const created = [];
                for (const dir of dirs) {
                    if (!existsSync(dir)) {
                        await mkdir(dir, { recursive: true });
                        created.push(relative(CWD, dir));
                    }
                }
                if (!existsSync(STATE_FILE)) await saveState({});
                return JSON.stringify({
                    created,
                    message: created.length > 0
                        ? `Created: ${created.join(", ")}. Drop Oracle SQL files into oracle-sql/ to begin.`
                        : "Project structure already exists.",
                });
            },
        },
    ],
});

import { joinSession } from "@github/copilot-sdk/extension";
import { readdir, stat, readFile, writeFile, mkdir } from "node:fs/promises";
import { join, relative, basename, extname } from "node:path";
import { existsSync } from "node:fs";

const CWD = process.cwd();
const ORACLE_DIR = join(CWD, "oracle-sql");
const TSQL_DIR = join(CWD, "tsql-output");
const REPORTS_DIR = join(CWD, "migration-reports");

// Recursively collect all SQL files in a directory
async function collectSqlFiles(dir) {
    const results = [];
    if (!existsSync(dir)) return results;

    const entries = await readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
        const fullPath = join(dir, entry.name);
        if (entry.isDirectory()) {
            results.push(...(await collectSqlFiles(fullPath)));
        } else if (
            entry.isFile() &&
            [".sql", ".pls", ".pks", ".pkb", ".trg", ".vw", ".fnc", ".prc", ".typ"].includes(
                extname(entry.name).toLowerCase()
            )
        ) {
            const stats = await stat(fullPath);
            const content = await readFile(fullPath, "utf-8");
            const lineCount = content.split("\n").length;
            results.push({
                path: relative(CWD, fullPath),
                name: entry.name,
                size: stats.size,
                lines: lineCount,
                modified: stats.mtime.toISOString(),
            });
        }
    }
    return results;
}

const session = await joinSession({
    hooks: {
        onSessionStart: async () => {
            await session.log("Oracle→T-SQL Migration toolkit loaded");
        },
        onUserPromptSubmitted: async (input) => {
            const prompt = input.prompt.toLowerCase();
            // Auto-inject project context when migration-related prompts are detected
            if (
                prompt.includes("oracle") ||
                prompt.includes("tsql") ||
                prompt.includes("t-sql") ||
                prompt.includes("migrat") ||
                prompt.includes("convert") ||
                prompt.includes("evaluat") ||
                prompt.includes("validat")
            ) {
                let context = "";
                // Count files in each directory
                const oracleFiles = await collectSqlFiles(ORACLE_DIR);
                const tsqlFiles = await collectSqlFiles(TSQL_DIR);

                if (oracleFiles.length > 0 || tsqlFiles.length > 0) {
                    context += `\n\nProject status: ${oracleFiles.length} Oracle SQL files in oracle-sql/, ${tsqlFiles.length} T-SQL files in tsql-output/.`;
                }

                if (context) {
                    return { additionalContext: context };
                }
            }
        },
    },
    tools: [
        {
            name: "scan_oracle_files",
            description:
                "Scans the oracle-sql/ directory and returns a list of all Oracle SQL files with metadata (path, size, line count, last modified). Use this to discover what files are available for migration.",
            parameters: {
                type: "object",
                properties: {},
            },
            handler: async () => {
                const files = await collectSqlFiles(ORACLE_DIR);
                if (files.length === 0) {
                    return "No SQL files found in oracle-sql/. Drop your Oracle SQL files there to begin migration.";
                }

                const totalLines = files.reduce((sum, f) => sum + f.lines, 0);
                const totalSize = files.reduce((sum, f) => sum + f.size, 0);

                let result = `Found ${files.length} Oracle SQL file(s) (${totalLines} total lines, ${(totalSize / 1024).toFixed(1)} KB)\n\n`;
                result += "| File | Lines | Size | Modified |\n";
                result += "|------|-------|------|----------|\n";
                for (const f of files) {
                    result += `| ${f.path} | ${f.lines} | ${(f.size / 1024).toFixed(1)} KB | ${f.modified.split("T")[0]} |\n`;
                }
                return result;
            },
        },
        {
            name: "migration_status",
            description:
                "Shows the migration status of all Oracle SQL files: which have been evaluated, converted, validated, and performance-analyzed. Compares files across oracle-sql/, tsql-output/, and migration-reports/ directories.",
            parameters: {
                type: "object",
                properties: {},
            },
            handler: async () => {
                const oracleFiles = await collectSqlFiles(ORACLE_DIR);
                if (oracleFiles.length === 0) {
                    return "No Oracle SQL files found. Drop files into oracle-sql/ to begin.";
                }

                // Collect tsql output files
                const tsqlFiles = await collectSqlFiles(TSQL_DIR);
                const tsqlSet = new Set(tsqlFiles.map((f) => basename(f.name)));

                // Collect report files
                let reportFiles = [];
                if (existsSync(REPORTS_DIR)) {
                    const entries = await readdir(REPORTS_DIR);
                    reportFiles = entries.filter((e) => e.endsWith(".md"));
                }
                const reportSet = new Set(reportFiles);

                let result = `Migration Status (${oracleFiles.length} source files)\n\n`;
                result += "| Source File | Evaluated | Converted | Validated | Perf Analyzed |\n";
                result += "|------------|-----------|-----------|-----------|---------------|\n";

                let stats = { evaluated: 0, converted: 0, validated: 0, performance: 0 };

                for (const f of oracleFiles) {
                    const name = basename(f.name, extname(f.name));
                    const hasEval = reportSet.has(`evaluation-${f.name}.md`) || reportSet.has(`evaluation-${name}.md`);
                    const hasConvert = tsqlSet.has(f.name);
                    const hasValid = reportSet.has(`validation-${f.name}.md`) || reportSet.has(`validation-${name}.md`);
                    const hasPerf = reportSet.has(`performance-${f.name}.md`) || reportSet.has(`performance-${name}.md`);

                    if (hasEval) stats.evaluated++;
                    if (hasConvert) stats.converted++;
                    if (hasValid) stats.validated++;
                    if (hasPerf) stats.performance++;

                    result += `| ${f.path} | ${hasEval ? "✅" : "⬜"} | ${hasConvert ? "✅" : "⬜"} | ${hasValid ? "✅" : "⬜"} | ${hasPerf ? "✅" : "⬜"} |\n`;
                }

                result += `\nProgress: ${stats.evaluated}/${oracleFiles.length} evaluated, ${stats.converted}/${oracleFiles.length} converted, ${stats.validated}/${oracleFiles.length} validated, ${stats.performance}/${oracleFiles.length} perf-analyzed`;

                return result;
            },
        },
        {
            name: "list_migration_reports",
            description:
                "Lists all migration reports in the migration-reports/ directory with their type (evaluation, validation, performance) and summary.",
            parameters: {
                type: "object",
                properties: {},
            },
            handler: async () => {
                if (!existsSync(REPORTS_DIR)) {
                    return "No migration-reports/ directory found.";
                }

                const entries = await readdir(REPORTS_DIR);
                const reports = entries.filter((e) => e.endsWith(".md"));

                if (reports.length === 0) {
                    return "No reports found in migration-reports/. Use @oracle-evaluator, @tsql-validator, or @performance-analyzer to generate reports.";
                }

                let result = `Found ${reports.length} report(s):\n\n`;
                result += "| Report | Type |\n";
                result += "|--------|------|\n";

                for (const r of reports) {
                    let type = "Unknown";
                    if (r.startsWith("evaluation-")) type = "📋 Evaluation";
                    else if (r.startsWith("validation-")) type = "✅ Validation";
                    else if (r.startsWith("performance-")) type = "⚡ Performance";
                    else if (r.includes("summary")) type = "📊 Summary";
                    result += `| ${r} | ${type} |\n`;
                }

                return result;
            },
        },
        {
            name: "init_migration_project",
            description:
                "Initializes the migration project structure. Creates oracle-sql/, tsql-output/, and migration-reports/ directories if they don't exist. Run this once to set up the project.",
            parameters: {
                type: "object",
                properties: {},
            },
            handler: async () => {
                const dirs = [ORACLE_DIR, TSQL_DIR, REPORTS_DIR];
                const created = [];

                for (const dir of dirs) {
                    if (!existsSync(dir)) {
                        await mkdir(dir, { recursive: true });
                        created.push(relative(CWD, dir));
                    }
                }

                if (created.length === 0) {
                    return "Project structure already exists. All directories are in place:\n- oracle-sql/ (drop Oracle SQL files here)\n- tsql-output/ (converted T-SQL output)\n- migration-reports/ (evaluation, validation, performance reports)";
                }

                return `Created directories: ${created.join(", ")}\n\nProject ready! Drop Oracle SQL files into oracle-sql/ and use the migration agents:\n- @oracle-evaluator → evaluate complexity\n- @oracle-to-tsql → convert to T-SQL\n- @tsql-validator → validate conversion\n- @performance-analyzer → optimize performance`;
            },
        },
    ],
});

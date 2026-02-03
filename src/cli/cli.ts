#!/usr/bin/env bun
// Manuscript CLI - ms command

import { parseArgs } from "util";
import * as fs from "fs/promises";
import * as path from "path";
import { Glob } from "bun";
import { compile, check, formatErrors, type CompileOptions } from "./compiler";
import { __ms_runtime } from "../runtime/runtime";

const VERSION = "0.1.0";

const HELP = `
Manuscript v${VERSION} - A language for AI agents

Usage:
  ms <command> [options] [files...]

Commands:
  run <file>       Compile and run a Manuscript file
  check <files>    Type check files without running
  test [pattern]   Run tests matching pattern (default: **/*.test.ms)
  build <files>    Compile to JavaScript
  emit <file>      Print compiled JavaScript to stdout
  repl             Start interactive REPL

Options:
  -h, --help       Show this help message
  -v, --version    Show version
  -o, --output     Output file/directory for build
  -w, --watch      Watch for changes and recompile
  --no-typecheck   Skip type checking
  --emit-ast       Output AST as JSON
  --quiet          Suppress non-error output

Examples:
  ms run main.ms
  ms check src/**/*.ms
  ms test
  ms build src/*.ms -o dist/
  ms emit main.ms
`;

interface CLIOptions {
  help: boolean;
  version: boolean;
  output?: string;
  watch: boolean;
  noTypecheck: boolean;
  emitAst: boolean;
  quiet: boolean;
}

function parseOptions(args: string[]): { command: string; files: string[]; options: CLIOptions } {
  const { values, positionals } = parseArgs({
    args,
    options: {
      help: { type: "boolean", short: "h", default: false },
      version: { type: "boolean", short: "v", default: false },
      output: { type: "string", short: "o" },
      watch: { type: "boolean", short: "w", default: false },
      "no-typecheck": { type: "boolean", default: false },
      "emit-ast": { type: "boolean", default: false },
      quiet: { type: "boolean", short: "q", default: false },
    },
    allowPositionals: true,
    strict: false,
  });

  const command = positionals[0] || "";
  const files = positionals.slice(1);

  return {
    command,
    files,
    options: {
      help: values.help as boolean,
      version: values.version as boolean,
      output: values.output as string | undefined,
      watch: values.watch as boolean,
      noTypecheck: values["no-typecheck"] as boolean,
      emitAst: values["emit-ast"] as boolean,
      quiet: values.quiet as boolean,
    },
  };
}

function log(message: string, options: CLIOptions): void {
  if (!options.quiet) {
    console.log(message);
  }
}

function error(message: string): void {
  console.error(`\x1b[31merror:\x1b[0m ${message}`);
}

function success(message: string): void {
  console.log(`\x1b[32m${message}\x1b[0m`);
}

async function readFile(filepath: string): Promise<string> {
  try {
    return await fs.readFile(filepath, "utf-8");
  } catch (e) {
    throw new Error(`Cannot read file: ${filepath}`);
  }
}

async function globFiles(patterns: string[]): Promise<string[]> {
  const files: string[] = [];
  
  for (const pattern of patterns) {
    if (pattern.includes("*")) {
      const glob = new Glob(pattern);
      for await (const file of glob.scan({ cwd: process.cwd() })) {
        if (file.endsWith(".ms")) {
          files.push(file);
        }
      }
    } else {
      files.push(pattern);
    }
  }
  
  return [...new Set(files)]; // Dedupe
}

// ============================================
// Commands
// ============================================

async function runCommand(files: string[], options: CLIOptions): Promise<number> {
  if (files.length === 0) {
    error("No file specified. Usage: ms run <file>");
    return 1;
  }

  const filepath = files[0]!;
  
  try {
    const source = await readFile(filepath);
    const result = compile(source, {
      filename: filepath,
      typeCheck: !options.noTypecheck,
      emitRuntimeImport: false, // We inject runtime via Function arguments
    });

    if (!result.success) {
      console.error(formatErrors(result.errors, source));
      return 1;
    }

    if (options.emitAst) {
      console.log(JSON.stringify(result.ast, null, 2));
      return 0;
    }

    // Execute the compiled code
    const code = result.code!;
    
    // Create a module with runtime injected
    // Wrap in async IIFE to support top-level await
    const wrappedCode = `const __ms_runtime = arguments[0];
return (async () => {
${code}
})();`;
    
    const fn = new Function(wrappedCode);
    await fn(__ms_runtime);
    
    // Run any pending tests
    if (__ms_runtime.getTestCount() > 0) {
      __ms_runtime.runTests();
    }
    
    return 0;
  } catch (e: any) {
    error(e.message);
    return 1;
  }
}

async function checkCommand(files: string[], options: CLIOptions): Promise<number> {
  if (files.length === 0) {
    error("No files specified. Usage: ms check <files...>");
    return 1;
  }

  const resolvedFiles = await globFiles(files);
  
  if (resolvedFiles.length === 0) {
    error("No .ms files found matching the pattern");
    return 1;
  }

  let hasErrors = false;
  let totalErrors = 0;
  let checkedCount = 0;

  for (const filepath of resolvedFiles) {
    try {
      const source = await readFile(filepath);
      const result = check(source, { filename: filepath });

      if (!result.success) {
        hasErrors = true;
        totalErrors += result.errors.length;
        console.error(formatErrors(result.errors, source));
      } else {
        log(`\x1b[32m✓\x1b[0m ${filepath}`, options);
      }
      checkedCount++;
    } catch (e: any) {
      error(`${filepath}: ${e.message}`);
      hasErrors = true;
    }
  }

  console.log();
  if (hasErrors) {
    error(`Found ${totalErrors} error(s) in ${checkedCount} file(s)`);
    return 1;
  } else {
    success(`Checked ${checkedCount} file(s) with no errors`);
    return 0;
  }
}

async function testCommand(files: string[], options: CLIOptions): Promise<number> {
  // Default pattern for test files
  const patterns = files.length > 0 ? files : ["**/*.test.ms"];
  const resolvedFiles = await globFiles(patterns);

  if (resolvedFiles.length === 0) {
    log("No test files found", options);
    return 0;
  }

  log(`Running ${resolvedFiles.length} test file(s)...\n`, options);

  let totalTests = 0;
  let passedTests = 0;
  let failedTests = 0;
  const failures: { file: string; name: string; error: string }[] = [];

  for (const filepath of resolvedFiles) {
    try {
      const source = await readFile(filepath);
      const result = compile(source, {
        filename: filepath,
        typeCheck: !options.noTypecheck,
        emitRuntimeImport: false, // We inject runtime via Function arguments
      });

      if (!result.success) {
        console.error(formatErrors(result.errors, source));
        failedTests++;
        continue;
      }

      // Clear previous tests
      __ms_runtime.clearTests();

      // Execute to register tests
      const code = result.code!;
      const wrappedCode = `
        const __ms_runtime = arguments[0];
        ${code}
      `;
      
      const fn = new Function(wrappedCode);
      await fn(__ms_runtime);

      // Run tests and collect results
      const testResults = await __ms_runtime.runTestsWithResults();
      
      for (const test of testResults) {
        totalTests++;
        if (test.passed) {
          passedTests++;
          log(`  \x1b[32m✓\x1b[0m ${test.name}`, options);
        } else {
          failedTests++;
          log(`  \x1b[31m✗\x1b[0m ${test.name}`, options);
          failures.push({ file: filepath, name: test.name, error: test.error || "Unknown error" });
        }
      }
    } catch (e: any) {
      error(`${filepath}: ${e.message}`);
      failedTests++;
    }
  }

  console.log();

  // Print failures
  if (failures.length > 0) {
    console.log("\x1b[31mFailures:\x1b[0m\n");
    for (const failure of failures) {
      console.log(`  ${failure.file} > ${failure.name}`);
      console.log(`    ${failure.error}\n`);
    }
  }

  // Summary
  if (failedTests > 0) {
    console.log(`\x1b[31m${failedTests} failed\x1b[0m, \x1b[32m${passedTests} passed\x1b[0m, ${totalTests} total`);
    return 1;
  } else {
    success(`${passedTests} passed, ${totalTests} total`);
    return 0;
  }
}

async function buildCommand(files: string[], options: CLIOptions): Promise<number> {
  if (files.length === 0) {
    error("No files specified. Usage: ms build <files...> [-o output]");
    return 1;
  }

  const resolvedFiles = await globFiles(files);
  
  if (resolvedFiles.length === 0) {
    error("No .ms files found matching the pattern");
    return 1;
  }

  const outputDir = options.output || "dist";
  
  // Create output directory
  await fs.mkdir(outputDir, { recursive: true });

  let hasErrors = false;

  for (const filepath of resolvedFiles) {
    try {
      const source = await readFile(filepath);
      const result = compile(source, {
        filename: filepath,
        typeCheck: !options.noTypecheck,
      });

      if (!result.success) {
        hasErrors = true;
        console.error(formatErrors(result.errors, source));
        continue;
      }

      // Use basename for absolute paths to avoid nested directories
      const outputName = path.isAbsolute(filepath) 
        ? path.basename(filepath)
        : filepath;

      if (options.emitAst) {
        const astPath = path.join(outputDir, outputName.replace(/\.ms$/, ".ast.json"));
        await fs.mkdir(path.dirname(astPath), { recursive: true });
        await fs.writeFile(astPath, JSON.stringify(result.ast, null, 2));
        log(`\x1b[32m✓\x1b[0m ${filepath} → ${astPath}`, options);
      } else {
        const outPath = path.join(outputDir, outputName.replace(/\.ms$/, ".js"));
        await fs.mkdir(path.dirname(outPath), { recursive: true });
        await fs.writeFile(outPath, result.code!);
        log(`\x1b[32m✓\x1b[0m ${filepath} → ${outPath}`, options);
      }
    } catch (e: any) {
      error(`${filepath}: ${e.message}`);
      hasErrors = true;
    }
  }

  return hasErrors ? 1 : 0;
}

async function emitCommand(files: string[], options: CLIOptions): Promise<number> {
  if (files.length === 0) {
    error("No file specified. Usage: ms emit <file>");
    return 1;
  }

  const filepath = files[0]!;

  try {
    const source = await readFile(filepath);
    const result = compile(source, {
      filename: filepath,
      typeCheck: !options.noTypecheck,
    });

    if (!result.success) {
      console.error(formatErrors(result.errors, source));
      return 1;
    }

    if (options.emitAst) {
      console.log(JSON.stringify(result.ast, null, 2));
    } else {
      console.log(result.code);
    }

    return 0;
  } catch (e: any) {
    error(e.message);
    return 1;
  }
}

async function replCommand(options: CLIOptions): Promise<number> {
  console.log(`Manuscript v${VERSION} REPL`);
  console.log("Type expressions to evaluate, or :help for commands\n");

  const readline = await import("readline");
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const prompt = () => {
    rl.question("\x1b[36mms>\x1b[0m ", async (line) => {
      line = line.trim();

      if (line === ":quit" || line === ":q") {
        rl.close();
        return;
      }

      if (line === ":help" || line === ":h") {
        console.log(`
Commands:
  :help, :h     Show this help
  :quit, :q     Exit REPL
  :clear        Clear screen
  :ast <code>   Show AST for expression
`);
        prompt();
        return;
      }

      if (line === ":clear") {
        console.clear();
        prompt();
        return;
      }

      if (line.startsWith(":ast ")) {
        const code = line.slice(5);
        const result = compile(code, { typeCheck: false });
        if (result.success) {
          console.log(JSON.stringify(result.ast, null, 2));
        } else {
          console.error(formatErrors(result.errors, code));
        }
        prompt();
        return;
      }

      if (!line) {
        prompt();
        return;
      }

      // Try to compile and run
      try {
        // Wrap expression in a print if it's not a statement
        let code = line;
        if (!line.includes("let ") && !line.includes("var ") && !line.includes("fn ")) {
          code = `print(${line})`;
        }

        const result = compile(code, { 
          typeCheck: !options.noTypecheck,
          emitRuntimeImport: false, // We inject runtime via Function arguments
        });

        if (!result.success) {
          console.error(formatErrors(result.errors, code));
        } else {
          const wrappedCode = `
            const __ms_runtime = arguments[0];
            ${result.code}
          `;
          const fn = new Function(wrappedCode);
          await fn(__ms_runtime);
        }
      } catch (e: any) {
        console.error(`Error: ${e.message}`);
      }

      prompt();
    });
  };

  prompt();

  return new Promise((resolve) => {
    rl.on("close", () => resolve(0));
  });
}

// ============================================
// Main
// ============================================

async function main(): Promise<number> {
  const { command, files, options } = parseOptions(process.argv.slice(2));

  if (options.help || command === "help") {
    console.log(HELP);
    return 0;
  }

  if (options.version) {
    console.log(`Manuscript v${VERSION}`);
    return 0;
  }

  switch (command) {
    case "run":
      return runCommand(files, options);
    case "check":
      return checkCommand(files, options);
    case "test":
      return testCommand(files, options);
    case "build":
      return buildCommand(files, options);
    case "emit":
      return emitCommand(files, options);
    case "repl":
      return replCommand(options);
    case "":
      console.log(HELP);
      return 0;
    default:
      // If no command but a .ms file is provided, run it
      if (command.endsWith(".ms")) {
        return runCommand([command, ...files], options);
      }
      error(`Unknown command: ${command}`);
      console.log(HELP);
      return 1;
  }
}

// Run CLI
main().then((code) => {
  process.exit(code);
}).catch((e) => {
  console.error(e);
  process.exit(1);
});

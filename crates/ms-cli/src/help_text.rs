//! The `ms help` text.

pub const HELP: &str = r#"Usage: ms <command> [arguments] [options]
       ms help [command]

Manuscript checks, builds, and runs .ms source and ms.toml projects.

Commands:
  check          Parse and type-check without executing
  lint           Check source hygiene and semantic lint rules
  build          Build a native executable
  emit           Emit the lowered intermediate code as text
  run            Build and run an application
  test           Execute test blocks, including imported modules
  fmt            Format source files or a project
  verify         Run check, fmt --check, lint, and test; one result
  inspect        Emit checked source metadata as JSON
  diagram        Emit a static call graph as ascii or Mermaid
  review         Report where to look: project map, or the semantic effect of a diff
  profile        Run with sampling profile capture: folded stacks, pprof, top report
  init           Create a new project with a manifest, entry, test, and .gitignore
  lsp            Serve the language server on stdin/stdout
  search_symbol  Find a project or standard-library symbol: definition, type, uses
  guide          Print the language cheat sheet, or explain diagnostic codes
  help           Show help for a command
  version        Print the compiler version

Options:
  -h, --help  Show help
  --version   Print the compiler version

Native build levels:
  --build-type <Debug|Release|MinSizeRel>
  Default: Release

Start with:
  ms init hello
  ms check ms.toml
  ms run ms.toml -- first second

Bare ms prints this help and exits successfully.
Long options that take values also accept --flag=value.
Run 'ms help <command>' or 'ms <command> --help' for usage and examples.
Builds link with the linker bundled in ms on every platform; no C compiler or SDK is needed.
MANUSCRIPT_CACHE_DIR selects the user cache for standalone run/test/profile artifacts.
"#;

pub const HELP_CHECK: &str = r#"Usage: ms check <file.ms|directory|ms.toml>... [--json] [--watch] [--fix]

Parse, resolve imports, and type-check independent inputs without executing source.
A project directory selects ms.toml and checks all source modules, discovered tests, and its entry signature.
Standalone directories discover .ms files recursively, skipping hidden/vendor/node_modules directories, directory symlinks, and nested projects.
Each input retains its own import root; pass nested projects explicitly. Use -- before flag-like filenames.

Options:
  --json  Emit versioned JSON diagnostics instead of terminal messages
  --watch Recheck after each saved change to an input or loaded module (no --json)
  --fix   Apply machine-applicable fixes (the `fix` field of --json diagnostics) in place, then report what remains (no --watch)
  -h, --help  Show this help without executing the command

Examples:
  ms check main.ms --watch
  ms check main.ms
  ms check ms.toml --json
  ms check src utilities.ms --json
"#;

pub const HELP_LINT: &str = r#"Usage: ms lint <file.ms|directory|ms.toml>... [--json] [--watch] [--fix]

Check source hygiene and semantic lint rules in independent inputs and their imports.
A project directory selects ms.toml; standalone directories discover .ms files recursively.
Discovery skips hidden/vendor/node_modules directories, directory symlinks, and nested projects.
Each input retains its own import root; pass nested projects explicitly. Use -- before flag-like filenames.
Exit status is 1 when any input fails checking or has lint findings.

Options:
  --json  Emit versioned JSON findings with stable rule codes
  --watch Recheck after each saved change to an input or loaded module (no --json)
  --fix   Apply machine-applicable fixes (the `fix` field of --json diagnostics) in place, then report what remains (no --watch)
  -h, --help  Show this help without executing the command

Examples:
  ms lint ms.toml
  ms lint main.ms --json
  ms lint src utilities.ms --json
"#;

pub const HELP_BUILD: &str = r#"Usage: ms build <file.ms|ms.toml> [--json] [-o output] [--build-type level]

Build an application exporting main() -> Int as a native executable.
Builds link with the linker bundled in ms on every platform; no C compiler or SDK is needed.

Options:
  -o, --output <path>  Executable path (default: ./program; ./program.exe on Windows)
  --json              Emit one versioned build result and artifact inventory
  --build-type <level>  Debug, Release, or MinSizeRel (case-insensitive)
  --link <file>         Link an object or static library that defines `extern fn` symbols (repeatable)
  Default build type: Release
  -h, --help  Show this help without executing the command

Examples:
  ms build ms.toml -o hello
  ms build main.ms --build-type MinSizeRel
"#;

pub const HELP_EMIT: &str = r#"Usage: ms emit <file.ms|ms.toml> [-o output] [--json]

Emit the lowered intermediate code of the program as text.

Options:
  -o, --output <path>  Write output to a file (default: stdout)
  --json               On failure, emit versioned JSON diagnostics instead of terminal messages
  -h, --help  Show this help without executing the command

Examples:
  ms emit main.ms
  ms emit ms.toml -o main.mir
"#;

pub const HELP_RUN: &str = r#"Usage: ms run <file.ms|ms.toml> [--json] [options] [-- program arguments]

Build a temporary executable and run its exported main() -> Int.
Arguments after -- are passed unchanged to the application; its exit status is returned.
Builds link with the linker bundled in ms on every platform; no C compiler or SDK is needed.

Options:
  --json                Capture output and emit one versioned result; a runtime fault is reported as data (no --watch)
  --watch               Rebuild and restart after each saved source change
  --build-type <level>  Debug, Release, or MinSizeRel (case-insensitive)
  --link <file>         Link an object or static library that defines `extern fn` symbols (repeatable)
  Default build type: Release
  -h, --help  Show this help without executing the command

Examples:
  ms run ms.toml -- first second
  ms run main.ms --watch
"#;

pub const HELP_TEST: &str = r#"Usage: ms test <file.ms|ms.toml> [--json] [--filter text] [--timeout duration] [--build-type level] [--watch] [-- program arguments]

Build and execute test blocks in the module and its imported modules.
Tests run with the project directory (or the test file's directory) as the working directory, so relative fixture paths resolve there.
Each test prints RUN before it starts and PASS or FAIL after; a test that exceeds the timeout fails by name.
Arguments after -- are passed to the test executable; its exit status is returned.
Builds link with the linker bundled in ms on every platform; no C compiler or SDK is needed.

Options:
  --json              Emit one versioned result; stdout is captured, stderr stays live (no --watch)
  --filter <text>      Run only tests whose module::name contains text
  --timeout <duration> Fail a test that runs longer (default 60s; 0 disables)
  --test <full-name>   Select exact module::name (repeatable)
  --match <regex>      Include names matching a regular expression
  --exclude <regex>    Exclude names matching a regular expression
  --list              List selected tests without running them
  --fail-fast         Stop after the first failed test
  --repeat <count>     Run the selected tests count times
  --shuffle <seed>     Shuffle with a reproducible integer seed
  --runs <count>       Cases per property test from @std/test/property.ms (default 100)
  --seed <seed>        Start property tests at this integer seed to replay a failure
  --fuzz <duration>    Run each property for this long, with fresh seeds, instead of a fixed case count; disables the default --timeout
  --watch              Rebuild and rerun after each saved source change
  --build-type <level>  Debug, Release, or MinSizeRel (case-insensitive)
  --link <file>         Link an object or static library that defines `extern fn` symbols (repeatable)
  Default build type: Release
  -h, --help  Show this help without executing the command

Examples:
  ms test test.ms
  ms test ms.toml --fuzz 30s
  ms test ms.toml --seed 1234 --filter "sorting"
  ms test ms.toml --build-type Debug
  ms test ms.toml --filter "nick collisions" --timeout 10s
"#;

pub const HELP_FMT: &str = r#"Usage: ms fmt <file.ms|directory|ms.toml>... [--check [--json]] [--drop-labels]

Format selected source files in place, preserving their file permissions.
Directories are recursive; projects include all source modules and test files.
Discovery skips hidden, vendor, and node_modules directories.

Options:
  --check  Leave files unchanged; report every unformatted file and exit 1
  --json   Emit versioned file statuses and diagnostics; requires --check
  --drop-labels  Also remove redundant argument labels such as key: key where the call binds the same parameter by position; needs source that checks
  -h, --help  Show this help without executing the command

Examples:
  ms fmt main.ms
  ms fmt ms.toml --check
  ms fmt src test.ms
  ms fmt src/*.ms --check
"#;

pub const HELP_VERIFY: &str = r#"Usage: ms verify [file.ms|directory|ms.toml] [--json] [--no-test]

Run check, fmt --check, lint, and test on one target and report every step together.
The target defaults to ms.toml. Lint and test are skipped when check fails; fmt always runs.
With --json the document holds one entry per step with its status, exit code, and that command's own --json result.
Exit status is 1 when any step fails.

Options:
  --json     Emit one versioned result with every step
  --no-test  Skip the test step (it builds a native executable)
  -h, --help  Show this help without executing the command

Examples:
  ms verify
  ms verify ms.toml --json
  ms verify src/main.ms --no-test
"#;

pub const HELP_INSPECT: &str = r#"Usage: ms inspect <file.ms|ms.toml> [-o output] [--json]

Emit checked symbols, source hashes, call sites, and statement spans as JSON.

Options:
  -o, --output <path>  Write output to a file (default: stdout)
  --json               On failure, emit versioned JSON diagnostics instead of terminal messages
  -h, --help  Show this help without executing the command

Examples:
  ms inspect main.ms
  ms inspect ms.toml -o inspection.json
"#;

pub const HELP_DIAGRAM: &str = r#"Usage: ms diagram <file.ms|ms.toml> [--view calls|effects|errors|modules|flow|scope|tasks] [--entity name] [--depth n] [--diff <file|->] [--format ascii|mermaid] [-o output] [--json]

Emit the checked static call graph of project declarations; standard calls are boundary leaves.
The default ascii outline is plain text with a fixed order;
mermaid is a flowchart for rendering. --view or --entity switch to one question's tree:
calls (who is called), effects (where effects enter), errors (error types and try sites),
modules (imports), flow (one function's ordered steps), scope (its cleanup scopes and exits),
tasks (its task groups and the work each spawn starts). flow, scope and tasks need --entity. --entity roots the tree at one declaration (name, file::name, or full entity ID; a module
path for modules) and --depth bounds expansion (default 3, at most 200 nodes).

Options:
  --view <name>        calls, effects, errors, modules, flow, scope, or tasks (default calls with --entity)
  --entity <name>      Root the view at one declaration or module
  --depth <n>          Expansion depth for a view (default 3)
  --diff <path|->      Mark what a unified diff changed in the view (tree is the after state)
  --format <name>      ascii (default) or mermaid
  -o, --output <path>  Write output to a file (default: stdout)
  --json               Emit a versioned diagram tree with source IDs and locations (default: calls view)
  -h, --help  Show this help without executing the command

Examples:
  ms diagram main.ms
  ms diagram ms.toml --format mermaid -o calls.mmd
  ms diagram ms.toml --view effects --entity save
  ms diagram ms.toml --view errors
  ms diagram ms.toml --view flow --entity main --depth 2
  ms diagram ms.toml --view flow --entity save --diff change.patch
  ms diagram ms.toml --view flow --entity save --json
"#;

pub const HELP_REVIEW: &str = r#"Usage: ms review <file.ms|ms.toml> [--diff <file|->] [--explain n|id] [--format ascii|markdown] [--json] [--all] [-o output]

Print a fixed-template report of where to look. Without --diff it maps the project:
public surface, entry points with effects, error types, resources, imports.
With a unified diff it compares the checked program before and after the change and
ranks entities by contract, effect, error-flow, and resource changes and their reach.
ms never runs git: pipe the diff in. The tree must be the diff's after state; the
before state is rebuilt from the diff and verified. Output is deterministic, with no
timestamps, absolute paths, or generated prose, and ends with a digest.

Options:
  --diff <path|->      Unified diff to review (- reads standard input)
  --format <name>      ascii (default) or markdown
  --json               Emit the complete report or explanation as versioned JSON (not with --format)
  --explain <n|id>     Show one finding in full: score terms, evidence, callers (needs --diff)
  --all                Show every row instead of the first five per section
  -o, --output <path>  Write output to a file (default: stdout)
  -h, --help  Show this help without executing the command

Examples:
  ms review ms.toml
  git diff --no-renames main... | ms review ms.toml --diff -
  ms review ms.toml --diff change.patch --format markdown
  ms review ms.toml --diff change.patch --explain 1
  ms review ms.toml --diff change.patch --explain 1 --json
"#;

pub const HELP_INIT: &str = r#"Usage: ms init [directory]

Create a runnable project in the directory (default: the current directory).
Writes ms.toml, src/main.ms (a hello program), test.ms, and a .gitignore that
excludes the .ms-cache/ build cache. An existing file is never overwritten; the
command fails before writing anything when ms.toml, src/main.ms, or test.ms exist.

Keep .ms-cache/ out of version control.

Options:
  -h, --help  Show this help without creating files

Examples:
  ms init
  ms init hello
  cd hello && ms run ms.toml -- first second
"#;

pub const HELP_LSP: &str = r#"Usage: ms lsp

Serve the language server over stdin/stdout until the client disconnects.
Configure an LSP-capable editor to launch ms lsp. No file argument is needed.

Options:
  -h, --help  Show this help without executing the command

Examples:
  ms lsp
"#;

pub const HELP_SEARCH_SYMBOL: &str = r#"Usage: ms search_symbol [<name or words>... | <path>] [--limit n] [--json]

Find a symbol, in the project or the standard library. Matching ignores case
and tolerates partial names, small typos, missing underscores, and plain words
(read file lines). Exact names rank first.
  A project match prints its definition, type, description, and uses.
  A standard-library match prints its signature and a path for details.
  A lone module or declaration path shows its page, in bounded size:
    ms search_symbol                 Standard modules, each with a few names
    ms search_symbol json            One module: a line per declaration
    ms search_symbol prelude.List    A declaration with its members
    ms search_symbol prelude.List.sorted
                                     One member's signature and doc
Run it from the project directory, or any folder under its ms.toml.

Options:
  --limit <n>  Maximum matches (default 5, at most 10)
  --json       Always search, and emit versioned JSON
  -h, --help   Show this help

Examples:
  ms search_symbol parse_config
  ms search_symbol read file lines
  ms search_symbol json.parse
"#;

pub const HELP_GUIDE: &str = r#"Usage: ms guide [code...] [--json]

Print the language cheat sheet: syntax, types, errors, a checked example
program, and common mistakes beside their fixes. Look symbols up with ms search_symbol.

With diagnostic codes from ms check --json, print each code's rule family and
usual repair instead. Apply the diagnostic's own fix field first when it has one.

Options:
  --json      Emit versioned JSON (with codes)
  -h, --help  Show this help

Examples:
  ms guide
  ms guide MS3060
  ms guide MS2001 MS3050 --json
"#;

pub const HELP_HELP: &str = r#"Usage: ms help [command]

Show the command list, or detailed usage for one command.

Options:
  -h, --help  Show this help without executing the command

Examples:
  ms help
  ms help run
"#;

pub const HELP_VERSION: &str = r#"Usage: ms version

Print the compiler version. Equivalent to ms --version. Takes no arguments.

Options:
  -h, --help  Show this help without executing the command

Examples:
  ms version
  ms --version
"#;

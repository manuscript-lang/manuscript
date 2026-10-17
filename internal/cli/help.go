package cli

import (
	"fmt"
	"os"
)

const help = `Usage: ms <command> [arguments] [options]
       ms help [command]

Manuscript checks, builds, and runs .ms source and ms.toml projects.

Commands:
  check          Parse and type-check without executing
  lint           Check source hygiene and semantic lint rules
  build          Build a native executable
  emit           Emit standalone Go source with the runtime
  run            Build and run an application
  test           Execute test blocks, including imported modules
  fmt            Format source files or a project
  verify         Run check, fmt --check, lint, and test; one result
  inspect        Emit checked source metadata as JSON
  diagram        Emit a static call graph as ascii or Mermaid
  review         Report where to look: project map, or the semantic effect of a diff
  profile        Run with CPU and heap capture; optionally trace
  pprof          Inspect captured CPU or heap profiles
  trace          Inspect captured execution traces
  debug          Start an application in the embedded Delve debugger
  dap            Serve one native debugger session on stdin/stdout
  init           Create a new project with a manifest, entry, test, and .gitignore
  lsp            Serve the language server on stdin/stdout
  search_symbol  Find a project or standard-library symbol: definition, type, uses
  guide          Print the language cheat sheet
  help           Show help for a command
  version        Print the compiler version

Options:
  -h, --help  Show help
  --version   Print the compiler version

Native build levels:
  --build-type <Debug|Release|RelWithDebInfo|MinSizeRel>
  Default: Release; profile and profiled tests default to RelWithDebInfo; debug always uses Debug

Start with:
  ms init hello
  ms check ms.toml
  ms run ms.toml -- first second

Bare ms prints this help and exits successfully.
Long options that take values also accept --flag=value.
Run 'ms help <command>' or 'ms <command> --help' for usage and examples.
The Go toolchain is embedded and cannot be replaced by external tools.
MANUSCRIPT_CACHE_DIR selects the user cache for bundled toolchains
and standalone run/test/debug/profile artifacts.
`

// Keep command usage next to its explanation so flags and defaults are visible
// without running the compiler or initializing an external tool.
func commandHelp(command string) (string, bool) {
	var usage, description, options, examples string
	switch command {
	case "check":
		usage = "<file.ms|directory|ms.toml>... [--json] [--watch]"
		description = "Parse, resolve imports, and type-check independent inputs without executing source.\nA project directory selects ms.toml and checks all source modules, discovered tests, and its entry signature.\nStandalone directories discover .ms files recursively, skipping hidden/vendor/node_modules directories, directory symlinks, and nested projects.\nEach input retains its own import root; pass nested projects explicitly. Use -- before flag-like filenames."
		options = "  --json  Emit versioned JSON diagnostics instead of terminal messages\n  --watch Recheck after each saved change to an input or loaded module (no --json)\n"
		examples = "ms check main.ms --watch\n  ms check main.ms\n  ms check ms.toml --json\n  ms check src utilities.ms --json"
	case "lint":
		usage = "<file.ms|directory|ms.toml>... [--json] [--watch]"
		description = "Check source hygiene and semantic lint rules in independent inputs and their imports.\nA project directory selects ms.toml; standalone directories discover .ms files recursively.\nDiscovery skips hidden/vendor/node_modules directories, directory symlinks, and nested projects.\nEach input retains its own import root; pass nested projects explicitly. Use -- before flag-like filenames.\nExit status is 1 when any input fails checking or has lint findings."
		options = "  --json  Emit versioned JSON findings with stable rule codes\n  --watch Recheck after each saved change to an input or loaded module (no --json)\n"
		examples = "ms lint ms.toml\n  ms lint main.ms --json\n  ms lint src utilities.ms --json"
	case "build":
		usage = "<file.ms|ms.toml> [--json] [-o output] [--build-type level] [--debug]"
		description = "Build an application exporting main() -> Int as a native executable."
		options = "  -o, --output <path>  Executable path (default: ./program; ./program.exe on Windows)\n  --json              Emit one versioned build result and artifact inventory\n  --debug             Alias for --build-type Debug\n"
		examples = "ms build ms.toml -o hello\n  ms build main.ms --build-type MinSizeRel"
	case "emit":
		usage = "<file.ms|ms.toml> [-o output] [--json]"
		description = "Emit standalone Go source containing the runtime. No Go toolchain is needed."
		options = outputHelp + jsonErrorsHelp
		examples = "ms emit main.ms\n  ms emit ms.toml -o main.go"
	case "run":
		usage = "<file.ms|ms.toml> [options] [-- program arguments]"
		description = "Build a temporary executable and run its exported main() -> Int.\nArguments after -- are passed unchanged to the application; its exit status is returned."
		options = "  --debug               Alias for --build-type Debug\n  --watch               Rebuild and restart after each saved source change\n  --cpu-profile <path>  Write a CPU profile\n  --heap-profile <path> Write a heap profile\n  --trace <path>        Write an execution trace\n"
		examples = "ms run ms.toml -- first second\n  ms run main.ms --watch\n  ms run main.ms --cpu-profile cpu.pprof"
	case "test":
		usage = "<file.ms|ms.toml> [--json] [--filter text] [--timeout duration] [--build-type level] [--debug] [--watch] [-- program arguments]"
		description = "Build and execute test blocks in the module and its imported modules.\nTests run with the project directory (or the test file's directory) as the working directory, so relative fixture paths resolve there.\nEach test prints RUN before it starts and PASS or FAIL after; a test that exceeds the timeout fails by name.\nArguments after -- are passed to the test executable; its exit status is returned."
		options = "  --json              Emit one versioned result; stdout is captured, stderr stays live (no --watch)\n  --filter <text>      Run only tests whose module::name contains text\n  --timeout <duration> Fail a test that runs longer (default 60s; 0 disables)\n  --test <full-name>   Select exact module::name (repeatable)\n  --match <regex>      Include names matching a regular expression\n  --exclude <regex>    Exclude names matching a regular expression\n  --list              List selected tests without running them\n  --fail-fast         Stop after the first failed test\n  --repeat <count>     Run the selected tests count times\n  --shuffle <seed>     Shuffle with a reproducible integer seed\n  --cpu-profile <path> Write a CPU profile of selected tests\n  --heap-profile <path> Write a heap profile\n  --trace <path>       Write an execution trace\n  --debug              Alias for --build-type Debug\n  --watch              Rebuild and rerun after each saved source change\n"
		examples = "ms test test.ms\n  ms test ms.toml --debug\n  ms test ms.toml --filter \"nick collisions\" --timeout 10s"
	case "fmt":
		usage = "<file.ms|directory|ms.toml>... [--check [--json]] [--drop-labels]"
		description = "Format selected source files in place, preserving their file permissions.\nDirectories are recursive; projects include all source modules and test files.\nDiscovery skips hidden, vendor, and node_modules directories."
		options = "  --check  Leave files unchanged; report every unformatted file and exit 1\n  --json   Emit versioned file statuses and diagnostics; requires --check\n  --drop-labels  Also remove redundant argument labels such as key: key where the call binds the same parameter by position; needs source that checks\n"
		examples = "ms fmt main.ms\n  ms fmt ms.toml --check\n  ms fmt src test.ms\n  ms fmt src/*.ms --check"
	case "verify":
		usage = "[file.ms|directory|ms.toml] [--json] [--no-test]"
		description = "Run check, fmt --check, lint, and test on one target and report every step together.\nThe target defaults to ms.toml. Lint and test are skipped when check fails; fmt always runs.\nWith --json the document holds one entry per step with its status, exit code, and that command's own --json result.\nExit status is 1 when any step fails."
		options = "  --json     Emit one versioned result with every step\n  --no-test  Skip the test step (it builds a native executable)\n"
		examples = "ms verify\n  ms verify ms.toml --json\n  ms verify src/main.ms --no-test"
	case "inspect":
		usage = "<file.ms|ms.toml> [-o output] [--json]"
		description = "Emit checked symbols, source hashes, call sites, and statement spans as JSON."
		options = outputHelp + jsonErrorsHelp
		examples = "ms inspect main.ms\n  ms inspect ms.toml -o inspection.json"
	case "diagram":
		usage = "<file.ms|ms.toml> [--view calls|effects|errors|modules|flow|scope] [--entity name] [--depth n] [--diff <file|->] [--format ascii|mermaid] [-o output] [--json]"
		description = "Emit the checked static call graph. The default ascii outline is plain text with a fixed order;\nmermaid is a flowchart for rendering. --view or --entity switch to one question's tree:\ncalls (who is called), effects (where effects enter), errors (error types and try sites),\nmodules (imports), flow (one function's ordered steps), scope (its cleanup scopes and exits).\nflow and scope need --entity. --entity roots the tree at one declaration (name or file::name; a module\npath for modules) and --depth bounds expansion (default 3, at most 200 nodes)."
		options = "  --view <name>        calls, effects, errors, modules, flow, or scope (default calls with --entity)\n  --entity <name>      Root the view at one declaration or module\n  --depth <n>          Expansion depth for a view (default 3)\n  --diff <path|->      Mark what a unified diff changed in the view (tree is the after state)\n  --format <name>      ascii (default) or mermaid\n" + outputHelp + jsonErrorsHelp
		examples = "ms diagram main.ms\n  ms diagram ms.toml --format mermaid -o calls.mmd\n  ms diagram ms.toml --view effects --entity save\n  ms diagram ms.toml --view errors\n  ms diagram ms.toml --view flow --entity main --depth 2\n  ms diagram ms.toml --view flow --entity save --diff change.patch"
	case "review":
		usage = "<file.ms|ms.toml> [--diff <file|->] [--explain n|id] [--format ascii|markdown|json] [--all] [-o output]"
		description = "Print a fixed-template report of where to look. Without --diff it maps the project:\npublic surface, entry points with effects, error types, resources, imports.\nWith a unified diff it compares the checked program before and after the change and\nranks entities by contract, effect, error-flow, and resource changes and their reach.\nms never runs git: pipe the diff in. The tree must be the diff's after state; the\nbefore state is rebuilt from the diff and verified. Output is deterministic, with no\ntimestamps, absolute paths, or generated prose, and ends with a digest."
		options = "  --diff <path|->      Unified diff to review (- reads standard input)\n  --format <name>      ascii (default), markdown, or json\n  --explain <n|id>     Show one finding in full: score terms, evidence, callers (needs --diff)\n  --all                Show every row instead of the first five per section\n" + outputHelp
		examples = "ms review ms.toml\n  git diff --no-renames main... | ms review ms.toml --diff -\n  ms review ms.toml --diff change.patch --format markdown\n  ms review ms.toml --diff change.patch --explain 1"
	case "profile":
		usage = "<file.ms|ms.toml> [--json] [--out-dir directory] [--trace] [--build-type level] [-- program arguments]"
		description = "Build and run an application with CPU and heap capture.\nThe bundle contains the executable, cpu.pprof, heap.pprof, inspection.json,\nand manifest.json. Add --trace to also write trace.out. The directory must be new.\nSource labels/regions identify entry and work boundaries; CPU stacks retain nested calls.\nProfiling adds overhead; tracing can add substantial time and disk usage.\nMeasure normal execution separately. Arguments after -- go to the application; its exit status is returned."
		options = "  --out-dir <directory>    Bundle directory (default: ./profile)\n  -o, --output <directory>  Compatible aliases for --out-dir\n  --json                   Emit one versioned result; capture stdout, keep stderr live\n  --trace                  Also capture an execution trace\n"
		examples = "ms profile ms.toml\n  ms profile main.ms --out-dir capture --trace -- first second"
	case "pprof", "trace":
		usage = "[viewer options] <profile file>"
		description = "Inspect captured profiles with the embedded SDK viewer."
		examples = "ms pprof -top heap.pprof\n  ms trace -http=127.0.0.1:8080 trace.out"
	case "dap":
		description = "Serve one Delve DAP session on stdin/stdout.\nExits on disconnect, closed input, or termination."
		examples = "ms dap"
	case "debug":
		usage = "<file.ms|ms.toml> [-- program arguments]"
		description = "Build without optimization or inlining, then start the embedded Delve terminal.\nNo dlv executable is needed. On macOS, Xcode command line tools supply debugserver. Arguments after -- are passed to the application.\nWith --script or --break the session is non-interactive and reports Manuscript names, lines, and only Manuscript stack frames."
		examples = "ms debug ms.toml\n  ms debug main.ms -- first second\n  ms debug ms.toml --break src/main.ms:7 --json\n  ms debug ms.toml --script commands.txt"
	case "init":
		return initHelp, true
	case "search_symbol":
		return searchSymbolHelp, true
	case "guide":
		return guideHelp, true
	case "lsp":
		description = "Serve the language server over stdin/stdout until the client disconnects.\nConfigure an LSP-capable editor to launch ms lsp. No file argument is needed."
		examples = "ms lsp"
	case "help":
		usage = "[command]"
		description = "Show the command list, or detailed usage for one command."
		examples = "ms help\n  ms help run"
	case "version":
		description = "Print the compiler version. Equivalent to ms --version. Takes no arguments."
		examples = "ms version\n  ms --version"
	default:
		return "", false
	}
	switch command {
	case "build", "run", "test":
		options += buildTypeHelp + "  Default build type: Release\n"
	case "profile":
		options += buildTypeHelp + "  Default build type: RelWithDebInfo\n"
	case "dap":
		description = "Serve one Delve DAP session on stdin/stdout.\nExits on disconnect, closed input, or termination."
		examples = "ms dap"
	case "debug":
		usage = "<file.ms|ms.toml> [--build-type Debug] [--break location]... | --script file [--json] [-- program arguments]"
		options += "  --build-type Debug  Debug is required for Delve\n  --break <location>  Run to the first of file:line or function name, report the stop, and exit (repeatable)\n  --script <file>     Run debugger commands from a file, or - for standard input\n  --json              With --script or --break, print JSON Lines events instead of text\n  Script commands: break, clear, breakpoints, continue, next, step, stepout, stack, locals, print <name>, exit\n"
	}
	text := fmt.Sprintf("Usage: ms %s", command)
	if usage != "" {
		text += " " + usage
	}
	switch command {
	case "build", "run", "test", "profile", "debug":
		description += "\nAll builds use the embedded Go toolchain; no Go installation is needed."
	}
	return text + "\n\n" + description + "\n\nOptions:\n" + options +
		"  -h, --help  Show this help without executing the command\n\nExamples:\n  " + examples + "\n", true
}

const outputHelp = "  -o, --output <path>  Write output to a file (default: stdout)\n"

// jsonErrorsHelp documents --json on commands whose success output is not a JSON result.
const jsonErrorsHelp = "  --json               On failure, emit versioned JSON diagnostics instead of terminal messages\n"

func runHelp(args []string) int {
	if len(args) == 0 {
		fmt.Print(help)
		return 0
	}
	if len(args) == 1 {
		if usage, ok := commandHelp(args[0]); ok {
			fmt.Print(usage)
			return 0
		}
	}
	fmt.Fprintln(os.Stderr, "usage: ms help [command]")
	fmt.Fprintln(os.Stderr, "Run 'ms --help' to list commands.")
	return 2
}

func requestsHelp(command string, args []string) bool {
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--":
			return false
		case "-h", "--help":
			return true
		case "--trace":
			if command != "profile" {
				i++
			}
		case "-o", "--output", "--out-dir", "--cpu-profile", "--heap-profile", "--build-type", "--limit", "--timeout", "--filter", "--test", "--match", "--exclude", "--repeat", "--shuffle":
			// A flag value is not a help request, even if it is spelled --help.
			i++
		}
	}
	return false
}

const buildTypeHelp = "  --build-type <level>  Debug, Release, RelWithDebInfo, or MinSizeRel (case-insensitive)\n"

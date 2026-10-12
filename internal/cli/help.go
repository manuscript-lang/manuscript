package cli

import (
	"fmt"
	"os"
)

const help = `Usage: ms <command> [arguments] [options]
       ms help [command]

Manuscript checks, builds, runs, and documents .ms source and ms.toml projects.

Commands:
  check    Parse and type-check without executing
  lint     Check source hygiene and semantic lint rules
  build    Build a native executable
  emit     Emit standalone Go source with the runtime
  run      Build and run an application
  test     Execute test blocks, including imported modules
  fmt      Format a source file
  inspect  Emit checked source metadata as JSON
  diagram  Emit a static call graph as Mermaid
  profile  Run with CPU, heap, and trace capture
  debug    Start an application in Delve
  lock     Create or update project build pins
  doc      Generate public API documentation
  stdlib   Write bundled standard library declarations to a directory
  lsp      Serve the language server on stdin/stdout
  help     Show help for a command

Options:
  -h, --help  Show help
  --version   Print the compiler version

Native build levels:
  --build-type <Debug|Release|RelWithDebInfo|MinSizeRel>
  Default: Release; profile defaults to RelWithDebInfo; debug always uses Debug

Start with:
  ms check ms.toml
  ms lock ms.toml
  ms run ms.toml -- first second

Run 'ms help <command>' or 'ms <command> --help' for usage and examples.
Release binaries bundle the Go toolchain. MANUSCRIPT_GO selects another Go
executable; MANUSCRIPT_CACHE_DIR selects the bundled-toolchain cache directory.
`

// Keep command usage next to its explanation so flags and defaults are visible
// without running the compiler or initializing an external tool.
func commandHelp(command string) (string, bool) {
	var usage, description, options, examples string
	switch command {
	case "check":
		usage = "<file.ms|ms.toml> [--json]"
		description = "Parse, resolve imports, and type-check without executing source.\nA project also checks its application entry signature."
		options = "  --json  Emit versioned JSON diagnostics instead of terminal messages\n"
		examples = "ms check main.ms\n  ms check ms.toml --json"
	case "lint":
		usage = "<file.ms|ms.toml> [--json]"
		description = "Check source hygiene and semantic lint rules, including imported modules.\nExit status is 1 when lint findings are present."
		options = "  --json  Emit versioned JSON findings with stable rule codes\n"
		examples = "ms lint ms.toml\n  ms lint main.ms --json"
	case "build":
		usage = "<file.ms|ms.toml> [-o output] [--build-type level] [--debug]"
		description = "Build an application exporting main() -> Int as a native executable."
		options = "  -o, --output <path>  Executable path (default: ./program; ./program.exe on Windows)\n  --debug             Alias for --build-type Debug\n"
		examples = "ms build ms.toml -o hello\n  ms build main.ms --build-type MinSizeRel"
	case "emit":
		usage = "<file.ms|ms.toml> [-o output]"
		description = "Emit standalone Go source containing the runtime. No Go toolchain is needed."
		options = outputHelp
		examples = "ms emit main.ms\n  ms emit ms.toml -o main.go"
	case "run":
		usage = "<file.ms|ms.toml> [options] [-- program arguments]"
		description = "Build a temporary executable and run its exported main() -> Int.\nArguments after -- are passed unchanged to the application; its exit status is returned."
		options = "  --debug               Alias for --build-type Debug\n  --cpu-profile <path>  Write a CPU profile\n  --heap-profile <path> Write a heap profile\n  --trace <path>        Write an execution trace\n"
		examples = "ms run ms.toml -- first second\n  ms run main.ms --cpu-profile cpu.pprof"
	case "test":
		usage = "<file.ms|ms.toml> [--build-type level] [--debug] [-- program arguments]"
		description = "Build and execute test blocks in the module and its imported modules.\nArguments after -- are passed to the test executable; its exit status is returned."
		options = "  --debug  Alias for --build-type Debug\n"
		examples = "ms test test.ms\n  ms test ms.toml --debug"
	case "fmt":
		usage = "<file.ms> [--check]"
		description = "Format one source file in place, preserving its file permissions."
		options = "  --check  Leave the file unchanged; exit 1 if formatting is needed\n"
		examples = "ms fmt main.ms\n  ms fmt main.ms --check"
	case "inspect":
		usage = "<file.ms|ms.toml> [-o output]"
		description = "Emit checked symbols, source hashes, call sites, and statement spans as JSON."
		options = outputHelp
		examples = "ms inspect main.ms\n  ms inspect ms.toml -o inspection.json"
	case "diagram":
		usage = "<file.ms|ms.toml> [-o output]"
		description = "Emit the checked static call graph as Mermaid."
		options = outputHelp
		examples = "ms diagram main.ms\n  ms diagram ms.toml -o calls.mmd"
	case "profile":
		usage = "<file.ms|ms.toml> [-o directory] [--build-type level] [-- program arguments]"
		description = "Build and run an application with CPU, heap, and execution trace capture.\nThe bundle contains the executable, cpu.pprof, heap.pprof, trace.out,\ninspection.json, and manifest.json. The output directory must not already exist.\nArguments after -- are passed to the application; its exit status is returned."
		options = "  -o, --output <directory>  Bundle directory (default: ./profile)\n"
		examples = "ms profile ms.toml\n  ms profile main.ms -o capture -- first second"
	case "debug":
		usage = "<file.ms|ms.toml> [-- program arguments]"
		description = "Build without optimization or inlining, then start Delve with dlv exec.\nRequires Delve (dlv) on PATH. Arguments after -- are passed to the application."
		examples = "ms debug ms.toml\n  ms debug main.ms -- first second"
	case "lock":
		usage = "<ms.toml>"
		description = "Create or update project-root ms.lock with compiler/runtime, Go toolchain,\nand target pins. Run again after changing the compiler or toolchain.\nRequires a project manifest, rather than a standalone source file."
		examples = "ms lock ms.toml"
	case "doc":
		return docHelp, true
	case "stdlib":
		usage = "<directory>"
		description = "Materialize bundled standard library .ms declarations and bindings.json.\nCreate the directory if needed and replace matching files already in it.\nThese are API declarations for tooling, rather than executable implementations."
		examples = "ms stdlib ./stdlib"
	case "lsp":
		description = "Serve the language server over stdin/stdout until the client disconnects.\nConfigure an LSP-capable editor to launch ms lsp. No file argument is needed."
		examples = "ms lsp"
	case "help":
		usage = "[command]"
		description = "Show the command list, or detailed usage for one command."
		examples = "ms help\n  ms help run\n  ms doc --stdlib --help"
	default:
		return "", false
	}
	switch command {
	case "build", "run", "test":
		options += buildTypeHelp + "  Default build type: Release\n"
	case "profile":
		options += buildTypeHelp + "  Default build type: RelWithDebInfo\n"
	case "debug":
		usage = "<file.ms|ms.toml> [--build-type Debug] [-- program arguments]"
		options += "  --build-type Debug  Debug is required for Delve\n"
	}
	text := fmt.Sprintf("Usage: ms %s", command)
	if usage != "" {
		text += " " + usage
	}
	switch command {
	case "build", "run", "test", "profile", "debug", "lock":
		description += "\nRelease binaries use the bundled Go toolchain; no Go installation is needed.\nMANUSCRIPT_GO selects another Go executable. Project builds require matching\nms.lock pins; use 'ms lock ms.toml' to create or update them."
	}
	return text + "\n\n" + description + "\n\nOptions:\n" + options +
		"  -h, --help  Show this help without executing the command\n\nExamples:\n  " + examples + "\n", true
}

const outputHelp = "  -o, --output <path>  Write output to a file (default: stdout)\n"

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

func requestsHelp(args []string) bool {
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--":
			return false
		case "-h", "--help":
			return true
		case "-o", "--output", "--cpu-profile", "--heap-profile", "--trace", "--build-type":
			// A flag value is not a help request, even if it is spelled --help.
			i++
		}
	}
	return false
}

const buildTypeHelp = "  --build-type <level>  Debug, Release, RelWithDebInfo, or MinSizeRel (case-insensitive)\n"

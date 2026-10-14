package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// invocation is a source command after flag parsing and before validation.
type invocation struct {
	command, filename                  string
	analysis                           bool // check and lint accept many targets
	targets                            []string
	output                             string
	cpuProfile, heapProfile, tracePath string
	profileTrace                       bool
	formatCheck, structured            bool
	debug, watch                       bool
	buildTypeName                      string
	buildTypeSet                       bool
	testTimeout, testFilter            string
	debugScript                        string   // ms debug --script: command file, or - for stdin
	debugBreaks                        []string // ms debug --break: one-shot breakpoints
	arguments                          []string // forwarded to the program after --
}

// plan is the validated compiler configuration for an invocation.
type plan struct {
	options compiler.Options
	kind    compiler.BuildType
}

func (inv *invocation) isOneOf(commands ...string) bool {
	return slices.Contains(commands, inv.command)
}

func (inv *invocation) hasProfilePaths() bool {
	return inv.cpuProfile != "" || inv.heapProfile != "" || inv.tracePath != ""
}

// usageError prints a message and returns the usage status.
func usageError(format string, a ...any) int {
	fmt.Fprintf(os.Stderr, format+"\n", a...)
	return 2
}

// parseInvocation reads the command, its input file, and options. A false
// result carries the exit status for the problem it already reported.
func parseInvocation(args []string) (*invocation, int, bool) {
	inv := &invocation{command: args[0], filename: args[1]}
	if inv.filename == "" {
		return nil, usageError("ms %s: the file argument is empty; pass a .ms file, directory, or ms.toml", inv.command), false
	}
	inv.analysis = inv.isOneOf("check", "lint")
	first, positional := 1, false
	if inv.analysis && inv.filename == "--" {
		if len(args) == 2 {
			return nil, usageError("ms %s: missing a target; pass .ms files, directories, or ms.toml", inv.command), false
		}
		first, inv.filename, positional = 2, args[2], true
	}
	if strings.HasPrefix(inv.filename, "-") && inv.filename != "--" && !positional {
		return nil, usageError("unknown option %s for ms %s; run 'ms help %s' for its options (put the file first, then options)", inv.filename, inv.command, inv.command), false
	}
	if !inv.analysis {
		filename, err := resolveInput(inv.command, inv.filename)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return nil, 2, false
		}
		inv.filename = filename
	}
	inv.targets = []string{inv.filename}
	if status, ok := inv.parseOptions(args, first, positional); !ok {
		return nil, status, false
	}
	return inv, 0, true
}

// parseOptions consumes the arguments after the input file.
func (inv *invocation) parseOptions(args []string, first int, positional bool) (int, bool) {
	for i := first + 1; i < len(args); i++ {
		if positional {
			inv.targets = append(inv.targets, args[i])
			continue
		}
		flag, value, inline := splitCommandValueOption(inv.command, args[i])
		switch flag {
		case "--":
			if inv.analysis {
				inv.targets = append(inv.targets, args[i+1:]...)
			} else {
				inv.arguments = args[i+1:]
			}
			return 0, true
		case "--debug":
			inv.debug = true
		case "--watch":
			inv.watch = true
		case "--check":
			inv.formatCheck = true
		case "--json":
			inv.structured = true
		case "--build-type":
			value, ok := requiredValue(args, &i, value, inline)
			if !ok {
				return usageError("--build-type requires a build type; use Debug, Release, RelWithDebInfo, or MinSizeRel"), false
			}
			if inv.buildTypeSet {
				return usageError("--build-type may only be specified once; remove the duplicate flag"), false
			}
			inv.buildTypeName, inv.buildTypeSet = value, true
		case "--timeout", "--filter":
			value, ok := requiredValue(args, &i, value, inline)
			if !ok {
				example := map[string]string{"--timeout": "--timeout 30s", "--filter": "--filter \"test name\""}[flag]
				return usageError("%s requires a value, e.g. %s", flag, example), false
			}
			if flag == "--filter" {
				inv.testFilter = value
				continue
			}
			if d, err := time.ParseDuration(value); err != nil || d < 0 {
				return usageError("invalid --timeout %q; use a duration such as 30s or 2m, or 0 to disable", value), false
			}
			inv.testTimeout = value
		case "--script":
			value, ok := requiredValue(args, &i, value, inline)
			if !ok {
				return usageError("--script requires a file of debugger commands, or - for standard input, e.g. --script commands.txt"), false
			}
			inv.debugScript = value
		case "--break":
			value, ok := requiredValue(args, &i, value, inline)
			if !ok {
				return usageError("--break requires file:line or a function name, e.g. --break src/main.ms:7"), false
			}
			inv.debugBreaks = append(inv.debugBreaks, value)
		case "--trace":
			if inv.command == "profile" {
				inv.profileTrace = true
				continue
			}
			fallthrough
		case "-o", "--output", "--out-dir", "--cpu-profile", "--heap-profile":
			value, ok := requiredValue(args, &i, value, inline)
			if !ok {
				return usageError("%s", pathRequirement(flag)), false
			}
			if status, ok := inv.setPath(flag, value); !ok {
				return status, false
			}
		default:
			if !strings.HasPrefix(args[i], "-") {
				if inv.analysis {
					if args[i] == "" {
						return usageError("ms %s: an input argument is empty; pass a .ms file, directory, or ms.toml", inv.command), false
					}
					inv.targets = append(inv.targets, args[i])
					continue
				}
				return usageError("unexpected extra argument %s (ms %s takes one file; arguments for the program go after --)", args[i], inv.command), false
			}
			return usageError("unknown option %s for ms %s; run 'ms help %s' for its options (arguments for the program go after --)", args[i], inv.command, inv.command), false
		}
	}
	return 0, true
}

func pathRequirement(flag string) string {
	example := "out.pprof"
	switch flag {
	case "--out-dir":
		example = "profile-bundle"
	case "-o", "--output":
		example = "out.txt"
	}
	return flag + " requires a path argument, e.g. " + flag + " " + example
}

func (inv *invocation) setPath(flag, value string) (int, bool) {
	switch flag {
	case "-o", "--output", "--out-dir":
		if flag == "--out-dir" && inv.command != "profile" {
			return usageError("--out-dir is valid only for ms profile, not ms %s; use -o for commands that write a file", inv.command), false
		}
		inv.output = value
	case "--cpu-profile":
		inv.cpuProfile = value
	case "--heap-profile":
		inv.heapProfile = value
	case "--trace":
		inv.tracePath = value
	}
	return 0, true
}

// validate rejects option combinations the command does not accept and
// selects the compiler mode and build type. It reports each problem as a cause and fix.
func (inv *invocation) validate() (plan, int, bool) {
	command := inv.command
	var p plan
	switch command {
	case "check", "lint": // Independent source requests run after flag validation.
	case "inspect", "diagram", "lock":
		p.options.AnalyzeOnly = true
		p.options.Entry = filepath.Base(inv.filename) == "ms.toml"
	case "emit": // Only source emission needs lowering without an entry launcher.
	case "build", "run", "debug", "profile":
		p.options.Entry = true
	case "test":
		p.options.Tests = true
	default:
		unknownCommand(command)
		return p, 2, false
	}
	if inv.output != "" && !inv.isOneOf("build", "emit", "inspect", "diagram", "profile") {
		return p, usageError("-o and --output are valid only for ms build, emit, inspect, diagram, doc, or profile, not ms %s; run 'ms help %s' for its options", command, command), false
	}
	if (inv.testTimeout != "" || inv.testFilter != "") && command != "test" {
		return p, usageError("--timeout and --filter are valid only for ms test, not ms %s; run 'ms help %s' for the options this command accepts", command, command), false
	}
	if command == "test" {
		var testArgs []string
		if inv.testTimeout != "" {
			testArgs = append(testArgs, "--timeout="+inv.testTimeout)
		}
		if inv.testFilter != "" {
			testArgs = append(testArgs, "--filter="+inv.testFilter)
		}
		inv.arguments = append(testArgs, inv.arguments...)
	}
	if (inv.debugScript != "" || len(inv.debugBreaks) > 0) && command != "debug" {
		return p, usageError("--script and --break are valid only for ms debug, not ms %s; run 'ms help %s' for the options this command accepts", command, command), false
	}
	if inv.debugScript != "" && len(inv.debugBreaks) > 0 {
		return p, usageError("--script and --break cannot be combined; put break commands in the script or use --break alone"), false
	}
	if command == "debug" && inv.structured && inv.debugScript == "" && len(inv.debugBreaks) == 0 {
		return p, usageError("ms debug --json requires --script or --break; the interactive terminal has no structured output"), false
	}
	if inv.watch && inv.structured {
		return p, usageError("--json cannot be combined with --watch; remove --watch for one versioned result"), false
	}
	if inv.watch && !inv.isOneOf("check", "lint", "run", "test") {
		return p, usageError("--watch requires check, lint, run, or test, not %s; use ms check <file> --watch or ms run <file> --watch", command), false
	}
	if inv.formatCheck && command != "fmt" ||
		inv.structured && !inv.isOneOf(jsonCommands...) ||
		inv.debug && !inv.isOneOf("build", "run", "test") {
		return p, usageError("%s; run 'ms help %s' for the options this command accepts", invalidFlag(command, inv.formatCheck, inv.structured, inv.debug), command), false
	}
	kind, err := compiler.ParseBuildType(inv.buildTypeName)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return p, 2, false
	}
	if inv.buildTypeSet && !inv.isOneOf("build", "run", "test", "debug", "profile") {
		return p, usageError("--build-type requires build, run, test, debug, or profile, not %s; remove the flag", command), false
	}
	switch {
	case inv.debug || command == "debug":
		if inv.buildTypeSet && kind != compiler.Debug {
			return p, usageError("debug requires build type Debug; remove --build-type or pass --build-type Debug"), false
		}
		kind = compiler.Debug
	case command == "profile" && !inv.buildTypeSet:
		kind = compiler.RelWithDebInfo
	}
	if inv.hasProfilePaths() && command != "run" {
		return p, usageError("profiling paths (--cpu-profile, --heap-profile, --trace) require run, not %s; use ms run <file> with them, or ms profile <file> [--trace] for a bundle", command), false
	}
	if inv.watch && inv.hasProfilePaths() {
		return p, usageError("--watch cannot be combined with profiling flags; run the profile once without --watch"), false
	}
	p.options.CPUProfile, p.options.HeapProfile, p.options.Trace = inv.cpuProfile, inv.heapProfile, inv.tracePath
	p.kind = kind
	return p, 0, true
}

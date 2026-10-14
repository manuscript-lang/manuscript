package cli

import (
	"slices"
	"strings"
)

// commandSpec is the one description of a command's name and the shared
// options it accepts. Dispatch, validation, and diagnostics read it; help text
// stays beside the command's explanation in help.go.
type commandSpec struct {
	name                                  string
	json, output, watch, debug, buildType bool // --json, -o/--output, --watch, --debug, --build-type
	testOptions, profilePaths             bool // --timeout/--filter; --cpu-profile/--heap-profile/--trace
}

var commandSpecs = []commandSpec{
	{name: "check", json: true, watch: true},
	{name: "lint", json: true, watch: true},
	{name: "build", json: true, output: true, debug: true, buildType: true},
	{name: "emit", json: true, output: true},
	{name: "run", watch: true, debug: true, buildType: true, profilePaths: true},
	{name: "test", json: true, debug: true, buildType: true, testOptions: true, watch: true},
	{name: "fmt", json: true},
	{name: "inspect", json: true, output: true},
	{name: "diagram", json: true, output: true},
	{name: "profile", json: true, output: true, buildType: true},
	{name: "pprof"},
	{name: "trace"},
	{name: "debug", buildType: true},
	{name: "dap"},
	{name: "lock", json: true},
	{name: "init"},
	{name: "doc", json: true},
	{name: "stdlib"},
	{name: "lsp"},
	{name: "help"},
	{name: "version"},
}

// commandNames lists every dispatched command; a test keeps it equal to the help text.
var commandNames = namesWhere(func(commandSpec) bool { return true })

// jsonCommands accept --json; fmt and doc parse their own options but share the spelling.
var jsonCommands = namesWhere(func(c commandSpec) bool { return c.json })

func namesWhere(keep func(commandSpec) bool) []string {
	var names []string
	for _, spec := range commandSpecs {
		if keep(spec) {
			names = append(names, spec.name)
		}
	}
	return names
}

func specOf(name string) commandSpec {
	if i := slices.IndexFunc(commandSpecs, func(c commandSpec) bool { return c.name == name }); i >= 0 {
		return commandSpecs[i]
	}
	return commandSpec{name: name}
}

// list renders names as "a, b, or c" for usage errors.
func list(names []string) string {
	if len(names) < 2 {
		return strings.Join(names, "")
	}
	return strings.Join(names[:len(names)-1], ", ") + ", or " + names[len(names)-1]
}

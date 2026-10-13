package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/pkg/tooling/docgen"
)

const docHelp = `Usage: ms doc <file.ms|directory|ms.toml>... [--json] [-o output]
       ms doc --stdlib [--json] [-o output]

Generate public API documentation as Markdown (default) or versioned JSON.
Contiguous # comments describe declarations, fields, cases, and operations.
Project documentation includes reachable exports; libraries include all source modules and tests.
A project directory selects its ms.toml. Standalone directories discover independent .ms inputs.
Discovery skips hidden, vendor, node_modules, directory symlinks, and nested projects.
Multiple inputs keep their own import roots; output is written only after every input checks.
Long value options also accept --flag=value. Use -- before flag-like filenames.
Output goes to stdout unless -o or --output is supplied. No Go toolchain is needed.

Options:
  --stdlib             Document the bundled standard library; omit the input file
  --json               Emit versioned JSON instead of Markdown
  -o, --output <path>  Write output to a file (default: stdout)
  -h, --help           Show this help without generating documentation

Examples:
  ms doc main.ms
  ms doc ms.toml -o api.md
  ms doc src utilities.ms --json -o api.json
  ms doc --stdlib -o stdlib.md
  ms doc --stdlib --json -o stdlib.json
`

func runDoc(args []string) int {
	output := ""
	var targets []string
	standard, structured, positional := false, false, false
	for i := 0; i < len(args); i++ {
		if positional {
			targets = append(targets, args[i])
			continue
		}
		flag, value, inline := splitValueOption(args[i], "--output")
		switch flag {
		case "--":
			positional = true
		case "--help", "-h":
			fmt.Print(docHelp)
			return 0
		case "--stdlib":
			standard = true
		case "--json":
			structured = true
		case "-o", "--output":
			value, ok := requiredValue(args, &i, value, inline)
			if !ok {
				fmt.Fprintf(os.Stderr, "%s requires a path argument, e.g. %s docs.md\n", flag, flag)
				return 2
			}
			output = value
		default:
			if strings.HasPrefix(args[i], "-") {
				fmt.Fprintf(os.Stderr, "unknown option %s for ms doc; run 'ms help doc' for its options\n", args[i])
				return 2
			}
			targets = append(targets, args[i])
		}
	}
	if standard && len(targets) != 0 || !standard && len(targets) == 0 {
		if standard {
			fmt.Fprintln(os.Stderr, "ms doc --stdlib takes no input file; omit the file or remove --stdlib")
		} else {
			fmt.Fprintln(os.Stderr, "ms doc: missing the file argument; pass a .ms file, project directory, or --stdlib")
		}
		fmt.Fprintln(os.Stderr)
		fmt.Fprint(os.Stderr, docHelp)
		return 2
	}
	var modules []checker.APIModule
	if standard {
		modules = checker.StandardLibrary()
	} else {
		selection, err := selectAnalysisInputs(targets)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		inputs, issues := analyzeSelection("doc", selection)
		if len(issues) != 0 {
			return reportAnalysisErrors(selection, inputs, issues)
		}
		seen := map[string]checker.APIModule{}
		modules = []checker.APIModule{}
		for _, input := range inputs {
			for _, module := range checker.ModuleDocumentation(input.result.Program) {
				if selection.collection {
					for i := range module.Declarations {
						sort.Strings(module.Declarations[i].ImplementationDeclarations)
					}
				}
				if selection.collection && !strings.HasPrefix(module.Path, "@std/") {
					module.Path = filepath.ToSlash(formatDisplay(selection.cwd, filepath.Join(input.result.SourceRoot, filepath.FromSlash(module.Path))))
				}
				if previous, exists := seen[module.Path]; exists {
					if !reflect.DeepEqual(previous, module) {
						issues = append(issues, syntax.Diagnostic{Position: syntax.Position{File: module.Path, Line: 1, Column: 1}, Phase: "resolution", Message: "conflicting API descriptions for " + module.Path + "; select one independent input, or a project manifest defining one complete module graph"})
					}
					continue
				}
				seen[module.Path] = module
				modules = append(modules, module)
			}
		}
		if len(issues) > 0 {
			return reportAnalysisErrors(selection, inputs, issues)
		}
		sort.Slice(modules, func(i, j int) bool { return modules[i].Path < modules[j].Path })
	}
	var data []byte
	if structured {
		var err error
		data, err = docgen.JSON(modules)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
	} else if standard {
		data = []byte(docgen.StandardLibraryMarkdown())
	} else {
		var b strings.Builder
		b.WriteString("# Manuscript module reference\n\nGenerated from checked public declarations.\n\n")
		for _, module := range modules {
			b.WriteString(docgen.RenderModule(module))
		}
		data = []byte(b.String())
	}
	return writeOutput(output, data)
}

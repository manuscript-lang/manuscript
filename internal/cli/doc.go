package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling/docgen"
)

const docHelp = `Usage: ms doc <file.ms|directory|ms.toml> [--json] [-o output]
       ms doc --stdlib [--json] [-o output]

Generate public API documentation as Markdown (default) or versioned JSON.
Project documentation includes exports from the entry module and local imports.
A project directory selects its ms.toml. Long value options also accept --flag=value.
Output goes to stdout unless -o or --output is supplied. No Go toolchain is needed.

Options:
  --stdlib             Document the bundled standard library; omit the input file
  --json               Emit versioned JSON instead of Markdown
  -o, --output <path>  Write output to a file (default: stdout)
  -h, --help           Show this help without generating documentation

Examples:
  ms doc main.ms
  ms doc ms.toml -o api.md
  ms doc --stdlib -o stdlib.md
  ms doc --stdlib --json -o stdlib.json
`

func runDoc(args []string) int {
	filename, output := "", ""
	standard, structured := false, false
	for i := 0; i < len(args); i++ {
		flag, value, inline := splitValueOption(args[i], "--output")
		switch flag {
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
				fmt.Fprintln(os.Stderr, "output flag requires a path argument, e.g. -o docs.md")
				return 2
			}
			output = value
		default:
			if strings.HasPrefix(args[i], "-") {
				fmt.Fprintf(os.Stderr, "unknown option %s for ms doc; run 'ms help doc' for its options\n", args[i])
				return 2
			}
			if filename != "" {
				fmt.Fprintf(os.Stderr, "unexpected extra argument %s (ms doc takes one file or project directory, or --stdlib)\n", args[i])
				return 2
			}
			filename = args[i]
		}
	}
	if standard && filename != "" || !standard && filename == "" {
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
		var err error
		filename, err = resolveInput("doc", filename)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 2
		}
		result := compiler.CompileFile(filename, compiler.Options{AnalyzeOnly: true, Entry: filepath.Base(filename) == "ms.toml"})
		if !result.Success() {
			return reportDiagnostics(result)
		}
		modules = checker.ModuleDocumentation(result.Program)
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

package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/manuscript-lang/manuscript/checker"
	"github.com/manuscript-lang/manuscript/compiler"
	documentation "github.com/manuscript-lang/manuscript/documentation"
)

const docHelp = `Usage: ms doc <file.ms|ms.toml> [--json] [-o output]
       ms doc --stdlib [--json] [-o output]

Generate public API documentation as Markdown (default) or versioned JSON.
Project documentation includes exports from the entry module and local imports.
--stdlib documents the standard library bundled with this binary.
Output goes to stdout unless -o or --output is supplied. No Go toolchain is needed.
`

func runDoc(args []string) int {
	filename, output := "", ""
	standard, structured := false, false
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--help", "-h":
			fmt.Print(docHelp)
			return 0
		case "--stdlib":
			standard = true
		case "--json":
			structured = true
		case "-o", "--output":
			i++
			if i == len(args) {
				fmt.Fprintln(os.Stderr, "output flag requires a path")
				return 2
			}
			output = args[i]
		default:
			if strings.HasPrefix(args[i], "-") || filename != "" {
				fmt.Fprintln(os.Stderr, "unexpected doc argument:", args[i])
				return 2
			}
			filename = args[i]
		}
	}
	if standard && filename != "" || !standard && filename == "" {
		fmt.Fprint(os.Stderr, docHelp)
		return 2
	}
	var modules []checker.APIModule
	if standard {
		modules = checker.StandardLibrary()
	} else {
		result := compiler.CompileFile(filename, compiler.Options{})
		if !result.Success() {
			for _, d := range result.Diagnostics {
				fmt.Fprintln(os.Stderr, d)
			}
			return 1
		}
		modules = checker.ModuleDocumentation(result.Program)
	}
	var data []byte
	if structured {
		var err error
		data, err = documentation.JSON(modules)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
	} else if standard {
		data = []byte(documentation.StandardLibraryMarkdown())
	} else {
		var b strings.Builder
		b.WriteString("# Manuscript module reference\n\nGenerated from checked public declarations.\n\n")
		for _, module := range modules {
			b.WriteString(documentation.RenderModule(module))
		}
		data = []byte(b.String())
	}
	var err error
	if output == "" {
		_, err = os.Stdout.Write(data)
	} else {
		err = os.WriteFile(output, data, 0644)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return 0
}

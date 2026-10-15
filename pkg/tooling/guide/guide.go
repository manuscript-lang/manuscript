package guide

import (
	_ "embed"
	"fmt"
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

//go:embed cheatsheet.md
var cheatsheet string

// Cheatsheet is the one-page language guide for agents.
func Cheatsheet() string { return cheatsheet }

// StdlibIndex lists each module's exported names, generated from the same
// declarations the checker uses so it cannot drift from the library.
func StdlibIndex() string {
	var b strings.Builder
	b.WriteString("# Standard library\n\n`import Name from \"@std/<module>.ms\"`; `prelude` names need no import. `ms search` gives signatures.\n")
	for _, module := range checker.StandardLibrary() {
		fmt.Fprintf(&b, "\n## %s\n", module.Path)
		names := make([]string, 0, len(module.Declarations))
		for _, d := range module.Declarations {
			names = append(names, d.Name)
		}
		b.WriteString(strings.Join(names, ", "))
		b.WriteString("\n")
	}
	return b.String()
}

// ModuleNames returns the short names accepted by Module, sorted.
func ModuleNames() []string {
	var names []string
	for _, module := range checker.StandardLibrary() {
		names = append(names, shortName(module.Path))
	}
	sort.Strings(names)
	return names
}

func shortName(path string) string {
	return strings.TrimSuffix(strings.TrimPrefix(path, "@std/"), ".ms")
}

// Module renders one module's declarations and documented members as Markdown.
// It accepts a short name ("json"), an import path ("@std/json.ms"), or "prelude".
func Module(name string) (string, bool) {
	name = shortName(name)
	for _, module := range checker.StandardLibrary() {
		if shortName(module.Path) == name {
			return renderModule(module), true
		}
	}
	return "", false
}

func renderModule(module checker.APIModule) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# %s\n\n", module.Path)
	for _, d := range module.Declarations {
		fmt.Fprintf(&b, "## %s\n\n**%s**\n\n", d.Name, d.Kind)
		if d.Doc != "" {
			fmt.Fprintf(&b, "%s\n\n", d.Doc)
		}
		if d.Declaration != "" {
			fmt.Fprintf(&b, "```manuscript\n%s```\n\n", d.Declaration)
		}
		for _, m := range d.Members {
			if strings.TrimSpace(m.Doc) != "" {
				fmt.Fprintf(&b, "### %s.%s\n\n%s\n\n```manuscript\n%s\n```\n\n", d.Name, m.Name, m.Doc, m.Signature)
			}
		}
	}
	return b.String()
}

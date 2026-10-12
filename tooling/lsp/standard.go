package lsp

import (
	"fmt"
	"net/url"
	"strings"

	"github.com/manuscript-lang/manuscript/checker"
	"github.com/manuscript-lang/manuscript/compiler"
	"github.com/manuscript-lang/manuscript/syntax"
)

// Standard declarations are immutable virtual documents from the compiler that
// checked this workspace, so editor navigation cannot drift to another version.
func sourceModules(result compiler.Result) []*syntax.Module {
	if result.Program == nil {
		return nil
	}
	return append(append([]*syntax.Module{}, result.Program.Modules...), checker.StandardModules()...)
}
func sourceURI(result compiler.Result, file string) string {
	if strings.HasPrefix(file, "@std/") {
		return (&url.URL{Scheme: "manuscript-stdlib", Path: "/" + strings.TrimPrefix(file, "@std/")}).String()
	}
	return fileURI(modulePath(result, file))
}
func standardLibrarySource(uri string) (string, error) {
	u, err := url.Parse(uri)
	if err != nil || u.Scheme != "manuscript-stdlib" || u.Host != "" || u.RawQuery != "" || u.Fragment != "" {
		return "", fmt.Errorf("invalid standard-library URI")
	}
	for _, m := range checker.StandardModules() {
		if u.Path == "/"+strings.TrimPrefix(m.File, "@std/") {
			return m.Source, nil
		}
	}
	return "", fmt.Errorf("unknown standard-library module")
}
func sourceSymbols(result compiler.Result, file string) map[string]*checker.Symbol {
	if strings.HasPrefix(file, "@std/") {
		return checker.StandardExports(file)
	}
	return result.Program.Symbols[file]
}

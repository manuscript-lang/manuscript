package lsp

import (
	"fmt"
	"net/url"
	"path/filepath"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
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
	m, err := standardLibraryModule(uri)
	if err != nil {
		return "", err
	}
	return m.Source, nil
}
func isStandardLibraryURI(uri string) bool {
	return strings.HasPrefix(uri, "manuscript-stdlib:")
}

// Native sources on disk still need the pinned binding context after parsing.
// A matching name alone cannot authorize a workspace native declaration.
func standardLibraryDocument(d document) *syntax.Module {
	if isStandardLibraryURI(d.URI) {
		m, _ := standardLibraryModule(d.URI)
		return m
	}
	u, err := url.Parse(d.URI)
	if err != nil || u.Scheme != "file" || u.RawQuery != "" || u.Fragment != "" {
		return nil
	}
	for _, m := range checker.StandardModules() {
		if filepath.Base(filename(d.URI)) == strings.TrimPrefix(m.File, "@std/") && d.Text == m.Source {
			return m
		}
	}
	return nil
}
func standardLibraryModule(uri string) (*syntax.Module, error) {
	u, err := url.Parse(uri)
	if err != nil || u.Scheme != "manuscript-stdlib" || u.Host != "" || u.RawQuery != "" || u.Fragment != "" {
		return nil, fmt.Errorf("invalid standard-library URI")
	}
	for _, m := range checker.StandardModules() {
		if u.Path == "/"+strings.TrimPrefix(m.File, "@std/") {
			return m, nil
		}
	}
	return nil, fmt.Errorf("unknown standard-library module")
}
func sourceSymbols(result compiler.Result, file string) map[string]*checker.Symbol {
	if strings.HasPrefix(file, "@std/") {
		return checker.StandardExports(file)
	}
	return result.Program.Symbols[file]
}

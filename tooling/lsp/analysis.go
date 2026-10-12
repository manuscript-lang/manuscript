package lsp

import (
	"github.com/manuscript-lang/manuscript/checker"
	"github.com/manuscript-lang/manuscript/compiler"
	"github.com/manuscript-lang/manuscript/syntax"
	"github.com/manuscript-lang/manuscript/tooling"
	"os"
	"path/filepath"
)

func analyze(d document, docs map[string]document) compiler.Result {
	return analyzeOptions(d, docs, compiler.Options{AnalyzeOnly: true, Recover: true})
}
func analyzeOptions(d document, docs map[string]document, options compiler.Options) compiler.Result {
	path := filename(d.URI)
	overlay := map[string]string{}
	for _, open := range docs {
		p := filename(open.URI)
		if real, e := filepath.EvalSymlinks(p); e == nil {
			p = real
		}
		overlay[p] = open.Text
	}
	overlay[path] = d.Text
	options.Overlay = overlay
	target := path
	for dir := filepath.Dir(path); ; dir = filepath.Dir(dir) {
		manifest := filepath.Join(dir, "ms.toml")
		if _, e := os.Stat(manifest); e == nil {
			target = manifest
			break
		}
		if filepath.Dir(dir) == dir {
			break
		}
	}
	if options.ScopeMarker != "" && target != path {
		options.Module = path
	}
	result := compiler.CompileFile(target, options)
	if result.Program == nil && result.SourceRoot == "" && target == path {
		return compiler.CompileSource(path, d.Text, options)
	}
	if target != path && result.Program != nil && module(result, d) == nil {
		options.Module = path
		return compiler.CompileFile(target, options)
	}
	return result
}

func modulePath(result compiler.Result, file string) string {
	if filepath.IsAbs(file) {
		return file
	}
	root := result.ProjectRoot
	if root == "" {
		root = result.SourceRoot
	}
	return filepath.Join(root, filepath.FromSlash(file))
}
func module(result compiler.Result, d document) *syntax.Module {
	if result.Program == nil {
		return nil
	}
	path := filename(d.URI)
	if canonical, err := filepath.EvalSymlinks(path); err == nil {
		path = canonical
	}
	for _, m := range result.Program.Modules {
		if m.File == path || modulePath(result, m.File) == path {
			return m
		}
	}
	return nil
}
func at(result compiler.Result, d document, p position) (*syntax.Expression, *checker.Info) {
	if entry := occurrenceAt(result, d, p); entry != nil {
		return &syntax.Expression{Pos: entry.pos, Text: entry.name, Kind: "name"}, entry.info
	}
	m := module(result, d)
	if m == nil {
		return nil, nil
	}
	var selected *syntax.Expression
	var info *checker.Info
	for e, i := range result.Program.Expressions {
		if e.Pos.File != m.File || e.Text == "" {
			continue
		}
		start := Position(d.Text, e.Pos.Offset)
		end := Position(d.Text, e.Pos.Offset+len(e.Text))
		if p.Line == start.Line && p.Character >= start.Character && p.Character < end.Character {
			if selected == nil || len(e.Text) < len(selected.Text) {
				selected = e
				info = i
			}
		}
	}
	return selected, info
}
func navigation(result compiler.Result, d document, p position, method string) any {
	e, i := at(result, d, p)
	if e == nil || i == nil {
		return nil
	}
	if method == "textDocument/hover" {
		return map[string]any{"contents": map[string]any{"kind": "plaintext", "value": e.Text + ": " + i.Type.String()}, "range": span{Position(d.Text, e.Pos.Offset), Position(d.Text, e.Pos.Offset+len(e.Text))}}
	}
	if selected := occurrenceAt(result, d, p); selected != nil {
		for _, entry := range sourceIndex(result) {
			if entry.key == selected.key && entry.declaration {
				// Operation keys group a contract and all implementations for
				// rename. Definition lookup follows the checked concrete method.
				if i.Method != nil && i.Method.ID != "" && (entry.info == nil || entry.info.Method == nil || entry.info.Method.ID != i.Method.ID) {
					continue
				}
				return []any{occurrenceLocation(result, entry)}
			}
		}
	}
	target := declaration(result, i)
	if target.File == "" {
		return nil
	}
	for _, m := range sourceModules(result) {
		if m.File == target.File {
			pos := Position(m.Source, target.Offset)
			uri := sourceURI(result, m.File)
			return []any{map[string]any{"uri": uri, "range": span{pos, pos}}}
		}
	}
	return nil
}
func declaration(result compiler.Result, i *checker.Info) syntax.Position {
	if i.Symbol != nil && i.Symbol.Decl != nil {
		return i.Symbol.Decl.Pos
	}
	if i.Method != nil && i.Method.Decl != nil {
		return i.Method.Decl.Pos
	}
	if i.Binding != nil {
		for _, local := range tooling.Inspect(result.Program).Locals {
			if local.GoID == i.Binding.ID {
				return syntax.Position{File: local.Span.File, Offset: local.Span.Start}
			}
		}
	}
	return syntax.Position{}
}

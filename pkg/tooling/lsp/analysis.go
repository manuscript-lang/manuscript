package lsp

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/project"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"path/filepath"
	"strings"
)

func analyze(d document, docs map[string]document) compiler.Result {
	return analyzeOptions(d, docs, compiler.Options{AnalyzeOnly: true, Recover: true})
}
func analyzeOptions(d document, docs map[string]document, options compiler.Options) compiler.Result {
	if standardLibraryDocument(d) != nil {
		// Standard signatures are already checked by the compiler at startup.
		// They are library declarations, not standalone executable modules.
		return compiler.Result{Program: &checker.Program{}}
	}
	if isStandardLibraryURI(d.URI) {
		return compiler.Result{}
	}
	path := filename(d.URI)
	overlay := map[string]string{}
	for _, open := range docs {
		if isStandardLibraryURI(open.URI) || standardLibraryDocument(open) != nil {
			continue
		}
		p := filename(open.URI)
		overlay[p] = open.Text
	}
	overlay[path] = d.Text
	options.Overlay = overlay
	target, found := project.FindManifest(path)
	if !found {
		target = path
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
	if m := standardLibraryDocument(d); m != nil {
		return m
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
func at(result compiler.Result, d document, p position, index []occurrence) (*syntax.Expression, *checker.Info) {
	if entry := occurrenceAt(result, d, p, index); entry != nil {
		return &syntax.Expression{Pos: entry.pos, Text: entry.name, Kind: syntax.KindName}, entry.info
	}
	m := module(result, d)
	if m == nil {
		return nil, nil
	}
	var selected *syntax.Expression
	var info *checker.Info
	for e, i := range result.Program.Expressions() {
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
	index := sourceIndex(result)
	e, i := at(result, d, p, index)
	if e == nil || i == nil {
		return nil
	}
	if method == "textDocument/hover" {
		shown := i.Type
		if i.Symbol != nil && i.Symbol.IsConstant() && shown == i.Symbol.Type {
			shown = i.Symbol.ValueType()
		}
		label := e.Text + ": " + shown.String()
		if i.Method != nil && i.Method.Accessor {
			label = "get " + e.Text + " -> " + shown.String()
		}
		value := "```manuscript\n" + label + "\n```"
		docs := hoverDocumentation(result, i)
		if docs != "" {
			value += "\n\n" + docs
		}
		return map[string]any{"contents": map[string]any{"kind": "markdown", "value": value}, "range": span{Position(d.Text, e.Pos.Offset), Position(d.Text, e.Pos.Offset+len(e.Text))}}
	}
	if selected := occurrenceAt(result, d, p, index); selected != nil {
		for _, entry := range index {
			if entry.key == selected.key && entry.declaration {
				// Operation keys group a contract and all implementations for
				// rename. Definition lookup follows the checked concrete method.
				if i.Method != nil && i.Method.ID != "" && (entry.info == nil || entry.info.Method == nil || entry.info.Method.ID != i.Method.ID) {
					continue
				}
				// Contract reads have no concrete implementation ID. Follow
				// their checked declaration, rather than the first implementation
				// sharing the rename group (including standard-library methods).
				if i.Method != nil && i.Method.ID == "" && i.Method.Decl != nil && (entry.info == nil || entry.info.Method == nil || entry.info.Method.Decl == nil || entry.info.Method.Decl.Pos != i.Method.Decl.Pos) {
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

func documentationDeclaration(info *checker.Info) *syntax.Declaration {
	if info == nil {
		return nil
	}
	if info.Method != nil && info.Method.Decl != nil {
		return info.Method.Decl
	}
	if info.Symbol != nil {
		return info.Symbol.Decl
	}
	return nil
}

func hoverDocumentation(result compiler.Result, info *checker.Info) string {
	if docs := declarationDocumentation(result, documentationDeclaration(info)); docs != "" {
		return docs
	}
	if info == nil || info.Method == nil {
		return ""
	}
	for _, receiver := range []*checker.Type{info.Method.Receiver, info.Method.Contract} {
		if receiver != nil && receiver.Def != nil && receiver.Def.Symbol != nil {
			if docs := declarationDocumentation(result, receiver.Def.Symbol.Decl); docs != "" {
				return docs
			}
		}
	}
	return ""
}

// declarationDocumentation reads the contiguous # comment block immediately
// above a declaration. The source remains the single documentation authority
// for project modules and immutable standard-library documents alike.
func declarationDocumentation(result compiler.Result, decl *syntax.Declaration) string {
	if decl == nil {
		return ""
	}
	for _, m := range sourceModules(result) {
		if m.File != decl.Pos.File {
			continue
		}
		lines := strings.Split(m.Source, "\n")
		line := decl.Pos.Line - 2
		var notes []string
		for line >= 0 {
			text := strings.TrimSpace(lines[line])
			if !strings.HasPrefix(text, "#") {
				break
			}
			notes = append([]string{strings.TrimSpace(strings.TrimPrefix(text, "#"))}, notes...)
			line--
		}
		return strings.TrimSpace(strings.Join(notes, "\n"))
	}
	return ""
}

func declaration(result compiler.Result, i *checker.Info) syntax.Position {
	if i.Symbol != nil && i.Symbol.Decl != nil {
		return i.Symbol.Decl.Pos
	}
	if i.Method != nil && i.Method.Decl != nil {
		return i.Method.Decl.Pos
	}
	if i.Binding != nil {
		// Ordinary locals already resolve through the source index above.
		// The implicit self binding is anchored at its method declaration.
		for decl, binding := range result.Program.SelfBindings() {
			if binding == i.Binding {
				return decl.Pos
			}
		}
	}
	return syntax.Position{}
}

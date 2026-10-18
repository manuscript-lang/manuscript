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
	return analyzeWith(d, docs, options, compiler.CompileFile)
}

// analyzeWith keeps selection and overlay validation identical for uncached
// callers and the server's single live generation of shared analyses.
func analyzeWith(d document, docs map[string]document, options compiler.Options, compile func(string, compiler.Options) compiler.Result) compiler.Result {
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
	result := compile(target, options)
	if result.Program == nil && result.SourceRoot == "" && target == path {
		return compiler.CompileSource(path, d.Text, options)
	}
	if target != path && result.Program != nil && module(result, d) == nil {
		options.Module = path
		return compile(target, options)
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
func navigation(result compiler.Result, d document, p position, method string, cached ...[]occurrence) any {
	var index []occurrence
	if len(cached) > 0 {
		index = cached[0]
	} else {
		index = sourceIndex(result)
	}
	e, i := at(result, d, p, index)
	if e == nil || i == nil {
		return nil
	}
	if method == "textDocument/hover" {
		shown := i.Type
		if i.Symbol != nil && i.Symbol.IsConstant() && shown == i.Symbol.Type {
			shown = i.Symbol.ValueType()
		}
		value := "```manuscript\n" + e.Text + ": " + shown.String() + "\n```"
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
		if decl.Pos.Line <= 1 || decl.Pos.Offset < 0 || decl.Pos.Offset > len(m.Source) {
			return ""
		}
		// Offsets are in the original source, including CRLF and recovered
		// declarations. Only inspect the immediately preceding line spans.
		end := strings.LastIndexByte(m.Source[:decl.Pos.Offset], '\n')
		var notes []string
		for end >= 0 {
			start := strings.LastIndexByte(m.Source[:end], '\n') + 1
			text := strings.TrimSpace(m.Source[start:end])
			if !strings.HasPrefix(text, "#") {
				break
			}
			notes = append(notes, strings.TrimSpace(strings.TrimPrefix(text, "#")))
			end = start - 1
		}
		for left, right := 0, len(notes)-1; left < right; left, right = left+1, right-1 {
			notes[left], notes[right] = notes[right], notes[left]
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
		for decl, binding := range result.Program.FixtureBindings() {
			if binding == i.Binding {
				if fixture := result.Program.TestFixtures[decl.Pos.File]; fixture != nil {
					return fixture.Factory.Decl.Pos
				}
				return decl.Pos
			}
		}
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

package lsp

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/frontend"
	"github.com/manuscript-lang/manuscript/pkg/project"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type completionItem struct {
	Label               string `json:"label"`
	Kind                int    `json:"kind"`
	Detail              string `json:"detail,omitempty"`
	Documentation       any    `json:"documentation,omitempty"`
	SortText            string `json:"sortText"`
	FilterText          string `json:"filterText"`
	InsertTextFormat    int    `json:"insertTextFormat"`
	TextEdit            any    `json:"textEdit"`
	AdditionalTextEdits []any  `json:"additionalTextEdits,omitempty"`
}

func callableText(name string, t *checker.Type, variables []*checker.Type, snippets bool) string {
	if !snippets || t == nil || t.Kind != "function" {
		return name
	}
	var output strings.Builder
	output.WriteString(name)
	at := 1
	if len(variables) > 0 {
		output.WriteByte('[')
		for i, v := range variables {
			if i > 0 {
				output.WriteString(", ")
			}
			fmt.Fprintf(&output, "${%d:%s}", at, v.Name)
			at++
		}
		output.WriteByte(']')
	}
	output.WriteByte('(')
	written := 0
	for _, p := range t.Params {
		if t.Defaults[p.Name] {
			continue
		}
		if written > 0 {
			output.WriteString(", ")
		}
		if len(t.Params) != 1 {
			fmt.Fprintf(&output, "%s: ", p.Name)
		}
		fmt.Fprintf(&output, "${%d:%s}", at, p.Name)
		at++
		written++
	}
	output.WriteString(")$0")
	return output.String()
}
func description(result compiler.Result, decl *syntax.Declaration) any {
	if notes := declarationDocumentation(result, decl); notes != "" {
		return map[string]string{"kind": "markdown", "value": notes}
	}
	return nil
}
func completionAt(d document, docs map[string]document, p position, snippets bool) ([]completionItem, error) {
	items := []completionItem{}
	c, err := contextAt(d, p)
	if err != nil {
		return items, err
	}
	if c.comment {
		return items, nil
	}
	if imports, handled := importCompletion(d, docs, c, snippets); handled {
		return imports, nil
	}
	if c.literal {
		return items, nil
	}
	analysis := queryEditor(d, docs, c)
	k := &completer{d: d, docs: docs, c: c, snippets: snippets, analysis: analysis, result: analysis.result, items: items, seen: map[string]bool{}}
	switch {
	case c.member:
		k.memberItems()
	case c.argument:
		k.argumentItems()
	default:
		k.scopeItems()
		k.keywordItems()
		if c.prefix != "" {
			k.standardImports()
			k.workspaceImports()
		}
	}
	sortCompletion(k.items)
	return k.items, nil
}

// completer accumulates the completion items for one request.
type completer struct {
	d        document
	docs     map[string]document
	c        cursorContext
	snippets bool
	analysis editorAnalysis
	result   compiler.Result
	items    []completionItem
	seen     map[string]bool
}

// add appends an item unless its name repeats, does not match the typed
// prefix, or is the editor's own completion marker.
func (k *completer) add(name string, kind int, t *checker.Type, priority int, insert string, decl *syntax.Declaration) {
	if k.seen[name] || !nameMatches(name, k.c.prefix) || strings.HasPrefix(name, "__manuscript_completion") {
		return
	}
	k.seen[name] = true
	detail := ""
	if t != nil {
		detail = t.String()
	}
	format := 1
	if k.snippets && strings.Contains(insert, "${") || k.snippets && strings.Contains(insert, "$0") {
		format = 2
	}
	k.items = append(k.items, completionItem{Label: name, Kind: kind, Detail: detail, Documentation: description(k.result, decl), SortText: fmt.Sprintf("%02d_%s", priority, name), FilterText: name, InsertTextFormat: format, TextEdit: map[string]any{"range": span{Position(k.d.Text, k.c.start), Position(k.d.Text, k.c.end)}, "newText": insert}})
}

// addImport appends an item that also inserts an ordinary import for it.
func (k *completer) addImport(s *checker.Symbol, path string) {
	before := len(k.items)
	kind := 3
	if s.Kind == syntax.KindType {
		kind = 7
	}
	k.add(s.Name, kind, s.Type, 4, callableText(s.Name, s.Type, s.Variables, k.snippets), s.Decl)
	if len(k.items) > before {
		item := &k.items[len(k.items)-1]
		item.Detail += " — " + path
		item.AdditionalTextEdits = []any{map[string]any{"range": span{position{}, position{}}, "newText": "import " + s.Name + " from " + strconv.Quote(path) + "\n"}}
	}
}

// memberItems offers alternative cases or members after a dot.
func (k *completer) memberItems() {
	analysis, result := k.analysis, k.result
	if analysis.expression == nil || analysis.expression.Kind != syntax.KindMember {
		return
	}
	left := analysis.expression.Left
	if typ := typeExpression(left, analysis.scope); typ != nil {
		for _, cs := range checker.Cases(typ) {
			signature := &checker.Type{Kind: "function", Params: cs.Fields, Result: typ}
			insert := cs.Name
			if len(cs.Fields) > 0 {
				insert = callableText(cs.Name, signature, nil, k.snippets)
			}
			k.add(cs.Name, 20, signature, 0, insert, nil)
		}
	} else if result.Program != nil {
		if info := result.Program.Info(left); info != nil && info.Type != nil {
			for _, member := range checker.Members(result.Program, info.Type, left.Pos.File) {
				kind := 5
				insert := member.Name
				if member.Kind == "method" {
					kind = 2
					insert = callableText(member.Name, member.Type, nil, k.snippets)
				}
				k.add(member.Name, kind, member.Type, 0, insert, member.Declaration)
			}
		}
	}
}

// argumentItems offers the labels of parameters not yet supplied.
func (k *completer) argumentItems() {
	call, signature := queryCall(k.analysis)
	if call == nil || signature == nil {
		return
	}
	used := map[string]bool{}
	for _, arg := range editorCallArguments(k.analysis, call) {
		if arg.Name != k.analysis.marker {
			used[arg.Name] = true
		}
	}
	for _, param := range signature.Params {
		if used[param.Name] {
			continue
		}
		insert := param.Name + ": "
		if k.snippets {
			insert += "${1:" + param.Name + "}"
		}
		k.add(param.Name, 6, param.Type, 0, insert, nil)
	}
}

// scopeItems offers the bindings, types, and module symbols visible here.
func (k *completer) scopeItems() {
	analysis, result, c := k.analysis, k.result, k.c
	for name, b := range analysis.scope.Bindings {
		if !c.typeContext {
			k.add(name, 6, b.Type, 0, callableText(name, b.Type, nil, k.snippets), nil)
		}
	}
	for name, t := range analysis.scope.Types {
		k.add(name, 25, t, 1, name, nil)
	}
	symbols := analysis.scope.Symbols
	if len(symbols) == 0 && result.Program != nil {
		if m := module(result, analysis.document); m != nil {
			symbols = result.Program.ModuleSymbols(m.File)
		}
	}
	for name, s := range symbols {
		if c.typeContext && s.Kind != syntax.KindType {
			continue
		}
		kind := 3
		insert := callableText(name, s.Type, s.Variables, k.snippets)
		if s.Kind == syntax.KindType {
			kind = 7
			insert = name
			if c.typeContext && k.snippets && s.Type.Def != nil && len(s.Type.Def.Variables) > 0 {
				insert = name + "["
				for i, v := range s.Type.Def.Variables {
					if i > 0 {
						insert += ", "
					}
					insert += fmt.Sprintf("${%d:%s}", i+1, v.Name)
				}
				insert += "]"
			}
			if !c.typeContext && s.Type.Kind == syntax.KindRecord {
				signature := checker.ConstructorSignature(s.Type)
				insert = callableText(name, signature, s.Variables, k.snippets)
			}
		}
		k.add(name, kind, s.Type, 2, insert, s.Decl)
	}
	// Preserve useful declaration suggestions even when another declaration has
	// malformed syntax. Scope-sensitive results above only use checked snapshots.
	if len(symbols) == 0 {
		if parsed, _ := frontend.Parse(filename(k.d.URI), k.d.Text, true); parsed != nil {
			for _, decl := range parsed.Declarations {
				kind := 3
				if decl.Kind == syntax.KindType {
					kind = 7
				}
				k.add(decl.Name, kind, nil, 2, decl.Name, decl)
			}
		}
	}
}

// keywordItems offers statement and declaration keywords (with snippet
// templates), literals, and the built-in type names.
func (k *completer) keywordItems() {
	d, c := k.d, k.c
	lineStart := strings.LastIndex(d.Text[:c.start], "\n") + 1
	if strings.TrimSpace(d.Text[lineStart:c.start]) == "" {
		words := []string{"let", "var", "if", "else", "for", "while", "match", "with", "return"}
		if lineStart == c.start {
			words = []string{"fn", "type", "interface", "impl", "import", "export", "test"}
		}
		templates := map[string]string{"interface": "interface ${1:Name}:\n    ${0:fn operation() -> Unit}", "fn": "fn ${1:name}(${2}) -> ${3:Unit}:\n    ${0:return unit}", "type": "type ${1:Name}:\n    ${0:field: String}", "if": "if ${1:condition}:\n    $0", "for": "for ${1:item} in ${2:items}:\n    $0", "with": "with ${1:resource} = ${2:initializer}:\n    $0", "test": "test \"${1:name}\":\n    ${0:return unit}"}
		for _, word := range words {
			insert := word + " "
			if k.snippets {
				if template := templates[word]; template != "" {
					insert = template
				}
			}
			k.add(word, 14, nil, 5, insert, nil)
		}
	}
	for _, word := range []string{"true", "false", "unit", "fn", "not", "try"} {
		if !c.typeContext {
			k.add(word, 14, nil, 5, word, nil)
		}
	}
	if c.typeContext {
		for _, name := range []string{"Int", "Float", "String", "Bool", "Unit", "Never", "Equal", "Hashable", "Optional", "Result", "Error", "List", "Map", "Set"} {
			k.add(name, 7, nil, 3, name, nil)
		}
	}
}

// standardImports offers standard-library names that accepting adds an import for.
func (k *completer) standardImports() {
	inventory := checker.StandardExportInventory()
	for _, path := range standardPaths() {
		for _, s := range inventory[path] {
			if k.seen[s.Name] || !nameMatches(s.Name, k.c.prefix) || k.c.typeContext && s.Kind != syntax.KindType {
				continue
			}
			k.addImport(s, path)
		}
	}
}

// workspaceImports offers exported names from other workspace files, with a
// relative import.
func (k *completer) workspaceImports() {
	d, c := k.d, k.c
	files, e := workspaceDocuments(d, k.docs)
	if e != nil {
		return
	}
	for _, file := range files {
		if file.URI == d.URI {
			continue
		}
		parsed, issues := frontend.Parse(filename(file.URI), file.Text, false)
		if len(issues) != 0 {
			continue
		}
		matches := false
		for _, decl := range parsed.Declarations {
			if decl.Export && nameMatches(decl.Name, c.prefix) && !k.seen[decl.Name] {
				matches = true
			}
		}
		if !matches {
			continue
		}
		checked := workspaceAnalysis(file, k.docs)
		m := module(checked, file)
		if m == nil {
			continue
		}
		relative, e := filepath.Rel(filepath.Dir(filename(d.URI)), filename(file.URI))
		if e != nil {
			continue
		}
		path := filepath.ToSlash(relative)
		if !strings.HasPrefix(path, ".") {
			path = "./" + path
		}
		for _, s := range checked.Program.ModuleSymbols(m.File) {
			if !s.Export || s.Decl == nil || s.Decl.Pos.File != m.File || k.seen[s.Name] || !nameMatches(s.Name, c.prefix) || c.typeContext && s.Kind != syntax.KindType {
				continue
			}
			k.addImport(s, path)
		}
	}
}
func sortCompletion(items []completionItem) {
	sort.Slice(items, func(i, j int) bool {
		return items[i].SortText < items[j].SortText || items[i].SortText == items[j].SortText && items[i].Detail < items[j].Detail
	})
}
func typeExpression(e *syntax.Expression, state checker.ScopeState) *checker.Type {
	if e == nil {
		return nil
	}
	if e.Kind == syntax.KindName {
		if t := state.Types[e.Text]; t != nil {
			return t
		}
		if s := state.Symbols[e.Text]; s != nil && s.Kind == syntax.KindType {
			return s.Type
		}
	}
	if e.Kind == syntax.KindApply {
		base := typeExpression(e.Left, state)
		if base == nil {
			return nil
		}
		copy := *base
		copy.Args = nil
		for _, arg := range e.Types {
			t := resolveEditorType(arg, state)
			if t == nil {
				return nil
			}
			copy.Args = append(copy.Args, t)
		}
		return &copy
	}
	return nil
}
func resolveEditorType(t *syntax.Type, state checker.ScopeState) *checker.Type {
	if t == nil {
		return nil
	}
	base := state.Types[t.Name]
	if base == nil {
		if symbol := state.Symbols[t.Name]; symbol != nil && symbol.Kind == syntax.KindType {
			base = symbol.Type
		}
	}
	if base == nil {
		return nil
	}
	copy := *base
	copy.Args = nil
	for _, arg := range t.Args {
		resolved := resolveEditorType(arg, state)
		if resolved == nil {
			return nil
		}
		copy.Args = append(copy.Args, resolved)
	}
	return &copy
}
func queryCall(a editorAnalysis) (*syntax.Expression, *checker.Type) {
	if a.result.Program == nil {
		return nil, nil
	}
	for e := range a.result.Program.Expressions() {
		if e.Kind != syntax.KindCall || e.Pos.File != moduleFile(a.result, a.document) {
			continue
		}
		matched := false
		for _, arg := range e.Args {
			if arg.Name == a.marker || containsMarker(arg.Value, a.marker) {
				matched = true
			}
		}
		if !matched {
			continue
		}
		if info := a.result.Program.Info(e.Left); info != nil && info.Type != nil && info.Type.Kind == "function" {
			signature := info.Type
			if strings.Contains(signature.String(), "<invalid>") && info.Symbol != nil {
				signature = info.Symbol.Type
			}
			return e, signature
		}
		if constructed := a.result.Program.Info(e); constructed != nil && constructed.Constructor != nil && constructed.Case != "" {
			for _, cs := range checker.Cases(constructed.Constructor) {
				if cs.Name == constructed.Case {
					return e, &checker.Type{Kind: "function", Params: cs.Fields, Result: constructed.Constructor}
				}
			}
		}
		if typ := typeExpression(e.Left, a.scope); typ != nil {
			return e, checker.ConstructorSignature(typ)
		}
	}
	return nil, nil
}
func containsMarker(e *syntax.Expression, marker string) bool {
	return e != nil && (e.Text == marker || containsMarker(e.Left, marker) || containsMarker(e.Right, marker))
}
func importCompletion(d document, docs map[string]document, c cursorContext, snippets bool) ([]completionItem, bool) {
	start := strings.LastIndex(d.Text[:c.offset], "\n") + 1
	line := d.Text[start:c.offset]
	trimmed := strings.TrimSpace(line)
	if !strings.HasPrefix(trimmed, "import ") {
		groupStart := strings.LastIndex(d.Text[:c.start], "import {")
		if groupStart < 0 || strings.Contains(d.Text[groupStart:c.start], "}") {
			return nil, false
		}
		start = groupStart
		line = d.Text[start:c.offset]
	}
	grouped := strings.HasPrefix(strings.TrimSpace(line), "import {")
	imported := map[string]bool{}
	if grouped {
		end := strings.Index(d.Text[start:], "}")
		if end < 0 {
			end = len(d.Text) - start
		}
		for _, token := range editorTokens(d.Text[start : start+end]) {
			if token.kind == "name" && token.text != "import" && (start+token.end <= c.start || start+token.start >= c.end) {
				imported[token.text] = true
			}
		}
	}
	items := []completionItem{}
	add := func(name, path string, kind int, r span, text string) {
		items = append(items, completionItem{Label: name, Kind: kind, Detail: path, SortText: name, FilterText: name, InsertTextFormat: 1, TextEdit: map[string]any{"range": r, "newText": text}})
	}
	quote := strings.IndexByte(line, '"')
	if quote >= 0 {
		pathStart := start + quote + 1
		prefix := d.Text[pathStart:c.offset]
		end := c.offset
		for end < len(d.Text) && d.Text[end] != '"' && d.Text[end] != '\n' {
			end++
		}
		r := span{Position(d.Text, pathStart), Position(d.Text, end)}
		for path := range checker.StandardExportInventory() {
			if strings.HasPrefix(path, prefix) {
				add(path, path, 17, r, path)
			}
		}
		project, hasProject := editorProject(d)
		for alias, target := range project.Aliases {
			candidate := alias
			if stat, e := os.Stat(target); e == nil && stat.IsDir() {
				candidate += "/"
			}
			if strings.HasPrefix(candidate, prefix) {
				add(candidate, candidate, 17, r, candidate)
			}
		}
		if strings.HasPrefix(prefix, "./") || strings.HasPrefix(prefix, "../") || strings.HasPrefix(prefix, "@") && !strings.HasPrefix(prefix, "@std/") {
			slash := strings.LastIndexByte(prefix, '/')
			if slash >= 0 {
				directoryPrefix := prefix[:slash+1]
				directory := filepath.Join(filepath.Dir(filename(d.URI)), filepath.FromSlash(directoryPrefix))
				if strings.HasPrefix(prefix, "@") {
					alias, remainder, _ := strings.Cut(strings.TrimSuffix(directoryPrefix, "/"), "/")
					if base := project.Aliases[alias]; base != "" {
						directory = filepath.Join(base, filepath.FromSlash(remainder))
					} else {
						directory = ""
					}
				}
				if directory != "" {
					canonical, e := filepath.EvalSymlinks(directory)
					root := filepath.Dir(filename(d.URI))
					if hasProject {
						root = project.Root
					}
					relative, re := filepath.Rel(root, canonical)
					if e == nil && re == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
						entries, e := os.ReadDir(canonical)
						if e == nil {
							for _, entry := range entries {
								path := directoryPrefix + entry.Name()
								if strings.HasPrefix(path, prefix) && (entry.IsDir() || strings.HasSuffix(path, ".ms")) {
									if entry.IsDir() {
										path += "/"
									}
									add(path, path, 17, r, path)
								}
							}
						}
					}
				}
			}
		}

		sortCompletion(items)
		return items, true
	}
	// Symbol completion in `import Name from "..."` uses only exported declarations.
	rest := d.Text[c.end:]
	from := strings.Index(rest, "from ")
	if from >= 0 {
		tail := strings.TrimSpace(rest[from+5:])
		if index := strings.IndexByte(tail, '\n'); index >= 0 {
			tail = tail[:index]
		}
		path, err := strconv.Unquote(tail)
		if err == nil {
			exports := checker.StandardExportInventory()[path]
			if len(exports) == 0 && (strings.HasPrefix(path, ".") || strings.HasPrefix(path, "@") && !strings.HasPrefix(path, "@std/")) {
				file := filepath.Clean(filepath.Join(filepath.Dir(filename(d.URI)), filepath.FromSlash(path)))
				if strings.HasPrefix(path, "@") {
					project, _ := editorProject(d)
					alias, remainder, _ := strings.Cut(path, "/")
					if base := project.Aliases[alias]; base != "" {
						file = filepath.Join(base, filepath.FromSlash(remainder))
					} else {
						file = ""
					}
				}
				source, e := os.ReadFile(file)
				if opened, ok := docs[fileURI(file)]; ok {
					source = []byte(opened.Text)
					e = nil
				}
				if e == nil {
					target := document{URI: fileURI(file), Text: string(source)}
					checked := workspaceAnalysis(target, docs)
					if m := module(checked, target); m != nil {
						for _, s := range checked.Program.ModuleSymbols(m.File) {
							if s.Export && s.Decl != nil && s.Decl.Pos.File == m.File {
								exports = append(exports, s)
							}
						}
					}
				}
			}
			for _, s := range exports {
				if !imported[s.Name] && nameMatches(s.Name, c.prefix) {
					kind := 3
					if s.Kind == syntax.KindType {
						kind = 7
					}
					add(s.Name, path, kind, span{Position(d.Text, c.start), Position(d.Text, c.end)}, s.Name)
				}
			}
			sortCompletion(items)
			return items, true
		}
	}
	for path, exports := range checker.StandardExportInventory() {
		for _, s := range exports {
			if !imported[s.Name] && nameMatches(s.Name, c.prefix) {
				text := s.Name + " from " + strconv.Quote(path)
				if grouped {
					text = s.Name
				}
				add(s.Name, path, 7, span{Position(d.Text, c.start), Position(d.Text, c.end)}, text)
			}
		}
	}
	_ = snippets
	sortCompletion(items)
	return items, true
}

func standardPaths() []string {
	paths := []string{}
	for path := range checker.StandardExportInventory() {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	return paths
}

func editorProject(d document) (project.Project, bool) {
	if manifest, ok := project.FindManifest(filename(d.URI)); ok {
		p, err := project.ReadProject(manifest)
		if err == nil {
			return p, true
		}
	}
	return project.Project{Aliases: map[string]string{}}, false
}

// Identifier completion supports the same case-insensitive subsequence match
// editors use for camel/snake names, while import paths retain prefix matching.
func nameMatches(name, query string) bool {
	name = strings.ToLower(name)
	query = strings.ToLower(query)
	at := 0
	for _, char := range name {
		if at < len(query) && byte(char) == query[at] {
			at++
		}
	}
	return at == len(query)
}

// Use checked label resolution without changing the source expressions used for navigation.
func editorCallArguments(a editorAnalysis, call *syntax.Expression) []syntax.Argument {
	if info := a.result.Program.Info(call); info != nil && info.Arguments != nil {
		return info.Arguments
	}
	return call.Args
}

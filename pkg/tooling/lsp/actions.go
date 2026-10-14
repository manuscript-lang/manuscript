package lsp

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"sort"
	"strings"
)

func actionFor(d document, title, kind string, edits []any, diagnostics []any) any {
	action := map[string]any{"title": title, "kind": kind, "edit": map[string]any{"documentChanges": []any{map[string]any{"textDocument": map[string]any{"uri": d.URI, "version": d.Version}, "edits": edits}}}}
	if len(diagnostics) > 0 {
		action["diagnostics"] = diagnostics
		action["isPreferred"] = true
	}
	return action
}
func lineRange(source string, line int) span {
	start := 0
	for n := 0; n < line; n++ {
		offset := strings.IndexByte(source[start:], '\n')
		if offset < 0 {
			break
		}
		start += offset + 1
	}
	end := strings.IndexByte(source[start:], '\n')
	if end < 0 {
		end = len(source) - start
	} else {
		end++
	}
	return span{Position(source, start), Position(source, start+end)}
}
func editorActions(d document, checked compiler.Result, requested span, only []string) []any {
	result := actions(d)
	eligible := func(r span) bool { return r.Start.Line <= requested.End.Line && r.End.Line >= requested.Start.Line }
	for _, issue := range checked.Diagnostics {
		m := module(checked, d)
		if m == nil || issue.Position.File != m.File || issue.Code() != "MS2003" || issue.End == nil || issue.Fix == nil {
			continue
		}
		r := span{Position(d.Text, issue.Position.Offset), Position(d.Text, issue.End.Offset)}
		if eligible(r) {
			fix := issue.Fix
			edits := []any{map[string]any{"range": span{Position(d.Text, fix.Position.Offset), Position(d.Text, fix.End.Offset)}, "newText": fix.Replacement}}
			result = append(result, actionFor(d, "Remove redundant prelude import", "quickfix", edits, []any{map[string]any{"range": r, "message": issue.Message, "code": issue.Code(), "source": "manuscript"}}))
		}
	}
	for _, issue := range tooling.Lint(filename(d.URI), d.Text) {
		p := Position(d.Text, issue.Position.Offset)
		r := span{p, p}
		if !eligible(r) {
			continue
		}
		title := "Insert final newline"
		end := p
		newText := "\n"
		if issue.Code == "MSL001" {
			title = "Remove trailing whitespace"
			sourceTail := d.Text[issue.Position.Offset:]
			n := strings.IndexByte(sourceTail, '\n')
			if n < 0 {
				n = len(sourceTail)
			}
			if n > 0 && sourceTail[n-1] == '\r' {
				n--
			}
			end = Position(d.Text, issue.Position.Offset+n)
			newText = ""
		}
		result = append(result, actionFor(d, title, "quickfix", []any{map[string]any{"range": span{p, end}, "newText": newText}}, []any{map[string]any{"range": r, "message": issue.Message, "code": issue.Code, "source": "manuscript-lint"}}))
	}
	for _, issue := range tooling.LintProgram(checked.Program) {
		m := module(checked, d)
		if m == nil || issue.Position.File != m.File || issue.Code != "MSL102" {
			continue
		}
		edits, r := unusedImportEdits(d, m, issue.Position.Offset)
		if eligible(r) && len(edits) > 0 {
			result = append(result, actionFor(d, "Remove unused import", "quickfix", edits, []any{map[string]any{"range": span{r.Start, r.Start}, "message": issue.Message, "code": issue.Code, "source": "manuscript-lint"}}))
		}
	}
	// Sort contiguous import runs. Comments and blank separators retain their
	// original attachment and remain outside the replaced source ranges.
	lines := strings.SplitAfter(d.Text, "\n")
	edits := []any{}
	for at := 0; at < len(lines); {
		if !strings.HasPrefix(strings.TrimSpace(lines[at]), "import ") {
			at++
			continue
		}
		start := at
		block := []string{}
		for at < len(lines) && strings.HasPrefix(strings.TrimSpace(lines[at]), "import ") {
			block = append(block, lines[at])
			at++
		}
		before := strings.Join(block, "")
		sort.Strings(block)
		after := strings.Join(block, "")
		if before != after {
			begin := lineRange(d.Text, start).Start
			end := lineRange(d.Text, at-1).End
			edits = append(edits, map[string]any{"range": span{begin, end}, "newText": after})
		}
	}
	if len(edits) > 0 {
		result = append(result, actionFor(d, "Organize imports", "source.organizeImports", edits, nil))
	}
	if len(only) > 0 {
		filtered := []any{}
		for _, raw := range result {
			kind := raw.(map[string]any)["kind"].(string)
			for _, requested := range only {
				if kind == requested || strings.HasPrefix(kind, requested+".") {
					filtered = append(filtered, raw)
					break
				}
			}
		}
		return filtered
	}
	return result
}

// A grouped import expands into bindings sharing one declaration position.
// Remove the selected name and its following comma without touching comments or
// other bindings. A remaining trailing comma is valid Manuscript syntax.
func unusedImportEdits(d document, module *syntax.Module, offset int) ([]any, span) {
	tokens, err := lexer.Lex(module.File, module.Source)
	if err != nil {
		return nil, span{}
	}
	var selected *syntax.Import
	for _, imp := range module.Imports {
		if imp.NamePos.Offset == offset {
			selected = imp
			break
		}
	}
	if selected == nil {
		return nil, span{}
	}
	count := 0
	for _, imp := range module.Imports {
		if imp.Pos.Offset == selected.Pos.Offset {
			count++
		}
	}
	if count == 1 {
		endLine := selected.NamePos.Line
		for _, token := range tokens {
			if token.Pos.Offset >= selected.Pos.Offset && token.Kind == lexer.String {
				endLine = token.Pos.Line
				break
			}
		}
		r := span{lineRange(d.Text, selected.Pos.Line-1).Start, lineRange(d.Text, endLine-1).End}
		return []any{map[string]any{"range": r, "newText": ""}}, r
	}
	r := span{Position(d.Text, offset), Position(d.Text, offset+len(selected.Name))}
	edits := []any{map[string]any{"range": r, "newText": ""}}
	for at, token := range tokens {
		if token.Pos.Offset == offset && at+1 < len(tokens) && tokens[at+1].Kind == "," {
			comma := tokens[at+1].Pos.Offset
			edits = append(edits, map[string]any{"range": span{Position(d.Text, comma), Position(d.Text, comma+1)}, "newText": ""})
			break
		}
	}
	return edits, r
}

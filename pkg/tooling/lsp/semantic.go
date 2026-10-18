package lsp

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/pkg/tooling/format"
	"strings"
)

var tokenTypes = []string{"keyword", "variable", "number", "string", "comment", "function", "type", "property", "parameter", "enumMember", "typeParameter"}

func semantic(d document, checked ...compiler.Result) map[string]any {
	var index []occurrence
	if len(checked) > 0 {
		index = sourceIndex(checked[0])
	}
	return semanticWithIndex(d, checked, index)
}

func semanticWithIndex(d document, checked []compiler.Result, index []occurrence) map[string]any {
	data := []int{}
	positions := newSourcePositions(d.Text)
	tokens, e := lexer.Lex(filename(d.URI), d.Text)
	if e != nil {
		tokens = []lexer.Token{}
		keywords := map[string]bool{}
		for _, word := range lexer.Keywords() {
			keywords[word] = true
		}
		for _, token := range editorTokens(d.Text) {
			kind := token.kind
			switch kind {
			case "name":
				kind = lexer.Name
				if keywords[token.text] {
					kind = token.text
				} else if token.text[0] >= '0' && token.text[0] <= '9' {
					kind = lexer.Number
				}
			case "string":
				kind = lexer.String
			case "comment":
				kind = "COMMENT"
			}
			p := positions.position(token.start)
			tokens = append(tokens, lexer.Token{Kind: kind, Text: token.text, Pos: syntax.Position{Offset: token.start, Line: p.Line + 1, Column: 1}})
		}
	}
	resolved := map[int]int{}
	if len(checked) > 0 {
		file := moduleFile(checked[0], d)
		for _, entry := range index {
			if entry.pos.File != file || entry.info == nil {
				continue
			}
			kind := 1
			if strings.HasPrefix(entry.key, "field:") {
				kind = 7
			} else if strings.HasPrefix(entry.key, "parameter:") {
				kind = 8
			} else if strings.HasPrefix(entry.key, "case:") {
				kind = 9
			} else if entry.info.Symbol != nil && entry.info.Symbol.Kind == syntax.KindType {
				kind = 6
			} else if entry.info.Type != nil && entry.info.Type.Kind == "function" && (entry.info.Symbol == nil || !entry.info.Symbol.IsConstant()) {
				kind = 5
			}
			resolved[entry.pos.Offset] = kind
		}
	}
	if len(checked) > 0 && checked[0].Program != nil {
		result := checked[0]
		m := module(result, d)
		if m != nil {
			for expression, info := range result.Program.Expressions() {
				if expression == nil || info == nil || expression.Pos.File != m.File || expression.Text == "" {
					continue
				}
				if info.Symbol != nil && info.Symbol.Kind == syntax.KindType {
					resolved[expression.Pos.Offset] = 6
				} else if info.Type != nil && info.Type.Kind == "function" && (info.Symbol == nil || !info.Symbol.IsConstant()) {
					resolved[expression.Pos.Offset] = 5
				}
			}
		}
	}
	line, character := 0, 0
	appendToken := func(start position, length, kind int) {
		if length <= 0 {
			return
		}
		delta := start.Character
		if start.Line == line {
			delta -= character
		}
		data = append(data, start.Line-line, delta, length, kind, 0)
		line, character = start.Line, start.Character
	}
	for index, token := range tokens {
		kind := -1
		switch token.Kind {
		case lexer.Name:
			kind = 1
		case lexer.Number:
			kind = 2
		case lexer.String:
			kind = 3
		case "COMMENT":
			kind = 4
		case lexer.Indent, lexer.Dedent, lexer.Newline, lexer.EOF:
			continue
		default:
			if token.Kind != "" && token.Kind[0] >= 'a' && token.Kind[0] <= 'z' {
				kind = 0
			}
		}
		if token.Kind == lexer.Name {
			if resolvedKind, ok := resolved[token.Pos.Offset]; ok {
				kind = resolvedKind
			}
			if index > 0 {
				if tokens[index-1].Kind == syntax.KindFn {
					kind = 5
				}
				if tokens[index-1].Kind == syntax.KindType {
					kind = 6
				}
			}
		}
		if kind < 0 {
			continue
		}
		offset := token.Pos.Offset
		for _, part := range strings.SplitAfter(token.Text, "\n") {
			text := strings.TrimSuffix(strings.TrimSuffix(part, "\n"), "\r")
			start := positions.position(offset)
			end := positions.position(offset + len(text))
			appendToken(start, end.Character-start.Character, kind)
			offset += len(part)
		}
	}
	return map[string]any{"data": data}
}
func actions(d document) []any {
	result := []any{}
	formatted, e := format.Format(filename(d.URI), d.Text)
	if e != nil || formatted == d.Text {
		return result
	}
	result = append(result, map[string]any{"title": "Format Manuscript document", "kind": "source.fixAll.manuscript", "edit": map[string]any{"documentChanges": []any{map[string]any{"textDocument": map[string]any{"uri": d.URI, "version": d.Version}, "edits": []any{map[string]any{"range": span{position{}, Position(d.Text, len(d.Text))}, "newText": formatted}}}}}})
	return result
}

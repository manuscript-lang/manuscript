package lsp

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strings"
)

func documentSymbols(result compiler.Result, d document) []any {
	output := []any{}
	m := module(result, d)
	if m == nil {
		return output
	}
	tokens, _ := lexer.Lex(m.File, m.Source)
	selection := func(pos syntax.Position, name string) span {
		for _, token := range tokens {
			if token.Pos.Offset < pos.Offset {
				continue
			}
			if token.Kind == lexer.Newline {
				if token.Pos.Offset == pos.Offset {
					continue
				}
				break
			}
			if token.Kind == lexer.Name && token.Text == name {
				return span{Position(d.Text, token.Pos.Offset), Position(d.Text, token.Pos.Offset+len(name))}
			}
		}
		p := Position(d.Text, pos.Offset)
		return span{p, p}
	}
	blockEnd := func(next int) int {
		if next < len(d.Text) {
			next = strings.LastIndex(d.Text[:next], "\n") + 1
		}
		return len(strings.TrimRight(d.Text[:next], " \t\r\n"))
	}
	var symbol func(*syntax.Declaration, int) any
	symbol = func(decl *syntax.Declaration, end int) any {
		name := decl.Name
		kind := 12
		detail := ""
		if s := result.Program.Symbol(m.File, decl.Name); s != nil && s.Decl == decl {
			detail = s.ValueType().String()
			if s.IsConstant() {
				kind = 14
			}
		}
		if decl.Kind == syntax.KindRecord || decl.Kind == "contract" || decl.Kind == "alternative" {
			kind = 5
		}
		if decl.Kind == syntax.KindInterface {
			kind = 11
		}
		if decl.Kind == syntax.KindImpl {
			kind = 5
			name = decl.Contract.Name + " for " + decl.Receiver.Name
		}
		if decl.Kind == syntax.KindTest {
			name = "test " + decl.Name
		}
		children := []any{}
		for _, field := range decl.Fields {
			r := selection(field.Pos, field.Name)
			children = append(children, map[string]any{"name": field.Name, "kind": 8, "range": span{r.Start, Position(d.Text, field.Pos.Offset+len(strings.TrimRight(strings.Split(d.Text[field.Pos.Offset:], "\n")[0], "\r")))}, "selectionRange": r})
		}
		for _, cs := range decl.Cases {
			r := selection(cs.Pos, cs.Name)
			children = append(children, map[string]any{"name": cs.Name, "kind": 22, "range": r, "selectionRange": r})
		}
		for i, method := range decl.Methods {
			methodEnd := end
			if i+1 < len(decl.Methods) {
				methodEnd = blockEnd(decl.Methods[i+1].Pos.Offset)
			}
			child := symbol(method, methodEnd).(map[string]any)
			child["kind"] = 6
			children = append(children, child)
		}
		value := map[string]any{"name": name, "detail": detail, "kind": kind, "range": span{Position(d.Text, decl.Pos.Offset), Position(d.Text, end)}, "selectionRange": selection(decl.Pos, decl.Name)}
		if len(children) > 0 {
			value["children"] = children
		}
		return value
	}
	for i, decl := range m.Declarations {
		end := blockEnd(len(d.Text))
		if i+1 < len(m.Declarations) {
			end = blockEnd(m.Declarations[i+1].Pos.Offset)
		}
		if end < decl.Pos.Offset {
			end = decl.Pos.Offset
		}
		output = append(output, symbol(decl, end))
	}
	return output
}

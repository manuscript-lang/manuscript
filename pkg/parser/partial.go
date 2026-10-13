package parser

import (
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strings"
)

// ParsePartial retains independently valid declarations for editor analysis.
// Parse remains the strict build API. Recovered trees retain original positions
// and source text, and always carry the diagnostics from omitted declarations.
func ParsePartial(file, source string) (*syntax.Module, []syntax.Diagnostic) {
	if module, err := Parse(file, source); err == nil {
		return module, nil
	}
	module := &syntax.Module{File: file, Source: source}
	diagnostics := []syntax.Diagnostic{}
	starts := []int{}
	offset := 0
	for _, line := range strings.SplitAfter(source, "\n") {
		trimmed := strings.TrimSpace(line)
		if len(line) > 0 && line[0] != ' ' && line[0] != '\t' && trimmed != "" && !strings.HasPrefix(trimmed, "#") {
			declaration := false
			for _, keyword := range []string{"import ", "export ", "fn ", "type ", "interface ", "impl ", "test "} {
				declaration = declaration || strings.HasPrefix(trimmed, keyword)
			}
			// A fresh declaration synchronizes even after an unmatched opener.
			// Other column-zero lines can still belong to a continued header,
			// import, or expression. Let the lexer handle strings and comments
			// rather than counting delimiter characters in source text.
			if !declaration && len(starts) > 0 {
				_, err := lexer.Lex(file, source[starts[len(starts)-1]:offset])
				if issue, ok := err.(syntax.Diagnostic); ok && issue.Message == "unterminated delimiter" {
					offset += len(line)
					continue
				}
			}
			starts = append(starts, offset)
		}
		offset += len(line)
	}
	if len(starts) == 0 {
		_, err := Parse(file, source)
		if issue, ok := err.(syntax.Diagnostic); ok {
			diagnostics = append(diagnostics, issue)
		}
		return module, diagnostics
	}
	starts[0] = 0
	starts = append(starts, len(source))
	lineOffset := 0
	previous := 0
	for index := 0; index < len(starts)-1; index++ {
		start, end := starts[index], starts[index+1]
		lineOffset += strings.Count(source[previous:start], "\n")
		previous = start
		parsed, err := Parse(file, source[start:end])
		if err != nil {
			if issue, ok := err.(syntax.Diagnostic); ok {
				issue.Position.Offset += start
				issue.Position.Line += lineOffset
				diagnostics = append(diagnostics, issue)
			}
			continue
		}
		rebase(parsed, start, lineOffset)
		module.Imports = append(module.Imports, parsed.Imports...)
		module.Declarations = append(module.Declarations, parsed.Declarations...)
	}
	return module, diagnostics
}
func rebase(module *syntax.Module, offset, lines int) {
	position := func(p *syntax.Position) { p.Offset += offset; p.Line += lines }
	var typ func(*syntax.Type)
	var expression func(*syntax.Expression)
	var body func([]*syntax.Statement)
	var pattern func(*syntax.Pattern)
	var declaration func(*syntax.Declaration)
	parameters := func(params []syntax.Parameter) {
		for i := range params {
			position(&params[i].Pos)
			typ(params[i].Type)
			expression(params[i].Default)
		}
	}
	typ = func(t *syntax.Type) {
		if t == nil {
			return
		}
		position(&t.Pos)
		for _, arg := range t.Args {
			typ(arg)
		}
		parameters(t.Params)
		typ(t.Result)
	}
	pattern = func(p *syntax.Pattern) {
		if p == nil {
			return
		}
		position(&p.Pos)
		for _, child := range p.Elements {
			pattern(child)
		}
		for i := range p.Fields {
			position(&p.Fields[i].Pos)
			pattern(p.Fields[i].Pattern)
		}
	}
	expression = func(e *syntax.Expression) {
		if e == nil {
			return
		}
		position(&e.Pos)
		expression(e.Left)
		expression(e.Right)
		for i := range e.Args {
			position(&e.Args[i].Pos)
			expression(e.Args[i].Value)
		}
		for _, t := range e.Types {
			typ(t)
		}
		for _, item := range e.Elements {
			expression(item)
		}
		for _, part := range e.Parts {
			expression(part.Value)
		}
		parameters(e.Params)
		typ(e.Result)
		body(e.Body)
		for i := range e.Arms {
			position(&e.Arms[i].Pos)
			expression(e.Arms[i].Path)
			body(e.Arms[i].Body)
			expression(e.Arms[i].Value)
		}
	}
	body = func(statements []*syntax.Statement) {
		for _, s := range statements {
			position(&s.Pos)
			pattern(s.Pattern)
			typ(s.Type)
			expression(s.Target)
			expression(s.Value)
			body(s.Body)
			body(s.Else)
		}
	}
	declaration = func(d *syntax.Declaration) {
		position(&d.Pos)
		for i := range d.TypeParams {
			position(&d.TypeParams[i].Pos)
			for _, bound := range d.TypeParams[i].Bounds {
				typ(bound)
			}
		}
		parameters(d.Fields)
		parameters(d.Params)
		for i := range d.Cases {
			position(&d.Cases[i].Pos)
			parameters(d.Cases[i].Fields)
		}
		typ(d.Result)
		typ(d.Contract)
		typ(d.Receiver)
		body(d.Body)
		for _, method := range d.Methods {
			declaration(method)
		}
	}
	for _, imp := range module.Imports {
		position(&imp.Pos)
		position(&imp.NamePos)
	}
	for _, decl := range module.Declarations {
		declaration(decl)
	}
}

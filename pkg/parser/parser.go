// Package parser implements the grammar in documentation/core-language/basics/grammar.md.
package parser

import (
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strconv"
	"strings"
)

type Parser struct {
	tokens          []lexer.Token
	at              int
	inlineStatement bool
}

func Parse(file, source string) (module *syntax.Module, err error) {
	return parse(file, source)
}

// ParseLibrary is retained for callers; library and application syntax are identical.
// Deprecated: use Parse.
func ParseLibrary(file, source string) (*syntax.Module, error) { return Parse(file, source) }
func parse(file, source string) (module *syntax.Module, err error) {
	tokens, err := lexer.Lex(file, source)
	if err != nil {
		return nil, err
	}
	defer func() {
		if r := recover(); r != nil {
			if d, ok := r.(syntax.Diagnostic); ok {
				module = nil
				err = d
			} else {
				panic(r)
			}
		}
	}()
	p := &Parser{tokens: tokens}
	module = &syntax.Module{File: file, Source: source}
	for p.peek().Kind != lexer.EOF {
		p.newlines()
		if p.peek().Kind == lexer.EOF {
			break
		}
		if p.take("import") {
			pos := p.previous().Pos
			names := []lexer.Token{}
			if p.take("{") {
				// A named import list is nonempty and permits a trailing comma.
				for {
					names = append(names, p.need(lexer.Name))
					if !p.take(",") || p.peek().Kind == "}" {
						break
					}
				}
				p.need("}")
			} else {
				names = append(names, p.need(lexer.Name))
			}
			p.need("from")
			token := p.need(lexer.String)
			expr := p.text(token)
			if len(expr.Parts) != 1 || expr.Parts[0].Value != nil {
				p.fail(token, "import paths cannot interpolate; write the path as plain text without {…}")
			}
			for _, name := range names {
				module.Imports = append(module.Imports, &syntax.Import{Pos: pos, NamePos: name.Pos, Name: name.Text, Path: expr.Parts[0].Text})
			}
			p.end()
			continue
		}
		exported := p.take("export")
		d := p.declaration()
		if exported && (d.Kind == syntax.KindImpl || d.Kind == syntax.KindTest) {
			p.fail(p.previous(), "only types, interfaces, and named functions can be exported; remove 'export' before this impl or test")
		}
		d.Export = exported
		module.Declarations = append(module.Declarations, d)
	}
	return module, nil
}
func (p *Parser) peek() lexer.Token     { return p.tokens[p.at] }
func (p *Parser) previous() lexer.Token { return p.tokens[p.at-1] }
func (p *Parser) take(k string) bool {
	if p.peek().Kind == k {
		p.at++
		return true
	}
	return false
}
func (p *Parser) need(k string) lexer.Token {
	t := p.peek()
	if !p.take(k) {
		p.fail(t, "expected "+describeKind(k)+", found "+describe(t)+needHint(k, t))
	}
	return t
}
func (p *Parser) fail(t lexer.Token, m string) {
	panic(syntax.Diagnostic{Position: t.Pos, Phase: "parse", Message: m})
}
func (p *Parser) newlines() {
	for p.take(lexer.Newline) {
	}
}
func (p *Parser) end() {
	if p.inlineStatement {
		switch p.peek().Kind {
		case lexer.Newline, ",", ")", "]", "}":
			return
		}
		p.fail(p.peek(), "expected end of inline statement, found "+describe(p.peek())+"; an inline body holds one simple statement, so move more statements to an indented block")
	}
	if p.take(lexer.Newline) {
		p.newlines()
		return
	}
	if p.at > 0 && p.previous().Kind == lexer.Dedent {
		return
	}
	p.fail(p.peek(), "expected end of statement, found "+describe(p.peek())+"; put one statement per line, and join operands with an operator or a comma inside brackets")
}
func (p *Parser) typeParams() []syntax.TypeParameter {
	var result []syntax.TypeParameter
	if !p.take("[") {
		return result
	}
	for {
		name := p.need(lexer.Name)
		param := syntax.TypeParameter{Pos: name.Pos, Name: name.Text}
		if p.take(":") {
			param.Bounds = append(param.Bounds, p.namedType())
			for p.take("&") {
				param.Bounds = append(param.Bounds, p.namedType())
			}
		}
		result = append(result, param)
		if !p.take(",") {
			break
		}
		if p.peek().Kind == "]" {
			break
		}
	}
	p.need("]")
	return result
}
func (p *Parser) parameters(defaults bool) []syntax.Parameter {
	p.need("(")
	var params []syntax.Parameter
	if !p.take(")") {
		for {
			name := p.need(lexer.Name)
			p.need(":")
			param := syntax.Parameter{Pos: name.Pos, Name: name.Text, Type: p.typ()}
			if p.take("=") {
				if !defaults {
					p.fail(p.previous(), "function types and case payloads cannot have defaults; put the default on a named function parameter or a record field instead")
				}
				param.Default = p.expression(0)
			}
			params = append(params, param)
			if !p.take(",") {
				break
			}
			if p.peek().Kind == ")" {
				break
			}
		}
		p.need(")")
	}
	return params
}
func (p *Parser) namedType() *syntax.Type {
	name := p.need(lexer.Name)
	t := &syntax.Type{Pos: name.Pos, Name: name.Text}
	for p.take(".") {
		t.Name += "." + p.need(lexer.Name).Text
	}
	if p.take("[") {
		t.Args = p.typeArgs()
	}
	return t
}
func (p *Parser) typeArgs() []*syntax.Type {
	var types []*syntax.Type
	for {
		types = append(types, p.typ())
		if !p.take(",") {
			break
		}
		if p.peek().Kind == "]" {
			break
		}
	}
	p.need("]")
	return types
}
func (p *Parser) typ() *syntax.Type {
	if p.take("fn") {
		pos := p.previous().Pos
		params := p.parameters(false)
		p.need("->")
		return &syntax.Type{Pos: pos, Name: "fn", Params: params, Result: p.typ()}
	}
	if p.take("(") {
		t := p.typ()
		p.need(")")
		return t
	}
	return p.namedType()
}
func (p *Parser) declaration() *syntax.Declaration {
	token := p.peek()
	d := &syntax.Declaration{Pos: token.Pos, Kind: token.Kind}
	switch {
	case p.take("fn"):
		d.Name = p.need(lexer.Name).Text
		d.TypeParams = p.typeParams()
		d.Params = p.parameters(true)
		p.need("->")
		d.Result = p.typ()
		d.Body = p.statementSuite(false, true)
	case p.take("test"):
		name := p.need(lexer.String)
		text := p.text(name)
		if len(text.Parts) != 1 || text.Parts[0].Value != nil {
			p.fail(name, "test names cannot interpolate; use plain text, e.g. test \"adds numbers\":")
		}
		d.Name = text.Parts[0].Text
		d.Result = &syntax.Type{Name: "Unit", Pos: token.Pos}
		d.Body = p.suite()
	case p.take("impl"):
		d.Contract = p.namedType()
		p.need("for")
		d.Receiver = p.namedType()
		p.need(":")
		p.need(lexer.Newline)
		p.need(lexer.Indent)
		for p.peek().Kind != lexer.Dedent {
			p.newlines()
			if p.peek().Kind == lexer.Dedent {
				break
			}
			p.need("fn")
			name := p.need(lexer.Name)
			m := &syntax.Declaration{Pos: name.Pos, Kind: syntax.KindFn, Name: name.Text}
			m.Params = p.parameters(true)
			p.need("->")
			m.Result = p.typ()
			m.Body = p.statementSuite(false, true)
			d.Methods = append(d.Methods, m)
		}
		p.need(lexer.Dedent)
		if len(d.Methods) == 0 {
			p.fail(token, "implementation requires operations; add at least one 'fn name(...) -> Type:' under the impl")
		}
	case p.take("type") || p.take("interface"):
		d.Name = p.need(lexer.Name).Text
		d.TypeParams = p.typeParams()
		p.need(":")
		p.need(lexer.Newline)
		p.need(lexer.Indent)
		form := ""
		if token.Kind == syntax.KindInterface {
			form = "interface"
		}
		for p.peek().Kind != lexer.Dedent {
			p.newlines()
			if p.peek().Kind == lexer.Dedent {
				break
			}
			next := "record"
			if p.peek().Kind == "case" {
				next = "alternative"
			}
			if p.peek().Kind == syntax.KindFn {
				next = "interface"
			}
			if token.Kind == syntax.KindInterface && next != "interface" {
				p.fail(p.peek(), "a type has only fields or cases; an interface has only operation signatures; declare fields as 'name: Type' in a type, and put method bodies in an 'impl' block")
			}
			if next != "interface" {
				if form != "" && form != next {
					p.fail(p.peek(), "a type cannot mix fields and cases; use either fields (a record) or 'case' lines (an alternative), and wrap shared data in a case payload")
				}
				form = next
			}
			if p.take("case") {
				name := p.need(lexer.Name)
				c := syntax.Case{Pos: name.Pos, Name: name.Text}
				if p.peek().Kind == "(" {
					c.Fields = p.parameters(false)
					if len(c.Fields) == 0 {
						p.fail(name, "nullary cases omit parentheses; write 'case "+name.Text+"' instead of 'case "+name.Text+"()'")
					}
				}
				d.Cases = append(d.Cases, c)
				p.end()
			} else if p.take("fn") {
				name := p.need(lexer.Name)
				m := &syntax.Declaration{Pos: name.Pos, Name: name.Text, Kind: syntax.KindFn}
				if token.Kind == "type" {
					m.TypeParams = p.typeParams()
				}
				m.Params = p.parameters(true)
				p.need("->")
				m.Result = p.typ()
				if token.Kind == "interface" {
					p.end()
				} else {
					m.Body = p.statementSuite(false, true)
				}
				d.Methods = append(d.Methods, m)
			} else {
				name := p.need(lexer.Name)
				p.need(":")
				field := syntax.Parameter{Pos: name.Pos, Name: name.Text, Type: p.typ()}
				if p.take("=") {
					field.Default = p.expression(0)
				}
				d.Fields = append(d.Fields, field)
				p.end()
			}
		}
		p.need(lexer.Dedent)
		if token.Kind == "interface" && len(d.Methods) == 0 {
			p.fail(token, "declaration body cannot be empty; an interface needs at least one 'fn name(...) -> Type' operation")
		}
		if form == "" {
			form = syntax.KindRecord
		}
		d.Kind = form
	default:
		p.fail(token, "expected a module declaration or import, found "+describe(token)+"; top level holds only import, fn, type, interface, impl, and test (optionally prefixed by export), so put statements inside a fn")
	}
	return d
}
func (p *Parser) suite() []*syntax.Statement {
	return p.statementSuite(false)
}
func (p *Parser) statementSuite(expression bool, empty ...bool) []*syntax.Statement {
	outer := p.inlineStatement
	defer func() { p.inlineStatement = outer }()
	p.need(":")
	if p.peek().Kind != lexer.Newline {
		switch p.peek().Kind {
		case "if", "while", "for", "with", "match":
			p.fail(p.peek(), "inline bodies require one simple statement; put '"+p.peek().Kind+"' on its own line in an indented block")
		}
		p.inlineStatement = true
		body := []*syntax.Statement{p.statement()}
		p.inlineStatement = outer
		if !expression {
			p.end()
		}
		return body
	}
	p.inlineStatement = false
	p.need(lexer.Newline)
	p.need(lexer.Indent)
	var body []*syntax.Statement
	for {
		p.newlines()
		if p.peek().Kind == lexer.Dedent || p.peek().Kind == lexer.EOF {
			break
		}
		body = append(body, p.statement())
	}
	p.need(lexer.Dedent)
	if len(body) == 0 && (len(empty) == 0 || !empty[0]) {
		p.fail(p.previous(), "suite cannot be empty; add at least one statement (e.g. 'return') in the indented block")
	}
	return body
}
func (p *Parser) statement() *syntax.Statement {
	t := p.peek()
	s := &syntax.Statement{Pos: t.Pos, Kind: t.Kind}
	switch {
	case p.take("let") || p.take("var"):
		s.Kind = syntax.KindBind
		s.Mutable = t.Kind == "var"
		s.Pattern = p.pattern()
		if s.Pattern.Kind == syntax.KindName && p.take(":") {
			s.Type = p.typ()
		}
		p.need("=")
		s.Value = p.expression(0)
		p.end()
	case p.take("return"):
		if p.peek().Kind != lexer.Newline && !(p.inlineStatement && (p.peek().Kind == "," || p.peek().Kind == ")" || p.peek().Kind == "]" || p.peek().Kind == "}")) {
			s.Value = p.expression(0)
		}
		p.end()
	case p.take("break") || p.take("continue"):
		p.end()
	case p.take("if"):
		s.Value = p.expression(0)
		s.Body = p.suite()
		p.newlines()
		if p.take("else") {
			if p.peek().Kind == syntax.KindIf {
				s.Else = []*syntax.Statement{p.statement()}
			} else {
				s.Else = p.suite()
			}
		}
	case p.take("while"):
		s.Value = p.expression(0)
		s.Body = p.suite()
	case p.take("for"):
		s.Name = p.need(lexer.Name).Text
		p.need("in")
		s.Value = p.expression(0)
		s.Body = p.suite()
	case p.take("with"):
		s.Name = p.need(lexer.Name).Text
		p.need("=")
		s.Value = p.expression(0)
		s.Body = p.suite()
	case p.take("match"):
		s.Value = p.expression(0)
		p.need(":")
		p.need(lexer.Newline)
		p.need(lexer.Indent)
		for {
			p.newlines()
			if p.peek().Kind == lexer.Dedent {
				break
			}
			a := syntax.Arm{Pos: p.peek().Pos}
			if p.take("_") {
				a.Path = &syntax.Expression{Kind: syntax.KindName, Text: "_", Pos: a.Pos}
			} else {
				a.Path = p.casePath()
				if p.take("(") {
					for {
						tok := p.peek()
						if !p.take("_") {
							p.need(lexer.Name)
						}
						a.Names = append(a.Names, tok.Text)
						if !p.take(",") {
							break
						}
						if p.peek().Kind == ")" {
							break
						}
					}
					p.need(")")
				}
			}
			a.Body = p.suite()
			s.Arms = append(s.Arms, a)
		}
		p.need(lexer.Dedent)
	default:
		e := p.expression(0)
		if p.take("=") {
			if (e.Kind != syntax.KindName && e.Kind != syntax.KindMember) || e.Text == "self" {
				p.fail(t, "assignment requires a local binding name or record field; the left side of '=' must be a name or a.field")
			}
			s.Kind = syntax.KindAssign
			if e.Kind == syntax.KindMember {
				s.Target = e
			} else {
				s.Name = e.Text
			}
			s.Value = p.expression(0)
		} else {
			if e.Kind != syntax.KindCall {
				p.fail(t, "only a call can be a standalone expression statement; use 'let name = ...' to keep the value, 'return' to return it, or call a function")
			}
			s.Kind = syntax.KindCall
			s.Value = e
		}
		p.end()
	}
	return s
}
func (p *Parser) pattern() *syntax.Pattern {
	t := p.peek()
	r := &syntax.Pattern{Pos: t.Pos}
	if p.take(lexer.Name) {
		r.Kind = syntax.KindName
		r.Name = t.Text
		return r
	}
	if p.take("[") {
		r.Kind = syntax.KindList
		if !p.take("]") {
			for {
				r.Elements = append(r.Elements, p.pattern())
				if !p.take(",") {
					break
				}
				if p.peek().Kind == "]" {
					break
				}
			}
			p.need("]")
		}
		return r
	}
	if p.take("{") {
		r.Kind = syntax.KindRecord
		for {
			name := p.need(lexer.Name)
			child := &syntax.Pattern{Kind: syntax.KindName, Name: name.Text, Pos: name.Pos}
			if p.take(":") {
				child = p.pattern()
			}
			r.Fields = append(r.Fields, syntax.PatternField{Pos: name.Pos, Name: name.Text, Pattern: child})
			if !p.take(",") {
				break
			}
			if p.peek().Kind == "}" {
				break
			}
		}
		p.need("}")
		return r
	}
	p.fail(t, "expected a binding name, list pattern, or record pattern, found "+describe(t)+"; write a name, [a, b], or {x, y}")
	return nil
}

var precedence = map[string]int{"or": 1, "and": 2, "==": 4, "!=": 4, "<": 4, ">": 4, "<=": 4, ">=": 4, "+": 5, "-": 5, "*": 6, "/": 6, "%": 6}

func (p *Parser) expression(min int) *syntax.Expression {
	t := p.peek()
	var e *syntax.Expression
	if t.Kind == "not" && min > 3 {
		p.fail(t, "not requires grouping at this operator position; wrap it in parentheses, e.g. a == (not b)")
	}
	if p.take("not") {
		e = &syntax.Expression{Kind: syntax.KindUnary, Text: t.Text, Pos: t.Pos, Right: p.expression(3)}
	} else if p.take("+") || p.take("-") || p.take("try") {
		e = &syntax.Expression{Kind: syntax.KindUnary, Text: t.Text, Pos: t.Pos, Right: p.expression(7)}
	} else {
		e = p.primary()
	}
	compared := false
	for {
		op := p.peek()
		level := precedence[op.Kind]
		if level == 0 || level < min {
			break
		}
		if level == 4 && compared {
			p.fail(op, "comparison operators cannot chain; combine two comparisons with 'and', e.g. a < b and b < c")
		}
		p.at++
		e = &syntax.Expression{Kind: syntax.KindBinary, Text: op.Text, Pos: op.Pos, Left: e, Right: p.expression(level + 1)}
		if level == 4 {
			compared = true
		}
	}
	return e
}
func (p *Parser) casePath() *syntax.Expression {
	t := p.need(lexer.Name)
	e := &syntax.Expression{Kind: syntax.KindName, Text: t.Text, Pos: t.Pos}
	if p.take("[") {
		e = &syntax.Expression{Kind: syntax.KindApply, Pos: t.Pos, Left: e, Types: p.typeArgs()}
	}
	for p.take(".") {
		name := p.need(lexer.Name)
		e = &syntax.Expression{Kind: syntax.KindMember, Pos: name.Pos, Left: e, Text: name.Text}
	}
	return e
}
func (p *Parser) primary() *syntax.Expression {
	t := p.peek()
	p.at++
	e := &syntax.Expression{Kind: syntax.KindName, Text: t.Text, Pos: t.Pos}
	switch t.Kind {
	case lexer.Name, "self":
	case lexer.Number:
		e.Kind = syntax.KindNumber
	case "true", "false":
		e.Kind = syntax.KindBool
	case "unit":
		e.Kind = syntax.KindUnit
	case lexer.String:
		e = p.text(t)
	case "(":
		e = p.expression(0)
		p.need(")")
	case "[":
		e.Kind = syntax.KindList
		if !p.take("]") {
			for {
				e.Elements = append(e.Elements, p.expression(0))
				if !p.take(",") {
					break
				}
				if p.peek().Kind == "]" {
					break
				}
			}
			p.need("]")
		}
	case "{":
		e.Kind = syntax.KindMap
		if !p.take("}") {
			for {
				e.Elements = append(e.Elements, p.expression(0))
				p.need(":")
				e.Elements = append(e.Elements, p.expression(0))
				if !p.take(",") || p.peek().Kind == "}" {
					break
				}
			}
			p.need("}")
		}
	case "fn":
		e.Kind = syntax.KindLambda
		e.Text = ""
		e.Params = p.parameters(true)
		p.need("->")
		e.Result = p.typ()
		e.Body = p.statementSuite(true)
	default:
		p.fail(t, "expected an expression, found "+describe(t)+"; write a value, name, call, or literal here")
	}
	for {
		if p.take(".") {
			name := p.need(lexer.Name)
			e = &syntax.Expression{Kind: syntax.KindMember, Pos: name.Pos, Text: name.Text, Left: e}
		} else if p.take("[") {
			e = &syntax.Expression{Kind: syntax.KindApply, Pos: t.Pos, Left: e, Types: p.typeArgs()}
		} else if p.take("(") {
			call := &syntax.Expression{Kind: syntax.KindCall, Pos: e.Pos, Left: e}
			if !p.take(")") {
				for {
					arg := syntax.Argument{Pos: p.peek().Pos}
					if p.peek().Kind == lexer.Name && p.tokens[p.at+1].Kind == ":" {
						arg.Name = p.need(lexer.Name).Text
						p.need(":")
					}
					arg.Value = p.expression(0)
					call.Args = append(call.Args, arg)
					if !p.take(",") {
						break
					}
					if p.peek().Kind == ")" {
						break
					}
				}
				p.need(")")
			}
			e = call
		} else {
			break
		}
	}
	return e
}
func (p *Parser) text(token lexer.Token) *syntax.Expression {
	raw := token.Text[1 : len(token.Text)-1]
	e := &syntax.Expression{Kind: syntax.KindText, Pos: token.Pos}
	var literal strings.Builder
	flush := func() {
		if literal.Len() > 0 {
			e.Parts = append(e.Parts, syntax.TextPart{Text: literal.String()})
			literal.Reset()
		}
	}
	for i := 0; i < len(raw); {
		c := raw[i]
		i++
		if c == '\\' {
			c = raw[i]
			i++
			switch c {
			case 'n':
				literal.WriteByte('\n')
			case 'r':
				literal.WriteByte('\r')
			case 't':
				literal.WriteByte('\t')
			case 'u':
				start := i + 1
				i = start
				for raw[i] != '}' {
					i++
				}
				n, _ := strconv.ParseInt(raw[start:i], 16, 32)
				literal.WriteRune(rune(n))
				i++
			default:
				literal.WriteByte(c)
			}
			continue
		}
		if c != '{' {
			literal.WriteByte(c)
			continue
		}
		flush()
		start := i
		depth := 1
		quoted := false
		for i < len(raw) && depth > 0 {
			b := raw[i]
			if b == '\\' {
				i += 2
				continue
			}
			if b == '"' {
				quoted = !quoted
			}
			if !quoted {
				if b == '{' {
					depth++
				}
				if b == '}' {
					depth--
				}
			}
			i++
		}
		source := raw[start : i-1]
		tokens, err := lexer.Lex(token.Pos.File, "("+source+")")
		shift := func(position syntax.Position) syntax.Position {
			offset := position.Offset
			if offset > len(source)+1 {
				offset = len(source) + 1
			}
			position.Line = token.Pos.Line
			position.Column = token.Pos.Column + start + offset
			position.Offset = token.Pos.Offset + start + offset
			return position
		}
		if err != nil {
			diagnostic := err.(syntax.Diagnostic)
			diagnostic.Position = shift(diagnostic.Position)
			panic(diagnostic)
		}
		// The wrapper disables statement layout while preserving spaces inside braces.
		closing := len(tokens) - 3
		tokens = append(tokens[1:closing], tokens[closing+1:]...)
		for index := range tokens {
			tokens[index].Pos = shift(tokens[index].Pos)
		}
		nested := &Parser{tokens: tokens}
		value := nested.expression(0)
		nested.newlines()
		nested.need(lexer.EOF)

		e.Parts = append(e.Parts, syntax.TextPart{Value: value})
	}
	flush()
	if len(e.Parts) == 0 {
		e.Parts = []syntax.TextPart{{Text: ""}}
	}
	return e
}

// describe names a token for diagnostics in source terms.
func describe(t lexer.Token) string {
	switch t.Kind {
	case lexer.Newline:
		return "end of line"
	case lexer.Indent:
		return "an unexpected indented block"
	case lexer.Dedent:
		return "the end of the block"
	case lexer.EOF:
		return "end of file"
	case lexer.Name:
		return "name '" + t.Text + "'"
	case lexer.Number:
		return "number " + t.Text
	case lexer.String:
		return "text " + t.Text
	}
	return "'" + t.Kind + "'"
}

func describeKind(kind string) string {
	switch kind {
	case lexer.Newline:
		return "end of line"
	case lexer.Indent:
		return "an indented block"
	case lexer.Dedent:
		return "the end of the block"
	case lexer.EOF:
		return "end of file"
	case lexer.Name:
		return "a name"
	case lexer.Number:
		return "a number"
	case lexer.String:
		return "text in double quotes"
	}
	return "'" + kind + "'"
}

// needHint adds the usual fix for the punctuation that is most often missing.
func needHint(kind string, found lexer.Token) string {
	switch kind {
	case ":":
		return "; block headers (fn, if, else, for, while, match, with, type, impl, test) end with ':' before their indented body"
	case "->":
		return "; every fn declares its result type after '->', e.g. fn f() -> Unit:"
	case ")":
		return "; close the parenthesis, separating items with commas"
	case "]":
		return "; close the bracket, separating items with commas"
	case "}":
		return "; close the brace, separating items with commas"
	case "(":
		return "; a call or parameter list starts with '('"
	case "from":
		return "; imports read: import name from \"path.ms\""
	case lexer.Name:
		if found.Kind == lexer.Number || found.Kind == lexer.String {
			return "; a name is required here. If you meant indexing like xs[0], Manuscript has none: call xs.at(index: 0), which returns an Optional"
		}
		if found.Kind == "case" {
			return "; match arms are written without 'case', e.g. Paid(receipt): or Missing:, and 'case' only declares the cases of a type"
		}
		if found.Kind == found.Text {
			return "; '" + found.Text + "' is a reserved word and cannot be used as a name"
		}
		return ""
	case lexer.Newline:
		return "; end the statement with a line break"
	case lexer.Indent:
		return "; indent the block body by four spaces under its header"
	}
	return ""
}

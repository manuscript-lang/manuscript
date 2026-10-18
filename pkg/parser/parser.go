// Package parser implements the grammar in documentation/core-language/basics/grammar.md.
package parser

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"sort"
	"strconv"
	"strings"
)

type Parser struct {
	tokens          []lexer.Token
	at              int
	inlineStatement bool
	inlineReturn    bool
	blockLambda     bool
	depth           int
	// queued holds the bindings after the first of a `let (...)` group until
	// statements collects them.
	queued []*syntax.Statement
}

// maxNesting bounds recursive descent so generated or hostile input produces a
// diagnostic instead of exhausting the Go stack, which cannot be recovered.
const maxNesting = 1000

// maxChain bounds left-nested operator, member, call, and index chains, which
// build deep trees without recursive descent.
const maxChain = 10000

func (p *Parser) link(links *int) {
	*links++
	if *links > maxChain {
		p.fail(p.peek(), fmt.Sprintf("expression chain exceeds %d operators or accesses; split it into named parts", maxChain))
	}
}

// enter counts one level of syntactic nesting; the returned function leaves it.
func (p *Parser) enter() func() {
	p.depth++
	if p.depth > maxNesting {
		p.fail(p.peek(), fmt.Sprintf("nesting exceeds %d levels; split the expression, type, or block into named parts", maxNesting))
	}
	return func() { p.depth-- }
}

func Parse(file, source string) (module *syntax.Module, err error) {
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
			if p.peek().Kind == "*" {
				p.fail(p.peek(), "namespace and wildcard imports are unsupported; import individual exports with 'import { Name, OtherName } from \"./module.ms\"'")
			}
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
			p.needFrom()
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
		for _, d := range p.declarations() {
			if exported && (d.Kind == syntax.KindImpl || d.Kind == syntax.KindTest) {
				p.fail(p.previous(), "only types, interfaces, and named functions can be exported; remove 'export' before this impl or test")
			}
			d.Export = exported
			module.Declarations = append(module.Declarations, d)
		}
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

// needFrom consumes the contextual word 'from' that ends an import's names;
// elsewhere it is an ordinary name.
func (p *Parser) needFrom() {
	t := p.peek()
	if t.Kind == lexer.Name && t.Text == "from" {
		p.at++
		return
	}
	p.fail(t, "expected 'from', found "+describe(t)+needHint("from", t))
}
func (p *Parser) fail(t lexer.Token, m string) {
	d := syntax.Diagnostic{Position: t.Pos, Phase: "parse", Message: m}
	if t.End.Line > 0 {
		d.End = &t.End
	}
	panic(d)
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
	if p.blockLambda && p.peek().Kind == "," {
		p.fail(p.peek(), "a comma cannot end a statement in an indented function body; to separate enclosing arguments, put the comma on its own line dedented to the fn header, or group the function in parentheses")
	}
	if p.peek().Kind == "&" {
		p.fail(p.peek(), "'&&' is not an operator; write 'and' for logical and")
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
		if p.take("=") {
			param.Default = p.typ()
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
func (p *Parser) parameters(defaults, inferred bool) []syntax.Parameter {
	p.need("(")
	var params []syntax.Parameter
	if !p.take(")") {
		for {
			name := p.need(lexer.Name)
			param := syntax.Parameter{Pos: name.Pos, Name: name.Text}
			if p.take(":") {
				param.Type = p.typ()
			} else if !inferred {
				p.need(":")
			}
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

// resultType parses the type that follows a parameter list. It rejects the
// removed '->' and a missing type with the form to write instead.
func (p *Parser) resultType() *syntax.Type {
	p.noArrow()
	if k := p.peek().Kind; k == ":" || k == lexer.Newline {
		p.fail(p.peek(), "every fn declares its result type after the parameter list, e.g. fn f() Unit:")
	}
	return p.typ()
}

// noArrow rejects the removed '->' before a result type.
func (p *Parser) noArrow() {
	if p.peek().Kind == "->" {
		p.fail(p.peek(), "result types follow the parameter list without an arrow; remove '->', e.g. fn f() Unit:")
	}
}
func (p *Parser) typ() *syntax.Type {
	defer p.enter()()
	if p.take("fn") {
		pos := p.previous().Pos
		params := p.parameters(false, false)
		return &syntax.Type{Pos: pos, Name: "fn", Params: params, Result: p.resultType()}
	}
	if p.take("(") {
		t := p.typ()
		p.need(")")
		return t
	}
	return p.namedType()
}

// declarations parses one top-level item, or every constant of a `let (...)`
// group. Each group entry is its own declaration.
func (p *Parser) declarations() []*syntax.Declaration {
	if p.peek().Kind != "let" || p.tokens[p.at+1].Kind != "(" {
		return []*syntax.Declaration{p.declaration()}
	}
	keyword := p.next()
	var result []*syntax.Declaration
	p.bindingGroup(keyword, func() {
		d := &syntax.Declaration{Pos: p.peek().Pos, Kind: syntax.KindFn, Group: keyword.Pos}
		p.constant(d)
		result = append(result, d)
	})
	return result
}

// constant parses `name [: Type] = value` after `let` into a parameterless
// function that returns the value.
func (p *Parser) constant(d *syntax.Declaration) {
	d.Kind = syntax.KindFn
	d.Constant = true
	d.Name = p.need(lexer.Name).Text
	if p.take(":") {
		d.Result = p.typ()
	}
	p.need("=")
	// A binary expression's position is its operator, so the statement
	// starts at the first token of the initializer for source tooling.
	start := p.peek().Pos
	value := p.expression(0)
	if d.Result == nil {
		d.Result = &syntax.Type{Pos: value.Pos}
	}
	d.Body = []*syntax.Statement{{Pos: start, Kind: syntax.KindReturn, Value: value}}
}

func (p *Parser) next() lexer.Token {
	t := p.peek()
	p.at++
	return t
}

// bindingGroup parses the `( ... )` after a consumed let or var keyword. The
// lexer ends each line of the group with a newline; entry parses one binding
// at the start of its line. Entries sit four spaces inside the keyword's line
// and the closing parenthesis aligns with it.
func (p *Parser) bindingGroup(keyword lexer.Token, entry func()) {
	indent := keyword.Pos.Column
	for i := p.at - 2; i >= 0 && p.tokens[i].Pos.Line == keyword.Pos.Line && p.tokens[i].Kind != lexer.Newline; i-- {
		indent = p.tokens[i].Pos.Column
	}
	if p.inlineStatement {
		p.fail(p.peek(), "a binding group needs its own lines; put '"+keyword.Kind+" (' on a line of its own with one binding per indented line, or write single '"+keyword.Kind+" name = value' bindings")
	}
	p.need("(")
	if p.peek().Kind != lexer.Newline {
		p.fail(p.peek(), "a binding group starts its entries on the next line; write '"+keyword.Kind+" (' then one 'name = value' per indented line, or destructure with '"+keyword.Kind+" [a, b] = value' or '"+keyword.Kind+" {x, y} = value'")
	}
	p.next()
	count := 0
	for {
		p.newlines()
		if t := p.peek(); t.Kind == ")" {
			if t.Pos.Column != indent {
				p.fail(t, "the closing ')' of a binding group aligns with its '"+keyword.Kind+"' line, at column "+strconv.Itoa(indent))
			}
			break
		} else if t.Kind == lexer.EOF {
			p.need(")")
		} else if t.Pos.Column != indent+4 {
			p.fail(t, "binding group entries are indented four spaces past the '"+keyword.Kind+"' line, to column "+strconv.Itoa(indent+4))
		}
		entry()
		count++
		if p.peek().Kind == "," {
			p.fail(p.peek(), "a binding group holds one 'name = value' per line, not a comma list; to destructure write '"+keyword.Kind+" [a, b] = value' or '"+keyword.Kind+" {x, y} = value'")
		}
		// A block lambda value ends at its dedent, which also ends the line.
		if p.previous().Kind != lexer.Dedent {
			p.need(lexer.Newline)
		}
	}
	if count == 0 {
		p.fail(p.peek(), "a binding group cannot be empty; add 'name = value' lines or remove the group")
	}
	p.need(")")
	p.end()
}

func (p *Parser) declaration() *syntax.Declaration {
	token := p.peek()
	d := &syntax.Declaration{Pos: token.Pos, Kind: token.Kind}
	switch {
	case p.take("fn"):
		d.Name = p.need(lexer.Name).Text
		d.TypeParams = p.typeParams()
		d.Params = p.parameters(true, false)
		d.Result = p.resultType()
		d.Body = p.statementSuite(false, true)
	case p.take("let"):
		p.constant(d)
		p.end()
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
		// `impl Contract for Type:` implements a contract; `impl Type:` declares
		// the type's own methods. The first name is the type exactly when no
		// `for` follows.
		first := p.namedType()
		if p.take("for") {
			d.Contract = first
			d.Receiver = p.namedType()
		} else {
			d.Receiver = first
		}
		p.need(":")
		p.need(lexer.Newline)
		p.newlines()
		if !p.take(lexer.Indent) {
			return d
		}
		for p.peek().Kind != lexer.Dedent {
			p.newlines()
			if p.peek().Kind == lexer.Dedent {
				break
			}
			p.need("fn")
			name := p.need(lexer.Name)
			m := &syntax.Declaration{Pos: name.Pos, Kind: syntax.KindFn, Name: name.Text}
			if d.Contract == nil {
				m.TypeParams = p.typeParams()
			}
			m.Params = p.parameters(true, false)
			m.Result = p.resultType()
			m.Body = p.statementSuite(false, true)
			d.Methods = append(d.Methods, m)
		}
		p.need(lexer.Dedent)
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
					c.Fields = p.parameters(false, false)
					if len(c.Fields) == 0 {
						p.fail(name, "nullary cases omit parentheses; write 'case "+name.Text+"' instead of 'case "+name.Text+"()'")
					}
				}
				d.Cases = append(d.Cases, c)
				p.end()
			} else if p.take("fn") {
				if token.Kind == "type" {
					p.fail(p.previous(), "a type declares only fields or cases; write its methods in an 'impl "+d.Name+typeParamNames(d.TypeParams)+":' block, or implement an interface with 'impl <Interface> for "+d.Name+typeParamNames(d.TypeParams)+":'")
				}
				name := p.need(lexer.Name)
				m := &syntax.Declaration{Pos: name.Pos, Name: name.Text, Kind: syntax.KindFn}
				m.Params = p.parameters(true, false)
				m.Result = p.resultType()
				p.end()
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
			p.fail(token, "declaration body cannot be empty; an interface needs at least one 'fn name(...) Type' operation")
		}
		if form == "" {
			form = syntax.KindRecord
		}
		d.Kind = form
	default:
		p.fail(token, "expected a module declaration or import, found "+describe(token)+"; top level holds only import, let constants, fn, type, interface, impl, and test (optionally prefixed by export), so put statements inside a fn")
	}
	return d
}
func (p *Parser) suite() []*syntax.Statement {
	return p.statementSuite(false)
}
func (p *Parser) statementSuite(expression bool, empty ...bool) []*syntax.Statement {
	defer p.enter()()
	outer, outerReturn, outerLambda := p.inlineStatement, p.inlineReturn, p.blockLambda
	defer func() { p.inlineStatement, p.inlineReturn, p.blockLambda = outer, outerReturn, outerLambda }()
	p.need(":")
	if p.peek().Kind != lexer.Newline {
		switch p.peek().Kind {
		case "if", "while", "for", "with":
			p.fail(p.peek(), "inline bodies require one simple statement; put '"+p.peek().Kind+"' on its own line in an indented block")
		}
		p.inlineStatement = true
		p.inlineReturn = expression || len(empty) > 0
		body := []*syntax.Statement{p.statement()}
		p.inlineStatement = outer
		if !expression {
			p.end()
		}
		return body
	}
	p.inlineStatement = false
	p.inlineReturn = false
	p.blockLambda = outerLambda || expression
	p.need(lexer.Newline)
	p.need(lexer.Indent)
	var body []*syntax.Statement
	for {
		p.newlines()
		if p.peek().Kind == lexer.Dedent || p.peek().Kind == lexer.EOF {
			break
		}
		body = append(body, p.statements()...)
	}
	p.need(lexer.Dedent)
	if len(body) == 0 && (len(empty) == 0 || !empty[0]) {
		p.fail(p.previous(), "suite cannot be empty; add at least one statement (e.g. 'return') in the indented block")
	}
	return body
}

// binding parses `pattern [: Type] = value` after let or var.
func (p *Parser) binding(s *syntax.Statement) {
	s.Pattern = p.pattern()
	if s.Pattern.Kind == syntax.KindName && p.take(":") {
		s.Type = p.typ()
	}
	p.need("=")
	s.Value = p.expression(0)
}

// statements parses one statement, plus the rest of its bindings when it is a
// `let (...)` or `var (...)` group.
func (p *Parser) statements(allowValue ...bool) []*syntax.Statement {
	result := []*syntax.Statement{p.statement(allowValue...)}
	result = append(result, p.queued...)
	p.queued = nil
	return result
}
func (p *Parser) statement(allowValue ...bool) *syntax.Statement {
	t := p.peek()
	s := &syntax.Statement{Pos: t.Pos, Kind: t.Kind}
	switch {
	case p.take("let") || p.take("var"):
		s.Kind = syntax.KindBind
		s.Mutable = t.Kind == "var"
		if p.peek().Kind == "(" {
			var entries []*syntax.Statement
			p.bindingGroup(t, func() {
				entry := &syntax.Statement{Pos: p.peek().Pos, Kind: syntax.KindBind, Mutable: s.Mutable, Group: t.Pos}
				p.binding(entry)
				entries = append(entries, entry)
			})
			p.queued = entries[1:]
			return entries[0]
		}
		p.binding(s)
		p.end()
	case p.take("return"):
		if p.peek().Kind != lexer.Newline && !(p.inlineStatement && (p.peek().Kind == "," || p.peek().Kind == ")" || p.peek().Kind == "]" || p.peek().Kind == "}")) {
			s.Value = p.expression(0)
		}
		p.end()
	case p.take("break") || p.take("continue"):
		p.end()
	case p.take("if"):
		if p.take("let") {
			s.Pattern = p.pattern()
			if s.Pattern.Kind != syntax.KindName {
				p.fail(t, "if let binds one name; write 'if let value = optional:' and destructure the value inside the branch")
			}
			p.need("=")
		}
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
		if p.peek().Kind == "," {
			p.fail(p.peek(), "for binds one name; to read positions, loop over the entries, e.g. 'for entry in items.entries():' and use entry.index and entry.value")
		}
		p.need("in")
		s.Value = p.expression(0)
		s.Body = p.suite()
	case p.take("with"):
		s.Name = p.need(lexer.Name).Text
		p.need("=")
		s.Value = p.expression(0)
		s.Body = p.suite()
	default:
		e := p.expression(0)
		if p.compoundAssignment() {
			p.compound(s, t, e)
		} else if p.take("=") {
			p.assignTarget(s, t, e)
			s.Value = p.expression(0)
		} else {
			tryCall := e.Kind == syntax.KindUnary && e.Text == "try" && e.Right.Kind == syntax.KindCall
			if !p.inlineReturn && e.Kind != syntax.KindCall && e.Kind != syntax.KindMatch && !tryCall && len(allowValue) == 0 {
				if e.Kind == syntax.KindName && e.Text == "pass" {
					p.fail(t, "'pass' is not a keyword; write 'unit' for an empty block or match arm")
				}
				if e.Kind == syntax.KindName && (e.Text == "const" || e.Text == "val" || e.Text == "final") {
					p.fail(t, "'"+e.Text+"' is not a keyword; write 'let name = ...' for a binding that is not reassigned, or 'var name = ...' when it changes")
				}
				if e.Kind == syntax.KindName && (e.Text == "throw" || e.Text == "raise" || e.Text == "catch") {
					p.fail(t, "'"+e.Text+"' is not a keyword; failures are values, so return error(...) from a fn returning Result and handle it with 'try' or 'if let'")
				}
				if e.Kind == syntax.KindName && e.Text == "elif" {
					p.fail(t, "'elif' is not a keyword; write 'else if <condition>:' for a further branch")
				}
				p.fail(t, "only a call, try call, or match can be a standalone expression statement; use 'let name = ...' to keep the value, 'return' to return it, or call a function")
			}
			s.Kind = syntax.KindCall
			if p.inlineReturn {
				s.Kind = syntax.KindReturn
			}
			s.Value = e
		}
		p.end()
	}
	return s
}
func (p *Parser) pattern() *syntax.Pattern {
	defer p.enter()()
	t := p.peek()
	r := &syntax.Pattern{Pos: t.Pos}
	if t.Kind == "unit" {
		p.fail(t, "unit is a reserved value keyword, not a binding name; choose another name such as code_unit, and use unit for the Unit value")
	}
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
	defer p.enter()()
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
	links := 0
	for {
		op := p.peek()
		if p.compoundAssignment() {
			break
		}
		if op.Kind == "&" {
			p.fail(op, "'&&' is not an operator; write 'and' for logical and")
		}
		if op.Kind == "|" {
			if min > 0 {
				break
			}
			e = p.pipe(e)
			if p.peek().Kind == "." {
				e = p.postfix(e)
			}
			if precedence[p.peek().Kind] != 0 {
				p.fail(p.peek(), "a pipe has the lowest precedence; parenthesize it to use its result in an operator, e.g. (x | f) == y")
			}
			continue
		}
		level := precedence[op.Kind]
		if level == 0 || level < min {
			break
		}
		if (op.Kind == "+" || op.Kind == "-") && e.Kind == syntax.KindName && p.at+2 < len(p.tokens) && p.tokens[p.at+1].Kind == op.Kind && p.tokens[p.at+2].Kind == lexer.Newline {
			p.fail(op, "Manuscript has no '"+op.Text+op.Text+"' operator; write '"+e.Text+" = "+e.Text+" "+op.Text+" 1'")
		}
		if level == 4 && compared {
			p.fail(op, "comparison operators cannot chain; combine two comparisons with 'and', e.g. a < b and b < c")
		}
		p.at++
		p.link(&links)
		e = &syntax.Expression{Kind: syntax.KindBinary, Text: op.Text, Pos: op.Pos, Left: e, Right: p.expression(level + 1)}
		if level == 4 {
			compared = true
		}
	}
	return e
}

// pipe parses one `| step` after lhs and desugars it to the ordinary expression
// the step names, so checking and lowering see plain calls in written order:
//
//	lhs | f            f(lhs)
//	lhs | f(a: 1)      f(lhs, a: 1)
//	lhs | .m(a)        lhs.m(a)
//	lhs | try step     try (the desugared step)
//	lhs | try          try lhs
//
// A step head is a name path with no calls in it, so lhs is evaluated before
// anything the step contributes. A '.member' on the line after a step applies
// to the step's result.
func (p *Parser) pipe(lhs *syntax.Expression) *syntax.Expression {
	p.at++
	if p.peek().Kind == "|" {
		p.fail(p.peek(), "'||' is not an operator; write 'or' for logical or, and '|' only to start a pipe step")
	}
	try := p.peek()
	tried := p.take("try")
	var step *syntax.Expression
	switch {
	case p.peek().Kind == "." && !(tried && p.peek().Pos.Line != try.Pos.Line):
		step = p.postfix(lhs)
	case tried && p.peek().Kind != lexer.Name:
		return &syntax.Expression{Kind: syntax.KindUnary, Text: "try", Pos: try.Pos, Right: lhs}
	default:
		name := p.peek()
		if name.Kind != lexer.Name {
			hint := ""
			if name.Kind == lexer.Newline {
				hint = "; to continue a flow on the next line, end this line before '|' and start the next line with '|'"
			}
			p.fail(name, "a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found "+describe(name)+hint)
		}
		p.at++
		callee := &syntax.Expression{Kind: syntax.KindName, Text: name.Text, Pos: name.Pos}
		// A '.' on a later line continues the flow and applies to the step's
		// result, so it never extends the step's name path.
		for p.peek().Kind == "." && p.peek().Pos.Line == p.tokens[p.at-1].Pos.Line {
			p.at++
			member := p.need(lexer.Name)
			callee = &syntax.Expression{Kind: syntax.KindMember, Pos: member.Pos, Text: member.Text, Left: callee}
		}
		if p.peek().Kind == "[" {
			p.fail(p.peek(), "a pipe step cannot take type arguments; bind the instance to a name first, e.g. let step = "+name.Text+"[Int], then write x | step")
		}
		step = &syntax.Expression{Kind: syntax.KindCall, Pos: name.Pos, Left: callee, Args: []syntax.Argument{{Pos: lhs.Pos, Value: lhs}}}
		if p.take("(") {
			call := p.callArguments(callee)
			step.Args = append(step.Args, call.Args...)
		}
	}
	if tried {
		step = &syntax.Expression{Kind: syntax.KindUnary, Text: "try", Pos: try.Pos, Right: step}
	}
	return step
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
	case lexer.Name, "self", "fixture":
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
		if p.peek().Kind == "," {
			p.fail(p.peek(), "Manuscript has no tuples; declare a record with 'type Pair:' and named fields, or use a List when the items share one type")
		}
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
	case "match":
		e.Kind = syntax.KindMatch
		e.Left = p.expression(0)
		e.Arms = p.matchArms(t)
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
		e.Params = p.parameters(true, true)
		p.noArrow()
		if k := p.peek().Kind; k == lexer.Name || k == "fn" || k == "(" {
			e.Result = p.typ()
		}
		if p.peek().Kind == "=" && p.tokens[p.at+1].Kind == ">" {
			p.fail(p.peek(), "there is no '=>' arrow function; write the result type and a colon, e.g. fn(x: Int) Int: x + 1")
		}
		e.Body = p.statementSuite(true)
	default:
		if t.Kind == "if" {
			p.fail(t, "'if' is a statement, not an expression; declare 'var name = ...' and assign it in each branch, or use 'match'")
		}
		p.fail(t, "expected an expression, found "+describe(t)+"; write a value, name, call, or literal here")
	}
	return p.postfix(e)
}

// postfix applies member access, indexing, and calls to e.
func (p *Parser) postfix(e *syntax.Expression) *syntax.Expression {
	links := 0
	for {
		if p.take(".") {
			p.link(&links)
			if p.peek().Kind == "." {
				p.fail(p.peek(), "Manuscript has no '..' range; to count, use a while loop, or import range from \"@std/collections.ms\" and loop over range(start: 0, end: 10, step: 1), which returns a Result")
			}
			name := p.need(lexer.Name)
			e = &syntax.Expression{Kind: syntax.KindMember, Pos: name.Pos, Text: name.Text, Left: e}
		} else if p.take("[") {
			p.link(&links)
			e = p.bracket(e)
		} else if p.take("(") {
			p.link(&links)
			e = p.callArguments(e)
		} else {
			break
		}
	}
	return e
}

// callArguments parses the arguments after an opening parenthesis and returns
// the call of callee.
func (p *Parser) callArguments(callee *syntax.Expression) *syntax.Expression {
	call := &syntax.Expression{Kind: syntax.KindCall, Pos: callee.Pos, Left: callee}
	if !p.take(")") {
		for {
			arg := syntax.Argument{Pos: p.peek().Pos}
			if p.peek().Kind == lexer.Name && p.tokens[p.at+1].Kind == ":" {
				arg.Name = p.need(lexer.Name).Text
				p.need(":")
			}
			if p.peek().Kind == lexer.Name && p.tokens[p.at+1].Kind == "=" {
				p.fail(p.tokens[p.at+1], "argument labels use a colon; write "+p.peek().Text+": value")
			}
			arg.Value = p.expression(0)
			if arg.Value.Kind == syntax.KindName && p.peek().Kind == "->" {
				p.fail(p.peek(), "lambdas are written fn(name: Type) Result: expression, e.g. fn("+arg.Value.Text+": Int) Int: "+arg.Value.Text+" + 1")
			}
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
	return call
}

func (p *Parser) text(token lexer.Token) *syntax.Expression {
	raw := token.Text[1 : len(token.Text)-1]
	e := &syntax.Expression{Kind: syntax.KindText, Pos: token.Pos}
	if !strings.ContainsAny(raw, "\\{") {
		e.Parts = []syntax.TextPart{{Text: strings.Clone(raw)}}
		return e
	}
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
		value := func() *syntax.Expression {
			// A failure inside the braces is often a literal brace the writer
			// forgot to escape, so every such failure also states the escape.
			defer func() {
				if r := recover(); r != nil {
					if diagnostic, ok := r.(syntax.Diagnostic); ok {
						diagnostic.Message += fmt.Sprintf(" ('{' at column %d starts an interpolation; write \\{ and \\} for literal braces)", token.Pos.Column+start)
						panic(diagnostic)
					}
					panic(r)
				}
			}()
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
				tokens[index].End = shift(tokens[index].End)
			}
			nested := &Parser{tokens: tokens, depth: p.depth}
			value := nested.expression(0)
			nested.newlines()
			nested.need(lexer.EOF)
			return value
		}()
		e.Parts = append(e.Parts, syntax.TextPart{Value: value})
	}
	flush()
	if len(e.Parts) == 0 {
		e.Parts = []syntax.TextPart{{Text: ""}}
	}
	return e
}

func (p *Parser) matchArms(header lexer.Token) []syntax.Arm {
	var arms []syntax.Arm
	p.need(":")
	p.need(lexer.Newline)
	p.need(lexer.Indent)
	for {
		p.newlines()
		if p.peek().Kind == lexer.Dedent {
			if len(arms) == 0 {
				p.fail(header, "match requires at least one arm; add a case pattern or '_' arm under the header")
			}
			break
		}
		a := syntax.Arm{Pos: p.peek().Pos}
		if k := p.peek().Kind; k == lexer.Number || k == "true" || k == "false" {
			p.fail(p.peek(), "literal match patterns are unsupported; match arms select alternative cases or concrete types, so compare values with 'if x == 1:' and 'else if'")
		}
		if p.peek().Kind == lexer.String {
			p.fail(p.peek(), "string-literal match patterns are unsupported; match arms select alternative cases or concrete types, so compare strings with 'if command == \"report\":' and 'else' instead")
		}
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
					a.NamePositions = append(a.NamePositions, tok.Pos)
					if p.peek().Kind == "(" {
						p.fail(p.peek(), "patterns cannot be nested; bind the outer payload, then handle it in a separate match or helper function")
					}
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
		p.valueArm(&a)
		arms = append(arms, a)
	}
	p.need(lexer.Dedent)
	return arms
}

// Brackets may contain types or a value. Retain both interpretations of a
// single name/application until name resolution identifies the receiver.
func (p *Parser) bracket(left *syntax.Expression) *syntax.Expression {
	start := p.at
	var types []*syntax.Type
	func() {
		defer func() {
			if r := recover(); r != nil {
				if _, ok := r.(syntax.Diagnostic); !ok {
					panic(r)
				}
				types = nil
				p.at = start
			}
		}()
		types = p.typeArgs()
	}()
	if types != nil {
		e := &syntax.Expression{Kind: syntax.KindApply, Pos: left.Pos, Left: left, Types: types}
		if len(types) == 1 {
			e.Right = p.typeValue(types[0])
		}
		return e
	}
	index := p.expression(0)
	if p.peek().Kind == ":" {
		p.fail(p.peek(), "there is no slice syntax; call slice(start: 0, end: 2) on a List or String")
	}
	p.need("]")
	return &syntax.Expression{Kind: syntax.KindIndex, Pos: left.Pos, Left: left, Right: index}
}

func (p *Parser) typeValue(t *syntax.Type) *syntax.Expression {
	if t.Name == "fn" {
		return nil
	}
	names := strings.Split(t.Name, ".")
	e := &syntax.Expression{Kind: syntax.KindName, Pos: t.Pos, Text: names[0]}
	token := sort.Search(len(p.tokens), func(i int) bool { return p.tokens[i].Pos.Offset >= t.Pos.Offset })
	for index, name := range names[1:] {
		pos := p.tokens[token+2*(index+1)].Pos
		e = &syntax.Expression{Kind: syntax.KindMember, Pos: pos, Left: e, Text: name}
	}
	if len(t.Args) > 0 {
		e = &syntax.Expression{Kind: syntax.KindApply, Pos: t.Pos, Left: e, Types: copyTypes(t.Args)}
		if len(t.Args) == 1 {
			e.Right = p.typeValue(t.Args[0])
		}
	}
	return e
}

// An arm's final expression supplies its value; a statement-only arm yields Unit.
func (p *Parser) valueArm(a *syntax.Arm) {
	outer, outerReturn := p.inlineStatement, p.inlineReturn
	defer func() { p.inlineStatement, p.inlineReturn = outer, outerReturn }()
	p.inlineReturn = false
	p.need(":")
	indented := p.take(lexer.Newline)
	if indented {
		p.need(lexer.Indent)
	}
	p.inlineStatement = !indented
	for {
		a.Body = append(a.Body, p.statements(true)...)
		if !indented {
			break
		}
		p.newlines()
		if p.peek().Kind == lexer.Dedent || p.peek().Kind == lexer.EOF {
			break
		}
	}
	last := a.Body[len(a.Body)-1]
	if last.Kind == syntax.KindCall {
		a.Value = last.Value
		a.Body = a.Body[:len(a.Body)-1]
	}
	for _, statement := range a.Body {
		isTry := statement.Value != nil && statement.Value.Kind == syntax.KindUnary && statement.Value.Text == "try"
		if statement.Kind == syntax.KindCall && statement.Value.Kind != syntax.KindCall && statement.Value.Kind != syntax.KindMatch && !isTry {
			p.fail(lexer.Token{Pos: statement.Pos}, "an arm value must be its final expression")
		}
	}
	if indented {
		p.need(lexer.Dedent)
	} else {
		p.inlineStatement = false
		p.end()
	}
}

// The two possible bracket interpretations own their positions independently:
// recovery rebases each subtree, and must never shift a shared type twice.
func copyTypes(types []*syntax.Type) []*syntax.Type {
	result := make([]*syntax.Type, len(types))
	for index, typ := range types {
		copy := *typ
		copy.Args = copyTypes(typ.Args)
		copy.Params = append([]syntax.Parameter(nil), typ.Params...)
		for index := range copy.Params {
			copy.Params[index].Type = copyTypes([]*syntax.Type{typ.Params[index].Type})[0]
		}
		if typ.Result != nil {
			copy.Result = copyTypes([]*syntax.Type{typ.Result})[0]
		}
		result[index] = &copy
	}
	return result
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
	case ")":
		return "; close the parenthesis, separating items with commas"
	case "]":
		return "; close the bracket, separating items with commas"
	case "}":
		return "; close the brace, separating items with commas"
	case "(":
		return "; a call or parameter list starts with '('"
	case "from":
		if found.Kind == "," {
			return "; to import several names, write import {a, b} from \"path.ms\""
		}
		return "; imports read: import name from \"path.ms\""
	case lexer.Name:
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

// typeParamNames spells a type's parameters as the arguments of its impl receiver.
func typeParamNames(parameters []syntax.TypeParameter) string {
	if len(parameters) == 0 {
		return ""
	}
	names := make([]string, len(parameters))
	for i, parameter := range parameters {
		names[i] = parameter.Name
	}
	return "[" + strings.Join(names, ", ") + "]"
}

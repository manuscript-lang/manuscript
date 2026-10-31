package main

import (
	"bufio"
	"io"
	"math"
	"os"
	"strconv"
	"strings"
)

// ---------------------------------------------------------------- values

type Value interface{}

type Sym string

type NilT struct{}

type VoidT struct{}

var Nil = NilT{}
var Void = VoidT{}

type Pair struct {
	Car, Cdr Value
}

type Closure struct {
	names   []string // parameter names, followed by the rest name when hasRest
	np      int      // number of fixed parameters
	hasRest bool
	body    []Value
	env     *Env
	name    string
}

type Builtin struct {
	name     string
	min, max int // max < 0 means unbounded
	fn       func(in *Interp, a []Value) Value
}

type RuntimeErr struct{ msg string }

type SyntaxErr struct{ msg string }

func throw(msg string) { panic(&RuntimeErr{msg}) }

func synErr(msg string) { panic(&SyntaxErr{msg}) }

func badForm(kw string) { synErr("syntax error: bad form: " + kw) }

// ---------------------------------------------------------------- environments

type Env struct {
	names  []string
	vals   []Value
	parent *Env
	table  map[string]Value // non-nil only for the global frame
}

func (e *Env) lookup(name string) (Value, bool) {
	for env := e; env != nil; env = env.parent {
		if env.table != nil {
			v, ok := env.table[name]
			return v, ok
		}
		for i, n := range env.names {
			if n == name {
				return env.vals[i], true
			}
		}
	}
	return nil, false
}

// define binds (or rebinds) name in the innermost frame.
func (e *Env) define(name string, v Value) {
	if e.table != nil {
		e.table[name] = v
		return
	}
	for i, n := range e.names {
		if n == name {
			e.vals[i] = v
			return
		}
	}
	e.names = append(e.names, name)
	e.vals = append(e.vals, v)
}

// set updates the nearest binding of name; false if there is none.
func (e *Env) set(name string, v Value) bool {
	for env := e; env != nil; env = env.parent {
		if env.table != nil {
			if _, ok := env.table[name]; ok {
				env.table[name] = v
				return true
			}
			return false
		}
		for i, n := range env.names {
			if n == name {
				env.vals[i] = v
				return true
			}
		}
	}
	return false
}

// ---------------------------------------------------------------- reader

type Reader struct {
	src []byte
	pos int
}

func isSpace(c byte) bool { return c == ' ' || c == '\t' || c == '\n' || c == '\r' }

func isDelim(c byte) bool {
	return isSpace(c) || c == '(' || c == ')' || c == '"' || c == ';'
}

func (r *Reader) skip() {
	for r.pos < len(r.src) {
		c := r.src[r.pos]
		if isSpace(c) {
			r.pos++
		} else if c == ';' {
			for r.pos < len(r.src) && r.src[r.pos] != '\n' {
				r.pos++
			}
		} else {
			return
		}
	}
}

// top reads the next top-level datum; ok is false at end of input.
func (r *Reader) top() (Value, bool) {
	r.skip()
	if r.pos >= len(r.src) {
		return nil, false
	}
	return r.datum(), true
}

func (r *Reader) datum() Value {
	r.skip()
	if r.pos >= len(r.src) {
		synErr("syntax error: unexpected end of input")
	}
	switch r.src[r.pos] {
	case '(':
		r.pos++
		return r.list()
	case ')':
		synErr("syntax error: unexpected )")
	case '\'':
		r.pos++
		d := r.datum()
		return &Pair{Sym("quote"), &Pair{d, Nil}}
	case '"':
		r.pos++
		return r.str()
	}
	tok := r.token()
	if tok == "." {
		synErr("syntax error: unexpected .")
	}
	return classify(tok)
}

func (r *Reader) token() string {
	start := r.pos
	for r.pos < len(r.src) && !isDelim(r.src[r.pos]) {
		r.pos++
	}
	return string(r.src[start:r.pos])
}

func (r *Reader) list() Value {
	var elems []Value
	for {
		r.skip()
		if r.pos >= len(r.src) {
			synErr("syntax error: unexpected end of input")
		}
		c := r.src[r.pos]
		if c == ')' {
			r.pos++
			return buildList(elems, Nil)
		}
		if c == '.' && (r.pos+1 == len(r.src) || isDelim(r.src[r.pos+1])) {
			r.pos++
			if len(elems) == 0 {
				synErr("syntax error: bad dotted list")
			}
			r.skip()
			if r.pos >= len(r.src) {
				synErr("syntax error: unexpected end of input")
			}
			if r.src[r.pos] == ')' {
				synErr("syntax error: bad dotted list")
			}
			tail := r.datum()
			r.skip()
			if r.pos >= len(r.src) {
				synErr("syntax error: unexpected end of input")
			}
			if r.src[r.pos] != ')' {
				synErr("syntax error: bad dotted list")
			}
			r.pos++
			return buildList(elems, tail)
		}
		elems = append(elems, r.datum())
	}
}

func (r *Reader) str() Value {
	var sb strings.Builder
	for {
		if r.pos >= len(r.src) {
			synErr("syntax error: unterminated string")
		}
		c := r.src[r.pos]
		r.pos++
		if c == '"' {
			return sb.String()
		}
		if c == '\\' {
			if r.pos >= len(r.src) {
				synErr("syntax error: unterminated string")
			}
			e := r.src[r.pos]
			r.pos++
			switch e {
			case 'n':
				sb.WriteByte('\n')
			case 't':
				sb.WriteByte('\t')
			case '\\':
				sb.WriteByte('\\')
			case '"':
				sb.WriteByte('"')
			default:
				synErr("syntax error: bad escape")
			}
			continue
		}
		sb.WriteByte(c)
	}
}

func isIntLit(s string) bool {
	t := s
	if len(t) > 0 && t[0] == '-' {
		t = t[1:]
	}
	if len(t) == 0 {
		return false
	}
	for i := 0; i < len(t); i++ {
		if t[i] < '0' || t[i] > '9' {
			return false
		}
	}
	return true
}

func classify(tok string) Value {
	switch tok {
	case "#t":
		return true
	case "#f":
		return false
	}
	if tok[0] == '#' {
		synErr("syntax error: bad token: " + tok)
	}
	if isIntLit(tok) {
		n, err := strconv.ParseInt(tok, 10, 64)
		if err != nil {
			synErr("syntax error: integer out of range")
		}
		return n
	}
	return Sym(tok)
}

// ---------------------------------------------------------------- list helpers

// properList returns the elements of a proper list; ok is false otherwise.
func properList(v Value) ([]Value, bool) {
	var out []Value
	for {
		switch p := v.(type) {
		case NilT:
			return out, true
		case *Pair:
			out = append(out, p.Car)
			v = p.Cdr
		default:
			return out, false
		}
	}
}

func buildList(elems []Value, tail Value) Value {
	for i := len(elems) - 1; i >= 0; i-- {
		tail = &Pair{elems[i], tail}
	}
	return tail
}

func truthy(v Value) bool {
	b, ok := v.(bool)
	return !ok || b
}

// ---------------------------------------------------------------- printing

func show(sb *strings.Builder, v Value, wr bool) {
	switch x := v.(type) {
	case int64:
		sb.WriteString(strconv.FormatInt(x, 10))
	case bool:
		if x {
			sb.WriteString("#t")
		} else {
			sb.WriteString("#f")
		}
	case string:
		if !wr {
			sb.WriteString(x)
			return
		}
		sb.WriteByte('"')
		for i := 0; i < len(x); i++ {
			switch c := x[i]; c {
			case '\\':
				sb.WriteString(`\\`)
			case '"':
				sb.WriteString(`\"`)
			case '\n':
				sb.WriteString(`\n`)
			case '\t':
				sb.WriteString(`\t`)
			default:
				sb.WriteByte(c)
			}
		}
		sb.WriteByte('"')
	case Sym:
		sb.WriteString(string(x))
	case NilT:
		sb.WriteString("()")
	case VoidT:
		sb.WriteString("#<void>")
	case *Pair:
		sb.WriteByte('(')
		cur := x
		for {
			show(sb, cur.Car, wr)
			switch nx := cur.Cdr.(type) {
			case *Pair:
				sb.WriteByte(' ')
				cur = nx
				continue
			case NilT:
			default:
				sb.WriteString(" . ")
				show(sb, nx, wr)
			}
			break
		}
		sb.WriteByte(')')
	case *Closure:
		if x.name == "" {
			sb.WriteString("#<procedure>")
		} else {
			sb.WriteString("#<procedure " + x.name + ">")
		}
	case *Builtin:
		sb.WriteString("#<builtin " + x.name + ">")
	}
}

func repr(v Value) string {
	var sb strings.Builder
	show(&sb, v, true)
	return sb.String()
}

func displayStr(v Value) string {
	var sb strings.Builder
	show(&sb, v, false)
	return sb.String()
}

// ---------------------------------------------------------------- equality

func eqv(a, b Value) bool {
	switch x := a.(type) {
	case int64:
		y, ok := b.(int64)
		return ok && x == y
	case bool:
		y, ok := b.(bool)
		return ok && x == y
	case Sym:
		y, ok := b.(Sym)
		return ok && x == y
	case NilT:
		_, ok := b.(NilT)
		return ok
	}
	return false
}

func equal(a, b Value) bool {
	for {
		pa, ok1 := a.(*Pair)
		pb, ok2 := b.(*Pair)
		if ok1 || ok2 {
			if !(ok1 && ok2) || !equal(pa.Car, pb.Car) {
				return false
			}
			a, b = pa.Cdr, pb.Cdr
			continue
		}
		switch x := a.(type) {
		case string:
			y, ok := b.(string)
			return ok && x == y
		case VoidT:
			_, ok := b.(VoidT)
			return ok
		case *Closure, *Builtin:
			return a == b
		}
		return eqv(a, b)
	}
}

// ---------------------------------------------------------------- interpreter

const maxDepth = 10000

type Interp struct {
	out    *bufio.Writer
	global *Env
	depth  int  // non-tail procedure entries currently active
	last   byte // last byte written, 0 if none
}

func (in *Interp) write(s string) {
	if len(s) > 0 {
		in.out.WriteString(s)
		in.last = s[len(s)-1]
	}
}

func (in *Interp) enter() {
	if in.depth+1 > maxDepth {
		throw("recursion limit exceeded")
	}
	in.depth++
}

type binding struct {
	name string
	init Value
}

// parseBindings validates a let-style binding list.
func parseBindings(kw string, v Value, dup bool) []binding {
	items, ok := properList(v)
	if !ok {
		badForm(kw)
	}
	out := make([]binding, 0, len(items))
	seen := map[string]bool{}
	for _, it := range items {
		bl, ok := properList(it)
		if !ok || len(bl) != 2 {
			badForm(kw)
		}
		s, ok := bl[0].(Sym)
		if !ok {
			badForm(kw)
		}
		if dup {
			if seen[string(s)] {
				badForm(kw)
			}
			seen[string(s)] = true
		}
		out = append(out, binding{string(s), bl[1]})
	}
	return out
}

// makeClosure builds a procedure from a parameter list and body.
func makeClosure(kw string, params Value, body []Value, env *Env, name string) *Closure {
	var names []string
	np := 0
	hasRest := false
	addName := func(s Sym) {
		for _, n := range names {
			if n == string(s) {
				badForm(kw)
			}
		}
		names = append(names, string(s))
	}
	cur := params
	for {
		if s, ok := cur.(Sym); ok {
			addName(s)
			hasRest = true
			break
		}
		if _, ok := cur.(NilT); ok {
			break
		}
		p, ok := cur.(*Pair)
		if !ok {
			badForm(kw)
		}
		s, ok := p.Car.(Sym)
		if !ok {
			badForm(kw)
		}
		addName(s)
		np++
		cur = p.Cdr
	}
	return &Closure{
		names:   names[:len(names):len(names)],
		np:      np,
		hasRest: hasRest,
		body:    body,
		env:     env,
		name:    name,
	}
}

// makeLambda builds a closure from a (lambda params body...) form.
func makeLambda(form *Pair, env *Env, name string) *Closure {
	items, ok := properList(form)
	if !ok || len(items) < 3 {
		badForm("lambda")
	}
	return makeClosure("lambda", items[1], items[2:], env, name)
}

// bind creates the call frame for a closure applied to args.
func (c *Closure) bind(args []Value) *Env {
	n := len(args)
	if n < c.np || (!c.hasRest && n > c.np) {
		exp := strconv.Itoa(c.np)
		if c.hasRest {
			exp = "at least " + exp
		}
		name := c.name
		if name == "" {
			name = "lambda"
		}
		throw("wrong number of arguments to " + name + ": expected " + exp + ", got " + strconv.Itoa(n))
	}
	vals := make([]Value, len(c.names))
	copy(vals, args[:c.np])
	if c.hasRest {
		vals[c.np] = buildList(args[c.np:], Nil)
	}
	return &Env{names: c.names, vals: vals, parent: c.env}
}

// applyTail performs a call. For a builtin it returns the result with env nil.
// For a closure it returns the callee frame and the last body expression, which
// the caller evaluates in tail position. counted says whether the caller's frame
// already accounts for depth; n counts depth increments owned by the caller.
func (in *Interp) applyTail(f Value, args []Value, counted *bool, n *int) (Value, *Env, Value) {
	switch fn := f.(type) {
	case *Builtin:
		return in.callBuiltin(fn, args), nil, nil
	case *Closure:
		env := fn.bind(args)
		if !*counted {
			in.enter()
			*n++
			*counted = true
		}
		body := fn.body
		for _, e := range body[:len(body)-1] {
			in.eval(e, env, false)
		}
		return nil, env, body[len(body)-1]
	}
	throw("not a procedure: " + repr(f))
	return nil, nil, nil
}

// apply calls f from Go code (builtins); the call is non-tail.
func (in *Interp) apply(f Value, args []Value) Value {
	counted := false
	n := 0
	defer func() { in.depth -= n }()
	res, env, last := in.applyTail(f, args, &counted, &n)
	if env == nil {
		return res
	}
	return in.eval(last, env, true)
}

func (in *Interp) callBuiltin(b *Builtin, args []Value) Value {
	n := len(args)
	if n < b.min || (b.max >= 0 && n > b.max) {
		var exp string
		switch {
		case b.max < 0:
			exp = "at least " + strconv.Itoa(b.min)
		case b.min == b.max:
			exp = strconv.Itoa(b.min)
		default:
			exp = strconv.Itoa(b.min) + " to " + strconv.Itoa(b.max)
		}
		throw("wrong number of arguments to " + b.name + ": expected " + exp + ", got " + strconv.Itoa(n))
	}
	return b.fn(in, args)
}

func isSpecialName(s Sym) bool {
	switch s {
	case "quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec",
		"cond", "and", "or", "when", "unless", "try":
		return true
	}
	return false
}

func isNamedLet(p *Pair) bool {
	items, ok := properList(p)
	if !ok || len(items) < 2 {
		return false
	}
	_, isSym := items[1].(Sym)
	return isSym
}

// namedLetSetup prepares (let name ((var init)...) body...) as a call of the loop procedure.
func (in *Interp) namedLetSetup(p *Pair, env *Env) (Value, []Value) {
	items, _ := properList(p)
	if len(items) < 4 {
		badForm("let")
	}
	name := string(items[1].(Sym))
	bs := parseBindings("let", items[2], true)
	args := make([]Value, len(bs))
	names := make([]string, len(bs))
	for i, b := range bs {
		args[i] = in.eval(b.init, env, false)
		names[i] = b.name
	}
	loopEnv := &Env{names: []string{name}, vals: []Value{nil}, parent: env}
	clo := &Closure{
		names: names[:len(names):len(names)],
		np:    len(names),
		body:  items[3:],
		env:   loopEnv,
		name:  name,
	}
	loopEnv.vals[0] = clo
	return clo, args
}

// evalDefine handles (define ...) forms.
func (in *Interp) evalDefine(items []Value, env *Env) {
	if len(items) < 2 {
		badForm("define")
	}
	switch t := items[1].(type) {
	case Sym:
		if len(items) != 3 {
			badForm("define")
		}
		var val Value
		if lp, ok := items[2].(*Pair); ok && lp.Car == Sym("lambda") {
			val = makeLambda(lp, env, string(t))
		} else {
			val = in.eval(items[2], env, false)
		}
		env.define(string(t), val)
	case *Pair:
		nm, ok := t.Car.(Sym)
		if !ok || len(items) < 3 {
			badForm("define")
		}
		clo := makeClosure("define", t.Cdr, items[2:], env, string(nm))
		env.define(string(nm), clo)
	default:
		badForm("define")
	}
}

// evalPrefix evaluates all but the last expression of a body and returns the last.
func (in *Interp) evalPrefix(body []Value, env *Env) Value {
	for _, e := range body[:len(body)-1] {
		in.eval(e, env, false)
	}
	return body[len(body)-1]
}

func (in *Interp) tryEval(e Value, env *Env) (res Value, failed bool, msg string) {
	defer func() {
		if r := recover(); r != nil {
			re, ok := r.(*RuntimeErr)
			if !ok {
				panic(r)
			}
			failed = true
			msg = re.msg
		}
	}()
	return in.eval(e, env, false), false, ""
}

func (in *Interp) evalApp(p *Pair, env *Env) (Value, []Value) {
	items, ok := properList(p)
	if !ok {
		synErr("syntax error: bad application")
	}
	f := in.eval(items[0], env, false)
	args := make([]Value, len(items)-1)
	for i, a := range items[1:] {
		args[i] = in.eval(a, env, false)
	}
	return f, args
}

// eval evaluates x. counted reports whether the frame this evaluation runs in
// already counts toward the call depth.
func (in *Interp) eval(x Value, env *Env, counted bool) Value {
	n := 0
	defer func() { in.depth -= n }()
	for {
		var f Value
		var args []Value
		switch v := x.(type) {
		case Sym:
			val, ok := env.lookup(string(v))
			if !ok {
				throw("unbound variable: " + string(v))
			}
			return val
		case NilT:
			synErr("syntax error: empty application")
		case *Pair:
			head, isSym := v.Car.(Sym)
			if !isSym {
				f, args = in.evalApp(v, env)
				break
			}
			if head == "let" && isNamedLet(v) {
				f, args = in.namedLetSetup(v, env)
				break
			}
			if !isSpecialName(head) {
				f, args = in.evalApp(v, env)
				break
			}
			items, ok := properList(v)
			if !ok {
				badForm(string(head))
			}
			switch head {
			case "quote":
				if len(items) != 2 {
					badForm("quote")
				}
				return items[1]
			case "if":
				if len(items) != 3 && len(items) != 4 {
					badForm("if")
				}
				if truthy(in.eval(items[1], env, false)) {
					x = items[2]
					continue
				}
				if len(items) == 4 {
					x = items[3]
					continue
				}
				return Void
			case "define":
				in.evalDefine(items, env)
				return Void
			case "set!":
				if len(items) != 3 {
					badForm("set!")
				}
				name, ok := items[1].(Sym)
				if !ok {
					badForm("set!")
				}
				val := in.eval(items[2], env, false)
				if !env.set(string(name), val) {
					throw("unbound variable: " + string(name))
				}
				return Void
			case "lambda":
				return makeLambda(v, env, "")
			case "begin":
				if len(items) == 1 {
					return Void
				}
				x = in.evalPrefix(items[1:], env)
				continue
			case "let":
				if len(items) < 3 {
					badForm("let")
				}
				bs := parseBindings("let", items[1], true)
				names := make([]string, len(bs))
				vals := make([]Value, len(bs))
				for i, b := range bs {
					vals[i] = in.eval(b.init, env, false)
					names[i] = b.name
				}
				env = &Env{names: names, vals: vals, parent: env}
				x = in.evalPrefix(items[2:], env)
				continue
			case "let*", "letrec":
				if len(items) < 3 {
					badForm(string(head))
				}
				bs := parseBindings(string(head), items[1], false)
				frame := &Env{parent: env}
				for _, b := range bs {
					frame.define(b.name, in.eval(b.init, frame, false))
				}
				env = frame
				x = in.evalPrefix(items[2:], env)
				continue
			case "cond":
				res, nx, isTail := in.evalCond(items[1:], env)
				if !isTail {
					return res
				}
				x = nx
				continue
			case "and":
				if len(items) == 1 {
					return true
				}
				for _, e := range items[1 : len(items)-1] {
					if r := in.eval(e, env, false); !truthy(r) {
						return r
					}
				}
				x = items[len(items)-1]
				continue
			case "or":
				if len(items) == 1 {
					return false
				}
				for _, e := range items[1 : len(items)-1] {
					if r := in.eval(e, env, false); truthy(r) {
						return r
					}
				}
				x = items[len(items)-1]
				continue
			case "when", "unless":
				if len(items) < 3 {
					badForm(string(head))
				}
				t := truthy(in.eval(items[1], env, false))
				if t != (head == "when") {
					return Void
				}
				x = in.evalPrefix(items[2:], env)
				continue
			case "try":
				if len(items) != 3 {
					badForm("try")
				}
				res, failed, msg := in.tryEval(items[1], env)
				if !failed {
					return res
				}
				h := in.eval(items[2], env, false)
				return in.apply(h, []Value{msg})
			}
			panic("unreachable")
		default:
			return x
		}

		// application in tail position
		res, nenv, last := in.applyTail(f, args, &counted, &n)
		if nenv == nil {
			return res
		}
		env = nenv
		x = last
	}
}

// evalCond evaluates cond clauses. If isTail is true, the result is the
// expression nx to evaluate in tail position of the cond.
func (in *Interp) evalCond(clauses []Value, env *Env) (res Value, nx Value, isTail bool) {
	for i, c := range clauses {
		cl, ok := properList(c)
		if !ok || len(cl) == 0 {
			badForm("cond")
		}
		if s, isS := cl[0].(Sym); isS && s == "else" {
			if i != len(clauses)-1 || len(cl) < 2 {
				badForm("cond")
			}
			return nil, in.evalPrefix(cl[1:], env), true
		}
		t := in.eval(cl[0], env, false)
		if truthy(t) {
			if len(cl) == 1 {
				return t, nil, false
			}
			return nil, in.evalPrefix(cl[1:], env), true
		}
	}
	return Void, nil, false
}

// ---------------------------------------------------------------- builtins

func wantInt(name string, v Value) int64 {
	if n, ok := v.(int64); ok {
		return n
	}
	throw(name + ": expected integer, got " + repr(v))
	return 0
}

func wantStr(name string, v Value) string {
	if s, ok := v.(string); ok {
		return s
	}
	throw(name + ": expected string, got " + repr(v))
	return ""
}

func wantList(name string, v Value) []Value {
	items, ok := properList(v)
	if !ok {
		throw(name + ": expected list, got " + repr(v))
	}
	return items
}

func wantProc(name string, v Value) Value {
	switch v.(type) {
	case *Closure, *Builtin:
		return v
	}
	throw(name + ": expected procedure, got " + repr(v))
	return nil
}

func addInt(a, b int64) int64 {
	r := a + b
	if (b >= 0 && r < a) || (b < 0 && r > a) {
		throw("integer overflow")
	}
	return r
}

func subInt(a, b int64) int64 {
	r := a - b
	if (b >= 0 && r > a) || (b < 0 && r < a) {
		throw("integer overflow")
	}
	return r
}

func mulInt(a, b int64) int64 {
	if a == 0 || b == 0 {
		return 0
	}
	r := a * b
	if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) || r/b != a {
		throw("integer overflow")
	}
	return r
}

func divCheck(b int64) {
	if b == 0 {
		throw("division by zero")
	}
}

func quotientInt(a, b int64) int64 {
	divCheck(b)
	if a == math.MinInt64 && b == -1 {
		throw("integer overflow")
	}
	return a / b
}

func remainderInt(a, b int64) int64 {
	divCheck(b)
	if b == -1 {
		return 0
	}
	return a % b
}

func moduloInt(a, b int64) int64 {
	divCheck(b)
	if b == -1 {
		return 0
	}
	r := a % b
	if r != 0 && ((r < 0) != (b < 0)) {
		r += b
	}
	return r
}

func (in *Interp) msort(xs []Value, less Value) []Value {
	if len(xs) <= 1 {
		return xs
	}
	mid := len(xs) / 2
	l := in.msort(xs[:mid], less)
	r := in.msort(xs[mid:], less)
	out := make([]Value, 0, len(xs))
	i, j := 0, 0
	for i < len(l) && j < len(r) {
		if truthy(in.apply(less, []Value{r[j], l[i]})) {
			out = append(out, r[j])
			j++
		} else {
			out = append(out, l[i])
			i++
		}
	}
	out = append(out, l[i:]...)
	out = append(out, r[j:]...)
	return out
}

func cxr(name, path string) func(in *Interp, a []Value) Value {
	return func(in *Interp, a []Value) Value {
		v := a[0]
		for i := len(path) - 1; i >= 0; i-- {
			p, ok := v.(*Pair)
			if !ok {
				throw(name + ": expected pair, got " + repr(v))
			}
			if path[i] == 'a' {
				v = p.Car
			} else {
				v = p.Cdr
			}
		}
		return v
	}
}

func (in *Interp) installBuiltins() {
	def := func(name string, min, max int, fn func(in *Interp, a []Value) Value) {
		in.global.table[name] = &Builtin{name, min, max, fn}
	}
	cmp := func(name string, ok func(a, b int64) bool) func(in *Interp, a []Value) Value {
		return func(in *Interp, a []Value) Value {
			nums := make([]int64, len(a))
			for i, v := range a {
				nums[i] = wantInt(name, v)
			}
			res := true
			for i := 0; i+1 < len(nums); i++ {
				if !ok(nums[i], nums[i+1]) {
					res = false
				}
			}
			return res
		}
	}

	// numbers
	def("+", 0, -1, func(in *Interp, a []Value) Value {
		var acc int64
		for _, v := range a {
			acc = addInt(acc, wantInt("+", v))
		}
		return acc
	})
	def("-", 1, -1, func(in *Interp, a []Value) Value {
		if len(a) == 1 {
			x := wantInt("-", a[0])
			if x == math.MinInt64 {
				throw("integer overflow")
			}
			return -x
		}
		acc := wantInt("-", a[0])
		for _, v := range a[1:] {
			acc = subInt(acc, wantInt("-", v))
		}
		return acc
	})
	def("*", 0, -1, func(in *Interp, a []Value) Value {
		acc := int64(1)
		for _, v := range a {
			acc = mulInt(acc, wantInt("*", v))
		}
		return acc
	})
	def("quotient", 2, 2, func(in *Interp, a []Value) Value {
		x := wantInt("quotient", a[0])
		return quotientInt(x, wantInt("quotient", a[1]))
	})
	def("remainder", 2, 2, func(in *Interp, a []Value) Value {
		x := wantInt("remainder", a[0])
		return remainderInt(x, wantInt("remainder", a[1]))
	})
	def("modulo", 2, 2, func(in *Interp, a []Value) Value {
		x := wantInt("modulo", a[0])
		return moduloInt(x, wantInt("modulo", a[1]))
	})
	def("abs", 1, 1, func(in *Interp, a []Value) Value {
		x := wantInt("abs", a[0])
		if x < 0 {
			if x == math.MinInt64 {
				throw("integer overflow")
			}
			return -x
		}
		return x
	})
	minmax := func(name string, pickFirst func(a, b int64) bool) func(in *Interp, a []Value) Value {
		return func(in *Interp, a []Value) Value {
			m := wantInt(name, a[0])
			for _, v := range a[1:] {
				x := wantInt(name, v)
				if pickFirst(x, m) {
					m = x
				}
			}
			return m
		}
	}
	def("min", 1, -1, minmax("min", func(a, b int64) bool { return a < b }))
	def("max", 1, -1, minmax("max", func(a, b int64) bool { return a > b }))
	def("=", 2, -1, cmp("=", func(a, b int64) bool { return a == b }))
	def("<", 2, -1, cmp("<", func(a, b int64) bool { return a < b }))
	def(">", 2, -1, cmp(">", func(a, b int64) bool { return a > b }))
	def("<=", 2, -1, cmp("<=", func(a, b int64) bool { return a <= b }))
	def(">=", 2, -1, cmp(">=", func(a, b int64) bool { return a >= b }))
	def("zero?", 1, 1, func(in *Interp, a []Value) Value { return wantInt("zero?", a[0]) == 0 })
	def("even?", 1, 1, func(in *Interp, a []Value) Value { return wantInt("even?", a[0])%2 == 0 })
	def("odd?", 1, 1, func(in *Interp, a []Value) Value { return wantInt("odd?", a[0])%2 != 0 })

	// predicates and equality
	def("not", 1, 1, func(in *Interp, a []Value) Value {
		b, ok := a[0].(bool)
		return ok && !b
	})
	def("null?", 1, 1, func(in *Interp, a []Value) Value { _, ok := a[0].(NilT); return ok })
	def("pair?", 1, 1, func(in *Interp, a []Value) Value { _, ok := a[0].(*Pair); return ok })
	def("list?", 1, 1, func(in *Interp, a []Value) Value { _, ok := properList(a[0]); return ok })
	def("number?", 1, 1, func(in *Interp, a []Value) Value { _, ok := a[0].(int64); return ok })
	def("string?", 1, 1, func(in *Interp, a []Value) Value { _, ok := a[0].(string); return ok })
	def("symbol?", 1, 1, func(in *Interp, a []Value) Value { _, ok := a[0].(Sym); return ok })
	def("boolean?", 1, 1, func(in *Interp, a []Value) Value { _, ok := a[0].(bool); return ok })
	def("procedure?", 1, 1, func(in *Interp, a []Value) Value {
		switch a[0].(type) {
		case *Closure, *Builtin:
			return true
		}
		return false
	})
	def("eq?", 2, 2, func(in *Interp, a []Value) Value { return eqv(a[0], a[1]) })
	def("equal?", 2, 2, func(in *Interp, a []Value) Value { return equal(a[0], a[1]) })

	// pairs and lists
	def("cons", 2, 2, func(in *Interp, a []Value) Value { return &Pair{a[0], a[1]} })
	def("car", 1, 1, cxr("car", "a"))
	def("cdr", 1, 1, cxr("cdr", "d"))
	def("cadr", 1, 1, cxr("cadr", "ad"))
	def("cddr", 1, 1, cxr("cddr", "dd"))
	def("caddr", 1, 1, cxr("caddr", "add"))
	def("set-car!", 2, 2, func(in *Interp, a []Value) Value {
		p, ok := a[0].(*Pair)
		if !ok {
			throw("set-car!: expected pair, got " + repr(a[0]))
		}
		p.Car = a[1]
		return Void
	})
	def("set-cdr!", 2, 2, func(in *Interp, a []Value) Value {
		p, ok := a[0].(*Pair)
		if !ok {
			throw("set-cdr!: expected pair, got " + repr(a[0]))
		}
		p.Cdr = a[1]
		return Void
	})
	def("list", 0, -1, func(in *Interp, a []Value) Value { return buildList(a, Nil) })
	def("length", 1, 1, func(in *Interp, a []Value) Value {
		return int64(len(wantList("length", a[0])))
	})
	def("append", 0, -1, func(in *Interp, a []Value) Value {
		if len(a) == 0 {
			return Nil
		}
		last := len(a) - 1
		parts := make([][]Value, last)
		for i := 0; i < last; i++ {
			parts[i] = wantList("append", a[i])
		}
		res := a[last]
		for i := last - 1; i >= 0; i-- {
			res = buildList(parts[i], res)
		}
		return res
	})
	def("reverse", 1, 1, func(in *Interp, a []Value) Value {
		xs := wantList("reverse", a[0])
		var res Value = Nil
		for _, x := range xs {
			res = &Pair{x, res}
		}
		return res
	})
	def("list-ref", 2, 2, func(in *Interp, a []Value) Value {
		lst := wantList("list-ref", a[0])
		k := wantInt("list-ref", a[1])
		if k < 0 || k >= int64(len(lst)) {
			throw("list-ref: index out of range")
		}
		return lst[k]
	})
	def("list-tail", 2, 2, func(in *Interp, a []Value) Value {
		wantList("list-tail", a[0])
		k := wantInt("list-tail", a[1])
		v := a[0]
		for i := int64(0); i < k; i++ {
			p, ok := v.(*Pair)
			if !ok {
				throw("list-tail: index out of range")
			}
			v = p.Cdr
		}
		return v
	})
	def("range", 2, 2, func(in *Interp, a []Value) Value {
		lo := wantInt("range", a[0])
		hi := wantInt("range", a[1])
		if lo >= hi {
			return Nil
		}
		elems := make([]Value, 0, hi-lo)
		for i := lo; i < hi; i++ {
			elems = append(elems, i)
		}
		return buildList(elems, Nil)
	})
	def("assoc", 2, 2, func(in *Interp, a []Value) Value {
		alist := wantList("assoc", a[1])
		for _, e := range alist {
			if _, ok := e.(*Pair); !ok {
				throw("assoc: expected pair, got " + repr(e))
			}
		}
		for _, e := range alist {
			p := e.(*Pair)
			if equal(a[0], p.Car) {
				return p
			}
		}
		return false
	})
	def("member", 2, 2, func(in *Interp, a []Value) Value {
		wantList("member", a[1])
		for cur := a[1]; ; {
			p, ok := cur.(*Pair)
			if !ok {
				return false
			}
			if equal(a[0], p.Car) {
				return p
			}
			cur = p.Cdr
		}
	})

	// higher-order
	def("map", 2, -1, func(in *Interp, a []Value) Value {
		f := wantProc("map", a[0])
		lists := make([][]Value, len(a)-1)
		for i, l := range a[1:] {
			lists[i] = wantList("map", l)
		}
		n := minLen(lists)
		out := make([]Value, n)
		for k := 0; k < n; k++ {
			args := make([]Value, len(lists))
			for j := range lists {
				args[j] = lists[j][k]
			}
			out[k] = in.apply(f, args)
		}
		return buildList(out, Nil)
	})
	def("for-each", 2, -1, func(in *Interp, a []Value) Value {
		f := wantProc("for-each", a[0])
		lists := make([][]Value, len(a)-1)
		for i, l := range a[1:] {
			lists[i] = wantList("for-each", l)
		}
		n := minLen(lists)
		for k := 0; k < n; k++ {
			args := make([]Value, len(lists))
			for j := range lists {
				args[j] = lists[j][k]
			}
			in.apply(f, args)
		}
		return Void
	})
	def("filter", 2, 2, func(in *Interp, a []Value) Value {
		f := wantProc("filter", a[0])
		xs := wantList("filter", a[1])
		var out []Value
		for _, x := range xs {
			if truthy(in.apply(f, []Value{x})) {
				out = append(out, x)
			}
		}
		return buildList(out, Nil)
	})
	def("fold", 3, 3, func(in *Interp, a []Value) Value {
		f := wantProc("fold", a[0])
		xs := wantList("fold", a[2])
		acc := a[1]
		for _, x := range xs {
			acc = in.apply(f, []Value{acc, x})
		}
		return acc
	})
	def("foldr", 3, 3, func(in *Interp, a []Value) Value {
		f := wantProc("foldr", a[0])
		xs := wantList("foldr", a[2])
		acc := a[1]
		for i := len(xs) - 1; i >= 0; i-- {
			acc = in.apply(f, []Value{xs[i], acc})
		}
		return acc
	})
	def("apply", 2, -1, func(in *Interp, a []Value) Value {
		f := wantProc("apply", a[0])
		last := len(a) - 1
		tail := wantList("apply", a[last])
		args := make([]Value, 0, len(a)-2+len(tail))
		args = append(args, a[1:last]...)
		args = append(args, tail...)
		return in.apply(f, args)
	})
	def("sort", 2, 2, func(in *Interp, a []Value) Value {
		less := wantProc("sort", a[1])
		xs := wantList("sort", a[0])
		return buildList(in.msort(xs, less), Nil)
	})

	// strings
	def("string-length", 1, 1, func(in *Interp, a []Value) Value {
		return int64(len(wantStr("string-length", a[0])))
	})
	def("string-append", 0, -1, func(in *Interp, a []Value) Value {
		var sb strings.Builder
		for _, v := range a {
			sb.WriteString(wantStr("string-append", v))
		}
		return sb.String()
	})
	def("substring", 3, 3, func(in *Interp, a []Value) Value {
		s := wantStr("substring", a[0])
		st := wantInt("substring", a[1])
		en := wantInt("substring", a[2])
		if st < 0 || en > int64(len(s)) || st > en {
			throw("substring: index out of range")
		}
		return s[st:en]
	})
	def("string-ref", 2, 2, func(in *Interp, a []Value) Value {
		s := wantStr("string-ref", a[0])
		k := wantInt("string-ref", a[1])
		if k < 0 || k >= int64(len(s)) {
			throw("string-ref: index out of range")
		}
		return s[k : k+1]
	})
	def("string=?", 2, 2, func(in *Interp, a []Value) Value {
		x := wantStr("string=?", a[0])
		return x == wantStr("string=?", a[1])
	})
	def("string<?", 2, 2, func(in *Interp, a []Value) Value {
		x := wantStr("string<?", a[0])
		return x < wantStr("string<?", a[1])
	})
	def("string-upcase", 1, 1, func(in *Interp, a []Value) Value {
		return asciiCase(wantStr("string-upcase", a[0]), true)
	})
	def("string-downcase", 1, 1, func(in *Interp, a []Value) Value {
		return asciiCase(wantStr("string-downcase", a[0]), false)
	})
	def("string->number", 1, 1, func(in *Interp, a []Value) Value {
		s := wantStr("string->number", a[0])
		if !isIntLit(s) {
			return false
		}
		n, err := strconv.ParseInt(s, 10, 64)
		if err != nil {
			return false
		}
		return n
	})
	def("number->string", 1, 1, func(in *Interp, a []Value) Value {
		return strconv.FormatInt(wantInt("number->string", a[0]), 10)
	})
	def("string->symbol", 1, 1, func(in *Interp, a []Value) Value {
		return Sym(wantStr("string->symbol", a[0]))
	})
	def("symbol->string", 1, 1, func(in *Interp, a []Value) Value {
		s, ok := a[0].(Sym)
		if !ok {
			throw("symbol->string: expected symbol, got " + repr(a[0]))
		}
		return string(s)
	})
	def("string->list", 1, 1, func(in *Interp, a []Value) Value {
		s := wantStr("string->list", a[0])
		elems := make([]Value, len(s))
		for i := 0; i < len(s); i++ {
			elems[i] = s[i : i+1]
		}
		return buildList(elems, Nil)
	})
	def("list->string", 1, 1, func(in *Interp, a []Value) Value {
		xs := wantList("list->string", a[0])
		var sb strings.Builder
		for _, x := range xs {
			sb.WriteString(wantStr("list->string", x))
		}
		return sb.String()
	})
	def("string-join", 2, 2, func(in *Interp, a []Value) Value {
		xs := wantList("string-join", a[0])
		sep := wantStr("string-join", a[1])
		parts := make([]string, len(xs))
		for i, x := range xs {
			parts[i] = wantStr("string-join", x)
		}
		return strings.Join(parts, sep)
	})
	def("string-split", 2, 2, func(in *Interp, a []Value) Value {
		s := wantStr("string-split", a[0])
		sep := wantStr("string-split", a[1])
		if len(sep) != 1 {
			throw("string-split: separator must be one character")
		}
		parts := strings.Split(s, sep)
		elems := make([]Value, len(parts))
		for i, p := range parts {
			elems[i] = p
		}
		return buildList(elems, Nil)
	})
	def("string-contains?", 2, 2, func(in *Interp, a []Value) Value {
		s := wantStr("string-contains?", a[0])
		return strings.Contains(s, wantStr("string-contains?", a[1]))
	})

	// output and misc
	def("display", 1, 1, func(in *Interp, a []Value) Value {
		in.write(displayStr(a[0]))
		return Void
	})
	def("write", 1, 1, func(in *Interp, a []Value) Value {
		in.write(repr(a[0]))
		return Void
	})
	def("newline", 0, 0, func(in *Interp, a []Value) Value {
		in.write("\n")
		return Void
	})
	def("void", 0, 0, func(in *Interp, a []Value) Value { return Void })
	def("error", 1, -1, func(in *Interp, a []Value) Value {
		var sb strings.Builder
		sb.WriteString(wantStr("error", a[0]))
		for _, v := range a[1:] {
			sb.WriteByte(' ')
			show(&sb, v, true)
		}
		throw(sb.String())
		return Void
	})
}

func minLen(lists [][]Value) int {
	n := -1
	for _, l := range lists {
		if n < 0 || len(l) < n {
			n = len(l)
		}
	}
	if n < 0 {
		return 0
	}
	return n
}

func asciiCase(s string, upper bool) string {
	b := []byte(s)
	for i, c := range b {
		if upper && c >= 'a' && c <= 'z' {
			b[i] = c - 32
		} else if !upper && c >= 'A' && c <= 'Z' {
			b[i] = c + 32
		}
	}
	return string(b)
}

// ---------------------------------------------------------------- top level

// runTop evaluates the next top-level form. It returns false at end of input
// or after an uncaught error (which has been reported).
func (in *Interp) runTop(r *Reader) (cont bool) {
	defer func() {
		if rec := recover(); rec != nil {
			var msg string
			switch e := rec.(type) {
			case *RuntimeErr:
				msg = e.msg
			case *SyntaxErr:
				msg = e.msg
			default:
				panic(rec)
			}
			if in.last != 0 && in.last != '\n' {
				in.write("\n")
			}
			in.write("error: " + msg + "\n")
			cont = false
		}
	}()
	x, ok := r.top()
	if !ok {
		return false
	}
	in.eval(x, in.global, false)
	return true
}

func main() {
	src, _ := io.ReadAll(os.Stdin)
	in := &Interp{
		out:    bufio.NewWriter(os.Stdout),
		global: &Env{table: map[string]Value{}},
	}
	in.installBuiltins()
	r := &Reader{src: src}
	for in.runTop(r) {
	}
	in.out.Flush()
}

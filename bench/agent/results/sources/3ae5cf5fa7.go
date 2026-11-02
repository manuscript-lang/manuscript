package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"
)

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

type Kind int

const (
	KEmpty Kind = iota
	KNum
	KText
	KBool
	KErr
)

type Value struct {
	K Kind
	N float64
	S string // text, or error code when K == KErr
	B bool
}

func vNum(f float64) Value   { return Value{K: KNum, N: f} }
func vText(s string) Value   { return Value{K: KText, S: s} }
func vBool(b bool) Value     { return Value{K: KBool, B: b} }
func vErr(code string) Value { return Value{K: KErr, S: code} }
func numRes(f float64) Value {
	if math.IsNaN(f) || math.IsInf(f, 0) {
		return vErr("#NUM!")
	}
	return vNum(f)
}

func finite(f float64) bool { return !math.IsNaN(f) && !math.IsInf(f, 0) }

func fmtNum(f float64) string {
	s := strconv.FormatFloat(f, 'f', 10, 64)
	if strings.Contains(s, ".") {
		s = strings.TrimRight(s, "0")
		s = strings.TrimSuffix(s, ".")
	}
	if s == "-0" {
		s = "0"
	}
	return s
}

func display(v Value) string {
	switch v.K {
	case KNum:
		return fmtNum(v.N)
	case KText:
		return v.S
	case KBool:
		if v.B {
			return "TRUE"
		}
		return "FALSE"
	case KErr:
		return v.S
	}
	return ""
}

// toStr: string form; error code returned when v is an error.
func toStr(v Value) (string, string) {
	if v.K == KErr {
		return "", v.S
	}
	return display(v), ""
}

var numberRe = regexp.MustCompile(`^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$`)

// parseNumLit: number grammar, finite, no trimming.
func parseNumLit(s string) (float64, bool) {
	if !numberRe.MatchString(s) {
		return 0, false
	}
	f, err := strconv.ParseFloat(s, 64)
	if err != nil && !errors.Is(err, strconv.ErrRange) {
		return 0, false
	}
	if !finite(f) {
		return 0, false
	}
	return f, true
}

func trimWS(s string) string      { return strings.Trim(s, " \t\r\n\v\f") }
func trimRightWS(s string) string { return strings.TrimRight(s, " \t\r\n\v\f") }
func trimLeftWS(s string) string  { return strings.TrimLeft(s, " \t\r\n\v\f") }

// toNum: number coercion; error code returned on failure ("" when ok).
func toNum(v Value) (float64, string) {
	switch v.K {
	case KNum:
		return v.N, ""
	case KBool:
		if v.B {
			return 1, ""
		}
		return 0, ""
	case KEmpty:
		return 0, ""
	case KText:
		if f, ok := parseNumLit(trimWS(v.S)); ok {
			return f, ""
		}
		return 0, "#VALUE!"
	}
	return 0, v.S
}

// toBool: boolean coercion.
func toBool(v Value) (bool, string) {
	switch v.K {
	case KNum:
		return v.N != 0, ""
	case KBool:
		return v.B, ""
	case KEmpty:
		return false, ""
	case KText:
		if strings.EqualFold(v.S, "TRUE") {
			return true, ""
		}
		if strings.EqualFold(v.S, "FALSE") {
			return false, ""
		}
		return false, "#VALUE!"
	}
	return false, v.S
}

func rankOf(k Kind) int {
	switch k {
	case KNum:
		return 0
	case KText:
		return 1
	case KBool:
		return 2
	}
	return 3
}

func zeroOf(v Value) Value {
	switch v.K {
	case KNum:
		return vNum(0)
	case KText:
		return vText("")
	case KBool:
		return vBool(false)
	}
	return Value{}
}

// compareVals assumes neither side is an error.
func compareVals(l, r Value) int {
	if l.K == KEmpty && r.K == KEmpty {
		return 0
	}
	if l.K == KEmpty {
		l = zeroOf(r)
	}
	if r.K == KEmpty {
		r = zeroOf(l)
	}
	if l.K != r.K {
		if rankOf(l.K) < rankOf(r.K) {
			return -1
		}
		return 1
	}
	switch l.K {
	case KNum:
		switch {
		case l.N < r.N:
			return -1
		case l.N > r.N:
			return 1
		}
		return 0
	case KText:
		return strings.Compare(l.S, r.S)
	case KBool:
		switch {
		case l.B == r.B:
			return 0
		case !l.B:
			return -1
		}
		return 1
	}
	return 0
}

func opHolds(op string, c int) bool {
	switch op {
	case "=":
		return c == 0
	case "<>":
		return c != 0
	case "<":
		return c < 0
	case "<=":
		return c <= 0
	case ">":
		return c > 0
	case ">=":
		return c >= 0
	}
	return false
}

// ---------------------------------------------------------------------------
// Grid positions and references
// ---------------------------------------------------------------------------

type Pos struct{ c, r int } // c: 0..25 (A..Z), r: 1..999

func (p Pos) name() string { return string(rune('A'+p.c)) + strconv.Itoa(p.r) }

type Rect struct{ c1, r1, c2, r2 int } // normalized, inclusive

func (r Rect) contains(p Pos) bool {
	return p.c >= r.c1 && p.c <= r.c2 && p.r >= r.r1 && p.r <= r.r2
}

func normRect(a, b Pos) Rect {
	r := Rect{a.c, a.r, b.c, b.r}
	if r.c1 > r.c2 {
		r.c1, r.c2 = r.c2, r.c1
	}
	if r.r1 > r.r2 {
		r.r1, r.r2 = r.r2, r.r1
	}
	return r
}

func sortPos(ps []Pos) {
	sort.Slice(ps, func(i, j int) bool {
		if ps[i].r != ps[j].r {
			return ps[i].r < ps[j].r
		}
		return ps[i].c < ps[j].c
	})
}

var cellRe = regexp.MustCompile(`^([A-Za-z])([1-9][0-9]{0,2})$`)

// parseCellTok parses a command-argument cell reference.
func parseCellTok(t string) (Pos, bool) {
	m := cellRe.FindStringSubmatch(t)
	if m == nil {
		return Pos{}, false
	}
	r, _ := strconv.Atoi(m[2])
	return Pos{int(upperByte(m[1][0]) - 'A'), r}, true
}

// parseRangeTok parses a command-argument range (cell or cell:cell).
func parseRangeTok(t string) (Rect, bool) {
	parts := strings.Split(t, ":")
	if len(parts) == 1 {
		p, ok := parseCellTok(t)
		if !ok {
			return Rect{}, false
		}
		return Rect{p.c, p.r, p.c, p.r}, true
	}
	if len(parts) != 2 {
		return Rect{}, false
	}
	a, ok1 := parseCellTok(parts[0])
	b, ok2 := parseCellTok(parts[1])
	if !ok1 || !ok2 {
		return Rect{}, false
	}
	return normRect(a, b), true
}

func upperByte(c byte) byte {
	if c >= 'a' && c <= 'z' {
		return c - 32
	}
	return c
}

func isLetter(c byte) bool { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') }
func isDigit(c byte) bool  { return c >= '0' && c <= '9' }
func isIdentChar(c byte) bool {
	return isLetter(c) || isDigit(c) || c == '_' || c == '.'
}

func allDigits(s string) bool {
	for i := 0; i < len(s); i++ {
		if !isDigit(s[i]) {
			return false
		}
	}
	return len(s) > 0
}

// refText is a parsed reference word such as $A$1 (structure assumed valid).
type refText struct {
	col, row   int
	cAbs, rAbs bool
	valid      bool
}

func parseRef(s string) refText {
	var r refText
	i := 0
	if i < len(s) && s[i] == '$' {
		r.cAbs = true
		i++
	}
	ls := i
	for i < len(s) && isLetter(s[i]) {
		i++
	}
	letters := s[ls:i]
	if i < len(s) && s[i] == '$' {
		r.rAbs = true
		i++
	}
	digits := s[i:]
	r.valid = len(letters) == 1 && len(digits) >= 1 && len(digits) <= 3 &&
		digits[0] != '0' && allDigits(digits)
	if r.valid {
		r.col = int(upperByte(letters[0]) - 'A')
		r.row, _ = strconv.Atoi(digits)
	}
	return r
}

// ---------------------------------------------------------------------------
// Formula lexer
// ---------------------------------------------------------------------------

type tkind int

const (
	tNum tkind = iota
	tStr
	tRef
	tRange
	tErrRef
	tIdent
	tOp
	tLP
	tRP
	tComma
	tEOF
)

type token struct {
	k          tkind
	text       string
	start, end int
	num        float64
	str        string
	op         string
	ref, ref2  refText
}

// matchRef returns the end index of a reference word starting at i, or -1.
func matchRef(src string, i int) int {
	n := len(src)
	j := i
	if j < n && src[j] == '$' {
		j++
	}
	ls := j
	for j < n && isLetter(src[j]) {
		j++
	}
	if j == ls {
		return -1
	}
	if j < n && src[j] == '$' {
		j++
	}
	ds := j
	for j < n && isDigit(src[j]) {
		j++
	}
	if j == ds {
		return -1
	}
	if j < n && (isIdentChar(src[j]) || src[j] == '(' || src[j] == '$') {
		return -1
	}
	return j
}

func lex(src string) ([]token, bool) {
	var toks []token
	n := len(src)
	i := 0
	for {
		for i < n && (src[i] == ' ' || src[i] == '\t') {
			i++
		}
		if i >= n {
			break
		}
		c := src[i]
		start := i
		switch {
		case isDigit(c) || (c == '.' && i+1 < n && isDigit(src[i+1])):
			j := i
			for j < n && isDigit(src[j]) {
				j++
			}
			if j < n && src[j] == '.' {
				j++
				for j < n && isDigit(src[j]) {
					j++
				}
			}
			if j < n && (src[j] == 'e' || src[j] == 'E') {
				k := j + 1
				if k < n && (src[k] == '+' || src[k] == '-') {
					k++
				}
				if k < n && isDigit(src[k]) {
					for k < n && isDigit(src[k]) {
						k++
					}
					j = k
				}
			}
			text := src[i:j]
			f, err := strconv.ParseFloat(text, 64)
			if err != nil && !errors.Is(err, strconv.ErrRange) {
				return nil, false
			}
			toks = append(toks, token{k: tNum, text: text, start: start, end: j, num: f})
			i = j

		case c == '"':
			j := i + 1
			var sb strings.Builder
			closed := false
			for j < n {
				if src[j] == '"' {
					if j+1 < n && src[j+1] == '"' {
						sb.WriteByte('"')
						j += 2
						continue
					}
					closed = true
					j++
					break
				}
				sb.WriteByte(src[j])
				j++
			}
			if !closed {
				return nil, false
			}
			toks = append(toks, token{k: tStr, text: src[i:j], start: start, end: j, str: sb.String()})
			i = j

		case c == '#':
			if !strings.HasPrefix(src[i:], "#REF!") {
				return nil, false
			}
			toks = append(toks, token{k: tErrRef, text: "#REF!", start: start, end: i + 5})
			i += 5

		case c == '$' || isLetter(c) || c == '_':
			if e := matchRef(src, i); e >= 0 {
				r1 := parseRef(src[i:e])
				if e < n && src[e] == ':' {
					if e2 := matchRef(src, e+1); e2 >= 0 {
						r2 := parseRef(src[e+1 : e2])
						toks = append(toks, token{k: tRange, text: src[i:e2], start: start, end: e2, ref: r1, ref2: r2})
						i = e2
						continue
					}
				}
				toks = append(toks, token{k: tRef, text: src[i:e], start: start, end: e, ref: r1})
				i = e
				continue
			}
			if c == '$' {
				return nil, false
			}
			j := i + 1
			for j < n && isIdentChar(src[j]) {
				j++
			}
			toks = append(toks, token{k: tIdent, text: src[i:j], start: start, end: j})
			i = j

		default:
			two := ""
			if i+1 < n {
				two = src[i : i+2]
			}
			switch {
			case two == "<>" || two == "<=" || two == ">=":
				toks = append(toks, token{k: tOp, text: two, start: start, end: i + 2, op: two})
				i += 2
			case strings.IndexByte("+-*/^&=<>", c) >= 0:
				toks = append(toks, token{k: tOp, text: string(c), start: start, end: i + 1, op: string(c)})
				i++
			case c == '(':
				toks = append(toks, token{k: tLP, text: "(", start: start, end: i + 1})
				i++
			case c == ')':
				toks = append(toks, token{k: tRP, text: ")", start: start, end: i + 1})
				i++
			case c == ',':
				toks = append(toks, token{k: tComma, text: ",", start: start, end: i + 1})
				i++
			default:
				return nil, false
			}
		}
	}
	return toks, true
}

// ---------------------------------------------------------------------------
// Formula AST and parser
// ---------------------------------------------------------------------------

type Node interface{}

type numLit struct {
	v   float64
	inf bool
}
type strLit struct{ s string }
type boolLit struct{ b bool }
type errLit struct{ code string }
type refNode struct {
	p     Pos
	valid bool
}
type rangeNode struct {
	rc    Rect
	valid bool
}
type identNode struct{ name string }
type callNode struct {
	name string
	args []Node
}
type unaryNode struct {
	op string
	x  Node
}
type binNode struct {
	op   string
	l, r Node
}
type parenNode struct{ x Node }

type parseErr struct{}

type parser struct {
	toks []token
	pos  int
}

func (p *parser) peek() token { return p.toks[p.pos] }

func (p *parser) isOp(ops ...string) (string, bool) {
	t := p.toks[p.pos]
	if t.k != tOp {
		return "", false
	}
	for _, o := range ops {
		if t.op == o {
			return o, true
		}
	}
	return "", false
}

func (p *parser) fail() { panic(parseErr{}) }

func (p *parser) parseCmp() Node {
	l := p.parseConcat()
	for {
		op, ok := p.isOp("=", "<>", "<", "<=", ">", ">=")
		if !ok {
			return l
		}
		p.pos++
		r := p.parseConcat()
		l = &binNode{op: op, l: l, r: r}
	}
}

func (p *parser) parseConcat() Node {
	l := p.parseAdd()
	for {
		if _, ok := p.isOp("&"); !ok {
			return l
		}
		p.pos++
		r := p.parseAdd()
		l = &binNode{op: "&", l: l, r: r}
	}
}

func (p *parser) parseAdd() Node {
	l := p.parseMul()
	for {
		op, ok := p.isOp("+", "-")
		if !ok {
			return l
		}
		p.pos++
		r := p.parseMul()
		l = &binNode{op: op, l: l, r: r}
	}
}

func (p *parser) parseMul() Node {
	l := p.parseUnary()
	for {
		op, ok := p.isOp("*", "/")
		if !ok {
			return l
		}
		p.pos++
		r := p.parseUnary()
		l = &binNode{op: op, l: l, r: r}
	}
}

func (p *parser) parseUnary() Node {
	if op, ok := p.isOp("+", "-"); ok {
		p.pos++
		return &unaryNode{op: op, x: p.parseUnary()}
	}
	return p.parsePower()
}

func (p *parser) parsePower() Node {
	base := p.parsePrimary()
	if _, ok := p.isOp("^"); ok {
		p.pos++
		ex := p.parsePowRHS()
		return &binNode{op: "^", l: base, r: ex}
	}
	return base
}

func (p *parser) parsePowRHS() Node {
	if op, ok := p.isOp("+", "-"); ok {
		p.pos++
		return &unaryNode{op: op, x: p.parsePowRHS()}
	}
	return p.parsePower()
}

func (p *parser) parseArgs() []Node {
	var args []Node
	if p.peek().k == tRP {
		p.pos++
		return args
	}
	for {
		args = append(args, p.parseCmp())
		switch p.peek().k {
		case tComma:
			p.pos++
		case tRP:
			p.pos++
			return args
		default:
			p.fail()
		}
	}
}

func (p *parser) parsePrimary() Node {
	t := p.peek()
	switch t.k {
	case tNum:
		p.pos++
		return &numLit{v: t.num, inf: math.IsInf(t.num, 0)}
	case tStr:
		p.pos++
		return &strLit{s: t.str}
	case tErrRef:
		p.pos++
		return &errLit{code: "#REF!"}
	case tRef:
		p.pos++
		return &refNode{p: Pos{t.ref.col, t.ref.row}, valid: t.ref.valid}
	case tRange:
		p.pos++
		return &rangeNode{rc: normRect(Pos{t.ref.col, t.ref.row}, Pos{t.ref2.col, t.ref2.row}),
			valid: t.ref.valid && t.ref2.valid}
	case tIdent:
		p.pos++
		if p.peek().k == tLP {
			p.pos++
			return &callNode{name: t.text, args: p.parseArgs()}
		}
		switch strings.ToUpper(t.text) {
		case "TRUE":
			return &boolLit{b: true}
		case "FALSE":
			return &boolLit{b: false}
		}
		return &identNode{name: t.text}
	case tLP:
		p.pos++
		e := p.parseCmp()
		if p.peek().k != tRP {
			p.fail()
		}
		p.pos++
		return &parenNode{x: e}
	}
	p.fail()
	return nil
}

func collectPrec(n Node, out *[]Rect) {
	switch x := n.(type) {
	case *refNode:
		if x.valid {
			*out = append(*out, Rect{x.p.c, x.p.r, x.p.c, x.p.r})
		}
	case *rangeNode:
		if x.valid {
			*out = append(*out, x.rc)
		}
	case *unaryNode:
		collectPrec(x.x, out)
	case *binNode:
		collectPrec(x.l, out)
		collectPrec(x.r, out)
	case *parenNode:
		collectPrec(x.x, out)
	case *callNode:
		up := strings.ToUpper(x.name)
		if up == "ROW" || up == "COLUMN" {
			return
		}
		for _, a := range x.args {
			collectPrec(a, out)
		}
	}
}

// parseFormula parses the source after '='.
func parseFormula(src string) (ast Node, prec []Rect, ok bool) {
	toks, lok := lex(src)
	if !lok {
		return nil, nil, false
	}
	toks = append(toks, token{k: tEOF})
	defer func() {
		if r := recover(); r != nil {
			if _, is := r.(parseErr); is {
				ast, prec, ok = nil, nil, false
				return
			}
			panic(r)
		}
	}()
	p := &parser{toks: toks}
	ast = p.parseCmp()
	if p.peek().k != tEOF {
		p.fail()
	}
	collectPrec(ast, &prec)
	return ast, prec, true
}

// ---------------------------------------------------------------------------
// Sheet
// ---------------------------------------------------------------------------

type Cell struct {
	raw     string
	formula bool
	perr    bool
	ast     Node
	prec    []Rect
	val     Value
}

type Sheet struct {
	cells map[Pos]*Cell
	evals int
}

func newSheet() *Sheet { return &Sheet{cells: map[Pos]*Cell{}} }

func (s *Sheet) cellValue(p Pos) Value {
	c := s.cells[p]
	if c == nil {
		return Value{}
	}
	return c.val
}

func (s *Sheet) formulaPositions() []Pos {
	var out []Pos
	for p, c := range s.cells {
		if c.formula {
			out = append(out, p)
		}
	}
	sortPos(out)
	return out
}

// assign stores raw cell input (VALUE of set) at p. It does not recalculate.
func (s *Sheet) assign(p Pos, raw string) {
	v := trimWS(raw)
	if v == "" {
		delete(s.cells, p)
		return
	}
	c := &Cell{raw: v}
	switch {
	case v[0] == '=':
		c.formula = true
		ast, prec, ok := parseFormula(v[1:])
		if ok {
			c.ast = ast
			c.prec = prec
		} else {
			c.perr = true
		}
	case v[0] == '\'':
		c.val = vText(v[1:])
	default:
		if f, ok := parseNumLit(v); ok {
			c.val = vNum(f)
		} else if strings.EqualFold(v, "TRUE") {
			c.val = vBool(true)
		} else if strings.EqualFold(v, "FALSE") {
			c.val = vBool(false)
		} else {
			c.val = vText(v)
		}
	}
	s.cells[p] = c
}

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

func (s *Sheet) evalCell(c *Cell) Value {
	if c.perr {
		return vErr("#PARSE!")
	}
	v := s.eval(c.ast)
	if v.K == KEmpty {
		return vNum(0)
	}
	return v
}

func (s *Sheet) eval(n Node) Value {
	switch x := n.(type) {
	case *numLit:
		if x.inf {
			return vErr("#NUM!")
		}
		return vNum(x.v)
	case *strLit:
		return vText(x.s)
	case *boolLit:
		return vBool(x.b)
	case *errLit:
		return vErr(x.code)
	case *refNode:
		if !x.valid {
			return vErr("#REF!")
		}
		return s.cellValue(x.p)
	case *rangeNode:
		return vErr("#VALUE!")
	case *identNode:
		return vErr("#NAME?")
	case *parenNode:
		return s.eval(x.x)
	case *unaryNode:
		v := s.eval(x.x)
		f, e := toNum(v)
		if e != "" {
			return vErr(e)
		}
		if x.op == "-" {
			f = -f
		}
		return vNum(f)
	case *binNode:
		return s.evalBin(x)
	case *callNode:
		return s.call(x)
	}
	return vErr("#VALUE!")
}

func (s *Sheet) evalBin(x *binNode) Value {
	l := s.eval(x.l)
	r := s.eval(x.r)
	switch x.op {
	case "=", "<>", "<", "<=", ">", ">=":
		if l.K == KErr {
			return l
		}
		if r.K == KErr {
			return r
		}
		return vBool(opHolds(x.op, compareVals(l, r)))
	case "&":
		ls, e := toStr(l)
		if e != "" {
			return vErr(e)
		}
		rs, e := toStr(r)
		if e != "" {
			return vErr(e)
		}
		return vText(ls + rs)
	}
	a, e := toNum(l)
	if e != "" {
		return vErr(e)
	}
	b, e := toNum(r)
	if e != "" {
		return vErr(e)
	}
	switch x.op {
	case "+":
		return numRes(a + b)
	case "-":
		return numRes(a - b)
	case "*":
		return numRes(a * b)
	case "/":
		if b == 0 {
			return vErr("#DIV/0!")
		}
		return numRes(a / b)
	case "^":
		return numRes(math.Pow(a, b))
	}
	return vErr("#VALUE!")
}

// item is one argument item of an aggregate function.
type item struct {
	v   Value
	rng bool
}

func (s *Sheet) items(args []Node) []item {
	var out []item
	for _, a := range args {
		if r, ok := a.(*rangeNode); ok {
			if !r.valid {
				out = append(out, item{v: vErr("#REF!"), rng: true})
				continue
			}
			rc := r.rc
			for row := rc.r1; row <= rc.r2; row++ {
				for col := rc.c1; col <= rc.c2; col++ {
					out = append(out, item{v: s.cellValue(Pos{col, row}), rng: true})
				}
			}
			continue
		}
		out = append(out, item{v: s.eval(a)})
	}
	return out
}

// collectNums returns the numeric items in order, or the first error code.
func collectNums(items []item) ([]float64, string) {
	var nums []float64
	for _, it := range items {
		if it.v.K == KErr {
			return nil, it.v.S
		}
		if it.rng {
			if it.v.K == KNum {
				nums = append(nums, it.v.N)
			}
			continue
		}
		f, e := toNum(it.v)
		if e != "" {
			return nil, e
		}
		nums = append(nums, f)
	}
	return nums, ""
}

func aggNums(name string, nums []float64) Value {
	switch name {
	case "SUM", "AVERAGE":
		sum := 0.0
		for _, f := range nums {
			sum += f
			if !finite(sum) {
				return vErr("#NUM!")
			}
		}
		if name == "SUM" {
			return vNum(sum)
		}
		if len(nums) == 0 {
			return vErr("#DIV/0!")
		}
		return numRes(sum / float64(len(nums)))
	case "MIN", "MAX":
		if len(nums) == 0 {
			return vNum(0)
		}
		m := nums[0]
		for _, f := range nums[1:] {
			if (name == "MIN" && f < m) || (name == "MAX" && f > m) {
				m = f
			}
		}
		return vNum(m)
	case "PRODUCT":
		if len(nums) == 0 {
			return vNum(0)
		}
		p := 1.0
		for _, f := range nums {
			p *= f
			if !finite(p) {
				return vErr("#NUM!")
			}
		}
		return vNum(p)
	case "MEDIAN":
		if len(nums) == 0 {
			return vErr("#NUM!")
		}
		sorted := append([]float64(nil), nums...)
		sort.Float64s(sorted)
		n := len(sorted)
		if n%2 == 1 {
			return vNum(sorted[n/2])
		}
		return numRes((sorted[n/2-1] + sorted[n/2]) / 2)
	}
	return vErr("#VALUE!")
}

func (s *Sheet) call(x *callNode) Value {
	name := strings.ToUpper(x.name)
	args := x.args
	n := len(args)
	switch name {
	case "SUM", "AVERAGE", "MIN", "MAX", "PRODUCT", "MEDIAN":
		if n == 0 {
			return vErr("#VALUE!")
		}
		nums, e := collectNums(s.items(args))
		if e != "" {
			return vErr(e)
		}
		return aggNums(name, nums)

	case "COUNT", "COUNTA":
		if n == 0 {
			return vErr("#VALUE!")
		}
		cnt := 0
		for _, it := range s.items(args) {
			if name == "COUNT" && it.v.K == KNum {
				cnt++
			} else if name == "COUNTA" && it.v.K != KEmpty {
				cnt++
			}
		}
		return vNum(float64(cnt))

	case "CONCAT":
		if n == 0 {
			return vErr("#VALUE!")
		}
		var sb strings.Builder
		for _, it := range s.items(args) {
			str, e := toStr(it.v)
			if e != "" {
				return vErr(e)
			}
			sb.WriteString(str)
		}
		return vText(sb.String())

	case "AND", "OR":
		if n == 0 {
			return vErr("#VALUE!")
		}
		taken := false
		result := name == "AND"
		for _, it := range s.items(args) {
			if it.v.K == KErr {
				return it.v
			}
			if it.rng && (it.v.K == KText || it.v.K == KEmpty) {
				continue
			}
			b, e := toBool(it.v)
			if e != "" {
				return vErr(e)
			}
			taken = true
			if name == "AND" {
				result = result && b
			} else {
				result = result || b
			}
		}
		if !taken {
			return vErr("#VALUE!")
		}
		return vBool(result)

	case "IF":
		if n != 2 && n != 3 {
			return vErr("#VALUE!")
		}
		c, e := toBool(s.eval(args[0]))
		if e != "" {
			return vErr(e)
		}
		if c {
			return s.eval(args[1])
		}
		if n == 3 {
			return s.eval(args[2])
		}
		return vBool(false)

	case "IFERROR":
		if n != 2 {
			return vErr("#VALUE!")
		}
		a := s.eval(args[0])
		if a.K == KErr {
			return s.eval(args[1])
		}
		return a

	case "CHOOSE":
		if n < 2 {
			return vErr("#VALUE!")
		}
		f, e := toNum(s.eval(args[0]))
		if e != "" {
			return vErr(e)
		}
		f = math.Floor(f)
		if f < 1 || f > float64(n-1) {
			return vErr("#VALUE!")
		}
		return s.eval(args[int(f)])

	case "NOT":
		if n != 1 {
			return vErr("#VALUE!")
		}
		b, e := toBool(s.eval(args[0]))
		if e != "" {
			return vErr(e)
		}
		return vBool(!b)

	case "ABS", "INT", "SQRT":
		if n != 1 {
			return vErr("#VALUE!")
		}
		f, e := toNum(s.eval(args[0]))
		if e != "" {
			return vErr(e)
		}
		switch name {
		case "ABS":
			return numRes(math.Abs(f))
		case "INT":
			return numRes(math.Floor(f))
		}
		if f < 0 {
			return vErr("#NUM!")
		}
		return numRes(math.Sqrt(f))

	case "POW", "MOD":
		if n != 2 {
			return vErr("#VALUE!")
		}
		a, e := toNum(s.eval(args[0]))
		if e != "" {
			return vErr(e)
		}
		b, e := toNum(s.eval(args[1]))
		if e != "" {
			return vErr(e)
		}
		if name == "POW" {
			return numRes(math.Pow(a, b))
		}
		if b == 0 {
			return vErr("#DIV/0!")
		}
		return numRes(a - b*math.Floor(a/b))

	case "ROUND":
		if n != 1 && n != 2 {
			return vErr("#VALUE!")
		}
		x, e := toNum(s.eval(args[0]))
		if e != "" {
			return vErr(e)
		}
		d := 0.0
		if n == 2 {
			d, e = toNum(s.eval(args[1]))
			if e != "" {
				return vErr(e)
			}
			d = math.Trunc(d)
		}
		if math.Abs(d) > 15 {
			return vErr("#NUM!")
		}
		p := math.Pow10(int(d))
		return numRes(math.Round(x*p) / p)

	case "LEN", "UPPER", "LOWER", "TRIM":
		if n != 1 {
			return vErr("#VALUE!")
		}
		str, e := toStr(s.eval(args[0]))
		if e != "" {
			return vErr(e)
		}
		switch name {
		case "LEN":
			return vNum(float64(utf8.RuneCountInString(str)))
		case "UPPER":
			return vText(asciiCase(str, true))
		case "LOWER":
			return vText(asciiCase(str, false))
		}
		return vText(strings.Join(strings.FieldsFunc(str, isWSRune), " "))

	case "LEFT", "RIGHT":
		if n != 1 && n != 2 {
			return vErr("#VALUE!")
		}
		str, e := toStr(s.eval(args[0]))
		if e != "" {
			return vErr(e)
		}
		cnt := 1.0
		if n == 2 {
			cnt, e = toNum(s.eval(args[1]))
			if e != "" {
				return vErr(e)
			}
		}
		cnt = math.Floor(cnt)
		if cnt < 0 {
			return vErr("#VALUE!")
		}
		runes := []rune(str)
		if cnt > float64(len(runes)) {
			cnt = float64(len(runes))
		}
		k := int(cnt)
		if name == "LEFT" {
			return vText(string(runes[:k]))
		}
		return vText(string(runes[len(runes)-k:]))

	case "MID":
		if n != 3 {
			return vErr("#VALUE!")
		}
		str, e := toStr(s.eval(args[0]))
		if e != "" {
			return vErr(e)
		}
		st, e := toNum(s.eval(args[1]))
		if e != "" {
			return vErr(e)
		}
		ln, e := toNum(s.eval(args[2]))
		if e != "" {
			return vErr(e)
		}
		st = math.Floor(st)
		ln = math.Floor(ln)
		if st < 1 || ln < 0 {
			return vErr("#VALUE!")
		}
		runes := []rune(str)
		if st-1 >= float64(len(runes)) {
			return vText("")
		}
		from := int(st) - 1
		to := from + int(math.Min(ln, float64(len(runes))))
		if to > len(runes) {
			to = len(runes)
		}
		return vText(string(runes[from:to]))

	case "SUBSTITUTE":
		if n != 3 {
			return vErr("#VALUE!")
		}
		var strs [3]string
		for i := 0; i < 3; i++ {
			str, e := toStr(s.eval(args[i]))
			if e != "" {
				return vErr(e)
			}
			strs[i] = str
		}
		if strs[1] == "" {
			return vText(strs[0])
		}
		return vText(strings.ReplaceAll(strs[0], strs[1], strs[2]))

	case "VALUE":
		if n != 1 {
			return vErr("#VALUE!")
		}
		f, e := toNum(s.eval(args[0]))
		if e != "" {
			return vErr(e)
		}
		return vNum(f)

	case "ISERROR", "ISBLANK", "ISNUMBER", "ISTEXT":
		if n != 1 {
			return vErr("#VALUE!")
		}
		v := s.eval(args[0])
		switch name {
		case "ISERROR":
			return vBool(v.K == KErr)
		case "ISBLANK":
			return vBool(v.K == KEmpty)
		case "ISNUMBER":
			return vBool(v.K == KNum)
		}
		return vBool(v.K == KText)

	case "ROW", "COLUMN":
		if n != 1 {
			return vErr("#VALUE!")
		}
		switch a := args[0].(type) {
		case *refNode:
			if !a.valid {
				return vErr("#REF!")
			}
			if name == "ROW" {
				return vNum(float64(a.p.r))
			}
			return vNum(float64(a.p.c + 1))
		case *rangeNode:
			if !a.valid {
				return vErr("#REF!")
			}
			if name == "ROW" {
				return vNum(float64(a.rc.r1))
			}
			return vNum(float64(a.rc.c1 + 1))
		}
		return vErr("#VALUE!")

	case "INDEX":
		if n != 2 && n != 3 {
			return vErr("#VALUE!")
		}
		rn, ok := args[0].(*rangeNode)
		if !ok {
			return vErr("#VALUE!")
		}
		if !rn.valid {
			return vErr("#REF!")
		}
		rc := rn.rc
		rows := rc.r2 - rc.r1 + 1
		cols := rc.c2 - rc.c1 + 1
		rf, e := toNum(s.eval(args[1]))
		if e != "" {
			return vErr(e)
		}
		var rowF, colF float64
		if n == 2 {
			if rows == 1 {
				rowF, colF = 1, rf
			} else {
				rowF, colF = rf, 1
			}
		} else {
			cf, e2 := toNum(s.eval(args[2]))
			if e2 != "" {
				return vErr(e2)
			}
			rowF, colF = rf, cf
		}
		rowF = math.Floor(rowF)
		colF = math.Floor(colF)
		if rowF < 1 || colF < 1 || rowF > float64(rows) || colF > float64(cols) {
			return vErr("#REF!")
		}
		return s.cellValue(Pos{rc.c1 + int(colF) - 1, rc.r1 + int(rowF) - 1})

	case "COUNTIF":
		if n != 2 {
			return vErr("#VALUE!")
		}
		rn, ok := args[0].(*rangeNode)
		if !ok {
			return vErr("#VALUE!")
		}
		if !rn.valid {
			return vErr("#REF!")
		}
		crit := s.eval(args[1])
		if crit.K == KErr {
			return crit
		}
		op := "="
		operand := crit
		if crit.K == KText {
			body := crit.S
			for _, o := range []string{">=", "<=", "<>", ">", "<", "="} {
				if strings.HasPrefix(body, o) {
					op = o
					body = body[len(o):]
					break
				}
			}
			if f, ok2 := parseNumLit(body); ok2 {
				operand = vNum(f)
			} else {
				operand = vText(body)
			}
		}
		rc := rn.rc
		cnt := 0
		for row := rc.r1; row <= rc.r2; row++ {
			for col := rc.c1; col <= rc.c2; col++ {
				v := s.cellValue(Pos{col, row})
				if v.K == operand.K {
					if opHolds(op, compareVals(v, operand)) {
						cnt++
					}
				} else if op == "<>" && v.K != KEmpty {
					cnt++
				}
			}
		}
		return vNum(float64(cnt))
	}
	return vErr("#NAME?")
}

func isWSRune(r rune) bool {
	return r == ' ' || r == '\t' || r == '\r' || r == '\n' || r == '\v' || r == '\f'
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

// ---------------------------------------------------------------------------
// Recalculation
// ---------------------------------------------------------------------------

// recalc updates everything affected by the changed cells and returns N.
func (s *Sheet) recalc(changed []Pos) int {
	inS := map[Pos]bool{}
	queued := map[Pos]bool{}
	var queue []Pos
	push := func(p Pos) {
		if !queued[p] {
			queued[p] = true
			queue = append(queue, p)
		}
	}
	for _, p := range changed {
		push(p)
		if c := s.cells[p]; c != nil && c.formula {
			inS[p] = true
		}
	}
	deps := s.buildDeps()
	for i := 0; i < len(queue); i++ {
		deps.each(queue[i], func(f Pos) {
			if !inS[f] {
				inS[f] = true
				push(f)
			}
		})
	}

	var nodes []Pos
	for p := range inS {
		nodes = append(nodes, p)
	}
	sortPos(nodes)
	n := len(nodes)
	if n == 0 {
		return 0
	}

	idx := make(map[Pos]int, n)
	for i, p := range nodes {
		idx[p] = i
	}
	adj := make([][]int, n)
	for i := range nodes {
		c := s.cells[nodes[i]]
		for _, r := range c.prec {
			area := (r.c2 - r.c1 + 1) * (r.r2 - r.r1 + 1)
			if area <= n {
				for row := r.r1; row <= r.r2; row++ {
					for col := r.c1; col <= r.c2; col++ {
						if j, ok := idx[Pos{col, row}]; ok {
							adj[i] = append(adj[i], j)
						}
					}
				}
			} else {
				for j, q := range nodes {
					if r.contains(q) {
						adj[i] = append(adj[i], j)
					}
				}
			}
		}
	}

	// Tarjan's SCC; components come out precedents-first.
	index := make([]int, n)
	for i := range index {
		index[i] = -1
	}
	low := make([]int, n)
	onStack := make([]bool, n)
	var stack []int
	counter := 0
	var sccs [][]int
	var strong func(v int)
	strong = func(v int) {
		index[v] = counter
		low[v] = counter
		counter++
		stack = append(stack, v)
		onStack[v] = true
		for _, w := range adj[v] {
			if index[w] < 0 {
				strong(w)
				if low[w] < low[v] {
					low[v] = low[w]
				}
			} else if onStack[w] && index[w] < low[v] {
				low[v] = index[w]
			}
		}
		if low[v] == index[v] {
			var comp []int
			for {
				w := stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				onStack[w] = false
				comp = append(comp, w)
				if w == v {
					break
				}
			}
			sccs = append(sccs, comp)
		}
	}
	for v := 0; v < n; v++ {
		if index[v] < 0 {
			strong(v)
		}
	}

	for _, comp := range sccs {
		cyclic := len(comp) > 1
		if !cyclic {
			for _, w := range adj[comp[0]] {
				if w == comp[0] {
					cyclic = true
				}
			}
		}
		if cyclic {
			for _, v := range comp {
				s.cells[nodes[v]].val = vErr("#CYCLE!")
			}
		} else {
			c := s.cells[nodes[comp[0]]]
			c.val = s.evalCell(c)
		}
	}
	s.evals += n
	return n
}

// bigEdge is a dependency on a large range, kept as a rectangle.
type bigEdge struct {
	r Rect
	f Pos
}

// depIndex maps a cell to the formulas that name it as a precedent.
// Small ranges are expanded per cell; large ones are scanned.
type depIndex struct {
	cell map[Pos][]Pos
	big  []bigEdge
}

const expandLimit = 256

func (s *Sheet) buildDeps() *depIndex {
	d := &depIndex{cell: map[Pos][]Pos{}}
	for _, f := range s.formulaPositions() {
		for _, r := range s.cells[f].prec {
			if (r.c2-r.c1+1)*(r.r2-r.r1+1) <= expandLimit {
				for row := r.r1; row <= r.r2; row++ {
					for col := r.c1; col <= r.c2; col++ {
						q := Pos{col, row}
						d.cell[q] = append(d.cell[q], f)
					}
				}
			} else {
				d.big = append(d.big, bigEdge{r, f})
			}
		}
	}
	return d
}

func (d *depIndex) each(p Pos, fn func(Pos)) {
	for _, f := range d.cell[p] {
		fn(f)
	}
	for _, e := range d.big {
		if e.r.contains(p) {
			fn(e.f)
		}
	}
}

// dependentsOf returns all transitive formula dependents of p.
func (s *Sheet) dependentsOf(p Pos) []Pos {
	found := map[Pos]bool{}
	queue := []Pos{p}
	deps := s.buildDeps()
	for i := 0; i < len(queue); i++ {
		deps.each(queue[i], func(f Pos) {
			if !found[f] {
				found[f] = true
				queue = append(queue, f)
			}
		})
	}
	var out []Pos
	for f := range found {
		out = append(out, f)
	}
	sortPos(out)
	return out
}

// ---------------------------------------------------------------------------
// Reference shifting (copy)
// ---------------------------------------------------------------------------

func shiftRef(r refText, dc, dr int) (string, bool) {
	col := r.col
	if !r.cAbs {
		col += dc
	}
	row := r.row
	if !r.rAbs {
		row += dr
	}
	if col < 0 || col > 25 || row < 1 || row > 999 {
		return "", false
	}
	var sb strings.Builder
	if r.cAbs {
		sb.WriteByte('$')
	}
	sb.WriteByte(byte('A' + col))
	if r.rAbs {
		sb.WriteByte('$')
	}
	sb.WriteString(strconv.Itoa(row))
	return sb.String(), true
}

func shiftFormula(src string, dc, dr int) string {
	toks, ok := lex(src)
	if !ok {
		return src
	}
	var sb strings.Builder
	prev := 0
	for _, t := range toks {
		if t.k != tRef && t.k != tRange {
			continue
		}
		sb.WriteString(src[prev:t.start])
		switch t.k {
		case tRef:
			if !t.ref.valid {
				sb.WriteString(t.text)
			} else if s, ok := shiftRef(t.ref, dc, dr); ok {
				sb.WriteString(s)
			} else {
				sb.WriteString("#REF!")
			}
		case tRange:
			if !t.ref.valid || !t.ref2.valid {
				sb.WriteString(t.text)
			} else {
				a, okA := shiftRef(t.ref, dc, dr)
				b, okB := shiftRef(t.ref2, dc, dr)
				if okA && okB {
					sb.WriteString(a + ":" + b)
				} else {
					sb.WriteString("#REF!")
				}
			}
		}
		prev = t.end
	}
	sb.WriteString(src[prev:])
	return sb.String()
}

// ---------------------------------------------------------------------------
// CSV (import) and export helpers
// ---------------------------------------------------------------------------

func parseCSV(text string) [][]string {
	var recs [][]string
	var fields []string
	var field strings.Builder
	inQ := false
	content := false
	endRecord := func() {
		fields = append(fields, field.String())
		field.Reset()
		if content {
			recs = append(recs, fields)
		}
		fields = nil
		content = false
	}
	for i := 0; i < len(text); i++ {
		c := text[i]
		if inQ {
			content = true
			if c == '"' {
				if i+1 < len(text) && text[i+1] == '"' {
					field.WriteByte('"')
					i++
				} else {
					inQ = false
				}
			} else {
				field.WriteByte(c)
			}
			continue
		}
		switch c {
		case '"':
			inQ = true
			content = true
		case ',':
			fields = append(fields, field.String())
			field.Reset()
			content = true
		case '\n':
			endRecord()
		case '\r':
		default:
			field.WriteByte(c)
			content = true
		}
	}
	endRecord()
	return recs
}

func csvField(s string) string {
	if strings.ContainsAny(s, ",\"\n\r") || strings.HasPrefix(s, " ") || strings.HasSuffix(s, " ") {
		return "\"" + strings.ReplaceAll(s, "\"", "\"\"") + "\""
	}
	return s
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

func errLine(w *bufio.Writer, msg string) {
	fmt.Fprintf(w, "error: %s\n", msg)
}

func splitWord(s string) (string, string) {
	i := strings.IndexAny(s, " \t\r\n\v\f")
	if i < 0 {
		return s, ""
	}
	return s[:i], trimLeftWS(s[i:])
}

func splitTokens(s string) []string {
	return strings.FieldsFunc(s, isWSRune)
}

func (s *Sheet) printRecalc(w *bufio.Writer, changed []Pos) {
	fmt.Fprintf(w, "recalc %d\n", s.recalc(changed))
}

func (s *Sheet) cmdSet(w *bufio.Writer, rest string) {
	if rest == "" {
		errLine(w, "usage: set CELL VALUE")
		return
	}
	cellTok, after := splitWord(rest)
	p, ok := parseCellTok(cellTok)
	if !ok {
		errLine(w, fmt.Sprintf("bad cell reference '%s'", cellTok))
		return
	}
	s.assign(p, after)
	s.printRecalc(w, []Pos{p})
}

func (s *Sheet) cmdOneCell(w *bufio.Writer, rest, usage string) (Pos, bool) {
	toks := splitTokens(rest)
	if len(toks) != 1 {
		errLine(w, usage)
		return Pos{}, false
	}
	p, ok := parseCellTok(toks[0])
	if !ok {
		errLine(w, fmt.Sprintf("bad cell reference '%s'", toks[0]))
		return Pos{}, false
	}
	return p, true
}

func (s *Sheet) cmdClear(w *bufio.Writer, rest string) {
	p, ok := s.cmdOneCell(w, rest, "usage: clear CELL")
	if !ok {
		return
	}
	s.assign(p, "")
	s.printRecalc(w, []Pos{p})
}

func (s *Sheet) cmdGet(w *bufio.Writer, rest string) {
	p, ok := s.cmdOneCell(w, rest, "usage: get CELL")
	if !ok {
		return
	}
	c := s.cells[p]
	if c == nil {
		fmt.Fprintln(w, "(empty)")
		return
	}
	fmt.Fprintln(w, display(c.val))
}

func (s *Sheet) cmdShow(w *bufio.Writer, rest string) {
	p, ok := s.cmdOneCell(w, rest, "usage: show CELL")
	if !ok {
		return
	}
	c := s.cells[p]
	switch {
	case c == nil:
		fmt.Fprintf(w, "%s: (empty)\n", p.name())
	case !c.formula:
		fmt.Fprintf(w, "%s: %s\n", p.name(), c.raw)
	default:
		fmt.Fprintf(w, "%s: %s => %s\n", p.name(), c.raw, display(c.val))
	}
}

func (s *Sheet) cmdDeps(w *bufio.Writer, rest string, dependents bool) {
	usage := "usage: precedents CELL"
	if dependents {
		usage = "usage: dependents CELL"
	}
	p, ok := s.cmdOneCell(w, rest, usage)
	if !ok {
		return
	}
	var list []Pos
	if dependents {
		list = s.dependentsOf(p)
	} else {
		c := s.cells[p]
		if c != nil && c.formula {
			seen := map[Pos]bool{}
			for _, r := range c.prec {
				for row := r.r1; row <= r.r2; row++ {
					for col := r.c1; col <= r.c2; col++ {
						q := Pos{col, row}
						if !seen[q] {
							seen[q] = true
							list = append(list, q)
						}
					}
				}
			}
			sortPos(list)
		}
	}
	if len(list) == 0 {
		fmt.Fprintln(w, "(none)")
		return
	}
	names := make([]string, len(list))
	for i, q := range list {
		names[i] = q.name()
	}
	fmt.Fprintln(w, strings.Join(names, " "))
}

func (s *Sheet) cmdStats(w *bufio.Writer) {
	formulas := 0
	for _, c := range s.cells {
		if c.formula {
			formulas++
		}
	}
	fmt.Fprintf(w, "cells %d formulas %d evals %d\n", len(s.cells), formulas, s.evals)
}

func (s *Sheet) cmdCopy(w *bufio.Writer, rest string) {
	toks := splitTokens(rest)
	if len(toks) != 2 {
		errLine(w, "usage: copy SRC DST")
		return
	}
	src, ok := parseCellTok(toks[0])
	if !ok {
		errLine(w, fmt.Sprintf("bad cell reference '%s'", toks[0]))
		return
	}
	dst, ok := parseRangeTok(toks[1])
	if !ok {
		errLine(w, fmt.Sprintf("bad range '%s'", toks[1]))
		return
	}
	srcCell := s.cells[src]
	var srcRaw string
	if srcCell != nil {
		srcRaw = srcCell.raw
	}
	var changed []Pos
	for row := dst.r1; row <= dst.r2; row++ {
		for col := dst.c1; col <= dst.c2; col++ {
			p := Pos{col, row}
			changed = append(changed, p)
			switch {
			case srcCell == nil:
				s.assign(p, "")
			case !srcCell.formula:
				s.assign(p, srcRaw)
			default:
				s.assign(p, "="+shiftFormula(srcRaw[1:], col-src.c, row-src.r))
			}
		}
	}
	s.printRecalc(w, changed)
}

func (s *Sheet) cmdImport(w *bufio.Writer, rest string, block []string) {
	toks := splitTokens(rest)
	if len(toks) != 1 {
		errLine(w, "usage: import CELL")
		return
	}
	p, ok := parseCellTok(toks[0])
	if !ok {
		errLine(w, fmt.Sprintf("bad cell reference '%s'", toks[0]))
		return
	}
	recs := parseCSV(strings.Join(block, "\n"))
	R := len(recs)
	C := 0
	for _, r := range recs {
		if len(r) > C {
			C = len(r)
		}
	}
	if R > 0 && (p.r+R-1 > 999 || p.c+C-1 > 25) {
		errLine(w, "import out of range")
		return
	}
	var changed []Pos
	for i, rec := range recs {
		for j, f := range rec {
			q := Pos{p.c + j, p.r + i}
			s.assign(q, f)
			changed = append(changed, q)
		}
	}
	n := s.recalc(changed)
	fmt.Fprintf(w, "imported %d rows, %d columns; recalc %d\n", R, C, n)
}

// parseOutArgs parses the arguments of print/export.
func parseOutArgs(toks []string, isExport bool) (formulas bool, rc Rect, hasRange bool, errMsg string) {
	usage := "usage: print [RANGE]"
	if isExport {
		usage = "usage: export [formulas] [RANGE]"
	}
	modes := 0
	var rest []string
	for _, t := range toks {
		switch {
		case t == "formulas" && isExport:
			formulas = true
			modes++
		case t == "formulas":
			return false, rc, false, usage
		case t == "values":
			modes++
		default:
			rest = append(rest, t)
		}
	}
	if modes > 1 || len(rest) > 1 {
		return false, rc, false, usage
	}
	if len(rest) == 1 {
		r, ok := parseRangeTok(rest[0])
		if !ok {
			return false, rc, false, fmt.Sprintf("bad range '%s'", rest[0])
		}
		return formulas, r, true, ""
	}
	return formulas, rc, false, ""
}

func (s *Sheet) cmdPrintExport(w *bufio.Writer, rest string, isExport bool) {
	formulas, rc, has, em := parseOutArgs(splitTokens(rest), isExport)
	if em != "" {
		errLine(w, em)
		return
	}
	if !has {
		if len(s.cells) == 0 {
			fmt.Fprintln(w, "(empty sheet)")
			return
		}
		maxC, maxR := 0, 1
		for p := range s.cells {
			if p.c > maxC {
				maxC = p.c
			}
			if p.r > maxR {
				maxR = p.r
			}
		}
		rc = Rect{0, 1, maxC, maxR}
	}
	for row := rc.r1; row <= rc.r2; row++ {
		fields := make([]string, 0, rc.c2-rc.c1+1)
		for col := rc.c1; col <= rc.c2; col++ {
			p := Pos{col, row}
			c := s.cells[p]
			var f string
			switch {
			case isExport && formulas:
				if c != nil {
					f = c.raw
				}
			default:
				f = display(s.cellValue(p))
			}
			if isExport {
				f = csvField(f)
			}
			fields = append(fields, f)
		}
		if isExport {
			fmt.Fprintln(w, strings.Join(fields, ","))
		} else {
			fmt.Fprintln(w, strings.Join(fields, " | "))
		}
	}
}

func main() {
	data, _ := io.ReadAll(os.Stdin)
	lines := strings.Split(string(data), "\n")
	if len(lines) > 0 && lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	for i := range lines {
		lines[i] = strings.TrimSuffix(lines[i], "\r")
	}
	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	s := newSheet()

	for i := 0; i < len(lines); {
		t := trimRightWS(lines[i])
		i++
		lt := trimLeftWS(t)
		if lt == "" || lt[0] == '#' {
			continue
		}
		fmt.Fprintln(w, "> "+t)
		word, rest := splitWord(lt)
		switch word {
		case "set":
			s.cmdSet(w, rest)
		case "clear":
			s.cmdClear(w, rest)
		case "get":
			s.cmdGet(w, rest)
		case "show":
			s.cmdShow(w, rest)
		case "print":
			s.cmdPrintExport(w, rest, false)
		case "export":
			s.cmdPrintExport(w, rest, true)
		case "import":
			start := i
			for i < len(lines) && lines[i] != "." {
				i++
			}
			block := lines[start:i]
			if i < len(lines) {
				i++
			}
			s.cmdImport(w, rest, block)
		case "copy":
			s.cmdCopy(w, rest)
		case "precedents":
			s.cmdDeps(w, rest, false)
		case "dependents":
			s.cmdDeps(w, rest, true)
		case "stats":
			s.cmdStats(w)
		default:
			errLine(w, fmt.Sprintf("unknown command '%s'", word))
		}
	}
}

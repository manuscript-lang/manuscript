package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
)

type sqlError struct{ msg string }

func fail(msg string) { panic(sqlError{msg}) }

// ---------- values ----------
const (
	kNull = iota
	kInt
	kText
	kBool
)

type Value struct {
	k int
	i int64
	s string
}

var null = Value{}

func vInt(i int64) Value  { return Value{k: kInt, i: i} }
func vText(s string) Value { return Value{k: kText, s: s} }
func vBool(b bool) Value {
	if b {
		return Value{k: kBool, i: 1}
	}
	return Value{k: kBool}
}

func (v Value) String() string {
	switch v.k {
	case kNull:
		return "NULL"
	case kInt:
		return strconv.FormatInt(v.i, 10)
	case kText:
		return v.s
	}
	if v.i != 0 {
		return "true"
	}
	return "false"
}

func valueKey(v Value) string {
	switch v.k {
	case kNull:
		return "n;"
	case kInt:
		return "i" + strconv.FormatInt(v.i, 10) + ";"
	case kText:
		return "s" + strconv.Itoa(len(v.s)) + ":" + v.s + ";"
	}
	return "b" + strconv.FormatInt(v.i, 10) + ";"
}

// ---------- lexer ----------
const (
	tEOF = iota
	tInt
	tStr
	tIdent
	tKw
	tOp
)

type Token struct {
	k int
	s string
	n int64
}

var keywords = map[string]bool{}

func init() {
	for _, w := range strings.Fields("SELECT FROM WHERE GROUP BY HAVING ORDER LIMIT OFFSET JOIN LEFT INNER ON AS AND OR NOT NULL IS LIKE IN BETWEEN INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY DISTINCT ASC DESC") {
		keywords[w] = true
	}
}

func isAlpha(c byte) bool { return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') }
func isDigit(c byte) bool { return c >= '0' && c <= '9' }

func lex(src string) []Token {
	var toks []Token
	i := 0
	n := len(src)
	for i < n {
		c := src[i]
		switch {
		case c == ' ' || c == '\t' || c == '\r' || c == '\n':
			i++
		case c == '-' && i+1 < n && src[i+1] == '-':
			for i < n && src[i] != '\n' {
				i++
			}
		case isAlpha(c):
			j := i
			for j < n && (isAlpha(src[j]) || isDigit(src[j])) {
				j++
			}
			w := src[i:j]
			if keywords[strings.ToUpper(w)] {
				toks = append(toks, Token{k: tKw, s: strings.ToUpper(w)})
			} else {
				toks = append(toks, Token{k: tIdent, s: w})
			}
			i = j
		case isDigit(c):
			j := i
			for j < n && isDigit(src[j]) {
				j++
			}
			v, err := strconv.ParseInt(src[i:j], 10, 64)
			if err != nil {
				fail("syntax error")
			}
			toks = append(toks, Token{k: tInt, n: v})
			i = j
		case c == '\'':
			var sb strings.Builder
			j := i + 1
			closed := false
			for j < n {
				if src[j] == '\'' {
					if j+1 < n && src[j+1] == '\'' {
						sb.WriteByte('\'')
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
				fail("syntax error")
			}
			toks = append(toks, Token{k: tStr, s: sb.String()})
			i = j
		default:
			two := ""
			if i+1 < n {
				two = src[i : i+2]
			}
			switch two {
			case "<>", "!=", "<=", ">=", "||":
				if two == "!=" {
					two = "<>"
				}
				toks = append(toks, Token{k: tOp, s: two})
				i += 2
				continue
			}
			switch c {
			case '=', '<', '>', '+', '-', '*', '/', '%', '(', ')', ',', '.':
				toks = append(toks, Token{k: tOp, s: string(c)})
				i++
			default:
				fail("syntax error")
			}
		}
	}
	toks = append(toks, Token{k: tEOF})
	return toks
}

// ---------- AST ----------
const (
	eLit = iota
	eCol
	eNeg
	eNot
	eBin
	eIsNull
	eLike
	eIn
	eBetween
	eCall
)

type Expr struct {
	typ      int
	val      Value
	tbl      string
	name     string
	idx      int
	args     []*Expr
	op       string
	neg      bool
	fn       string
	distinct bool
	star     bool
	agg      bool
}

type Item struct {
	star     bool
	tbl      string
	expr     *Expr
	alias    string
	hasAlias bool
}
type TRef struct{ name, alias string }
type Join struct {
	left bool
	ref  TRef
	on   *Expr
}
type OrderItem struct {
	e    *Expr
	desc bool
	out  int // output column index, or -1
}
type Select struct {
	distinct bool
	items    []Item
	from     []TRef
	joins    []Join
	where    *Expr
	groupBy  []*Expr
	having   *Expr
	orderBy  []OrderItem
	limit    int64
	offset   int64
}

type ColDef struct {
	name    string
	typ     string
	pk      bool
	notNull bool
}

type Stmt struct {
	kind    string
	table   string
	cols    []ColDef
	names   []string
	hasCols bool
	rows    [][]*Expr
	sets    []*Expr
	where   *Expr
	sel     *Select
}

// ---------- parser ----------
type Parser struct {
	t []Token
	p int
}

func (p *Parser) peek() Token { return p.t[p.p] }
func (p *Parser) next() Token {
	t := p.t[p.p]
	if t.k != tEOF {
		p.p++
	}
	return t
}
func (p *Parser) isKw(s string) bool {
	t := p.peek()
	return t.k == tKw && t.s == s
}
func (p *Parser) isOp(s string) bool {
	t := p.peek()
	return t.k == tOp && t.s == s
}
func (p *Parser) acceptKw(s string) bool {
	if p.isKw(s) {
		p.p++
		return true
	}
	return false
}
func (p *Parser) acceptOp(s string) bool {
	if p.isOp(s) {
		p.p++
		return true
	}
	return false
}
func (p *Parser) expectKw(s string) {
	if !p.acceptKw(s) {
		fail("syntax error")
	}
}
func (p *Parser) expectOp(s string) {
	if !p.acceptOp(s) {
		fail("syntax error")
	}
}
func (p *Parser) name() string {
	t := p.peek()
	if t.k != tIdent {
		fail("syntax error")
	}
	p.p++
	return t.s
}

func (p *Parser) parseStmt() *Stmt {
	t := p.peek()
	if t.k != tKw {
		fail("syntax error")
	}
	var st *Stmt
	switch t.s {
	case "CREATE":
		p.next()
		p.expectKw("TABLE")
		st = &Stmt{kind: "create", table: p.name()}
		p.expectOp("(")
		for {
			cd := ColDef{name: p.name()}
			ty := p.name()
			switch strings.ToUpper(ty) {
			case "INT":
				cd.typ = "INT"
			case "TEXT":
				cd.typ = "TEXT"
			default:
				fail("syntax error")
			}
			for {
				if p.acceptKw("PRIMARY") {
					p.expectKw("KEY")
					cd.pk = true
				} else if p.acceptKw("NOT") {
					p.expectKw("NULL")
					cd.notNull = true
				} else {
					break
				}
			}
			st.cols = append(st.cols, cd)
			if !p.acceptOp(",") {
				break
			}
		}
		p.expectOp(")")
	case "DROP":
		p.next()
		p.expectKw("TABLE")
		st = &Stmt{kind: "drop", table: p.name()}
	case "INSERT":
		p.next()
		p.expectKw("INTO")
		st = &Stmt{kind: "insert", table: p.name()}
		if p.acceptOp("(") {
			st.hasCols = true
			for {
				st.names = append(st.names, p.name())
				if !p.acceptOp(",") {
					break
				}
			}
			p.expectOp(")")
		}
		p.expectKw("VALUES")
		for {
			p.expectOp("(")
			var row []*Expr
			for {
				row = append(row, p.parseExpr())
				if !p.acceptOp(",") {
					break
				}
			}
			p.expectOp(")")
			st.rows = append(st.rows, row)
			if !p.acceptOp(",") {
				break
			}
		}
	case "UPDATE":
		p.next()
		st = &Stmt{kind: "update", table: p.name()}
		p.expectKw("SET")
		for {
			st.names = append(st.names, p.name())
			p.expectOp("=")
			st.sets = append(st.sets, p.parseExpr())
			if !p.acceptOp(",") {
				break
			}
		}
		if p.acceptKw("WHERE") {
			st.where = p.parseExpr()
		}
	case "DELETE":
		p.next()
		p.expectKw("FROM")
		st = &Stmt{kind: "delete", table: p.name()}
		if p.acceptKw("WHERE") {
			st.where = p.parseExpr()
		}
	case "SELECT":
		st = &Stmt{kind: "select", sel: p.parseSelect()}
	default:
		fail("syntax error")
	}
	if p.peek().k != tEOF {
		fail("syntax error")
	}
	return st
}

func (p *Parser) parseTRef() TRef {
	r := TRef{name: p.name()}
	r.alias = r.name
	if p.acceptKw("AS") {
		r.alias = p.name()
	} else if p.peek().k == tIdent {
		r.alias = p.name()
	}
	return r
}

func (p *Parser) parseColref() *Expr {
	n := p.name()
	if p.acceptOp(".") {
		return &Expr{typ: eCol, tbl: n, name: p.name()}
	}
	return &Expr{typ: eCol, name: n}
}

func (p *Parser) parseSelect() *Select {
	p.expectKw("SELECT")
	s := &Select{limit: -1, offset: 0}
	if p.acceptKw("DISTINCT") {
		s.distinct = true
	}
	for {
		var it Item
		if p.acceptOp("*") {
			it.star = true
		} else if p.peek().k == tIdent && p.t[p.p+1].k == tOp && p.t[p.p+1].s == "." && p.t[p.p+2].k == tOp && p.t[p.p+2].s == "*" {
			it.star = true
			it.tbl = p.peek().s
			p.p += 3
		} else {
			it.expr = p.parseExpr()
			if p.acceptKw("AS") {
				it.alias = p.name()
				it.hasAlias = true
			}
		}
		s.items = append(s.items, it)
		if !p.acceptOp(",") {
			break
		}
	}
	if p.acceptKw("FROM") {
		s.from = append(s.from, p.parseTRef())
		for {
			left := false
			if p.acceptKw("INNER") {
			} else if p.acceptKw("LEFT") {
				left = true
			} else if !p.isKw("JOIN") {
				break
			}
			p.expectKw("JOIN")
			j := Join{left: left, ref: p.parseTRef()}
			p.expectKw("ON")
			j.on = p.parseExpr()
			s.joins = append(s.joins, j)
		}
	}
	if p.acceptKw("WHERE") {
		s.where = p.parseExpr()
	}
	if p.acceptKw("GROUP") {
		p.expectKw("BY")
		for {
			s.groupBy = append(s.groupBy, p.parseColref())
			if !p.acceptOp(",") {
				break
			}
		}
	}
	if p.acceptKw("HAVING") {
		s.having = p.parseExpr()
	}
	if p.acceptKw("ORDER") {
		p.expectKw("BY")
		for {
			oi := OrderItem{e: p.parseExpr(), out: -1}
			if p.acceptKw("DESC") {
				oi.desc = true
			} else {
				p.acceptKw("ASC")
			}
			s.orderBy = append(s.orderBy, oi)
			if !p.acceptOp(",") {
				break
			}
		}
	}
	if p.acceptKw("LIMIT") {
		t := p.next()
		if t.k != tInt {
			fail("syntax error")
		}
		s.limit = t.n
		if p.acceptKw("OFFSET") {
			t := p.next()
			if t.k != tInt {
				fail("syntax error")
			}
			s.offset = t.n
		}
	}
	return s
}

func (p *Parser) parseExpr() *Expr { return p.parseOr() }

func (p *Parser) parseOr() *Expr {
	l := p.parseAnd()
	for p.acceptKw("OR") {
		r := p.parseAnd()
		l = &Expr{typ: eBin, op: "OR", args: []*Expr{l, r}}
	}
	return l
}
func (p *Parser) parseAnd() *Expr {
	l := p.parseNot()
	for p.acceptKw("AND") {
		r := p.parseNot()
		l = &Expr{typ: eBin, op: "AND", args: []*Expr{l, r}}
	}
	return l
}
func (p *Parser) parseNot() *Expr {
	if p.acceptKw("NOT") {
		return &Expr{typ: eNot, args: []*Expr{p.parseNot()}}
	}
	return p.parseCmp()
}
func (p *Parser) parseCmp() *Expr {
	l := p.parseAdd()
	t := p.peek()
	if t.k == tOp {
		switch t.s {
		case "=", "<>", "<", "<=", ">", ">=":
			p.next()
			r := p.parseAdd()
			return &Expr{typ: eBin, op: t.s, args: []*Expr{l, r}}
		}
		return l
	}
	if t.k != tKw {
		return l
	}
	neg := false
	if t.s == "IS" {
		p.next()
		if p.acceptKw("NOT") {
			neg = true
		}
		p.expectKw("NULL")
		return &Expr{typ: eIsNull, neg: neg, args: []*Expr{l}}
	}
	if t.s == "NOT" {
		nt := p.t[p.p+1]
		if nt.k == tKw && (nt.s == "LIKE" || nt.s == "IN" || nt.s == "BETWEEN") {
			p.next()
			neg = true
			t = p.peek()
		} else {
			return l
		}
	}
	switch t.s {
	case "LIKE":
		p.next()
		r := p.parseAdd()
		return &Expr{typ: eLike, neg: neg, args: []*Expr{l, r}}
	case "IN":
		p.next()
		p.expectOp("(")
		args := []*Expr{l}
		for {
			args = append(args, p.parseExpr())
			if !p.acceptOp(",") {
				break
			}
		}
		p.expectOp(")")
		return &Expr{typ: eIn, neg: neg, args: args}
	case "BETWEEN":
		p.next()
		lo := p.parseAdd()
		p.expectKw("AND")
		hi := p.parseAdd()
		return &Expr{typ: eBetween, neg: neg, args: []*Expr{l, lo, hi}}
	}
	return l
}
func (p *Parser) parseAdd() *Expr {
	l := p.parseMul()
	for p.isOp("+") || p.isOp("-") || p.isOp("||") {
		op := p.next().s
		r := p.parseMul()
		l = &Expr{typ: eBin, op: op, args: []*Expr{l, r}}
	}
	return l
}
func (p *Parser) parseMul() *Expr {
	l := p.parseUnary()
	for p.isOp("*") || p.isOp("/") || p.isOp("%") {
		op := p.next().s
		r := p.parseUnary()
		l = &Expr{typ: eBin, op: op, args: []*Expr{l, r}}
	}
	return l
}
func (p *Parser) parseUnary() *Expr {
	if p.acceptOp("-") {
		return &Expr{typ: eNeg, args: []*Expr{p.parseUnary()}}
	}
	return p.parsePrimary()
}
func (p *Parser) parsePrimary() *Expr {
	t := p.peek()
	switch t.k {
	case tInt:
		p.next()
		return &Expr{typ: eLit, val: vInt(t.n)}
	case tStr:
		p.next()
		return &Expr{typ: eLit, val: vText(t.s)}
	case tKw:
		if t.s == "NULL" {
			p.next()
			return &Expr{typ: eLit, val: null}
		}
		fail("syntax error")
	case tOp:
		if t.s == "(" {
			p.next()
			e := p.parseExpr()
			p.expectOp(")")
			return e
		}
		fail("syntax error")
	case tIdent:
		nt := p.t[p.p+1]
		if nt.k == tOp && nt.s == "(" {
			p.p += 2
			e := &Expr{typ: eCall, fn: strings.ToUpper(t.s)}
			if p.acceptKw("DISTINCT") {
				e.distinct = true
			}
			if p.acceptOp("*") {
				if e.fn != "COUNT" {
					fail("syntax error")
				}
				e.star = true
			} else if !p.isOp(")") {
				for {
					e.args = append(e.args, p.parseExpr())
					if !p.acceptOp(",") {
						break
					}
				}
			}
			p.expectOp(")")
			if e.distinct && !e.star && len(e.args) != 1 {
				fail("syntax error")
			}
			return e
		}
		return p.parseColref()
	}
	fail("syntax error")
	return nil
}

// ---------- database ----------
type Table struct {
	name string
	cols []ColDef
	rows [][]Value
}

var db = map[string]*Table{}

type scTab struct {
	alias string
	cols  []string
	off   int
}
type scope struct {
	tabs []scTab
	n    int
}

func (s *scope) add(alias string, cols []string) {
	s.tabs = append(s.tabs, scTab{alias, cols, s.n})
	s.n += len(cols)
}

func (e *Expr) display() string {
	if e.tbl != "" {
		return e.tbl + "." + e.name
	}
	return e.name
}

func (s *scope) lookup(e *Expr) int {
	if s == nil {
		fail("no such column: " + e.display())
	}
	if e.tbl != "" {
		for _, t := range s.tabs {
			if t.alias == e.tbl {
				for i, c := range t.cols {
					if c == e.name {
						return t.off + i
					}
				}
				break
			}
		}
		fail("no such column: " + e.display())
	}
	found := -1
	cnt := 0
	for _, t := range s.tabs {
		for i, c := range t.cols {
			if c == e.name {
				cnt++
				found = t.off + i
			}
		}
	}
	if cnt == 0 {
		fail("no such column: " + e.name)
	}
	if cnt > 1 {
		fail("ambiguous column: " + e.name)
	}
	return found
}

func isAggName(n string) bool { return n == "COUNT" || n == "SUM" || n == "MIN" || n == "MAX" }

func resolve(e *Expr, sc *scope, aggOK, inAgg bool) {
	switch e.typ {
	case eLit:
	case eCol:
		e.idx = sc.lookup(e)
	case eCall:
		if isAggName(e.fn) {
			if !e.star && len(e.args) != 1 {
				fail("wrong number of arguments to " + e.fn)
			}
			if !aggOK || inAgg {
				fail("misuse of aggregate")
			}
			e.agg = true
			for _, a := range e.args {
				resolve(a, sc, aggOK, true)
			}
			return
		}
		switch e.fn {
		case "UPPER", "LOWER", "LENGTH", "ABS":
			if len(e.args) != 1 {
				fail("wrong number of arguments to " + e.fn)
			}
		case "SUBSTR":
			if len(e.args) != 3 {
				fail("wrong number of arguments to " + e.fn)
			}
		case "COALESCE":
			if len(e.args) < 1 {
				fail("wrong number of arguments to " + e.fn)
			}
		default:
			fail("no such function: " + e.fn)
		}
		for _, a := range e.args {
			resolve(a, sc, aggOK, inAgg)
		}
	default:
		for _, a := range e.args {
			resolve(a, sc, aggOK, inAgg)
		}
	}
}

func hasAgg(e *Expr) bool {
	if e.typ == eCall && e.agg {
		return true
	}
	for _, a := range e.args {
		if hasAgg(a) {
			return true
		}
	}
	return false
}

func checkGroup(e *Expr, g map[int]bool) {
	switch e.typ {
	case eCol:
		if !g[e.idx] {
			fail("column " + e.display() + " must appear in GROUP BY")
		}
		return
	case eCall:
		if e.agg {
			return
		}
	}
	for _, a := range e.args {
		checkGroup(a, g)
	}
}

// ---------- evaluation ----------
type ctx struct {
	row     []Value
	group   [][]Value
	grouped bool
}

func truthy(v Value) bool {
	switch v.k {
	case kBool:
		return v.i != 0
	case kNull:
		return false
	}
	fail("type error")
	return false
}

func cmpSame(a, b Value) int {
	if a.k == kInt {
		switch {
		case a.i < b.i:
			return -1
		case a.i > b.i:
			return 1
		}
		return 0
	}
	return strings.Compare(a.s, b.s)
}

func compare(op string, a, b Value) Value {
	if a.k == kNull || b.k == kNull {
		return null
	}
	if a.k != b.k || (a.k != kInt && a.k != kText) {
		fail("type error")
	}
	c := cmpSame(a, b)
	var r bool
	switch op {
	case "=":
		r = c == 0
	case "<>":
		r = c != 0
	case "<":
		r = c < 0
	case "<=":
		r = c <= 0
	case ">":
		r = c > 0
	case ">=":
		r = c >= 0
	}
	return vBool(r)
}

func boolOrNull(v Value) {
	if v.k != kBool && v.k != kNull {
		fail("type error")
	}
}

func notV(v Value) Value {
	if v.k == kNull {
		return null
	}
	return vBool(v.i == 0)
}

func likeMatch(s, p string) bool {
	si, pi := 0, 0
	star, mark := -1, 0
	for si < len(s) {
		if pi < len(p) && p[pi] == '%' {
			star = pi
			mark = si
			pi++
		} else if pi < len(p) && (p[pi] == '_' || p[pi] == s[si]) {
			pi++
			si++
		} else if star >= 0 {
			pi = star + 1
			mark++
			si = mark
		} else {
			return false
		}
	}
	for pi < len(p) && p[pi] == '%' {
		pi++
	}
	return pi == len(p)
}

func eval(e *Expr, c *ctx) Value {
	switch e.typ {
	case eLit:
		return e.val
	case eCol:
		return c.row[e.idx]
	case eNeg:
		v := eval(e.args[0], c)
		if v.k == kNull {
			return null
		}
		if v.k != kInt {
			fail("type error")
		}
		return vInt(-v.i)
	case eNot:
		v := eval(e.args[0], c)
		boolOrNull(v)
		return notV(v)
	case eIsNull:
		v := eval(e.args[0], c)
		return vBool((v.k == kNull) != e.neg)
	case eBin:
		switch e.op {
		case "AND":
			l := eval(e.args[0], c)
			boolOrNull(l)
			if l.k == kBool && l.i == 0 {
				return vBool(false)
			}
			r := eval(e.args[1], c)
			boolOrNull(r)
			if r.k == kBool && r.i == 0 {
				return vBool(false)
			}
			if l.k == kNull || r.k == kNull {
				return null
			}
			return vBool(true)
		case "OR":
			l := eval(e.args[0], c)
			boolOrNull(l)
			if l.k == kBool && l.i != 0 {
				return vBool(true)
			}
			r := eval(e.args[1], c)
			boolOrNull(r)
			if r.k == kBool && r.i != 0 {
				return vBool(true)
			}
			if l.k == kNull || r.k == kNull {
				return null
			}
			return vBool(false)
		case "=", "<>", "<", "<=", ">", ">=":
			l := eval(e.args[0], c)
			r := eval(e.args[1], c)
			return compare(e.op, l, r)
		case "||":
			l := eval(e.args[0], c)
			r := eval(e.args[1], c)
			if l.k == kNull || r.k == kNull {
				return null
			}
			if l.k != kText || r.k != kText {
				fail("type error")
			}
			return vText(l.s + r.s)
		default:
			l := eval(e.args[0], c)
			r := eval(e.args[1], c)
			if l.k == kNull || r.k == kNull {
				return null
			}
			if l.k != kInt || r.k != kInt {
				fail("type error")
			}
			switch e.op {
			case "+":
				return vInt(l.i + r.i)
			case "-":
				return vInt(l.i - r.i)
			case "*":
				return vInt(l.i * r.i)
			case "/":
				if r.i == 0 {
					fail("division by zero")
				}
				if r.i == -1 {
					return vInt(-l.i)
				}
				return vInt(l.i / r.i)
			default:
				if r.i == 0 {
					fail("division by zero")
				}
				if r.i == -1 {
					return vInt(0)
				}
				return vInt(l.i % r.i)
			}
		}
	case eLike:
		l := eval(e.args[0], c)
		r := eval(e.args[1], c)
		if l.k == kNull || r.k == kNull {
			return null
		}
		if l.k != kText || r.k != kText {
			fail("type error")
		}
		res := vBool(likeMatch(l.s, r.s))
		if e.neg {
			res = notV(res)
		}
		return res
	case eIn:
		x := eval(e.args[0], c)
		sawNull := false
		found := false
		for _, a := range e.args[1:] {
			v := eval(a, c)
			if x.k == kNull {
				continue
			}
			if v.k == kNull {
				sawNull = true
				continue
			}
			r := compare("=", x, v)
			if r.i != 0 {
				found = true
				break
			}
		}
		var res Value
		switch {
		case x.k == kNull:
			res = null
		case found:
			res = vBool(true)
		case sawNull:
			res = null
		default:
			res = vBool(false)
		}
		if e.neg {
			res = notV(res)
		}
		return res
	case eBetween:
		x := eval(e.args[0], c)
		lo := eval(e.args[1], c)
		hi := eval(e.args[2], c)
		a := compare(">=", x, lo)
		var res Value
		if a.k == kBool && a.i == 0 {
			res = vBool(false)
		} else {
			b := compare("<=", x, hi)
			if b.k == kBool && b.i == 0 {
				res = vBool(false)
			} else if a.k == kNull || b.k == kNull {
				res = null
			} else {
				res = vBool(true)
			}
		}
		if e.neg {
			res = notV(res)
		}
		return res
	case eCall:
		if e.agg {
			return evalAgg(e, c)
		}
		vals := make([]Value, len(e.args))
		for i, a := range e.args {
			vals[i] = eval(a, c)
		}
		if e.fn == "COALESCE" {
			for _, v := range vals {
				if v.k != kNull {
					return v
				}
			}
			return null
		}
		for _, v := range vals {
			if v.k == kNull {
				return null
			}
		}
		switch e.fn {
		case "UPPER", "LOWER", "LENGTH":
			if vals[0].k != kText {
				fail("type error")
			}
			switch e.fn {
			case "UPPER":
				b := []byte(vals[0].s)
				for i, ch := range b {
					if ch >= 'a' && ch <= 'z' {
						b[i] = ch - 32
					}
				}
				return vText(string(b))
			case "LOWER":
				b := []byte(vals[0].s)
				for i, ch := range b {
					if ch >= 'A' && ch <= 'Z' {
						b[i] = ch + 32
					}
				}
				return vText(string(b))
			}
			return vInt(int64(len(vals[0].s)))
		case "ABS":
			if vals[0].k != kInt {
				fail("type error")
			}
			if vals[0].i < 0 {
				return vInt(-vals[0].i)
			}
			return vals[0]
		case "SUBSTR":
			if vals[0].k != kText || vals[1].k != kInt || vals[2].k != kInt {
				fail("type error")
			}
			s := vals[0].s
			st, ln := vals[1].i, vals[2].i
			if ln <= 0 || st > int64(len(s)) {
				return vText("")
			}
			lo := st
			if lo < 1 {
				lo = 1
			}
			var hi int64
			if ln > int64(len(s)) {
				hi = int64(len(s))
			} else {
				hi = st + ln - 1
				if hi > int64(len(s)) {
					hi = int64(len(s))
				}
			}
			if lo > hi {
				return vText("")
			}
			return vText(s[lo-1 : hi])
		}
	}
	fail("type error")
	return null
}

func evalAgg(e *Expr, c *ctx) Value {
	if e.star {
		return vInt(int64(len(c.group)))
	}
	var vals []Value
	seen := map[string]bool{}
	for _, r := range c.group {
		v := eval(e.args[0], &ctx{row: r})
		if v.k == kNull {
			continue
		}
		if e.distinct {
			k := valueKey(v)
			if seen[k] {
				continue
			}
			seen[k] = true
		}
		vals = append(vals, v)
	}
	switch e.fn {
	case "COUNT":
		return vInt(int64(len(vals)))
	case "SUM":
		var s int64
		for _, v := range vals {
			if v.k != kInt {
				fail("type error")
			}
			s += v.i
		}
		if len(vals) == 0 {
			return null
		}
		return vInt(s)
	}
	if len(vals) == 0 {
		return null
	}
	best := vals[0]
	for _, v := range vals {
		if v.k != kInt && v.k != kText {
			fail("type error")
		}
		if v.k != best.k {
			fail("type error")
		}
	}
	for _, v := range vals[1:] {
		cm := cmpSame(v, best)
		if (e.fn == "MIN" && cm < 0) || (e.fn == "MAX" && cm > 0) {
			best = v
		}
	}
	return best
}

// ---------- executor ----------
func lookupTable(name string) *Table {
	t, ok := db[name]
	if !ok {
		fail("no such table: " + name)
	}
	return t
}

func tableScope(t *Table) *scope {
	sc := &scope{}
	names := make([]string, len(t.cols))
	for i, c := range t.cols {
		names[i] = c.name
	}
	sc.add(t.name, names)
	return sc
}

func checkRow(t *Table, row []Value) {
	for i, c := range t.cols {
		v := row[i]
		if v.k == kNull {
			if c.notNull || c.pk {
				fail("NOT NULL constraint failed: " + c.name)
			}
		} else if (c.typ == "INT" && v.k != kInt) || (c.typ == "TEXT" && v.k != kText) {
			fail("type mismatch in column " + c.name)
		}
	}
}

func checkPK(t *Table, existing, added [][]Value) {
	pk := -1
	for i, c := range t.cols {
		if c.pk {
			pk = i
		}
	}
	if pk < 0 {
		return
	}
	seen := map[string]bool{}
	for _, set := range [][][]Value{existing, added} {
		for _, r := range set {
			k := valueKey(r[pk])
			if seen[k] {
				fail("duplicate primary key: " + r[pk].String())
			}
			seen[k] = true
		}
	}
}

func execStmt(st *Stmt, out *bufio.Writer) {
	switch st.kind {
	case "create":
		if _, ok := db[st.table]; ok {
			fail("table " + st.table + " already exists")
		}
		seen := map[string]bool{}
		for _, c := range st.cols {
			if seen[c.name] {
				fail("duplicate column: " + c.name)
			}
			seen[c.name] = true
		}
		pks := 0
		for _, c := range st.cols {
			if c.pk {
				pks++
			}
		}
		if pks > 1 {
			fail("multiple primary keys")
		}
		db[st.table] = &Table{name: st.table, cols: st.cols}
		fmt.Fprintln(out, "ok")
	case "drop":
		lookupTable(st.table)
		delete(db, st.table)
		fmt.Fprintln(out, "ok")
	case "insert":
		t := lookupTable(st.table)
		var idxs []int
		if st.hasCols {
			seen := map[string]bool{}
			for _, n := range st.names {
				ix := -1
				for i, c := range t.cols {
					if c.name == n {
						ix = i
					}
				}
				if ix < 0 {
					fail("no such column: " + n)
				}
				if seen[n] {
					fail("duplicate column: " + n)
				}
				seen[n] = true
				idxs = append(idxs, ix)
			}
		} else {
			for i := range t.cols {
				idxs = append(idxs, i)
			}
		}
		var added [][]Value
		for _, r := range st.rows {
			if len(r) != len(idxs) {
				fail("wrong number of values")
			}
			for _, e := range r {
				resolve(e, nil, false, false)
			}
			row := make([]Value, len(t.cols))
			for j, e := range r {
				row[idxs[j]] = eval(e, &ctx{})
			}
			checkRow(t, row)
			added = append(added, row)
		}
		checkPK(t, t.rows, added)
		t.rows = append(t.rows, added...)
		fmt.Fprintf(out, "inserted %d\n", len(added))
	case "update":
		t := lookupTable(st.table)
		var idxs []int
		for _, n := range st.names {
			ix := -1
			for i, c := range t.cols {
				if c.name == n {
					ix = i
				}
			}
			if ix < 0 {
				fail("no such column: " + n)
			}
			idxs = append(idxs, ix)
		}
		sc := tableScope(t)
		for _, e := range st.sets {
			resolve(e, sc, false, false)
		}
		if st.where != nil {
			resolve(st.where, sc, false, false)
		}
		newRows := make([][]Value, len(t.rows))
		cnt := 0
		for ri, r := range t.rows {
			c := &ctx{row: r}
			match := true
			if st.where != nil {
				match = truthy(eval(st.where, c))
			}
			if !match {
				newRows[ri] = r
				continue
			}
			cnt++
			nr := append([]Value(nil), r...)
			for j, e := range st.sets {
				nr[idxs[j]] = eval(e, c)
			}
			checkRow(t, nr)
			newRows[ri] = nr
		}
		checkPK(t, newRows, nil)
		t.rows = newRows
		fmt.Fprintf(out, "updated %d\n", cnt)
	case "delete":
		t := lookupTable(st.table)
		if st.where != nil {
			resolve(st.where, tableScope(t), false, false)
		}
		var keep [][]Value
		cnt := 0
		for _, r := range t.rows {
			match := true
			if st.where != nil {
				match = truthy(eval(st.where, &ctx{row: r}))
			}
			if match {
				cnt++
			} else {
				keep = append(keep, r)
			}
		}
		t.rows = keep
		fmt.Fprintf(out, "deleted %d\n", cnt)
	case "select":
		execSelect(st.sel, out)
	}
}

type outRec struct {
	vals []Value
	c    *ctx
	keys []Value
}

func rank(v Value) int {
	switch v.k {
	case kNull:
		return 0
	case kBool:
		return 1
	case kInt:
		return 2
	}
	return 3
}

func cmpKey(a, b Value) int {
	ra, rb := rank(a), rank(b)
	if ra != rb {
		if ra < rb {
			return -1
		}
		return 1
	}
	switch a.k {
	case kInt, kBool:
		switch {
		case a.i < b.i:
			return -1
		case a.i > b.i:
			return 1
		}
		return 0
	case kText:
		return strings.Compare(a.s, b.s)
	}
	return 0
}

func execSelect(s *Select, out *bufio.Writer) {
	// 1. tables
	var refs []TRef
	refs = append(refs, s.from...)
	for _, j := range s.joins {
		refs = append(refs, j.ref)
	}
	tabs := make([]*Table, len(refs))
	for i, r := range refs {
		tabs[i] = lookupTable(r.name)
	}
	seenAlias := map[string]bool{}
	for _, r := range refs {
		if seenAlias[r.alias] {
			fail("duplicate alias: " + r.alias)
		}
		seenAlias[r.alias] = true
	}
	colNames := func(t *Table) []string {
		n := make([]string, len(t.cols))
		for i, c := range t.cols {
			n[i] = c.name
		}
		return n
	}
	full := &scope{}
	for i, r := range refs {
		full.add(r.alias, colNames(tabs[i]))
	}
	// join conditions
	for ji, j := range s.joins {
		sc := &scope{}
		for i := 0; i <= ji+1; i++ {
			sc.add(refs[i].alias, colNames(tabs[i]))
		}
		resolve(j.on, sc, false, false)
	}
	// stars
	var outNames []string
	var outExprs []*Expr
	for _, it := range s.items {
		if it.star {
			matched := false
			for _, t := range full.tabs {
				if it.tbl != "" && t.alias != it.tbl {
					continue
				}
				matched = true
				for i, cn := range t.cols {
					outNames = append(outNames, cn)
					outExprs = append(outExprs, &Expr{typ: eCol, name: cn, idx: t.off + i})
				}
			}
			if it.tbl != "" && !matched {
				fail("no such table: " + it.tbl)
			}
		}
	}
	// group by
	for _, g := range s.groupBy {
		resolve(g, full, false, false)
	}
	if s.where != nil {
		resolve(s.where, full, false, false)
	}
	outNames = outNames[:0]
	outExprs = outExprs[:0]
	for _, it := range s.items {
		if it.star {
			for _, t := range full.tabs {
				if it.tbl != "" && t.alias != it.tbl {
					continue
				}
				for i, cn := range t.cols {
					outNames = append(outNames, cn)
					outExprs = append(outExprs, &Expr{typ: eCol, name: cn, idx: t.off + i})
				}
			}
			continue
		}
		resolve(it.expr, full, true, false)
		nm := "?column?"
		if it.hasAlias {
			nm = it.alias
		} else if it.expr.typ == eCol {
			nm = it.expr.name
		}
		outNames = append(outNames, nm)
		outExprs = append(outExprs, it.expr)
	}
	if s.having != nil {
		resolve(s.having, full, true, false)
	}
	aggregated := len(s.groupBy) > 0 || s.having != nil
	for _, e := range outExprs {
		if hasAgg(e) {
			aggregated = true
		}
	}
	for i := range s.orderBy {
		oi := &s.orderBy[i]
		e := oi.e
		if e.typ == eLit && e.val.k == kInt {
			if e.val.i < 1 || e.val.i > int64(len(outNames)) {
				fail("bad ORDER BY position")
			}
			oi.out = int(e.val.i) - 1
			continue
		}
		if e.typ == eCol && e.tbl == "" {
			found := -1
			for k, n := range outNames {
				if n == e.name {
					found = k
					break
				}
			}
			if found >= 0 {
				oi.out = found
				continue
			}
		}
		resolve(e, full, true, false)
		if hasAgg(e) {
			aggregated = true
		}
	}
	if aggregated {
		g := map[int]bool{}
		for _, ge := range s.groupBy {
			g[ge.idx] = true
		}
		for _, e := range outExprs {
			checkGroup(e, g)
		}
		if s.having != nil {
			checkGroup(s.having, g)
		}
		for _, oi := range s.orderBy {
			if oi.out < 0 {
				checkGroup(oi.e, g)
			}
		}
	}
	// 3. rows
	var rows [][]Value
	for _, r := range tabs[0:min(1, len(tabs))] {
		for _, row := range r.rows {
			rows = append(rows, row)
		}
	}
	if len(tabs) == 0 {
		rows = [][]Value{{}}
	}
	for ji, j := range s.joins {
		jt := tabs[ji+1]
		var nrows [][]Value
		for _, o := range rows {
			matched := false
			for _, in := range jt.rows {
				comb := make([]Value, 0, len(o)+len(in))
				comb = append(comb, o...)
				comb = append(comb, in...)
				if truthy(eval(j.on, &ctx{row: comb})) {
					matched = true
					nrows = append(nrows, comb)
				}
			}
			if !matched && j.left {
				comb := make([]Value, len(o)+len(jt.cols))
				copy(comb, o)
				nrows = append(nrows, comb)
			}
		}
		rows = nrows
	}
	if s.where != nil {
		var f [][]Value
		for _, r := range rows {
			if truthy(eval(s.where, &ctx{row: r})) {
				f = append(f, r)
			}
		}
		rows = f
	}
	var ctxs []*ctx
	if aggregated {
		if len(s.groupBy) == 0 {
			c := &ctx{group: rows, grouped: true}
			if len(rows) > 0 {
				c.row = rows[0]
			}
			ctxs = append(ctxs, c)
		} else {
			m := map[string]*ctx{}
			for _, r := range rows {
				var sb strings.Builder
				for _, g := range s.groupBy {
					sb.WriteString(valueKey(r[g.idx]))
				}
				k := sb.String()
				c, ok := m[k]
				if !ok {
					c = &ctx{row: r, grouped: true}
					m[k] = c
					ctxs = append(ctxs, c)
				}
				c.group = append(c.group, r)
			}
		}
		if s.having != nil {
			var f []*ctx
			for _, c := range ctxs {
				if truthy(eval(s.having, c)) {
					f = append(f, c)
				}
			}
			ctxs = f
		}
	} else {
		for _, r := range rows {
			ctxs = append(ctxs, &ctx{row: r})
		}
	}
	var recs []*outRec
	for _, c := range ctxs {
		rec := &outRec{c: c, vals: make([]Value, len(outExprs))}
		for i, e := range outExprs {
			rec.vals[i] = eval(e, c)
		}
		recs = append(recs, rec)
	}
	if s.distinct {
		seen := map[string]bool{}
		var f []*outRec
		for _, r := range recs {
			var sb strings.Builder
			for _, v := range r.vals {
				sb.WriteString(valueKey(v))
			}
			k := sb.String()
			if seen[k] {
				continue
			}
			seen[k] = true
			f = append(f, r)
		}
		recs = f
	}
	if len(s.orderBy) > 0 {
		for _, r := range recs {
			r.keys = make([]Value, len(s.orderBy))
			for i, oi := range s.orderBy {
				if oi.out >= 0 {
					r.keys[i] = r.vals[oi.out]
				} else {
					r.keys[i] = eval(oi.e, r.c)
				}
			}
		}
		sort.SliceStable(recs, func(a, b int) bool {
			for i, oi := range s.orderBy {
				c := cmpKey(recs[a].keys[i], recs[b].keys[i])
				if c == 0 {
					continue
				}
				if oi.desc {
					return c > 0
				}
				return c < 0
			}
			return false
		})
	}
	if s.offset > 0 {
		if s.offset >= int64(len(recs)) {
			recs = nil
		} else {
			recs = recs[s.offset:]
		}
	}
	if s.limit >= 0 && s.limit < int64(len(recs)) {
		recs = recs[:s.limit]
	}
	fmt.Fprintln(out, strings.Join(outNames, "|"))
	for _, r := range recs {
		parts := make([]string, len(r.vals))
		for i, v := range r.vals {
			parts[i] = v.String()
		}
		fmt.Fprintln(out, strings.Join(parts, "|"))
	}
	fmt.Fprintf(out, "(%d rows)\n", len(recs))
}

func splitStatements(src string) []string {
	var res []string
	start := 0
	i := 0
	n := len(src)
	for i < n {
		c := src[i]
		switch {
		case c == '\'':
			i++
			for i < n {
				if src[i] == '\'' {
					if i+1 < n && src[i+1] == '\'' {
						i += 2
						continue
					}
					break
				}
				i++
			}
			i++
		case c == '-' && i+1 < n && src[i+1] == '-':
			for i < n && src[i] != '\n' {
				i++
			}
		case c == ';':
			res = append(res, src[start:i])
			i++
			start = i
		default:
			i++
		}
	}
	if start < n {
		res = append(res, src[start:])
	}
	return res
}

func runOne(text string, out *bufio.Writer) {
	defer func() {
		if r := recover(); r != nil {
			if se, ok := r.(sqlError); ok {
				fmt.Fprintln(out, "error: "+se.msg)
				return
			}
			panic(r)
		}
	}()
	toks := lex(text)
	if len(toks) == 1 {
		return
	}
	p := &Parser{t: toks}
	st := p.parseStmt()
	var buf strings.Builder
	bw := bufio.NewWriter(&buf)
	execStmt(st, bw)
	bw.Flush()
	out.WriteString(buf.String())
}

func main() {
	data, _ := io.ReadAll(os.Stdin)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	for _, s := range splitStatements(string(data)) {
		runOne(s, out)
	}
}

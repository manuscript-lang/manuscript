package main

import (
	"bufio"
	"fmt"
	"io"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

// ---------------------------------------------------------------------------
// Errors. SQL errors are raised with throw() and recovered per statement.
// ---------------------------------------------------------------------------

type sqlErr struct{ msg string }

func throw(msg string) { panic(sqlErr{msg}) }

const syntaxMsg = "syntax error"

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

type vkind int

const (
	vNull vkind = iota
	vInt
	vText
	vBool
)

type Value struct {
	k vkind
	i int64
	s string
	b bool
}

var nullV = Value{k: vNull}

func intV(i int64) Value   { return Value{k: vInt, i: i} }
func textV(s string) Value { return Value{k: vText, s: s} }
func boolV(b bool) Value   { return Value{k: vBool, b: b} }

func show(v Value) string {
	switch v.k {
	case vNull:
		return "NULL"
	case vInt:
		return strconv.FormatInt(v.i, 10)
	case vText:
		return v.s
	default:
		if v.b {
			return "true"
		}
		return "false"
	}
}

// keyOf gives an equality key: NULLs are equal to each other.
func keyOf(v Value) string {
	switch v.k {
	case vNull:
		return "N"
	case vInt:
		return "I" + strconv.FormatInt(v.i, 10) + ";"
	case vText:
		return "T" + strconv.Itoa(len(v.s)) + ":" + v.s
	default:
		if v.b {
			return "B1"
		}
		return "B0"
	}
}

func rowKey(vals []Value) string {
	var sb strings.Builder
	for _, v := range vals {
		sb.WriteString(keyOf(v))
	}
	return sb.String()
}

// orderRank: NULL < BOOL < INT < TEXT for ORDER BY keys.
func orderRank(v Value) int {
	switch v.k {
	case vNull:
		return 0
	case vBool:
		return 1
	case vInt:
		return 2
	default:
		return 3
	}
}

func cmpOrder(a, b Value) int {
	ra, rb := orderRank(a), orderRank(b)
	if ra != rb {
		if ra < rb {
			return -1
		}
		return 1
	}
	switch a.k {
	case vInt:
		if a.i < b.i {
			return -1
		} else if a.i > b.i {
			return 1
		}
	case vText:
		return strings.Compare(a.s, b.s)
	case vBool:
		if a.b == b.b {
			return 0
		}
		if !a.b {
			return -1
		}
		return 1
	}
	return 0
}

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

const (
	tIdent = iota
	tKw
	tInt
	tStr
	tOp
	tEOF
)

type token struct {
	kind int
	text string
	ival int64
}

var keywords = map[string]bool{
	"SELECT": true, "FROM": true, "WHERE": true, "GROUP": true, "BY": true, "HAVING": true,
	"ORDER": true, "LIMIT": true, "OFFSET": true, "JOIN": true, "LEFT": true, "INNER": true,
	"ON": true, "AS": true, "AND": true, "OR": true, "NOT": true, "NULL": true, "IS": true,
	"LIKE": true, "IN": true, "BETWEEN": true, "INSERT": true, "INTO": true, "VALUES": true,
	"UPDATE": true, "SET": true, "DELETE": true, "CREATE": true, "TABLE": true, "DROP": true,
	"PRIMARY": true, "KEY": true, "DISTINCT": true, "ASC": true, "DESC": true,
}

func isAlpha(c byte) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}
func isDigit(c byte) bool { return c >= '0' && c <= '9' }
func isAlnum(c byte) bool { return isAlpha(c) || isDigit(c) }

func lex(src string) []token {
	var toks []token
	i, n := 0, len(src)
	for {
		for i < n {
			c := src[i]
			if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
				i++
				continue
			}
			if c == '-' && i+1 < n && src[i+1] == '-' {
				for i < n && src[i] != '\n' {
					i++
				}
				continue
			}
			break
		}
		if i >= n {
			break
		}
		c := src[i]
		switch {
		case isAlpha(c):
			j := i
			for j < n && isAlnum(src[j]) {
				j++
			}
			w := src[i:j]
			up := strings.ToUpper(w)
			if keywords[up] {
				toks = append(toks, token{kind: tKw, text: up})
			} else {
				toks = append(toks, token{kind: tIdent, text: w})
			}
			i = j
		case isDigit(c):
			j := i
			for j < n && isDigit(src[j]) {
				j++
			}
			v, err := strconv.ParseInt(src[i:j], 10, 64)
			if err != nil {
				throw(syntaxMsg)
			}
			toks = append(toks, token{kind: tInt, ival: v})
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
				throw(syntaxMsg)
			}
			toks = append(toks, token{kind: tStr, text: sb.String()})
			i = j
		default:
			if i+1 < n {
				two := src[i : i+2]
				switch two {
				case "<>", "<=", ">=", "||":
					toks = append(toks, token{kind: tOp, text: two})
					i += 2
					continue
				case "!=":
					toks = append(toks, token{kind: tOp, text: "<>"})
					i += 2
					continue
				}
			}
			if strings.IndexByte("=<>+-*/%(),.", c) >= 0 {
				toks = append(toks, token{kind: tOp, text: string(c)})
				i++
			} else {
				throw(syntaxMsg)
			}
		}
	}
	toks = append(toks, token{kind: tEOF})
	return toks
}

// splitStatements splits on ';' outside string literals and comments.
func splitStatements(src string) []string {
	var out []string
	start := 0
	inStr := false
	n := len(src)
	for i := 0; i < n; i++ {
		c := src[i]
		if inStr {
			if c == '\'' {
				inStr = false
			}
			continue
		}
		if c == '\'' {
			inStr = true
			continue
		}
		if c == '-' && i+1 < n && src[i+1] == '-' {
			for i < n && src[i] != '\n' {
				i++
			}
			continue
		}
		if c == ';' {
			out = append(out, src[start:i])
			start = i + 1
		}
	}
	out = append(out, src[start:])
	return out
}

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

type Expr interface{}

type Lit struct{ v Value }

type ColRef struct {
	qual, name string
	idx        int
	pre        bool // idx already known (star expansion)
}

func (c *ColRef) text() string {
	if c.qual != "" {
		return c.qual + "." + c.name
	}
	return c.name
}

type Unary struct {
	op string // "-" or "NOT"
	x  Expr
}

type Binary struct {
	op   string
	l, r Expr
}

type IsNull struct {
	x   Expr
	neg bool
}

type Like struct {
	x, pat Expr
	neg    bool
}

type In struct {
	x    Expr
	list []Expr
	neg  bool
}

type Between struct {
	x, lo, hi Expr
	neg       bool
}

type Call struct {
	name     string // upper case
	distinct bool
	star     bool
	args     []Expr
	agg      bool
	aggIdx   int
}

const (
	tyInt  = 1
	tyText = 2
)

type Column struct {
	name    string
	typ     int
	pk      bool
	notnull bool
}

type Stmt interface{}

type CreateStmt struct {
	name string
	cols []Column
}
type DropStmt struct{ name string }
type InsertStmt struct {
	table   string
	cols    []string
	hasCols bool
	rows    [][]Expr
}
type setItem struct {
	col string
	e   Expr
}
type UpdateStmt struct {
	table string
	sets  []setItem
	where Expr
}
type DeleteStmt struct {
	table string
	where Expr
}

type tref struct{ table, alias string }

type joinItem struct {
	left bool
	t    tref
	on   Expr
}

type selItem struct {
	star     bool
	isTStar  bool
	tstar    string
	e        Expr
	alias    string
	hasAlias bool
}

type orderItem struct {
	e    Expr
	desc bool
}

type SelectStmt struct {
	distinct  bool
	items     []selItem
	from      *tref
	joins     []joinItem
	where     Expr
	groupBy   []*ColRef
	having    Expr
	orderBy   []orderItem
	hasLimit  bool
	limit     int64
	hasOffset bool
	offset    int64
}

// ---------------------------------------------------------------------------
// Parser (errors via throw)
// ---------------------------------------------------------------------------

type parser struct {
	toks []token
	pos  int
}

func (p *parser) peek() token { return p.toks[p.pos] }
func (p *parser) peekN(n int) token {
	if p.pos+n < len(p.toks) {
		return p.toks[p.pos+n]
	}
	return p.toks[len(p.toks)-1]
}
func (p *parser) advance() token {
	t := p.toks[p.pos]
	if t.kind != tEOF {
		p.pos++
	}
	return t
}
func (p *parser) isKw(w string) bool {
	t := p.peek()
	return t.kind == tKw && t.text == w
}
func (p *parser) isOp(o string) bool {
	t := p.peek()
	return t.kind == tOp && t.text == o
}
func (p *parser) acceptKw(w string) bool {
	if p.isKw(w) {
		p.pos++
		return true
	}
	return false
}
func (p *parser) acceptOp(o string) bool {
	if p.isOp(o) {
		p.pos++
		return true
	}
	return false
}
func (p *parser) expectKw(w string) {
	if !p.acceptKw(w) {
		throw(syntaxMsg)
	}
}
func (p *parser) expectOp(o string) {
	if !p.acceptOp(o) {
		throw(syntaxMsg)
	}
}
func (p *parser) ident() string {
	t := p.peek()
	if t.kind != tIdent {
		throw(syntaxMsg)
	}
	p.pos++
	return t.text
}
func (p *parser) intLit() int64 {
	t := p.peek()
	if t.kind != tInt {
		throw(syntaxMsg)
	}
	p.pos++
	return t.ival
}

func parseStatement(toks []token) Stmt {
	p := &parser{toks: toks}
	var st Stmt
	switch {
	case p.isKw("SELECT"):
		st = p.parseSelect()
	case p.isKw("INSERT"):
		st = p.parseInsert()
	case p.isKw("UPDATE"):
		st = p.parseUpdate()
	case p.isKw("DELETE"):
		st = p.parseDelete()
	case p.isKw("CREATE"):
		st = p.parseCreate()
	case p.isKw("DROP"):
		st = p.parseDrop()
	default:
		throw(syntaxMsg)
	}
	if p.peek().kind != tEOF {
		throw(syntaxMsg)
	}
	return st
}

func (p *parser) parseCreate() Stmt {
	p.expectKw("CREATE")
	p.expectKw("TABLE")
	st := &CreateStmt{name: p.ident()}
	p.expectOp("(")
	for {
		c := Column{name: p.ident()}
		switch strings.ToUpper(p.ident()) {
		case "INT":
			c.typ = tyInt
		case "TEXT":
			c.typ = tyText
		default:
			throw(syntaxMsg)
		}
		for {
			if p.acceptKw("PRIMARY") {
				p.expectKw("KEY")
				c.pk = true
				c.notnull = true
				continue
			}
			if p.acceptKw("NOT") {
				p.expectKw("NULL")
				c.notnull = true
				continue
			}
			break
		}
		st.cols = append(st.cols, c)
		if !p.acceptOp(",") {
			break
		}
	}
	p.expectOp(")")
	return st
}

func (p *parser) parseDrop() Stmt {
	p.expectKw("DROP")
	p.expectKw("TABLE")
	return &DropStmt{name: p.ident()}
}

func (p *parser) parseInsert() Stmt {
	p.expectKw("INSERT")
	p.expectKw("INTO")
	st := &InsertStmt{table: p.ident()}
	if p.acceptOp("(") {
		st.hasCols = true
		for {
			st.cols = append(st.cols, p.ident())
			if !p.acceptOp(",") {
				break
			}
		}
		p.expectOp(")")
	}
	p.expectKw("VALUES")
	for {
		p.expectOp("(")
		var row []Expr
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
	return st
}

func (p *parser) parseUpdate() Stmt {
	p.expectKw("UPDATE")
	st := &UpdateStmt{table: p.ident()}
	p.expectKw("SET")
	for {
		col := p.ident()
		p.expectOp("=")
		st.sets = append(st.sets, setItem{col: col, e: p.parseExpr()})
		if !p.acceptOp(",") {
			break
		}
	}
	if p.acceptKw("WHERE") {
		st.where = p.parseExpr()
	}
	return st
}

func (p *parser) parseDelete() Stmt {
	p.expectKw("DELETE")
	p.expectKw("FROM")
	st := &DeleteStmt{table: p.ident()}
	if p.acceptKw("WHERE") {
		st.where = p.parseExpr()
	}
	return st
}

func (p *parser) parseTref() tref {
	t := tref{table: p.ident()}
	t.alias = t.table
	if p.acceptKw("AS") {
		t.alias = p.ident()
	} else if p.peek().kind == tIdent {
		t.alias = p.ident()
	}
	return t
}

func (p *parser) parseColRefPlain() *ColRef {
	name := p.ident()
	if p.acceptOp(".") {
		return &ColRef{qual: name, name: p.ident()}
	}
	return &ColRef{name: name}
}

func (p *parser) parseItem() selItem {
	if p.acceptOp("*") {
		return selItem{star: true}
	}
	t0, t1, t2 := p.peek(), p.peekN(1), p.peekN(2)
	if t0.kind == tIdent && t1.kind == tOp && t1.text == "." && t2.kind == tOp && t2.text == "*" {
		p.pos += 3
		return selItem{isTStar: true, tstar: t0.text}
	}
	it := selItem{e: p.parseExpr()}
	if p.acceptKw("AS") {
		it.alias = p.ident()
		it.hasAlias = true
	}
	return it
}

func (p *parser) parseSelect() Stmt {
	p.expectKw("SELECT")
	st := &SelectStmt{}
	st.distinct = p.acceptKw("DISTINCT")
	for {
		st.items = append(st.items, p.parseItem())
		if !p.acceptOp(",") {
			break
		}
	}
	if p.acceptKw("FROM") {
		t := p.parseTref()
		st.from = &t
		for {
			var j joinItem
			if p.acceptKw("LEFT") {
				j.left = true
				p.expectKw("JOIN")
			} else if p.acceptKw("INNER") {
				p.expectKw("JOIN")
			} else if !p.acceptKw("JOIN") {
				break
			}
			j.t = p.parseTref()
			p.expectKw("ON")
			j.on = p.parseExpr()
			st.joins = append(st.joins, j)
		}
	}
	if p.acceptKw("WHERE") {
		st.where = p.parseExpr()
	}
	if p.acceptKw("GROUP") {
		p.expectKw("BY")
		for {
			st.groupBy = append(st.groupBy, p.parseColRefPlain())
			if !p.acceptOp(",") {
				break
			}
		}
	}
	if p.acceptKw("HAVING") {
		st.having = p.parseExpr()
	}
	if p.acceptKw("ORDER") {
		p.expectKw("BY")
		for {
			e := p.parseExpr()
			desc := false
			if p.acceptKw("DESC") {
				desc = true
			} else {
				p.acceptKw("ASC")
			}
			st.orderBy = append(st.orderBy, orderItem{e: e, desc: desc})
			if !p.acceptOp(",") {
				break
			}
		}
	}
	if p.acceptKw("LIMIT") {
		st.hasLimit = true
		st.limit = p.intLit()
		if p.acceptKw("OFFSET") {
			st.hasOffset = true
			st.offset = p.intLit()
		}
	}
	return st
}

func (p *parser) parseExpr() Expr { return p.parseOr() }

func (p *parser) parseOr() Expr {
	e := p.parseAnd()
	for p.acceptKw("OR") {
		e = &Binary{op: "OR", l: e, r: p.parseAnd()}
	}
	return e
}

func (p *parser) parseAnd() Expr {
	e := p.parseNot()
	for p.acceptKw("AND") {
		e = &Binary{op: "AND", l: e, r: p.parseNot()}
	}
	return e
}

func (p *parser) parseNot() Expr {
	if p.acceptKw("NOT") {
		return &Unary{op: "NOT", x: p.parseNot()}
	}
	return p.parseCmp()
}

func (p *parser) parseInList(left Expr, neg bool) Expr {
	p.expectOp("(")
	var list []Expr
	for {
		list = append(list, p.parseExpr())
		if !p.acceptOp(",") {
			break
		}
	}
	p.expectOp(")")
	return &In{x: left, list: list, neg: neg}
}

func (p *parser) parseBetween(left Expr, neg bool) Expr {
	lo := p.parseAdd()
	p.expectKw("AND")
	hi := p.parseAdd()
	return &Between{x: left, lo: lo, hi: hi, neg: neg}
}

func (p *parser) parseCmp() Expr {
	left := p.parseAdd()
	t := p.peek()
	if t.kind == tOp {
		switch t.text {
		case "=", "<>", "<", "<=", ">", ">=":
			p.pos++
			return &Binary{op: t.text, l: left, r: p.parseAdd()}
		}
		return left
	}
	if t.kind != tKw {
		return left
	}
	switch t.text {
	case "IS":
		p.pos++
		neg := p.acceptKw("NOT")
		p.expectKw("NULL")
		return &IsNull{x: left, neg: neg}
	case "LIKE":
		p.pos++
		return &Like{x: left, pat: p.parseAdd()}
	case "IN":
		p.pos++
		return p.parseInList(left, false)
	case "BETWEEN":
		p.pos++
		return p.parseBetween(left, false)
	case "NOT":
		nt := p.peekN(1)
		if nt.kind == tKw {
			switch nt.text {
			case "LIKE":
				p.pos += 2
				return &Like{x: left, pat: p.parseAdd(), neg: true}
			case "IN":
				p.pos += 2
				return p.parseInList(left, true)
			case "BETWEEN":
				p.pos += 2
				return p.parseBetween(left, true)
			}
		}
		throw(syntaxMsg)
	}
	return left
}

func (p *parser) parseAdd() Expr {
	e := p.parseMul()
	for p.isOp("+") || p.isOp("-") || p.isOp("||") {
		op := p.advance().text
		e = &Binary{op: op, l: e, r: p.parseMul()}
	}
	return e
}

func (p *parser) parseMul() Expr {
	e := p.parseUnary()
	for p.isOp("*") || p.isOp("/") || p.isOp("%") {
		op := p.advance().text
		e = &Binary{op: op, l: e, r: p.parseUnary()}
	}
	return e
}

func (p *parser) parseUnary() Expr {
	if p.acceptOp("-") {
		return &Unary{op: "-", x: p.parseUnary()}
	}
	return p.parsePrimary()
}

func (p *parser) parsePrimary() Expr {
	t := p.peek()
	switch t.kind {
	case tInt:
		p.pos++
		return &Lit{v: intV(t.ival)}
	case tStr:
		p.pos++
		return &Lit{v: textV(t.text)}
	case tKw:
		if t.text == "NULL" {
			p.pos++
			return &Lit{v: nullV}
		}
	case tOp:
		if t.text == "(" {
			p.pos++
			e := p.parseExpr()
			p.expectOp(")")
			return e
		}
	case tIdent:
		p.pos++
		if p.isOp("(") {
			return p.parseCall(t.text)
		}
		if p.acceptOp(".") {
			return &ColRef{qual: t.text, name: p.ident()}
		}
		return &ColRef{name: t.text}
	}
	throw(syntaxMsg)
	return nil
}

func (p *parser) parseCall(name string) Expr {
	p.expectOp("(")
	c := &Call{name: strings.ToUpper(name)}
	if p.acceptOp(")") {
		return c
	}
	if p.acceptKw("DISTINCT") {
		c.distinct = true
		if p.acceptOp(")") {
			return c
		}
	}
	if p.acceptOp("*") {
		c.star = true
		p.expectOp(")")
		return c
	}
	for {
		c.args = append(c.args, p.parseExpr())
		if !p.acceptOp(",") {
			break
		}
	}
	p.expectOp(")")
	return c
}

// ---------------------------------------------------------------------------
// Scopes and name resolution
// ---------------------------------------------------------------------------

type stab struct {
	alias string
	cols  []Column
	off   int
}

type scope struct {
	tabs  []stab
	width int
}

func (sc *scope) add(alias string, cols []Column) {
	sc.tabs = append(sc.tabs, stab{alias: alias, cols: cols, off: sc.width})
	sc.width += len(cols)
}

func (sc *scope) lookup(qual, name string) int {
	if qual != "" {
		for _, t := range sc.tabs {
			if t.alias == qual {
				for j, c := range t.cols {
					if c.name == name {
						return t.off + j
					}
				}
				break
			}
		}
		throw("no such column: " + qual + "." + name)
	}
	found, count := -1, 0
	for _, t := range sc.tabs {
		for j, c := range t.cols {
			if c.name == name {
				found = t.off + j
				count++
			}
		}
	}
	if count == 0 {
		throw("no such column: " + name)
	}
	if count > 1 {
		throw("ambiguous column: " + name)
	}
	return found
}

type rctx struct {
	sc         *scope
	allowAgg   bool
	inAgg      bool
	aggregated bool
	groupIdx   map[int]bool
	aggs       []*Call
}

func isAggName(n string) bool {
	return n == "COUNT" || n == "SUM" || n == "MIN" || n == "MAX"
}

func hasAgg(e Expr) bool {
	switch x := e.(type) {
	case *Call:
		if isAggName(x.name) {
			return true
		}
		for _, a := range x.args {
			if hasAgg(a) {
				return true
			}
		}
	case *Unary:
		return hasAgg(x.x)
	case *Binary:
		return hasAgg(x.l) || hasAgg(x.r)
	case *IsNull:
		return hasAgg(x.x)
	case *Like:
		return hasAgg(x.x) || hasAgg(x.pat)
	case *In:
		if hasAgg(x.x) {
			return true
		}
		for _, a := range x.list {
			if hasAgg(a) {
				return true
			}
		}
	case *Between:
		return hasAgg(x.x) || hasAgg(x.lo) || hasAgg(x.hi)
	}
	return false
}

func wrongArgs(name string) {
	throw("wrong number of arguments to " + name)
}

func resolve(e Expr, rc *rctx) {
	switch x := e.(type) {
	case *Lit:
	case *ColRef:
		if !x.pre {
			x.idx = rc.sc.lookup(x.qual, x.name)
		}
		if rc.aggregated && !rc.inAgg && !rc.groupIdx[x.idx] {
			throw("column " + x.text() + " must appear in GROUP BY")
		}
	case *Unary:
		resolve(x.x, rc)
	case *Binary:
		resolve(x.l, rc)
		resolve(x.r, rc)
	case *IsNull:
		resolve(x.x, rc)
	case *Like:
		resolve(x.x, rc)
		resolve(x.pat, rc)
	case *In:
		resolve(x.x, rc)
		for _, a := range x.list {
			resolve(a, rc)
		}
	case *Between:
		resolve(x.x, rc)
		resolve(x.lo, rc)
		resolve(x.hi, rc)
	case *Call:
		resolveCall(x, rc)
	default:
		throw("internal: unknown expression")
	}
}

func resolveCall(c *Call, rc *rctx) {
	if isAggName(c.name) {
		if !rc.allowAgg || rc.inAgg {
			throw("misuse of aggregate")
		}
		if c.name == "COUNT" {
			if c.star {
				if c.distinct {
					wrongArgs(c.name)
				}
			} else if len(c.args) != 1 {
				wrongArgs(c.name)
			}
		} else if c.star || len(c.args) != 1 {
			wrongArgs(c.name)
		}
		saved := rc.inAgg
		rc.inAgg = true
		for _, a := range c.args {
			resolve(a, rc)
		}
		rc.inAgg = saved
		c.agg = true
		c.aggIdx = len(rc.aggs)
		rc.aggs = append(rc.aggs, c)
		return
	}
	switch c.name {
	case "UPPER", "LOWER", "LENGTH", "ABS":
		if c.star || len(c.args) != 1 {
			wrongArgs(c.name)
		}
	case "SUBSTR":
		if c.star || len(c.args) != 3 {
			wrongArgs(c.name)
		}
	case "COALESCE":
		if c.star || len(c.args) < 1 {
			wrongArgs(c.name)
		}
	default:
		throw("no such function: " + c.name)
	}
	for _, a := range c.args {
		resolve(a, rc)
	}
}

// ---------------------------------------------------------------------------
// Expression evaluation
// ---------------------------------------------------------------------------

type ectx struct {
	row  []Value
	aggs []Value
}

func truth(v Value) bool {
	switch v.k {
	case vNull:
		return false
	case vBool:
		return v.b
	}
	throw("type error")
	return false
}

func not3(v Value) Value {
	switch v.k {
	case vNull:
		return nullV
	case vBool:
		return boolV(!v.b)
	}
	throw("type error")
	return nullV
}

func and3(a, b Value) Value {
	if (a.k == vBool && !a.b) || (b.k == vBool && !b.b) {
		return boolV(false)
	}
	if a.k == vNull || b.k == vNull {
		return nullV
	}
	return boolV(true)
}

func compareOp(op string, a, b Value) Value {
	if a.k == vNull || b.k == vNull {
		return nullV
	}
	var c int
	switch {
	case a.k == vInt && b.k == vInt:
		if a.i < b.i {
			c = -1
		} else if a.i > b.i {
			c = 1
		}
	case a.k == vText && b.k == vText:
		c = strings.Compare(a.s, b.s)
	default:
		throw("type error")
	}
	switch op {
	case "=":
		return boolV(c == 0)
	case "<>":
		return boolV(c != 0)
	case "<":
		return boolV(c < 0)
	case "<=":
		return boolV(c <= 0)
	case ">":
		return boolV(c > 0)
	default:
		return boolV(c >= 0)
	}
}

func arith(op string, a, b Value) Value {
	if a.k == vNull || b.k == vNull {
		return nullV
	}
	if a.k != vInt || b.k != vInt {
		throw("type error")
	}
	switch op {
	case "+":
		return intV(a.i + b.i)
	case "-":
		return intV(a.i - b.i)
	case "*":
		return intV(a.i * b.i)
	case "/":
		if b.i == 0 {
			throw("division by zero")
		}
		return intV(a.i / b.i)
	default:
		if b.i == 0 {
			throw("division by zero")
		}
		return intV(a.i % b.i)
	}
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
			si++
			pi++
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

func asciiUpper(s string) string {
	b := []byte(s)
	for i, c := range b {
		if c >= 'a' && c <= 'z' {
			b[i] = c - 32
		}
	}
	return string(b)
}

func asciiLower(s string) string {
	b := []byte(s)
	for i, c := range b {
		if c >= 'A' && c <= 'Z' {
			b[i] = c + 32
		}
	}
	return string(b)
}

func substr(s string, start, length int64) string {
	if length <= 0 {
		return ""
	}
	n := int64(len(s))
	var end int64
	if start > math.MaxInt64-(length-1) {
		end = math.MaxInt64
	} else {
		end = start + length - 1
	}
	lo := start
	if lo < 1 {
		lo = 1
	}
	hi := end
	if hi > n {
		hi = n
	}
	if lo > hi {
		return ""
	}
	return s[lo-1 : hi]
}

func needText(v Value) string {
	if v.k != vText {
		throw("type error")
	}
	return v.s
}

func needInt(v Value) int64 {
	if v.k != vInt {
		throw("type error")
	}
	return v.i
}

func eval(e Expr, c *ectx) Value {
	switch x := e.(type) {
	case *Lit:
		return x.v
	case *ColRef:
		if c.row == nil {
			return nullV
		}
		return c.row[x.idx]
	case *Unary:
		v := eval(x.x, c)
		if x.op == "NOT" {
			return not3(v)
		}
		if v.k == vNull {
			return nullV
		}
		return intV(-needInt(v))
	case *Binary:
		switch x.op {
		case "AND":
			l := eval(x.l, c)
			if l.k == vBool && !l.b {
				return boolV(false)
			}
			if l.k != vNull && l.k != vBool {
				throw("type error")
			}
			r := eval(x.r, c)
			if r.k != vNull && r.k != vBool {
				throw("type error")
			}
			if l.k == vNull {
				if r.k == vBool && !r.b {
					return boolV(false)
				}
				return nullV
			}
			return r
		case "OR":
			l := eval(x.l, c)
			if l.k == vBool && l.b {
				return boolV(true)
			}
			if l.k != vNull && l.k != vBool {
				throw("type error")
			}
			r := eval(x.r, c)
			if r.k != vNull && r.k != vBool {
				throw("type error")
			}
			if l.k == vNull {
				if r.k == vBool && r.b {
					return boolV(true)
				}
				return nullV
			}
			return r
		}
		l := eval(x.l, c)
		r := eval(x.r, c)
		switch x.op {
		case "+", "-", "*", "/", "%":
			return arith(x.op, l, r)
		case "||":
			if l.k == vNull || r.k == vNull {
				return nullV
			}
			return textV(needText(l) + needText(r))
		default:
			return compareOp(x.op, l, r)
		}
	case *IsNull:
		v := eval(x.x, c)
		return boolV((v.k == vNull) != x.neg)
	case *Like:
		xv := eval(x.x, c)
		pv := eval(x.pat, c)
		if xv.k == vNull || pv.k == vNull {
			return nullV
		}
		m := likeMatch(needText(xv), needText(pv))
		return boolV(m != x.neg)
	case *In:
		xv := eval(x.x, c)
		var res Value
		if xv.k == vNull {
			for _, el := range x.list {
				eval(el, c)
			}
			res = nullV
		} else {
			sawNull, matched := false, false
			for _, el := range x.list {
				v := eval(el, c)
				if v.k == vNull {
					sawNull = true
					continue
				}
				if xv.k != v.k || xv.k == vBool {
					throw("type error")
				}
				if (xv.k == vInt && xv.i == v.i) || (xv.k == vText && xv.s == v.s) {
					matched = true
					break
				}
			}
			switch {
			case matched:
				res = boolV(true)
			case sawNull:
				res = nullV
			default:
				res = boolV(false)
			}
		}
		if x.neg {
			return not3(res)
		}
		return res
	case *Between:
		xv := eval(x.x, c)
		lo := eval(x.lo, c)
		hi := eval(x.hi, c)
		ge := compareOp(">=", xv, lo)
		var res Value
		if ge.k == vBool && !ge.b {
			res = boolV(false)
		} else {
			res = and3(ge, compareOp("<=", xv, hi))
		}
		if x.neg {
			return not3(res)
		}
		return res
	case *Call:
		return evalCall(x, c)
	}
	throw("internal: unknown expression")
	return nullV
}

func evalCall(x *Call, c *ectx) Value {
	if x.agg {
		return c.aggs[x.aggIdx]
	}
	if x.name == "COALESCE" {
		var res Value
		found := false
		for _, a := range x.args {
			v := eval(a, c)
			if !found && v.k != vNull {
				res = v
				found = true
			}
		}
		if !found {
			return nullV
		}
		return res
	}
	vals := make([]Value, len(x.args))
	for i, a := range x.args {
		vals[i] = eval(a, c)
	}
	for _, v := range vals {
		if v.k == vNull {
			return nullV
		}
	}
	switch x.name {
	case "UPPER":
		return textV(asciiUpper(needText(vals[0])))
	case "LOWER":
		return textV(asciiLower(needText(vals[0])))
	case "LENGTH":
		return intV(int64(len(needText(vals[0]))))
	case "ABS":
		v := needInt(vals[0])
		if v < 0 {
			v = -v
		}
		return intV(v)
	case "SUBSTR":
		s := needText(vals[0])
		st := needInt(vals[1])
		ln := needInt(vals[2])
		return textV(substr(s, st, ln))
	}
	throw("no such function: " + x.name)
	return nullV
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

type Table struct {
	name string
	cols []Column
	rows [][]Value
	pk   int // index of PRIMARY KEY column or -1
}

type DB struct {
	tables map[string]*Table
}

func (db *DB) table(name string) *Table {
	t := db.tables[name]
	if t == nil {
		throw("no such table: " + name)
	}
	return t
}

func (t *Table) colIndex(name string) int {
	for i, c := range t.cols {
		if c.name == name {
			return i
		}
	}
	return -1
}

func (t *Table) tableScope() *scope {
	sc := &scope{}
	sc.add(t.name, t.cols)
	return sc
}

// checkRow applies NOT NULL and type constraints in column declaration order.
func checkRow(t *Table, vals []Value) {
	for i, c := range t.cols {
		v := vals[i]
		if c.notnull && v.k == vNull {
			throw("NOT NULL constraint failed: " + c.name)
		}
		if v.k != vNull {
			ok := (c.typ == tyInt && v.k == vInt) || (c.typ == tyText && v.k == vText)
			if !ok {
				throw("type mismatch in column " + c.name)
			}
		}
	}
}

// checkPKDup reports the first duplicate primary key among the given rows
// (in order), also against rowsExisting.
func checkPKDup(t *Table, existing [][]Value, rows [][]Value) {
	if t.pk < 0 {
		return
	}
	seen := make(map[string]bool, len(existing)+len(rows))
	for _, r := range existing {
		seen[keyOf(r[t.pk])] = true
	}
	for _, r := range rows {
		k := keyOf(r[t.pk])
		if seen[k] {
			throw("duplicate primary key: " + show(r[t.pk]))
		}
		seen[k] = true
	}
}

func (db *DB) exec(st Stmt) string {
	switch s := st.(type) {
	case *CreateStmt:
		return db.create(s)
	case *DropStmt:
		db.table(s.name)
		delete(db.tables, s.name)
		return "ok\n"
	case *InsertStmt:
		return db.insert(s)
	case *UpdateStmt:
		return db.update(s)
	case *DeleteStmt:
		return db.delete(s)
	case *SelectStmt:
		return db.selectQuery(s)
	}
	throw(syntaxMsg)
	return ""
}

func (db *DB) create(s *CreateStmt) string {
	if db.tables[s.name] != nil {
		throw("table " + s.name + " already exists")
	}
	seen := map[string]bool{}
	pk := -1
	npk := 0
	for i, c := range s.cols {
		if seen[c.name] {
			throw("duplicate column: " + c.name)
		}
		seen[c.name] = true
		if c.pk {
			npk++
			pk = i
		}
	}
	if npk > 1 {
		throw("multiple primary keys")
	}
	db.tables[s.name] = &Table{name: s.name, cols: s.cols, pk: pk}
	return "ok\n"
}

func (db *DB) insert(s *InsertStmt) string {
	t := db.table(s.table)
	var targets []int
	if s.hasCols {
		seen := map[string]bool{}
		for _, cn := range s.cols {
			idx := t.colIndex(cn)
			if idx < 0 {
				throw("no such column: " + cn)
			}
			if seen[cn] {
				throw("duplicate column: " + cn)
			}
			seen[cn] = true
			targets = append(targets, idx)
		}
	} else {
		for i := range t.cols {
			targets = append(targets, i)
		}
	}
	empty := &scope{}
	var newRows [][]Value
	for _, row := range s.rows {
		if len(row) != len(targets) {
			throw("wrong number of values")
		}
		full := make([]Value, len(t.cols))
		for i := range full {
			full[i] = nullV
		}
		for i, e := range row {
			resolve(e, &rctx{sc: empty})
			full[targets[i]] = eval(e, &ectx{})
		}
		checkRow(t, full)
		newRows = append(newRows, full)
	}
	checkPKDup(t, t.rows, newRows)
	t.rows = append(t.rows, newRows...)
	return fmt.Sprintf("inserted %d\n", len(newRows))
}

func (db *DB) update(s *UpdateStmt) string {
	t := db.table(s.table)
	targets := make([]int, len(s.sets))
	for i, st := range s.sets {
		idx := t.colIndex(st.col)
		if idx < 0 {
			throw("no such column: " + st.col)
		}
		targets[i] = idx
	}
	sc := t.tableScope()
	for _, st := range s.sets {
		resolve(st.e, &rctx{sc: sc})
	}
	if s.where != nil {
		resolve(s.where, &rctx{sc: sc})
	}
	newRows := make([][]Value, len(t.rows))
	count := 0
	for i, r := range t.rows {
		c := &ectx{row: r}
		if s.where != nil && !truth(eval(s.where, c)) {
			newRows[i] = r
			continue
		}
		count++
		vals := make([]Value, len(s.sets))
		for k, st := range s.sets {
			vals[k] = eval(st.e, c)
		}
		nr := make([]Value, len(r))
		copy(nr, r)
		for k := range s.sets {
			nr[targets[k]] = vals[k]
		}
		checkRow(t, nr)
		newRows[i] = nr
	}
	checkPKDup(t, nil, newRows)
	t.rows = newRows
	return fmt.Sprintf("updated %d\n", count)
}

func (db *DB) delete(s *DeleteStmt) string {
	t := db.table(s.table)
	if s.where != nil {
		resolve(s.where, &rctx{sc: t.tableScope()})
	}
	var keep [][]Value
	deleted := 0
	for _, r := range t.rows {
		if s.where == nil || truth(eval(s.where, &ectx{row: r})) {
			deleted++
			continue
		}
		keep = append(keep, r)
	}
	t.rows = keep
	return fmt.Sprintf("deleted %d\n", deleted)
}

// ---------------------------------------------------------------------------
// SELECT
// ---------------------------------------------------------------------------

type outItem struct {
	e    Expr
	name string
}

type ordKey struct {
	pos  int // output column index, or -1 for expression
	e    Expr
	desc bool
}

type outRow struct {
	vals []Value
	keys []Value
}

type group struct {
	rep  []Value
	rows [][]Value
	aggs []Value
}

func computeAgg(c *Call, rows [][]Value) Value {
	if c.star {
		return intV(int64(len(rows)))
	}
	var vals []Value
	seen := map[string]bool{}
	for _, r := range rows {
		v := eval(c.args[0], &ectx{row: r})
		if v.k == vNull {
			continue
		}
		if c.distinct {
			k := keyOf(v)
			if seen[k] {
				continue
			}
			seen[k] = true
		}
		vals = append(vals, v)
	}
	switch c.name {
	case "COUNT":
		return intV(int64(len(vals)))
	case "SUM":
		if len(vals) == 0 {
			return nullV
		}
		var sum int64
		for _, v := range vals {
			sum += needInt(v)
		}
		return intV(sum)
	default: // MIN, MAX
		if len(vals) == 0 {
			return nullV
		}
		best := vals[0]
		if best.k != vInt && best.k != vText {
			throw("type error")
		}
		for _, v := range vals[1:] {
			if v.k != best.k {
				throw("type error")
			}
			r := cmpOrder(v, best)
			if (c.name == "MIN" && r < 0) || (c.name == "MAX" && r > 0) {
				best = v
			}
		}
		return best
	}
}

func buildRows(s *SelectStmt, tabs []*Table) [][]Value {
	if s.from == nil {
		return [][]Value{{}}
	}
	var rows [][]Value
	rows = append(rows, tabs[0].rows...)
	for k, j := range s.joins {
		t := tabs[k+1]
		var next [][]Value
		for _, o := range rows {
			matched := false
			for _, in := range t.rows {
				comb := make([]Value, 0, len(o)+len(in))
				comb = append(comb, o...)
				comb = append(comb, in...)
				if truth(eval(j.on, &ectx{row: comb})) {
					next = append(next, comb)
					matched = true
				}
			}
			if !matched && j.left {
				comb := make([]Value, 0, len(o)+len(t.cols))
				comb = append(comb, o...)
				for range t.cols {
					comb = append(comb, nullV)
				}
				next = append(next, comb)
			}
		}
		rows = next
	}
	return rows
}

func (db *DB) selectQuery(s *SelectStmt) string {
	// 1. tables
	sc := &scope{}
	var tabs []*Table
	if s.from != nil {
		trs := []tref{*s.from}
		for _, j := range s.joins {
			trs = append(trs, j.t)
		}
		for _, tr := range trs {
			t := db.table(tr.table)
			for _, st := range sc.tabs {
				if st.alias == tr.alias {
					throw("duplicate alias: " + tr.alias)
				}
			}
			sc.add(tr.alias, t.cols)
			tabs = append(tabs, t)
		}
	}
	// 2. JOIN conditions (each sees the tables up to and including its own)
	for k, j := range s.joins {
		resolve(j.on, &rctx{sc: &scope{tabs: sc.tabs[:k+2]}})
	}
	// 3. stars and select items (expanded)
	var outs []outItem
	for _, it := range s.items {
		switch {
		case it.star:
			for _, t := range sc.tabs {
				for j, c := range t.cols {
					outs = append(outs, outItem{e: &ColRef{name: c.name, idx: t.off + j, pre: true}, name: c.name})
				}
			}
		case it.isTStar:
			found := false
			for _, t := range sc.tabs {
				if t.alias == it.tstar {
					found = true
					for j, c := range t.cols {
						outs = append(outs, outItem{e: &ColRef{name: c.name, idx: t.off + j, pre: true}, name: c.name})
					}
					break
				}
			}
			if !found {
				throw("no such table: " + it.tstar)
			}
		default:
			name := "?column?"
			if it.hasAlias {
				name = it.alias
			} else if cr, ok := it.e.(*ColRef); ok {
				name = cr.name
			}
			outs = append(outs, outItem{e: it.e, name: name})
		}
	}
	// 4. GROUP BY columns
	groupIdx := map[int]bool{}
	var groupCols []int
	for _, g := range s.groupBy {
		idx := sc.lookup(g.qual, g.name)
		if !groupIdx[idx] {
			groupCols = append(groupCols, idx)
		}
		groupIdx[idx] = true
	}
	// 5. WHERE
	if s.where != nil {
		resolve(s.where, &rctx{sc: sc})
	}
	aggregated := len(s.groupBy) > 0 || s.having != nil
	for _, o := range outs {
		if hasAgg(o.e) {
			aggregated = true
		}
	}
	for _, o := range s.orderBy {
		if hasAgg(o.e) {
			aggregated = true
		}
	}
	rc := &rctx{sc: sc, allowAgg: true, aggregated: aggregated, groupIdx: groupIdx}
	// 6. select items
	for _, o := range outs {
		resolve(o.e, rc)
	}
	// 7. HAVING
	if s.having != nil {
		resolve(s.having, rc)
	}
	// 8. ORDER BY
	var ords []ordKey
	for _, o := range s.orderBy {
		if lit, ok := o.e.(*Lit); ok && lit.v.k == vInt {
			if lit.v.i < 1 || lit.v.i > int64(len(outs)) {
				throw("bad ORDER BY position")
			}
			ords = append(ords, ordKey{pos: int(lit.v.i - 1), desc: o.desc})
			continue
		}
		if cr, ok := o.e.(*ColRef); ok && cr.qual == "" {
			found := -1
			for i, out := range outs {
				if out.name == cr.name {
					found = i
					break
				}
			}
			if found >= 0 {
				ords = append(ords, ordKey{pos: found, desc: o.desc})
				continue
			}
		}
		resolve(o.e, rc)
		ords = append(ords, ordKey{pos: -1, e: o.e, desc: o.desc})
	}

	// ---- execution ----
	rows := buildRows(s, tabs)
	if s.where != nil {
		var kept [][]Value
		for _, r := range rows {
			if truth(eval(s.where, &ectx{row: r})) {
				kept = append(kept, r)
			}
		}
		rows = kept
	}

	computeKeys := func(c *ectx, vals []Value) []Value {
		keys := make([]Value, len(ords))
		for i, k := range ords {
			if k.pos >= 0 {
				keys[i] = vals[k.pos]
			} else {
				keys[i] = eval(k.e, c)
			}
		}
		return keys
	}

	var outRows []outRow
	if !aggregated {
		for _, r := range rows {
			c := &ectx{row: r}
			vals := make([]Value, len(outs))
			for i, o := range outs {
				vals[i] = eval(o.e, c)
			}
			outRows = append(outRows, outRow{vals: vals, keys: computeKeys(c, vals)})
		}
	} else {
		var groups []*group
		if len(groupCols) == 0 {
			g := &group{}
			if len(rows) > 0 {
				g.rep = rows[0]
			}
			g.rows = rows
			groups = append(groups, g)
		} else {
			index := map[string]*group{}
			for _, r := range rows {
				kv := make([]Value, len(groupCols))
				for i, idx := range groupCols {
					kv[i] = r[idx]
				}
				k := rowKey(kv)
				g := index[k]
				if g == nil {
					g = &group{rep: r}
					index[k] = g
					groups = append(groups, g)
				}
				g.rows = append(g.rows, r)
			}
		}
		for _, g := range groups {
			g.aggs = make([]Value, len(rc.aggs))
			for i, a := range rc.aggs {
				g.aggs[i] = computeAgg(a, g.rows)
			}
		}
		var kept []*group
		for _, g := range groups {
			if s.having == nil || truth(eval(s.having, &ectx{row: g.rep, aggs: g.aggs})) {
				kept = append(kept, g)
			}
		}
		for _, g := range kept {
			c := &ectx{row: g.rep, aggs: g.aggs}
			vals := make([]Value, len(outs))
			for i, o := range outs {
				vals[i] = eval(o.e, c)
			}
			outRows = append(outRows, outRow{vals: vals, keys: computeKeys(c, vals)})
		}
	}

	if s.distinct {
		seen := map[string]bool{}
		var uniq []outRow
		for _, r := range outRows {
			k := rowKey(r.vals)
			if !seen[k] {
				seen[k] = true
				uniq = append(uniq, r)
			}
		}
		outRows = uniq
	}

	if len(ords) > 0 {
		sort.SliceStable(outRows, func(i, j int) bool {
			a, b := outRows[i].keys, outRows[j].keys
			for k := range ords {
				r := cmpOrder(a[k], b[k])
				if ords[k].desc {
					r = -r
				}
				if r != 0 {
					return r < 0
				}
			}
			return false
		})
	}

	n := int64(len(outRows))
	var start int64
	if s.hasOffset {
		start = s.offset
	}
	if start > n {
		start = n
	}
	end := n
	if s.hasLimit && s.limit < end-start {
		end = start + s.limit
	}
	outRows = outRows[start:end]

	var sb strings.Builder
	names := make([]string, len(outs))
	for i, o := range outs {
		names[i] = o.name
	}
	sb.WriteString(strings.Join(names, "|"))
	sb.WriteByte('\n')
	for _, r := range outRows {
		parts := make([]string, len(r.vals))
		for i, v := range r.vals {
			parts[i] = show(v)
		}
		sb.WriteString(strings.Join(parts, "|"))
		sb.WriteByte('\n')
	}
	fmt.Fprintf(&sb, "(%d rows)\n", len(outRows))
	return sb.String()
}

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------

func runStatement(db *DB, src string) (out string) {
	defer func() {
		if r := recover(); r != nil {
			if e, ok := r.(sqlErr); ok {
				out = "error: " + e.msg + "\n"
			} else {
				out = "error: internal error\n"
			}
		}
	}()
	toks := lex(src)
	if len(toks) == 1 {
		return ""
	}
	st := parseStatement(toks)
	return db.exec(st)
}

func main() {
	data, _ := io.ReadAll(os.Stdin)
	db := &DB{tables: map[string]*Table{}}
	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	for _, s := range splitStatements(string(data)) {
		w.WriteString(runStatement(db, s))
	}
}

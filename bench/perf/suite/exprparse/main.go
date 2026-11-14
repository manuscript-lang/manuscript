package main

import (
	"fmt"
	"strconv"
	"strings"
)

type Tok struct {
	num bool
	v   int
}

type Expr struct {
	op          int
	v           int
	left, right *Expr
}

type Parser struct {
	toks []Tok
	pos  int
}

func lcg(x int) int { return (x*1103515245 + 12345) % 2147483648 }

func gen(depth int, x *int, out *strings.Builder) {
	*x = lcg(*x)
	if depth == 0 || *x%5 == 0 {
		out.WriteString(strconv.Itoa(*x / 7 % 100))
		return
	}
	*x = lcg(*x)
	op := []string{"+", "-", "*", "%"}[*x/3%4]
	out.WriteByte('(')
	gen(depth-1, x, out)
	out.WriteString(" " + op + " ")
	gen(depth-1, x, out)
	out.WriteByte(')')
}

func tokenize(text string) []Tok {
	var toks []Tok
	i := 0
	for i < len(text) {
		c := text[i]
		if c >= '0' && c <= '9' {
			v := 0
			for i < len(text) && text[i] >= '0' && text[i] <= '9' {
				v = v*10 + int(text[i]-'0')
				i++
			}
			toks = append(toks, Tok{true, v})
		} else if c == ' ' {
			i++
		} else {
			toks = append(toks, Tok{false, int(c)})
			i++
		}
	}
	return toks
}

func (p *Parser) expr() *Expr {
	t := p.toks[p.pos]
	if t.num {
		p.pos++
		return &Expr{v: t.v}
	}
	p.pos++
	left := p.expr()
	op := 0
	if !p.toks[p.pos].num {
		op = p.toks[p.pos].v
	}
	p.pos++
	right := p.expr()
	p.pos++
	return &Expr{op: op, left: left, right: right}
}

func eval(e *Expr) int {
	if e.left == nil {
		return e.v
	}
	a := eval(e.left)
	b := eval(e.right)
	switch e.op {
	case '+':
		return (a + b) % 1000003
	case '-':
		return (a - b) % 1000003
	case '*':
		return a * b % 1000003
	}
	if b == 0 {
		return a
	}
	return a % b
}

func main() {
	x, total, tokens, chars := 3, 0, 0, 0
	for i := 0; i < 60000; i++ {
		var sb strings.Builder
		gen(9, &x, &sb)
		text := sb.String()
		chars += len(text)
		toks := tokenize(text)
		tokens += len(toks)
		p := &Parser{toks: toks}
		total = (total + eval(p.expr())) % 1000003
	}
	fmt.Printf("chars %d tokens %d total %d\n", chars, tokens, total)
}

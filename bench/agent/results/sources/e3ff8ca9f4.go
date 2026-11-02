package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
)

var errSyntax = errors.New("syntax")

// parser is a recursive-descent evaluator for the calculator grammar:
//
//	expr   := term (('+' | '-') term)*
//	term   := unary (('*' | '/') unary)*
//	unary  := '-' unary | primary
//	primary:= NUMBER | '(' expr ')'
//
// Evaluation happens during parsing. Syntax errors take priority over
// division by zero, so the parser records both and the caller decides.
type parser struct {
	src     string
	pos     int
	divZero bool
}

func isSpace(c byte) bool { return c == ' ' || c == '\t' || c == '\r' }

func (p *parser) skipSpace() {
	for p.pos < len(p.src) && isSpace(p.src[p.pos]) {
		p.pos++
	}
}

// peek returns the next significant byte, or 0 at end of input.
func (p *parser) peek() byte {
	p.skipSpace()
	if p.pos >= len(p.src) {
		return 0
	}
	return p.src[p.pos]
}

func (p *parser) expr() (int64, error) {
	v, err := p.term()
	if err != nil {
		return 0, err
	}
	for {
		switch p.peek() {
		case '+':
			p.pos++
			r, err := p.term()
			if err != nil {
				return 0, err
			}
			v += r
		case '-':
			p.pos++
			r, err := p.term()
			if err != nil {
				return 0, err
			}
			v -= r
		default:
			return v, nil
		}
	}
}

func (p *parser) term() (int64, error) {
	v, err := p.unary()
	if err != nil {
		return 0, err
	}
	for {
		switch p.peek() {
		case '*':
			p.pos++
			r, err := p.unary()
			if err != nil {
				return 0, err
			}
			v *= r
		case '/':
			p.pos++
			r, err := p.unary()
			if err != nil {
				return 0, err
			}
			if r == 0 {
				p.divZero = true
				v = 0
			} else {
				v /= r
			}
		default:
			return v, nil
		}
	}
}

func (p *parser) unary() (int64, error) {
	if p.peek() == '-' {
		p.pos++
		v, err := p.unary()
		if err != nil {
			return 0, err
		}
		return -v, nil
	}
	return p.primary()
}

func (p *parser) primary() (int64, error) {
	c := p.peek()
	switch {
	case c == '(':
		p.pos++
		v, err := p.expr()
		if err != nil {
			return 0, err
		}
		if p.peek() != ')' {
			return 0, errSyntax
		}
		p.pos++
		return v, nil
	case c >= '0' && c <= '9':
		start := p.pos
		for p.pos < len(p.src) && p.src[p.pos] >= '0' && p.src[p.pos] <= '9' {
			p.pos++
		}
		n, err := strconv.ParseInt(p.src[start:p.pos], 10, 64)
		if err != nil {
			return 0, errSyntax // literal out of int64 range
		}
		return n, nil
	default:
		// Covers end of input, dangling operators, ')' and unknown characters.
		return 0, errSyntax
	}
}

// evalLine returns the output text for one non-blank line.
func evalLine(line string) string {
	p := &parser{src: line}
	v, err := p.expr()
	if err == nil && p.peek() != 0 {
		err = errSyntax // trailing garbage such as ')' or two adjacent numbers
	}
	switch {
	case err != nil:
		return "error: syntax"
	case p.divZero:
		return "error: division by zero"
	default:
		return strconv.FormatInt(v, 10)
	}
}

func isBlank(s string) bool {
	for i := 0; i < len(s); i++ {
		if !isSpace(s[i]) {
			return false
		}
	}
	return true
}

func run(in io.Reader, out io.Writer) error {
	r := bufio.NewReaderSize(in, 1<<16)
	w := bufio.NewWriter(out)
	defer w.Flush()
	for {
		line, err := r.ReadString('\n')
		if len(line) > 0 {
			// Strip the line terminator (\n, and \r via isSpace handling).
			if line[len(line)-1] == '\n' {
				line = line[:len(line)-1]
			}
			if !isBlank(line) {
				fmt.Fprintln(w, evalLine(line))
			}
		}
		if err != nil {
			if err == io.EOF {
				return nil
			}
			return err
		}
	}
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

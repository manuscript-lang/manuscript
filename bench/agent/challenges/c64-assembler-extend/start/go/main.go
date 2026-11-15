package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
)

type asmErr struct {
	line int
	msg  string
}

type sym struct {
	isEqu bool
	val   int32
	text  string // equ expression
	state int    // 0 none,1 evaluating,2 done
	err   error
}

type operand struct {
	kind  int // 0 reg 1 imm 2 mem
	reg   int
	text  string
	base  int
	signs []int
	terms []string
}

type instr struct {
	op   string
	ops  []operand
	line int
	// resolved
	val  [2]int32
	base [2]int
}

type dataItem struct {
	line  int
	exprs []string // .word values or fill
	words []int32  // ascii
	kind  int      // 0 word 1 ascii 2 space
	count int
	start int
}

type perr struct{ msg string }

func (e perr) Error() string { return e.msg }

var syms = map[string]*sym{}

var regNames = map[string]int{"r0": 0, "r1": 1, "r2": 2, "r3": 3, "r4": 4, "r5": 5, "r6": 6, "r7": 7, "sp": 8, "bp": 9}

func isIdentStart(c byte) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}
func isDigit(c byte) bool { return c >= '0' && c <= '9' }
func isIdentChar(c byte) bool {
	return isIdentStart(c) || isDigit(c) || c == '.'
}
func isIdent(s string) bool {
	if s == "" || !isIdentStart(s[0]) {
		return false
	}
	for i := 1; i < len(s); i++ {
		if !isIdentChar(s[i]) {
			return false
		}
	}
	return true
}

func unesc(c byte) (byte, bool) {
	switch c {
	case 'n':
		return '\n', true
	case 't':
		return '\t', true
	case '0':
		return 0, true
	case '\\':
		return '\\', true
	case '\'':
		return '\'', true
	case '"':
		return '"', true
	}
	return 0, false
}

// skipQuoted: s[i] is a quote char q; return index just past closing, or -1
func skipQuoted(s string, i int) int {
	q := s[i]
	for j := i + 1; j < len(s); j++ {
		if s[j] == '\\' {
			j++
			continue
		}
		if s[j] == q {
			return j + 1
		}
	}
	return -1
}

func stripComment(s string) string {
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == ';' {
			return s[:i]
		}
		if c == '"' || c == '\'' {
			j := skipQuoted(s, i)
			if j < 0 {
				return s
			}
			i = j - 1
		}
	}
	return s
}

func splitOps(s string) []string {
	var res []string
	depth := 0
	start := 0
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch c {
		case '[':
			depth++
		case ']':
			if depth > 0 {
				depth--
			}
		case '\'', '"':
			j := skipQuoted(s, i)
			if j > 0 {
				i = j - 1
			}
		case ',':
			if depth == 0 {
				res = append(res, strings.TrimSpace(s[start:i]))
				start = i + 1
			}
		}
	}
	res = append(res, strings.TrimSpace(s[start:]))
	return res
}

// ---- expressions ----

type term struct {
	sign int32
	kind int // 0 number 1 symbol
	val  int32
	name string
}

func parseExpr(text string) ([]term, error) {
	s := strings.TrimSpace(text)
	bad := perr{"invalid expression '" + s + "'"}
	i := 0
	skip := func() {
		for i < len(s) && (s[i] == ' ' || s[i] == '\t') {
			i++
		}
	}
	var terms []term
	sign := int32(1)
	skip()
	if i < len(s) && (s[i] == '+' || s[i] == '-') {
		if s[i] == '-' {
			sign = -1
		}
		i++
	}
	for {
		skip()
		if i >= len(s) {
			return nil, bad
		}
		c := s[i]
		var t term
		t.sign = sign
		if c == '\'' {
			j := skipQuoted(s, i)
			if j < 0 {
				return nil, bad
			}
			body := s[i+1 : j-1]
			var v byte
			if len(body) == 1 && body[0] != '\\' && body[0] != '\'' {
				v = body[0]
			} else if len(body) == 2 && body[0] == '\\' {
				u, ok := unesc(body[1])
				if !ok {
					return nil, bad
				}
				v = u
			} else {
				return nil, bad
			}
			t.val = int32(v)
			i = j
		} else if isDigit(c) {
			j := i
			for j < len(s) && (isIdentChar(s[j]) && s[j] != '.') {
				j++
			}
			tok := s[i:j]
			i = j
			base := uint64(10)
			digits := tok
			if len(tok) > 1 && tok[0] == '0' && (tok[1] == 'x' || tok[1] == 'b') {
				if tok[1] == 'x' {
					base = 16
				} else {
					base = 2
				}
				digits = tok[2:]
			}
			if digits == "" {
				return nil, bad
			}
			var v uint64
			over := false
			for k := 0; k < len(digits); k++ {
				d := digits[k]
				var dv uint64
				switch {
				case d >= '0' && d <= '9':
					dv = uint64(d - '0')
				case d >= 'a' && d <= 'f':
					dv = uint64(d-'a') + 10
				case d >= 'A' && d <= 'F':
					dv = uint64(d-'A') + 10
				default:
					return nil, bad
				}
				if dv >= base {
					return nil, bad
				}
				if !over {
					v = v*base + dv
					if v > 4294967295 {
						over = true
					}
				}
			}
			if over {
				return nil, perr{"immediate out of range"}
			}
			t.val = int32(uint32(v))
		} else if isIdentStart(c) {
			j := i
			for j < len(s) && isIdentChar(s[j]) {
				j++
			}
			t.kind = 1
			t.name = s[i:j]
			i = j
		} else {
			return nil, bad
		}
		terms = append(terms, t)
		skip()
		if i >= len(s) {
			return terms, nil
		}
		if s[i] == '+' {
			sign = 1
		} else if s[i] == '-' {
			sign = -1
		} else {
			return nil, bad
		}
		i++
	}
}

func lookup(name string) (int32, error) {
	sy, ok := syms[name]
	if !ok {
		return 0, perr{"undefined symbol '" + name + "'"}
	}
	if !sy.isEqu {
		return sy.val, nil
	}
	if sy.state == 1 {
		return 0, perr{"circular definition of '" + name + "'"}
	}
	if sy.state == 2 {
		return sy.val, sy.err
	}
	sy.state = 1
	v, err := evalExpr(sy.text)
	sy.state = 2
	if err != nil {
		// don't cache circular-through errors incorrectly; cache anyway
		sy.err = err
		return 0, err
	}
	sy.val = v
	return v, nil
}

func evalExpr(text string) (int32, error) {
	terms, err := parseExpr(text)
	if err != nil {
		return 0, err
	}
	var sum int32
	for _, t := range terms {
		v := t.val
		if t.kind == 1 {
			v, err = lookup(t.name)
			if err != nil {
				return 0, err
			}
		}
		sum += t.sign * v
	}
	return sum, nil
}

// ---- operand parsing ----

func parseOperand(s string) (operand, bool) {
	o := operand{text: s, base: -1}
	if s == "" {
		return o, false
	}
	if r, ok := regNames[s]; ok {
		o.kind = 0
		o.reg = r
		return o, true
	}
	if s[0] != '[' {
		o.kind = 1
		return o, true
	}
	if s[len(s)-1] != ']' || len(s) < 2 {
		return o, false
	}
	in := s[1 : len(s)-1]
	var segs []string
	var ops []byte
	start := 0
	for i := 0; i < len(in); i++ {
		c := in[i]
		if c == '\'' {
			j := skipQuoted(in, i)
			if j > 0 {
				i = j - 1
			}
		} else if c == '+' || c == '-' {
			segs = append(segs, strings.TrimSpace(in[start:i]))
			ops = append(ops, c)
			start = i + 1
		}
	}
	segs = append(segs, strings.TrimSpace(in[start:]))
	type tm struct {
		sign int
		text string
	}
	var tms []tm
	if segs[0] == "" {
		if len(ops) == 0 {
			return o, false
		}
		segs = segs[1:]
		// first op applies to segs[0]
	} else {
		tms = append(tms, tm{1, segs[0]})
		segs = segs[1:]
	}
	for k, sg := range segs {
		if sg == "" {
			return o, false
		}
		sign := 1
		if ops[k] == '-' {
			sign = -1
		}
		tms = append(tms, tm{sign, sg})
	}
	o.kind = 2
	for _, t := range tms {
		if r, ok := regNames[t.text]; ok {
			if t.sign < 0 || o.base >= 0 {
				return o, false
			}
			o.base = r
			continue
		}
		o.signs = append(o.signs, t.sign)
		o.terms = append(o.terms, t.text)
	}
	return o, true
}

type spec struct {
	n     int
	allow [][]int // per position allowed kinds bitmask
}

const (
	R = 1
	I = 2
	M = 4
)

var specs = map[string]spec{}

func init() {
	for _, m := range []string{"add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar", "cmp"} {
		specs[m] = spec{2, [][]int{{R}, {R | I | M}}}
	}
	for _, m := range []string{"neg", "not", "inc", "dec", "pop", "in"} {
		specs[m] = spec{1, [][]int{{R}}}
	}
	for _, m := range []string{"jmp", "je", "jne", "jz", "jnz", "jl", "jle", "jg", "jge", "call"} {
		specs[m] = spec{1, [][]int{{I}}}
	}
	for _, m := range []string{"push", "out", "outc"} {
		specs[m] = spec{1, [][]int{{R | I | M}}}
	}
	specs["lea"] = spec{2, [][]int{{R}, {M}}}
	specs["mov"] = spec{2, [][]int{{R | M}, {R | I | M}}}
	specs["ret"] = spec{0, nil}
	specs["halt"] = spec{0, nil}
	specs["nop"] = spec{0, nil}
}

func kindBit(k int) int { return 1 << uint(k) }

func fail(line int, msg string) {
	fmt.Printf("asm error line %d: %s\n", line, msg)
	os.Exit(0)
}

func parseString(s string) ([]int32, bool) {
	if len(s) < 2 || s[0] != '"' || s[len(s)-1] != '"' {
		return nil, false
	}
	b := s[1 : len(s)-1]
	var res []int32
	for i := 0; i < len(b); i++ {
		c := b[i]
		if c == '"' {
			return nil, false
		}
		if c == '\\' {
			if i+1 >= len(b) {
				return nil, false
			}
			u, ok := unesc(b[i+1])
			if !ok {
				return nil, false
			}
			res = append(res, int32(u))
			i++
			continue
		}
		res = append(res, int32(c))
	}
	return res, true
}

type item struct {
	line int
	ins  *instr
	data *dataItem
}

func main() {
	raw, _ := io.ReadAll(os.Stdin)
	text := string(raw)
	lines := strings.Split(text, "\n")
	var srcLines []string
	var inputPart strings.Builder
	found := false
	for i, l := range lines {
		l = strings.TrimSuffix(l, "\r")
		if !found && l == "====" {
			found = true
			inputPart.WriteString(strings.Join(lines[i+1:], "\n"))
			break
		}
		srcLines = append(srcLines, l)
	}

	var items []item
	var code []*instr
	var memInit []int32
	budget := 100000
	inData := false
	mainIdx := -1

	for ln, l := range srcLines {
		line := ln + 1
		s := strings.TrimSpace(stripComment(l))
		for {
			j := 0
			if len(s) > 0 && isIdentStart(s[0]) {
				for j < len(s) && isIdentChar(s[j]) {
					j++
				}
			}
			if j == 0 || j >= len(s) || s[j] != ':' {
				break
			}
			name := s[:j]
			if _, ok := regNames[name]; ok {
				fail(line, "reserved name '"+name+"'")
			}
			if _, ok := syms[name]; ok {
				fail(line, "duplicate symbol '"+name+"'")
			}
			if inData {
				syms[name] = &sym{val: int32(len(memInit))}
			} else {
				syms[name] = &sym{val: int32(len(code))}
				if name == "main" {
					mainIdx = len(code)
				}
			}
			s = strings.TrimSpace(s[j+1:])
		}
		if s == "" {
			continue
		}
		k := 0
		for k < len(s) && s[k] != ' ' && s[k] != '\t' {
			k++
		}
		word := s[:k]
		rest := strings.TrimSpace(s[k:])
		if word[0] == '.' {
			switch word {
			case ".text", ".data":
				if rest != "" {
					fail(line, "invalid operand '"+rest+"'")
				}
				inData = word == ".data"
			case ".budget":
				n := 0
				ok := rest != ""
				for i := 0; i < len(rest) && ok; i++ {
					if !isDigit(rest[i]) {
						ok = false
					} else if n <= 10000000 {
						n = n*10 + int(rest[i]-'0')
					}
				}
				if !ok || n < 1 || n > 10000000 {
					fail(line, "invalid operand '"+rest+"'")
				}
				budget = n
			case ".equ":
				ops := splitOps(rest)
				if len(ops) != 2 {
					fail(line, "wrong number of operands for '.equ'")
				}
				if !isIdent(ops[0]) {
					fail(line, "invalid operand '"+ops[0]+"'")
				}
				if _, ok := regNames[ops[0]]; ok {
					fail(line, "reserved name '"+ops[0]+"'")
				}
				if _, ok := syms[ops[0]]; ok {
					fail(line, "duplicate symbol '"+ops[0]+"'")
				}
				syms[ops[0]] = &sym{isEqu: true, text: ops[1]}
			case ".word", ".ascii", ".asciz", ".space":
				if !inData {
					fail(line, "data directive in text section")
				}
				d := &dataItem{line: line, start: len(memInit)}
				switch word {
				case ".word":
					if rest == "" {
						fail(line, "wrong number of operands for '.word'")
					}
					d.kind = 0
					d.exprs = splitOps(rest)
					d.count = len(d.exprs)
				case ".ascii", ".asciz":
					w, ok := parseString(rest)
					if !ok {
						fail(line, "invalid string")
					}
					if word == ".asciz" {
						w = append(w, 0)
					}
					d.kind = 1
					d.words = w
					d.count = len(w)
				case ".space":
					ops := splitOps(rest)
					if rest == "" || len(ops) > 2 {
						fail(line, "wrong number of operands for '.space'")
					}
					n, err := evalExpr(ops[0])
					if err != nil {
						fail(line, err.Error())
					}
					if n < 0 {
						fail(line, "invalid operand '"+ops[0]+"'")
					}
					d.kind = 2
					d.count = int(n)
					if len(ops) == 2 {
						d.exprs = []string{ops[1]}
					}
				}
				if len(memInit)+d.count > 4096 {
					fail(line, "data section too large")
				}
				memInit = append(memInit, make([]int32, d.count)...)
				items = append(items, item{line: line, data: d})
			default:
				fail(line, "unknown directive '"+word+"'")
			}
			continue
		}
		if inData {
			fail(line, "instruction in data section")
		}
		sp, ok := specs[word]
		if !ok {
			fail(line, "unknown mnemonic '"+word+"'")
		}
		var ops []operand
		if rest != "" {
			for _, t := range splitOps(rest) {
				o, ok := parseOperand(t)
				if !ok {
					fail(line, "invalid operand '"+t+"'")
				}
				ops = append(ops, o)
			}
		}
		if len(ops) != sp.n {
			fail(line, "wrong number of operands for '"+word+"'")
		}
		for i, o := range ops {
			okk := false
			for _, a := range sp.allow[i] {
				if a&kindBit(o.kind) != 0 {
					okk = true
				}
			}
			if !okk {
				fail(line, "invalid operands for '"+word+"'")
			}
		}
		if word == "mov" && ops[0].kind == 2 && ops[1].kind == 2 {
			fail(line, "invalid operands for 'mov'")
		}
		in := &instr{op: word, ops: ops, line: line}
		code = append(code, in)
		items = append(items, item{line: line, ins: in})
	}

	// pass 2
	n := len(code)
	for _, it := range items {
		if it.data != nil {
			d := it.data
			switch d.kind {
			case 0:
				for i, e := range d.exprs {
					v, err := evalExpr(e)
					if err != nil {
						fail(it.line, err.Error())
					}
					memInit[d.start+i] = v
				}
			case 1:
				copy(memInit[d.start:], d.words)
			case 2:
				var f int32
				if len(d.exprs) == 1 {
					v, err := evalExpr(d.exprs[0])
					if err != nil {
						fail(it.line, err.Error())
					}
					f = v
				}
				for i := 0; i < d.count; i++ {
					memInit[d.start+i] = f
				}
			}
			continue
		}
		in := it.ins
		for i, o := range in.ops {
			in.base[i] = -1
			switch o.kind {
			case 1:
				v, err := evalExpr(o.text)
				if err != nil {
					fail(it.line, err.Error())
				}
				in.val[i] = v
				if i == 0 && sp1(in.op) {
					if v < 0 || int(v) >= n {
						fail(it.line, "invalid jump target")
					}
				}
			case 2:
				var sum int32
				for k, t := range o.terms {
					v, err := evalExpr(t)
					if err != nil {
						fail(it.line, err.Error())
					}
					sum += int32(o.signs[k]) * v
				}
				in.val[i] = sum
				in.base[i] = o.base
			}
		}
	}

	// input
	var inputs []int32
	for _, tok := range strings.Fields(inputPart.String()) {
		neg := false
		d := tok
		if d[0] == '-' {
			neg = true
			d = d[1:]
		}
		if d == "" {
			continue
		}
		ok := true
		var v uint32
		for i := 0; i < len(d); i++ {
			if !isDigit(d[i]) {
				ok = false
				break
			}
			v = v*10 + uint32(d[i]-'0')
		}
		if !ok {
			continue
		}
		x := int32(v)
		if neg {
			x = -x
		}
		inputs = append(inputs, x)
	}

	// run
	var reg [10]int32
	reg[8] = 4096
	var mem [4096]int32
	copy(mem[:], memInit)
	var Z, L bool
	pc := 0
	if mainIdx >= 0 {
		pc = mainIdx
	}
	steps := 0
	var out []byte
	trap := ""
	halted := false
	inp := 0

	type trapT struct{ msg string }
	// helpers returning ok
	addr := func(in *instr, i int) int32 {
		a := in.val[i]
		if in.base[i] >= 0 {
			a += reg[in.base[i]]
		}
		return a
	}
	var tmsg string
	rd := func(a int32) (int32, bool) {
		if a < 0 || a >= 4096 {
			tmsg = fmt.Sprintf("memory access out of range: %d", a)
			return 0, false
		}
		return mem[a], true
	}
	wr := func(a int32, v int32) bool {
		if a < 0 || a >= 4096 {
			tmsg = fmt.Sprintf("memory access out of range: %d", a)
			return false
		}
		mem[a] = v
		return true
	}
	get := func(in *instr, i int) (int32, bool) {
		o := in.ops[i]
		switch o.kind {
		case 0:
			return reg[o.reg], true
		case 1:
			return in.val[i], true
		}
		return rd(addr(in, i))
	}

	var badLine int
	for {
		if pc < 0 || pc >= n {
			trap = "pc out of range"
			badLine = -1
			break
		}
		in := code[pc]
		if steps == budget {
			trap = "budget exceeded"
			break
		}
		next := pc + 1
		okx := true
		switch in.op {
		case "nop":
		case "halt":
			halted = true
		case "mov":
			v, ok := get(in, 1)
			if !ok {
				okx = false
				break
			}
			if in.ops[0].kind == 0 {
				reg[in.ops[0].reg] = v
			} else {
				okx = wr(addr(in, 0), v)
			}
		case "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar", "cmp":
			v, ok := get(in, 1)
			if !ok {
				okx = false
				break
			}
			d := reg[in.ops[0].reg]
			var r int32
			switch in.op {
			case "add":
				r = d + v
			case "sub":
				r = d - v
			case "mul":
				r = d * v
			case "div", "mod":
				if v == 0 {
					tmsg = "division by zero"
					okx = false
				} else if in.op == "div" {
					r = d / v
				} else {
					r = d % v
				}
			case "and":
				r = d & v
			case "or":
				r = d | v
			case "xor":
				r = d ^ v
			case "shl":
				r = int32(uint32(d) << uint(v&31))
			case "shr":
				r = int32(uint32(d) >> uint(v&31))
			case "sar":
				r = d >> uint(v&31)
			case "cmp":
				Z = d == v
				L = d < v
			}
			if okx && in.op != "cmp" {
				reg[in.ops[0].reg] = r
			}
		case "neg":
			reg[in.ops[0].reg] = -reg[in.ops[0].reg]
		case "not":
			reg[in.ops[0].reg] = ^reg[in.ops[0].reg]
		case "inc":
			reg[in.ops[0].reg]++
		case "dec":
			reg[in.ops[0].reg]--
		case "lea":
			reg[in.ops[0].reg] = addr(in, 1)
		case "push":
			v, ok := get(in, 0)
			if !ok {
				okx = false
				break
			}
			if reg[8] <= 0 {
				tmsg = "stack overflow"
				okx = false
				break
			}
			reg[8]--
			okx = wr(reg[8], v)
		case "pop":
			if reg[8] >= 4096 {
				tmsg = "stack underflow"
				okx = false
				break
			}
			v, ok := rd(reg[8])
			if !ok {
				okx = false
				break
			}
			reg[8]++
			reg[in.ops[0].reg] = v
		case "jmp", "je", "jz", "jne", "jnz", "jl", "jle", "jg", "jge":
			c := true
			switch in.op {
			case "je", "jz":
				c = Z
			case "jne", "jnz":
				c = !Z
			case "jl":
				c = L
			case "jle":
				c = L || Z
			case "jg":
				c = !L && !Z
			case "jge":
				c = !L
			}
			if c {
				next = int(in.val[0])
			}
		case "call":
			if reg[8] <= 0 {
				tmsg = "stack overflow"
				okx = false
				break
			}
			reg[8]--
			if !wr(reg[8], int32(pc+1)) {
				okx = false
				break
			}
			next = int(in.val[0])
		case "ret":
			if reg[8] >= 4096 {
				tmsg = "stack underflow"
				okx = false
				break
			}
			v, ok := rd(reg[8])
			if !ok {
				okx = false
				break
			}
			reg[8]++
			next = int(v)
		case "in":
			if inp >= len(inputs) {
				tmsg = "input exhausted"
				okx = false
				break
			}
			reg[in.ops[0].reg] = inputs[inp]
			inp++
		case "out":
			v, ok := get(in, 0)
			if !ok {
				okx = false
				break
			}
			out = append(out, []byte(fmt.Sprintf("%d\n", v))...)
		case "outc":
			v, ok := get(in, 0)
			if !ok {
				okx = false
				break
			}
			if v < 0 || v > 127 {
				tmsg = "invalid character"
				okx = false
				break
			}
			out = append(out, byte(v))
		}
		if !okx {
			trap = tmsg
			break
		}
		steps++
		if halted {
			break
		}
		pc = next
	}

	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	w.Write(out)
	if len(out) > 0 && out[len(out)-1] != '\n' {
		w.WriteString("\n")
	}
	if trap == "" {
		fmt.Fprintf(w, "-- halted after %d steps\n", steps)
	} else {
		ls := "-"
		if badLine != -1 {
			ls = fmt.Sprint(code[pc].line)
		}
		fmt.Fprintf(w, "-- trap: %s (pc=%d line=%s) after %d steps\n", trap, pc, ls, steps)
	}
	fmt.Fprintf(w, "regs: r0=%d r1=%d r2=%d r3=%d r4=%d r5=%d r6=%d r7=%d sp=%d bp=%d\n", reg[0], reg[1], reg[2], reg[3], reg[4], reg[5], reg[6], reg[7], reg[8], reg[9])
	z, l := 0, 0
	if Z {
		z = 1
	}
	if L {
		l = 1
	}
	fmt.Fprintf(w, "flags: Z=%d L=%d\n", z, l)
}

func sp1(op string) bool {
	switch op {
	case "jmp", "je", "jne", "jz", "jnz", "jl", "jle", "jg", "jge", "call":
		return true
	}
	return false
}

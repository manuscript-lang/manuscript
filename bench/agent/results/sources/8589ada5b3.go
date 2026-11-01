package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

const (
	memSize   = 4096
	maxBudget = 10000000
	defBudget = 100000
	regSP     = 8
	regBP     = 9
)

type asmError struct {
	line int
	msg  string
}

type trapError string

// ---------------------------------------------------------------- lexing helpers

func isDigit(c byte) bool      { return c >= '0' && c <= '9' }
func isIdentStart(c byte) bool { return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') }
func isWordChar(c byte) bool   { return isIdentStart(c) || isDigit(c) || c == '.' }

func isIdent(s string) bool {
	if s == "" || !isIdentStart(s[0]) {
		return false
	}
	for i := 1; i < len(s); i++ {
		if !isWordChar(s[i]) {
			return false
		}
	}
	return true
}

func allDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if !isDigit(s[i]) {
			return false
		}
	}
	return true
}

func regIndex(s string) (int, bool) {
	switch s {
	case "sp":
		return regSP, true
	case "bp":
		return regBP, true
	}
	if len(s) == 2 && s[0] == 'r' && s[1] >= '0' && s[1] <= '7' {
		return int(s[1] - '0'), true
	}
	return 0, false
}

func escapeVal(c byte) (byte, bool) {
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

// stripComment removes a ';' comment that lies outside string and char literals.
func stripComment(s string) string {
	inStr, inChar := false, false
	for i := 0; i < len(s); i++ {
		c := s[i]
		if inStr || inChar {
			if c == '\\' {
				i++
			} else if inStr && c == '"' {
				inStr = false
			} else if inChar && c == '\'' {
				inChar = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
		case '\'':
			inChar = true
		case ';':
			return s[:i]
		}
	}
	return s
}

func splitWord(s string) (string, string) {
	i := strings.IndexAny(s, " \t")
	if i < 0 {
		return s, ""
	}
	return s[:i], s[i:]
}

// parseLabel recognises a leading "name:" and returns the name and the rest.
func parseLabel(s string) (string, string, bool) {
	if s == "" || !isIdentStart(s[0]) {
		return "", "", false
	}
	i := 1
	for i < len(s) && isWordChar(s[i]) {
		i++
	}
	if i < len(s) && s[i] == ':' {
		return s[:i], s[i+1:], true
	}
	return "", "", false
}

// splitOperands splits at commas outside brackets and char literals.
// An empty text yields no operands; empty pieces are kept.
func splitOperands(s string) []string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	var out []string
	depth := 0
	inChar := false
	start := 0
	for i := 0; i < len(s); i++ {
		c := s[i]
		if inChar {
			if c == '\\' {
				i++
			} else if c == '\'' {
				inChar = false
			}
			continue
		}
		switch c {
		case '\'':
			inChar = true
		case '[':
			depth++
		case ']':
			if depth > 0 {
				depth--
			}
		case ',':
			if depth == 0 {
				out = append(out, strings.TrimSpace(s[start:i]))
				start = i + 1
			}
		}
	}
	return append(out, strings.TrimSpace(s[start:]))
}

type memTerm struct {
	neg   bool
	isReg bool
	reg   int
	text  string
}

// splitMem validates a memory operand "[...]" and splits it into signed terms.
func splitMem(t string) ([]memTerm, bool) {
	end := -1
	inChar := false
	for i := 1; i < len(t); i++ {
		c := t[i]
		if inChar {
			if c == '\\' {
				i++
			} else if c == '\'' {
				inChar = false
			}
			continue
		}
		if c == '\'' {
			inChar = true
		} else if c == ']' {
			end = i
			break
		}
	}
	if end < 0 || end != len(t)-1 {
		return nil, false
	}
	content := t[1:end]

	var terms []memTerm
	ok := true
	hasReg := false
	add := func(neg bool, raw string) {
		txt := strings.TrimSpace(raw)
		if txt == "" || strings.ContainsAny(txt, ",[]") {
			ok = false
			return
		}
		if r, isR := regIndex(txt); isR {
			if neg || hasReg {
				ok = false
				return
			}
			hasReg = true
			terms = append(terms, memTerm{isReg: true, reg: r, text: txt})
			return
		}
		terms = append(terms, memTerm{neg: neg, text: txt})
	}

	neg := false
	start := 0
	if len(content) > 0 && (content[0] == '+' || content[0] == '-') {
		neg = content[0] == '-'
		start = 1
	}
	inChar = false
	for k := start; k <= len(content); k++ {
		if k == len(content) {
			add(neg, content[start:])
			break
		}
		c := content[k]
		if inChar {
			if c == '\\' {
				k++
			} else if c == '\'' {
				inChar = false
			}
			continue
		}
		if c == '\'' {
			inChar = true
		} else if c == '+' || c == '-' {
			add(neg, content[start:k])
			neg = c == '-'
			start = k + 1
		}
	}
	if !ok {
		return nil, false
	}
	return terms, true
}

// parseString decodes a double-quoted string literal used by .ascii/.asciz.
func parseString(t string) ([]byte, bool) {
	if len(t) < 2 || t[0] != '"' || t[len(t)-1] != '"' {
		return nil, false
	}
	inner := t[1 : len(t)-1]
	var out []byte
	for i := 0; i < len(inner); i++ {
		c := inner[i]
		if c == '"' {
			return nil, false
		}
		if c == '\\' {
			if i+1 >= len(inner) {
				return nil, false
			}
			v, ok := escapeVal(inner[i+1])
			if !ok {
				return nil, false
			}
			out = append(out, v)
			i++
			continue
		}
		out = append(out, c)
	}
	return out, true
}

// ---------------------------------------------------------------- opcodes

const (
	opMov = iota
	opAdd
	opSub
	opMul
	opDiv
	opMod
	opAnd
	opOr
	opXor
	opShl
	opShr
	opSar
	opCmp
	opNeg
	opNot
	opInc
	opDec
	opLea
	opPush
	opPop
	opJmp
	opJe
	opJne
	opJl
	opJle
	opJg
	opJge
	opCall
	opRet
	opIn
	opOut
	opOutc
	opHalt
	opNop
)

type opInfo struct {
	op    int
	nargs int
	sigs  []string // allowed operand class signatures (R, I, M)
}

func (i opInfo) allows(classes []byte) bool {
	sig := string(classes)
	for _, s := range i.sigs {
		if s == sig {
			return true
		}
	}
	return false
}

var rmi = []string{"RR", "RI", "RM"}
var rim = []string{"R", "I", "M"}

var opTable = map[string]opInfo{
	"mov":  {opMov, 2, []string{"RR", "RI", "RM", "MR", "MI"}},
	"add":  {opAdd, 2, rmi},
	"sub":  {opSub, 2, rmi},
	"mul":  {opMul, 2, rmi},
	"div":  {opDiv, 2, rmi},
	"mod":  {opMod, 2, rmi},
	"and":  {opAnd, 2, rmi},
	"or":   {opOr, 2, rmi},
	"xor":  {opXor, 2, rmi},
	"shl":  {opShl, 2, rmi},
	"shr":  {opShr, 2, rmi},
	"sar":  {opSar, 2, rmi},
	"cmp":  {opCmp, 2, rmi},
	"neg":  {opNeg, 1, []string{"R"}},
	"not":  {opNot, 1, []string{"R"}},
	"inc":  {opInc, 1, []string{"R"}},
	"dec":  {opDec, 1, []string{"R"}},
	"lea":  {opLea, 2, []string{"RM"}},
	"push": {opPush, 1, rim},
	"pop":  {opPop, 1, []string{"R"}},
	"jmp":  {opJmp, 1, []string{"I"}},
	"je":   {opJe, 1, []string{"I"}},
	"jz":   {opJe, 1, []string{"I"}},
	"jne":  {opJne, 1, []string{"I"}},
	"jnz":  {opJne, 1, []string{"I"}},
	"jl":   {opJl, 1, []string{"I"}},
	"jle":  {opJle, 1, []string{"I"}},
	"jg":   {opJg, 1, []string{"I"}},
	"jge":  {opJge, 1, []string{"I"}},
	"call": {opCall, 1, []string{"I"}},
	"ret":  {opRet, 0, []string{""}},
	"in":   {opIn, 1, []string{"R"}},
	"out":  {opOut, 1, rim},
	"outc": {opOutc, 1, rim},
	"halt": {opHalt, 0, []string{""}},
	"nop":  {opNop, 0, []string{""}},
}

// ---------------------------------------------------------------- assembler

type symbol struct {
	isEqu  bool
	inText bool
	state  int // .equ: 0 unevaluated, 1 in progress, 2 done
	val    uint32
	expr   string
}

type operand struct {
	cls byte   // 'R', 'I' or 'M'
	reg int    // register index (R), base register or -1 (M)
	val uint32 // immediate value (I) or displacement (M)
}

type instr struct {
	op      int
	name    string
	line    int
	raw     []string
	classes []byte
	ops     []operand
}

type job struct {
	line int
	fn   func()
}

type assembler struct {
	syms   map[string]*symbol
	line   int
	inText bool
	code   []instr
	data   [memSize]uint32
	dc     int
	budget int
	jobs   []job
}

type program struct {
	code   []instr
	data   [memSize]uint32
	budget int
	start  int
}

func (a *assembler) fail(msg string) {
	panic(asmError{a.line, msg})
}

func (a *assembler) addJob(fn func()) {
	a.jobs = append(a.jobs, job{a.line, fn})
}

func (a *assembler) checkNewName(name string) {
	if _, isReg := regIndex(name); isReg {
		a.fail("reserved name '" + name + "'")
	}
	if _, dup := a.syms[name]; dup {
		a.fail("duplicate symbol '" + name + "'")
	}
}

func (a *assembler) reserve(n int) int {
	if a.dc+n > memSize {
		a.fail("data section too large")
	}
	addr := a.dc
	a.dc += n
	return addr
}

func (a *assembler) defineLabel(name string) {
	a.checkNewName(name)
	v := a.dc
	if a.inText {
		v = len(a.code)
	}
	a.syms[name] = &symbol{inText: a.inText, val: uint32(v)}
}

func (a *assembler) evalSym(name string) uint32 {
	s, ok := a.syms[name]
	if !ok {
		a.fail("undefined symbol '" + name + "'")
	}
	if !s.isEqu {
		return s.val
	}
	switch s.state {
	case 2:
		return s.val
	case 1:
		a.fail("circular definition of '" + name + "'")
	}
	s.state = 1
	v := a.evalExpr(s.expr)
	s.val = v
	s.state = 2
	return v
}

func (a *assembler) numberValue(tok string) uint32 {
	base := uint64(10)
	digits := tok
	if strings.HasPrefix(tok, "0x") {
		base, digits = 16, tok[2:]
	} else if strings.HasPrefix(tok, "0b") {
		base, digits = 2, tok[2:]
	}
	if digits == "" {
		a.fail("invalid expression '" + tok + "'")
	}
	var v uint64
	over := false
	for i := 0; i < len(digits); i++ {
		c := digits[i]
		var d uint64
		switch {
		case c >= '0' && c <= '9':
			d = uint64(c - '0')
		case c >= 'a' && c <= 'f':
			d = uint64(c-'a') + 10
		case c >= 'A' && c <= 'F':
			d = uint64(c-'A') + 10
		default:
			d = 99
		}
		if d >= base {
			a.fail("invalid expression '" + tok + "'")
		}
		if !over {
			v = v*base + d
			if v > 0xFFFFFFFF {
				over = true
			}
		}
	}
	if over {
		a.fail("immediate out of range")
	}
	return uint32(v)
}

// evalExpr evaluates an immediate expression with 32-bit wraparound.
func (a *assembler) evalExpr(s string) uint32 {
	t := strings.TrimSpace(s)
	n := len(t)
	i := 0
	skip := func() {
		for i < n && (t[i] == ' ' || t[i] == '\t') {
			i++
		}
	}
	bad := func() {
		a.fail("invalid expression '" + t + "'")
	}
	term := func() uint32 {
		skip()
		if i >= n {
			bad()
		}
		c := t[i]
		switch {
		case c == '\'':
			i++
			if i >= n || t[i] == '\'' {
				bad()
			}
			var v byte
			if t[i] == '\\' {
				if i+1 >= n {
					bad()
				}
				ev, ok := escapeVal(t[i+1])
				if !ok {
					bad()
				}
				v = ev
				i += 2
			} else {
				v = t[i]
				i++
			}
			if i >= n || t[i] != '\'' {
				bad()
			}
			i++
			return uint32(v)
		case isDigit(c):
			j := i
			for j < n && isWordChar(t[j]) {
				j++
			}
			tok := t[i:j]
			i = j
			return a.numberValue(tok)
		case isIdentStart(c):
			j := i
			for j < n && isWordChar(t[j]) {
				j++
			}
			name := t[i:j]
			i = j
			return a.evalSym(name)
		}
		bad()
		return 0
	}

	skip()
	neg := false
	if i < n && (t[i] == '+' || t[i] == '-') {
		neg = t[i] == '-'
		i++
	}
	acc := term()
	if neg {
		acc = -acc
	}
	for {
		skip()
		if i >= n {
			break
		}
		op := t[i]
		if op != '+' && op != '-' {
			bad()
		}
		i++
		v := term()
		if op == '+' {
			acc += v
		} else {
			acc -= v
		}
	}
	return acc
}

func parseBudget(s string) (int, bool) {
	if !allDigits(s) {
		return 0, false
	}
	n, err := strconv.Atoi(s)
	if err != nil || n < 1 || n > maxBudget {
		return 0, false
	}
	return n, true
}

func (a *assembler) directive(word, rest string) {
	switch word {
	case ".text", ".data":
		if rest != "" {
			a.fail("invalid operand '" + rest + "'")
		}
		a.inText = word == ".text"

	case ".equ":
		ops := splitOperands(rest)
		if len(ops) != 2 {
			a.fail("wrong number of operands for '.equ'")
		}
		if !isIdent(ops[0]) {
			a.fail("invalid operand '" + ops[0] + "'")
		}
		a.checkNewName(ops[0])
		a.syms[ops[0]] = &symbol{isEqu: true, expr: ops[1]}

	case ".budget":
		n, ok := parseBudget(rest)
		if !ok {
			a.fail("invalid operand '" + rest + "'")
		}
		a.budget = n

	case ".word":
		if a.inText {
			a.fail("data directive in text section")
		}
		ops := splitOperands(rest)
		if len(ops) == 0 {
			a.fail("wrong number of operands for '.word'")
		}
		addr := a.reserve(len(ops))
		a.addJob(func() {
			for i, t := range ops {
				a.data[addr+i] = a.evalExpr(t)
			}
		})

	case ".ascii", ".asciz":
		if a.inText {
			a.fail("data directive in text section")
		}
		b, ok := parseString(rest)
		if !ok {
			a.fail("invalid string")
		}
		if word == ".asciz" {
			b = append(b, 0)
		}
		addr := a.reserve(len(b))
		for i, c := range b {
			a.data[addr+i] = uint32(c)
		}

	case ".space":
		if a.inText {
			a.fail("data directive in text section")
		}
		ops := splitOperands(rest)
		if len(ops) < 1 || len(ops) > 2 {
			a.fail("wrong number of operands for '.space'")
		}
		nv := int32(a.evalExpr(ops[0]))
		if nv < 0 {
			a.fail("invalid operand '" + ops[0] + "'")
		}
		addr := a.reserve(int(nv))
		if len(ops) == 2 {
			fill := ops[1]
			a.addJob(func() {
				f := a.evalExpr(fill)
				for k := 0; k < int(nv); k++ {
					a.data[addr+k] = f
				}
			})
		}

	default:
		a.fail("unknown directive '" + word + "'")
	}
}

func (a *assembler) instruction(name, rest string) {
	if !a.inText {
		a.fail("instruction in data section")
	}
	info, ok := opTable[name]
	if !ok {
		a.fail("unknown mnemonic '" + name + "'")
	}
	ops := splitOperands(rest)
	classes := make([]byte, len(ops))
	for i, o := range ops {
		switch {
		case o == "":
			a.fail("invalid operand ''")
		case o[0] == '[':
			if _, ok := splitMem(o); !ok {
				a.fail("invalid operand '" + o + "'")
			}
			classes[i] = 'M'
		default:
			if _, isR := regIndex(o); isR {
				classes[i] = 'R'
			} else {
				classes[i] = 'I'
			}
		}
	}
	if len(ops) != info.nargs {
		a.fail("wrong number of operands for '" + name + "'")
	}
	if !info.allows(classes) {
		a.fail("invalid operands for '" + name + "'")
	}
	idx := len(a.code)
	a.code = append(a.code, instr{op: info.op, name: name, line: a.line, raw: ops, classes: classes})
	a.addJob(func() { a.resolve(idx) })
}

func isJump(op int) bool {
	switch op {
	case opJmp, opJe, opJne, opJl, opJle, opJg, opJge, opCall:
		return true
	}
	return false
}

// resolve is the pass-2 evaluation of one instruction's operands.
func (a *assembler) resolve(idx int) {
	in := &a.code[idx]
	ops := make([]operand, len(in.raw))
	for i, t := range in.raw {
		switch in.classes[i] {
		case 'R':
			r, _ := regIndex(t)
			ops[i] = operand{cls: 'R', reg: r}
		case 'I':
			ops[i] = operand{cls: 'I', val: a.evalExpr(t)}
		case 'M':
			terms, _ := splitMem(t)
			o := operand{cls: 'M', reg: -1}
			for _, tm := range terms {
				if tm.isReg {
					o.reg = tm.reg
					continue
				}
				v := a.evalExpr(tm.text)
				if tm.neg {
					v = -v
				}
				o.val += v
			}
			ops[i] = o
		}
	}
	if isJump(in.op) {
		t := int32(ops[0].val)
		if t < 0 || int(t) >= len(a.code) {
			a.fail("invalid jump target")
		}
	}
	in.ops = ops
}

func (a *assembler) statement(raw string) {
	s := strings.TrimSpace(stripComment(raw))
	for {
		name, rest, ok := parseLabel(s)
		if !ok {
			break
		}
		a.defineLabel(name)
		s = strings.TrimSpace(rest)
	}
	if s == "" {
		return
	}
	word, rest := splitWord(s)
	rest = strings.TrimSpace(rest)
	if strings.HasPrefix(word, ".") {
		a.directive(word, rest)
	} else {
		a.instruction(word, rest)
	}
}

func assemble(lines []string) (p *program, aerr *asmError) {
	a := &assembler{syms: map[string]*symbol{}, budget: defBudget, inText: true}
	defer func() {
		if r := recover(); r != nil {
			e, ok := r.(asmError)
			if !ok {
				panic(r)
			}
			aerr = &e
		}
	}()
	for i, l := range lines {
		a.line = i + 1
		a.statement(l)
	}
	for _, j := range a.jobs {
		a.line = j.line
		j.fn()
	}
	start := 0
	if s, ok := a.syms["main"]; ok && s.inText && !s.isEqu {
		start = int(s.val)
	}
	p = &program{code: a.code, data: a.data, budget: a.budget, start: start}
	return p, nil
}

// ---------------------------------------------------------------- machine

type machine struct {
	regs   [10]int32
	mem    [memSize]int32
	z, l   bool
	steps  int
	budget int
	pc     int
	code   []instr
	input  []int32
	inPos  int
	out    []byte
	halted bool
}

func (m *machine) checkAddr(addr int32) int {
	if addr < 0 || addr >= memSize {
		panic(trapError(fmt.Sprintf("memory access out of range: %d", addr)))
	}
	return int(addr)
}

func (m *machine) effAddr(o operand) int32 {
	var base int32
	if o.reg >= 0 {
		base = m.regs[o.reg]
	}
	return base + int32(o.val)
}

func (m *machine) read(o operand) int32 {
	switch o.cls {
	case 'R':
		return m.regs[o.reg]
	case 'I':
		return int32(o.val)
	}
	return m.mem[m.checkAddr(m.effAddr(o))]
}

func (m *machine) write(o operand, v int32) {
	if o.cls == 'R' {
		m.regs[o.reg] = v
		return
	}
	m.mem[m.checkAddr(m.effAddr(o))] = v
}

func (m *machine) exec(in *instr) {
	ops := in.ops
	next := m.pc + 1
	sp := &m.regs[regSP]
	switch in.op {
	case opMov:
		v := m.read(ops[1])
		m.write(ops[0], v)

	case opAdd, opSub, opMul, opDiv, opMod, opAnd, opOr, opXor, opShl, opShr, opSar:
		b := m.read(ops[1])
		d := ops[0].reg
		a := m.regs[d]
		var r int32
		switch in.op {
		case opAdd:
			r = a + b
		case opSub:
			r = a - b
		case opMul:
			r = a * b
		case opDiv:
			if b == 0 {
				panic(trapError("division by zero"))
			}
			r = a / b
		case opMod:
			if b == 0 {
				panic(trapError("division by zero"))
			}
			r = a % b
		case opAnd:
			r = a & b
		case opOr:
			r = a | b
		case opXor:
			r = a ^ b
		case opShl:
			r = int32(uint32(a) << (uint32(b) & 31))
		case opShr:
			r = int32(uint32(a) >> (uint32(b) & 31))
		case opSar:
			r = a >> (uint32(b) & 31)
		}
		m.regs[d] = r

	case opCmp:
		b := m.read(ops[1])
		a := m.regs[ops[0].reg]
		m.z = a == b
		m.l = a < b

	case opNeg:
		m.regs[ops[0].reg] = -m.regs[ops[0].reg]
	case opNot:
		m.regs[ops[0].reg] = ^m.regs[ops[0].reg]
	case opInc:
		m.regs[ops[0].reg]++
	case opDec:
		m.regs[ops[0].reg]--

	case opLea:
		m.regs[ops[0].reg] = m.effAddr(ops[1])

	case opPush:
		v := m.read(ops[0])
		if *sp <= 0 {
			panic(trapError("stack overflow"))
		}
		addr := m.checkAddr(*sp - 1)
		*sp--
		m.mem[addr] = v

	case opPop:
		if *sp >= memSize {
			panic(trapError("stack underflow"))
		}
		v := m.mem[m.checkAddr(*sp)]
		*sp++
		m.regs[ops[0].reg] = v

	case opJmp:
		next = int(int32(ops[0].val))
	case opJe:
		if m.z {
			next = int(int32(ops[0].val))
		}
	case opJne:
		if !m.z {
			next = int(int32(ops[0].val))
		}
	case opJl:
		if m.l {
			next = int(int32(ops[0].val))
		}
	case opJle:
		if m.l || m.z {
			next = int(int32(ops[0].val))
		}
	case opJg:
		if !m.l && !m.z {
			next = int(int32(ops[0].val))
		}
	case opJge:
		if !m.l {
			next = int(int32(ops[0].val))
		}

	case opCall:
		if *sp <= 0 {
			panic(trapError("stack overflow"))
		}
		addr := m.checkAddr(*sp - 1)
		*sp--
		m.mem[addr] = int32(next)
		next = int(int32(ops[0].val))

	case opRet:
		if *sp >= memSize {
			panic(trapError("stack underflow"))
		}
		v := m.mem[m.checkAddr(*sp)]
		*sp++
		next = int(v)

	case opIn:
		if m.inPos >= len(m.input) {
			panic(trapError("input exhausted"))
		}
		m.regs[ops[0].reg] = m.input[m.inPos]
		m.inPos++

	case opOut:
		v := m.read(ops[0])
		m.out = strconv.AppendInt(m.out, int64(v), 10)
		m.out = append(m.out, '\n')

	case opOutc:
		v := m.read(ops[0])
		if v < 0 || v > 127 {
			panic(trapError("invalid character"))
		}
		m.out = append(m.out, byte(v))

	case opHalt:
		m.halted = true

	case opNop:
	}
	m.pc = next
}

// run executes until halt or a trap. It returns the trap message, or "" on halt.
func (m *machine) run() (msg string) {
	defer func() {
		if r := recover(); r != nil {
			t, ok := r.(trapError)
			if !ok {
				panic(r)
			}
			msg = string(t)
		}
	}()
	for !m.halted {
		if m.steps >= m.budget {
			panic(trapError("budget exceeded"))
		}
		if m.pc < 0 || m.pc >= len(m.code) {
			panic(trapError("pc out of range"))
		}
		m.exec(&m.code[m.pc])
		m.steps++
	}
	return ""
}

// ---------------------------------------------------------------- main

func parseInput(tokens []string) []int32 {
	var vals []int32
	for _, tok := range tokens {
		neg := false
		digits := tok
		if strings.HasPrefix(tok, "-") {
			neg = true
			digits = tok[1:]
		}
		if !allDigits(digits) {
			continue
		}
		var v uint32
		for i := 0; i < len(digits); i++ {
			v = v*10 + uint32(digits[i]-'0')
		}
		if neg {
			v = -v
		}
		vals = append(vals, int32(v))
	}
	return vals
}

func b2i(b bool) int {
	if b {
		return 1
	}
	return 0
}

func main() {
	raw, _ := io.ReadAll(os.Stdin)
	lines := strings.Split(string(raw), "\n")
	var src []string
	var inputLines []string
	sep := false
	for _, l := range lines {
		l = strings.TrimSuffix(l, "\r")
		if sep {
			inputLines = append(inputLines, l)
			continue
		}
		if l == "====" {
			sep = true
			continue
		}
		src = append(src, l)
	}

	p, aerr := assemble(src)
	if aerr != nil {
		fmt.Printf("asm error line %d: %s\n", aerr.line, aerr.msg)
		return
	}

	m := &machine{
		code:   p.code,
		budget: p.budget,
		pc:     p.start,
		input:  parseInput(strings.Fields(strings.Join(inputLines, "\n"))),
	}
	m.regs[regSP] = memSize
	for i := range m.mem {
		m.mem[i] = int32(p.data[i])
	}

	msg := m.run()

	var buf bytes.Buffer
	buf.Write(m.out)
	if len(m.out) > 0 && m.out[len(m.out)-1] != '\n' {
		buf.WriteByte('\n')
	}
	if msg == "" {
		fmt.Fprintf(&buf, "-- halted after %d steps\n", m.steps)
	} else {
		line := "-"
		if m.pc >= 0 && m.pc < len(m.code) {
			line = strconv.Itoa(m.code[m.pc].line)
		}
		fmt.Fprintf(&buf, "-- trap: %s (pc=%d line=%s) after %d steps\n", msg, m.pc, line, m.steps)
	}
	r := m.regs
	fmt.Fprintf(&buf, "regs: r0=%d r1=%d r2=%d r3=%d r4=%d r5=%d r6=%d r7=%d sp=%d bp=%d\n",
		r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[regSP], r[regBP])
	fmt.Fprintf(&buf, "flags: Z=%d L=%d\n", b2i(m.z), b2i(m.l))
	os.Stdout.Write(buf.Bytes())
}

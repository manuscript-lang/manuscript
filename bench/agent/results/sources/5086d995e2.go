package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

// stopT is panicked after a fatal error; it ends the current request only.
type stopT struct{}

type recipeLine struct {
	text string
	line int
}

// Rule is an explicit rule (accumulated over all rules for the target).
type Rule struct {
	normal, order []string
	recipe        []recipeLine
	hasRecipe     bool
}

type patRule struct {
	pattern       string
	normal, order []string
	recipe        []recipeLine
}

type Var struct {
	value     string
	recursive bool
}

type Makefile struct {
	vars          map[string]*Var
	explicit      map[string]*Rule
	explicitOrder []string
	patterns      []*patRule
	phony         map[string]bool
	phonyOrder    []string
	hasDefault    bool
	defaultGoal   string
}

// resolved is the result of rule resolution for one target.
type resolved struct {
	normal, order []string
	recipe        []recipeLine
	hasRecipe     bool
	stem          string
}

type binding struct{ name, value string }

type pendingRule struct {
	targets       []string
	normal, order []string
	recipe        []recipeLine
	line          int
	phony         bool
}

type condFrame struct {
	active, taken, elseSeen bool
	line                    int
}

type logical struct {
	text string
	line int
}

type prog struct {
	out       *bufio.Writer
	srcLines  []string
	table     map[string]int64
	clock     int64
	mf        *Makefile
	cmd       map[string]string
	locals    []binding
	auto      map[string]string
	expanding map[string]bool
	curLine   int

	// per-build state
	memo       map[string]bool
	changed    map[string]bool
	stack      []string
	recipeRuns int
	dry        bool
}

func main() {
	data, _ := io.ReadAll(os.Stdin)
	raw := strings.Split(string(data), "\n")
	var secs [3][]string
	cur := 0
	for _, ln := range raw {
		ln = strings.TrimSuffix(ln, "\r")
		if ln == "====" && cur < 2 {
			cur++
			continue
		}
		secs[cur] = append(secs[cur], ln)
	}
	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	p := &prog{out: w, srcLines: secs[0], table: map[string]int64{}}
	for _, ln := range secs[1] {
		f := strings.Fields(ln)
		if len(f) != 2 {
			continue
		}
		m, err := strconv.ParseInt(f[1], 10, 64)
		if err != nil || m < 0 {
			continue
		}
		p.table[f[0]] = m
		if m > p.clock {
			p.clock = m
		}
	}
	for _, ln := range secs[2] {
		t := strings.TrimSpace(ln)
		if t == "" || t[0] == '#' {
			continue
		}
		p.say("> " + strings.TrimRightFunc(ln, unicode.IsSpace))
		p.handle(t)
	}
}

// ---------- output and errors ----------

func (p *prog) say(s string) {
	p.out.WriteString(s)
	p.out.WriteByte('\n')
}

// fatalAt prints "Makefile:N: *** msg.  Stop." (or "make: ***" when line is 0).
func (p *prog) fatalAt(line int, msg string) {
	if line > 0 {
		p.say(fmt.Sprintf("Makefile:%d: *** %s.  Stop.", line, msg))
	} else {
		p.say("make: *** " + msg + ".  Stop.")
	}
	panic(stopT{})
}

func (p *prog) fatalLine(msg string) { p.fatalAt(p.curLine, msg) }

// fatalMake prints "make: *** msg  Stop." where msg already carries its period.
func (p *prog) fatalMake(msg string) {
	p.say("make: *** " + msg + "  Stop.")
	panic(stopT{})
}

// ---------- requests ----------

func (p *prog) handle(t string) {
	defer func() {
		if r := recover(); r != nil {
			if _, ok := r.(stopT); !ok {
				panic(r)
			}
		}
	}()
	p.locals = nil
	p.auto = nil
	p.expanding = map[string]bool{}
	p.curLine = 0
	words := strings.Fields(t)
	switch words[0] {
	case "build", "dry", "deps", "targets":
		p.cmd = map[string]string{}
		var rest []string
		for _, w := range words[1:] {
			if i := strings.IndexByte(w, '='); i > 0 {
				p.cmd[w[:i]] = w[i+1:]
			} else {
				rest = append(rest, w)
			}
		}
		p.parse()
		switch words[0] {
		case "build", "dry":
			goals := rest
			if len(goals) == 0 {
				if !p.mf.hasDefault {
					p.fatalMake("No targets.")
				}
				goals = []string{p.mf.defaultGoal}
			}
			p.build(goals, words[0] == "dry")
		case "deps":
			if len(rest) != 1 {
				p.say("usage: deps TARGET")
				return
			}
			p.deps(rest[0])
		case "targets":
			p.listTargets()
		}
	case "expand":
		p.cmd = nil
		p.parse()
		p.curLine = 0
		p.say("[" + p.expand(strings.TrimSpace(t[len("expand"):])) + "]")
	case "files":
		names := make([]string, 0, len(p.table))
		for n := range p.table {
			names = append(names, n)
		}
		if len(names) == 0 {
			p.say("(no files)")
			return
		}
		sort.Strings(names)
		for _, n := range names {
			p.say(fmt.Sprintf("%s %d", n, p.table[n]))
		}
	case "touch":
		args := words[1:]
		switch len(args) {
		case 1:
			p.clock++
			p.table[args[0]] = p.clock
		case 2:
			n, err := strconv.ParseInt(args[1], 10, 64)
			if err != nil {
				p.say("bad request")
			} else {
				p.table[args[0]] = n
				if n > p.clock {
					p.clock = n
				}
			}
		default:
			p.say("bad request")
		}
	case "rm":
		for _, a := range words[1:] {
			delete(p.table, a)
		}
	default:
		p.say("unknown request: " + words[0])
	}
}

func (p *prog) inTable(n string) bool {
	_, ok := p.table[n]
	return ok
}

// ---------- logical lines and parsing ----------

func logicalLines(phys []string) []logical {
	var out []logical
	for i := 0; i < len(phys); {
		start := i + 1
		cur := phys[i]
		i++
		for strings.HasSuffix(cur, "\\") && i < len(phys) {
			cur = strings.TrimRight(cur[:len(cur)-1], " \t") + " " + strings.TrimLeft(phys[i], " \t")
			i++
		}
		out = append(out, logical{cur, start})
	}
	return out
}

// stripComment removes a '#' comment; "\#" becomes a literal '#'.
func stripComment(s string) string {
	var sb strings.Builder
	for k := 0; k < len(s); k++ {
		if s[k] == '\\' && k+1 < len(s) && s[k+1] == '#' {
			sb.WriteByte('#')
			k++
			continue
		}
		if s[k] == '#' {
			break
		}
		sb.WriteByte(s[k])
	}
	return sb.String()
}

// matchClose returns the index of the closer balancing an opener at start-1, or -1.
func matchClose(s string, start int, open, cl byte) int {
	depth := 1
	for k := start; k < len(s); k++ {
		switch s[k] {
		case open:
			depth++
		case cl:
			depth--
			if depth == 0 {
				return k
			}
		}
	}
	return -1
}

// findColon returns the first ':' outside variable references and before any ';'.
func findColon(s string) int {
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case ';':
			return -1
		case ':':
			return i
		case '$':
			if i+1 < len(s) {
				if s[i+1] == '(' || s[i+1] == '{' {
					cl := byte(')')
					if s[i+1] == '{' {
						cl = '}'
					}
					j := matchClose(s, i+2, s[i+1], cl)
					if j < 0 {
						return -1
					}
					i = j
				} else {
					i++
				}
			}
		}
	}
	return -1
}

func (p *prog) parse() {
	p.mf = &Makefile{vars: map[string]*Var{}, explicit: map[string]*Rule{}, phony: map[string]bool{}}
	p.curLine = 0
	var conds []condFrame
	var pend *pendingRule
	active := func() bool { return len(conds) == 0 || conds[len(conds)-1].active }
	closePending := func() {
		if pend != nil {
			p.closeRule(pend)
			pend = nil
		}
	}
	for _, ll := range logicalLines(p.srcLines) {
		p.curLine = ll.line
		if strings.HasPrefix(ll.text, "\t") {
			if !active() {
				continue
			}
			txt := strings.TrimLeft(ll.text, "\t")
			if strings.TrimSpace(txt) == "" {
				continue
			}
			if pend == nil {
				p.fatalLine("recipe commences before first target")
			}
			pend.recipe = append(pend.recipe, recipeLine{txt, ll.line})
			continue
		}
		s := strings.Trim(stripComment(ll.text), " \t")
		if s == "" {
			continue
		}
		word := strings.Fields(s)[0]
		switch word {
		case "ifdef", "ifndef", "ifeq", "ifneq", "else", "endif":
			closePending()
			rest := strings.TrimSpace(s[len(word):])
			switch word {
			case "ifdef", "ifndef", "ifeq", "ifneq":
				parent := active()
				c := false
				if parent {
					if word == "ifdef" || word == "ifndef" {
						c = p.definedNonEmpty(strings.TrimSpace(p.expand(rest)))
						if word == "ifndef" {
							c = !c
						}
					} else {
						c = p.evalIfeq(rest)
						if word == "ifneq" {
							c = !c
						}
					}
				}
				conds = append(conds, condFrame{active: c, taken: c || !parent, line: ll.line})
			case "else":
				if len(conds) == 0 || conds[len(conds)-1].elseSeen {
					p.fatalLine("extraneous 'else'")
				}
				f := &conds[len(conds)-1]
				f.elseSeen = true
				f.active = !f.taken
				f.taken = true
			case "endif":
				if len(conds) == 0 {
					p.fatalLine("extraneous 'endif'")
				}
				conds = conds[:len(conds)-1]
			}
			continue
		}
		if !active() {
			continue
		}
		closePending()
		pend = p.statement(s, ll.line)
	}
	closePending()
	if len(conds) > 0 {
		p.fatalAt(conds[len(conds)-1].line, "missing 'endif'")
	}
	for _, t := range p.mf.explicitOrder {
		if !strings.HasPrefix(t, ".") {
			p.mf.defaultGoal = t
			p.mf.hasDefault = true
			break
		}
	}
}

func (p *prog) definedNonEmpty(name string) bool {
	if v, ok := p.cmd[name]; ok {
		return v != ""
	}
	if v, ok := p.mf.vars[name]; ok {
		return v.value != ""
	}
	return false
}

func (p *prog) evalIfeq(rest string) bool {
	if len(rest) < 2 || rest[0] != '(' || rest[len(rest)-1] != ')' {
		p.fatalLine("invalid syntax in conditional")
	}
	inner := rest[1 : len(rest)-1]
	depth, commas, comma := 0, 0, -1
	for i := 0; i < len(inner); i++ {
		switch inner[i] {
		case '(', '{':
			depth++
		case ')', '}':
			depth--
		case ',':
			if depth == 0 {
				commas++
				comma = i
			}
		}
	}
	if commas != 1 {
		p.fatalLine("invalid syntax in conditional")
	}
	a := strings.Trim(p.expand(strings.Trim(inner[:comma], " \t")), " \t")
	b := strings.Trim(p.expand(strings.Trim(inner[comma+1:], " \t")), " \t")
	return a == b
}

// statement handles a non-directive, non-recipe, non-blank line. It returns a
// pending rule if the line opens one.
func (p *prog) statement(s string, line int) *pendingRule {
	eq := strings.IndexByte(s, '=')
	col := findColon(s)
	if eq >= 0 && (col < 0 || col > eq || col == eq-1) {
		nameEnd := eq
		op := "="
		if eq >= 1 {
			switch s[eq-1] {
			case ':':
				op = ":="
			case '?':
				op = "?="
			case '+':
				op = "+="
			}
			if op != "=" {
				nameEnd = eq - 1
			}
		}
		name := strings.Trim(p.expand(s[:nameEnd]), " \t")
		if name == "" {
			p.fatalLine("empty variable name")
		}
		p.assign(name, op, strings.Trim(s[eq+1:], " \t"))
		return nil
	}
	if col >= 0 {
		rest := s[col+1:]
		prereqRaw := rest
		recipeText, hasSemi := "", false
		if i := strings.IndexByte(rest, ';'); i >= 0 {
			prereqRaw = rest[:i]
			recipeText = rest[i+1:]
			hasSemi = true
		}
		targets := strings.Fields(p.expand(s[:col]))
		exp := p.expand(prereqRaw)
		pd := &pendingRule{targets: targets, line: line}
		if i := strings.IndexByte(exp, '|'); i >= 0 {
			pd.normal = strings.Fields(exp[:i])
			pd.order = strings.Fields(exp[i+1:])
		} else {
			pd.normal = strings.Fields(exp)
		}
		if hasSemi {
			pd.recipe = []recipeLine{{recipeText, line}}
		}
		if len(targets) == 1 && targets[0] == ".PHONY" {
			pd.phony = true
			for _, n := range append(append([]string{}, pd.normal...), pd.order...) {
				if !p.mf.phony[n] {
					p.mf.phony[n] = true
					p.mf.phonyOrder = append(p.mf.phonyOrder, n)
				}
			}
		}
		return pd
	}
	if strings.TrimSpace(p.expand(s)) != "" {
		p.fatalLine("missing separator")
	}
	return nil
}

func (p *prog) assign(name, op, value string) {
	if _, ok := p.cmd[name]; ok {
		return
	}
	mf := p.mf
	v, defined := mf.vars[name]
	switch op {
	case "=":
		mf.vars[name] = &Var{value, true}
	case ":=":
		mf.vars[name] = &Var{p.expand(value), false}
	case "?=":
		if !defined {
			mf.vars[name] = &Var{value, true}
		}
	case "+=":
		switch {
		case !defined:
			mf.vars[name] = &Var{value, true}
		case !v.recursive:
			mf.vars[name] = &Var{joinSp(v.value, p.expand(value)), false}
		default:
			mf.vars[name] = &Var{joinSp(v.value, value), true}
		}
	}
}

func joinSp(a, b string) string {
	if a == "" {
		return b
	}
	if b == "" {
		return a
	}
	return a + " " + b
}

func (p *prog) closeRule(pd *pendingRule) {
	if pd.phony {
		return
	}
	mf := p.mf
	for _, t := range pd.targets {
		if strings.Contains(t, "%") {
			mf.patterns = append(mf.patterns, &patRule{
				pattern: t,
				normal:  pd.normal,
				order:   pd.order,
				recipe:  pd.recipe,
			})
			continue
		}
		r := mf.explicit[t]
		if r == nil {
			r = &Rule{}
			mf.explicit[t] = r
			mf.explicitOrder = append(mf.explicitOrder, t)
		}
		r.normal = append(r.normal, pd.normal...)
		r.order = append(r.order, pd.order...)
		if len(pd.recipe) > 0 {
			if r.hasRecipe {
				p.say(fmt.Sprintf("Makefile:%d: warning: overriding recipe for target '%s'", pd.line, t))
			}
			r.recipe = pd.recipe
			r.hasRecipe = true
		}
	}
}

// ---------- expansion ----------

func isAutoVar(n string) bool {
	switch n {
	case "@", "<", "^", "?", "|", "*":
		return true
	}
	return false
}

func (p *prog) expand(s string) string {
	if strings.IndexByte(s, '$') < 0 {
		return s
	}
	var sb strings.Builder
	for i := 0; i < len(s); {
		c := s[i]
		if c != '$' {
			sb.WriteByte(c)
			i++
			continue
		}
		if i+1 >= len(s) {
			i++
			continue
		}
		d := s[i+1]
		switch d {
		case '$':
			sb.WriteByte('$')
			i += 2
		case '(', '{':
			cl := byte(')')
			if d == '{' {
				cl = '}'
			}
			j := matchClose(s, i+2, d, cl)
			if j < 0 {
				p.fatalLine("unterminated variable reference")
			}
			sb.WriteString(p.reference(s[i+2 : j]))
			i = j + 1
		default:
			_, size := utf8.DecodeRuneInString(s[i+1:])
			sb.WriteString(p.lookupValue(s[i+1 : i+1+size]))
			i += 1 + size
		}
	}
	return sb.String()
}

var funcNames = map[string]bool{
	"subst": true, "patsubst": true, "strip": true, "findstring": true,
	"filter": true, "filter-out": true, "sort": true, "word": true,
	"wordlist": true, "words": true, "firstword": true, "lastword": true,
	"dir": true, "notdir": true, "suffix": true, "basename": true,
	"addprefix": true, "addsuffix": true, "wildcard": true, "foreach": true,
	"if": true, "info": true, "error": true,
}

// reference expands the inside of $(...) or ${...}.
func (p *prog) reference(body string) string {
	if k := strings.IndexAny(body, " \t"); k > 0 && funcNames[body[:k]] {
		return p.callFunc(body[:k], body[k+1:])
	}
	exp := p.expand(body)
	if c := strings.IndexByte(exp, ':'); c > 0 {
		if e := strings.IndexByte(exp[c+1:], '='); e >= 0 {
			name := strings.TrimSpace(exp[:c])
			rest := exp[c+1:]
			return substRef(p.lookupValue(name), rest[:e], rest[e+1:])
		}
	}
	return p.lookupValue(strings.Trim(exp, " \t"))
}

func substRef(value, from, to string) string {
	if !strings.Contains(from, "%") {
		from = "%" + from
	}
	if !strings.Contains(to, "%") {
		to = "%" + to
	}
	return strings.Join(patsubstWords(from, to, strings.Fields(value)), " ")
}

func (p *prog) lookupValue(name string) string {
	v, _ := p.lookup(name)
	return v
}

func (p *prog) lookup(name string) (string, bool) {
	for i := len(p.locals) - 1; i >= 0; i-- {
		if p.locals[i].name == name {
			return p.locals[i].value, true
		}
	}
	if isAutoVar(name) {
		return p.auto[name], true
	}
	if v, ok := p.cmd[name]; ok {
		return p.expandRec(name, v), true
	}
	if v, ok := p.mf.vars[name]; ok {
		if v.recursive {
			return p.expandRec(name, v.value), true
		}
		return v.value, true
	}
	return "", false
}

func (p *prog) expandRec(name, raw string) string {
	if p.expanding[name] {
		p.fatalLine(fmt.Sprintf("Recursive variable '%s' references itself (eventually)", name))
	}
	p.expanding[name] = true
	r := p.expand(raw)
	delete(p.expanding, name)
	return r
}

// splitArgs splits at top-level commas (parens and braces count), trimming each raw argument.
func splitArgs(rest string) []string {
	depth, start := 0, 0
	var out []string
	for i := 0; i < len(rest); i++ {
		switch rest[i] {
		case '(', '{':
			depth++
		case ')', '}':
			depth--
		case ',':
			if depth == 0 {
				out = append(out, strings.Trim(rest[start:i], " \t"))
				start = i + 1
			}
		}
	}
	return append(out, strings.Trim(rest[start:], " \t"))
}

func matchStem(pat, w string) (string, bool) {
	i := strings.IndexByte(pat, '%')
	if i < 0 {
		return "", pat == w
	}
	pre, suf := pat[:i], pat[i+1:]
	if len(w) < len(pre)+len(suf) || !strings.HasPrefix(w, pre) || !strings.HasSuffix(w, suf) {
		return "", false
	}
	return w[len(pre) : len(w)-len(suf)], true
}

func patsubstWords(pat, repl string, words []string) []string {
	out := make([]string, 0, len(words))
	for _, w := range words {
		if stem, ok := matchStem(pat, w); ok {
			if i := strings.IndexByte(repl, '%'); i >= 0 {
				out = append(out, repl[:i]+stem+repl[i+1:])
			} else {
				out = append(out, repl)
			}
		} else {
			out = append(out, w)
		}
	}
	return out
}

func filterWords(pats, words string, keep bool) string {
	ps := strings.Fields(pats)
	var out []string
	for _, w := range strings.Fields(words) {
		match := false
		for _, pt := range ps {
			if _, ok := matchStem(pt, w); ok {
				match = true
				break
			}
		}
		if match == keep {
			out = append(out, w)
		}
	}
	return strings.Join(out, " ")
}

func hasWild(s string) bool { return strings.ContainsAny(s, "*?") }

// glob matches with * (run of non-'/') and ? (one non-'/'); other bytes literally.
func glob(p, s string) bool {
	if p == "" {
		return s == ""
	}
	switch p[0] {
	case '*':
		for k := 0; k <= len(s); k++ {
			if glob(p[1:], s[k:]) {
				return true
			}
			if k < len(s) && s[k] == '/' {
				break
			}
		}
		return false
	case '?':
		return len(s) > 0 && s[0] != '/' && glob(p[1:], s[1:])
	default:
		return len(s) > 0 && s[0] == p[0] && glob(p[1:], s[1:])
	}
}

func (p *prog) callFunc(name, rest string) string {
	args := splitArgs(rest)
	arg := func(i int) string {
		if i < len(args) {
			return args[i]
		}
		return ""
	}
	ex := func(i int) string { return p.expand(arg(i)) }
	switch name {
	case "info":
		p.say(p.expand(strings.Trim(rest, " \t")))
		return ""
	case "error":
		p.fatalLine(p.expand(strings.Trim(rest, " \t")))
	case "subst":
		from := ex(0)
		to := ex(1)
		text := ex(2)
		if from == "" {
			return text
		}
		return strings.ReplaceAll(text, from, to)
	case "patsubst":
		pat := ex(0)
		repl := ex(1)
		text := ex(2)
		return strings.Join(patsubstWords(pat, repl, strings.Fields(text)), " ")
	case "strip":
		return strings.Join(strings.Fields(ex(0)), " ")
	case "findstring":
		find := ex(0)
		text := ex(1)
		if strings.Contains(text, find) {
			return find
		}
		return ""
	case "filter":
		pats := ex(0)
		return filterWords(pats, ex(1), true)
	case "filter-out":
		pats := ex(0)
		return filterWords(pats, ex(1), false)
	case "sort":
		ws := strings.Fields(ex(0))
		sort.Strings(ws)
		var out []string
		for i, w := range ws {
			if i == 0 || w != ws[i-1] {
				out = append(out, w)
			}
		}
		return strings.Join(out, " ")
	case "word":
		n, err := strconv.Atoi(strings.TrimSpace(ex(0)))
		ws := strings.Fields(ex(1))
		if err != nil || n < 1 || n > len(ws) {
			return ""
		}
		return ws[n-1]
	case "wordlist":
		s, err1 := strconv.Atoi(strings.TrimSpace(ex(0)))
		e, err2 := strconv.Atoi(strings.TrimSpace(ex(1)))
		ws := strings.Fields(ex(2))
		if err1 != nil || err2 != nil || s < 1 || e < s || s > len(ws) {
			return ""
		}
		if e > len(ws) {
			e = len(ws)
		}
		return strings.Join(ws[s-1:e], " ")
	case "words":
		return strconv.Itoa(len(strings.Fields(ex(0))))
	case "firstword":
		ws := strings.Fields(ex(0))
		if len(ws) == 0 {
			return ""
		}
		return ws[0]
	case "lastword":
		ws := strings.Fields(ex(0))
		if len(ws) == 0 {
			return ""
		}
		return ws[len(ws)-1]
	case "dir", "notdir", "suffix", "basename":
		var out []string
		for _, w := range strings.Fields(ex(0)) {
			slash := strings.LastIndexByte(w, '/')
			base := w[slash+1:]
			switch name {
			case "dir":
				if slash < 0 {
					out = append(out, "./")
				} else {
					out = append(out, w[:slash+1])
				}
			case "notdir":
				out = append(out, base)
			case "suffix":
				if j := strings.LastIndexByte(base, '.'); j >= 0 {
					out = append(out, base[j:])
				}
			case "basename":
				if j := strings.LastIndexByte(base, '.'); j >= 0 {
					out = append(out, w[:slash+1+j])
				} else {
					out = append(out, w)
				}
			}
		}
		return strings.Join(out, " ")
	case "addprefix":
		pre := ex(0)
		var out []string
		for _, w := range strings.Fields(ex(1)) {
			out = append(out, pre+w)
		}
		return strings.Join(out, " ")
	case "addsuffix":
		suf := ex(0)
		var out []string
		for _, w := range strings.Fields(ex(1)) {
			out = append(out, w+suf)
		}
		return strings.Join(out, " ")
	case "wildcard":
		var out []string
		for _, pat := range strings.Fields(ex(0)) {
			if !hasWild(pat) {
				if p.inTable(pat) {
					out = append(out, pat)
				}
				continue
			}
			var matches []string
			for n := range p.table {
				if glob(pat, n) {
					matches = append(matches, n)
				}
			}
			sort.Strings(matches)
			out = append(out, matches...)
		}
		return strings.Join(out, " ")
	case "foreach":
		v := strings.TrimSpace(ex(0))
		words := strings.Fields(ex(1))
		text := arg(2)
		results := make([]string, 0, len(words))
		for _, w := range words {
			p.locals = append(p.locals, binding{v, w})
			results = append(results, p.expand(text))
			p.locals = p.locals[:len(p.locals)-1]
		}
		return strings.Join(results, " ")
	case "if":
		if strings.TrimSpace(ex(0)) != "" {
			return p.expand(arg(1))
		}
		if len(args) > 2 {
			return p.expand(arg(2))
		}
		return ""
	}
	return ""
}

// ---------- rule resolution ----------

func substStem(q, stem string) string {
	if i := strings.IndexByte(q, '%'); i >= 0 {
		return q[:i] + stem + q[i+1:]
	}
	return q
}

func (p *prog) canMake(name string, d int) bool {
	if p.inTable(name) || p.mf.explicit[name] != nil || p.mf.phony[name] {
		return true
	}
	if d >= 8 {
		return false
	}
	for _, pr := range p.mf.patterns {
		if len(pr.recipe) == 0 {
			continue
		}
		stem, ok := matchStem(pr.pattern, name)
		if !ok || stem == "" {
			continue
		}
		if p.allMakeable(pr.normal, stem, d+1) && p.allMakeable(pr.order, stem, d+1) {
			return true
		}
	}
	return false
}

func (p *prog) allMakeable(list []string, stem string, d int) bool {
	for _, q := range list {
		if !p.canMake(substStem(q, stem), d) {
			return false
		}
	}
	return true
}

func substAll(list []string, stem string) []string {
	out := make([]string, 0, len(list))
	for _, q := range list {
		out = append(out, substStem(q, stem))
	}
	return out
}

func (p *prog) resolve(t string) *resolved {
	mf := p.mf
	ex := mf.explicit[t]
	if ex != nil && ex.hasRecipe {
		return &resolved{normal: ex.normal, order: ex.order, recipe: ex.recipe, hasRecipe: true}
	}
	for _, pr := range mf.patterns {
		if len(pr.recipe) == 0 {
			continue
		}
		stem, ok := matchStem(pr.pattern, t)
		if !ok || stem == "" {
			continue
		}
		if !p.allMakeable(pr.normal, stem, 0) || !p.allMakeable(pr.order, stem, 0) {
			continue
		}
		r := &resolved{recipe: pr.recipe, hasRecipe: true, stem: stem}
		r.normal = substAll(pr.normal, stem)
		r.order = substAll(pr.order, stem)
		if ex != nil {
			r.normal = append(r.normal, ex.normal...)
			r.order = append(r.order, ex.order...)
		}
		return r
	}
	if ex != nil {
		return &resolved{normal: ex.normal, order: ex.order}
	}
	return nil
}

func dedupe(xs []string) []string {
	seen := make(map[string]bool, len(xs))
	out := []string{}
	for _, x := range xs {
		if !seen[x] {
			seen[x] = true
			out = append(out, x)
		}
	}
	return out
}

// ---------- build ----------

func (p *prog) build(goals []string, dry bool) {
	p.dry = dry
	p.memo = map[string]bool{}
	p.changed = map[string]bool{}
	p.stack = nil
	p.recipeRuns = 0
	for _, g := range goals {
		before := p.recipeRuns
		p.update(g, "")
		if p.recipeRuns == before {
			rr := p.resolve(g)
			if (rr != nil && rr.hasRecipe) || (p.inTable(g) && !p.mf.phony[g]) {
				p.say(fmt.Sprintf("make: '%s' is up to date.", g))
			} else {
				p.say(fmt.Sprintf("make: Nothing to be done for '%s'.", g))
			}
		}
	}
}

func (p *prog) finish(t string, changed bool) bool {
	p.memo[t] = changed
	if changed {
		p.changed[t] = true
	}
	p.stack = p.stack[:len(p.stack)-1]
	return changed
}

func (p *prog) update(t, neededBy string) bool {
	if v, ok := p.memo[t]; ok {
		return v
	}
	for i, s := range p.stack {
		if s == t {
			cyc := append(append([]string{}, p.stack[i:]...), t)
			p.fatalMake("Circular dependency detected: " + strings.Join(cyc, " -> ") + ".")
		}
	}
	p.stack = append(p.stack, t)
	rr := p.resolve(t)
	if rr == nil {
		if p.inTable(t) {
			return p.finish(t, false)
		}
		if p.mf.phony[t] {
			return p.finish(t, true)
		}
		if neededBy == "" {
			p.fatalMake(fmt.Sprintf("No rule to make target '%s'.", t))
		}
		p.fatalMake(fmt.Sprintf("No rule to make target '%s', needed by '%s'.", t, neededBy))
	}
	oldM, wasIn := p.table[t]
	normal := dedupe(rr.normal)
	anyChanged := false
	for _, q := range normal {
		if p.update(q, t) {
			anyChanged = true
		}
	}
	newer := false
	if wasIn {
		for _, q := range normal {
			if m, ok := p.table[q]; ok && m > oldM {
				newer = true
			}
		}
	}
	for _, q := range dedupe(rr.order) {
		p.update(q, t)
	}
	need := p.mf.phony[t] || !p.inTable(t) || anyChanged || newer
	changed := false
	if need {
		changed = true
		if rr.hasRecipe {
			p.runRecipe(t, rr, wasIn, oldM)
		}
	}
	return p.finish(t, changed)
}

func (p *prog) runRecipe(t string, rr *resolved, wasIn bool, oldM int64) {
	p.recipeRuns++
	dd := dedupe(rr.normal)
	var newer []string
	for _, q := range dd {
		if !wasIn || p.changed[q] {
			newer = append(newer, q)
			continue
		}
		if m, ok := p.table[q]; ok && m > oldM {
			newer = append(newer, q)
		}
	}
	first := ""
	if len(rr.normal) > 0 {
		first = rr.normal[0]
	}
	p.auto = map[string]string{
		"@": t,
		"<": first,
		"^": strings.Join(dd, " "),
		"?": strings.Join(newer, " "),
		"|": strings.Join(dedupe(rr.order), " "),
		"*": rr.stem,
	}
	for _, rl := range rr.recipe {
		p.curLine = rl.line
		text := strings.TrimSpace(p.expand(rl.text))
		silent, ignore := false, false
		i := 0
		for ; i < len(text); i++ {
			c := text[i]
			if c == '@' {
				silent = true
			} else if c == '-' {
				ignore = true
			} else if c != '+' && c != ' ' && c != '\t' {
				break
			}
		}
		command := strings.TrimSpace(text[i:])
		if p.dry {
			p.say(command)
			continue
		}
		if !silent {
			p.say(command)
		}
		status := p.simulate(command)
		if status != 0 {
			if ignore {
				p.say(fmt.Sprintf("make: [Makefile:%d: %s] Error %d (ignored)", rl.line, t, status))
				continue
			}
			p.say(fmt.Sprintf("make: *** [Makefile:%d: %s] Error %d", rl.line, t, status))
			panic(stopT{})
		}
	}
	p.auto = nil
	p.curLine = 0
	if p.dry {
		return
	}
	if !p.mf.phony[t] {
		p.clock++
		p.table[t] = p.clock
	}
}

var quoteStripper = strings.NewReplacer("'", "", "\"", "")

// simulate runs a recipe command against the in-memory file table and returns its status.
func (p *prog) simulate(command string) int {
	words := strings.Fields(command)
	if len(words) == 0 {
		return 0
	}
	args := words[1:]
	switch words[0] {
	case "false":
		return 1
	case "exit":
		if len(args) == 0 {
			return 0
		}
		n, err := strconv.Atoi(args[0])
		if err != nil {
			return 2
		}
		return n
	case "touch":
		for _, a := range args {
			if !strings.HasPrefix(a, "-") {
				p.clock++
				p.table[a] = p.clock
			}
		}
		return 0
	case "rm":
		for _, a := range args {
			if !strings.HasPrefix(a, "-") {
				delete(p.table, a)
			}
		}
		return 0
	case "cp":
		if len(args) == 2 {
			if !p.inTable(args[0]) {
				p.say(fmt.Sprintf("cp: cannot stat '%s': No such file or directory", args[0]))
				return 1
			}
			p.clock++
			p.table[args[1]] = p.clock
		}
		return 0
	case "echo":
		out := make([]string, 0, len(args))
		for _, a := range args {
			out = append(out, quoteStripper.Replace(a))
		}
		p.say(strings.Join(out, " "))
		return 0
	}
	return 0
}

// ---------- deps and targets ----------

func (p *prog) deps(target string) {
	var buf []string
	state := map[string]int{target: 1}
	stack := []string{target}
	var visit func(n string)
	visit = func(n string) {
		rr := p.resolve(n)
		if rr == nil {
			return
		}
		prs := append(dedupe(rr.normal), dedupe(rr.order)...)
		for _, q := range prs {
			switch state[q] {
			case 2:
				continue
			case 1:
				idx := 0
				for i, s := range stack {
					if s == q {
						idx = i
						break
					}
				}
				cyc := append(append([]string{}, stack[idx:]...), q)
				p.fatalMake("Circular dependency detected: " + strings.Join(cyc, " -> ") + ".")
			}
			state[q] = 1
			stack = append(stack, q)
			visit(q)
			stack = stack[:len(stack)-1]
			state[q] = 2
			buf = append(buf, q)
		}
	}
	visit(target)
	if len(buf) == 0 {
		p.say("(no prerequisites)")
		return
	}
	for _, q := range buf {
		p.say(q)
	}
}

func formatRule(name string, normal, order []string) string {
	s := name + ":"
	if len(normal) > 0 {
		s += " " + strings.Join(normal, " ")
	}
	if len(order) > 0 {
		s += " | " + strings.Join(order, " ")
	}
	return s
}

func (p *prog) listTargets() {
	mf := p.mf
	if mf.hasDefault {
		p.say("default: " + mf.defaultGoal)
	}
	for _, t := range mf.explicitOrder {
		r := mf.explicit[t]
		p.say(formatRule(t, r.normal, r.order))
	}
	for _, pr := range mf.patterns {
		p.say(formatRule("pattern "+pr.pattern, pr.normal, pr.order))
	}
	if len(mf.phonyOrder) > 0 {
		p.say("phony: " + strings.Join(mf.phonyOrder, " "))
	}
}

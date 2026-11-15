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

type fatalErr struct{ msg string }
type abortErr struct{}

type variable struct {
	simple bool
	val    string
}
type recLine struct {
	text string
	no   int
}
type rule struct {
	prereqs, order []string
	recipe         []recLine
}
type patRule struct {
	pat            string
	prereqs, order []string
	recipe         []recLine
}

var (
	out       *bufio.Writer
	files     = map[string]int64{}
	clock     int64
	curLine   int
	vars      map[string]*variable
	cmdSet    map[string]bool
	expanding map[string]bool
	explicit  map[string]*rule
	expOrder  []string
	patterns  []*patRule
	phony     map[string]bool
	phonyOrd  []string
	bindings  []binding
	autoOn    bool
	autoV     map[string]string
)

type binding struct{ name, val string }

func fatal(msg string) { panic(fatalErr{msg}) }

func printFatal(msg string) {
	if curLine > 0 {
		fmt.Fprintf(out, "Makefile:%d: *** %s.  Stop.\n", curLine, msg)
	} else {
		fmt.Fprintf(out, "make: *** %s.  Stop.\n", msg)
	}
}

func isWS(c byte) bool { return c == ' ' || c == '\t' }

func trim(s string) string { return strings.Trim(s, " \t") }

// ---------- expansion ----------

var funcNames = map[string]bool{"subst": true, "patsubst": true, "strip": true, "findstring": true, "filter": true, "filter-out": true, "sort": true, "word": true, "wordlist": true, "words": true, "firstword": true, "lastword": true, "dir": true, "notdir": true, "suffix": true, "basename": true, "addprefix": true, "addsuffix": true, "wildcard": true, "foreach": true, "if": true, "info": true, "error": true}

func expand(s string) string {
	if !strings.Contains(s, "$") {
		return s
	}
	var b strings.Builder
	i := 0
	for i < len(s) {
		c := s[i]
		if c != '$' {
			b.WriteByte(c)
			i++
			continue
		}
		i++
		if i >= len(s) {
			break
		}
		d := s[i]
		if d == '$' {
			b.WriteByte('$')
			i++
		} else if d == '(' || d == '{' {
			cl := byte(')')
			if d == '{' {
				cl = '}'
			}
			depth := 1
			j := i + 1
			for ; j < len(s); j++ {
				if s[j] == d {
					depth++
				} else if s[j] == cl {
					depth--
					if depth == 0 {
						break
					}
				}
			}
			if j >= len(s) {
				fatal("unterminated variable reference")
			}
			b.WriteString(evalRef(s[i+1 : j]))
			i = j + 1
		} else {
			b.WriteString(lookup(string(d)))
			i++
		}
	}
	return b.String()
}

func lookup(name string) string {
	for k := len(bindings) - 1; k >= 0; k-- {
		if bindings[k].name == name {
			return bindings[k].val
		}
	}
	if autoOn {
		if v, ok := autoV[name]; ok {
			return v
		}
	}
	v, ok := vars[name]
	if !ok {
		return ""
	}
	if v.simple {
		return v.val
	}
	if expanding[name] {
		fatal("Recursive variable '" + name + "' references itself (eventually)")
	}
	expanding[name] = true
	r := expand(v.val)
	delete(expanding, name)
	return r
}

func evalRef(inner string) string {
	idx := strings.IndexAny(inner, " \t")
	if idx > 0 && funcNames[inner[:idx]] {
		return callFunc(inner[:idx], inner[idx+1:])
	}
	name := trim(expand(inner))
	ci := strings.Index(name, ":")
	if ci > 0 {
		if ei := strings.Index(name[ci:], "="); ei >= 0 {
			ei += ci
			vn := name[:ci]
			from := name[ci+1 : ei]
			to := name[ei+1:]
			if !strings.Contains(from, "%") {
				from = "%" + from
				to = "%" + to
			}
			return patsubst(from, to, lookup(vn))
		}
	}
	return lookup(name)
}

func splitArgs(s string) []string {
	var r []string
	depth := 0
	st := 0
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '(', '{':
			depth++
		case ')', '}':
			if depth > 0 {
				depth--
			}
		case ',':
			if depth == 0 {
				r = append(r, trim(s[st:i]))
				st = i + 1
			}
		}
	}
	r = append(r, trim(s[st:]))
	return r
}

func matchPat(pat, w string) (string, bool) {
	p := strings.Index(pat, "%")
	if p < 0 {
		return "", pat == w
	}
	pre, suf := pat[:p], pat[p+1:]
	if len(w) < len(pre)+len(suf) || !strings.HasPrefix(w, pre) || !strings.HasSuffix(w, suf) {
		return "", false
	}
	return w[len(pre) : len(w)-len(suf)], true
}

func patsubst(pat, rep string, text string) string {
	var r []string
	for _, w := range strings.Fields(text) {
		if stem, ok := matchPat(pat, w); ok && strings.Contains(pat, "%") {
			r = append(r, strings.Replace(rep, "%", stem, 1))
		} else if ok {
			r = append(r, rep)
		} else {
			r = append(r, w)
		}
	}
	return strings.Join(r, " ")
}

func glob(p, n string) bool {
	if p == "" {
		return n == ""
	}
	switch p[0] {
	case '*':
		for k := 0; k <= len(n); k++ {
			if glob(p[1:], n[k:]) {
				return true
			}
			if k < len(n) && n[k] == '/' {
				break
			}
		}
		return false
	case '?':
		return n != "" && n[0] != '/' && glob(p[1:], n[1:])
	}
	return n != "" && n[0] == p[0] && glob(p[1:], n[1:])
}

func mapWords(text string, f func(string) string, skipEmpty bool) string {
	var r []string
	for _, w := range strings.Fields(text) {
		x := f(w)
		if x == "" && skipEmpty {
			continue
		}
		r = append(r, x)
	}
	return strings.Join(r, " ")
}

func callFunc(name, argstr string) string {
	raw := splitArgs(argstr)
	get := func(i int) string {
		if i < len(raw) {
			return expand(raw[i])
		}
		return ""
	}
	switch name {
	case "subst":
		from, to, text := get(0), get(1), get(2)
		if from == "" {
			return text
		}
		return strings.ReplaceAll(text, from, to)
	case "patsubst":
		a, b, c := get(0), get(1), get(2)
		return patsubst(a, b, c)
	case "strip":
		return strings.Join(strings.Fields(get(0)), " ")
	case "findstring":
		f, t := get(0), get(1)
		if strings.Contains(t, f) {
			return f
		}
		return ""
	case "filter", "filter-out":
		pats := strings.Fields(get(0))
		words := strings.Fields(get(1))
		var r []string
		for _, w := range words {
			m := false
			for _, p := range pats {
				if _, ok := matchPat(p, w); ok {
					m = true
					break
				}
			}
			if m == (name == "filter") {
				r = append(r, w)
			}
		}
		return strings.Join(r, " ")
	case "sort":
		ws := strings.Fields(get(0))
		sort.Strings(ws)
		var r []string
		for i, w := range ws {
			if i == 0 || w != ws[i-1] {
				r = append(r, w)
			}
		}
		return strings.Join(r, " ")
	case "word":
		n, err := strconv.Atoi(trim(get(0)))
		ws := strings.Fields(get(1))
		if err != nil || n < 1 || n > len(ws) {
			return ""
		}
		return ws[n-1]
	case "wordlist":
		s, e1 := strconv.Atoi(trim(get(0)))
		e, e2 := strconv.Atoi(trim(get(1)))
		ws := strings.Fields(get(2))
		if e1 != nil || e2 != nil || s < 1 || e < s || s > len(ws) {
			return ""
		}
		if e > len(ws) {
			e = len(ws)
		}
		return strings.Join(ws[s-1:e], " ")
	case "words":
		return strconv.Itoa(len(strings.Fields(get(0))))
	case "firstword":
		ws := strings.Fields(get(0))
		if len(ws) == 0 {
			return ""
		}
		return ws[0]
	case "lastword":
		ws := strings.Fields(get(0))
		if len(ws) == 0 {
			return ""
		}
		return ws[len(ws)-1]
	case "dir":
		return mapWords(get(0), func(w string) string {
			if i := strings.LastIndex(w, "/"); i >= 0 {
				return w[:i+1]
			}
			return "./"
		}, true)
	case "notdir":
		return mapWords(get(0), func(w string) string {
			return w[strings.LastIndex(w, "/")+1:]
		}, true)
	case "suffix":
		return mapWords(get(0), func(w string) string {
			c := w[strings.LastIndex(w, "/")+1:]
			if i := strings.LastIndex(c, "."); i >= 0 {
				return c[i:]
			}
			return ""
		}, true)
	case "basename":
		return mapWords(get(0), func(w string) string {
			k := strings.LastIndex(w, "/") + 1
			if i := strings.LastIndex(w[k:], "."); i >= 0 {
				return w[:k+i]
			}
			return w
		}, true)
	case "addprefix":
		p := get(0)
		return mapWords(get(1), func(w string) string { return p + w }, true)
	case "addsuffix":
		p := get(0)
		return mapWords(get(1), func(w string) string { return w + p }, true)
	case "wildcard":
		var r []string
		for _, p := range strings.Fields(get(0)) {
			var m []string
			if !strings.ContainsAny(p, "*?") {
				if _, ok := files[p]; ok {
					m = append(m, p)
				}
			} else {
				for n := range files {
					if glob(p, n) {
						m = append(m, n)
					}
				}
				sort.Strings(m)
			}
			r = append(r, m...)
		}
		return strings.Join(r, " ")
	case "foreach":
		v := trim(get(0))
		list := strings.Fields(get(1))
		var r []string
		for _, w := range list {
			bindings = append(bindings, binding{v, w})
			t := ""
			if len(raw) > 2 {
				t = expand(raw[2])
			}
			bindings = bindings[:len(bindings)-1]
			r = append(r, t)
		}
		return strings.Join(r, " ")
	case "if":
		if trim(get(0)) != "" {
			return get(1)
		}
		return get(2)
	case "info":
		fmt.Fprintln(out, get(0))
		return ""
	case "error":
		fatal(get(0))
	}
	return ""
}

// ---------- parsing ----------

type frame struct {
	line         int
	parentActive bool
	cond         bool
	elseSeen     bool
}

// scan for ch outside references, stopping at ';' (unless ch==';')
func topIndex(s string, ch byte, stopSemi bool) int {
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == '$' && i+1 < len(s) {
			d := s[i+1]
			if d == '$' {
				i++
				continue
			}
			if d == '(' || d == '{' {
				cl := byte(')')
				if d == '{' {
					cl = '}'
				}
				depth := 0
				j := i + 1
				for ; j < len(s); j++ {
					if s[j] == d {
						depth++
					} else if s[j] == cl {
						depth--
						if depth == 0 {
							break
						}
					}
				}
				i = j
				continue
			}
			i++
			continue
		}
		if c == ch {
			return i
		}
		if stopSemi && c == ';' {
			return -1
		}
	}
	return -1
}

func stripComment(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) && s[i+1] == '#' {
			b.WriteByte('#')
			i++
		} else if s[i] == '#' {
			break
		} else {
			b.WriteByte(s[i])
		}
	}
	return b.String()
}

func dedupe(a []string) []string {
	seen := map[string]bool{}
	var r []string
	for _, x := range a {
		if !seen[x] {
			seen[x] = true
			r = append(r, x)
		}
	}
	return r
}

func parseMakefile(lines []string, cmdVars map[string]string) {
	vars = map[string]*variable{}
	cmdSet = map[string]bool{}
	expanding = map[string]bool{}
	explicit = map[string]*rule{}
	expOrder = nil
	patterns = nil
	phony = map[string]bool{}
	phonyOrd = nil
	bindings = nil
	autoOn = false
	for k, v := range cmdVars {
		vars[k] = &variable{false, v}
		cmdSet[k] = true
	}
	var stack []frame
	active := func() bool {
		if len(stack) == 0 {
			return true
		}
		t := stack[len(stack)-1]
		return t.parentActive && t.cond
	}
	// open rule
	var open bool
	var rTargets []string
	var rPre, rOrd []string
	var rRec []recLine
	var rLine int
	finalize := func() {
		if !open {
			return
		}
		open = false
		if len(rTargets) == 1 && rTargets[0] == ".PHONY" {
			for _, p := range rPre {
				if !phony[p] {
					phony[p] = true
					phonyOrd = append(phonyOrd, p)
				}
			}
			return
		}
		for _, t := range rTargets {
			if strings.Contains(t, "%") {
				patterns = append(patterns, &patRule{t, rPre, rOrd, rRec})
				continue
			}
			e := explicit[t]
			if e == nil {
				e = &rule{}
				explicit[t] = e
				expOrder = append(expOrder, t)
			}
			e.prereqs = append(e.prereqs, rPre...)
			e.order = append(e.order, rOrd...)
			if len(rRec) > 0 {
				if len(e.recipe) > 0 {
					fmt.Fprintf(out, "Makefile:%d: warning: overriding recipe for target '%s'\n", rLine, t)
				}
				e.recipe = rRec
			}
		}
	}
	n := len(lines)
	for i := 0; i < n; i++ {
		lineNo := i + 1
		cur := lines[i]
		for strings.HasSuffix(cur, "\\") && i+1 < n {
			cur = strings.TrimRight(strings.TrimSuffix(cur, "\\"), " \t")
			i++
			cur += " " + strings.TrimLeft(lines[i], " \t")
		}
		if strings.HasSuffix(cur, "\\") {
			cur = strings.TrimRight(strings.TrimSuffix(cur, "\\"), " \t")
		}
		curLine = lineNo
		if strings.HasPrefix(cur, "\t") {
			text := strings.TrimLeft(cur, "\t")
			if trim(text) == "" {
				continue
			}
			if !active() {
				continue
			}
			if !open {
				fatal("recipe commences before first target")
			}
			rRec = append(rRec, recLine{text, lineNo})
			continue
		}
		line := trim(stripComment(cur))
		if line == "" {
			continue
		}
		word := line
		rest := ""
		if k := strings.IndexAny(line, " \t"); k >= 0 {
			word = line[:k]
			rest = trim(line[k:])
		}
		switch word {
		case "ifdef", "ifndef", "ifeq", "ifneq":
			finalize()
			fr := frame{line: lineNo, parentActive: active()}
			if fr.parentActive {
				switch word {
				case "ifdef", "ifndef":
					nm := trim(expand(rest))
					v, ok := vars[nm]
					def := ok && v.val != ""
					fr.cond = def == (word == "ifdef")
				default:
					if !strings.HasPrefix(rest, "(") || !strings.HasSuffix(rest, ")") {
						fatal("invalid syntax in conditional")
					}
					inner := rest[1 : len(rest)-1]
					parts := splitArgs(inner)
					if len(parts) != 2 {
						fatal("invalid syntax in conditional")
					}
					a := trim(expand(trim(parts[0])))
					b := trim(expand(trim(parts[1])))
					fr.cond = (a == b) == (word == "ifeq")
				}
			}
			stack = append(stack, fr)
			continue
		case "else":
			if rest == "" {
				finalize()
				if len(stack) == 0 || stack[len(stack)-1].elseSeen {
					fatal("extraneous 'else'")
				}
				t := &stack[len(stack)-1]
				t.elseSeen = true
				t.cond = !t.cond
				continue
			}
		case "endif":
			finalize()
			if len(stack) == 0 {
				fatal("extraneous 'endif'")
			}
			stack = stack[:len(stack)-1]
			continue
		}
		if !active() {
			continue
		}
		finalize()
		eq := strings.Index(line, "=")
		col := topIndex(line, ':', true)
		if eq >= 0 && (col < 0 || col > eq || col == eq-1) {
			op := byte('=')
			nameEnd := eq
			if eq > 0 && (line[eq-1] == ':' || line[eq-1] == '?' || line[eq-1] == '+') {
				op = line[eq-1]
				nameEnd = eq - 1
			}
			name := trim(expand(line[:nameEnd]))
			if name == "" {
				fatal("empty variable name")
			}
			val := trim(line[eq+1:])
			if cmdSet[name] {
				continue
			}
			old, exists := vars[name]
			switch op {
			case '=':
				vars[name] = &variable{false, val}
			case ':':
				vars[name] = &variable{true, expand(val)}
			case '?':
				if !exists {
					vars[name] = &variable{false, val}
				}
			case '+':
				if !exists {
					vars[name] = &variable{false, val}
				} else if old.simple {
					nv := expand(val)
					vars[name] = &variable{true, joinSp(old.val, nv)}
				} else {
					vars[name] = &variable{false, joinSp(old.val, val)}
				}
			}
			continue
		}
		if col >= 0 {
			tText := line[:col]
			pText := line[col+1:]
			cmd := ""
			hasCmd := false
			if sp := topIndex(pText, ';', false); sp >= 0 {
				cmd = strings.TrimLeft(pText[sp+1:], " \t")
				hasCmd = true
				pText = pText[:sp]
			}
			targets := strings.Fields(expand(tText))
			pe := expand(pText)
			var pre, ord []string
			if bi := strings.Index(pe, "|"); bi >= 0 {
				pre = strings.Fields(pe[:bi])
				ord = strings.Fields(pe[bi+1:])
			} else {
				pre = strings.Fields(pe)
			}
			open = true
			rTargets, rPre, rOrd, rRec, rLine = targets, pre, ord, nil, lineNo
			if hasCmd && trim(cmd) != "" {
				rRec = append(rRec, recLine{cmd, lineNo})
			}
			continue
		}
		if trim(expand(line)) != "" {
			fatal("missing separator")
		}
	}
	finalize()
	if len(stack) > 0 {
		curLine = stack[len(stack)-1].line
		fatal("missing 'endif'")
	}
	curLine = 0
}

func joinSp(a, b string) string {
	if a == "" || b == "" {
		return a + b
	}
	return a + " " + b
}

// ---------- resolution ----------

type resolved struct {
	found     bool
	prereqs   []string
	order     []string
	recipe    []recLine
	hasRecipe bool
	stem      string
}

func subStem(s, stem string) string { return strings.Replace(s, "%", stem, 1) }

func canMake(n string, d int) bool {
	if _, ok := files[n]; ok {
		return true
	}
	if explicit[n] != nil || phony[n] {
		return true
	}
	if d > 8 {
		return false
	}
	for _, pr := range patterns {
		if len(pr.recipe) == 0 {
			continue
		}
		stem, ok := matchPat(pr.pat, n)
		if !ok || stem == "" {
			continue
		}
		all := true
		for _, p := range append(append([]string{}, pr.prereqs...), pr.order...) {
			if !canMake(subStem(p, stem), d+1) {
				all = false
				break
			}
		}
		if all {
			return true
		}
	}
	return false
}

func resolve(t string) resolved {
	e := explicit[t]
	if e != nil && len(e.recipe) > 0 {
		return resolved{true, e.prereqs, e.order, e.recipe, true, ""}
	}
	for _, pr := range patterns {
		if len(pr.recipe) == 0 {
			continue
		}
		stem, ok := matchPat(pr.pat, t)
		if !ok || stem == "" {
			continue
		}
		all := true
		var pre, ord []string
		for _, p := range pr.prereqs {
			x := subStem(p, stem)
			pre = append(pre, x)
			if !canMake(x, 1) {
				all = false
				break
			}
		}
		if !all {
			continue
		}
		for _, p := range pr.order {
			x := subStem(p, stem)
			ord = append(ord, x)
			if !canMake(x, 1) {
				all = false
				break
			}
		}
		if !all {
			continue
		}
		if e != nil {
			pre = append(pre, e.prereqs...)
			ord = append(ord, e.order...)
		}
		return resolved{true, pre, ord, pr.recipe, true, stem}
	}
	if e != nil {
		return resolved{true, e.prereqs, e.order, nil, false, ""}
	}
	return resolved{}
}

// ---------- building ----------

type memoEnt struct {
	changed bool
	res     resolved
}

var (
	memo   map[string]*memoEnt
	stackN []string
	onStk  map[string]bool
	dry    bool
	ran    int
)

func abort() { panic(abortErr{}) }

func circular(t string) {
	idx := 0
	for i, s := range stackN {
		if s == t {
			idx = i
			break
		}
	}
	p := append(append([]string{}, stackN[idx:]...), t)
	fmt.Fprintf(out, "make: *** Circular dependency detected: %s.  Stop.\n", strings.Join(p, " -> "))
	abort()
}

func update(t, needed string) bool {
	if m, ok := memo[t]; ok {
		return m.changed
	}
	if onStk[t] {
		circular(t)
	}
	res := resolve(t)
	if !res.found {
		if _, ok := files[t]; ok {
			memo[t] = &memoEnt{false, res}
			return false
		}
		if phony[t] {
			memo[t] = &memoEnt{true, res}
			return true
		}
		if needed == "" {
			fmt.Fprintf(out, "make: *** No rule to make target '%s'.  Stop.\n", t)
		} else {
			fmt.Fprintf(out, "make: *** No rule to make target '%s', needed by '%s'.  Stop.\n", t, needed)
		}
		abort()
	}
	stackN = append(stackN, t)
	onStk[t] = true
	mt, inT := files[t]
	pre := dedupe(res.prereqs)
	ord := dedupe(res.order)
	anyCh, newer := false, false
	chm := map[string]bool{}
	for _, p := range pre {
		ch := update(p, t)
		chm[p] = ch
		if ch {
			anyCh = true
		}
		if inT {
			if pm, ok := files[p]; ok && pm > mt {
				newer = true
			}
		}
	}
	for _, o := range ord {
		update(o, t)
	}
	stackN = stackN[:len(stackN)-1]
	delete(onStk, t)
	_, nowIn := files[t]
	changed := false
	if phony[t] || !nowIn || anyCh || newer {
		changed = true
		if res.hasRecipe {
			var q []string
			for _, p := range pre {
				pm, ok := files[p]
				if !inT || chm[p] || (ok && pm > mt) {
					q = append(q, p)
				}
			}
			first := ""
			if len(res.prereqs) > 0 {
				first = res.prereqs[0]
			}
			autoV = map[string]string{"@": t, "<": first, "^": strings.Join(pre, " "), "?": strings.Join(q, " "), "|": strings.Join(ord, " "), "*": res.stem}
			runRecipe(t, res)
		}
	}
	memo[t] = &memoEnt{changed, res}
	return changed
}

func runRecipe(t string, res resolved) {
	ran++
	for _, l := range res.recipe {
		curLine = l.no
		autoOn = true
		cmd := trim(expand(l.text))
		autoOn = false
		silent, ignore := false, false
		for len(cmd) > 0 && (cmd[0] == '@' || cmd[0] == '-' || cmd[0] == '+' || isWS(cmd[0])) {
			if cmd[0] == '@' {
				silent = true
			} else if cmd[0] == '-' {
				ignore = true
			}
			cmd = cmd[1:]
		}
		cmd = trim(cmd)
		if dry {
			fmt.Fprintln(out, cmd)
			continue
		}
		if !silent {
			fmt.Fprintln(out, cmd)
		}
		w := strings.Fields(cmd)
		status := 0
		if len(w) > 0 {
			switch w[0] {
			case "false":
				status = 1
			case "exit":
				if len(w) > 1 {
					if v, err := strconv.Atoi(w[1]); err == nil {
						status = v
					} else {
						status = 2
					}
				}
			case "touch":
				for _, a := range w[1:] {
					if !strings.HasPrefix(a, "-") {
						clock++
						files[a] = clock
					}
				}
			case "rm":
				for _, a := range w[1:] {
					if !strings.HasPrefix(a, "-") {
						delete(files, a)
					}
				}
			case "cp":
				if len(w) == 3 {
					if _, ok := files[w[1]]; !ok {
						fmt.Fprintf(out, "cp: cannot stat '%s': No such file or directory\n", w[1])
						status = 1
					} else {
						clock++
						files[w[2]] = clock
					}
				}
			case "echo":
				var r []string
				for _, a := range w[1:] {
					a = strings.NewReplacer("'", "", "\"", "").Replace(a)
					r = append(r, a)
				}
				fmt.Fprintln(out, strings.Join(r, " "))
			}
		}
		if status != 0 {
			if ignore {
				fmt.Fprintf(out, "make: [Makefile:%d: %s] Error %d (ignored)\n", l.no, t, status)
			} else {
				fmt.Fprintf(out, "make: *** [Makefile:%d: %s] Error %d\n", l.no, t, status)
				abort()
			}
		}
	}
	if !phony[t] && !dry {
		clock++
		files[t] = clock
	}
}

func defaultGoal() string {
	for _, t := range expOrder {
		if !strings.HasPrefix(t, ".") {
			return t
		}
	}
	return ""
}

// ---------- deps ----------

func depsReq(t string) {
	var order []string
	done := map[string]bool{}
	stackN = nil
	onStk = map[string]bool{}
	var visit func(n string, top bool)
	visit = func(n string, top bool) {
		if onStk[n] {
			circular(n)
		}
		if done[n] {
			return
		}
		onStk[n] = true
		stackN = append(stackN, n)
		res := resolve(n)
		for _, p := range dedupe(res.prereqs) {
			visit(p, false)
		}
		for _, p := range dedupe(res.order) {
			visit(p, false)
		}
		stackN = stackN[:len(stackN)-1]
		delete(onStk, n)
		done[n] = true
		if !top {
			order = append(order, n)
		}
	}
	visit(t, true)
	if len(order) == 0 {
		fmt.Fprintln(out, "(no prerequisites)")
		return
	}
	for _, n := range order {
		fmt.Fprintln(out, n)
	}
}

func fmtRule(prefix string, pre, ord []string) string {
	s := prefix + ":"
	for _, p := range pre {
		s += " " + p
	}
	if len(ord) > 0 {
		s += " |"
		for _, o := range ord {
			s += " " + o
		}
	}
	return s
}

// ---------- main ----------

var mfLines []string

func protect(f func()) {
	defer func() {
		if r := recover(); r != nil {
			switch e := r.(type) {
			case fatalErr:
				printFatal(e.msg)
			case abortErr:
			default:
				panic(r)
			}
		}
	}()
	f()
}

func splitVarArgs(args []string) (map[string]string, []string) {
	cv := map[string]string{}
	var goals []string
	for _, a := range args {
		if i := strings.Index(a, "="); i > 0 {
			cv[a[:i]] = a[i+1:]
		} else {
			goals = append(goals, a)
		}
	}
	return cv, goals
}

func handle(line string) {
	t := strings.TrimLeft(line, " \t")
	word := t
	rest := ""
	if k := strings.IndexAny(t, " \t"); k >= 0 {
		word = t[:k]
		rest = trim(t[k:])
	}
	args := strings.Fields(rest)
	switch word {
	case "build", "dry":
		cv, goals := splitVarArgs(args)
		dry = word == "dry"
		protect(func() {
			parseMakefile(mfLines, cv)
			if len(goals) == 0 {
				g := defaultGoal()
				if g == "" {
					fmt.Fprintln(out, "make: *** No targets.  Stop.")
					return
				}
				goals = []string{g}
			}
			memo = map[string]*memoEnt{}
			onStk = map[string]bool{}
			stackN = nil
			for _, g := range goals {
				before := ran
				update(g, "")
				if ran == before {
					m := memo[g]
					_, inT := files[g]
					if m.res.hasRecipe || (!phony[g] && inT) {
						fmt.Fprintf(out, "make: '%s' is up to date.\n", g)
					} else {
						fmt.Fprintf(out, "make: Nothing to be done for '%s'.\n", g)
					}
				}
			}
		})
	case "deps":
		cv, goals := splitVarArgs(args)
		if len(goals) != 1 {
			fmt.Fprintln(out, "usage: deps TARGET")
			return
		}
		protect(func() {
			parseMakefile(mfLines, cv)
			depsReq(goals[0])
		})
	case "targets":
		cv, _ := splitVarArgs(args)
		protect(func() {
			parseMakefile(mfLines, cv)
			if g := defaultGoal(); g != "" {
				fmt.Fprintln(out, "default: "+g)
			}
			for _, t := range expOrder {
				e := explicit[t]
				fmt.Fprintln(out, fmtRule(t, e.prereqs, e.order))
			}
			for _, p := range patterns {
				fmt.Fprintln(out, fmtRule("pattern "+p.pat, p.prereqs, p.order))
			}
			if len(phonyOrd) > 0 {
				fmt.Fprintln(out, "phony: "+strings.Join(phonyOrd, " "))
			}
		})
	case "expand":
		protect(func() {
			parseMakefile(mfLines, nil)
			curLine = 0
			fmt.Fprintf(out, "[%s]\n", expand(rest))
		})
	case "files":
		if len(files) == 0 {
			fmt.Fprintln(out, "(no files)")
			return
		}
		var names []string
		for n := range files {
			names = append(names, n)
		}
		sort.Strings(names)
		for _, n := range names {
			fmt.Fprintf(out, "%s %d\n", n, files[n])
		}
	case "touch":
		if len(args) == 1 {
			clock++
			files[args[0]] = clock
		} else if len(args) == 2 {
			v, err := strconv.ParseInt(args[1], 10, 64)
			if err != nil {
				fmt.Fprintln(out, "bad request")
				return
			}
			files[args[0]] = v
			if v > clock {
				clock = v
			}
		} else {
			fmt.Fprintln(out, "bad request")
		}
	case "rm":
		for _, a := range args {
			delete(files, a)
		}
	default:
		fmt.Fprintf(out, "unknown request: %s\n", word)
	}
}

func main() {
	out = bufio.NewWriter(os.Stdout)
	defer out.Flush()
	data, _ := io.ReadAll(os.Stdin)
	text := strings.ReplaceAll(string(data), "\r\n", "\n")
	all := strings.Split(text, "\n")
	if len(all) > 0 && all[len(all)-1] == "" {
		all = all[:len(all)-1]
	}
	var secs [3][]string
	s := 0
	for _, l := range all {
		l = strings.TrimSuffix(l, "\r")
		if l == "====" && s < 2 {
			s++
			continue
		}
		secs[s] = append(secs[s], l)
	}
	mfLines = secs[0]
	for _, l := range secs[1] {
		f := strings.Fields(l)
		if len(f) != 2 {
			continue
		}
		v, err := strconv.ParseInt(f[1], 10, 64)
		if err != nil || v < 0 {
			continue
		}
		files[f[0]] = v
		if v > clock {
			clock = v
		}
	}
	for _, l := range secs[2] {
		t := strings.TrimSpace(l)
		if t == "" || t[0] == '#' {
			continue
		}
		fmt.Fprintln(out, "> "+strings.TrimRight(l, " \t\r\n"))
		handle(l)
	}
}

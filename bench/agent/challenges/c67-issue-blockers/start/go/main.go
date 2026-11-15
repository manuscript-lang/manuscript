package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

var out *bufio.Writer

func pr(format string, a ...interface{}) {
	fmt.Fprintf(out, format+"\n", a...)
}

// ---------- model ----------

var prios = []string{"low", "medium", "high", "critical"}

type vals struct {
	title  string
	prio   int
	asg    string
	hasAsg bool
	points int // -1 absent
	due    string
	labels []string
	rep    string
	hasRep bool
}

type comment struct {
	t     int
	actor string
	text  string
}

type change struct {
	t     int
	state string
}

type Issue struct {
	vals
	id       int
	state    string
	comments []comment
	created  int
	updated  int
	changes  []change
}

type logEntry struct {
	t      int
	actor  string
	id     int
	detail string
}

type transition struct {
	dst    string
	guards []string
}

type Workflow struct {
	states  []string
	idx     map[string]int
	initial string
	final   map[string]bool
	trans   map[string][]transition
}

var (
	clock   int
	actor   = "system"
	today   = "1970-01-01"
	wf      *Workflow
	issues  = map[int]*Issue{}
	nextID  = 1
	logs    []logEntry
	views   = map[string]string{}
	created bool
)

func addLog(id int, detail string) {
	logs = append(logs, logEntry{clock, actor, id, detail})
}

// ---------- helpers ----------

func isSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\v' || c == '\f'
}

func restAfter(s string, n int) string {
	i := 0
	for k := 0; k < n; k++ {
		for i < len(s) && isSpace(s[i]) {
			i++
		}
		for i < len(s) && !isSpace(s[i]) {
			i++
		}
	}
	for i < len(s) && isSpace(s[i]) {
		i++
	}
	return s[i:]
}

func tokenize(s string) ([]string, bool) {
	var toks []string
	var cur []byte
	in := false
	q := false
	for i := 0; i < len(s); i++ {
		c := s[i]
		if q {
			if c == '\\' && i+1 < len(s) && (s[i+1] == '"' || s[i+1] == '\\') {
				cur = append(cur, s[i+1])
				i++
			} else if c == '"' {
				q = false
			} else {
				cur = append(cur, c)
			}
			continue
		}
		if isSpace(c) {
			if in {
				toks = append(toks, string(cur))
				cur = cur[:0]
				in = false
			}
			continue
		}
		in = true
		if c == '"' {
			q = true
		} else {
			cur = append(cur, c)
		}
	}
	if q {
		return nil, false
	}
	if in {
		toks = append(toks, string(cur))
	}
	return toks, true
}

func parseInt(s string) (int, bool) {
	if s == "" || len(s) > 7 {
		return 0, false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return 0, false
		}
	}
	if len(s) > 1 && s[0] == '0' {
		return 0, false
	}
	n, _ := strconv.Atoi(s)
	if n > 1000000 {
		return 0, false
	}
	return n, true
}

func validDate(s string) bool {
	if len(s) != 10 || s[4] != '-' || s[7] != '-' {
		return false
	}
	for i := 0; i < 10; i++ {
		if i == 4 || i == 7 {
			continue
		}
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	y, _ := strconv.Atoi(s[0:4])
	m, _ := strconv.Atoi(s[5:7])
	d, _ := strconv.Atoi(s[8:10])
	if y < 1 || m < 1 || m > 12 || d < 1 {
		return false
	}
	dm := []int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	if m == 2 && (y%4 == 0 && (y%100 != 0 || y%400 == 0)) {
		return d <= 29
	}
	return d <= dm[m-1]
}

func validLabel(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_' || c == '-') {
			return false
		}
	}
	return true
}

func validState(s string) bool {
	if s == "" || !(s[0] >= 'a' && s[0] <= 'z') {
		return false
	}
	for i := 1; i < len(s); i++ {
		c := s[i]
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_') {
			return false
		}
	}
	return true
}

func normLabels(ls []string) []string {
	m := map[string]bool{}
	var r []string
	for _, l := range ls {
		if !m[l] {
			m[l] = true
			r = append(r, l)
		}
	}
	sort.Strings(r)
	return r
}

func dash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

func (v *vals) asgS() string {
	if v.hasAsg {
		return v.asg
	}
	return "-"
}
func (v *vals) repS() string {
	if v.hasRep {
		return v.rep
	}
	return "-"
}
func (v *vals) ptsS() string {
	if v.points < 0 {
		return "-"
	}
	return strconv.Itoa(v.points)
}
func (v *vals) labS() string { return dash(strings.Join(v.labels, ",")) }

func parseIssueID(arg string) (int, string) {
	s := strings.TrimPrefix(arg, "#")
	ok := s != ""
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			ok = false
		}
	}
	if ok {
		s = strings.TrimLeft(s, "0")
		if s == "" {
			ok = false
		}
	}
	if !ok {
		return 0, fmt.Sprintf("bad issue id '%s'", arg)
	}
	if len(s) > 12 {
		return 0, fmt.Sprintf("no such issue #%s", s)
	}
	n, _ := strconv.Atoi(s)
	return n, ""
}

func findIssue(arg string) (*Issue, string) {
	n, e := parseIssueID(arg)
	if e != "" {
		return nil, e
	}
	iss := issues[n]
	if iss == nil {
		return nil, fmt.Sprintf("no such issue #%d", n)
	}
	return iss, ""
}

func (w *Workflow) isFinal(s string) bool { return w != nil && w.final[s] }

// ---------- field parsing ----------

func parseField(tok string, v *vals) string {
	i := strings.Index(tok, "=")
	if i <= 0 {
		return fmt.Sprintf("expected field=value, got '%s'", tok)
	}
	f, val := tok[:i], tok[i+1:]
	switch f {
	case "state":
		return "use move to change state"
	case "title":
		if strings.TrimSpace(val) == "" {
			return "empty title"
		}
		v.title = val
	case "priority":
		p := prioRank(val)
		if p < 0 {
			return fmt.Sprintf("bad priority '%s'", val)
		}
		v.prio = p
	case "assignee":
		if val == "none" {
			v.asg, v.hasAsg = "", false
		} else if strings.TrimSpace(val) == "" {
			return "empty assignee"
		} else {
			v.asg, v.hasAsg = val, true
		}
	case "reporter":
		if val == "none" {
			v.rep, v.hasRep = "", false
		} else if strings.TrimSpace(val) == "" {
			return "empty reporter"
		} else {
			v.rep, v.hasRep = val, true
		}
	case "points":
		if val == "none" {
			v.points = -1
		} else if n, ok := parseInt(val); ok {
			v.points = n
		} else {
			return fmt.Sprintf("bad points '%s'", val)
		}
	case "due":
		if val == "none" {
			v.due = ""
		} else if validDate(val) {
			v.due = val
		} else {
			return fmt.Sprintf("bad date '%s'", val)
		}
	case "labels":
		if val == "none" {
			v.labels = nil
		} else {
			var ls []string
			for _, l := range strings.Split(val, ",") {
				l = strings.ToLower(l)
				if !validLabel(l) {
					return fmt.Sprintf("bad label '%s'", l)
				}
				ls = append(ls, l)
			}
			v.labels = normLabels(ls)
		}
	default:
		return fmt.Sprintf("unknown field '%s'", f)
	}
	return ""
}

func diffs(old, nw *vals) []string {
	var r []string
	add := func(f, a, b string) {
		if a != b {
			r = append(r, fmt.Sprintf("%s: %s -> %s", f, a, b))
		}
	}
	add("title", old.title, nw.title)
	add("priority", prios[old.prio], prios[nw.prio])
	add("assignee", old.asgS(), nw.asgS())
	add("points", old.ptsS(), nw.ptsS())
	add("due", dash(old.due), dash(nw.due))
	add("labels", old.labS(), nw.labS())
	add("reporter", old.repS(), nw.repS())
	return r
}

// ---------- single commands ----------

func finalErr(iss *Issue) string {
	if wf.isFinal(iss.state) {
		return fmt.Sprintf("#%d is in final state '%s'", iss.id, iss.state)
	}
	return ""
}

func doEdit(iss *Issue, toks []string) (string, string) {
	if e := finalErr(iss); e != "" {
		return "", e
	}
	nv := iss.vals
	for _, t := range toks {
		if e := parseField(t, &nv); e != "" {
			return "", e
		}
	}
	return applyVals(iss, &nv)
}

func applyVals(iss *Issue, nv *vals) (string, string) {
	d := diffs(&iss.vals, nv)
	if len(d) == 0 {
		return fmt.Sprintf("#%d unchanged", iss.id), ""
	}
	clock++
	iss.vals = *nv
	iss.updated = clock
	for _, x := range d {
		addLog(iss.id, x)
	}
	return fmt.Sprintf("updated #%d", iss.id), ""
}

func doLabel(iss *Issue, ops []string) (string, string) {
	if e := finalErr(iss); e != "" {
		return "", e
	}
	set := map[string]bool{}
	for _, l := range iss.labels {
		set[l] = true
	}
	for _, o := range ops {
		rem := false
		if strings.HasPrefix(o, "+") {
			o = o[1:]
		} else if strings.HasPrefix(o, "-") {
			o = o[1:]
			rem = true
		}
		o = strings.ToLower(o)
		if !validLabel(o) {
			return "", fmt.Sprintf("bad label '%s'", o)
		}
		if rem {
			delete(set, o)
		} else {
			set[o] = true
		}
	}
	var ls []string
	for l := range set {
		ls = append(ls, l)
	}
	sort.Strings(ls)
	nv := iss.vals
	nv.labels = ls
	return applyVals(iss, &nv)
}

func doMove(iss *Issue, st string, cmt string, hasCmt bool) (string, string) {
	if e := finalErr(iss); e != "" {
		return "", e
	}
	if wf == nil || !hasState(st) {
		return "", fmt.Sprintf("unknown state '%s'", st)
	}
	if iss.state == st {
		return "", fmt.Sprintf("already in state '%s'", st)
	}
	var tr *transition
	for k := range wf.trans[iss.state] {
		if wf.trans[iss.state][k].dst == st {
			tr = &wf.trans[iss.state][k]
			break
		}
	}
	if tr == nil {
		return "", fmt.Sprintf("transition '%s -> %s' not allowed", iss.state, st)
	}
	var miss []string
	for _, g := range tr.guards {
		bad := false
		switch g {
		case "assignee":
			bad = !iss.hasAsg
		case "points":
			bad = iss.points < 0
		case "due":
			bad = iss.due == ""
		case "labels":
			bad = len(iss.labels) == 0
		case "reporter":
			bad = !iss.hasRep
		}
		if bad {
			miss = append(miss, g)
		}
	}
	if len(miss) > 0 {
		return "", fmt.Sprintf("cannot move #%d to %s: missing %s", iss.id, st, strings.Join(miss, ", "))
	}
	clock++
	old := iss.state
	iss.state = st
	iss.updated = clock
	iss.changes = append(iss.changes, change{clock, st})
	addLog(iss.id, fmt.Sprintf("state: %s -> %s", old, st))
	if hasCmt {
		iss.comments = append(iss.comments, comment{clock, actor, cmt})
		addLog(iss.id, "comment: "+cmt)
	}
	return fmt.Sprintf("moved #%d: %s -> %s", iss.id, old, st), ""
}

func cmdCreate(line string) {
	if wf == nil {
		pr("error: no workflow defined")
		return
	}
	toks, ok := tokenize(restAfter(line, 1))
	if !ok {
		pr("error: unterminated quote")
		return
	}
	if len(toks) == 0 {
		pr("error: usage: create TITLE [field=value...]")
		return
	}
	if strings.TrimSpace(toks[0]) == "" {
		pr("error: empty title")
		return
	}
	v := vals{title: toks[0], prio: 1, points: -1, rep: actor, hasRep: true}
	given := map[string]bool{}
	for _, t := range toks[1:] {
		if e := parseField(t, &v); e != "" {
			pr("error: %s", e)
			return
		}
		given[t[:strings.Index(t, "=")]] = true
	}
	def := vals{title: toks[0], prio: 1, points: -1}
	var d []string
	for _, x := range diffs(&def, &v) {
		f := x[:strings.Index(x, ":")]
		if given[f] {
			d = append(d, x)
		}
	}
	clock++
	iss := &Issue{vals: v, id: nextID, state: wf.initial, created: clock, updated: clock}
	nextID++
	created = true
	issues[iss.id] = iss
	addLog(iss.id, fmt.Sprintf("created \"%s\"", toks[0]))
	for _, x := range d {
		addLog(iss.id, x)
	}
	pr("created #%d", iss.id)
}

func report(o, e string) {
	if e != "" {
		pr("error: %s", e)
	} else {
		pr("%s", o)
	}
}

func cmdEdit(line string) {
	toks, ok := tokenize(restAfter(line, 1))
	if !ok {
		pr("error: unterminated quote")
		return
	}
	if len(toks) == 0 {
		pr("error: usage: edit ID field=value...")
		return
	}
	iss, e := findIssue(toks[0])
	if e != "" {
		pr("error: %s", e)
		return
	}
	if e := finalErr(iss); e != "" {
		pr("error: %s", e)
		return
	}
	nv := iss.vals
	for _, t := range toks[1:] {
		if e := parseField(t, &nv); e != "" {
			pr("error: %s", e)
			return
		}
	}
	if len(toks) == 1 {
		pr("error: usage: edit ID field=value...")
		return
	}
	report(applyVals(iss, &nv))
}

func cmdLabel(line string) {
	toks, ok := tokenize(restAfter(line, 1))
	if !ok {
		pr("error: unterminated quote")
		return
	}
	if len(toks) < 2 {
		pr("error: usage: label ID +label -label...")
		return
	}
	iss, e := findIssue(toks[0])
	if e != "" {
		pr("error: %s", e)
		return
	}
	report(doLabel(iss, toks[1:]))
}

func cmdAssign(line string) {
	toks, ok := tokenize(restAfter(line, 1))
	if !ok {
		pr("error: unterminated quote")
		return
	}
	if len(toks) != 2 {
		pr("error: usage: assign ID NAME")
		return
	}
	iss, e := findIssue(toks[0])
	if e != "" {
		pr("error: %s", e)
		return
	}
	report(doEdit(iss, []string{"assignee=" + toks[1]}))
}

func cmdMove(line string) {
	w := strings.Fields(line)[1:]
	if len(w) < 2 {
		pr("error: usage: move ID STATE [comment...]")
		return
	}
	iss, e := findIssue(w[0])
	if e != "" {
		pr("error: %s", e)
		return
	}
	cm := restAfter(line, 3)
	report(doMove(iss, w[1], cm, len(w) > 2))
}

func cmdComment(line string) {
	w := strings.Fields(line)[1:]
	if len(w) < 2 {
		pr("error: usage: comment ID TEXT")
		return
	}
	iss, e := findIssue(w[0])
	if e != "" {
		pr("error: %s", e)
		return
	}
	text := restAfter(line, 2)
	clock++
	iss.updated = clock
	iss.comments = append(iss.comments, comment{clock, actor, text})
	addLog(iss.id, "comment: "+text)
	pr("commented #%d", iss.id)
}

func cmdDelete(line string) {
	w := strings.Fields(line)[1:]
	if len(w) != 1 {
		pr("error: usage: delete ID")
		return
	}
	iss, e := findIssue(w[0])
	if e != "" {
		pr("error: %s", e)
		return
	}
	clock++
	delete(issues, iss.id)
	addLog(iss.id, "deleted")
	pr("deleted #%d", iss.id)
}

func cmdShow(line string) {
	w := strings.Fields(line)[1:]
	if len(w) != 1 {
		pr("error: usage: show ID")
		return
	}
	iss, e := findIssue(w[0])
	if e != "" {
		pr("error: %s", e)
		return
	}
	pr("#%d %s", iss.id, iss.title)
	pr("  state: %s", iss.state)
	pr("  priority: %s", prios[iss.prio])
	pr("  assignee: %s", iss.asgS())
	pr("  points: %s", iss.ptsS())
	pr("  due: %s", dash(iss.due))
	pr("  labels: %s", dash(strings.Join(iss.labels, ", ")))
	pr("  reporter: %s", iss.repS())
	pr("  created: t=%d, updated: t=%d", iss.created, iss.updated)
	pr("  comments: %d", len(iss.comments))
	for _, c := range iss.comments {
		pr("    [t=%d %s] %s", c.t, c.actor, c.text)
	}
}

func cmdLog(line string) {
	w := strings.Fields(line)[1:]
	id := -1
	tail := -1
	if len(w) > 0 && w[0] != "tail" {
		n, e := parseIssueID(w[0])
		if e != "" {
			pr("error: %s", e)
			return
		}
		if n >= nextID {
			pr("error: no such issue #%d", n)
			return
		}
		id = n
		w = w[1:]
	}
	if len(w) > 0 {
		if w[0] != "tail" || len(w) != 2 {
			pr("error: usage: log [ID] [tail N]")
			return
		}
		n, ok := parseInt(w[1])
		if !ok {
			pr("error: bad tail '%s'", w[1])
			return
		}
		tail = n
	}
	var sel []logEntry
	for _, l := range logs {
		if id < 0 || l.id == id {
			sel = append(sel, l)
		}
	}
	if tail >= 0 && tail < len(sel) {
		sel = sel[len(sel)-tail:]
	}
	if len(sel) == 0 {
		pr("(no log entries)")
		return
	}
	for _, l := range sel {
		pr("t=%d %s #%d %s", l.t, l.actor, l.id, l.detail)
	}
}

// ---------- workflow ----------

func cmdWorkflow(lines []string, i *int) {
	var block []string
	for *i < len(lines) {
		l := strings.TrimSpace(lines[*i])
		*i++
		if l == "end" {
			break
		}
		block = append(block, l)
	}
	if created {
		pr("error: workflow: cannot redefine after issues were created")
		return
	}
	nw := &Workflow{idx: map[string]int{}, final: map[string]bool{}, trans: map[string][]transition{}}
	seen := func(s string) {
		if _, ok := nw.idx[s]; !ok {
			nw.idx[s] = len(nw.states)
			nw.states = append(nw.states, s)
		}
	}
	errMsg := ""
	hasInit := false
	nt := 0
	var srcs []string
	for _, l := range block {
		if l == "" || l[0] == '#' {
			continue
		}
		if strings.HasPrefix(l, "initial:") {
			n := strings.TrimSpace(l[8:])
			if !validState(n) {
				errMsg = fmt.Sprintf("workflow: bad state name '%s'", n)
				break
			}
			if hasInit {
				errMsg = "workflow: initial state defined twice"
				break
			}
			hasInit = true
			nw.initial = n
			seen(n)
		} else if strings.HasPrefix(l, "final:") {
			bad := false
			for _, n := range strings.Split(l[6:], ",") {
				n = strings.TrimSpace(n)
				if !validState(n) {
					errMsg = fmt.Sprintf("workflow: bad state name '%s'", n)
					bad = true
					break
				}
				seen(n)
				nw.final[n] = true
			}
			if bad {
				break
			}
		} else if k := strings.Index(l, "->"); k >= 0 {
			src := strings.TrimSpace(l[:k])
			if !validState(src) {
				errMsg = fmt.Sprintf("workflow: bad state name '%s'", src)
				break
			}
			seen(src)
			srcs = append(srcs, src)
			bad := false
			var trs []transition
			for _, ent := range strings.Split(l[k+2:], ",") {
				f := strings.Fields(ent)
				if len(f) == 0 || len(f) == 2 || len(f) > 3 || (len(f) == 3 && f[1] != "requires") {
					errMsg = fmt.Sprintf("workflow: bad line '%s'", l)
					bad = true
					break
				}
				if !validState(f[0]) {
					errMsg = fmt.Sprintf("workflow: bad state name '%s'", f[0])
					bad = true
					break
				}
				seen(f[0])
				tr := transition{dst: f[0]}
				if len(f) == 3 {
					for _, g := range strings.Split(f[2], "+") {
						switch g {
						case "assignee", "points", "due", "labels", "reporter":
							tr.guards = append(tr.guards, g)
						default:
							errMsg = fmt.Sprintf("workflow: bad guard field '%s'", g)
							bad = true
						}
						if bad {
							break
						}
					}
					if bad {
						break
					}
				}
				trs = append(trs, tr)
			}
			if bad {
				break
			}
			nw.trans[src] = append(nw.trans[src], trs...)
			nt += len(trs)
		} else {
			errMsg = fmt.Sprintf("workflow: bad line '%s'", l)
			break
		}
	}
	if errMsg == "" && !hasInit {
		errMsg = "workflow: initial state missing"
	}
	if errMsg == "" {
		for _, s := range srcs {
			if nw.final[s] {
				errMsg = fmt.Sprintf("workflow: '%s' is final and cannot have transitions", s)
				break
			}
		}
	}
	if errMsg != "" {
		pr("error: %s", errMsg)
		return
	}
	wf = nw
	pr("workflow ok: %d states, %d transitions", len(nw.states), nt)
}

// ---------- queries ----------

type qerr struct{ msg string }

type node func(*Issue) bool

type parser struct {
	s     string
	pos   int
	refs  map[string]bool
	depth int
}

type tok struct {
	kind   int // 0 end, 1 '(', 2 ')', 3 word, 4 term
	text   string
	field  string
	op     string
	val    string
	quoted bool
}

func (p *parser) skipWS() {
	for p.pos < len(p.s) && isSpace(p.s[p.pos]) {
		p.pos++
	}
}

func (p *parser) peek() (tok, int, *qerr) {
	save := p.pos
	t, e := p.next()
	np := p.pos
	p.pos = save
	return t, np, e
}

func (p *parser) next() (tok, *qerr) {
	p.skipWS()
	if p.pos >= len(p.s) {
		return tok{kind: 0}, nil
	}
	c := p.s[p.pos]
	if c == '(' {
		p.pos++
		return tok{kind: 1, text: "("}, nil
	}
	if c == ')' {
		p.pos++
		return tok{kind: 2, text: ")"}, nil
	}
	start := p.pos
	i := p.pos
	for i < len(p.s) && (p.s[i] >= 'a' && p.s[i] <= 'z' || p.s[i] == '_') {
		i++
	}
	if i > start && i < len(p.s) {
		op := ""
		rest := p.s[i:]
		for _, o := range []string{"!=", "<=", ">=", ":", "<", ">", "~"} {
			if strings.HasPrefix(rest, o) {
				op = o
				break
			}
		}
		if op != "" {
			field := p.s[start:i]
			j := i + len(op)
			if j < len(p.s) && p.s[j] == '"' {
				j++
				var b []byte
				closed := false
				for j < len(p.s) {
					ch := p.s[j]
					if ch == '\\' && j+1 < len(p.s) && (p.s[j+1] == '"' || p.s[j+1] == '\\') {
						b = append(b, p.s[j+1])
						j += 2
						continue
					}
					if ch == '"' {
						closed = true
						j++
						break
					}
					b = append(b, ch)
					j++
				}
				if !closed {
					p.pos = len(p.s)
					return tok{}, &qerr{"query: unterminated quote"}
				}
				p.pos = j
				return tok{kind: 4, field: field, op: op, val: string(b), quoted: true}, nil
			}
			for j < len(p.s) && !isSpace(p.s[j]) && p.s[j] != '(' && p.s[j] != ')' {
				j++
			}
			p.pos = j
			return tok{kind: 4, field: field, op: op, val: p.s[i+len(op) : j]}, nil
		}
	}
	j := start
	for j < len(p.s) && !isSpace(p.s[j]) && p.s[j] != '(' && p.s[j] != ')' {
		j++
	}
	if j == start {
		j++
	}
	p.pos = j
	return tok{kind: 3, text: p.s[start:j]}, nil
}

func unexpected(t tok) *qerr {
	if t.kind == 0 {
		return &qerr{"query: unexpected end of query"}
	}
	if t.kind == 4 {
		return &qerr{"query: unexpected token '" + t.field + t.op + t.val + "'"}
	}
	return &qerr{"query: unexpected token '" + t.text + "'"}
}

func (p *parser) parseOr() (node, *qerr) {
	l, e := p.parseAnd()
	if e != nil {
		return nil, e
	}
	for {
		t, np, e := p.peek()
		if e != nil {
			return nil, e
		}
		if t.kind == 3 && t.text == "OR" {
			p.pos = np
			r, e := p.parseAnd()
			if e != nil {
				return nil, e
			}
			a, b := l, r
			l = func(i *Issue) bool { return a(i) || b(i) }
		} else {
			return l, nil
		}
	}
}

func (p *parser) parseAnd() (node, *qerr) {
	l, e := p.parseNot()
	if e != nil {
		return nil, e
	}
	for {
		t, np, e := p.peek()
		if e != nil {
			return nil, e
		}
		if t.kind == 3 && t.text == "AND" {
			p.pos = np
		} else if t.kind == 1 || t.kind == 4 || (t.kind == 3 && t.text == "NOT") {
		} else {
			return l, nil
		}
		r, e := p.parseNot()
		if e != nil {
			return nil, e
		}
		a, b := l, r
		l = func(i *Issue) bool { return a(i) && b(i) }
	}
}

func (p *parser) parseNot() (node, *qerr) {
	t, e := p.next()
	if e != nil {
		return nil, e
	}
	switch {
	case t.kind == 3 && t.text == "NOT":
		n, e := p.parseNot()
		if e != nil {
			return nil, e
		}
		return func(i *Issue) bool { return !n(i) }, nil
	case t.kind == 1:
		n, e := p.parseOr()
		if e != nil {
			return nil, e
		}
		c, e := p.next()
		if e != nil {
			return nil, e
		}
		if c.kind != 2 {
			return nil, unexpected(c)
		}
		return n, nil
	case t.kind == 4:
		return p.compileTerm(t)
	}
	return nil, unexpected(t)
}

func parseFilter(text string) (node, map[string]bool, *qerr) {
	return parseFilterD(text, 0)
}

func parseFilterD(text string, depth int) (node, map[string]bool, *qerr) {
	p := &parser{s: text, refs: map[string]bool{}, depth: depth}
	if strings.TrimSpace(text) == "" {
		return func(*Issue) bool { return true }, p.refs, nil
	}
	n, e := p.parseOr()
	if e != nil {
		return nil, nil, e
	}
	t, e := p.next()
	if e != nil {
		return nil, nil, e
	}
	if t.kind != 0 {
		return nil, nil, unexpected(t)
	}
	return n, p.refs, nil
}

func prioRank(s string) int {
	for k, n := range prios {
		if n == s {
			return k
		}
	}
	return -1
}

func cmpInt(a, b int) int {
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}

func okCmp(op string, c int) bool {
	switch op {
	case "<":
		return c < 0
	case "<=":
		return c <= 0
	case ">":
		return c > 0
	case ">=":
		return c >= 0
	case ":":
		return c == 0
	case "!=":
		return c != 0
	}
	return false
}

func hasState(s string) bool {
	if wf == nil {
		return false
	}
	_, ok := wf.idx[s]
	return ok
}

func val2(ordered bool, whole, alt string) string {
	if ordered {
		return whole
	}
	return alt
}

func finish(n int, neg bool, f func(i *Issue, k int) bool) node {
	return func(i *Issue) bool {
		any := false
		for k := 0; k < n; k++ {
			if f(i, k) {
				any = true
				break
			}
		}
		if neg {
			return !any
		}
		return any
	}
}

func (p *parser) compileTerm(t tok) (node, *qerr) {
	field, op, val := t.field, t.op, t.val
	const cmpOps = ":,!=,<,<=,>,>="
	allowed := map[string]string{
		"id": cmpOps, "created": cmpOps, "updated": cmpOps,
		"points": cmpOps, "due": cmpOps, "priority": cmpOps,
		"title": ":,!=,~", "assignee": ":,!=,~", "reporter": ":,!=,~",
		"text": "~", "state": ":,!=", "label": ":,!=,~", "labels": ":,!=,~",
		"is": ":", "has": ":", "view": ":",
	}
	al, ok := allowed[field]
	if !ok {
		return nil, &qerr{fmt.Sprintf("query: unknown field '%s'", field)}
	}
	okop := false
	for _, o := range strings.Split(al, ",") {
		if o == op {
			okop = true
		}
	}
	if !okop {
		return nil, &qerr{fmt.Sprintf("query: bad operator '%s' for field '%s'", op, field)}
	}
	bad := func(v string) *qerr {
		return &qerr{fmt.Sprintf("query: bad value '%s' for field '%s'", v, field)}
	}
	if field == "view" {
		q, ok := views[val]
		if !ok || p.depth > 50 {
			return nil, &qerr{fmt.Sprintf("query: unknown view '%s'", val)}
		}
		p.refs[val] = true
		f, _, _, _, _ := splitQ(q)
		n, refs, e := parseFilterD(f, p.depth+1)
		if e != nil {
			return nil, e
		}
		for r := range refs {
			p.refs[r] = true
		}
		return n, nil
	}
	ordered := op == "<" || op == "<=" || op == ">" || op == ">="
	alts := []string{val}
	if !t.quoted && !ordered && strings.Contains(val, "|") {
		alts = strings.Split(val, "|")
	}
	neg := op == "!="
	cop := op
	if neg {
		cop = ":"
	}
	lalts := make([]string, len(alts))
	for k, a := range alts {
		lalts[k] = strings.ToLower(a)
	}
	switch field {
	case "id", "created", "updated":
		get := func(i *Issue) int {
			switch field {
			case "id":
				return i.id
			case "created":
				return i.created
			}
			return i.updated
		}
		nums := make([]int, len(alts))
		for k, a := range alts {
			n, ok := parseInt(a)
			if !ok {
				return nil, bad(val2(ordered, val, a))
			}
			nums[k] = n
		}
		return finish(len(alts), neg, func(i *Issue, k int) bool {
			return okCmp(cop, cmpInt(get(i), nums[k]))
		}), nil
	case "points":
		nums := make([]int, len(alts))
		for k, a := range alts {
			if a == "none" && !ordered {
				nums[k] = -1
				continue
			}
			n, ok := parseInt(a)
			if !ok {
				return nil, bad(val2(ordered, val, a))
			}
			nums[k] = n
		}
		return finish(len(alts), neg, func(i *Issue, k int) bool {
			if i.points < 0 {
				return !ordered && nums[k] == -1
			}
			if nums[k] == -1 {
				return false
			}
			return okCmp(cop, cmpInt(i.points, nums[k]))
		}), nil
	case "title", "assignee", "reporter":
		return finish(len(alts), neg, func(i *Issue, k int) bool {
			var v string
			present := true
			switch field {
			case "title":
				v = i.title
			case "assignee":
				v, present = i.asg, i.hasAsg
			default:
				v, present = i.rep, i.hasRep
			}
			if op == "~" {
				return present && strings.Contains(strings.ToLower(v), lalts[k])
			}
			if !present {
				return lalts[k] == "none"
			}
			return strings.ToLower(v) == lalts[k]
		}), nil
	case "text":
		return finish(len(alts), false, func(i *Issue, k int) bool {
			if strings.Contains(strings.ToLower(i.title), lalts[k]) {
				return true
			}
			for _, c := range i.comments {
				if strings.Contains(strings.ToLower(c.text), lalts[k]) {
					return true
				}
			}
			return false
		}), nil
	case "state":
		for _, a := range alts {
			if !hasState(a) {
				return nil, bad(a)
			}
		}
		return finish(len(alts), neg, func(i *Issue, k int) bool { return i.state == alts[k] }), nil
	case "priority":
		rk := make([]int, len(alts))
		for k, a := range alts {
			rk[k] = prioRank(a)
			if rk[k] < 0 {
				return nil, bad(val2(ordered, val, a))
			}
		}
		return finish(len(alts), neg, func(i *Issue, k int) bool {
			return okCmp(cop, cmpInt(i.prio, rk[k]))
		}), nil
	case "due":
		for _, a := range alts {
			if (a == "none" && !ordered) || validDate(a) {
				continue
			}
			return nil, bad(val2(ordered, val, a))
		}
		return finish(len(alts), neg, func(i *Issue, k int) bool {
			if i.due == "" {
				return !ordered && alts[k] == "none"
			}
			if alts[k] == "none" {
				return false
			}
			return okCmp(cop, strings.Compare(i.due, alts[k]))
		}), nil
	case "label", "labels":
		return finish(len(alts), neg, func(i *Issue, k int) bool {
			a := lalts[k]
			if op == "~" {
				for _, l := range i.labels {
					if strings.Contains(l, a) {
						return true
					}
				}
				return false
			}
			if a == "none" {
				return len(i.labels) == 0
			}
			for _, l := range i.labels {
				if l == a {
					return true
				}
			}
			return false
		}), nil
	case "is":
		for _, a := range alts {
			switch a {
			case "open", "final", "overdue", "unassigned":
			default:
				return nil, bad(a)
			}
		}
		return finish(len(alts), false, func(i *Issue, k int) bool {
			open := !wf.isFinal(i.state)
			switch alts[k] {
			case "open":
				return open
			case "final":
				return !open
			case "overdue":
				return open && i.due != "" && i.due < today
			}
			return !i.hasAsg
		}), nil
	case "has":
		for _, a := range alts {
			switch a {
			case "assignee", "due", "points", "labels", "comments", "reporter":
			default:
				return nil, bad(a)
			}
		}
		return finish(len(alts), false, func(i *Issue, k int) bool {
			switch alts[k] {
			case "assignee":
				return i.hasAsg
			case "due":
				return i.due != ""
			case "points":
				return i.points >= 0
			case "labels":
				return len(i.labels) > 0
			case "comments":
				return len(i.comments) > 0
			}
			return i.hasRep
		}), nil
	}
	return nil, &qerr{fmt.Sprintf("query: unknown field '%s'", field)}
}

// splitQ: filter text, sort text, whether a sort clause exists, limit (-1 none), error
func splitQ(q string) (string, string, bool, int, *qerr) {
	limit := -1
	var qe *qerr
	t := strings.TrimRightFunc(q, unicode.IsSpace)
	e := len(t)
	s := e
	for s > 0 && !isSpace(t[s-1]) {
		s--
	}
	if s < e {
		arg := t[s:e]
		b := s
		for b > 0 && isSpace(t[b-1]) {
			b--
		}
		if b < s {
			w := b
			for w > 0 && !isSpace(t[w-1]) {
				w--
			}
			if t[w:b] == "limit" {
				if n, ok := parseInt(arg); ok {
					limit = n
				} else {
					qe = &qerr{fmt.Sprintf("bad limit '%s'", arg)}
				}
				q = t[:w]
			}
		}
	}
	for i := 0; i+4 < len(q); i++ {
		if q[i:i+4] == "sort" && (i == 0 || isSpace(q[i-1])) && isSpace(q[i+4]) {
			return q[:i], q[i+4:], true, limit, qe
		}
	}
	return q, "", false, limit, qe
}

type sortKey struct {
	field string
	desc  bool
}

func parseSort(text string) ([]sortKey, *qerr) {
	var keys []sortKey
	f := strings.FieldsFunc(text, func(r rune) bool { return r == ',' || r == ' ' || r == '\t' || r == '\r' || r == '\n' })
	for _, x := range f {
		k := sortKey{}
		if strings.HasPrefix(x, "-") {
			k.desc = true
			x = x[1:]
		}
		switch x {
		case "id", "created", "updated", "priority", "points", "state", "title", "assignee", "reporter", "due":
		default:
			return nil, &qerr{fmt.Sprintf("bad sort field '%s'", x)}
		}
		k.field = x
		keys = append(keys, k)
	}
	return keys, nil
}

func sortCmp(a, b *Issue, k sortKey) int {
	absA, absB := false, false
	c := 0
	switch k.field {
	case "id":
		c = cmpInt(a.id, b.id)
	case "created":
		c = cmpInt(a.created, b.created)
	case "updated":
		c = cmpInt(a.updated, b.updated)
	case "priority":
		c = cmpInt(a.prio, b.prio)
	case "state":
		c = cmpInt(wf.idx[a.state], wf.idx[b.state])
	case "title":
		c = strings.Compare(strings.ToLower(a.title), strings.ToLower(b.title))
	case "points":
		absA, absB = a.points < 0, b.points < 0
		c = cmpInt(a.points, b.points)
	case "assignee":
		absA, absB = !a.hasAsg, !b.hasAsg
		c = strings.Compare(strings.ToLower(a.asg), strings.ToLower(b.asg))
	case "reporter":
		absA, absB = !a.hasRep, !b.hasRep
		c = strings.Compare(strings.ToLower(a.rep), strings.ToLower(b.rep))
	case "due":
		absA, absB = a.due == "", b.due == ""
		c = strings.Compare(a.due, b.due)
	}
	if absA || absB {
		if absA && absB {
			c = 0
		} else if absA {
			c = 1
		} else {
			c = -1
		}
	}
	if k.desc {
		c = -c
	}
	return c
}

func sortedIssues() []*Issue {
	var r []*Issue
	for _, i := range issues {
		r = append(r, i)
	}
	sort.Slice(r, func(a, b int) bool { return r[a].id < r[b].id })
	return r
}

func execList(filterNode node, keys []sortKey, limit int) {
	var m []*Issue
	for _, i := range sortedIssues() {
		if filterNode(i) {
			m = append(m, i)
		}
	}
	sort.SliceStable(m, func(a, b int) bool {
		for _, k := range keys {
			c := sortCmp(m[a], m[b], k)
			if c != 0 {
				return c < 0
			}
		}
		return m[a].id < m[b].id
	})
	if limit >= 0 && limit < len(m) {
		m = m[:limit]
	}
	for _, i := range m {
		pr("#%d | %s | %s | %s | %s | %s | %s | %s", i.id, i.state, prios[i.prio], i.asgS(), i.ptsS(), dash(i.due), i.labS(), i.title)
	}
	if len(m) == 1 {
		pr("(1 issue)")
	} else {
		pr("(%d issues)", len(m))
	}
}

func compileFull(q string) (node, []sortKey, int, *qerr) {
	f, st, _, limit, le := splitQ(q)
	if le != nil {
		return nil, nil, 0, le
	}
	n, _, e := parseFilter(f)
	if e != nil {
		return nil, nil, 0, e
	}
	keys, e := parseSort(st)
	if e != nil {
		return nil, nil, 0, e
	}
	return n, keys, limit, nil
}

func cmdList(line string) {
	n, keys, limit, e := compileFull(restAfter(line, 1))
	if e != nil {
		pr("error: %s", e.msg)
		return
	}
	execList(n, keys, limit)
}

// ---------- views ----------

func viewRefs(q string) map[string]bool {
	f, _, _, _, _ := splitQ(q)
	_, refs, e := parseFilter(f)
	if e != nil {
		return map[string]bool{}
	}
	return refs
}

func viewNames() []string {
	var r []string
	for n := range views {
		r = append(r, n)
	}
	sort.Strings(r)
	return r
}

func cmdView(line string) {
	w := strings.Fields(line)[1:]
	gen := "usage: view save|run|list|show|delete"
	if len(w) == 0 {
		pr("error: %s", gen)
		return
	}
	switch w[0] {
	case "save":
		if len(w) < 2 {
			pr("error: usage: view save NAME QUERY")
			return
		}
		name := w[1]
		okn := name[0] >= 'a' && name[0] <= 'z'
		for i := 1; i < len(name); i++ {
			c := name[i]
			if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_' || c == '-') {
				okn = false
			}
		}
		if !okn {
			pr("error: bad view name '%s'", name)
			return
		}
		q := strings.TrimSpace(restAfter(line, 3))
		_, _, _, e := compileFull(q)
		if e != nil {
			pr("error: %s", e.msg)
			return
		}
		if _, exists := views[name]; exists && viewRefs(q)[name] {
			pr("error: view '%s' would reference itself", name)
			return
		}
		views[name] = q
		pr("saved view %s", name)
	case "run":
		if len(w) < 2 {
			pr("error: usage: view run NAME [sort FIELDS] [limit N]")
			return
		}
		q, ok := views[w[1]]
		if !ok {
			pr("error: unknown view '%s'", w[1])
			return
		}
		extra := restAfter(line, 3)
		ef, est, eHasSort, elim, le := splitQ(extra)
		if le != nil {
			pr("error: %s", le.msg)
			return
		}
		if strings.TrimSpace(ef) != "" {
			pr("error: unexpected '%s'", strings.TrimSpace(ef))
			return
		}
		var ekeys []sortKey
		if eHasSort {
			var e *qerr
			ekeys, e = parseSort(est)
			if e != nil {
				pr("error: %s", e.msg)
				return
			}
		}
		n, keys, limit, e := compileFull(q)
		if e != nil {
			pr("error: %s", e.msg)
			return
		}
		if eHasSort {
			keys = ekeys
		}
		if elim >= 0 {
			limit = elim
		}
		execList(n, keys, limit)
	case "list":
		if len(views) == 0 {
			pr("(no views)")
			return
		}
		for _, n := range viewNames() {
			pr("%s: %s", n, views[n])
		}
	case "show":
		if len(w) != 2 {
			pr("error: usage: view show NAME")
			return
		}
		q, ok := views[w[1]]
		if !ok {
			pr("error: unknown view '%s'", w[1])
			return
		}
		pr("%s: %s", w[1], q)
	case "delete":
		if len(w) != 2 {
			pr("error: usage: view delete NAME")
			return
		}
		if _, ok := views[w[1]]; !ok {
			pr("error: unknown view '%s'", w[1])
			return
		}
		for _, m := range viewNames() {
			if m != w[1] && viewRefs(views[m])[w[1]] {
				pr("error: view '%s' is used by '%s'", w[1], m)
				return
			}
		}
		delete(views, w[1])
		pr("deleted view %s", w[1])
	default:
		pr("error: %s", gen)
	}
}

// ---------- bulk ----------

func cmdBulk(line string) {
	body := restAfter(line, 1)
	usage := "usage: bulk ACTION... where QUERY"
	wi := -1
	for i := 0; i+5 <= len(body); i++ {
		if body[i:i+5] == "where" && (i == 0 || isSpace(body[i-1])) && (i+5 == len(body) || isSpace(body[i+5])) {
			wi = i
			break
		}
	}
	if wi < 0 || strings.TrimSpace(body[:wi]) == "" {
		pr("error: %s", usage)
		return
	}
	toks, ok := tokenize(body[:wi])
	if !ok {
		pr("error: unterminated quote")
		return
	}
	query := body[wi+5:]
	switch toks[0] {
	case "move":
		if len(toks) != 2 {
			pr("error: usage: bulk move STATE where QUERY")
			return
		}
	case "assign":
		if len(toks) != 2 {
			pr("error: usage: bulk assign NAME where QUERY")
			return
		}
	case "label":
		if len(toks) < 2 {
			pr("error: usage: bulk label +label... where QUERY")
			return
		}
	case "set":
		if len(toks) < 2 {
			pr("error: usage: bulk set field=value... where QUERY")
			return
		}
	default:
		pr("error: unknown bulk action '%s'", toks[0])
		return
	}
	n, _, e := parseFilter(query)
	if e != nil {
		pr("error: %s", e.msg)
		return
	}
	var m []*Issue
	for _, i := range sortedIssues() {
		if n(i) {
			m = append(m, i)
		}
	}
	okc, failc := 0, 0
	for _, iss := range m {
		var o, er string
		switch toks[0] {
		case "move":
			o, er = doMove(iss, toks[1], "", false)
		case "assign":
			o, er = doEdit(iss, []string{"assignee=" + toks[1]})
		case "label":
			o, er = doLabel(iss, toks[1:])
		case "set":
			o, er = doEdit(iss, toks[1:])
		}
		if er != "" {
			pr("#%d error: %s", iss.id, er)
			failc++
		} else {
			pr("%s", o)
			okc++
		}
	}
	pr("bulk: %d ok, %d failed", okc, failc)
}

// ---------- reports ----------

func cmdReport(line string) {
	w := strings.Fields(line)[1:]
	gen := "usage: report summary|workload|labels|timeline"
	if len(w) == 0 {
		pr("error: %s", gen)
		return
	}
	all := sortedIssues()
	switch w[0] {
	case "summary":
		total, open := 0, 0
		cnt := map[string]int{}
		pc := map[int]int{}
		un, od, pts := 0, 0, 0
		for _, i := range all {
			total++
			cnt[i.state]++
			pc[i.prio]++
			if !wf.isFinal(i.state) {
				open++
				if !i.hasAsg {
					un++
				}
				if i.due != "" && i.due < today {
					od++
				}
				if i.points > 0 {
					pts += i.points
				}
			}
		}
		pr("issues: %d (open %d, final %d)", total, open, total-open)
		pr("by state:")
		if wf != nil {
			for _, s := range wf.states {
				pr("  %s: %d", s, cnt[s])
			}
		}
		pr("by priority:")
		for k := 3; k >= 0; k-- {
			pr("  %s: %d", prios[k], pc[k])
		}
		pr("unassigned: %d", un)
		pr("overdue: %d", od)
		pr("open points: %d", pts)
	case "workload":
		type g struct {
			name string
			n, p int
		}
		var gs []*g
		gm := map[string]*g{}
		var ua *g
		for _, i := range all {
			if wf.isFinal(i.state) {
				continue
			}
			pt := 0
			if i.points > 0 {
				pt = i.points
			}
			if !i.hasAsg {
				if ua == nil {
					ua = &g{name: "unassigned"}
				}
				ua.n++
				ua.p += pt
				continue
			}
			k := strings.ToLower(i.asg)
			x := gm[k]
			if x == nil {
				x = &g{name: i.asg}
				gm[k] = x
				gs = append(gs, x)
			}
			x.n++
			x.p += pt
		}
		if len(gs) == 0 && ua == nil {
			pr("(no open issues)")
			return
		}
		sort.SliceStable(gs, func(a, b int) bool {
			if gs[a].p != gs[b].p {
				return gs[a].p > gs[b].p
			}
			if gs[a].n != gs[b].n {
				return gs[a].n > gs[b].n
			}
			return strings.ToLower(gs[a].name) < strings.ToLower(gs[b].name)
		})
		f := func(x *g) {
			u := "issues"
			if x.n == 1 {
				u = "issue"
			}
			pr("%s: %d %s, %d points", x.name, x.n, u, x.p)
		}
		for _, x := range gs {
			f(x)
		}
		if ua != nil {
			f(ua)
		}
	case "labels":
		n, _, e := parseFilter(restAfter(line, 2))
		if e != nil {
			pr("error: %s", e.msg)
			return
		}
		cnt := map[string]int{}
		for _, i := range all {
			if n(i) {
				for _, l := range i.labels {
					cnt[l]++
				}
			}
		}
		if len(cnt) == 0 {
			pr("(no labels)")
			return
		}
		var ls []string
		for l := range cnt {
			ls = append(ls, l)
		}
		sort.Slice(ls, func(a, b int) bool {
			if cnt[ls[a]] != cnt[ls[b]] {
				return cnt[ls[a]] > cnt[ls[b]]
			}
			return ls[a] < ls[b]
		})
		for _, l := range ls {
			pr("%s: %d", l, cnt[l])
		}
	case "timeline":
		if len(w) != 2 {
			pr("error: usage: report timeline ID")
			return
		}
		iss, e := findIssue(w[1])
		if e != "" {
			pr("error: %s", e)
			return
		}
		st := wf.initial
		from := iss.created
		for _, c := range iss.changes {
			pr("%s: t=%d..%d (%d)", st, from, c.t, c.t-from)
			st, from = c.state, c.t
		}
		pr("%s: t=%d..%d (%d)", st, from, clock, clock-from)
	default:
		pr("error: %s", gen)
	}
}

// ---------- main ----------

func main() {
	out = bufio.NewWriterSize(os.Stdout, 1<<16)
	defer out.Flush()
	sc := bufio.NewScanner(os.Stdin)
	sc.Buffer(make([]byte, 1<<20), 1<<28)
	var lines []string
	for sc.Scan() {
		lines = append(lines, strings.TrimRight(sc.Text(), "\r"))
	}
	for i := 0; i < len(lines); {
		raw := lines[i]
		i++
		t := strings.TrimSpace(raw)
		if t == "" || t[0] == '#' {
			continue
		}
		line := strings.TrimRightFunc(raw, unicode.IsSpace)
		pr("> %s", line)
		cmd := strings.Fields(line)[0]
		switch cmd {
		case "workflow":
			cmdWorkflow(lines, &i)
		case "actor":
			w := strings.Fields(line)[1:]
			if len(w) != 1 {
				pr("error: usage: actor NAME")
			} else {
				actor = w[0]
				pr("actor is %s", actor)
			}
		case "today":
			w := strings.Fields(line)[1:]
			if len(w) != 1 {
				pr("error: usage: today DATE")
			} else if !validDate(w[0]) {
				pr("error: bad date '%s'", w[0])
			} else {
				today = w[0]
				pr("today is %s", today)
			}
		case "create":
			cmdCreate(line)
		case "edit":
			cmdEdit(line)
		case "label":
			cmdLabel(line)
		case "assign":
			cmdAssign(line)
		case "move":
			cmdMove(line)
		case "comment":
			cmdComment(line)
		case "delete":
			cmdDelete(line)
		case "show":
			cmdShow(line)
		case "list":
			cmdList(line)
		case "view":
			cmdView(line)
		case "bulk":
			cmdBulk(line)
		case "log":
			cmdLog(line)
		case "report":
			cmdReport(line)
		default:
			pr("error: unknown command '%s'", cmd)
		}
	}
}

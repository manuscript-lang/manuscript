package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

type Comment struct {
	T     int
	Actor string
	Text  string
}

type stateEntry struct {
	State string
	T     int
}

// Issue: optional string fields use "" for absent (they can never be empty
// when present); points use HasPoints.
type Issue struct {
	ID        int
	Title     string
	State     string
	Priority  string
	Assignee  string
	Reporter  string
	Points    int
	HasPoints bool
	Due       string
	Labels    []string
	Comments  []Comment
	Created   int
	Updated   int
	History   []stateEntry
}

type LogEntry struct {
	T      int
	Actor  string
	ID     int
	Detail string
}

type Transition struct {
	Target string
	Guards []string
}

type Workflow struct {
	Initial  string
	States   []string
	StateIdx map[string]int
	Final    map[string]bool
	Trans    map[string][]Transition
	NTrans   int
}

var (
	out    *bufio.Writer
	reader *bufio.Reader
	clock  int
	actor  = "system"
	today  = "1970-01-01"
	nextID = 1
	wf     *Workflow
	issues = map[int]*Issue{}
	logs   []LogEntry
	views  = map[string]string{}
)

var prank = map[string]int{"low": 0, "medium": 1, "high": 2, "critical": 3}

var guardFields = map[string]bool{"assignee": true, "points": true, "due": true, "labels": true, "reporter": true}

var sortFields = map[string]bool{
	"id": true, "created": true, "updated": true, "priority": true, "points": true,
	"state": true, "title": true, "assignee": true, "reporter": true, "due": true,
}

var (
	stateRe    = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)
	labelRe    = regexp.MustCompile(`^[a-z0-9_-]+$`)
	dateRe     = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}$`)
	viewNameRe = regexp.MustCompile(`^[a-z][a-z0-9_-]*$`)
	whereRe    = regexp.MustCompile(`(^|\s)where(\s|$)`)
	limitRe    = regexp.MustCompile(`(?:^|\s)limit\s+(\S+)$`)
	sortKwRe   = regexp.MustCompile(`(?:^|\s)sort\s`)
	sepRe      = regexp.MustCompile(`[,\s]+`)
	termRe     = regexp.MustCompile(`^([A-Za-z_]+)(!=|<=|>=|:|<|>|~)(.*)$`)
)

func validState(s string) bool { return stateRe.MatchString(s) }
func validLabel(s string) bool { return labelRe.MatchString(s) }

func validDate(s string) bool {
	if !dateRe.MatchString(s) {
		return false
	}
	y, _ := strconv.Atoi(s[0:4])
	m, _ := strconv.Atoi(s[5:7])
	d, _ := strconv.Atoi(s[8:10])
	if y < 1 || m < 1 || m > 12 || d < 1 {
		return false
	}
	last := time.Date(y, time.Month(m)+1, 0, 0, 0, 0, 0, time.UTC).Day()
	return d <= last
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

// parseIntRule: digits only, no leading zeros (except 0), at most 1000000.
func parseIntRule(s string) (int, bool) {
	if !isDigits(s) || len(s) > 7 {
		return 0, false
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

func parseLimit(s string) int {
	if len(s) > 9 {
		return 1 << 40
	}
	n, _ := strconv.Atoi(s)
	return n
}

func isFinal(state string) bool { return wf != nil && wf.Final[state] }

func stateKnown(s string) bool {
	if wf == nil {
		return false
	}
	_, ok := wf.StateIdx[s]
	return ok
}

func dash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

func pointsStr(i *Issue) string {
	if !i.HasPoints {
		return "-"
	}
	return strconv.Itoa(i.Points)
}

func labelsStr(i *Issue) string {
	if len(i.Labels) == 0 {
		return "-"
	}
	return strings.Join(i.Labels, ",")
}

func sortedKeys(set map[string]bool) []string {
	var r []string
	for k := range set {
		r = append(r, k)
	}
	sort.Strings(r)
	return r
}

func liveIssues() []*Issue {
	ids := make([]int, 0, len(issues))
	for id := range issues {
		ids = append(ids, id)
	}
	sort.Ints(ids)
	res := make([]*Issue, len(ids))
	for k, id := range ids {
		res[k] = issues[id]
	}
	return res
}

func logAdd(t, id int, detail string) {
	logs = append(logs, LogEntry{t, actor, id, detail})
}

func plural(n int) string {
	if n == 1 {
		return "issue"
	}
	return "issues"
}

// ---------------------------------------------------------------------------
// Output / input
// ---------------------------------------------------------------------------

func pr(format string, args ...any) {
	fmt.Fprintf(out, format, args...)
	out.WriteByte('\n')
}

func errf(msg string) { pr("error: %s", msg) }

func emit(lines []string, err error) {
	if err != nil {
		errf(err.Error())
		return
	}
	for _, l := range lines {
		pr("%s", l)
	}
}

func readLine() (string, bool) {
	s, err := reader.ReadString('\n')
	if len(s) == 0 && err != nil {
		return "", false
	}
	s = strings.TrimSuffix(s, "\n")
	s = strings.TrimSuffix(s, "\r")
	return s, true
}

func main() {
	reader = bufio.NewReaderSize(os.Stdin, 1<<16)
	out = bufio.NewWriterSize(os.Stdout, 1<<16)
	defer out.Flush()
	for {
		line, ok := readLine()
		if !ok {
			break
		}
		handleLine(line)
	}
}

// ---------------------------------------------------------------------------
// Lexing helpers
// ---------------------------------------------------------------------------

// splitWord returns the first whitespace-separated word and the remainder
// (leading blanks removed).
func splitWord(s string) (string, string) {
	s = strings.TrimLeft(s, " \t")
	i := strings.IndexAny(s, " \t")
	if i < 0 {
		return s, ""
	}
	return s[:i], strings.TrimLeft(s[i:], " \t")
}

// splitN returns up to n leading words and the remainder.
func splitN(s string, n int) ([]string, string) {
	var words []string
	for len(words) < n {
		w, r := splitWord(s)
		if w == "" {
			break
		}
		words = append(words, w)
		s = r
	}
	return words, s
}

// tokenize: whitespace-separated tokens; double quotes group text, \" and \\
// are escapes inside quotes.
func tokenize(s string) ([]string, error) {
	var toks []string
	var cur strings.Builder
	inTok, inQ := false, false
	for i := 0; i < len(s); i++ {
		c := s[i]
		if inQ {
			if c == '\\' && i+1 < len(s) && (s[i+1] == '"' || s[i+1] == '\\') {
				cur.WriteByte(s[i+1])
				i++
				continue
			}
			if c == '"' {
				inQ = false
				continue
			}
			cur.WriteByte(c)
			continue
		}
		switch {
		case c == ' ' || c == '\t':
			if inTok {
				toks = append(toks, cur.String())
				cur.Reset()
				inTok = false
			}
		case c == '"':
			inQ = true
			inTok = true
		default:
			cur.WriteByte(c)
			inTok = true
		}
	}
	if inQ {
		return nil, errors.New("unterminated quote")
	}
	if inTok {
		toks = append(toks, cur.String())
	}
	return toks, nil
}

func parseIDArg(arg string) (int, string, bool) {
	s := strings.TrimPrefix(arg, "#")
	if !isDigits(s) {
		return 0, "", false
	}
	s = strings.TrimLeft(s, "0")
	if s == "" {
		return 0, "", false
	}
	if len(s) > 15 {
		return -1, s, true
	}
	n, _ := strconv.Atoi(s)
	return n, s, true
}

func findIssue(arg string) (*Issue, error) {
	n, disp, ok := parseIDArg(arg)
	if !ok {
		return nil, fmt.Errorf("bad issue id '%s'", arg)
	}
	iss := issues[n]
	if iss == nil {
		return nil, fmt.Errorf("no such issue #%s", disp)
	}
	return iss, nil
}

// ---------------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------------

func handleLine(raw string) {
	line := strings.TrimRight(raw, " \t\v\f\r")
	t := strings.TrimLeft(line, " \t\v\f\r")
	if t == "" || t[0] == '#' {
		return
	}
	pr("> %s", line)
	cmd, rest := splitWord(t)
	switch cmd {
	case "workflow":
		cmdWorkflow()
	case "actor":
		f := strings.Fields(rest)
		if len(f) != 1 {
			errf("usage: actor NAME")
			return
		}
		actor = f[0]
		pr("actor is %s", actor)
	case "today":
		f := strings.Fields(rest)
		if len(f) != 1 {
			errf("usage: today DATE")
			return
		}
		if !validDate(f[0]) {
			errf(fmt.Sprintf("bad date '%s'", f[0]))
			return
		}
		today = f[0]
		pr("today is %s", today)
	case "create":
		cmdCreate(rest)
	case "edit":
		cmdEdit(rest)
	case "label":
		cmdLabel(rest)
	case "assign":
		cmdAssign(rest)
	case "move":
		cmdMove(rest)
	case "comment":
		cmdComment(rest)
	case "delete":
		cmdDelete(rest)
	case "show":
		cmdShow(rest)
	case "list":
		cmdList(rest)
	case "view":
		cmdView(rest)
	case "bulk":
		cmdBulk(rest)
	case "log":
		cmdLog(rest)
	case "report":
		cmdReport(rest)
	default:
		errf(fmt.Sprintf("unknown command '%s'", cmd))
	}
}

// ---------------------------------------------------------------------------
// Workflow
// ---------------------------------------------------------------------------

func cmdWorkflow() {
	var body []string
	for {
		s, ok := readLine()
		if !ok || strings.TrimSpace(s) == "end" {
			break
		}
		body = append(body, s)
	}
	if nextID > 1 {
		errf("workflow: cannot redefine after issues were created")
		return
	}
	w := &Workflow{StateIdx: map[string]int{}, Final: map[string]bool{}, Trans: map[string][]Transition{}}
	add := func(s string) {
		if _, ok := w.StateIdx[s]; !ok {
			w.StateIdx[s] = len(w.States)
			w.States = append(w.States, s)
		}
	}
	var firstErr string
	fail := func(m string) {
		if firstErr == "" {
			firstErr = m
		}
	}
	initialSeen := false
	var transSrc []string
	for _, raw := range body {
		t := strings.TrimSpace(raw)
		if t == "" || t[0] == '#' {
			continue
		}
		switch {
		case strings.HasPrefix(t, "initial:"):
			name := strings.TrimSpace(t[len("initial:"):])
			if !validState(name) {
				fail(fmt.Sprintf("workflow: bad state name '%s'", name))
				continue
			}
			if initialSeen {
				fail("workflow: initial state defined twice")
				continue
			}
			initialSeen = true
			w.Initial = name
			add(name)

		case strings.HasPrefix(t, "final:"):
			for _, part := range strings.Split(t[len("final:"):], ",") {
				name := strings.TrimSpace(part)
				if !validState(name) {
					fail(fmt.Sprintf("workflow: bad state name '%s'", name))
					break
				}
				w.Final[name] = true
				add(name)
			}

		case strings.Contains(t, "->"):
			idx := strings.Index(t, "->")
			src := strings.TrimSpace(t[:idx])
			if !validState(src) {
				fail(fmt.Sprintf("workflow: bad state name '%s'", src))
				continue
			}
			add(src)
			var trs []Transition
			good := true
			for _, e := range strings.Split(t[idx+2:], ",") {
				words := strings.Fields(e)
				var target string
				var guards []string
				switch {
				case len(words) == 1:
					target = words[0]
				case len(words) == 3 && words[1] == "requires":
					target = words[0]
					guards = strings.Split(words[2], "+")
				default:
					fail(fmt.Sprintf("workflow: bad line '%s'", t))
					good = false
				}
				if !good {
					break
				}
				if !validState(target) {
					fail(fmt.Sprintf("workflow: bad state name '%s'", target))
					good = false
					break
				}
				for _, g := range guards {
					if !guardFields[g] {
						fail(fmt.Sprintf("workflow: bad guard field '%s'", g))
						good = false
						break
					}
				}
				if !good {
					break
				}
				add(target)
				trs = append(trs, Transition{Target: target, Guards: guards})
			}
			if good {
				w.Trans[src] = append(w.Trans[src], trs...)
				w.NTrans += len(trs)
				transSrc = append(transSrc, src)
			}

		default:
			fail(fmt.Sprintf("workflow: bad line '%s'", t))
		}
	}
	if firstErr == "" && !initialSeen {
		firstErr = "workflow: initial state missing"
	}
	if firstErr == "" {
		for _, s := range transSrc {
			if w.Final[s] {
				firstErr = fmt.Sprintf("workflow: '%s' is final and cannot have transitions", s)
				break
			}
		}
	}
	if firstErr != "" {
		errf(firstErr)
		return
	}
	wf = w
	pr("workflow ok: %d states, %d transitions", len(w.States), w.NTrans)
}

// ---------------------------------------------------------------------------
// Fields and patches
// ---------------------------------------------------------------------------

type Patch struct {
	Has       map[string]bool
	Title     string
	Priority  string
	Assignee  string
	Points    int
	HasPoints bool
	Due       string
	Labels    []string
	Reporter  string
}

func parseFields(toks []string) (*Patch, error) {
	p := &Patch{Has: map[string]bool{}}
	for _, t := range toks {
		idx := strings.IndexByte(t, '=')
		if idx <= 0 {
			return nil, fmt.Errorf("expected field=value, got '%s'", t)
		}
		field, val := t[:idx], t[idx+1:]
		switch field {
		case "state":
			return nil, errors.New("use move to change state")
		case "title":
			if strings.TrimSpace(val) == "" {
				return nil, errors.New("empty title")
			}
			p.Has[field] = true
			p.Title = val
		case "priority":
			if _, ok := prank[val]; !ok {
				return nil, fmt.Errorf("bad priority '%s'", val)
			}
			p.Has[field] = true
			p.Priority = val
		case "points":
			p.Has[field] = true
			if val == "none" {
				p.Points, p.HasPoints = 0, false
			} else {
				n, ok := parseIntRule(val)
				if !ok {
					return nil, fmt.Errorf("bad points '%s'", val)
				}
				p.Points, p.HasPoints = n, true
			}
		case "due":
			p.Has[field] = true
			if val == "none" {
				p.Due = ""
			} else {
				if !validDate(val) {
					return nil, fmt.Errorf("bad date '%s'", val)
				}
				p.Due = val
			}
		case "assignee":
			if val == "" {
				return nil, errors.New("empty assignee")
			}
			p.Has[field] = true
			if val == "none" {
				p.Assignee = ""
			} else {
				p.Assignee = val
			}
		case "reporter":
			if val == "" {
				return nil, errors.New("empty reporter")
			}
			p.Has[field] = true
			if val == "none" {
				p.Reporter = ""
			} else {
				p.Reporter = val
			}
		case "labels":
			p.Has[field] = true
			if val == "none" {
				p.Labels = nil
			} else {
				set := map[string]bool{}
				for _, l := range strings.Split(val, ",") {
					l = strings.ToLower(l)
					if !validLabel(l) {
						return nil, fmt.Errorf("bad label '%s'", l)
					}
					set[l] = true
				}
				p.Labels = sortedKeys(set)
			}
		default:
			return nil, fmt.Errorf("unknown field '%s'", field)
		}
	}
	return p, nil
}

func (p *Patch) apply(n *Issue) {
	if p.Has["title"] {
		n.Title = p.Title
	}
	if p.Has["priority"] {
		n.Priority = p.Priority
	}
	if p.Has["assignee"] {
		n.Assignee = p.Assignee
	}
	if p.Has["points"] {
		n.Points, n.HasPoints = p.Points, p.HasPoints
	}
	if p.Has["due"] {
		n.Due = p.Due
	}
	if p.Has["labels"] {
		n.Labels = append([]string(nil), p.Labels...)
	}
	if p.Has["reporter"] {
		n.Reporter = p.Reporter
	}
}

// fieldDiffs lists "FIELD: OLD -> NEW" for changed fields in fixed order.
func fieldDiffs(o, n *Issue) []string {
	var d []string
	if o.Title != n.Title {
		d = append(d, fmt.Sprintf("title: %s -> %s", o.Title, n.Title))
	}
	if o.Priority != n.Priority {
		d = append(d, fmt.Sprintf("priority: %s -> %s", o.Priority, n.Priority))
	}
	if o.Assignee != n.Assignee {
		d = append(d, fmt.Sprintf("assignee: %s -> %s", dash(o.Assignee), dash(n.Assignee)))
	}
	if pointsStr(o) != pointsStr(n) {
		d = append(d, fmt.Sprintf("points: %s -> %s", pointsStr(o), pointsStr(n)))
	}
	if o.Due != n.Due {
		d = append(d, fmt.Sprintf("due: %s -> %s", dash(o.Due), dash(n.Due)))
	}
	if labelsStr(o) != labelsStr(n) {
		d = append(d, fmt.Sprintf("labels: %s -> %s", labelsStr(o), labelsStr(n)))
	}
	if o.Reporter != n.Reporter {
		d = append(d, fmt.Sprintf("reporter: %s -> %s", dash(o.Reporter), dash(n.Reporter)))
	}
	return d
}

// applyPatch applies a validated patch to a live issue, logging changes.
func applyPatch(iss *Issue, p *Patch) []string {
	nw := *iss
	p.apply(&nw)
	diffs := fieldDiffs(iss, &nw)
	if len(diffs) == 0 {
		return []string{fmt.Sprintf("#%d unchanged", iss.ID)}
	}
	clock++
	nw.Updated = clock
	*iss = nw
	for _, d := range diffs {
		logAdd(clock, iss.ID, d)
	}
	return []string{fmt.Sprintf("updated #%d", iss.ID)}
}

// editIssue: final check, then field validation, then apply.
func editIssue(iss *Issue, fields []string, usage string) ([]string, error) {
	if isFinal(iss.State) {
		return nil, fmt.Errorf("#%d is in final state '%s'", iss.ID, iss.State)
	}
	if len(fields) == 0 {
		return nil, errors.New(usage)
	}
	p, err := parseFields(fields)
	if err != nil {
		return nil, err
	}
	return applyPatch(iss, p), nil
}

func labelIssue(iss *Issue, ops []string) ([]string, error) {
	if isFinal(iss.State) {
		return nil, fmt.Errorf("#%d is in final state '%s'", iss.ID, iss.State)
	}
	set := map[string]bool{}
	for _, l := range iss.Labels {
		set[l] = true
	}
	for _, op := range ops {
		remove := false
		name := op
		if strings.HasPrefix(op, "+") {
			name = op[1:]
		} else if strings.HasPrefix(op, "-") {
			remove = true
			name = op[1:]
		}
		name = strings.ToLower(name)
		if !validLabel(name) {
			return nil, fmt.Errorf("bad label '%s'", name)
		}
		if remove {
			delete(set, name)
		} else {
			set[name] = true
		}
	}
	p := &Patch{Has: map[string]bool{"labels": true}, Labels: sortedKeys(set)}
	return applyPatch(iss, p), nil
}

// ---------------------------------------------------------------------------
// Issue commands
// ---------------------------------------------------------------------------

func cmdCreate(rest string) {
	toks, err := tokenize(rest)
	if err != nil {
		errf(err.Error())
		return
	}
	if wf == nil {
		errf("no workflow defined")
		return
	}
	if len(toks) == 0 {
		errf("usage: create TITLE [field=value...]")
		return
	}
	title := toks[0]
	if strings.TrimSpace(title) == "" {
		errf("empty title")
		return
	}
	p, err := parseFields(toks[1:])
	if err != nil {
		errf(err.Error())
		return
	}
	old := &Issue{Title: title, Priority: "medium", Reporter: actor}
	nw := *old
	p.apply(&nw)
	diffs := fieldDiffs(old, &nw)
	clock++
	nw.ID = nextID
	nextID++
	nw.State = wf.Initial
	nw.Created = clock
	nw.Updated = clock
	nw.History = []stateEntry{{wf.Initial, clock}}
	issues[nw.ID] = &nw
	logAdd(clock, nw.ID, fmt.Sprintf("created \"%s\"", title))
	for _, d := range diffs {
		logAdd(clock, nw.ID, d)
	}
	pr("created #%d", nw.ID)
}

func cmdEdit(rest string) {
	toks, err := tokenize(rest)
	if err != nil {
		errf(err.Error())
		return
	}
	if len(toks) == 0 {
		errf("usage: edit ID field=value...")
		return
	}
	iss, err := findIssue(toks[0])
	if err != nil {
		errf(err.Error())
		return
	}
	emit(editIssue(iss, toks[1:], "usage: edit ID field=value..."))
}

func cmdLabel(rest string) {
	toks, err := tokenize(rest)
	if err != nil {
		errf(err.Error())
		return
	}
	if len(toks) < 2 {
		errf("usage: label ID +label -label...")
		return
	}
	iss, err := findIssue(toks[0])
	if err != nil {
		errf(err.Error())
		return
	}
	emit(labelIssue(iss, toks[1:]))
}

func cmdAssign(rest string) {
	toks, err := tokenize(rest)
	if err != nil {
		errf(err.Error())
		return
	}
	if len(toks) != 2 {
		errf("usage: assign ID NAME")
		return
	}
	iss, err := findIssue(toks[0])
	if err != nil {
		errf(err.Error())
		return
	}
	emit(editIssue(iss, []string{"assignee=" + toks[1]}, "usage: assign ID NAME"))
}

func unmetGuards(iss *Issue, guards []string) []string {
	var m []string
	for _, g := range guards {
		unmet := false
		switch g {
		case "assignee":
			unmet = iss.Assignee == ""
		case "points":
			unmet = !iss.HasPoints
		case "due":
			unmet = iss.Due == ""
		case "labels":
			unmet = len(iss.Labels) == 0
		case "reporter":
			unmet = iss.Reporter == ""
		}
		if unmet {
			m = append(m, g)
		}
	}
	return m
}

func moveIssue(iss *Issue, target, comment string, hasComment bool) ([]string, error) {
	if isFinal(iss.State) {
		return nil, fmt.Errorf("#%d is in final state '%s'", iss.ID, iss.State)
	}
	if !stateKnown(target) {
		return nil, fmt.Errorf("unknown state '%s'", target)
	}
	if iss.State == target {
		return nil, fmt.Errorf("already in state '%s'", target)
	}
	var entries []Transition
	for _, tr := range wf.Trans[iss.State] {
		if tr.Target == target {
			entries = append(entries, tr)
		}
	}
	if len(entries) == 0 {
		return nil, fmt.Errorf("transition '%s -> %s' not allowed", iss.State, target)
	}
	ok := false
	var firstMissing []string
	for i, tr := range entries {
		missing := unmetGuards(iss, tr.Guards)
		if len(missing) == 0 {
			ok = true
			break
		}
		if i == 0 {
			firstMissing = missing
		}
	}
	if !ok {
		return nil, fmt.Errorf("cannot move #%d to %s: missing %s", iss.ID, target, strings.Join(firstMissing, ", "))
	}
	from := iss.State
	clock++
	iss.State = target
	iss.Updated = clock
	iss.History = append(iss.History, stateEntry{target, clock})
	logAdd(clock, iss.ID, fmt.Sprintf("state: %s -> %s", from, target))
	if hasComment {
		iss.Comments = append(iss.Comments, Comment{clock, actor, comment})
		logAdd(clock, iss.ID, "comment: "+comment)
	}
	return []string{fmt.Sprintf("moved #%d: %s -> %s", iss.ID, from, target)}, nil
}

func cmdMove(rest string) {
	w, r := splitN(rest, 2)
	if len(w) < 2 {
		errf("usage: move ID STATE [comment...]")
		return
	}
	iss, err := findIssue(w[0])
	if err != nil {
		errf(err.Error())
		return
	}
	emit(moveIssue(iss, w[1], r, r != ""))
}

func cmdComment(rest string) {
	w, r := splitN(rest, 1)
	if len(w) < 1 || r == "" {
		errf("usage: comment ID TEXT")
		return
	}
	iss, err := findIssue(w[0])
	if err != nil {
		errf(err.Error())
		return
	}
	clock++
	iss.Updated = clock
	iss.Comments = append(iss.Comments, Comment{clock, actor, r})
	logAdd(clock, iss.ID, "comment: "+r)
	pr("commented #%d", iss.ID)
}

func cmdDelete(rest string) {
	f := strings.Fields(rest)
	if len(f) != 1 {
		errf("usage: delete ID")
		return
	}
	iss, err := findIssue(f[0])
	if err != nil {
		errf(err.Error())
		return
	}
	clock++
	logAdd(clock, iss.ID, "deleted")
	delete(issues, iss.ID)
	pr("deleted #%d", iss.ID)
}

func cmdShow(rest string) {
	f := strings.Fields(rest)
	if len(f) != 1 {
		errf("usage: show ID")
		return
	}
	iss, err := findIssue(f[0])
	if err != nil {
		errf(err.Error())
		return
	}
	labels := "-"
	if len(iss.Labels) > 0 {
		labels = strings.Join(iss.Labels, ", ")
	}
	pr("#%d %s", iss.ID, iss.Title)
	pr("  state: %s", iss.State)
	pr("  priority: %s", iss.Priority)
	pr("  assignee: %s", dash(iss.Assignee))
	pr("  points: %s", pointsStr(iss))
	pr("  due: %s", dash(iss.Due))
	pr("  labels: %s", labels)
	pr("  reporter: %s", dash(iss.Reporter))
	pr("  created: t=%d, updated: t=%d", iss.Created, iss.Updated)
	pr("  comments: %d", len(iss.Comments))
	for _, c := range iss.Comments {
		pr("    [t=%d %s] %s", c.T, c.Actor, c.Text)
	}
}

// ---------------------------------------------------------------------------
// Query language
// ---------------------------------------------------------------------------

type pred func(*Issue) bool

type qparts struct {
	filter   string
	hasSort  bool
	sort     string
	hasLimit bool
	limit    string
}

// splitQuery extracts a trailing "limit N" and a "sort FIELDS" clause.
func splitQuery(raw string) (qparts, error) {
	var qp qparts
	s := strings.TrimSpace(raw)
	if m := limitRe.FindStringSubmatchIndex(s); m != nil {
		arg := s[m[2]:m[3]]
		if !isDigits(arg) {
			return qp, fmt.Errorf("bad limit '%s'", arg)
		}
		qp.hasLimit, qp.limit = true, arg
		s = s[:m[0]]
	}
	if m := sortKwRe.FindStringIndex(s); m != nil {
		qp.hasSort = true
		qp.sort = strings.TrimSpace(s[m[1]:])
		s = s[:m[0]]
	}
	qp.filter = strings.TrimSpace(s)
	return qp, nil
}

type sortKey struct {
	field string
	desc  bool
}

func parseSort(text string) ([]sortKey, error) {
	var keys []sortKey
	for _, f := range sepRe.Split(text, -1) {
		if f == "" {
			continue
		}
		k := sortKey{}
		if strings.HasPrefix(f, "-") {
			k.desc = true
			f = f[1:]
		}
		if !sortFields[f] {
			return nil, fmt.Errorf("bad sort field '%s'", f)
		}
		k.field = f
		keys = append(keys, k)
	}
	return keys, nil
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

func absentCmp(pa, pb bool, cmp func() int) int {
	switch {
	case !pa && !pb:
		return 0
	case !pa:
		return 1
	case !pb:
		return -1
	}
	return cmp()
}

func cmpField(a, b *Issue, f string) int {
	switch f {
	case "id":
		return cmpInt(a.ID, b.ID)
	case "created":
		return cmpInt(a.Created, b.Created)
	case "updated":
		return cmpInt(a.Updated, b.Updated)
	case "priority":
		return cmpInt(prank[a.Priority], prank[b.Priority])
	case "state":
		return cmpInt(wf.StateIdx[a.State], wf.StateIdx[b.State])
	case "points":
		return absentCmp(a.HasPoints, b.HasPoints, func() int { return cmpInt(a.Points, b.Points) })
	case "title":
		return strings.Compare(strings.ToLower(a.Title), strings.ToLower(b.Title))
	case "assignee":
		return absentCmp(a.Assignee != "", b.Assignee != "", func() int {
			return strings.Compare(strings.ToLower(a.Assignee), strings.ToLower(b.Assignee))
		})
	case "reporter":
		return absentCmp(a.Reporter != "", b.Reporter != "", func() int {
			return strings.Compare(strings.ToLower(a.Reporter), strings.ToLower(b.Reporter))
		})
	case "due":
		return absentCmp(a.Due != "", b.Due != "", func() int { return strings.Compare(a.Due, b.Due) })
	}
	return 0
}

func cmpIssues(a, b *Issue, keys []sortKey) int {
	for _, k := range keys {
		c := cmpField(a, b, k.field)
		if c != 0 {
			if k.desc {
				return -c
			}
			return c
		}
	}
	return cmpInt(a.ID, b.ID)
}

func parseLimitArg(s string) int { return parseLimit(s) }

// execQuery: filter (errors first), then sort, then limit.
func execQuery(filter string, hasSort bool, sortText string, hasLimit bool, limit string) ([]*Issue, error) {
	fn, _, err := parseFilter(filter)
	if err != nil {
		return nil, err
	}
	var keys []sortKey
	if hasSort {
		keys, err = parseSort(sortText)
		if err != nil {
			return nil, err
		}
	}
	lim := -1
	if hasLimit {
		lim = parseLimitArg(limit)
	}
	var res []*Issue
	for _, i := range liveIssues() {
		if fn(i) {
			res = append(res, i)
		}
	}
	sort.SliceStable(res, func(a, b int) bool { return cmpIssues(res[a], res[b], keys) < 0 })
	if lim >= 0 && lim < len(res) {
		res = res[:lim]
	}
	return res, nil
}

func printIssues(res []*Issue) {
	for _, i := range res {
		pr("#%d | %s | %s | %s | %s | %s | %s | %s", i.ID, i.State, i.Priority, dash(i.Assignee),
			pointsStr(i), dash(i.Due), labelsStr(i), i.Title)
	}
	if len(res) == 1 {
		pr("(1 issue)")
	} else {
		pr("(%d issues)", len(res))
	}
}

func cmdList(rest string) {
	qp, err := splitQuery(rest)
	if err != nil {
		errf(err.Error())
		return
	}
	res, err := execQuery(qp.filter, qp.hasSort, qp.sort, qp.hasLimit, qp.limit)
	if err != nil {
		errf(err.Error())
		return
	}
	printIssues(res)
}

// --- filter lexer / parser ---

const (
	qWord = iota
	qAnd
	qOr
	qNot
	qLP
	qRP
)

type qtok struct {
	kind int
	raw  string
}

func lexQuery(s string) ([]qtok, error) {
	var toks []qtok
	i := 0
	for i < len(s) {
		c := s[i]
		if c == ' ' || c == '\t' {
			i++
			continue
		}
		if c == '(' {
			toks = append(toks, qtok{qLP, "("})
			i++
			continue
		}
		if c == ')' {
			toks = append(toks, qtok{qRP, ")"})
			i++
			continue
		}
		start := i
		for i < len(s) {
			c = s[i]
			if c == ' ' || c == '\t' || c == '(' || c == ')' {
				break
			}
			if c == '"' {
				i++
				closed := false
				for i < len(s) {
					if s[i] == '\\' && i+1 < len(s) && (s[i+1] == '"' || s[i+1] == '\\') {
						i += 2
						continue
					}
					if s[i] == '"' {
						closed = true
						i++
						break
					}
					i++
				}
				if !closed {
					return nil, errors.New("query: unterminated quote")
				}
				continue
			}
			i++
		}
		raw := s[start:i]
		switch raw {
		case "AND":
			toks = append(toks, qtok{qAnd, raw})
		case "OR":
			toks = append(toks, qtok{qOr, raw})
		case "NOT":
			toks = append(toks, qtok{qNot, raw})
		default:
			toks = append(toks, qtok{qWord, raw})
		}
	}
	return toks, nil
}

var errEnd = errors.New("query: unexpected end of query")

func unexpectedTok(raw string) error {
	return fmt.Errorf("query: unexpected token '%s'", raw)
}

type qctx struct{ refs []string }

type qparser struct {
	toks []qtok
	pos  int
	ctx  *qctx
}

func (p *qparser) peek() *qtok {
	if p.pos < len(p.toks) {
		return &p.toks[p.pos]
	}
	return nil
}

func (p *qparser) parseOr() (pred, error) {
	left, err := p.parseAnd()
	if err != nil {
		return nil, err
	}
	for t := p.peek(); t != nil && t.kind == qOr; t = p.peek() {
		p.pos++
		right, err := p.parseAnd()
		if err != nil {
			return nil, err
		}
		l, r := left, right
		left = func(i *Issue) bool { return l(i) || r(i) }
	}
	return left, nil
}

func (p *qparser) parseAnd() (pred, error) {
	left, err := p.parseNot()
	if err != nil {
		return nil, err
	}
	for {
		t := p.peek()
		if t == nil {
			break
		}
		if t.kind == qAnd {
			p.pos++
		} else if t.kind != qWord && t.kind != qNot && t.kind != qLP {
			break
		}
		right, err := p.parseNot()
		if err != nil {
			return nil, err
		}
		l, r := left, right
		left = func(i *Issue) bool { return l(i) && r(i) }
	}
	return left, nil
}

func (p *qparser) parseNot() (pred, error) {
	t := p.peek()
	if t == nil {
		return nil, errEnd
	}
	if t.kind == qNot {
		p.pos++
		inner, err := p.parseNot()
		if err != nil {
			return nil, err
		}
		return func(i *Issue) bool { return !inner(i) }, nil
	}
	return p.parsePrimary()
}

func (p *qparser) parsePrimary() (pred, error) {
	t := p.peek()
	if t == nil {
		return nil, errEnd
	}
	switch t.kind {
	case qLP:
		p.pos++
		e, err := p.parseOr()
		if err != nil {
			return nil, err
		}
		c := p.peek()
		if c == nil {
			return nil, errEnd
		}
		if c.kind != qRP {
			return nil, unexpectedTok(c.raw)
		}
		p.pos++
		return e, nil
	case qWord:
		p.pos++
		return p.term(t.raw)
	}
	return nil, unexpectedTok(t.raw)
}

// parseFilter compiles a filter; it also returns the directly referenced views.
func parseFilter(text string) (pred, []string, error) {
	ctx := &qctx{}
	if strings.TrimSpace(text) == "" {
		return func(*Issue) bool { return true }, nil, nil
	}
	toks, err := lexQuery(text)
	if err != nil {
		return nil, nil, err
	}
	p := &qparser{toks: toks, ctx: ctx}
	e, err := p.parseOr()
	if err != nil {
		return nil, nil, err
	}
	if p.pos < len(toks) {
		return nil, nil, unexpectedTok(toks[p.pos].raw)
	}
	return e, ctx.refs, nil
}

var fieldOps = map[string][]string{
	"id":       {":", "!=", "<", "<=", ">", ">="},
	"created":  {":", "!=", "<", "<=", ">", ">="},
	"updated":  {":", "!=", "<", "<=", ">", ">="},
	"points":   {":", "!=", "<", "<=", ">", ">="},
	"due":      {":", "!=", "<", "<=", ">", ">="},
	"priority": {":", "!=", "<", "<=", ">", ">="},
	"title":    {":", "!=", "~"},
	"assignee": {":", "!=", "~"},
	"reporter": {":", "!=", "~"},
	"label":    {":", "!=", "~"},
	"labels":   {":", "!=", "~"},
	"text":     {"~"},
	"state":    {":", "!="},
	"is":       {":"},
	"has":      {":"},
	"view":     {":"},
}

func containsOp(list []string, x string) bool {
	for _, s := range list {
		if s == x {
			return true
		}
	}
	return false
}

func containsCI(s, sub string) bool {
	return strings.Contains(strings.ToLower(s), strings.ToLower(sub))
}

func opHolds(op string, c int) bool {
	switch op {
	case ":":
		return c == 0
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

// unquoteValue parses a double-quoted value that must span the whole string.
func unquoteValue(s string) (string, bool) {
	var b strings.Builder
	for i := 1; i < len(s); i++ {
		c := s[i]
		if c == '\\' && i+1 < len(s) && (s[i+1] == '"' || s[i+1] == '\\') {
			b.WriteByte(s[i+1])
			i++
			continue
		}
		if c == '"' {
			return b.String(), i == len(s)-1
		}
		b.WriteByte(c)
	}
	return "", false
}

func (p *qparser) term(raw string) (pred, error) {
	m := termRe.FindStringSubmatch(raw)
	if m == nil {
		return nil, unexpectedTok(raw)
	}
	field, op, vraw := m[1], m[2], m[3]
	ops, known := fieldOps[field]
	if !known {
		return nil, fmt.Errorf("query: unknown field '%s'", field)
	}
	if !containsOp(ops, op) {
		return nil, fmt.Errorf("query: bad operator '%s' for field '%s'", op, field)
	}
	var alts []string
	if strings.HasPrefix(vraw, `"`) {
		v, ok := unquoteValue(vraw)
		if !ok {
			return nil, fmt.Errorf("query: bad value '%s' for field '%s'", vraw, field)
		}
		alts = []string{v}
	} else if (op == ":" || op == "!=" || op == "~") && field != "view" && strings.Contains(vraw, "|") {
		alts = strings.Split(vraw, "|")
	} else {
		alts = []string{vraw}
	}
	if op == "!=" {
		eq, err := p.altsPred(field, ":", alts)
		if err != nil {
			return nil, err
		}
		return func(i *Issue) bool { return !eq(i) }, nil
	}
	return p.altsPred(field, op, alts)
}

func (p *qparser) altsPred(field, op string, alts []string) (pred, error) {
	var preds []pred
	for _, a := range alts {
		fn, err := p.valuePred(field, op, a)
		if err != nil {
			return nil, err
		}
		preds = append(preds, fn)
	}
	return func(i *Issue) bool {
		for _, f := range preds {
			if f(i) {
				return true
			}
		}
		return false
	}, nil
}

func intGetter(field string) func(*Issue) int {
	switch field {
	case "created":
		return func(i *Issue) int { return i.Created }
	case "updated":
		return func(i *Issue) int { return i.Updated }
	}
	return func(i *Issue) int { return i.ID }
}

func strGetter(field string) func(*Issue) string {
	if field == "assignee" {
		return func(i *Issue) string { return i.Assignee }
	}
	return func(i *Issue) string { return i.Reporter }
}

// valuePred builds the predicate for one value under op (":" "~" or ordered).
func (p *qparser) valuePred(field, op, v string) (pred, error) {
	bad := func() (pred, error) {
		return nil, fmt.Errorf("query: bad value '%s' for field '%s'", v, field)
	}
	switch field {
	case "id", "created", "updated":
		n, ok := parseIntRule(v)
		if !ok {
			return bad()
		}
		get := intGetter(field)
		return func(i *Issue) bool { return opHolds(op, cmpInt(get(i), n)) }, nil

	case "points":
		if op == ":" && v == "none" {
			return func(i *Issue) bool { return !i.HasPoints }, nil
		}
		n, ok := parseIntRule(v)
		if !ok {
			return bad()
		}
		return func(i *Issue) bool { return i.HasPoints && opHolds(op, cmpInt(i.Points, n)) }, nil

	case "due":
		if op == ":" && v == "none" {
			return func(i *Issue) bool { return i.Due == "" }, nil
		}
		if !validDate(v) {
			return bad()
		}
		if op == ":" {
			return func(i *Issue) bool { return i.Due == v }, nil
		}
		return func(i *Issue) bool { return i.Due != "" && opHolds(op, strings.Compare(i.Due, v)) }, nil

	case "priority":
		rk, ok := prank[v]
		if !ok {
			return bad()
		}
		return func(i *Issue) bool { return opHolds(op, cmpInt(prank[i.Priority], rk)) }, nil

	case "title":
		if op == "~" {
			return func(i *Issue) bool { return containsCI(i.Title, v) }, nil
		}
		return func(i *Issue) bool { return strings.EqualFold(i.Title, v) }, nil

	case "assignee", "reporter":
		g := strGetter(field)
		if op == ":" && v == "none" {
			return func(i *Issue) bool { return g(i) == "" }, nil
		}
		if op == "~" {
			return func(i *Issue) bool { return g(i) != "" && containsCI(g(i), v) }, nil
		}
		return func(i *Issue) bool { return g(i) != "" && strings.EqualFold(g(i), v) }, nil

	case "text":
		return func(i *Issue) bool {
			if containsCI(i.Title, v) {
				return true
			}
			for _, c := range i.Comments {
				if containsCI(c.Text, v) {
					return true
				}
			}
			return false
		}, nil

	case "state":
		if !stateKnown(v) {
			return bad()
		}
		return func(i *Issue) bool { return i.State == v }, nil

	case "label", "labels":
		if op == ":" && v == "none" {
			return func(i *Issue) bool { return len(i.Labels) == 0 }, nil
		}
		lv := strings.ToLower(v)
		if op == "~" {
			return func(i *Issue) bool {
				for _, l := range i.Labels {
					if strings.Contains(l, lv) {
						return true
					}
				}
				return false
			}, nil
		}
		return func(i *Issue) bool {
			for _, l := range i.Labels {
				if l == lv {
					return true
				}
			}
			return false
		}, nil

	case "is":
		switch v {
		case "open":
			return func(i *Issue) bool { return !isFinal(i.State) }, nil
		case "final":
			return func(i *Issue) bool { return isFinal(i.State) }, nil
		case "overdue":
			return func(i *Issue) bool { return !isFinal(i.State) && i.Due != "" && i.Due < today }, nil
		case "unassigned":
			return func(i *Issue) bool { return i.Assignee == "" }, nil
		}
		return bad()

	case "has":
		switch v {
		case "assignee":
			return func(i *Issue) bool { return i.Assignee != "" }, nil
		case "due":
			return func(i *Issue) bool { return i.Due != "" }, nil
		case "points":
			return func(i *Issue) bool { return i.HasPoints }, nil
		case "labels":
			return func(i *Issue) bool { return len(i.Labels) > 0 }, nil
		case "comments":
			return func(i *Issue) bool { return len(i.Comments) > 0 }, nil
		case "reporter":
			return func(i *Issue) bool { return i.Reporter != "" }, nil
		}
		return bad()

	case "view":
		stored, ok := views[v]
		if !ok {
			return nil, fmt.Errorf("query: unknown view '%s'", v)
		}
		p.ctx.refs = append(p.ctx.refs, v)
		sp, err := splitQuery(stored)
		if err != nil {
			return nil, err
		}
		fn, _, err := parseFilter(sp.filter)
		if err != nil {
			return nil, err
		}
		return fn, nil
	}
	return bad()
}

// ---------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------

func viewRefs(name string) []string {
	sp, _ := splitQuery(views[name])
	_, refs, _ := parseFilter(sp.filter)
	return refs
}

// reaches reports whether view `from` directly or indirectly references `target`.
func reaches(from, target string) bool {
	seen := map[string]bool{}
	var walk func(v string) bool
	walk = func(v string) bool {
		if v == target {
			return true
		}
		if seen[v] {
			return false
		}
		seen[v] = true
		for _, r := range viewRefs(v) {
			if walk(r) {
				return true
			}
		}
		return false
	}
	return walk(from)
}

func sortedViewNames() []string {
	var names []string
	for n := range views {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

func cmdView(rest string) {
	sub, r := splitWord(rest)
	switch sub {
	case "save":
		viewSave(r)
	case "run":
		viewRun(r)
	case "list":
		viewList()
	case "show":
		viewShow(r)
	case "delete":
		viewDelete(r)
	default:
		errf("usage: view save|run|list|show|delete")
	}
}

func viewSave(r string) {
	name, q := splitWord(r)
	if name == "" {
		errf("usage: view save NAME QUERY")
		return
	}
	if !viewNameRe.MatchString(name) {
		errf(fmt.Sprintf("bad view name '%s'", name))
		return
	}
	raw := strings.TrimSpace(q)
	sp, err := splitQuery(raw)
	if err != nil {
		errf(err.Error())
		return
	}
	_, refs, err := parseFilter(sp.filter)
	if err != nil {
		errf(err.Error())
		return
	}
	if sp.hasSort {
		if _, err := parseSort(sp.sort); err != nil {
			errf(err.Error())
			return
		}
	}
	for _, ref := range refs {
		if ref == name || reaches(ref, name) {
			errf(fmt.Sprintf("view '%s' would reference itself", name))
			return
		}
	}
	views[name] = raw
	pr("saved view %s", name)
}

func viewRun(r string) {
	name, q := splitWord(r)
	if name == "" {
		errf("usage: view run NAME [sort FIELDS] [limit N]")
		return
	}
	stored, ok := views[name]
	if !ok {
		errf(fmt.Sprintf("unknown view '%s'", name))
		return
	}
	qp, err := splitQuery(q)
	if err != nil {
		errf(err.Error())
		return
	}
	if stray := strings.TrimSpace(qp.filter); stray != "" {
		errf(fmt.Sprintf("unexpected '%s'", stray))
		return
	}
	sp, _ := splitQuery(stored)
	hasSort, sortText := sp.hasSort, sp.sort
	if qp.hasSort {
		hasSort, sortText = true, qp.sort
	}
	hasLimit, limit := sp.hasLimit, sp.limit
	if qp.hasLimit {
		hasLimit, limit = true, qp.limit
	}
	res, err := execQuery(sp.filter, hasSort, sortText, hasLimit, limit)
	if err != nil {
		errf(err.Error())
		return
	}
	printIssues(res)
}

func viewList() {
	names := sortedViewNames()
	if len(names) == 0 {
		pr("(no views)")
		return
	}
	for _, n := range names {
		pr("%s: %s", n, views[n])
	}
}

func viewShow(r string) {
	f := strings.Fields(r)
	if len(f) != 1 {
		errf("usage: view show NAME")
		return
	}
	q, ok := views[f[0]]
	if !ok {
		errf(fmt.Sprintf("unknown view '%s'", f[0]))
		return
	}
	pr("%s: %s", f[0], q)
}

func viewDelete(r string) {
	f := strings.Fields(r)
	if len(f) != 1 {
		errf("usage: view delete NAME")
		return
	}
	name := f[0]
	if _, ok := views[name]; !ok {
		errf(fmt.Sprintf("unknown view '%s'", name))
		return
	}
	for _, m := range sortedViewNames() {
		if m != name && reaches(m, name) {
			errf(fmt.Sprintf("view '%s' is used by '%s'", name, m))
			return
		}
	}
	delete(views, name)
	pr("deleted view %s", name)
}

// ---------------------------------------------------------------------------
// Bulk
// ---------------------------------------------------------------------------

func cmdBulk(rest string) {
	const usage = "usage: bulk ACTION... where QUERY"
	loc := whereRe.FindStringSubmatchIndex(rest)
	if loc == nil {
		errf(usage)
		return
	}
	actionText := strings.TrimSpace(rest[:loc[0]])
	query := strings.TrimSpace(rest[loc[1]:])
	if actionText == "" {
		errf(usage)
		return
	}
	toks, err := tokenize(actionText)
	if err != nil {
		errf(err.Error())
		return
	}
	kind, args := toks[0], toks[1:]
	switch kind {
	case "move":
		if len(args) != 1 {
			errf("usage: bulk move STATE where QUERY")
			return
		}
	case "assign":
		if len(args) != 1 {
			errf("usage: bulk assign NAME where QUERY")
			return
		}
	case "label":
		if len(args) < 1 {
			errf("usage: bulk label +label... where QUERY")
			return
		}
	case "set":
		if len(args) < 1 {
			errf("usage: bulk set field=value... where QUERY")
			return
		}
	default:
		errf(fmt.Sprintf("unknown bulk action '%s'", kind))
		return
	}
	fn, _, err := parseFilter(query)
	if err != nil {
		errf(err.Error())
		return
	}
	var matched []*Issue
	for _, i := range liveIssues() {
		if fn(i) {
			matched = append(matched, i)
		}
	}
	ok, failed := 0, 0
	for _, i := range matched {
		var lines []string
		var err error
		switch kind {
		case "move":
			lines, err = moveIssue(i, args[0], "", false)
		case "assign":
			lines, err = editIssue(i, []string{"assignee=" + args[0]}, "")
		case "label":
			lines, err = labelIssue(i, args)
		case "set":
			lines, err = editIssue(i, args, "")
		}
		if err != nil {
			pr("#%d error: %s", i.ID, err.Error())
			failed++
			continue
		}
		for _, l := range lines {
			pr("%s", l)
		}
		ok++
	}
	pr("bulk: %d ok, %d failed", ok, failed)
}

// ---------------------------------------------------------------------------
// Log
// ---------------------------------------------------------------------------

func cmdLog(rest string) {
	const usage = "usage: log [ID] [tail N]"
	f := strings.Fields(rest)
	idArg, tailArg := "", ""
	hasTail := false
	switch len(f) {
	case 0:
	case 1:
		if f[0] == "tail" {
			errf(usage)
			return
		}
		idArg = f[0]
	case 2:
		if f[0] != "tail" {
			errf(usage)
			return
		}
		hasTail, tailArg = true, f[1]
	case 3:
		if f[1] != "tail" {
			errf(usage)
			return
		}
		idArg = f[0]
		hasTail, tailArg = true, f[2]
	default:
		errf(usage)
		return
	}
	filterID := -1
	if idArg != "" {
		n, disp, ok := parseIDArg(idArg)
		if !ok {
			errf(fmt.Sprintf("bad issue id '%s'", idArg))
			return
		}
		if n < 1 || n >= nextID {
			errf(fmt.Sprintf("no such issue #%s", disp))
			return
		}
		filterID = n
	}
	tailN := -1
	if hasTail {
		if !isDigits(tailArg) {
			errf(fmt.Sprintf("bad tail '%s'", tailArg))
			return
		}
		tailN = parseLimitArg(tailArg)
	}
	var sel []LogEntry
	for _, e := range logs {
		if filterID < 0 || e.ID == filterID {
			sel = append(sel, e)
		}
	}
	if tailN >= 0 && tailN < len(sel) {
		sel = sel[len(sel)-tailN:]
	}
	if len(sel) == 0 {
		pr("(no log entries)")
		return
	}
	for _, e := range sel {
		pr("t=%d %s #%d %s", e.T, e.Actor, e.ID, e.Detail)
	}
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

func cmdReport(rest string) {
	sub, r := splitWord(rest)
	switch sub {
	case "summary":
		reportSummary()
	case "workload":
		reportWorkload()
	case "labels":
		reportLabels(r)
	case "timeline":
		reportTimeline(r)
	default:
		errf("usage: report summary|workload|labels|timeline")
	}
}

func reportSummary() {
	total, open, unassigned, overdue, pts := 0, 0, 0, 0, 0
	byState := map[string]int{}
	byPrio := map[string]int{}
	for _, i := range liveIssues() {
		total++
		byState[i.State]++
		byPrio[i.Priority]++
		if !isFinal(i.State) {
			open++
			if i.Assignee == "" {
				unassigned++
			}
			if i.Due != "" && i.Due < today {
				overdue++
			}
			if i.HasPoints {
				pts += i.Points
			}
		}
	}
	pr("issues: %d (open %d, final %d)", total, open, total-open)
	pr("by state:")
	if wf != nil {
		for _, s := range wf.States {
			pr("  %s: %d", s, byState[s])
		}
	}
	pr("by priority:")
	for _, p := range []string{"critical", "high", "medium", "low"} {
		pr("  %s: %d", p, byPrio[p])
	}
	pr("unassigned: %d", unassigned)
	pr("overdue: %d", overdue)
	pr("open points: %d", pts)
}

func reportWorkload() {
	type grp struct {
		name string
		key  string
		n    int
		pts  int
	}
	var order []*grp
	groups := map[string]*grp{}
	openCount, unN, unPts := 0, 0, 0
	for _, i := range liveIssues() {
		if isFinal(i.State) {
			continue
		}
		openCount++
		p := 0
		if i.HasPoints {
			p = i.Points
		}
		if i.Assignee == "" {
			unN++
			unPts += p
			continue
		}
		k := strings.ToLower(i.Assignee)
		g := groups[k]
		if g == nil {
			g = &grp{name: i.Assignee, key: k}
			groups[k] = g
			order = append(order, g)
		}
		g.n++
		g.pts += p
	}
	if openCount == 0 {
		pr("(no open issues)")
		return
	}
	sort.SliceStable(order, func(a, b int) bool {
		x, y := order[a], order[b]
		if x.pts != y.pts {
			return x.pts > y.pts
		}
		if x.n != y.n {
			return x.n > y.n
		}
		return x.key < y.key
	})
	for _, g := range order {
		pr("%s: %d %s, %d points", g.name, g.n, plural(g.n), g.pts)
	}
	if unN > 0 {
		pr("unassigned: %d %s, %d points", unN, plural(unN), unPts)
	}
}

func reportLabels(r string) {
	fn, _, err := parseFilter(r)
	if err != nil {
		errf(err.Error())
		return
	}
	counts := map[string]int{}
	for _, i := range liveIssues() {
		if fn(i) {
			for _, l := range i.Labels {
				counts[l]++
			}
		}
	}
	if len(counts) == 0 {
		pr("(no labels)")
		return
	}
	names := sortedKeysInt(counts)
	sort.SliceStable(names, func(a, b int) bool {
		if counts[names[a]] != counts[names[b]] {
			return counts[names[a]] > counts[names[b]]
		}
		return names[a] < names[b]
	})
	for _, n := range names {
		pr("%s: %d", n, counts[n])
	}
}

func sortedKeysInt(m map[string]int) []string {
	var r []string
	for k := range m {
		r = append(r, k)
	}
	return r
}

func reportTimeline(r string) {
	f := strings.Fields(r)
	if len(f) != 1 {
		errf("usage: report timeline ID")
		return
	}
	iss, err := findIssue(f[0])
	if err != nil {
		errf(err.Error())
		return
	}
	for k, h := range iss.History {
		to := clock
		if k+1 < len(iss.History) {
			to = iss.History[k+1].T
		}
		pr("%s: t=%d..%d (%d)", h.State, h.T, to, to-h.T)
	}
}

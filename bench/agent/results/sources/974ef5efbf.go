package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

const (
	kChar = iota
	kEmpty
	kSeq
	kAlt
	kGroup
	kRepeat
	kLook
	kBol
	kEol
	kWordB
	kBackref
)

type byteSet = [256]bool

type node struct {
	kind   int
	set    *byteSet // kChar
	kids   []*node  // kSeq, kAlt
	body   *node    // kGroup, kRepeat, kLook
	min    int      // kRepeat
	max    int      // kRepeat, -1 = unbounded
	greedy bool     // kRepeat
	neg    bool     // kLook (negative), kWordB (\B)
	idx    int      // kGroup, kBackref
	name   string   // kBackref by name
	fold   bool     // kBackref
}

type regex struct {
	root    *node
	ng      int
	names   []string // names[g]; "" if unnamed; names[0] unused
	nameIdx map[string]int
	multi   bool
	dotall  bool
}

var (
	errNothing        = errors.New("nothing to repeat")
	errBadEsc         = errors.New("bad escape")
	errBadGroup       = errors.New("bad group")
	errBadRepeat      = errors.New("bad repeat")
	errBadRange       = errors.New("bad range")
	errUnterm         = errors.New("unterminated class")
	errUnmatchedOpen  = errors.New("unmatched (")
	errUnmatchedClose = errors.New("unmatched )")
	errDupName        = errors.New("duplicate group name")
	errBadBackref     = errors.New("bad backreference")
)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func isDigit(c byte) bool { return c >= '0' && c <= '9' }
func isAlpha(c byte) bool { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') }
func isAlnum(c byte) bool { return isAlpha(c) || isDigit(c) }
func isWord(c byte) bool  { return isAlnum(c) || c == '_' }

func hexVal(c byte) int {
	switch {
	case c >= '0' && c <= '9':
		return int(c - '0')
	case c >= 'a' && c <= 'f':
		return int(c-'a') + 10
	case c >= 'A' && c <= 'F':
		return int(c-'A') + 10
	}
	return -1
}

func foldSet(s *byteSet) {
	for c := 'A'; c <= 'Z'; c++ {
		if s[c] || s[c+32] {
			s[c] = true
			s[c+32] = true
		}
	}
}

func shorthand(c byte) *byteSet {
	s := new(byteSet)
	var pred func(b byte) bool
	switch c | 0x20 {
	case 'd':
		pred = isDigit
	case 'w':
		pred = isWord
	case 's':
		pred = func(b byte) bool {
			return b == ' ' || b == '\t' || b == '\n' || b == '\r' || b == '\f' || b == '\v'
		}
	}
	upper := c >= 'A' && c <= 'Z'
	for b := 0; b < 256; b++ {
		v := pred(byte(b))
		if upper {
			v = !v
		}
		s[b] = v
	}
	return s
}

func isShorthand(c byte) bool {
	switch c {
	case 'd', 'D', 'w', 'W', 's', 'S':
		return true
	}
	return false
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

type parser struct {
	p       string
	i       int
	icase   bool
	multi   bool
	dotall  bool
	ng      int
	names   []string
	nameIdx map[string]int
	backs   []*node
}

func (ps *parser) more() bool { return ps.i < len(ps.p) }

func (ps *parser) charNode(b byte) *node {
	s := new(byteSet)
	s[b] = true
	if ps.icase {
		foldSet(s)
	}
	return &node{kind: kChar, set: s}
}

func (ps *parser) parseAlt(depth int) (*node, error) {
	var alts []*node
	for {
		seq, err := ps.parseSeq(depth)
		if err != nil {
			return nil, err
		}
		alts = append(alts, seq)
		if ps.more() && ps.p[ps.i] == '|' {
			ps.i++
			continue
		}
		break
	}
	if len(alts) == 1 {
		return alts[0], nil
	}
	return &node{kind: kAlt, kids: alts}, nil
}

// braceAt checks whether a {n}, {n,} or {n,m} quantifier starts at position i.
func (ps *parser) braceAt(i int) (ok bool, mn, mx, end int) {
	const sat = 1 << 20
	p := ps.p
	n := len(p)
	j := i + 1
	start := j
	for j < n && isDigit(p[j]) {
		mn = mn*10 + int(p[j]-'0')
		if mn > sat {
			mn = sat
		}
		j++
	}
	if j == start {
		return false, 0, 0, 0
	}
	if j < n && p[j] == '}' {
		return true, mn, mn, j + 1
	}
	if j < n && p[j] == ',' {
		j++
		s2 := j
		mx = 0
		for j < n && isDigit(p[j]) {
			mx = mx*10 + int(p[j]-'0')
			if mx > sat {
				mx = sat
			}
			j++
		}
		if j < n && p[j] == '}' {
			if j == s2 {
				mx = -1
			}
			return true, mn, mx, j + 1
		}
	}
	return false, 0, 0, 0
}

func (ps *parser) isQuant() bool {
	if !ps.more() {
		return false
	}
	c := ps.p[ps.i]
	switch c {
	case '*', '+', '?':
		return true
	case '{':
		ok, _, _, _ := ps.braceAt(ps.i)
		return ok
	}
	return false
}

func (ps *parser) parseQuant() (int, int, bool, error) {
	c := ps.p[ps.i]
	var mn, mx int
	if c == '{' {
		_, a, b, end := ps.braceAt(ps.i)
		ps.i = end
		mn, mx = a, b
		if mn > 1000 || mx > 1000 || (mx >= 0 && mn > mx) {
			return 0, 0, false, errBadRepeat
		}
	} else {
		ps.i++
		switch c {
		case '*':
			mn, mx = 0, -1
		case '+':
			mn, mx = 1, -1
		case '?':
			mn, mx = 0, 1
		}
	}
	greedy := true
	if ps.more() && ps.p[ps.i] == '?' {
		greedy = false
		ps.i++
	}
	return mn, mx, greedy, nil
}

func (ps *parser) parseSeq(depth int) (*node, error) {
	seq := &node{kind: kSeq}
	for ps.more() {
		c := ps.p[ps.i]
		if c == '|' || c == ')' {
			break
		}
		atom, quantifiable, err := ps.parseAtom(depth)
		if err != nil {
			return nil, err
		}
		if ps.isQuant() {
			if !quantifiable {
				return nil, errNothing
			}
			mn, mx, greedy, err := ps.parseQuant()
			if err != nil {
				return nil, err
			}
			atom = &node{kind: kRepeat, body: atom, min: mn, max: mx, greedy: greedy}
			if ps.isQuant() {
				return nil, errNothing
			}
		}
		seq.kids = append(seq.kids, atom)
	}
	return seq, nil
}

func (ps *parser) parseAtom(depth int) (*node, bool, error) {
	c := ps.p[ps.i]
	switch c {
	case '.':
		ps.i++
		s := new(byteSet)
		for b := 0; b < 256; b++ {
			s[b] = b != '\n' || ps.dotall
		}
		return &node{kind: kChar, set: s}, true, nil
	case '^':
		ps.i++
		return &node{kind: kBol}, false, nil
	case '$':
		ps.i++
		return &node{kind: kEol}, false, nil
	case '[':
		n, err := ps.parseClass()
		return n, true, err
	case '(':
		return ps.parseGroup(depth)
	case '\\':
		return ps.parseEscape()
	case '*', '+', '?':
		return nil, false, errNothing
	}
	ps.i++
	return ps.charNode(c), true, nil
}

func (ps *parser) expectClose() error {
	if !ps.more() || ps.p[ps.i] != ')' {
		return errUnmatchedOpen
	}
	ps.i++
	return nil
}

func (ps *parser) parseGroup(depth int) (*node, bool, error) {
	ps.i++ // (
	if ps.more() && ps.p[ps.i] == '?' {
		ps.i++
		if !ps.more() {
			return nil, false, errBadGroup
		}
		c := ps.p[ps.i]
		switch c {
		case ':':
			ps.i++
			body, err := ps.parseAlt(depth + 1)
			if err != nil {
				return nil, false, err
			}
			if err := ps.expectClose(); err != nil {
				return nil, false, err
			}
			return &node{kind: kSeq, kids: []*node{body}}, true, nil
		case '=', '!':
			ps.i++
			body, err := ps.parseAlt(depth + 1)
			if err != nil {
				return nil, false, err
			}
			if err := ps.expectClose(); err != nil {
				return nil, false, err
			}
			return &node{kind: kLook, body: body, neg: c == '!'}, false, nil
		case '<':
			j := ps.i + 1
			if j >= len(ps.p) || !(isAlpha(ps.p[j]) || ps.p[j] == '_') {
				return nil, false, errBadGroup
			}
			k := j
			for k < len(ps.p) && isWord(ps.p[k]) {
				k++
			}
			if k >= len(ps.p) || ps.p[k] != '>' {
				return nil, false, errBadGroup
			}
			name := ps.p[j:k]
			if _, dup := ps.nameIdx[name]; dup {
				return nil, false, errDupName
			}
			ps.i = k + 1
			ps.ng++
			idx := ps.ng
			ps.names = append(ps.names, name)
			ps.nameIdx[name] = idx
			body, err := ps.parseAlt(depth + 1)
			if err != nil {
				return nil, false, err
			}
			if err := ps.expectClose(); err != nil {
				return nil, false, err
			}
			return &node{kind: kGroup, idx: idx, body: body}, true, nil
		default:
			return nil, false, errBadGroup
		}
	}
	ps.ng++
	idx := ps.ng
	ps.names = append(ps.names, "")
	body, err := ps.parseAlt(depth + 1)
	if err != nil {
		return nil, false, err
	}
	if err := ps.expectClose(); err != nil {
		return nil, false, err
	}
	return &node{kind: kGroup, idx: idx, body: body}, true, nil
}

// parseEscape handles a backslash outside a character class.
func (ps *parser) parseEscape() (*node, bool, error) {
	ps.i++ // backslash
	if !ps.more() {
		return nil, false, errBadEsc
	}
	c := ps.p[ps.i]
	ps.i++
	switch {
	case isShorthand(c):
		return &node{kind: kChar, set: shorthand(c)}, true, nil
	case c == 'n':
		return ps.charNode('\n'), true, nil
	case c == 't':
		return ps.charNode('\t'), true, nil
	case c == 'r':
		return ps.charNode('\r'), true, nil
	case c == 'b' || c == 'B':
		return &node{kind: kWordB, neg: c == 'B'}, false, nil
	case c >= '1' && c <= '9':
		b := &node{kind: kBackref, idx: int(c - '0'), fold: ps.icase}
		ps.backs = append(ps.backs, b)
		return b, true, nil
	case c == 'k':
		if !ps.more() || ps.p[ps.i] != '<' {
			return nil, false, errBadEsc
		}
		j := ps.i + 1
		if j >= len(ps.p) || !(isAlpha(ps.p[j]) || ps.p[j] == '_') {
			return nil, false, errBadEsc
		}
		k := j
		for k < len(ps.p) && isWord(ps.p[k]) {
			k++
		}
		if k >= len(ps.p) || ps.p[k] != '>' {
			return nil, false, errBadEsc
		}
		b := &node{kind: kBackref, name: ps.p[j:k], fold: ps.icase}
		ps.i = k + 1
		ps.backs = append(ps.backs, b)
		return b, true, nil
	case c == 'x':
		if ps.i+1 >= len(ps.p) || hexVal(ps.p[ps.i]) < 0 || hexVal(ps.p[ps.i+1]) < 0 {
			return nil, false, errBadEsc
		}
		v := byte(hexVal(ps.p[ps.i])*16 + hexVal(ps.p[ps.i+1]))
		ps.i += 2
		return ps.charNode(v), true, nil
	case c < 128 && !isAlnum(c):
		return ps.charNode(c), true, nil
	}
	return nil, false, errBadEsc
}

// classAtom reads one class member start: a byte, or a shorthand set.
func (ps *parser) classAtom() (byte, *byteSet, error) {
	if !ps.more() {
		return 0, nil, errUnterm
	}
	c := ps.p[ps.i]
	ps.i++
	if c != '\\' {
		return c, nil, nil
	}
	if !ps.more() {
		return 0, nil, errUnterm
	}
	e := ps.p[ps.i]
	ps.i++
	switch {
	case isShorthand(e):
		return 0, shorthand(e), nil
	case e == 'n':
		return '\n', nil, nil
	case e == 't':
		return '\t', nil, nil
	case e == 'r':
		return '\r', nil, nil
	case e == 'x':
		if ps.i+1 >= len(ps.p) || hexVal(ps.p[ps.i]) < 0 || hexVal(ps.p[ps.i+1]) < 0 {
			return 0, nil, errBadEsc
		}
		v := byte(hexVal(ps.p[ps.i])*16 + hexVal(ps.p[ps.i+1]))
		ps.i += 2
		return v, nil, nil
	case e < 128 && !isAlnum(e):
		return e, nil, nil
	}
	return 0, nil, errBadEsc
}

func (ps *parser) parseClass() (*node, error) {
	ps.i++ // [
	neg := false
	if ps.more() && ps.p[ps.i] == '^' {
		neg = true
		ps.i++
	}
	set := new(byteSet)
	first := true
	for {
		if !ps.more() {
			return nil, errUnterm
		}
		if ps.p[ps.i] == ']' && !first {
			ps.i++
			break
		}
		first = false
		a, aset, err := ps.classAtom()
		if err != nil {
			return nil, err
		}
		if ps.i+1 < len(ps.p) && ps.p[ps.i] == '-' && ps.p[ps.i+1] != ']' {
			ps.i++ // -
			b, bset, err := ps.classAtom()
			if err != nil {
				return nil, err
			}
			if aset != nil || bset != nil || b < a {
				return nil, errBadRange
			}
			for x := int(a); x <= int(b); x++ {
				set[x] = true
			}
			continue
		}
		if aset != nil {
			for x := range set {
				set[x] = set[x] || aset[x]
			}
		} else {
			set[a] = true
		}
	}
	if ps.icase {
		foldSet(set)
	}
	if neg {
		for x := range set {
			set[x] = !set[x]
		}
	}
	return &node{kind: kChar, set: set}, nil
}

func compile(pat string) (*regex, error) {
	ps := &parser{p: pat, nameIdx: map[string]int{}, names: []string{""}}
	// Leading inline flags: (?ims...)
	if len(pat) >= 3 && pat[0] == '(' && pat[1] == '?' {
		j := 2
		for j < len(pat) && strings.IndexByte("ims", pat[j]) >= 0 {
			j++
		}
		if j > 2 && j < len(pat) && pat[j] == ')' {
			for _, f := range pat[2:j] {
				switch f {
				case 'i':
					ps.icase = true
				case 'm':
					ps.multi = true
				case 's':
					ps.dotall = true
				}
			}
			ps.i = j + 1
		}
	}
	root, err := ps.parseAlt(0)
	if err != nil {
		return nil, err
	}
	if ps.more() {
		return nil, errUnmatchedClose
	}
	for _, b := range ps.backs {
		if b.name != "" {
			idx, ok := ps.nameIdx[b.name]
			if !ok {
				return nil, errBadBackref
			}
			b.idx = idx
		} else if b.idx > ps.ng {
			return nil, errBadBackref
		}
	}
	return &regex{root: root, ng: ps.ng, names: ps.names, nameIdx: ps.nameIdx,
		multi: ps.multi, dotall: ps.dotall}, nil
}

// ---------------------------------------------------------------------------
// Matcher (continuation-passing backtracking)
// ---------------------------------------------------------------------------

type matcher struct {
	re   *regex
	s    string
	n    int
	caps []int  // 2*(ng+1); -1 = unset
	open []bool // group currently open
}

type snapshot struct {
	caps []int
	open []bool
}

func (m *matcher) snap() snapshot {
	c := make([]int, len(m.caps))
	copy(c, m.caps)
	o := make([]bool, len(m.open))
	copy(o, m.open)
	return snapshot{c, o}
}

func (m *matcher) restore(s snapshot) {
	copy(m.caps, s.caps)
	copy(m.open, s.open)
}

func (m *matcher) seq(items []*node, idx, i int, k func(int) bool) bool {
	if idx == len(items) {
		return k(i)
	}
	return m.run(items[idx], i, func(j int) bool {
		return m.seq(items, idx+1, j, k)
	})
}

func (m *matcher) rep(nd *node, count, i int, k func(int) bool) bool {
	if count < nd.min {
		return m.run(nd.body, i, func(j int) bool {
			return m.rep(nd, count+1, j, k)
		})
	}
	more := func() bool {
		if nd.max >= 0 && count >= nd.max {
			return false
		}
		return m.run(nd.body, i, func(j int) bool {
			if j == i {
				// empty iteration after min: loop ends here
				return k(j)
			}
			return m.rep(nd, count+1, j, k)
		})
	}
	if nd.greedy {
		if more() {
			return true
		}
		return k(i)
	}
	if k(i) {
		return true
	}
	return more()
}

func (m *matcher) run(nd *node, i int, k func(int) bool) bool {
	switch nd.kind {
	case kChar:
		if i < m.n && nd.set[m.s[i]] {
			return k(i + 1)
		}
		return false
	case kEmpty:
		return k(i)
	case kSeq:
		return m.seq(nd.kids, 0, i, k)
	case kAlt:
		for _, a := range nd.kids {
			if m.run(a, i, k) {
				return true
			}
		}
		return false
	case kGroup:
		g := nd.idx
		m.open[g] = true
		ok := m.run(nd.body, i, func(j int) bool {
			m.open[g] = false
			ps, pe := m.caps[2*g], m.caps[2*g+1]
			m.caps[2*g], m.caps[2*g+1] = i, j
			if k(j) {
				return true
			}
			m.caps[2*g], m.caps[2*g+1] = ps, pe
			m.open[g] = true
			return false
		})
		if !ok {
			m.open[g] = false
		}
		return ok
	case kRepeat:
		return m.rep(nd, 0, i, k)
	case kLook:
		snap := m.snap()
		ok := m.run(nd.body, i, func(int) bool { return true })
		if nd.neg {
			if ok {
				m.restore(snap)
				return false
			}
			return k(i)
		}
		if !ok {
			return false
		}
		if k(i) {
			return true
		}
		m.restore(snap)
		return false
	case kBol:
		if i == 0 || (m.re.multi && m.s[i-1] == '\n') {
			return k(i)
		}
		return false
	case kEol:
		if i == m.n || (m.re.multi && m.s[i] == '\n') {
			return k(i)
		}
		return false
	case kWordB:
		a := i > 0 && isWord(m.s[i-1])
		b := i < m.n && isWord(m.s[i])
		boundary := a != b
		if boundary != nd.neg {
			return k(i)
		}
		return false
	case kBackref:
		g := nd.idx
		if m.caps[2*g] < 0 || m.open[g] {
			return false
		}
		sub := m.s[m.caps[2*g]:m.caps[2*g+1]]
		if i+len(sub) > m.n {
			return false
		}
		seg := m.s[i : i+len(sub)]
		if nd.fold {
			if !strings.EqualFold(seg, sub) {
				return false
			}
		} else if seg != sub {
			return false
		}
		return k(i + len(sub))
	}
	return false
}

// find returns the capture array of the leftmost match starting at or after
// from (only at 0 when full), or nil.
func (re *regex) find(s string, from int, full bool) []int {
	m := &matcher{re: re, s: s, n: len(s),
		caps: make([]int, 2*(re.ng+1)), open: make([]bool, re.ng+1)}
	for p := from; p <= len(s); p++ {
		if full && p != 0 {
			break
		}
		for x := range m.caps {
			m.caps[x] = -1
		}
		for x := range m.open {
			m.open[x] = false
		}
		start := p
		ok := m.run(re.root, p, func(j int) bool {
			if full && j != len(s) {
				return false
			}
			m.caps[0] = start
			m.caps[1] = j
			return true
		})
		if ok {
			return m.caps
		}
	}
	return nil
}

func findAll(re *regex, s string) [][]int {
	var out [][]int
	pos := 0
	for pos <= len(s) {
		c := re.find(s, pos, false)
		if c == nil {
			break
		}
		out = append(out, c)
		if c[1] == c[0] {
			pos = c[1] + 1
		} else {
			pos = c[1]
		}
	}
	return out
}

// ---------------------------------------------------------------------------
// Output helpers
// ---------------------------------------------------------------------------

func quoted(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '"':
			b.WriteString(`\"`)
		case c == '\\':
			b.WriteString(`\\`)
		case c == '\n':
			b.WriteString(`\n`)
		case c == '\t':
			b.WriteString(`\t`)
		case c == '\r':
			b.WriteString(`\r`)
		case c < 0x20 || c > 0x7e:
			fmt.Fprintf(&b, `\x%02x`, c)
		default:
			b.WriteByte(c)
		}
	}
	b.WriteByte('"')
	return b.String()
}

func unescape(s string) (string, bool) {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c != '\\' {
			b.WriteByte(c)
			continue
		}
		if i+1 >= len(s) {
			return "", false
		}
		i++
		switch s[i] {
		case 'n':
			b.WriteByte('\n')
		case 't':
			b.WriteByte('\t')
		case '\\':
			b.WriteByte('\\')
		case 'x':
			if i+2 >= len(s) || hexVal(s[i+1]) < 0 || hexVal(s[i+2]) < 0 {
				return "", false
			}
			b.WriteByte(byte(hexVal(s[i+1])*16 + hexVal(s[i+2])))
			i += 2
		default:
			return "", false
		}
	}
	return b.String(), true
}

func groupLabel(re *regex, g int) string {
	if re.names[g] != "" {
		return strconv.Itoa(g) + " (" + re.names[g] + ")"
	}
	return strconv.Itoa(g)
}

func formatCaps(re *regex, s string, caps []int) []string {
	var lines []string
	for g := 0; g <= re.ng; g++ {
		label := groupLabel(re, g)
		if caps[2*g] < 0 {
			lines = append(lines, label+": unset")
		} else {
			lines = append(lines, fmt.Sprintf("%s: %d..%d %s", label, caps[2*g], caps[2*g+1],
				quoted(s[caps[2*g]:caps[2*g+1]])))
		}
	}
	return lines
}

func expand(re *regex, caps []int, s, repl string) (string, error) {
	errBad := errors.New("bad replacement")
	appendGroup := func(b *strings.Builder, g int) {
		if caps[2*g] >= 0 {
			b.WriteString(s[caps[2*g]:caps[2*g+1]])
		}
	}
	var b strings.Builder
	for i := 0; i < len(repl); {
		c := repl[i]
		if c != '$' {
			b.WriteByte(c)
			i++
			continue
		}
		if i+1 >= len(repl) {
			b.WriteByte('$')
			i++
			continue
		}
		d := repl[i+1]
		switch {
		case isDigit(d):
			g := int(d - '0')
			if g > re.ng {
				return "", errBad
			}
			appendGroup(&b, g)
			i += 2
		case d == '$':
			b.WriteByte('$')
			i += 2
		case d == '{':
			j := strings.IndexByte(repl[i+2:], '}')
			if j < 0 {
				return "", errBad
			}
			name := repl[i+2 : i+2+j]
			idx, ok := re.nameIdx[name]
			if !ok {
				return "", errBad
			}
			appendGroup(&b, idx)
			i = i + 2 + j + 1
		default:
			b.WriteByte('$')
			i++
		}
	}
	return b.String(), nil
}

// ---------------------------------------------------------------------------
// Command driver
// ---------------------------------------------------------------------------

func process(out *bufio.Writer, line string) {
	if line == "" {
		return
	}
	f := strings.Split(line, "\t")
	cmd := f[0]
	badCmd := func() { out.WriteString("error: bad command\n") }

	var want int
	switch cmd {
	case "test", "match", "full", "find-all", "split":
		want = 3
	case "replace":
		want = 4
	default:
		badCmd()
		return
	}
	if len(f) != want {
		badCmd()
		return
	}
	subject, ok := unescape(f[2])
	if !ok {
		badCmd()
		return
	}
	repl := ""
	if cmd == "replace" {
		repl, ok = unescape(f[3])
		if !ok {
			badCmd()
			return
		}
	}
	re, err := compile(f[1])
	if err != nil {
		fmt.Fprintf(out, "error: %s\n", err)
		return
	}

	switch cmd {
	case "test":
		if re.find(subject, 0, false) != nil {
			out.WriteString("true\n")
		} else {
			out.WriteString("false\n")
		}
	case "match", "full":
		caps := re.find(subject, 0, cmd == "full")
		if caps == nil {
			out.WriteString("no match\n")
			return
		}
		for _, l := range formatCaps(re, subject, caps) {
			out.WriteString(l + "\n")
		}
	case "find-all":
		ms := findAll(re, subject)
		for _, c := range ms {
			fmt.Fprintf(out, "%d..%d %s\n", c[0], c[1], quoted(subject[c[0]:c[1]]))
		}
		fmt.Fprintf(out, "(%d matches)\n", len(ms))
	case "split":
		var pieces []string
		prev := 0
		for _, c := range findAll(re, subject) {
			if c[1] == c[0] {
				continue
			}
			pieces = append(pieces, subject[prev:c[0]])
			prev = c[1]
		}
		pieces = append(pieces, subject[prev:])
		for _, p := range pieces {
			out.WriteString(quoted(p) + "\n")
		}
		fmt.Fprintf(out, "(%d pieces)\n", len(pieces))
	case "replace":
		ms := findAll(re, subject)
		var b strings.Builder
		prev := 0
		for _, c := range ms {
			rep, err := expand(re, c, subject, repl)
			if err != nil {
				fmt.Fprintf(out, "error: %s\n", err)
				return
			}
			b.WriteString(subject[prev:c[0]])
			b.WriteString(rep)
			prev = c[1]
		}
		b.WriteString(subject[prev:])
		out.WriteString(quoted(b.String()) + "\n")
	}
}

func main() {
	in := bufio.NewReaderSize(os.Stdin, 1<<20)
	out := bufio.NewWriterSize(os.Stdout, 1<<20)
	defer out.Flush()
	for {
		line, err := in.ReadString('\n')
		if len(line) > 0 {
			line = strings.TrimSuffix(line, "\n")
			process(out, line)
		}
		if err != nil {
			break
		}
	}
}

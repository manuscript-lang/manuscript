package main

import (
	"io"
	"os"
	"strconv"
	"strings"
)

// hbreak is an internal sentinel for a two-space hard break inside paragraph
// text. Input is ASCII, so it can never occur in the source.
const hbreak = ''

var escaper = strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;")

func esc(s string) string { return escaper.Replace(s) }

func main() {
	data, _ := io.ReadAll(os.Stdin)
	text := string(data)
	var lines []string
	if text != "" {
		text = strings.TrimSuffix(text, "\n")
		lines = strings.Split(text, "\n")
	}
	os.Stdout.WriteString(renderBlocks(parseBlocks(lines)))
}

// ---------------------------------------------------------------- helpers

func isBlank(s string) bool { return strings.Trim(s, " ") == "" }

func indentOf(s string) int {
	n := 0
	for n < len(s) && s[n] == ' ' {
		n++
	}
	return n
}

func at(s string, i int) byte {
	if i >= 0 && i < len(s) {
		return s[i]
	}
	return 0
}

// stripUpTo removes up to k leading spaces.
func stripUpTo(l string, k int) string {
	c := 0
	for c < k && c < len(l) && l[c] == ' ' {
		c++
	}
	return l[c:]
}

// ---------------------------------------------------------------- block recognisers

type fence struct {
	ch   byte
	n    int
	ind  int
	info string
}

func fenceOpen(l string) (fence, bool) {
	ind := indentOf(l)
	if ind > 3 {
		return fence{}, false
	}
	c := at(l, ind)
	if c != '`' && c != '~' {
		return fence{}, false
	}
	p := ind
	for p < len(l) && l[p] == c {
		p++
	}
	if p-ind < 3 {
		return fence{}, false
	}
	info := strings.Trim(l[p:], " ")
	if c == '`' && strings.Contains(info, "`") {
		return fence{}, false
	}
	return fence{ch: c, n: p - ind, ind: ind, info: info}, true
}

func fenceClose(l string, f fence) bool {
	ind := indentOf(l)
	if ind > 3 {
		return false
	}
	q := ind
	for q < len(l) && l[q] == f.ch {
		q++
	}
	return q-ind >= f.n && strings.Trim(l[q:], " ") == ""
}

func headingOf(l string) (int, string, bool) {
	ind := indentOf(l)
	if ind > 3 {
		return 0, "", false
	}
	p := ind
	for p < len(l) && l[p] == '#' {
		p++
	}
	level := p - ind
	if level < 1 || level > 6 {
		return 0, "", false
	}
	if p < len(l) && l[p] != ' ' {
		return 0, "", false
	}
	c := strings.Trim(l[p:], " ")
	k := len(c) - len(strings.TrimRight(c, "#"))
	if k > 0 && (k == len(c) || c[len(c)-k-1] == ' ') {
		c = strings.TrimRight(c[:len(c)-k], " ")
	}
	return level, c, true
}

func isHR(l string) bool {
	if indentOf(l) > 3 {
		return false
	}
	s := strings.ReplaceAll(l, " ", "")
	if len(s) < 3 {
		return false
	}
	c := s[0]
	if c != '-' && c != '*' && c != '_' {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] != c {
			return false
		}
	}
	return true
}

func isQuote(l string) bool {
	ind := indentOf(l)
	return ind <= 3 && at(l, ind) == '>'
}

type marker struct {
	ordered bool
	ch      byte
	num     int
	W       int
	content string
	empty   bool
}

func parseMarker(l string) (marker, bool) {
	var m marker
	ind := indentOf(l)
	if ind > 3 {
		return m, false
	}
	p := ind
	if c := at(l, p); c == '-' || c == '*' || c == '+' {
		m.ch = c
		p++
	} else {
		q := p
		for q < len(l) && l[q] >= '0' && l[q] <= '9' {
			q++
		}
		d := q - p
		if d < 1 || d > 9 {
			return m, false
		}
		c := at(l, q)
		if c != '.' && c != ')' {
			return m, false
		}
		num, _ := strconv.Atoi(l[p:q])
		m.ordered = true
		m.ch = c
		m.num = num
		p = q + 1
	}
	if p < len(l) && l[p] != ' ' {
		return m, false
	}
	M := p
	if p == len(l) {
		m.W = M + 1
	} else {
		sp := 0
		for M+sp < len(l) && l[M+sp] == ' ' {
			sp++
		}
		if sp >= 5 {
			m.W = M + 1
		} else {
			m.W = M + sp
		}
	}
	if m.W <= len(l) {
		m.content = l[m.W:]
	}
	m.empty = isBlank(m.content)
	return m, true
}

// interrupts: rules 1-4 tested on the line alone.
func interrupts(l string) bool {
	if _, ok := fenceOpen(l); ok {
		return true
	}
	if _, _, ok := headingOf(l); ok {
		return true
	}
	return isHR(l) || isQuote(l)
}

func listInterrupts(l string) bool {
	m, ok := parseMarker(l)
	return ok && !m.empty && (!m.ordered || m.num == 1) && !isHR(l)
}

// splitRow implements the table cell splitting rule.
func splitRow(line string) []string {
	s := strings.Trim(line, " ")
	if strings.HasPrefix(s, "|") {
		s = s[1:]
	}
	if strings.HasSuffix(s, "|") && !(len(s) >= 2 && s[len(s)-2] == '\\') {
		s = s[:len(s)-1]
	}
	var cells []string
	start := 0
	for k := 0; k < len(s); k++ {
		if s[k] == '|' && !(k > 0 && s[k-1] == '\\') {
			cells = append(cells, s[start:k])
			start = k + 1
		}
	}
	cells = append(cells, s[start:])
	for i := range cells {
		cells[i] = strings.Trim(cells[i], " ")
	}
	return cells
}

func isDelimRow(l string) bool {
	if !strings.Contains(l, "|") {
		return false
	}
	for _, c := range splitRow(l) {
		t := c
		if strings.HasPrefix(t, ":") {
			t = t[1:]
		}
		if strings.HasSuffix(t, ":") {
			t = t[:len(t)-1]
		}
		if len(t) == 0 || strings.Trim(t, "-") != "" {
			return false
		}
	}
	return true
}

func alignsOf(l string) []string {
	var al []string
	for _, c := range splitRow(l) {
		left := strings.HasPrefix(c, ":")
		right := strings.HasSuffix(c, ":")
		switch {
		case left && right:
			al = append(al, "center")
		case left:
			al = append(al, "left")
		case right:
			al = append(al, "right")
		default:
			al = append(al, "")
		}
	}
	return al
}

// ---------------------------------------------------------------- block parsing

type kind int

const (
	bPara kind = iota
	bCode
	bHeading
	bHR
	bQuote
	bList
	bTable
)

type block struct {
	kind     kind
	s, e     int // span in the lines given to parseBlocks
	lang     string
	hasLang  bool
	code     []string
	level    int
	text     string
	para     []string
	children []block
	ordered  bool
	start    int
	loose    bool
	items    []item
	headers  []string
	aligns   []string
	rows     [][]string
}

type item struct {
	s, e   int // span of the marker line through the last included non-blank line
	blocks []block
}

func parseBlocks(lines []string) []block {
	var out []block
	n := len(lines)
	i := 0
	for i < n {
		l := lines[i]
		if isBlank(l) {
			i++
			continue
		}
		ind := indentOf(l)

		// 1. fenced code
		if f, ok := fenceOpen(l); ok {
			j := i + 1
			var code []string
			for j < n && !fenceClose(lines[j], f) {
				code = append(code, stripUpTo(lines[j], f.ind))
				j++
			}
			end := n
			if j < n {
				end = j + 1
			}
			lang := ""
			if f.info != "" {
				lang = strings.SplitN(f.info, " ", 2)[0]
			}
			out = append(out, block{kind: bCode, s: i, e: end, lang: lang, hasLang: f.info != "", code: code})
			i = end
			continue
		}

		if ind <= 3 {
			// 2. ATX heading
			if lev, c, ok := headingOf(l); ok {
				out = append(out, block{kind: bHeading, s: i, e: i + 1, level: lev, text: c})
				i++
				continue
			}
			// 3. thematic break
			if isHR(l) {
				out = append(out, block{kind: bHR, s: i, e: i + 1})
				i++
				continue
			}
			// 4. block quote
			if isQuote(l) {
				j := i
				var sub []string
				for j < n && isQuote(lines[j]) {
					lj := lines[j]
					p := indentOf(lj) + 1
					if at(lj, p) == ' ' {
						p++
					}
					sub = append(sub, lj[p:])
					j++
				}
				out = append(out, block{kind: bQuote, s: i, e: j, children: parseBlocks(sub)})
				i = j
				continue
			}
			// 5. list
			if m, ok := parseMarker(l); ok {
				blk, next := parseList(lines, i, m)
				out = append(out, blk)
				i = next
				continue
			}
		}

		// 6. indented code
		if ind >= 4 {
			j := i
			for j < n && (isBlank(lines[j]) || indentOf(lines[j]) >= 4) {
				j++
			}
			end := j
			for end > i && isBlank(lines[end-1]) {
				end--
			}
			var code []string
			for k := i; k < end; k++ {
				code = append(code, stripUpTo(lines[k], 4))
			}
			out = append(out, block{kind: bCode, s: i, e: end, code: code})
			i = end
			continue
		}

		// 7. table
		if i+1 < n && strings.Contains(l, "|") && isDelimRow(lines[i+1]) &&
			len(splitRow(l)) == len(splitRow(lines[i+1])) {
			j := i + 2
			var rows [][]string
			for j < n && !isBlank(lines[j]) && !interrupts(lines[j]) {
				rows = append(rows, splitRow(lines[j]))
				j++
			}
			out = append(out, block{kind: bTable, s: i, e: j,
				headers: splitRow(l), aligns: alignsOf(lines[i+1]), rows: rows})
			i = j
			continue
		}

		// 8. paragraph
		j := i + 1
		for j < n && !isBlank(lines[j]) && !interrupts(lines[j]) && !listInterrupts(lines[j]) {
			j++
		}
		out = append(out, block{kind: bPara, s: i, e: j, para: lines[i:j]})
		i = j
	}
	return out
}

func parseList(lines []string, i int, first marker) (block, int) {
	n := len(lines)
	var items []item
	k := i
	m := first
	for {
		content := []string{m.content}
		pending := 0
		j := k + 1
		lastJ := k + 1
		for j < n {
			l := lines[j]
			if isBlank(l) {
				pending++
				j++
				continue
			}
			if indentOf(l) >= m.W {
				for p := 0; p < pending; p++ {
					content = append(content, "")
				}
				pending = 0
				content = append(content, l[m.W:])
				j++
				lastJ = j
				continue
			}
			break
		}
		items = append(items, item{s: k, e: lastJ, blocks: parseBlocks(content)})
		k = j
		if k < n && !isHR(lines[k]) {
			if mk, ok := parseMarker(lines[k]); ok && mk.ordered == first.ordered && mk.ch == first.ch {
				m = mk
				continue
			}
		}
		break
	}

	loose := false
	for x := 0; x+1 < len(items); x++ {
		if items[x+1].s > items[x].e {
			loose = true
		}
	}
	for _, it := range items {
		for x := 0; x+1 < len(it.blocks); x++ {
			if it.blocks[x+1].s > it.blocks[x].e {
				loose = true
			}
		}
	}
	end := items[len(items)-1].e
	return block{kind: bList, s: i, e: end, ordered: first.ordered, start: first.num,
		loose: loose, items: items}, k
}

// ---------------------------------------------------------------- block rendering

func renderBlocks(bs []block) string {
	var sb strings.Builder
	for _, b := range bs {
		sb.WriteString(renderBlock(b))
	}
	return sb.String()
}

func renderBlock(b block) string {
	switch b.kind {
	case bPara:
		return "<p>" + paraHTML(b.para) + "</p>\n"
	case bCode:
		var sb strings.Builder
		if b.hasLang {
			sb.WriteString(`<pre><code class="language-` + esc(b.lang) + `">`)
		} else {
			sb.WriteString("<pre><code>")
		}
		for _, l := range b.code {
			sb.WriteString(esc(l) + "\n")
		}
		sb.WriteString("</code></pre>\n")
		return sb.String()
	case bHeading:
		h := strconv.Itoa(b.level)
		return "<h" + h + ">" + inline([]rune(b.text)) + "</h" + h + ">\n"
	case bHR:
		return "<hr />\n"
	case bQuote:
		return "<blockquote>\n" + renderBlocks(b.children) + "</blockquote>\n"
	case bList:
		tag := "ul"
		open := "<ul>\n"
		if b.ordered {
			tag = "ol"
			open = "<ol>\n"
			if b.start != 1 {
				open = `<ol start="` + strconv.Itoa(b.start) + `">` + "\n"
			}
		}
		var sb strings.Builder
		sb.WriteString(open)
		for _, it := range b.items {
			sb.WriteString(renderItem(it, !b.loose))
		}
		sb.WriteString("</" + tag + ">\n")
		return sb.String()
	case bTable:
		return tableHTML(b)
	}
	return ""
}

func renderItem(it item, tight bool) string {
	body := ""
	for _, b := range it.blocks {
		if tight && b.kind == bPara {
			body += paraHTML(b.para)
			continue
		}
		if body == "" || !strings.HasSuffix(body, "\n") {
			body += "\n"
		}
		body += renderBlock(b)
	}
	return "<li>" + body + "</li>\n"
}

func alignAttr(a string) string {
	if a == "" {
		return ""
	}
	return ` align="` + a + `"`
}

func tableHTML(b block) string {
	var sb strings.Builder
	sb.WriteString("<table>\n<thead>\n<tr>\n")
	for j, h := range b.headers {
		sb.WriteString("<th" + alignAttr(b.aligns[j]) + ">" + inline([]rune(h)) + "</th>\n")
	}
	sb.WriteString("</tr>\n</thead>\n")
	if len(b.rows) > 0 {
		sb.WriteString("<tbody>\n")
		for _, r := range b.rows {
			sb.WriteString("<tr>\n")
			for j := range b.headers {
				cell := ""
				if j < len(r) {
					cell = r[j]
				}
				sb.WriteString("<td" + alignAttr(b.aligns[j]) + ">" + inline([]rune(cell)) + "</td>\n")
			}
			sb.WriteString("</tr>\n")
		}
		sb.WriteString("</tbody>\n")
	}
	sb.WriteString("</table>\n")
	return sb.String()
}

// paraText builds the paragraph text: leading spaces removed, trailing spaces
// removed, lines joined with \n (or the hard-break sentinel for two-space breaks).
func paraRunes(lines []string) []rune {
	var out []rune
	for idx, l := range lines {
		t := strings.TrimLeft(l, " ")
		if idx == len(lines)-1 {
			out = append(out, []rune(strings.TrimRight(t, " "))...)
			break
		}
		hard := strings.HasSuffix(t, "  ")
		t = strings.TrimRight(t, " ")
		out = append(out, []rune(t)...)
		if hard && !oddBackslashes(t) {
			out = append(out, hbreak)
		} else {
			out = append(out, '\n')
		}
	}
	return out
}

func oddBackslashes(t string) bool {
	k := 0
	for k < len(t) && t[len(t)-1-k] == '\\' {
		k++
	}
	return k%2 == 1
}

func paraHTML(lines []string) string { return inline(paraRunes(lines)) }

// ---------------------------------------------------------------- inline

type nkind int

const (
	nText nkind = iota
	nBr
	nCode
	nDelim
	nOpen
	nEmph
	nStrong
	nLink
	nImage
)

type node struct {
	k        nkind
	text     string
	ch       byte
	count    int
	orig     int
	canOpen  bool
	canClose bool
	img      bool
	active   bool
	dest     string
	title    string
	hasTitle bool
	children []*node
}

func textNode(t string) *node { return &node{k: nText, text: t} }

func isPunct(r rune) bool {
	return r < 128 && strings.ContainsRune("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~", r)
}

func isWS(r rune) bool { return r == ' ' || r == '\n' || r == hbreak }

func inline(s []rune) string {
	return render(processEmphasis(scan(s)))
}

func addText(nodes *[]*node, t string) {
	ns := *nodes
	if len(ns) > 0 && ns[len(ns)-1].k == nText {
		ns[len(ns)-1].text += t
		return
	}
	*nodes = append(ns, textNode(t))
}

func scan(s []rune) []*node {
	var nodes []*node
	n := len(s)
	i := 0
	for i < n {
		c := s[i]
		switch {
		case c == hbreak:
			nodes = append(nodes, &node{k: nBr})
			i++
		case c == '\\':
			if i+1 < n && s[i+1] == '\n' {
				nodes = append(nodes, &node{k: nBr})
				i += 2
			} else if i+1 < n && isPunct(s[i+1]) {
				addText(&nodes, string(s[i+1]))
				i += 2
			} else {
				addText(&nodes, "\\")
				i++
			}
		case c == '`':
			N := 0
			for i+N < n && s[i+N] == '`' {
				N++
			}
			found := -1
			j := i + N
			for j < n {
				if s[j] == '`' {
					m := 0
					for j+m < n && s[j+m] == '`' {
						m++
					}
					if m == N {
						found = j
						break
					}
					j += m
				} else {
					j++
				}
			}
			if found < 0 {
				addText(&nodes, strings.Repeat("`", N))
				i += N
				continue
			}
			content := make([]rune, 0, found-(i+N))
			for _, r := range s[i+N : found] {
				if r == '\n' || r == hbreak {
					r = ' '
				}
				content = append(content, r)
			}
			cs := string(content)
			if len(cs) >= 2 && cs[0] == ' ' && cs[len(cs)-1] == ' ' && strings.Trim(cs, " ") != "" {
				cs = cs[1 : len(cs)-1]
			}
			nodes = append(nodes, &node{k: nCode, text: cs})
			i = found + N
		case c == '*' || c == '_':
			j := i
			for j < n && s[j] == c {
				j++
			}
			cnt := j - i
			prev := ' '
			if i > 0 {
				prev = s[i-1]
			}
			next := ' '
			if j < n {
				next = s[j]
			}
			lf := !isWS(next) && (!isPunct(next) || isWS(prev) || isPunct(prev))
			rf := !isWS(prev) && (!isPunct(prev) || isWS(next) || isPunct(next))
			var canOpen, canClose bool
			if c == '*' {
				canOpen, canClose = lf, rf
			} else {
				canOpen = lf && (!rf || isPunct(prev))
				canClose = rf && (!lf || isPunct(next))
			}
			nodes = append(nodes, &node{k: nDelim, ch: byte(c), count: cnt, orig: cnt,
				canOpen: canOpen, canClose: canClose})
			i = j
		case c == '[':
			nodes = append(nodes, &node{k: nOpen, active: true})
			i++
		case c == '!' && i+1 < n && s[i+1] == '[':
			nodes = append(nodes, &node{k: nOpen, img: true, active: true})
			i += 2
		case c == ']':
			i = closeBracket(s, i, &nodes)
		default:
			addText(&nodes, string(c))
			i++
		}
	}
	return nodes
}

// closeBracket handles a ']' at index i and returns the next scan index.
func closeBracket(s []rune, i int, nodes *[]*node) int {
	ns := *nodes
	idx := -1
	for k := len(ns) - 1; k >= 0; k-- {
		if ns[k].k == nOpen {
			idx = k
			break
		}
	}
	if idx < 0 {
		addText(nodes, "]")
		return i + 1
	}
	op := ns[idx]
	if !op.img && !op.active {
		op.k = nText
		op.text = "["
		addText(nodes, "]")
		return i + 1
	}
	if i+1 < len(s) && s[i+1] == '(' {
		if dest, title, hasTitle, end, ok := parseTail(s, i+1); ok {
			children := processEmphasis(append([]*node(nil), ns[idx+1:]...))
			var nn *node
			if op.img {
				nn = &node{k: nImage, dest: dest, title: title, hasTitle: hasTitle, children: children}
			} else {
				nn = &node{k: nLink, dest: dest, title: title, hasTitle: hasTitle, children: children}
				for _, x := range ns[:idx] {
					if x.k == nOpen && !x.img {
						x.active = false
					}
				}
			}
			*nodes = append(ns[:idx:idx], nn)
			return end
		}
	}
	// Not a link or image: the marker becomes literal text.
	op.k = nText
	if op.img {
		op.text = "!["
	} else {
		op.text = "["
	}
	addText(nodes, "]")
	return i + 1
}

// parseTail parses the inline link tail starting at the '(' at index p.
// It returns the destination, title, whether a title was given, and the index after ')'.
func parseTail(s []rune, p int) (string, string, bool, int, bool) {
	n := len(s)
	skip := func(q int) int {
		for q < n && (s[q] == ' ' || s[q] == '\n' || s[q] == hbreak) {
			q++
		}
		return q
	}
	q := skip(p + 1)
	var dest []rune
	if q < n && s[q] == '<' {
		q++
		for {
			if q >= n {
				return "", "", false, 0, false
			}
			c := s[q]
			if c == '\\' && q+1 < n && isPunct(s[q+1]) {
				dest = append(dest, s[q+1])
				q += 2
				continue
			}
			if c == '>' {
				q++
				break
			}
			if c == '<' || c == '\n' || c == hbreak {
				return "", "", false, 0, false
			}
			dest = append(dest, c)
			q++
		}
	} else {
		depth := 0
		for q < n {
			c := s[q]
			if c == ' ' || c == '\n' || c == hbreak {
				break
			}
			if c == '\\' && q+1 < n && isPunct(s[q+1]) {
				dest = append(dest, s[q+1])
				q += 2
				continue
			}
			if c == '(' {
				depth++
			} else if c == ')' {
				if depth == 0 {
					break
				}
				depth--
			}
			dest = append(dest, c)
			q++
		}
		if depth != 0 {
			return "", "", false, 0, false
		}
	}

	var title []rune
	hasTitle := false
	q2 := skip(q)
	if q2 > q && q2 < n && s[q2] == '"' {
		q = q2 + 1
		closed := false
		for q < n {
			c := s[q]
			if c == '\\' && q+1 < n && s[q+1] == '"' {
				title = append(title, '"')
				q += 2
				continue
			}
			if c == '"' {
				closed = true
				q++
				break
			}
			if c == hbreak {
				c = '\n'
			}
			title = append(title, c)
			q++
		}
		if !closed {
			return "", "", false, 0, false
		}
		hasTitle = true
	}
	q = skip(q)
	if q >= n || s[q] != ')' {
		return "", "", false, 0, false
	}
	return string(dest), string(title), hasTitle, q + 1, true
}

func multipleOK(o, c *node) bool {
	if (o.canClose || c.canOpen) && (o.orig+c.orig)%3 == 0 && !(o.orig%3 == 0 && c.orig%3 == 0) {
		return false
	}
	return true
}

// processEmphasis resolves delimiter runs in a node list and returns the final
// list, with all remaining delimiters and brackets turned into literal text.
func processEmphasis(list []*node) []*node {
	i := 0
	for i < len(list) {
		cl := list[i]
		if cl.k != nDelim || !cl.canClose || cl.count == 0 {
			i++
			continue
		}
		for cl.count > 0 {
			oi := -1
			for j := i - 1; j >= 0; j-- {
				o := list[j]
				if o.k == nDelim && o.ch == cl.ch && o.canOpen && o.count > 0 && multipleOK(o, cl) {
					oi = j
					break
				}
			}
			if oi < 0 {
				break
			}
			op := list[oi]
			use := 1
			if op.count >= 2 && cl.count >= 2 {
				use = 2
			}
			var kids []*node
			for _, x := range list[oi+1 : i] {
				if x.k == nDelim {
					if x.count > 0 {
						kids = append(kids, textNode(strings.Repeat(string(rune(x.ch)), x.count)))
					}
					continue
				}
				kids = append(kids, x)
			}
			em := &node{k: nEmph, children: kids}
			if use == 2 {
				em.k = nStrong
			}
			op.count -= use
			cl.count -= use
			nl := make([]*node, 0, len(list)+1)
			nl = append(nl, list[:oi+1]...)
			nl = append(nl, em)
			nl = append(nl, list[i:]...)
			list = nl
			i = oi + 2
		}
		i++
	}
	var out []*node
	for _, x := range list {
		switch x.k {
		case nDelim:
			if x.count > 0 {
				out = append(out, textNode(strings.Repeat(string(rune(x.ch)), x.count)))
			}
		case nOpen:
			if x.img {
				out = append(out, textNode("!["))
			} else {
				out = append(out, textNode("["))
			}
		default:
			out = append(out, x)
		}
	}
	return out
}

func render(nodes []*node) string {
	var sb strings.Builder
	for _, x := range nodes {
		switch x.k {
		case nText:
			sb.WriteString(esc(x.text))
		case nBr:
			sb.WriteString("<br />\n")
		case nCode:
			sb.WriteString("<code>" + esc(x.text) + "</code>")
		case nEmph:
			sb.WriteString("<em>" + render(x.children) + "</em>")
		case nStrong:
			sb.WriteString("<strong>" + render(x.children) + "</strong>")
		case nLink:
			sb.WriteString(`<a href="` + esc(x.dest) + `"`)
			if x.hasTitle {
				sb.WriteString(` title="` + esc(x.title) + `"`)
			}
			sb.WriteString(">" + render(x.children) + "</a>")
		case nImage:
			sb.WriteString(`<img src="` + esc(x.dest) + `" alt="` + esc(plain(x.children)) + `"`)
			if x.hasTitle {
				sb.WriteString(` title="` + esc(x.title) + `"`)
			}
			sb.WriteString(" />")
		}
	}
	return sb.String()
}

// plain gives the alt text of an image: text and code content, breaks as one space.
func plain(nodes []*node) string {
	var sb strings.Builder
	for _, x := range nodes {
		switch x.k {
		case nText:
			sb.WriteString(strings.ReplaceAll(x.text, "\n", " "))
		case nCode:
			sb.WriteString(x.text)
		case nBr:
			sb.WriteString(" ")
		default:
			sb.WriteString(plain(x.children))
		}
	}
	return sb.String()
}

import (
	stdin, stdout from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

// A rendered block. `inl` is the inline HTML of a paragraph (used in tight lists).
// `blank` is true when a blank line separates this block from the previous sibling.
type Block:
	is_para: Bool = false
	html: String = ""
	inl: String = ""
	blank: Bool = false

type Step:
	node: Block
	next: Int

type Marker:
	ok: Bool = false
	ordered: Bool = false
	delim: String = ""
	num: Int = 0
	width: Int = 0

type Tail:
	ok: Bool = false
	dest: String = ""
	title: String = ""
	has_title: Bool = false
	after: Int = 0

// Inline node kinds:
// 0 text, 1 code, 2 hard break, 3 delimiter run, 4 link opener (active),
// 5 em, 6 strong, 7 link, 8 image, 9 image opener, 10 link opener (deactivated)
type Inline:
	kind: Int = 0
	text: String = ""
	title: String = ""
	has_title: Bool = false
	cnt: Int = 0
	orig: Int = 0
	can_open: Bool = false
	can_close: Bool = false
	kids: List[Inline] = List[Inline]()

PUNCT := "!\"#$%&'()*+,-./:;<=>?@[\\]^_`\{|\}~"
DIGITS := "0123456789"

// ---------------------------------------------------------------------------
// String helpers (input is ASCII; indexes are scalar indexes)
// ---------------------------------------------------------------------------

fn ch(s: String, k: Int) String:
	if k < 0 or k >= s.length(): return ""
	return s.get(k)

fn cat(cs: List[String], k: Int) String:
	if k < 0 or k >= cs.length(): return ""
	return cs[k].clone()

// Scalars [a, b), clamped.
fn cut(s: String, a: Int, b: Int) String:
	var x = a
	var y = b
	if x < 0:
		x = 0
	if y > s.length():
		y = s.length()
	if x >= y: return ""

	return s.slice_scalars(x, y).get()

fn indentOf(s: String) Int:
	var k = 0
	while ch(s, k) == " ":
		k += 1
	return k

fn isBlank(s: String) Bool:
	return indentOf(s) == s.length()

fn lstrip(s: String) String:
	return cut(s, indentOf(s), s.length())

fn trailingSpaces(s: String) Int:
	var k = 0
	while ch(s, s.length() - 1 - k) == " ":
		k += 1
	return k

fn rstrip(s: String) String:
	return cut(s, 0, s.length() - trailingSpaces(s))

fn strip(s: String) String:
	return rstrip(lstrip(s))

fn esc(s: String) String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
		"\"", "&quot;"
	)

fn isPunct(c: String) Bool:
	return c != "" and PUNCT.contains(c)

fn isWs(c: String) Bool:
	return c == "" or c == " " or c == "\n" or c == "\t"

fn isSpNl(c: String) Bool:
	return c == " " or c == "\n" or c == "\t"

fn isDigit(c: String) Bool:
	return c != "" and DIGITS.contains(c)

fn isAllSpace(s: String) Bool:
	return indentOf(s) == s.length()

fn repeatStr(s: String, n: Int) String:
	var out = ""
	for k in 0..n:
		out += s
	return out

// ---------------------------------------------------------------------------
// Block-level line tests
// ---------------------------------------------------------------------------

// Run length of the fence if the line opens a fenced code block, else 0.
fn fenceRun(s: String) Int:
	ind := indentOf(s)
	if ind > 3: return 0

	c := ch(s, ind)
	if c != "`" and c != "~": return 0

	var k = ind
	while ch(s, k) == c:
		k += 1

	run := k - ind
	if run < 3: return 0

	info := strip(cut(s, k, s.length()))
	if c == "`" and info.contains("`"): return 0

	return run

// ATX heading level, or 0.
fn headingLevel(s: String) Int:
	ind := indentOf(s)
	if ind > 3: return 0

	var k = ind
	while ch(s, k) == "#":
		k += 1

	h := k - ind
	if h < 1 or h > 6: return 0

	c := ch(s, k)
	if c != "" and c != " ": return 0

	return h

fn isHr(s: String) Bool:
	if indentOf(s) > 3: return false

	var mark = ""
	var cnt = 0

	for x in s.split_after(""):
		if x == " ": continue
		if x != "-" and x != "*" and x != "_": return false

		if mark == "":
			mark = x
		else if x != mark:
			return false

		cnt += 1

	return cnt >= 3

fn markerAt(s: String) Marker:
	ind := indentOf(s)
	if ind > 3: return Marker(ok: false)

	c := ch(s, ind)

	if c == "-" or c == "*" or c == "+":
		after1 := ch(s, ind + 1)
		if after1 != "" and after1 != " ": return Marker(ok: false)

		return Marker(ok: true, ordered: false, delim: c, num: 0, width: ind + 1)

	var d = 0
	while isDigit(ch(s, ind + d)):
		d += 1

	dl := ch(s, ind + d)
	if d < 1 or d > 9 or (dl != "." and dl != ")"): return Marker(ok: false)

	after2 := ch(s, ind + d + 1)
	if after2 != "" and after2 != " ": return Marker(ok: false)

	var num = 0
	for k in 0..d:
		num = num * 10 + DIGITS.index_of(ch(s, ind + k)).get(0)
	return Marker(ok: true, ordered: true, delim: dl, num: num, width: ind + d + 1)

fn sameKind(a: Marker, b: Marker) Bool:
	return a.ok and b.ok and a.ordered == b.ordered and a.delim == b.delim

fn isQuote(s: String) Bool:
	return indentOf(s) <= 3 and ch(s, indentOf(s)) == ">"

// Lines that end a table body (and cannot be table rows).
fn blockStops(s: String) Bool:
	return isBlank(s) or fenceRun(s) > 0 or headingLevel(s) > 0 or isHr(s) or isQuote(s)

// Lines that end a paragraph (a list interrupts only when it is non-empty and starts at
// 1).
fn paraStops(s: String) Bool:
	if blockStops(s): return true

	m := markerAt(s)
	if not m.ok: return false
	if isBlank(cut(s, m.width, s.length())): return false

	return not m.ordered or m.num == 1

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

fn splitCells(line: String) List[String]:
	var s = strip(line)
	if ch(s, 0) == "|":
		s = cut(s, 1, s.length())

	L := s.length()
	if L > 0 and ch(s, L - 1) == "|" and ch(s, L - 2) != "\\":
		s = cut(s, 0, L - 1)

	var cells = List[String]()
	var cur = ""
	m := s.length()

	for k in 0..m:
		c := ch(s, k)

		if c == "|" and ch(s, k - 1) != "\\":
			cells.append(strip(cur))
			cur = ""
		else:
			cur += c

	cells.append(strip(cur))
	return cells

fn isDelimCell(c: String) Bool:
	var a = 0
	var b = c.length()
	if ch(c, 0) == ":":
		a = 1
	if b > a and ch(c, b - 1) == ":":
		b -= 1
	if b <= a: return false

	var k = a

	while k < b:
		if ch(c, k) != "-": return false

		k += 1

	return true

fn isDelimRow(s: String) Bool:
	if not s.contains("|"): return false

	for c in splitCells(s):
		if not isDelimCell(c): return false
	return true

// 0 none, 1 left, 2 center, 3 right
fn alignOf(c: String) Int:
	l := ch(c, 0) == ":"
	r := c.length() > 1 and ch(c, c.length() - 1) == ":"
	if l and r: return 2
	if l: return 1
	if r: return 3

	return 0

fn alignAttr(a: Int) String:
	if a == 1: return " align=\"left\""
	if a == 2: return " align=\"center\""
	if a == 3: return " align=\"right\""

	return ""

// ---------------------------------------------------------------------------
// Block parsing
// ---------------------------------------------------------------------------

fn htmlOf(nodes: List[Block]) String:
	var out = ""
	for nd in nodes:
		out += nd.html
	return out

// Body of a list item. A paragraph in a tight list contributes only its inline HTML.
fn itemBody(kids: List[Block], tight: Bool) String:
	var body = ""

	for c in kids:
		if c.is_para and tight:
			body += c.inl
		else:
			if body.is_empty() or not body.ends_with("\n"):
				body += "\n"
			body += c.html

	return body

fn parseFence(lines: List[String], i: Int, run: Int) Step:
	n := lines.length()
	s := lines[i]
	ind := indentOf(s)
	c := ch(s, ind)
	info := strip(cut(s, ind + run, s.length()))
	var close = n
	var j = i + 1

	while j < n:
		l := lines[j]
		li := indentOf(l)

		if li <= 3 and ch(l, li) == c:
			var r = li
			while ch(l, r) == c:
				r += 1

			if r - li >= run and isBlank(cut(l, r, l.length())):
				close = j
				break

		j += 1

	var body = ""
	var k = i + 1

	while k < close:
		l := lines[k]
		var cutn = indentOf(l)
		if cutn > ind:
			cutn = ind
		body += esc(cut(l, cutn, l.length())) + "\n"
		k += 1

	var opening = "<pre><code>"

	if not info.is_empty():
		var w = 0
		while ch(info, w) != "" and ch(info, w) != " ":
			w += 1
		opening = "<pre><code class=\"language-" + esc(cut(info, 0, w)) + "\">"

	nxt := if close < n: close + 1 else: n
	return Step(node: Block(html: opening + body + "</code></pre>\n"), next: nxt)

fn parseQuote(lines: List[String], i: Int) Step:
	n := lines.length()
	var inner = List[String]()
	var j = i

	while j < n:
		if not isQuote(lines[j]): break

		l := lines[j]
		var rest = cut(l, indentOf(l) + 1, l.length())
		if ch(rest, 0) == " ":
			rest = cut(rest, 1, rest.length())
		inner.append(rest)
		j += 1

	kids := parseBlocks(inner)
	return Step(
		node: Block(html: "<blockquote>\n" + htmlOf(kids) + "</blockquote>\n"), next: j
	)

fn parseIndented(lines: List[String], i: Int) Step:
	n := lines.length()
	var j = i
	var last = i

	while j < n:
		l := lines[j]
		if (not isBlank(l)) and indentOf(l) < 4: break

		if not isBlank(l):
			last = j
		j += 1

	var body = ""
	var k = i

	while k <= last:
		l := lines[k]
		var cutn = indentOf(l)
		if cutn > 4:
			cutn = 4
		body += esc(cut(l, cutn, l.length())) + "\n"
		k += 1

	return Step(
		node: Block(html: "<pre><code>" + body + "</code></pre>\n"), next: last + 1
	)

fn parseTable(lines: List[String], i: Int) Step:
	n := lines.length()
	head := splitCells(lines[i])
	delim := splitCells(lines[i + 1])
	var aligns = List[Int]()
	for c in delim:
		aligns.append(alignOf(c))

	var rows = List[List[String]]()
	var j = i + 2

	while j < n:
		if blockStops(lines[j]): break

		rows.append(splitCells(lines[j]))
		j += 1

	ncols := head.length()
	var out = "<table>\n<thead>\n<tr>\n"
	for k in 0..ncols:
		out += "<th" + alignAttr(aligns[k]) + ">" + inlineHtml(head[k]) + "</th>\n"
	out += "</tr>\n</thead>\n"

	if not rows.is_empty():
		out += "<tbody>\n"

		for r in rows:
			out += "<tr>\n"

			for q in 0..ncols:
				cell := if q < r.length(): r[q].clone() else: ""
				out += "<td" + alignAttr(aligns[q]) + ">" + inlineHtml(cell) + "</td>\n"

			out += "</tr>\n"

		out += "</tbody>\n"

	out += "</table>\n"
	return Step(node: Block(html: out), next: j)

fn parsePara(lines: List[String], i: Int) Step:
	n := lines.length()
	var j = i + 1

	while j < n:
		if paraStops(lines[j]): break

		j += 1

	var text = ""
	var k = i

	while k < j:
		text += strip(lines[k])

		if k < j - 1:
			// two or more trailing spaces: hard break, marked with a tab before the
			// newline
			if trailingSpaces(lines[k]) >= 2:
				text += "\t"
			text += "\n"

		k += 1

	inl := inlineHtml(text)
	return Step(
		node: Block(is_para: true, html: "<p>" + inl + "</p>\n", inl: inl), next: j
	)

fn parseList(lines: List[String], i: Int) Step:
	n := lines.length()
	first := markerAt(lines[i])
	var items = List[List[Block]]()
	var between = false
	var j = i
	var last = i
	var go = true

	while go:
		s := lines[j]
		m := markerAt(s)
		mw := m.width
		var w = mw + 1
		var content = List[String]()

		if isBlank(cut(s, mw, s.length())):
			content.append("")
		else:
			var sp = 0
			while ch(s, mw + sp) == " ":
				sp += 1

			if sp >= 5:
				w = mw + 1
			else:
				w = mw + sp

			content.append(cut(s, w, s.length()))

		var pending = 0
		var k = j + 1
		var lastIdx = j

		while k < n:
			l := lines[k]

			if isBlank(l):
				pending += 1
			else if indentOf(l) >= w:
				for q in 0..pending:
					content.append("")
				pending = 0
				content.append(cut(l, w, l.length()))
				lastIdx = k
			else:
				break

			k += 1

		items.append(parseBlocks(content))
		last = lastIdx

		nextSame := if k < n: sameKind(markerAt(lines[k]), first) and not isHr(lines[k]) else: false

		if nextSame:
			if pending > 0:
				between = true
			j = k
		else:
			go = false

	var loose = between
	for kids in items:
		for c in kids:
			if c.blank:
				loose = true

	tight := not loose
	var out = "<ul>\n"

	if first.ordered:
		if first.num == 1:
			out = "<ol>\n"
		else:
			out = "<ol start=\"{first.num}\">\n"

	for kids in items:
		out += "<li>" + itemBody(kids, tight) + "</li>\n"

	if first.ordered:
		out += "</ol>\n"
	else:
		out += "</ul>\n"

	return Step(node: Block(html: out), next: last + 1)

// Parse the block starting at line i (which is not blank).
fn blockAt(lines: List[String], i: Int) Step:
	s := lines[i]
	fr := fenceRun(s)
	if fr > 0: return parseFence(lines, i, fr)

	hl := headingLevel(s)

	if hl > 0:
		var content = strip(cut(s, indentOf(s) + hl, s.length()))
		e := content.length()
		var r = e
		while r > 0 and ch(content, r - 1) == "#":
			r -= 1
		if r < e and (r == 0 or ch(content, r - 1) == " "):
			content = rstrip(cut(content, 0, r))
		return Step(
			node: Block(
				html: "<h{hl}>" + inlineHtml(content) + "</h{hl}>\n"
			),
			next: i + 1
		)

	if isHr(s): return Step(node: Block(html: "<hr />\n"), next: i + 1)
	if isQuote(s): return parseQuote(lines, i)
	if markerAt(s).ok: return parseList(lines, i)
	if indentOf(s) >= 4: return parseIndented(lines, i)

	if i + 1 < lines.length() and s.contains("|") and isDelimRow(lines[i + 1]):
		if splitCells(s).length() == splitCells(lines[i + 1]).length():
			return parseTable(lines, i)
	return parsePara(lines, i)

fn parseBlocks(lines: List[String]) List[Block]:
	var out = List[Block]()
	n := lines.length()
	var i = 0
	var sawBlank = false

	while i < n:
		if isBlank(lines[i]):
			sawBlank = true
			i += 1
			continue

		st := blockAt(lines, i)
		var nd = st.node.clone()
		nd.blank = sawBlank and out.length() > 0
		out.append(nd)
		sawBlank = false
		i = st.next

	return out

// ---------------------------------------------------------------------------
// Inline: scanning
// ---------------------------------------------------------------------------

// Parses the link tail starting at cs[p] == "(".
fn tailAt(cs: List[String], p: Int) Tail:
	var q = p + 1
	while isSpNl(cat(cs, q)):
		q += 1

	var dest = ""

	if cat(cs, q) == "<":
		q += 1

		var closed = false

		while not closed:
			c := cat(cs, q)
			if c == "" or c == "\n" or c == "<": return Tail(ok: false)

			if c == "\\" and isPunct(cat(cs, q + 1)):
				dest += cat(cs, q + 1)
				q += 2
			else if c == ">":
				closed = true
				q += 1
			else:
				dest += c
				q += 1
	else:
		var depth = 0
		var go = true

		while go:
			c := cat(cs, q)

			if c == "" or isSpNl(c):
				go = false
			else if c == "\\" and isPunct(cat(cs, q + 1)):
				dest += cat(cs, q + 1)
				q += 2
			else if c == "(":
				depth += 1
				dest += c
				q += 1
			else if c == ")":
				if depth == 0:
					go = false
				else:
					depth -= 1
					dest += c
					q += 1
			else:
				dest += c
				q += 1

		if depth != 0: return Tail(ok: false)

	var ws = 0

	while isSpNl(cat(cs, q)):
		q += 1
		ws += 1

	var title = ""
	var has = false

	if ws >= 1 and cat(cs, q) == "\"":
		q += 1

		var closedT = false

		while not closedT:
			c := cat(cs, q)
			if c == "": return Tail(ok: false)

			if c == "\\" and cat(cs, q + 1) == "\"":
				title += "\""
				q += 2
			else if c == "\"":
				closedT = true
				q += 1
			else:
				title += c
				q += 1

		has = true
		while isSpNl(cat(cs, q)):
			q += 1

	if cat(cs, q) != ")": return Tail(ok: false)

	return Tail(ok: true, dest: dest, title: title, has_title: has, after: q + 1)

// Scan the paragraph/heading/cell text into a node list (emphasis not yet resolved).
fn scan(cs: List[String]) List[Inline]:
	var nodes = List[Inline]()
	n := cs.length()
	var p = 0

	while p < n:
		c := cat(cs, p)

		if c == "\\":
			d := cat(cs, p + 1)

			if d == "\n":
				nodes.append(Inline(kind: 2))
				p += 2
			else if isPunct(d):
				nodes.append(Inline(kind: 0, text: d))
				p += 2
			else:
				nodes.append(Inline(kind: 0, text: "\\"))
				p += 1
		else if c == "\t" and cat(cs, p + 1) == "\n":
			nodes.append(Inline(kind: 2))
			p += 2
		else if c == "`":
			var r = p
			while cat(cs, r) == "`":
				r += 1

			run := r - p
			var j = r
			var found = -1

			while j < n:
				if cat(cs, j) == "`":
					var e = j
					while cat(cs, e) == "`":
						e += 1

					if e - j == run:
						found = j
						break

					j = e
				else:
					j += 1

			if found < 0:
				for z in 0..run:
					nodes.append(Inline(kind: 0, text: "`"))
				p = r
			else:
				var content = ""
				var q = r

				while q < found:
					x := cat(cs, q)

					if x == "\n":
						content += " "
					else if x != "\t":
						content += x

					q += 1

				if (
					content.starts_with(" ")
					and content.ends_with(" ")
					and not isAllSpace(content)
				):
					content = cut(content, 1, content.length() - 1)
				nodes.append(Inline(kind: 1, text: content))
				p = found + run
		else if c == "*" or c == "_":
			var r = p
			while cat(cs, r) == c:
				r += 1

			prev := cat(cs, p - 1)
			nxt := cat(cs, r)
			left := (
				(not isWs(nxt))
				and ((not isPunct(nxt)) or isWs(prev) or isPunct(prev))
			)
			right := (
				(not isWs(prev))
				and ((not isPunct(prev)) or isWs(nxt) or isPunct(nxt))
			)
			var can_open = left
			var can_close = right

			if c == "_":
				can_open = left and ((not right) or isPunct(prev))
				can_close = right and ((not left) or isPunct(nxt))

			nodes.append(
				Inline(
					kind: 3, text: c, cnt: r - p, orig: r - p, can_open: can_open,
					can_close: can_close
				)
			)
			p = r
		else if c == "!" and cat(cs, p + 1) == "[":
			nodes.append(Inline(kind: 9, text: "!["))
			p += 2
		else if c == "[":
			nodes.append(Inline(kind: 4, text: "["))
			p += 1
		else if c == "]":
			var m = -1
			var k = nodes.length() - 1

			while k >= 0:
				kd := nodes[k].kind

				if kd == 4 or kd == 9 or kd == 10:
					m = k
					break

				k -= 1

			if m < 0:
				nodes.append(Inline(kind: 0, text: "]"))
				p += 1
			else if nodes[m].kind == 10:
				nodes[m].kind = 0
				nodes.append(Inline(kind: 0, text: "]"))
				p += 1
			else:
				var t = Tail(ok: false)
				if cat(cs, p + 1) == "(":
					t = tailAt(cs, p + 1)

				if t.ok:
					is_img := nodes[m].kind == 9
					if not is_img:
						for z in 0..m:
							if nodes[z].kind == 4:
								nodes[z].kind = 10

					var kids = List[Inline]()
					var q = m + 1

					while q < nodes.length():
						kids.append(nodes[q].clone())
						q += 1

					var made = Inline(
						kind: 7, text: t.dest, title: t.title, has_title: t.has_title,
						kids: resolve(kids)
					)
					if is_img:
						made.kind = 8

					var one = List[Inline]()
					one.append(made)
					nodes.splice(m, nodes.length() - m, one)
					p = t.after
				else:
					nodes[m].kind = 0
					nodes.append(Inline(kind: 0, text: "]"))
					p += 1
		else:
			nodes.append(Inline(kind: 0, text: c))
			p += 1

	return nodes

// ---------------------------------------------------------------------------
// Inline: emphasis resolution
// ---------------------------------------------------------------------------

// Delimiter runs become literal text; markers become literal text.
fn literalize(nd: Inline) Inline:
	if nd.kind == 3: return Inline(kind: 0, text: repeatStr(nd.text, nd.cnt))
	if nd.kind == 4 or nd.kind == 9 or nd.kind == 10:
		return Inline(kind: 0, text: nd.text)

	return nd.clone()

// The multiple-of-3 rule.
fn multipleOk(o: Inline, c: Inline) Bool:
	if (o.can_close or c.can_open) and (o.orig + c.orig) % 3 == 0:
		return o.orig % 3 == 0 and c.orig % 3 == 0
	return true

fn findOpener(nodes: List[Inline], i: Int) Int:
	var k = i - 1

	while k >= 0:
		o := nodes[k]
		if o.kind == 3 and o.text == nodes[i].text and o.can_open and o.cnt > 0:
			if multipleOk(o, nodes[i]): return k
		k -= 1

	return -1

fn resolve(input: List[Inline]) List[Inline]:
	var nodes = input
	var i = 0

	while i < nodes.length():
		if nodes[i].kind == 3 and nodes[i].can_close and nodes[i].cnt > 0:
			j := findOpener(nodes, i)

			if j < 0:
				i += 1
			else:
				use := if nodes[j].cnt >= 2 and nodes[i].cnt >= 2: 2 else: 1
				var inner = List[Inline]()
				var q = j + 1

				while q < i:
					inner.append(literalize(nodes[q].clone()))
					q += 1

				em := if use == 2: 6 else: 5
				var one = List[Inline]()
				one.append(Inline(kind: em, kids: inner))
				nodes.splice(j + 1, i - j - 1, one)
				nodes[j].cnt -= use
				nodes[j + 2].cnt = nodes[j + 2].cnt - use

				var em_idx = j + 1
				if nodes[j + 2].cnt == 0:
					nodes.splice(j + 2, 1, List[Inline]())

				if nodes[j].cnt == 0:
					nodes.splice(j, 1, List[Inline]())
					em_idx = j

				i = em_idx + 1
		else:
			i += 1

	var out = List[Inline]()
	for nd in nodes:
		out.append(literalize(nd))
	return out

// ---------------------------------------------------------------------------
// Inline: rendering
// ---------------------------------------------------------------------------

fn plain(nodes: List[Inline]) String:
	var out = ""

	for nd in nodes:
		if nd.kind == 0 or nd.kind == 1:
			out += nd.text.replace("\n", " ")
		else if nd.kind == 2:
			out += " "
		else if nd.kind == 5 or nd.kind == 6 or nd.kind == 7 or nd.kind == 8:
			out += plain(nd.kids)

	return out

fn render(nodes: List[Inline]) String:
	var out = ""

	for nd in nodes:
		if nd.kind == 0:
			out += esc(nd.text)
		else if nd.kind == 1:
			out += "<code>" + esc(nd.text) + "</code>"
		else if nd.kind == 2:
			out += "<br />\n"
		else if nd.kind == 5:
			out += "<em>" + render(nd.kids) + "</em>"
		else if nd.kind == 6:
			out += "<strong>" + render(nd.kids) + "</strong>"
		else if nd.kind == 7:
			t := if nd.has_title: " title=\"" + esc(nd.title) + "\"" else: ""
			out += (
				"<a href=\""
				+ esc(nd.text)
				+ "\""
				+ t
				+ ">"
				+ render(nd.kids)
				+ "</a>"
			)
		else if nd.kind == 8:
			t2 := if nd.has_title: " title=\"" + esc(nd.title) + "\"" else: ""
			out += (
				"<img src=\""
				+ esc(nd.text)
				+ "\" alt=\""
				+ esc(plain(nd.kids))
				+ "\""
				+ t2
				+ " />"
			)

	return out

fn inlineHtml(text: String) String:
	if text.is_empty(): return ""
	return render(resolve(scan(text.split_after(""))))

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export fn main() Int:
	bytes := read_all(stdin()).get()
	text := bytes.decode_utf8().get("")
	var lines = List[String]()

	if not text.is_empty():
		lines = text.split("\n")

		cnt := lines.length()
		if lines[cnt - 1] == "":
			lines.splice(cnt - 1, 1, List[String]())

	var out = ""
	for nd in parseBlocks(lines):
		out += nd.html
	stdout().write(out).get()
	return 0

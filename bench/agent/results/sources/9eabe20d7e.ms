import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

// ---------- helpers ----------

fn esc(s: String) String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

fn chr(s: String, k: Int) String:
	if k < 0 or k >= s.length(): return ""
	return s.view(k, k + 1).clone()

fn rest(s: String, k: Int) String:
	if k >= s.length(): return ""
	return s.view(k, s.length()).clone()

fn indentOf(s: String) Int:
	var k = 0
	n := s.length()
	while k < n and s.view(k, k + 1) == " ":
		k += 1
	return k

fn isBlank(s: String) Bool:
	return indentOf(s) == s.length()

fn rep(c: String, n: Int) String:
	var r = ""
	for _i in 0..n:
		r += c
	return r

fn isPunct(c: String) Bool:
	if c.length() != 1: return false
	return "!\"#$%&'()*+,-./:;<=>?@[\\]^_`\{|\}~".contains(c)

fn isDigit(c: String) Bool:
	if c.length() != 1: return false
	return "0123456789".contains(c)

fn isWs(c: String) Bool:
	return c == "" or c == " " or c == "\n" or c == "\u{1}"

// ---------- inline ----------

type Node:
	kind: Int = 0
	text: String = ""
	count: Int = 0
	orig: Int = 0
	can_open: Bool = false
	can_close: Bool = false
	active: Bool = true
	is_image: Bool = false
	kids: List[Int] = []
	title: String = ""
	has_title: Bool = false

type Inl:
	nodes: List[Node] = []

type Tail:
	ok: Bool = false
	dest: String = ""
	title: String = ""
	has_title: Bool = false
	end: Int = 0

fn skipWs(cs: List[String], start: Int) Int:
	var p = start
	while true:
		c := cs.get(p, "")
		if c == " " or c == "\n" or c == "\u{1}":
			p += 1
		else:
			break
	return p

fn parseTail(cs: List[String], start: Int) Tail:
	var p = skipWs(cs, start)
	var dest = ""
	if cs.get(p, "") == "<":
		p += 1
		while true:
			ch := cs.get(p, "")
			if ch == "" or ch == "\n" or ch == "\u{1}" or ch == "<": return Tail()
			if ch == ">":
				p += 1
				break
			nx := cs.get(p + 1, "")
			if ch == "\\" and isPunct(nx):
				dest += nx
				p += 2
			else:
				dest += ch
				p += 1
	else:
		var depth = 0
		while true:
			ch := cs.get(p, "")
			if ch == "" or ch == " " or ch == "\n" or ch == "\u{1}": break
			nx := cs.get(p + 1, "")
			if ch == "\\" and isPunct(nx):
				dest += nx
				p += 2
				continue
			if ch == "(":
				depth += 1
			else if ch == ")":
				if depth == 0: break
				depth -= 1
			dest += ch
			p += 1
		if depth != 0: return Tail()
	p2 := skipWs(cs, p)
	skipped := p2 > p
	p = p2
	var title = ""
	var hasTitle = false
	if skipped and cs.get(p, "") == "\"":
		p += 1
		var closed = false
		while true:
			ch := cs.get(p, "")
			if ch == "": break
			nx := cs.get(p + 1, "")
			if ch == "\\" and isPunct(nx):
				title += nx
				p += 2
			else if ch == "\"":
				p += 1
				closed = true
				break
			else:
				title += ch
				p += 1
		if not closed: return Tail()
		hasTitle = true
		p = skipWs(cs, p)
	if cs.get(p, "") != ")": return Tail()
	return Tail(true, dest, title, hasTitle, p + 1)

fn altText(nodes: List[Node], id: Int) String:
	nd := nodes[id]
	var r = ""
	if nd.kind == 0:
		return nd.text.replace("\n", " ").clone()
	if nd.kind == 3: return nd.text.clone()
	if nd.kind == 4: return " "
	if nd.kind == 1: return rep(nd.text, nd.count)
	if nd.kind == 2:
		if nd.is_image: return "!["
		return "["
	for k in nd.kids:
		r += altText(nodes, k)
	return r

fn renderNode(nodes: List[Node], id: Int) String:
	nd := nodes[id]
	if nd.kind == 0: return esc(nd.text)
	if nd.kind == 3: return "<code>" + esc(nd.text) + "</code>"
	if nd.kind == 4: return "<br />\n"
	if nd.kind == 1: return esc(rep(nd.text, nd.count))
	if nd.kind == 2:
		if nd.is_image: return "!["
		return "["
	var inner = ""
	for k in nd.kids:
		inner += renderNode(nodes, k)
	if nd.kind == 5: return "<em>" + inner + "</em>"
	if nd.kind == 6: return "<strong>" + inner + "</strong>"
	var t = ""
	if nd.has_title: t = " title=\"" + esc(nd.title) + "\""
	if nd.kind == 7: return "<a href=\"" + esc(nd.text) + "\"" + t + ">" + inner + "</a>"
	var alt = ""
	for k in nd.kids:
		alt += altText(nodes, k)
	return "<img src=\"" + esc(nd.text) + "\" alt=\"" + esc(alt) + "\"" + t + " />"

fn var Inl.add(node: Node) Int:
	self.nodes.append(node)
	return self.nodes.length() - 1

fn var Inl.flush(var out: List[Int], var buf: String) Unit:
	if buf.length() > 0:
		id := self.add(Node(kind: 0, text: buf.clone()))
		out.append(id)
		buf = ""

fn var Inl.resolve(ids: List[Int]) List[Int]:
	var w = ids.clone()
	var i = 0
	while i < w.length():
		cid := w[i]
		if self.nodes[cid].kind == 1 and self.nodes[cid].can_close and self.nodes[cid].count > 0:
			var found = -1
			var o = i - 1
			while o >= 0:
				oid := w[o]
				op := self.nodes[oid]
				if op.kind == 1 and op.text == self.nodes[cid].text and op.can_open and op.count > 0:
					cl := self.nodes[cid]
					var ok = true
					if (op.can_close or cl.can_open) and (op.orig + cl.orig) % 3 == 0:
						if not (op.orig % 3 == 0 and cl.orig % 3 == 0):
							ok = false
					if ok:
						found = o
						break
				o -= 1
			if found < 0:
				i += 1
				continue
			oid := w[found]
			use := if self.nodes[oid].count >= 2 and self.nodes[cid].count >= 2: 2 else: 1
			var kids = List[Int]()
			for t in (found + 1)..i:
				kids.append(w[t])
			nid := self.add(Node(kind: if use == 2: 6 else: 5, kids: kids))
			self.nodes[oid].count -= use
			self.nodes[cid].count -= use
			var nw = List[Int]()
			for t in 0..found:
				nw.append(w[t])
			if self.nodes[oid].count > 0: nw.append(oid)
			nw.append(nid)
			ni := nw.length()
			if self.nodes[cid].count > 0: nw.append(cid)
			for t in (i + 1)..w.length():
				nw.append(w[t])
			w = nw
			i = ni
		else:
			i += 1
	return w

fn var Inl.parse(text: String) List[Int]:
	cs := text.chars()
	n := cs.length()
	var out = List[Int]()
	var buf = ""
	var i = 0
	while i < n:
		c := cs[i]
		if c == "\\":
			nx := cs.get(i + 1, "")
			if nx == "\n":
				self.flush(var out, var buf)
				out.append(self.add(Node(kind: 4)))
				i += 2
			else if isPunct(nx):
				buf += nx
				i += 2
			else:
				buf += "\\"
				i += 1
			continue
		if c == "\u{1}":
			self.flush(var out, var buf)
			out.append(self.add(Node(kind: 4)))
			i += 1
			continue
		if c == "`":
			var k = 0
			while cs.get(i + k, "") == "`":
				k += 1
			var j = i + k
			var found = -1
			while j < n:
				if cs[j] == "`":
					var m = 0
					while cs.get(j + m, "") == "`":
						m += 1
					if m == k:
						found = j
						break
					j += m
				else:
					j += 1
			if found >= 0:
				var content = ""
				for t in (i + k)..found:
					ch := cs[t]
					if ch == "\n" or ch == "\u{1}":
						content += " "
					else:
						content += ch
				if content.length() >= 2 and content.starts_with(" ") and content.ends_with(" ") and content.trim() != "":
					content = content.view(1, content.length() - 1).clone()
				self.flush(var out, var buf)
				out.append(self.add(Node(kind: 3, text: content.clone())))
				i = found + k
			else:
				buf += rep("`", k)
				i += k
			continue
		if c == "*" or c == "_":
			var k = 0
			while cs.get(i + k, "") == c:
				k += 1
			prev := if i > 0: cs[i - 1].clone() else: ""
			next := cs.get(i + k, "")
			left := not isWs(next) and (not isPunct(next) or isWs(prev) or isPunct(prev))
			right := not isWs(prev) and (not isPunct(prev) or isWs(next) or isPunct(next))
			var co = left
			var cc = right
			if c == "_":
				co = left and (not right or isPunct(prev))
				cc = right and (not left or isPunct(next))
			self.flush(var out, var buf)
			out.append(self.add(Node(kind: 1, text: c.clone(), count: k, orig: k, can_open: co, can_close: cc)))
			i += k
			continue
		if c == "[":
			self.flush(var out, var buf)
			out.append(self.add(Node(kind: 2)))
			i += 1
			continue
		if c == "!" and cs.get(i + 1, "") == "[":
			self.flush(var out, var buf)
			out.append(self.add(Node(kind: 2, is_image: true)))
			i += 2
			continue
		if c == "]":
			self.flush(var out, var buf)
			var m = -1
			var q = out.length() - 1
			while q >= 0:
				if self.nodes[out[q]].kind == 2:
					m = q
					break
				q -= 1
			if m < 0:
				buf += "]"
				i += 1
				continue
			mid := out[m]
			isImg := self.nodes[mid].is_image
			if not isImg and not self.nodes[mid].active:
				self.nodes[mid] = Node(kind: 0, text: "[")
				buf += "]"
				i += 1
				continue
			if cs.get(i + 1, "") == "(":
				tail := parseTail(cs, i + 2)
				if tail.ok:
					var raw = List[Int]()
					for t in (m + 1)..out.length():
						raw.append(out[t])
					kids := self.resolve(raw)
					nid := self.add(Node(kind: if isImg: 8 else: 7, text: tail.dest.clone(), kids: kids, title: tail.title.clone(), has_title: tail.has_title))
					var no = List[Int]()
					for t in 0..m:
						no.append(out[t])
					no.append(nid)
					out = no
					if not isImg:
						for t in 0..m:
							if self.nodes[out[t]].kind == 2 and not self.nodes[out[t]].is_image:
								self.nodes[out[t]].active = false
					i = tail.end
					continue
			if isImg:
				self.nodes[mid] = Node(kind: 0, text: "![")
			else:
				self.nodes[mid] = Node(kind: 0, text: "[")
			buf += "]"
			i += 1
			continue
		buf += c
		i += 1
	self.flush(var out, var buf)
	return self.resolve(out)

fn inline(text: String) String:
	var st = Inl()
	ids := st.parse(text)
	var r = ""
	for id in ids:
		r += renderNode(st.nodes, id)
	return r

// ---------- blocks ----------

type Block:
	para: Bool = false
	text: String = ""
	blank: Bool = false

type Res:
	ok: Bool = false
	next: Int = 0
	text: String = ""

type Fence:
	ok: Bool = false
	ind: Int = 0
	ch: String = ""
	n: Int = 0
	info: String = ""

fn fenceOpen(line: String) Fence:
	ind := indentOf(line)
	if ind > 3: return Fence()
	c := chr(line, ind)
	if c != "`" and c != "~": return Fence()
	var k = ind
	while chr(line, k) == c:
		k += 1
	n := k - ind
	if n < 3: return Fence()
	info := rest(line, k).trim()
	if c == "`" and info.contains("`"): return Fence()
	return Fence(true, ind, c.clone(), n, info.clone())

fn isFenceClose(line: String, ch: String, n: Int) Bool:
	ind := indentOf(line)
	if ind > 3: return false
	var k = ind
	while chr(line, k) == ch:
		k += 1
	if k - ind < n: return false
	return rest(line, k).trim() == ""

type Atx:
	ok: Bool = false
	level: Int = 0
	content: String = ""

fn atx(line: String) Atx:
	ind := indentOf(line)
	if ind > 3: return Atx()
	var k = ind
	while chr(line, k) == "#":
		k += 1
	lv := k - ind
	if lv < 1 or lv > 6: return Atx()
	nx := chr(line, k)
	if nx != "" and nx != " ": return Atx()
	var content = rest(line, k).trim()
	n := content.length()
	if n > 0 and chr(content, n - 1) == "#":
		var r = n
		while r > 0 and chr(content, r - 1) == "#":
			r -= 1
		if r == 0:
			content = ""
		else if chr(content, r - 1) == " ":
			content = content.view(0, r).trim_end()
	return Atx(true, lv, content.clone())

fn isThematic(line: String) Bool:
	if indentOf(line) > 3: return false
	s := line.replace(" ", "")
	if s.length() < 3: return false
	c := chr(s, 0)
	if c != "-" and c != "*" and c != "_": return false
	for k in 1..s.length():
		if chr(s, k) != c: return false
	return true

fn isQuote(line: String) Bool:
	ind := indentOf(line)
	return ind <= 3 and chr(line, ind) == ">"

type Marker:
	ok: Bool = false
	ordered: Bool = false
	ch: String = ""
	num: Int = 0
	w: Int = 0
	empty: Bool = true

fn marker(line: String) Marker:
	ind := indentOf(line)
	if ind > 3: return Marker()
	c := chr(line, ind)
	var ordered = false
	var num = 0
	var ch = ""
	var mend = ind
	if c == "-" or c == "*" or c == "+":
		ch = c.clone()
		mend = ind + 1
	else if isDigit(c):
		var k = ind
		while isDigit(chr(line, k)):
			num = num * 10 + (line.scalar_at(k) - 48)
			k += 1
		if k - ind > 9: return Marker()
		d := chr(line, k)
		if d != "." and d != ")": return Marker()
		ordered = true
		ch = d.clone()
		mend = k + 1
	else:
		return Marker()
	nx := chr(line, mend)
	if nx != "" and nx != " ": return Marker()
	r := rest(line, mend)
	if r.trim() == "":
		return Marker(true, ordered, ch, num, mend + 1, true)
	nsp := indentOf(r)
	if nsp >= 5:
		return Marker(true, ordered, ch, num, mend + 1, false)
	return Marker(true, ordered, ch, num, mend + nsp, false)

fn interrupts(line: String) Bool:
	m := marker(line)
	if not m.ok or m.empty: return false
	if m.ordered and m.num != 1: return false
	return true

fn startsBlock(line: String) Bool:
	return fenceOpen(line).ok or atx(line).ok or isThematic(line) or isQuote(line)

fn blockHtml(b: Block) String:
	if b.para: return "<p>" + b.text + "</p>\n"
	return b.text.clone()

fn joinBlocks(bs: List[Block]) String:
	var r = ""
	for b in bs:
		r += blockHtml(b)
	return r

fn tryFence(lines: List[String], i: Int) Res:
	f := fenceOpen(lines[i])
	if not f.ok: return Res()
	n := lines.length()
	var j = i + 1
	var body = ""
	while j < n:
		l := lines[j]
		if isFenceClose(l, f.ch, f.n):
			j += 1
			break
		strip := if indentOf(l) < f.ind: indentOf(l) else: f.ind
		body += esc(rest(l, strip)) + "\n"
		j += 1
	var cls = ""
	if f.info != "":
		word := f.info.split(" ").get(0, "")
		cls = " class=\"language-" + esc(word) + "\""
	return Res(true, j, "<pre><code" + cls + ">" + body + "</code></pre>\n")

fn tryQuote(lines: List[String], i: Int) Res:
	if not isQuote(lines[i]): return Res()
	n := lines.length()
	var sub = List[String]()
	var j = i
	while j < n and isQuote(lines[j]):
		l := lines[j]
		var k = indentOf(l) + 1
		if chr(l, k) == " ": k += 1
		sub.append(rest(l, k).clone())
		j += 1
	inner := joinBlocks(parseBlocks(sub))
	return Res(true, j, "<blockquote>\n" + inner + "</blockquote>\n")

fn renderItem(kids: List[Block], tight: Bool) String:
	var body = ""
	for b in kids:
		if b.para and tight:
			body += b.text
		else:
			if not body.ends_with("\n"): body += "\n"
			body += blockHtml(b)
	return "<li>" + body + "</li>\n"

fn tryList(lines: List[String], i: Int) Res:
	m0 := marker(lines[i])
	if not m0.ok: return Res()
	n := lines.length()
	var items = List[List[Block]]()
	var loose = false
	var j = i
	var endAt = i
	while true:
		mk := marker(lines[j])
		l0 := lines[j]
		var sub = List[String]()
		sub.append(rest(l0, mk.w).clone())
		var k = j + 1
		var last = j
		var pend = 0
		while k < n:
			l := lines[k]
			if isBlank(l):
				pend += 1
				k += 1
				continue
			if indentOf(l) >= mk.w:
				for _p in 0..pend:
					sub.append("")
				pend = 0
				sub.append(rest(l, mk.w).clone())
				last = k
				k += 1
			else:
				break
		kids := parseBlocks(sub)
		for b in kids:
			if b.blank: loose = true
		items.append(kids)
		endAt = last + 1
		var q = endAt
		while q < n and isBlank(lines[q]):
			q += 1
		if q < n:
			nm := marker(lines[q])
			if nm.ok and not isThematic(lines[q]) and nm.ordered == m0.ordered and nm.ch == m0.ch:
				if q > endAt: loose = true
				j = q
				continue
		break
	var html = ""
	if m0.ordered:
		if m0.num != 1:
			html += "<ol start=\"" + "{m0.num}" + "\">\n"
		else:
			html += "<ol>\n"
	else:
		html += "<ul>\n"
	for it in items:
		html += renderItem(it, not loose)
	if m0.ordered:
		html += "</ol>\n"
	else:
		html += "</ul>\n"
	return Res(true, endAt, html)

fn tryIndented(lines: List[String], i: Int) Res:
	if indentOf(lines[i]) < 4: return Res()
	n := lines.length()
	var j = i
	var last = i
	while j < n:
		l := lines[j]
		if isBlank(l):
			j += 1
			continue
		if indentOf(l) >= 4:
			last = j
			j += 1
		else:
			break
	var body = ""
	for t in i..(last + 1):
		l := lines[t]
		strip := if indentOf(l) < 4: indentOf(l) else: 4
		body += esc(rest(l, strip)) + "\n"
	return Res(true, last + 1, "<pre><code>" + body + "</code></pre>\n")

fn splitCells(line: String) List[String]:
	var s = line.trim()
	if s.starts_with("|"):
		s = rest(s, 1).clone()
	n := s.length()
	if n > 0 and chr(s, n - 1) == "|" and chr(s, n - 2) != "\\":
		s = s.view(0, n - 1).clone()
	var cells = List[String]()
	var cur = ""
	for k in 0..s.length():
		c := chr(s, k)
		if c == "|" and chr(s, k - 1) != "\\":
			cells.append(cur.trim().clone())
			cur = ""
		else:
			cur += c
	cells.append(cur.trim().clone())
	return cells

fn isDelimCell(cell: String) Bool:
	var c = cell.clone()
	if c.starts_with(":"): c = rest(c, 1).clone()
	if c.ends_with(":"): c = c.view(0, c.length() - 1).clone()
	if c.length() < 1: return false
	for k in 0..c.length():
		if chr(c, k) != "-": return false
	return true

fn tryTable(lines: List[String], i: Int) Res:
	n := lines.length()
	if i + 1 >= n: return Res()
	l1 := lines[i]
	l2 := lines[i + 1]
	if not l1.contains("|") or not l2.contains("|"): return Res()
	c2 := splitCells(l2)
	for c in c2:
		if not isDelimCell(c): return Res()
	c1 := splitCells(l1)
	if c1.length() != c2.length(): return Res()
	cols := c1.length()
	var aligns = List[String]()
	for c in c2:
		left := c.starts_with(":")
		right := c.ends_with(":")
		if left and right:
			aligns.append(" align=\"center\"")
		else if left:
			aligns.append(" align=\"left\"")
		else if right:
			aligns.append(" align=\"right\"")
		else:
			aligns.append("")
	var html = "<table>\n<thead>\n<tr>\n"
	for k in 0..cols:
		html += "<th" + aligns[k] + ">" + inline(c1[k]) + "</th>\n"
	html += "</tr>\n</thead>\n"
	var j = i + 2
	var body = ""
	while j < n:
		l := lines[j]
		if isBlank(l) or startsBlock(l): break
		cells := splitCells(l)
		body += "<tr>\n"
		for k in 0..cols:
			body += "<td" + aligns[k] + ">" + inline(cells.get(k, "")) + "</td>\n"
		body += "</tr>\n"
		j += 1
	if body != "":
		html += "<tbody>\n" + body + "</tbody>\n"
	html += "</table>\n"
	return Res(true, j, html)

fn parseBlocks(lines: List[String]) List[Block]:
	var out = List[Block]()
	n := lines.length()
	var i = 0
	var blank = false
	while i < n:
		line := lines[i]
		if isBlank(line):
			blank = true
			i += 1
			continue
		flag := blank and out.length() > 0
		blank = false
		var r = tryFence(lines, i)
		if not r.ok:
			a := atx(line)
			if a.ok:
				r = Res(true, i + 1, "<h{a.level}>" + inline(a.content) + "</h{a.level}>\n")
		if not r.ok and isThematic(line):
			r = Res(true, i + 1, "<hr />\n")
		if not r.ok: r = tryQuote(lines, i)
		if not r.ok: r = tryList(lines, i)
		if not r.ok: r = tryIndented(lines, i)
		if not r.ok: r = tryTable(lines, i)
		if r.ok:
			out.append(Block(false, r.text.clone(), flag))
			i = r.next
			continue
		var j = i + 1
		while j < n:
			l := lines[j]
			if isBlank(l) or startsBlock(l) or interrupts(l): break
			j += 1
		var text = ""
		for t in i..j:
			l := lines[t].trim_start()
			if t == j - 1:
				text += l.trim_end()
			else:
				hard := l.ends_with("  ")
				text += l.trim_end()
				if hard:
					text += "\u{1}"
				else:
					text += "\n"
		out.append(Block(true, inline(text), flag))
		i = j
	return out

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	bytes := read_all(stdin())?
	text := bytes.decode_utf8().get("")
	var lines = List[String]()
	if text != "":
		lines = text.split("\n").clone()
		if text.ends_with("\n"):
			lines.remove(-1)
	print(joinBlocks(parseBlocks(lines)), end: "")

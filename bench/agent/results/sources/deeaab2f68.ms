import stdin, stdout from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Node:
	kind: Int
	text: String = ""
	alt: String = ""
	ch: Int = 0
	n: Int = 0
	orig: Int = 0
	can_open: Bool = false
	can_close: Bool = false
	active: Bool = true
	dead: Bool = false
	open_tags: String = ""
	close_tags: String = ""
	title: String = ""
	has_title: Bool = false

type Tail:
	ok: Bool
	dest: String = ""
	title: String = ""
	has_title: Bool = false
	end: Int = 0

type Block:
	is_para: Bool
	inline: String
	html: String
	gap: Bool

type Fence:
	ch: Int
	n: Int
	ind: Int
	info: String

type Marker:
	ind: Int
	kind: Int
	num: Int
	mend: Int

type ListRes:
	html: String
	end: Int

fn code(s: String, i: Int) Int:
	if i < 0 or i >= s.length(): return -1
	return s.scalar_at(i, -1)

fn sub(s: String, a: Int, b: Int) String:
	var lo = a
	var hi = b
	if lo < 0: lo = 0
	if hi > s.length(): hi = s.length()
	if lo >= hi: return ""
	return s.view(lo, hi).clone()

fn is_punct(c: Int) Bool:
	return (c >= 33 and c <= 47) or (c >= 58 and c <= 64) or (c >= 91 and c <= 96) or (c >= 123 and c <= 126)

fn is_ws(c: Int) Bool:
	return c < 0 or c == 32 or c == 10 or c == 1

fn esc(s: String) String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

fn rep(ch: Int, n: Int) String:
	var s = ""
	var k = 0
	while k < n:
		if ch == 42:
			s += "*"
		else:
			s += "_"
		k += 1
	return s

fn indent(s: String) Int:
	var k = 0
	while code(s, k) == 32: k += 1
	return k

fn is_blank(s: String) Bool:
	return indent(s) == s.length()

// ---------------- inline ----------------

fn parse_tail(t: String, pos: Int) Tail:
	n := t.length()
	var i = pos + 1
	while i < n and (code(t, i) == 32 or code(t, i) == 10): i += 1
	var dest = ""
	if code(t, i) == 60:
		i += 1
		var closed = false
		while i < n and not closed:
			c := code(t, i)
			if c == 62:
				closed = true
				i += 1
			else if c == 60 or c == 10:
				return Tail(ok: false)
			else if c == 92 and is_punct(code(t, i + 1)):
				dest += sub(t, i + 1, i + 2)
				i += 2
			else:
				dest += sub(t, i, i + 1)
				i += 1
		if not closed: return Tail(ok: false)
	else:
		var depth = 0
		var stop = false
		while i < n and not stop:
			c := code(t, i)
			if c == 92 and is_punct(code(t, i + 1)):
				dest += sub(t, i + 1, i + 2)
				i += 2
			else if c == 40:
				depth += 1
				dest += "("
				i += 1
			else if c == 41:
				if depth == 0:
					stop = true
				else:
					depth -= 1
					dest += ")"
					i += 1
			else if c == 32 or c == 10:
				stop = true
			else:
				dest += sub(t, i, i + 1)
				i += 1
		if depth != 0: return Tail(ok: false)
	var skipped = 0
	while i < n and (code(t, i) == 32 or code(t, i) == 10):
		i += 1
		skipped += 1
	var title = ""
	var has_title = false
	if code(t, i) == 34 and skipped > 0:
		i += 1
		var closed = false
		while i < n and not closed:
			c := code(t, i)
			if c == 92 and code(t, i + 1) == 34:
				title += "\""
				i += 2
			else if c == 34:
				closed = true
				i += 1
			else:
				title += sub(t, i, i + 1)
				i += 1
		if not closed: return Tail(ok: false)
		has_title = true
		while i < n and (code(t, i) == 32 or code(t, i) == 10): i += 1
	if code(t, i) != 41: return Tail(ok: false)
	return Tail(ok: true, dest: dest, title: title, has_title: has_title, end: i + 1)

fn resolve(var nodes: List[Node], start: Int) Unit:
	var ci = start
	while ci < nodes.length():
		if nodes[ci].kind == 2 and not nodes[ci].dead and nodes[ci].can_close and nodes[ci].n > 0:
			var oi = ci - 1
			var found = -1
			while oi >= start and found < 0:
				if nodes[oi].kind == 2 and not nodes[oi].dead and nodes[oi].ch == nodes[ci].ch and nodes[oi].can_open and nodes[oi].n > 0:
					var good = true
					if nodes[oi].can_close or nodes[ci].can_open:
						s := nodes[oi].orig + nodes[ci].orig
						if s % 3 == 0 and not (nodes[oi].orig % 3 == 0 and nodes[ci].orig % 3 == 0):
							good = false
					if good: found = oi
				oi -= 1
			if found >= 0:
				var use = 1
				if nodes[found].n >= 2 and nodes[ci].n >= 2: use = 2
				otag := if use == 2: "<strong>" else: "<em>"
				ctag := if use == 2: "</strong>" else: "</em>"
				nodes[found].n -= use
				nodes[ci].n -= use
				nodes[found].open_tags = otag + nodes[found].open_tags
				nodes[ci].close_tags = nodes[ci].close_tags + ctag
				var k = found + 1
				while k < ci:
					if nodes[k].kind == 2: nodes[k].dead = true
					k += 1
				if nodes[ci].n == 0: ci += 1
			else:
				ci += 1
		else:
			ci += 1

fn alt_text(nodes: List[Node], from: Int) String:
	var s = ""
	var k = from
	while k < nodes.length():
		kd := nodes[k].kind
		if kd == 0 or kd == 1 or kd == 3:
			s += nodes[k].text
		else if kd == 2:
			s += rep(nodes[k].ch, nodes[k].n)
		else if kd == 6:
			s += nodes[k].alt
		else if kd == 8 or kd == 9:
			s += " "
		k += 1
	return s

fn render_nodes(nodes: List[Node]) String:
	var out = ""
	for nd in nodes:
		kd := nd.kind
		if kd == 0 or kd == 3:
			out += esc(nd.text)
		else if kd == 1:
			out += "<code>" + esc(nd.text) + "</code>"
		else if kd == 2:
			out += nd.close_tags + rep(nd.ch, nd.n) + nd.open_tags
		else if kd == 4:
			out += "<a href=\"" + esc(nd.text) + "\""
			if nd.has_title: out += " title=\"" + esc(nd.title) + "\""
			out += ">"
		else if kd == 5:
			out += "</a>"
		else if kd == 6:
			out += "<img src=\"" + esc(nd.text) + "\" alt=\"" + esc(nd.alt) + "\""
			if nd.has_title: out += " title=\"" + esc(nd.title) + "\""
			out += " />"
		else if kd == 8:
			out += "<br />\n"
		else if kd == 9:
			out += "\n"
	return out

fn inline(t: String) String:
	var nodes = List[Node]()
	n := t.length()
	var i = 0
	while i < n:
		c := code(t, i)
		if c == 92:
			nc := code(t, i + 1)
			if nc == 10:
				nodes.append(Node(kind: 8))
				i += 2
			else if is_punct(nc):
				nodes.append(Node(kind: 0, text: sub(t, i + 1, i + 2)))
				i += 2
			else:
				nodes.append(Node(kind: 0, text: "\\"))
				i += 1
			continue
		if c == 1:
			nodes.append(Node(kind: 8))
			i += 1
			if code(t, i) == 10: i += 1
			continue
		if c == 10:
			nodes.append(Node(kind: 9))
			i += 1
			continue
		if c == 96:
			var k = i
			while code(t, k) == 96: k += 1
			cnt := k - i
			var j = k
			var found = -1
			while j < n and found < 0:
				if code(t, j) == 96:
					var m = j
					while code(t, m) == 96: m += 1
					if m - j == cnt:
						found = j
					else:
						j = m
				else:
					j += 1
			if found >= 0:
				var content = sub(t, k, found).replace("\u{1}", "").replace("\n", " ")
				if content.length() > 0 and code(content, 0) == 32 and code(content, content.length() - 1) == 32 and content.trim().length() > 0:
					content = sub(content, 1, content.length() - 1)
				nodes.append(Node(kind: 1, text: content))
				i = found + cnt
			else:
				nodes.append(Node(kind: 0, text: sub(t, i, k)))
				i = k
			continue
		if c == 42 or c == 95:
			var k = i
			while code(t, k) == c: k += 1
			prev := code(t, i - 1)
			next := code(t, k)
			left := not is_ws(next) and (not is_punct(next) or is_ws(prev) or is_punct(prev))
			right := not is_ws(prev) and (not is_punct(prev) or is_ws(next) or is_punct(next))
			var co = left
			var cc = right
			if c == 95:
				co = left and (not right or is_punct(prev))
				cc = right and (not left or is_punct(next))
			nodes.append(Node(kind: 2, ch: c, n: k - i, orig: k - i, can_open: co, can_close: cc))
			i = k
			continue
		if c == 33 and code(t, i + 1) == 91:
			nodes.append(Node(kind: 3, text: "![", ch: 1))
			i += 2
			continue
		if c == 91:
			nodes.append(Node(kind: 3, text: "[", ch: 0))
			i += 1
			continue
		if c == 93:
			var mi = -1
			var k = nodes.length() - 1
			while k >= 0 and mi < 0:
				if nodes[k].kind == 3: mi = k
				k -= 1
			if mi < 0:
				nodes.append(Node(kind: 0, text: "]"))
				i += 1
				continue
			is_image := nodes[mi].ch == 1
			if not is_image and not nodes[mi].active:
				nodes[mi].kind = 0
				nodes.append(Node(kind: 0, text: "]"))
				i += 1
				continue
			var done = false
			if code(t, i + 1) == 40:
				tail := parse_tail(t, i + 1)
				if tail.ok:
					resolve(var nodes, mi + 1)
					if is_image:
						alt := alt_text(nodes, mi + 1)
						while nodes.length() > mi + 1:
							_ := nodes.pop()
						nodes[mi].kind = 6
						nodes[mi].text = tail.dest.clone()
						nodes[mi].alt = alt
						nodes[mi].title = tail.title.clone()
						nodes[mi].has_title = tail.has_title
					else:
						var q = mi + 1
						while q < nodes.length():
							if nodes[q].kind == 2: nodes[q].dead = true
							q += 1
						nodes[mi].kind = 4
						nodes[mi].text = tail.dest.clone()
						nodes[mi].title = tail.title.clone()
						nodes[mi].has_title = tail.has_title
						nodes.append(Node(kind: 5))
						var e = 0
						while e < mi:
							if nodes[e].kind == 3 and nodes[e].ch == 0: nodes[e].active = false
							e += 1
					i = tail.end
					done = true
			if not done:
				nodes[mi].kind = 0
				nodes.append(Node(kind: 0, text: "]"))
				i += 1
			continue
		nodes.append(Node(kind: 0, text: sub(t, i, i + 1)))
		i += 1
	resolve(var nodes, 0)
	return render_nodes(nodes)

// ---------------- blocks ----------------

fn fence_open(line: String) Fence?:
	ind := indent(line)
	if ind > 3: return none
	c := code(line, ind)
	if c != 96 and c != 126: return none
	var k = ind
	while code(line, k) == c: k += 1
	if k - ind < 3: return none
	info := sub(line, k, line.length()).trim()
	if c == 96 and info.contains("`"): return none
	return Fence(ch: c, n: k - ind, ind: ind, info: info)

fn is_fence_close(line: String, ch: Int, n: Int) Bool:
	ind := indent(line)
	if ind > 3: return false
	var k = ind
	while code(line, k) == ch: k += 1
	if k - ind < n: return false
	return is_blank(sub(line, k, line.length()))

fn atx(line: String) String?:
	ind := indent(line)
	if ind > 3: return none
	var k = ind
	while code(line, k) == 35: k += 1
	lv := k - ind
	if lv < 1 or lv > 6: return none
	if k < line.length() and code(line, k) != 32: return none
	var content = sub(line, k, line.length()).trim()
	var r = content.length()
	while r > 0 and code(content, r - 1) == 35: r -= 1
	if r < content.length():
		if r == 0 or code(content, r - 1) == 32:
			content = sub(content, 0, r).trim_end()
	return "{lv}" + content

fn is_hr(line: String) Bool:
	ind := indent(line)
	if ind > 3: return false
	c := code(line, ind)
	if c != 45 and c != 42 and c != 95: return false
	var cnt = 0
	var k = 0
	while k < line.length():
		d := code(line, k)
		if d == c:
			cnt += 1
		else if d != 32:
			return false
		k += 1
	return cnt >= 3

fn is_quote(line: String) Bool:
	ind := indent(line)
	return ind <= 3 and code(line, ind) == 62

fn quote_strip(line: String) String:
	var k = indent(line) + 1
	if code(line, k) == 32: k += 1
	return sub(line, k, line.length())

fn list_marker(line: String) Marker?:
	ind := indent(line)
	if ind > 3: return none
	c := code(line, ind)
	n := line.length()
	if c == 45 or c == 42 or c == 43:
		e := ind + 1
		if e < n and code(line, e) != 32: return none
		return Marker(ind: ind, kind: c, num: 0, mend: e)
	if c >= 48 and c <= 57:
		var k = ind
		var num = 0
		while code(line, k) >= 48 and code(line, k) <= 57 and k - ind < 9:
			num = num * 10 + code(line, k) - 48
			k += 1
		d := code(line, k)
		if d != 46 and d != 41: return none
		e := k + 1
		if e < n and code(line, e) != 32: return none
		return Marker(ind: ind, kind: 1000 + d, num: num, mend: e)
	return none

fn list_interrupt(line: String) Bool:
	if m := list_marker(line):
		if is_blank(sub(line, m.mend, line.length())): return false
		return m.kind < 1000 or m.num == 1
	return false

fn starts_block(l: String) Bool:
	return fence_open(l).is_some() or atx(l).is_some() or is_hr(l) or is_quote(l)

fn split_cells(line: String) List[String]:
	var s = line.trim()
	if s.length() > 0 and code(s, 0) == 124: s = sub(s, 1, s.length())
	if s.length() > 0 and code(s, s.length() - 1) == 124 and code(s, s.length() - 2) != 92:
		s = sub(s, 0, s.length() - 1)
	var cells = List[String]()
	var cur = ""
	var k = 0
	while k < s.length():
		c := code(s, k)
		if c == 124 and code(s, k - 1) != 92:
			cells.append(cur.trim())
			cur = ""
		else:
			cur += sub(s, k, k + 1)
		k += 1
	cells.append(cur.trim())
	return cells

fn delim_align(cell: String) Int:
	var a = 0
	var b = cell.length()
	l := code(cell, 0) == 58
	if l: a = 1
	r := b > a and code(cell, b - 1) == 58
	if r: b -= 1
	if b <= a: return -1
	var k = a
	while k < b:
		if code(cell, k) != 45: return -1
		k += 1
	if l and r: return 2
	if l: return 1
	if r: return 3
	return 0

fn render_blocks(bs: List[Block]) String:
	var out = ""
	for b in bs:
		out += b.html
	return out

fn code_html(lines: List[String]) String:
	var out = "<pre><code>"
	for l in lines:
		out += esc(l) + "\n"
	return out + "</code></pre>\n"

fn parse_list(lines: List[String], start: Int) ListRes:
	n := lines.length()
	var items = List[List[Block]]()
	var loose = false
	var pos = start
	var going = true
	var first_num = 1
	var kind0 = 0
	while going:
		mo := list_marker(lines[pos])
		if m := mo:
			if pos == start:
				first_num = m.num
				kind0 = m.kind
			line := lines[pos]
			ll := line.length()
			var k = m.mend
			while code(line, k) == 32: k += 1
			s := k - m.mend
			var w = m.mend + 1
			if m.mend < ll and s < 5: w = m.mend + s
			var content = List[String]()
			content.append(sub(line, w, ll))
			var j = pos + 1
			var pending = 0
			var endj = pos + 1
			var stop = false
			while j < n and not stop:
				l := lines[j]
				if is_blank(l):
					pending += 1
					j += 1
				else if indent(l) >= w:
					var p = 0
					while p < pending:
						content.append("")
						p += 1
					pending = 0
					content.append(sub(l, w, l.length()))
					j += 1
					endj = j
				else:
					stop = true
			blocks := parse_blocks(content)
			var bi = 0
			while bi < blocks.length():
				if blocks[bi].gap: loose = true
				bi += 1
			items.append(blocks)
			pos = endj
			var q = pos
			while q < n and is_blank(lines[q]): q += 1
			going = false
			if q < n and not is_hr(lines[q]):
				if m2 := list_marker(lines[q]):
					if m2.kind == kind0:
						if q > pos: loose = true
						pos = q
						going = true
		else:
			going = false
	var out = ""
	if kind0 < 1000:
		out = "<ul>\n"
	else if first_num == 1:
		out = "<ol>\n"
	else:
		out = "<ol start=\"{first_num}\">\n"
	for blocks in items:
		var body = ""
		for b in blocks:
			if b.is_para and not loose:
				body += b.inline
			else:
				if not body.ends_with("\n"): body += "\n"
				body += b.html
		out += "<li>" + body + "</li>\n"
	if kind0 < 1000:
		out += "</ul>\n"
	else:
		out += "</ol>\n"
	return ListRes(html: out, end: pos)

fn align_attr(a: Int) String:
	if a == 1: return " align=\"left\""
	if a == 2: return " align=\"center\""
	if a == 3: return " align=\"right\""
	return ""

fn parse_blocks(lines: List[String]) List[Block]:
	var blocks = List[Block]()
	n := lines.length()
	var i = 0
	var gap = false
	while i < n:
		line := lines[i]
		if is_blank(line):
			if blocks.length() > 0: gap = true
			i += 1
			continue
		ind := indent(line)
		if f := fence_open(line):
			var out = "<pre><code>"
			lang := f.info.split(" ").get(0, "")
			if lang.length() > 0:
				out = "<pre><code class=\"language-" + esc(lang) + "\">"
			var j = i + 1
			var closed = false
			while j < n and not closed:
				l := lines[j]
				if is_fence_close(l, f.ch, f.n):
					closed = true
				else:
					var k = indent(l)
					if k > f.ind: k = f.ind
					out += esc(sub(l, k, l.length())) + "\n"
				j += 1
			out += "</code></pre>\n"
			blocks.append(Block(is_para: false, inline: "", html: out, gap: gap))
			gap = false
			i = j
			continue
		if h := atx(line):
			lv := h.view(0, 1).clone()
			body := sub(h, 1, h.length())
			blocks.append(Block(is_para: false, inline: "", html: "<h{lv}>" + inline(body) + "</h{lv}>\n", gap: gap))
			gap = false
			i += 1
			continue
		if is_hr(line):
			blocks.append(Block(is_para: false, inline: "", html: "<hr />\n", gap: gap))
			gap = false
			i += 1
			continue
		if is_quote(line):
			var inner = List[String]()
			var j = i
			while j < n and is_quote(lines[j]):
				inner.append(quote_strip(lines[j]))
				j += 1
			html := "<blockquote>\n" + render_blocks(parse_blocks(inner)) + "</blockquote>\n"
			blocks.append(Block(is_para: false, inline: "", html: html, gap: gap))
			gap = false
			i = j
			continue
		if list_marker(line).is_some():
			res := parse_list(lines, i)
			blocks.append(Block(is_para: false, inline: "", html: res.html.clone(), gap: gap))
			gap = false
			i = res.end
			continue
		if ind >= 4:
			var cl = List[String]()
			var j = i
			var last = i
			while j < n and (is_blank(lines[j]) or indent(lines[j]) >= 4):
				if not is_blank(lines[j]): last = j
				j += 1
			var p = i
			while p <= last:
				l := lines[p]
				var k = indent(l)
				if k > 4: k = 4
				cl.append(sub(l, k, l.length()))
				p += 1
			blocks.append(Block(is_para: false, inline: "", html: code_html(cl), gap: gap))
			gap = false
			i = last + 1
			continue
		if i + 1 < n and line.contains("|"):
			l2 := lines[i + 1]
			if l2.contains("|"):
				hc := split_cells(line)
				dc := split_cells(l2)
				var aligns = List[Int]()
				var okd = true
				for c in dc:
					a := delim_align(c)
					if a < 0: okd = false
					aligns.append(a)
				if okd and hc.length() == dc.length():
					ncols := hc.length()
					var out = "<table>\n<thead>\n<tr>\n"
					var c = 0
					while c < ncols:
						out += "<th" + align_attr(aligns[c]) + ">" + inline(hc[c]) + "</th>\n"
						c += 1
					out += "</tr>\n</thead>\n"
					var j = i + 2
					var body = ""
					while j < n and not is_blank(lines[j]) and not starts_block(lines[j]):
						cells := split_cells(lines[j])
						body += "<tr>\n"
						var d = 0
						while d < ncols:
							body += "<td" + align_attr(aligns[d]) + ">" + inline(cells.get(d, "")) + "</td>\n"
							d += 1
						body += "</tr>\n"
						j += 1
					if body.length() > 0:
						out += "<tbody>\n" + body + "</tbody>\n"
					out += "</table>\n"
					blocks.append(Block(is_para: false, inline: "", html: out, gap: gap))
					gap = false
					i = j
					continue
		var j = i + 1
		var stop = false
		while j < n and not stop:
			l := lines[j]
			if is_blank(l) or starts_block(l) or list_interrupt(l):
				stop = true
			else:
				j += 1
		var text = ""
		var p = i
		while p < j:
			l := lines[p]
			var t = l.trim_start()
			if p == j - 1:
				text += t.trim_end()
			else:
				hard := t.length() - t.trim_end().length() >= 2
				text += t.trim_end()
				if hard: text += "\u{1}"
				text += "\n"
			p += 1
		inl := inline(text)
		blocks.append(Block(is_para: true, inline: inl.clone(), html: "<p>" + inl + "</p>\n", gap: gap))
		gap = false
		i = j
	return blocks

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	bytes := read_all(stdin())?
	text := bytes.decode_utf8().get("")
	if text.length() == 0: return ok(unit)
	lines := text.lines()
	blocks := parse_blocks(lines)
	var o = stdout()
	o.write(render_blocks(blocks))?
	return ok(unit)

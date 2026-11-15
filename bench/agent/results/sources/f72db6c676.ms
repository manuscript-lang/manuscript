import stdin, stdout from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Node:
	kind: Int = 0
	html: String = ""
	plain: String = ""
	ch: String = ""
	count: Int = 0
	orig: Int = 0
	open: Bool = false
	close: Bool = false
	image: Bool = false
	active: Bool = true

type Tail:
	ok: Bool = false
	end: Int = 0
	dest: String = ""
	title: String = ""
	has_title: Bool = false

type Block:
	kind: Int = 0
	html: String = ""
	inl: String = ""
	start: Int = 0
	end: Int = 0
	next: Int = 0

type Item:
	blocks: List[Block]
	loose: Bool = false

type Marker:
	ok: Bool = false
	ordered: Bool = false
	kind: String = ""
	num: Int = 0
	m: Int = 0
	empty: Bool = false

type Fence:
	ok: Bool = false
	ch: String = ""
	len: Int = 0
	ind: Int = 0
	info: String = ""

fn sent() String: "\u{1}"

fn at(s: String, i: Int) String:
	if i < 0 or i >= s.length(): return ""
	return s.view(i, i + 1).clone()

fn sub(s: String, a: Int, b: Int) String:
	e := if b > s.length(): s.length() else: b
	if a >= e: return ""
	return s.view(a, e).clone()

fn rep(s: String, k: Int) String:
	var r = ""
	for _i in 0..k:
		r += s
	return r

fn esc(s: String) String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

fn is_punct(c: String) Bool:
	if c == "": return false
	return "!\"#$%&'()*+,-./:;<=>?@[\\]^_`\{|\}~".contains(c)

fn is_ws(c: String) Bool:
	return c == "" or c == " " or c == "\n" or c == sent()

fn is_skip(c: String) Bool:
	return c == " " or c == "\n" or c == sent()

fn is_digit(c: String) Bool:
	if c == "": return false
	return "0123456789".contains(c)

fn indent_of(s: String) Int:
	var i = 0
	while at(s, i) == " ":
		i += 1
	return i

fn is_blank(s: String) Bool: indent_of(s) == s.length()

// ---------------- inline ----------------

fn html_of(n: Node) String:
	if n.kind == 3: return ""
	if n.kind == 1: return rep(n.ch, n.count)
	if n.kind == 2: return if n.image: "![" else: "["
	return n.html.clone()

fn plain_of(n: Node) String:
	if n.kind == 3: return ""
	if n.kind == 1: return rep(n.ch, n.count)
	if n.kind == 2: return if n.image: "![" else: "["
	return n.plain.clone()

fn text_node(s: String) Node:
	return Node(html: esc(s), plain: s.replace("\n", " "))

fn parse_tail(s: String, p: Int) Tail:
	var q = p + 1
	while is_skip(at(s, q)):
		q += 1
	var dest = ""
	if at(s, q) == "<":
		q += 1
		var closed = false
		while q < s.length():
			c := at(s, q)
			if c == ">":
				closed = true
				break
			if c == "\n" or c == "<": return Tail()
			if c == "\\" and is_punct(at(s, q + 1)):
				dest += at(s, q + 1)
				q += 2
				continue
			dest += c
			q += 1
		if not closed: return Tail()
		q += 1
	else:
		var depth = 0
		while q < s.length():
			c := at(s, q)
			if is_skip(c): break
			if c == "\\" and is_punct(at(s, q + 1)):
				dest += at(s, q + 1)
				q += 2
				continue
			if c == "(":
				depth += 1
			else if c == ")":
				if depth == 0: break
				depth -= 1
			dest += c
			q += 1
		if depth != 0: return Tail()
	var skipped = false
	while is_skip(at(s, q)):
		skipped = true
		q += 1
	var title = ""
	var has_title = false
	if skipped and at(s, q) == "\"":
		q += 1
		var done = false
		while q < s.length():
			c := at(s, q)
			if c == "\"":
				done = true
				break
			if c == "\\" and is_punct(at(s, q + 1)):
				title += at(s, q + 1)
				q += 2
				continue
			title += c
			q += 1
		if not done: return Tail()
		q += 1
		while is_skip(at(s, q)):
			q += 1
		has_title = true
	if at(s, q) != ")": return Tail()
	return Tail(ok: true, end: q + 1, dest: dest.replace(sent(), ""), title: title.replace(sent(), ""), has_title: has_title)

fn resolve(var nodes: List[Node], lo: Int, hi: Int) Unit:
	var c = lo
	while c < hi:
		if nodes[c].kind != 1 or not nodes[c].close or nodes[c].count == 0:
			c += 1
			continue
		var found = -1
		var j = c - 1
		while j >= lo:
			if nodes[j].kind == 1 and nodes[j].ch == nodes[c].ch and nodes[j].open and nodes[j].count > 0:
				both3 := nodes[j].orig % 3 == 0 and nodes[c].orig % 3 == 0
				bad := (nodes[j].close or nodes[c].open) and (nodes[j].orig + nodes[c].orig) % 3 == 0 and not both3
				if not bad:
					found = j
					break
			j -= 1
		if found < 0 or found + 1 >= c:
			c += 1
			continue
		use := if nodes[found].count >= 2 and nodes[c].count >= 2: 2 else: 1
		var inner = ""
		var plain = ""
		for k in (found + 1)..c:
			inner += html_of(nodes[k])
			plain += plain_of(nodes[k])
			nodes[k].kind = 3
		tag := if use == 2: "strong" else: "em"
		nodes[found + 1].kind = 0
		nodes[found + 1].html = "<{tag}>{inner}</{tag}>"
		nodes[found + 1].plain = plain
		nodes[found].count -= use
		nodes[c].count -= use
		if nodes[found].count == 0:
			nodes[found].kind = 3
		if nodes[c].count == 0:
			nodes[c].kind = 3
			c += 1

fn inline(s: String) String:
	var nodes = List[Node]()
	var buf = ""
	var i = 0
	n := s.length()
	while i < n:
		c := at(s, i)
		if c == "\\":
			nx := at(s, i + 1)
			if nx == "\n":
				if buf != "":
					nodes.append(text_node(buf))
					buf = ""
				nodes.append(Node(html: "<br />\n", plain: " "))
				i += 2
				continue
			if is_punct(nx):
				buf += nx
				i += 2
				continue
			buf += "\\"
			i += 1
			continue
		if c == sent() and at(s, i + 1) == "\n":
			if buf != "":
				nodes.append(text_node(buf))
				buf = ""
			nodes.append(Node(html: "<br />\n", plain: " "))
			i += 2
			continue
		if c == "`":
			var r = 0
			while at(s, i + r) == "`":
				r += 1
			var k = i + r
			var found = -1
			while k < n:
				if at(s, k) == "`":
					var r2 = 0
					while at(s, k + r2) == "`":
						r2 += 1
					if r2 == r:
						found = k
						break
					k += r2
				else:
					k += 1
			if found < 0:
				buf += rep("`", r)
				i += r
				continue
			var content = sub(s, i + r, found).replace(sent(), "").replace("\n", " ")
			if content.length() >= 2 and content.starts_with(" ") and content.ends_with(" ") and not content.trim().is_empty():
				content = sub(content, 1, content.length() - 1)
			if buf != "":
				nodes.append(text_node(buf))
				buf = ""
			nodes.append(Node(html: "<code>{esc(content)}</code>", plain: content))
			i = found + r
			continue
		if c == "*" or c == "_":
			var r = 0
			while at(s, i + r) == c:
				r += 1
			prev := at(s, i - 1)
			next := at(s, i + r)
			ws_p := is_ws(prev)
			ws_n := is_ws(next)
			pu_p := is_punct(prev)
			pu_n := is_punct(next)
			left := not ws_n and (not pu_n or ws_p or pu_p)
			right := not ws_p and (not pu_p or ws_n or pu_n)
			var op = left
			var cl = right
			if c == "_":
				op = left and (not right or pu_p)
				cl = right and (not left or pu_n)
			if buf != "":
				nodes.append(text_node(buf))
				buf = ""
			nodes.append(Node(kind: 1, ch: c, count: r, orig: r, open: op, close: cl))
			i += r
			continue
		if c == "!" and at(s, i + 1) == "[":
			if buf != "":
				nodes.append(text_node(buf))
				buf = ""
			nodes.append(Node(kind: 2, image: true))
			i += 2
			continue
		if c == "[":
			if buf != "":
				nodes.append(text_node(buf))
				buf = ""
			nodes.append(Node(kind: 2))
			i += 1
			continue
		if c == "]":
			if buf != "":
				nodes.append(text_node(buf))
				buf = ""
			var m = -1
			var k = nodes.length() - 1
			while k >= 0:
				if nodes[k].kind == 2:
					m = k
					break
				k -= 1
			if m < 0:
				buf += "]"
				i += 1
				continue
			is_img := nodes[m].image
			if not is_img and not nodes[m].active:
				_old := nodes.replace(m, text_node("["))
				buf += "]"
				i += 1
				continue
			var formed = false
			if at(s, i + 1) == "(":
				t := parse_tail(s, i + 1)
				if t.ok:
					resolve(var nodes, m + 1, nodes.length())
					var inner = ""
					var plain = ""
					for q in (m + 1)..nodes.length():
						inner += html_of(nodes[q])
						plain += plain_of(nodes[q])
					while nodes.length() > m + 1:
						_p := nodes.pop()
					title_attr := if t.has_title: " title=\"{esc(t.title)}\"" else: ""
					var h = ""
					if is_img:
						h = "<img src=\"{esc(t.dest)}\" alt=\"{esc(plain)}\"{title_attr} />"
					else:
						h = "<a href=\"{esc(t.dest)}\"{title_attr}>{inner}</a>"
					_old := nodes.replace(m, Node(html: h, plain: plain))
					if not is_img:
						for q in 0..m:
							if nodes[q].kind == 2 and not nodes[q].image:
								nodes[q].active = false
					i = t.end
					formed = true
			if not formed:
				lit := if is_img: "![" else: "["
				_old := nodes.replace(m, text_node(lit))
				buf += "]"
				i += 1
			continue
		buf += c
		i += 1
	if buf != "":
		nodes.append(text_node(buf))
	resolve(var nodes, 0, nodes.length())
	var out = ""
	for q in 0..nodes.length():
		out += html_of(nodes[q])
	return out

// ---------------- blocks ----------------

fn marker_of(line: String) Marker:
	ind := indent_of(line)
	if ind > 3: return Marker()
	c := at(line, ind)
	if c == "-" or c == "*" or c == "+":
		nx := at(line, ind + 1)
		if nx != "" and nx != " ": return Marker()
		m := ind + 1
		return Marker(ok: true, kind: c, m: m, empty: is_blank(sub(line, m, line.length())))
	var d = 0
	while is_digit(at(line, ind + d)):
		d += 1
	if d < 1 or d > 9: return Marker()
	dl := at(line, ind + d)
	if dl != "." and dl != ")": return Marker()
	nx := at(line, ind + d + 1)
	if nx != "" and nx != " ": return Marker()
	m := ind + d + 1
	num := sub(line, ind, ind + d).parse_int().get(0)
	return Marker(ok: true, ordered: true, kind: dl, num: num, m: m, empty: is_blank(sub(line, m, line.length())))

fn fence_of(line: String) Fence:
	ind := indent_of(line)
	if ind > 3: return Fence()
	c := at(line, ind)
	if c != "`" and c != "~": return Fence()
	var r = 0
	while at(line, ind + r) == c:
		r += 1
	if r < 3: return Fence()
	info := sub(line, ind + r, line.length()).trim()
	if c == "`" and info.contains("`"): return Fence()
	return Fence(ok: true, ch: c, len: r, ind: ind, info: info)

fn is_fence_close(line: String, f: Fence) Bool:
	ind := indent_of(line)
	if ind > 3: return false
	var r = 0
	while at(line, ind + r) == f.ch:
		r += 1
	if r < f.len: return false
	return is_blank(sub(line, ind + r, line.length()))

fn atx_level(line: String) Int:
	ind := indent_of(line)
	if ind > 3: return 0
	var r = 0
	while at(line, ind + r) == "#":
		r += 1
	if r < 1 or r > 6: return 0
	nx := at(line, ind + r)
	if nx != "" and nx != " ": return 0
	return r

fn atx_content(line: String, level: Int) String:
	ind := indent_of(line)
	var content = sub(line, ind + level, line.length()).trim()
	var k = 0
	while at(content, content.length() - 1 - k) == "#":
		k += 1
	if k > 0:
		if k == content.length() or at(content, content.length() - k - 1) == " ":
			content = sub(content, 0, content.length() - k).trim_end()
	return content

fn is_hr(line: String) Bool:
	ind := indent_of(line)
	if ind > 3: return false
	t := line.replace(" ", "")
	if t.length() < 3: return false
	c := at(t, 0)
	if c != "-" and c != "*" and c != "_": return false
	return t.replace(c, "").is_empty()

fn is_quote(line: String) Bool:
	ind := indent_of(line)
	return ind <= 3 and at(line, ind) == ">"

fn starts_interrupt(line: String) Bool:
	if fence_of(line).ok: return true
	if atx_level(line) > 0: return true
	if is_hr(line): return true
	return is_quote(line)

fn split_cells(line: String) List[String]:
	var t = line.trim()
	if t.starts_with("|"):
		t = sub(t, 1, t.length())
	if t.ends_with("|") and at(t, t.length() - 2) != "\\":
		t = sub(t, 0, t.length() - 1)
	var cells = List[String]()
	var cur = ""
	for i in 0..t.length():
		c := at(t, i)
		if c == "|" and at(t, i - 1) != "\\":
			cells.append(cur.trim())
			cur = ""
		else:
			cur += c
	cells.append(cur.trim())
	return cells

// alignment codes: 0 none, 1 left, 2 center, 3 right; empty list if not a delimiter row
fn delim_row(line: String) List[Int]:
	var res = List[Int]()
	if not line.contains("|"): return res
	cells := split_cells(line)
	for cell in cells:
		var x = cell.clone()
		l := x.starts_with(":")
		if l:
			x = sub(x, 1, x.length())
		r := x.ends_with(":")
		if r:
			x = sub(x, 0, x.length() - 1)
		if x == "" or not x.replace("-", "").is_empty():
			return List[Int]()
		if l and r:
			res.append(2)
		else if l:
			res.append(1)
		else if r:
			res.append(3)
		else:
			res.append(0)
	return res

fn render_blocks(bs: List[Block]) String:
	var out = ""
	for b in bs:
		out += b.html
	return out

fn remove_indent(line: String, k: Int) String:
	var r = 0
	while r < k and at(line, r) == " ":
		r += 1
	return sub(line, r, line.length())

fn parse_list(lines: List[String], i: Int) Block:
	n := lines.length()
	first := marker_of(lines[i])
	var items = List[Item]()
	var j = i
	var list_loose = false
	var prev_end = -1
	var last_end = i
	var k = i
	while true:
		mk := marker_of(lines[j])
		rest := sub(lines[j], mk.m, lines[j].length())
		var w = mk.m + 1
		if rest.length() > 0:
			s := indent_of(rest)
			if s < 5:
				w = mk.m + s
		var content = List[String]()
		content.append(sub(lines[j], w, lines[j].length()))
		k = j + 1
		var end_idx = j
		while k < n:
			l := lines[k]
			if is_blank(l):
				content.append("")
				k += 1
				continue
			if indent_of(l) >= w:
				content.append(sub(l, w, l.length()))
				end_idx = k
				k += 1
				continue
			break
		while content.length() > end_idx - j + 1:
			_p := content.pop()
		if prev_end >= 0 and j > prev_end + 1:
			list_loose = true
		children := parse_blocks(content)
		var item_loose = false
		for b in 1..children.length():
			if children[b].start > children[b - 1].end + 1:
				item_loose = true
		items.append(Item(blocks: children, loose: item_loose))
		prev_end = end_idx
		last_end = end_idx
		if k >= n: break
		mk2 := marker_of(lines[k])
		if mk2.ok and not is_hr(lines[k]) and mk2.kind == mk.kind:
			j = k
			continue
		break
	var loose = list_loose
	for it in items:
		if it.loose: loose = true
	var body = ""
	for it in items:
		var b = ""
		for blk in it.blocks:
			if blk.kind == 0 and not loose:
				b += blk.inl
			else:
				if not b.ends_with("\n"):
					b += "\n"
				b += blk.html
		body += "<li>" + b + "</li>\n"
	var open = "<ul>\n"
	var close = "</ul>\n"
	if first.ordered:
		close = "</ol>\n"
		open = if first.num == 1: "<ol>\n" else: "<ol start=\"{first.num}\">\n"
	return Block(kind: 1, html: open + body + close, start: i, end: last_end, next: k)

fn code_html(lines: List[String]) String:
	var out = "<pre><code>"
	for l in lines:
		out += esc(l) + "\n"
	return out + "</code></pre>\n"

fn parse_blocks(lines: List[String]) List[Block]:
	var blocks = List[Block]()
	n := lines.length()
	var i = 0
	while i < n:
		line := lines[i]
		if is_blank(line):
			i += 1
			continue
		ind := indent_of(line)
		f := fence_of(line)
		if f.ok:
			var body = ""
			var j = i + 1
			while j < n:
				if is_fence_close(lines[j], f): break
				body += esc(remove_indent(lines[j], f.ind)) + "\n"
				j += 1
			var cls = ""
			if f.info != "":
				sp := f.info.index_of(" ")
				word := if sp.is_some(): sub(f.info, 0, sp.get(0)) else: f.info.clone()
				cls = " class=\"language-{esc(word)}\""
			e := if j < n: j else: n - 1
			blocks.append(Block(kind: 1, html: "<pre><code{cls}>{body}</code></pre>\n", start: i, end: e, next: j + 1))
			i = j + 1
			continue
		lvl := atx_level(line)
		if lvl > 0:
			h := "<h{lvl}>{inline(atx_content(line, lvl))}</h{lvl}>\n"
			blocks.append(Block(kind: 1, html: h, start: i, end: i, next: i + 1))
			i += 1
			continue
		if is_hr(line):
			blocks.append(Block(kind: 1, html: "<hr />\n", start: i, end: i, next: i + 1))
			i += 1
			continue
		if is_quote(line):
			var inner = List[String]()
			var j = i
			while j < n and is_quote(lines[j]):
				l := lines[j]
				var p = indent_of(l) + 1
				if at(l, p) == " ":
					p += 1
				inner.append(sub(l, p, l.length()))
				j += 1
			sub_blocks := parse_blocks(inner)
			blocks.append(Block(kind: 1, html: "<blockquote>\n{render_blocks(sub_blocks)}</blockquote>\n", start: i, end: j - 1, next: j))
			i = j
			continue
		if marker_of(line).ok:
			b := parse_list(lines, i)
			i = b.next
			blocks.append(b)
			continue
		if ind >= 4:
			var j = i
			var last = i
			var acc = List[String]()
			while j < n and (is_blank(lines[j]) or indent_of(lines[j]) >= 4):
				if not is_blank(lines[j]):
					last = j
				acc.append(remove_indent(lines[j], 4))
				j += 1
			while acc.length() > last - i + 1:
				_p := acc.pop()
			blocks.append(Block(kind: 1, html: code_html(acc), start: i, end: last, next: last + 1))
			i = last + 1
			continue
		if i + 1 < n and line.contains("|"):
			aligns := delim_row(lines[i + 1])
			head := split_cells(line)
			if aligns.length() > 0 and aligns.length() == head.length():
				var out = "<table>\n<thead>\n<tr>\n"
				for c in 0..head.length():
					a := aligns[c]
					attr := if a == 1: " align=\"left\"" else if a == 2: " align=\"center\"" else if a == 3: " align=\"right\"" else: ""
					out += "<th{attr}>{inline(head[c])}</th>\n"
				out += "</tr>\n</thead>\n"
				var j = i + 2
				var rows = ""
				while j < n and not is_blank(lines[j]) and not starts_interrupt(lines[j]):
					cells := split_cells(lines[j])
					rows += "<tr>\n"
					for c in 0..head.length():
						a := aligns[c]
						attr := if a == 1: " align=\"left\"" else if a == 2: " align=\"center\"" else if a == 3: " align=\"right\"" else: ""
						txt := cells.get(c, "")
						rows += "<td{attr}>{inline(txt)}</td>\n"
					rows += "</tr>\n"
					j += 1
				if rows != "":
					out += "<tbody>\n" + rows + "</tbody>\n"
				out += "</table>\n"
				blocks.append(Block(kind: 1, html: out, start: i, end: j - 1, next: j))
				i = j
				continue
		var j = i + 1
		while j < n:
			l := lines[j]
			if is_blank(l): break
			if starts_interrupt(l): break
			mk := marker_of(l)
			if mk.ok and not mk.empty and (not mk.ordered or mk.num == 1): break
			j += 1
		var text = ""
		for q in i..j:
			var s = lines[q].trim_start()
			if q == j - 1:
				s = s.trim_end()
			else:
				tr := s.trim_end()
				hard := s.length() - tr.length() >= 2
				s = if hard: tr + sent() else: tr
			if q > i:
				text += "\n"
			text += s
		inl := inline(text)
		blocks.append(Block(kind: 0, html: "<p>{inl}</p>\n", inl: inl, start: i, end: j - 1, next: j))
		i = j
	return blocks

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin(), none)?
	text := data.decode_utf8().get("")
	if text.is_empty(): return ok(unit)
	var lines = text.split("\n").clone()
	if text.ends_with("\n"):
		_p := lines.pop()
	blocks := parse_blocks(lines)
	var out = stdout()
	out.write(render_blocks(blocks))?

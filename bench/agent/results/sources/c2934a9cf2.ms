import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Node:
	kind: Int = 0
	html: String = ""
	alt: String = ""
	ch: Int = 0
	count: Int = 0
	orig: Int = 0
	canOpen: Bool = false
	canClose: Bool = false
	image: Bool = false
	active: Bool = true

type Rendered:
	html: String = ""
	alt: String = ""

type Tail:
	ok: Bool = false
	dest: String = ""
	title: String = ""
	hasTitle: Bool = false
	end: Int = 0

type Blk:
	para: Bool = false
	html: String = ""
	start: Int = 0
	end: Int = 0

type Marker:
	ok: Bool = false
	kind: Int = 0
	num: Int = 0
	w: Int = 0
	empty: Bool = false
	ordered: Bool = false

type Fence:
	ok: Bool = false
	ch: Int = 0
	len: Int = 0
	indent: Int = 0
	info: String = ""

fn at(s: String, i: Int) Int:
	if i < 0: return -1
	return s.scalar_at(i, default: -1)

fn sub(s: String, a: Int, b: Int) String:
	return s.view(a, b).clone()

fn esc(s: String) String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

fn isPunct(c: Int) Bool:
	return (c >= 33 and c <= 47) or (c >= 58 and c <= 64) or (c >= 91 and c <= 96) or (c >= 123 and c <= 126)

fn isWs(c: Int) Bool:
	return c < 0 or c == 32 or c == 10 or c == 1

fn isDigit(c: Int) Bool:
	return c >= 48 and c <= 57

fn addText(var nodes: List[Node], s: String) Unit:
	k := nodes.length() - 1
	if k >= 0 and nodes[k].kind == 0:
		nodes[k].html = nodes[k].html + esc(s)
		nodes[k].alt = nodes[k].alt + s
		return
	nodes.append(Node(kind: 0, html: esc(s), alt: s))

fn renderRange(nodes: List[Node], a: Int, b: Int) Rendered:
	var h = ""
	var t = ""
	for k in a..b:
		nd := nodes[k]
		if nd.kind == 1:
			s := (if nd.ch == 42: "*" else: "_").repeat(nd.count).get("")
			h += s
			t += s
		else if nd.kind == 2:
			s := if nd.image: "![" else: "["
			h += s
			t += s
		else:
			h += nd.html
			t += nd.alt
	return Rendered(html: h, alt: t)

fn resolve(var nodes: List[Node]) Rendered:
	for k in 0..nodes.length():
		if nodes[k].kind == 2:
			t := if nodes[k].image: "![" else: "["
			nodes[k] = Node(kind: 0, html: t.clone(), alt: t)
	var i = 0
	while i < nodes.length():
		if nodes[i].kind != 1 or not nodes[i].canClose or nodes[i].count <= 0:
			i += 1
			continue
		var found = -1
		var j = i - 1
		while j >= 0:
			if nodes[j].kind == 1 and nodes[j].ch == nodes[i].ch and nodes[j].canOpen and nodes[j].count > 0:
				sum := nodes[j].orig + nodes[i].orig
				bad := (nodes[j].canClose or nodes[i].canOpen) and sum % 3 == 0 and not (nodes[j].orig % 3 == 0 and nodes[i].orig % 3 == 0)
				if not bad:
					found = j
					break
			j -= 1
		if found < 0:
			i += 1
			continue
		use := if nodes[found].count >= 2 and nodes[i].count >= 2: 2 else: 1
		inner := renderRange(nodes, found + 1, i)
		tag := if use == 2: "strong" else: "em"
		node := Node(kind: 5, html: "<{tag}>{inner.html}</{tag}>", alt: inner.alt)
		cnt := i - found - 1
		for _u in 0..cnt:
			nodes.remove(found + 1)
		nodes.insert(found + 1, node)
		nodes[found].count = nodes[found].count - use
		ci := found + 2
		nodes[ci].count = nodes[ci].count - use
		if nodes[ci].count == 0:
			nodes.remove(ci)
		i = ci
		if nodes[found].count == 0:
			nodes.remove(found)
			i -= 1
	return renderRange(nodes, 0, nodes.length())

fn skipWs(text: String, i: Int) Int:
	var k = i
	while at(text, k) == 32 or at(text, k) == 10:
		k += 1
	return k

fn parseTail(text: String, p: Int) Tail:
	n := text.length()
	var i = skipWs(text, p + 1)
	var dest = ""
	if at(text, i) == 60:
		i += 1
		var closed = false
		while i < n:
			c := at(text, i)
			if c == 62:
				closed = true
				i += 1
				break
			if c == 10 or c == 60: break
			if c == 92 and isPunct(at(text, i + 1)):
				dest += sub(text, i + 1, i + 2)
				i += 2
				continue
			dest += sub(text, i, i + 1)
			i += 1
		if not closed: return Tail()
	else:
		var depth = 0
		while i < n:
			c := at(text, i)
			if c == 32 or c == 10: break
			if c == 92 and isPunct(at(text, i + 1)):
				dest += sub(text, i + 1, i + 2)
				i += 2
				continue
			if c == 40:
				depth += 1
			else if c == 41:
				if depth == 0: break
				depth -= 1
			dest += sub(text, i, i + 1)
			i += 1
		if depth != 0: return Tail()
	j := skipWs(text, i)
	skipped := j > i
	i = j
	var title = ""
	var hasTitle = false
	if skipped and at(text, i) == 34:
		i += 1
		var closed = false
		while i < n:
			c := at(text, i)
			if c == 34:
				closed = true
				i += 1
				break
			if c == 92 and isPunct(at(text, i + 1)):
				title += sub(text, i + 1, i + 2)
				i += 2
				continue
			title += sub(text, i, i + 1)
			i += 1
		if not closed: return Tail()
		hasTitle = true
		i = skipWs(text, i)
	if at(text, i) == 41:
		return Tail(ok: true, dest: dest, title: title, hasTitle: hasTitle, end: i + 1)
	return Tail()

fn closeBracket(var nodes: List[Node], text: String, i: Int) Int:
	var mi = -1
	var k = nodes.length() - 1
	while k >= 0:
		if nodes[k].kind == 2:
			mi = k
			break
		k -= 1
	if mi < 0:
		addText(var nodes, "]")
		return i + 1
	isImage := nodes[mi].image
	lit := if isImage: "![" else: "["
	if not isImage and not nodes[mi].active:
		nodes[mi] = Node(kind: 0, html: lit.clone(), alt: lit)
		addText(var nodes, "]")
		return i + 1
	if at(text, i + 1) == 40:
		r := parseTail(text, i + 1)
		if r.ok:
			var inner = List[Node]()
			while nodes.length() > mi + 1:
				if x := nodes.pop():
					inner.append(x)
			inner.reverse()
			_m := nodes.pop()
			res := resolve(var inner)
			ta := if r.hasTitle: " title=\"{esc(r.title)}\"" else: ""
			if isImage:
				nodes.append(Node(kind: 5, html: "<img src=\"{esc(r.dest)}\" alt=\"{esc(res.alt)}\"{ta} />", alt: res.alt))
			else:
				nodes.append(Node(kind: 5, html: "<a href=\"{esc(r.dest)}\"{ta}>{res.html}</a>", alt: res.alt))
				for q in 0..nodes.length():
					if nodes[q].kind == 2 and not nodes[q].image:
						nodes[q].active = false
			return r.end
	nodes[mi] = Node(kind: 0, html: lit.clone(), alt: lit)
	addText(var nodes, "]")
	return i + 1

fn inline(text: String) String:
	var nodes = List[Node]()
	n := text.length()
	var i = 0
	while i < n:
		c := at(text, i)
		if c == 92:
			nx := at(text, i + 1)
			if nx == 10:
				nodes.append(Node(kind: 5, html: "<br />\n", alt: " "))
				i += 2
			else if isPunct(nx):
				addText(var nodes, sub(text, i + 1, i + 2))
				i += 2
			else:
				addText(var nodes, "\\")
				i += 1
		else if c == 1:
			if at(text, i + 1) == 10:
				nodes.append(Node(kind: 5, html: "<br />\n", alt: " "))
				i += 2
			else:
				i += 1
		else if c == 10:
			nodes.append(Node(kind: 5, html: "\n", alt: " "))
			i += 1
		else if c == 96:
			var j = i
			while at(text, j) == 96:
				j += 1
			cn := j - i
			var k = j
			var found = -1
			while k < n:
				if at(text, k) == 96:
					var e = k
					while at(text, e) == 96:
						e += 1
					if e - k == cn:
						found = k
						break
					k = e
				else:
					k += 1
			if found >= 0:
				var content = sub(text, j, found).replace("\u{1}", "").replace("\n", " ")
				cl := content.length()
				if cl >= 2 and at(content, 0) == 32 and at(content, cl - 1) == 32 and content.trim_chars(" ").length() > 0:
					content = sub(content, 1, cl - 1)
				nodes.append(Node(kind: 5, html: "<code>{esc(content)}</code>", alt: content))
				i = found + cn
			else:
				addText(var nodes, sub(text, i, j))
				i = j
		else if c == 42 or c == 95:
			var j = i
			while at(text, j) == c:
				j += 1
			prev := at(text, i - 1)
			next := at(text, j)
			pw := isWs(prev)
			nw := isWs(next)
			pp := isPunct(prev)
			np := isPunct(next)
			left := not nw and (not np or pw or pp)
			right := not pw and (not pp or nw or np)
			var co = left
			var cc = right
			if c == 95:
				co = left and (not right or pp)
				cc = right and (not left or np)
			nodes.append(Node(kind: 1, ch: c, count: j - i, orig: j - i, canOpen: co, canClose: cc))
			i = j
		else if c == 33 and at(text, i + 1) == 91:
			nodes.append(Node(kind: 2, image: true))
			i += 2
		else if c == 91:
			nodes.append(Node(kind: 2, image: false))
			i += 1
		else if c == 93:
			i = closeBracket(var nodes, text, i)
		else:
			addText(var nodes, sub(text, i, i + 1))
			i += 1
	r := resolve(var nodes)
	return r.html

// ---------- blocks ----------

fn indentOf(line: String) Int:
	var k = 0
	while at(line, k) == 32:
		k += 1
	return k

fn isBlank(line: String) Bool:
	return indentOf(line) == line.length()

fn parseFence(line: String) Fence:
	ind := indentOf(line)
	if ind > 3: return Fence()
	c := at(line, ind)
	if c != 96 and c != 126: return Fence()
	var j = ind
	while at(line, j) == c:
		j += 1
	if j - ind < 3: return Fence()
	info := sub(line, j, line.length()).trim_chars(" ")
	if c == 96 and info.index_of("`").is_some(): return Fence()
	return Fence(ok: true, ch: c, len: j - ind, indent: ind, info: info)

fn isClosingFence(line: String, c: Int, len: Int) Bool:
	ind := indentOf(line)
	if ind > 3: return false
	var j = ind
	while at(line, j) == c:
		j += 1
	if j - ind < len: return false
	return isBlank(sub(line, j, line.length()))

fn atxLevel(line: String) Int:
	ind := indentOf(line)
	if ind > 3: return 0
	var j = ind
	while at(line, j) == 35:
		j += 1
	lv := j - ind
	if lv < 1 or lv > 6: return 0
	nx := at(line, j)
	if nx != -1 and nx != 32: return 0
	return lv

fn atxContent(line: String) String:
	ind := indentOf(line)
	var j = ind
	while at(line, j) == 35:
		j += 1
	var content = sub(line, j, line.length()).trim_chars(" ")
	cl := content.length()
	if cl > 0 and at(content, cl - 1) == 35:
		var s = cl
		while s > 0 and at(content, s - 1) == 35:
			s -= 1
		if s == 0:
			content = ""
		else if at(content, s - 1) == 32:
			content = sub(content, 0, s).trim_chars(" ")
	return content

fn isThematic(line: String) Bool:
	ind := indentOf(line)
	if ind > 3: return false
	var c = -1
	var cnt = 0
	for k in ind..line.length():
		x := at(line, k)
		if x == 32: continue
		if x != 45 and x != 42 and x != 95: return false
		if c == -1: c = x
		if x != c: return false
		cnt += 1
	return cnt >= 3

fn isQuote(line: String) Bool:
	ind := indentOf(line)
	return ind <= 3 and at(line, ind) == 62

fn listMarker(line: String) Marker:
	ind := indentOf(line)
	if ind > 3: return Marker()
	c := at(line, ind)
	var p = ind
	var kind = 0
	var ordered = false
	var num = 0
	if c == 45 or c == 42 or c == 43:
		kind = c
		p = ind + 1
	else if isDigit(c):
		var q = ind
		while isDigit(at(line, q)):
			q += 1
		if q - ind > 9: return Marker()
		d := at(line, q)
		if d != 46 and d != 41: return Marker()
		kind = 1000 + d
		ordered = true
		num = sub(line, ind, q).parse_int().get(0)
		p = q + 1
	else:
		return Marker()
	nx := at(line, p)
	if nx != -1 and nx != 32: return Marker()
	var s = 0
	while at(line, p + s) == 32:
		s += 1
	empty := at(line, p + s) == -1
	w := if empty or s >= 5: p + 1 else: p + s
	return Marker(ok: true, kind: kind, num: num, w: w, empty: empty, ordered: ordered)

fn startsInterrupt(line: String) Bool:
	if parseFence(line).ok: return true
	if atxLevel(line) > 0: return true
	if isThematic(line): return true
	if isQuote(line): return true
	return false

fn isInterruptMarker(line: String) Bool:
	m := listMarker(line)
	if not m.ok or m.empty: return false
	if m.ordered and m.num != 1: return false
	return true

fn splitCells(line: String) List[String]:
	var s = line.trim_chars(" ")
	if at(s, 0) == 124:
		s = sub(s, 1, s.length())
	sl := s.length()
	if sl > 0 and at(s, sl - 1) == 124 and not (sl >= 2 and at(s, sl - 2) == 92):
		s = sub(s, 0, sl - 1)
	var cells = List[String]()
	var cur = ""
	for k in 0..s.length():
		c := at(s, k)
		if c == 124 and not (k > 0 and at(s, k - 1) == 92):
			cells.append(cur.trim_chars(" "))
			cur = ""
		else:
			cur += sub(s, k, k + 1)
	cells.append(cur.trim_chars(" "))
	return cells

fn isDelimRow(line: String) Bool:
	if line.index_of("|").is_none(): return false
	for cell in splitCells(line):
		var s = 0
		e := cell.length()
		if at(cell, 0) == 58: s = 1
		var e2 = e
		if e2 > s and at(cell, e2 - 1) == 58: e2 -= 1
		if e2 - s < 1: return false
		for k in s..e2:
			if at(cell, k) != 45: return false
	return true

fn alignAttr(cell: String) String:
	l := at(cell, 0) == 58
	r := at(cell, cell.length() - 1) == 58 and cell.length() > 1
	if l and r: return " align=\"center\""
	if l: return " align=\"left\""
	if r: return " align=\"right\""
	return ""

fn codeBlock(lines: List[String]) String:
	var h = "<pre><code>"
	for l in lines:
		h += esc(l) + "\n"
	return h + "</code></pre>\n"

fn renderBlocks(blks: List[Blk]) String:
	var h = ""
	for b in blks:
		if b.para:
			h += "<p>" + b.html + "</p>\n"
		else:
			h += b.html
	return h

fn renderItem(kids: List[Blk], loose: Bool) String:
	var body = ""
	for b in kids:
		if b.para and not loose:
			body += b.html
		else:
			if body.length() == 0 or at(body, body.length() - 1) != 10:
				body += "\n"
			if b.para:
				body += "<p>" + b.html + "</p>\n"
			else:
				body += b.html
	return "<li>" + body + "</li>\n"

fn parseBlocks(lines: List[String]) List[Blk]:
	var out = List[Blk]()
	n := lines.length()
	var i = 0
	while i < n:
		line := lines[i]
		if isBlank(line):
			i += 1
			continue
		// 1 fenced
		f := parseFence(line)
		if f.ok:
			var content = List[String]()
			var j = i + 1
			var closed = false
			while j < n:
				l2 := lines[j]
				if isClosingFence(l2, f.ch, f.len):
					closed = true
					break
				var r = 0
				while r < f.indent and at(l2, r) == 32:
					r += 1
				content.append(sub(l2, r, l2.length()))
				j += 1
			var h = "<pre><code>"
			if f.info.length() > 0:
				w := f.info.split(" ")[0].clone()
				h = "<pre><code class=\"language-{esc(w)}\">"
			for l in content:
				h += esc(l) + "\n"
			h += "</code></pre>\n"
			endi := if closed: j + 1 else: j
			out.append(Blk(html: h, start: i, end: endi))
			i = endi
			continue
		// 2 atx
		lv := atxLevel(line)
		if lv > 0:
			out.append(Blk(html: "<h{lv}>{inline(atxContent(line))}</h{lv}>\n", start: i, end: i + 1))
			i += 1
			continue
		// 3 thematic
		if isThematic(line):
			out.append(Blk(html: "<hr />\n", start: i, end: i + 1))
			i += 1
			continue
		// 4 quote
		if isQuote(line):
			var inner = List[String]()
			var j = i
			while j < n and isQuote(lines[j]):
				l2 := lines[j]
				ind := indentOf(l2)
				var st = ind + 1
				if at(l2, st) == 32: st += 1
				inner.append(sub(l2, st, l2.length()))
				j += 1
			kids := parseBlocks(inner)
			out.append(Blk(html: "<blockquote>\n" + renderBlocks(kids) + "</blockquote>\n", start: i, end: j))
			i = j
			continue
		// 5 list
		m0 := listMarker(line)
		if m0.ok:
			var items = List[List[Blk]]()
			var loose = false
			var cur = m0.clone()
			var curLine = i
			var j = i
			var listEnd = i
			while true:
				l1 := lines[curLine]
				var itemLines = List[String]()
				if l1.length() > cur.w:
					itemLines.append(sub(l1, cur.w, l1.length()))
				else:
					itemLines.append("")
				j = curLine + 1
				var pending = 0
				while j < n:
					l2 := lines[j]
					if isBlank(l2):
						pending += 1
						j += 1
					else if indentOf(l2) >= cur.w:
						for _u in 0..pending:
							itemLines.append("")
						pending = 0
						itemLines.append(sub(l2, cur.w, l2.length()))
						j += 1
					else:
						break
				itemEnd := j - pending
				kids := parseBlocks(itemLines)
				for q in 1..kids.length():
					if kids[q].start > kids[q - 1].end:
						loose = true
				items.append(kids)
				listEnd = itemEnd
				if j < n:
					nm := listMarker(lines[j])
					if nm.ok and nm.kind == m0.kind and not isThematic(lines[j]):
						if j > itemEnd: loose = true
						cur = nm
						curLine = j
						continue
				break
			var h = "<ul>\n"
			if m0.ordered:
				h = "<ol>\n"
				if m0.num != 1:
					h = "<ol start=\"{m0.num}\">\n"
			for kids in items:
				h += renderItem(kids, loose)
			h += if m0.ordered: "</ol>\n" else: "</ul>\n"
			out.append(Blk(html: h, start: i, end: listEnd))
			i = listEnd
			continue
		// 6 indented code
		if indentOf(line) >= 4:
			var j = i
			var lastNb = i
			while j < n and (isBlank(lines[j]) or indentOf(lines[j]) >= 4):
				if not isBlank(lines[j]): lastNb = j
				j += 1
			var content = List[String]()
			for q in i..(lastNb + 1):
				l2 := lines[q]
				var r = 0
				while r < 4 and at(l2, r) == 32:
					r += 1
				content.append(sub(l2, r, l2.length()))
			out.append(Blk(html: codeBlock(content), start: i, end: lastNb + 1))
			i = lastNb + 1
			continue
		// 7 table
		if i + 1 < n and line.index_of("|").is_some() and isDelimRow(lines[i + 1]):
			head := splitCells(line)
			delim := splitCells(lines[i + 1])
			if head.length() == delim.length():
				nc := head.length()
				var h = "<table>\n<thead>\n<tr>\n"
				for c in 0..nc:
					h += "<th{alignAttr(delim[c])}>{inline(head[c])}</th>\n"
				h += "</tr>\n</thead>\n"
				var j = i + 2
				var body = ""
				while j < n and not isBlank(lines[j]) and not startsInterrupt(lines[j]):
					cells := splitCells(lines[j])
					body += "<tr>\n"
					for c in 0..nc:
						cell := cells.get(c, "")
						body += "<td{alignAttr(delim[c])}>{inline(cell)}</td>\n"
					body += "</tr>\n"
					j += 1
				if body.length() > 0:
					h += "<tbody>\n" + body + "</tbody>\n"
				h += "</table>\n"
				out.append(Blk(html: h, start: i, end: j))
				i = j
				continue
		// 8 paragraph
		var j = i + 1
		while j < n:
			l2 := lines[j]
			if isBlank(l2) or startsInterrupt(l2) or isInterruptMarker(l2): break
			j += 1
		var text = ""
		for q in i..j:
			var l2 = lines[q].trim_start()
			if q == j - 1:
				l2 = l2.trim_end()
			else:
				tl := l2.trim_end()
				if l2.length() - tl.length() >= 2:
					l2 = tl + "\u{1}"
				else:
					l2 = tl
			if q > i: text += "\n"
			text += l2
		out.append(Blk(para: true, html: inline(text), start: i, end: j))
		i = j
	return out

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	bytes := read_all(stdin(), none)?
	text := bytes.decode_utf8().get("")
	if text.length() == 0: return ok(unit)
	var lines = text.split("\n").clone()
	if at(text, text.length() - 1) == 10:
		_x := lines.pop()
	print(renderBlocks(parseBlocks(lines)), end: "")
	return ok(unit)

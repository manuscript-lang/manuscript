import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Tok:
	kind: Int = 0
	s: String = ""
	t: String = ""
	hastitle: Bool = false
	c: String = ""
	n: Int = 0
	orig: Int = 0
	co: Bool = false
	cc: Bool = false
	active: Bool = true
	image: Bool = false

type Tail:
	ok: Bool = false
	dest: String = ""
	title: String = ""
	hastitle: Bool = false
	end: Int = 0

fn at(s: String, i: Int) String:
	if i < 0 or i >= s.length(): return ""
	return s.view(i, i + 1).clone()

fn esc(s: String) String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

fn rep(c: String, n: Int) String:
	var r = ""
	for _i in 0..n:
		r += c
	return r

fn is_punct(c: String) Bool:
	if c.length() != 1: return false
	return "!\"#$%&'()*+,-./:;<=>?@[\\]^_`\{|\}~".contains(c)

fn is_digit(c: String) Bool:
	if c.length() != 1: return false
	return "0123456789".contains(c)

fn is_ws(c: String) Bool:
	return c == "" or c == " " or c == "\n" or c == "\r"

fn is_sp(c: String) Bool:
	return c == " " or c == "\n" or c == "\r"

fn skip_ws(s: String, p: Int) Int:
	var q = p
	while is_sp(at(s, q)):
		q += 1
	return q

fn parse_tail(s: String, p: Int) Tail:
	n := s.length()
	var q = skip_ws(s, p + 1)
	var dest = ""
	if at(s, q) == "<":
		q += 1
		var closed = false
		while q < n:
			c := at(s, q)
			if c == "\n" or c == "<": return Tail()
			if c == ">":
				closed = true
				break
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
		while q < n:
			c := at(s, q)
			if is_sp(c): break
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
	q2 := skip_ws(s, q)
	ws := q2 > q
	q = q2
	var title = ""
	var hastitle = false
	if ws and at(s, q) == "\"":
		q += 1
		var closed = false
		while q < n:
			c := at(s, q)
			if c == "\\" and is_punct(at(s, q + 1)):
				title += at(s, q + 1)
				q += 2
				continue
			if c == "\"":
				closed = true
				break
			title += c
			q += 1
		if not closed: return Tail()
		q += 1
		q = skip_ws(s, q)
		hastitle = true
	if at(s, q) != ")": return Tail()
	return Tail(ok: true, dest: dest.replace("\r", ""), title: title.replace("\r", ""), hastitle: hastitle, end: q + 1)

fn flush(var toks: List[Tok], var buf: String) Unit:
	if buf.length() > 0:
		toks.append(Tok(kind: 0, s: buf.clone()))
		buf = ""

fn resolve(var toks: List[Tok], lo: Int) Unit:
	var i = lo
	while i < toks.length():
		if toks[i].kind == 1 and toks[i].cc and toks[i].n > 0:
			var j = i - 1
			var found = -1
			while j >= lo:
				if toks[j].kind == 1 and toks[j].c == toks[i].c and toks[j].co and toks[j].n > 0:
					var ok = true
					if toks[j].cc or toks[i].co:
						sum := toks[j].orig + toks[i].orig
						if sum % 3 == 0 and not (toks[j].orig % 3 == 0 and toks[i].orig % 3 == 0):
							ok = false
					if ok:
						found = j
						break
				j -= 1
			if found < 0:
				i += 1
				continue
			use := if toks[found].n >= 2 and toks[i].n >= 2: 2 else: 1
			for k in found + 1..i:
				if toks[k].kind == 1:
					toks[k].s = rep(toks[k].c, toks[k].n)
					toks[k].kind = 0
			toks[found].n -= use
			toks[i].n -= use
			if toks[found].n == 0:
				toks[found].kind = 0
				toks[found].s = ""
			ck := if use == 2: 9 else: 7
			ok2 := if use == 2: 8 else: 6
			toks.insert(i, Tok(kind: ck))
			toks.insert(found + 1, Tok(kind: ok2))
			i += 2
			if toks[i].n == 0:
				toks[i].kind = 0
				toks[i].s = ""
				i += 1
		else:
			i += 1

fn bracket(var toks: List[Tok], s: String, i: Int) Int:
	var m = toks.length() - 1
	while m >= 0 and toks[m].kind != 2:
		m -= 1
	if m < 0:
		toks.append(Tok(kind: 0, s: "]"))
		return i + 1
	if not toks[m].image and not toks[m].active:
		toks[m].kind = 0
		toks.append(Tok(kind: 0, s: "]"))
		return i + 1
	if at(s, i + 1) == "(":
		tail := parse_tail(s, i + 1)
		if tail.ok:
			resolve(var toks, m + 1)
			for k in m + 1..toks.length():
				if toks[k].kind == 1:
					toks[k].s = rep(toks[k].c, toks[k].n)
					toks[k].kind = 0
				else if toks[k].kind == 2:
					toks[k].kind = 0
			isimg := toks[m].image
			toks[m].kind = if isimg: 12 else: 10
			toks[m].s = tail.dest.clone()
			toks[m].t = tail.title.clone()
			toks[m].hastitle = tail.hastitle
			ck := if isimg: 13 else: 11
			toks.append(Tok(kind: ck, t: tail.title.clone(), hastitle: tail.hastitle))
			if not isimg:
				for k in 0..m:
					if toks[k].kind == 2 and not toks[k].image:
						toks[k].active = false
			return tail.end
	toks[m].kind = 0
	toks.append(Tok(kind: 0, s: "]"))
	return i + 1

fn scan(s: String) List[Tok]:
	var toks = List[Tok]()
	var buf = ""
	var i = 0
	n := s.length()
	while i < n:
		c := at(s, i)
		if c == "\\":
			nx := at(s, i + 1)
			if nx == "\n":
				flush(var toks, var buf)
				toks.append(Tok(kind: 4))
				i += 2
			else if is_punct(nx):
				buf += nx
				i += 2
			else:
				buf += "\\"
				i += 1
		else if c == "\r":
			if at(s, i + 1) == "\n":
				flush(var toks, var buf)
				toks.append(Tok(kind: 4))
				i += 2
			else:
				i += 1
		else if c == "\n":
			flush(var toks, var buf)
			toks.append(Tok(kind: 3))
			i += 1
		else if c == "`":
			var k = i
			while at(s, k) == "`":
				k += 1
			nrun := k - i
			var j = k
			var found = false
			while j < n:
				if at(s, j) == "`":
					var e = j
					while at(s, e) == "`":
						e += 1
					if e - j == nrun:
						found = true
						break
					j = e
				else:
					j += 1
			if found:
				var content = s.view(k, j).clone().replace("\n", " ").replace("\r", "")
				if content.starts_with(" ") and content.ends_with(" ") and content.trim() != "":
					content = content.view(1, content.length() - 1).clone()
				flush(var toks, var buf)
				toks.append(Tok(kind: 5, s: content))
				i = j + nrun
			else:
				buf += rep("`", nrun)
				i = k
		else if c == "*" or c == "_":
			var k = i
			while at(s, k) == c:
				k += 1
			nrun := k - i
			prev := at(s, i - 1)
			next := at(s, k)
			pw := is_ws(prev)
			nw := is_ws(next)
			pp := is_punct(prev)
			np := is_punct(next)
			left := (not nw) and ((not np) or pw or pp)
			right := (not pw) and ((not pp) or nw or np)
			var co = left
			var cc = right
			if c == "_":
				co = left and ((not right) or pp)
				cc = right and ((not left) or np)
			flush(var toks, var buf)
			toks.append(Tok(kind: 1, c: c, n: nrun, orig: nrun, co: co, cc: cc))
			i = k
		else if c == "!" and at(s, i + 1) == "[":
			flush(var toks, var buf)
			toks.append(Tok(kind: 2, s: "![", image: true))
			i += 2
		else if c == "[":
			flush(var toks, var buf)
			toks.append(Tok(kind: 2, s: "["))
			i += 1
		else if c == "]":
			flush(var toks, var buf)
			i = bracket(var toks, s, i)
		else:
			buf += c
			i += 1
	flush(var toks, var buf)
	return toks

fn render(toks: List[Tok]) String:
	var out = ""
	var alt = 0
	for t in toks:
		k := t.kind
		if alt > 0:
			if k == 0 or k == 2:
				out += esc(t.s)
			else if k == 1:
				out += rep(t.c, t.n)
			else if k == 5:
				out += esc(t.s)
			else if k == 3 or k == 4:
				out += " "
			else if k == 12:
				alt += 1
			else if k == 13:
				alt -= 1
				if alt == 0:
					out += "\""
					if t.hastitle:
						out += " title=\"" + esc(t.t) + "\""
					out += " />"
		else:
			if k == 0 or k == 2:
				out += esc(t.s)
			else if k == 1:
				out += rep(t.c, t.n)
			else if k == 3:
				out += "\n"
			else if k == 4:
				out += "<br />\n"
			else if k == 5:
				out += "<code>" + esc(t.s) + "</code>"
			else if k == 6:
				out += "<em>"
			else if k == 7:
				out += "</em>"
			else if k == 8:
				out += "<strong>"
			else if k == 9:
				out += "</strong>"
			else if k == 10:
				out += "<a href=\"" + esc(t.s) + "\""
				if t.hastitle:
					out += " title=\"" + esc(t.t) + "\""
				out += ">"
			else if k == 11:
				out += "</a>"
			else if k == 12:
				out += "<img src=\"" + esc(t.s) + "\" alt=\""
				alt = 1
	return out

fn inline(text: String) String:
	var toks = scan(text)
	resolve(var toks, 0)
	return render(toks)

// ---------------- blocks ----------------

type Block:
	para: Bool = false
	html: String = ""
	blank_before: Bool = false

type Fence:
	ok: Bool = false
	ch: String = ""
	len: Int = 0
	ind: Int = 0
	info: String = ""

type Atx:
	ok: Bool = false
	level: Int = 0
	content: String = ""

type Marker:
	ok: Bool = false
	ordered: Bool = false
	ch: String = ""
	num: Int = 0
	w: Int = 0
	nonempty: Bool = false

type ListRes:
	html: String = ""
	next: Int = 0

fn indent(line: String) Int:
	var k = 0
	while at(line, k) == " ":
		k += 1
	return k

fn is_blank(line: String) Bool:
	return indent(line) == line.length()

fn strip_lead(line: String, k: Int) String:
	var m = indent(line)
	if m > k:
		m = k
	return line.view(m, line.length()).clone()

fn parse_fence(line: String) Fence:
	ind := indent(line)
	if ind > 3: return Fence()
	c := at(line, ind)
	if c != "`" and c != "~": return Fence()
	var k = ind
	while at(line, k) == c:
		k += 1
	len := k - ind
	if len < 3: return Fence()
	info := line.view(k, line.length()).clone().trim()
	if c == "`" and info.contains("`"): return Fence()
	return Fence(ok: true, ch: c, len: len, ind: ind, info: info)

fn is_close_fence(line: String, f: Fence) Bool:
	ind := indent(line)
	if ind > 3: return false
	var k = ind
	while at(line, k) == f.ch:
		k += 1
	if k - ind < f.len: return false
	return line.view(k, line.length()).clone().trim() == ""

fn parse_atx(line: String) Atx:
	ind := indent(line)
	if ind > 3: return Atx()
	var k = ind
	while at(line, k) == "#":
		k += 1
	lvl := k - ind
	if lvl < 1 or lvl > 6: return Atx()
	if k < line.length() and at(line, k) != " ": return Atx()
	var content = line.view(k, line.length()).clone().trim()
	var e = content.length()
	while e > 0 and at(content, e - 1) == "#":
		e -= 1
	if e < content.length() and (e == 0 or at(content, e - 1) == " "):
		content = content.view(0, e).clone().trim_end()
	return Atx(ok: true, level: lvl, content: content)

fn is_hr(line: String) Bool:
	if indent(line) > 3: return false
	s := line.replace(" ", "")
	if s.length() < 3: return false
	c := at(s, 0)
	if c != "-" and c != "*" and c != "_": return false
	return s.replace(c, "") == ""

fn is_quote(line: String) Bool:
	ind := indent(line)
	return ind <= 3 and at(line, ind) == ">"

fn parse_marker(line: String) Marker:
	ind := indent(line)
	if ind > 3: return Marker()
	c := at(line, ind)
	var m = 0
	var ordered = false
	var ch = ""
	var num = 0
	if c == "-" or c == "*" or c == "+":
		m = ind + 1
		ch = c
	else if is_digit(c):
		var k = ind
		while is_digit(at(line, k)):
			k += 1
		cnt := k - ind
		if cnt > 9: return Marker()
		d := at(line, k)
		if d != "." and d != ")": return Marker()
		num = line.view(ind, k).clone().parse_int().get(0)
		ordered = true
		ch = d
		m = k + 1
	else:
		return Marker()
	nx := at(line, m)
	if nx != "" and nx != " ": return Marker()
	rest := line.view(m, line.length()).clone()
	var w = m + 1
	if rest != "":
		sp := indent(rest)
		if sp < 5:
			w = m + sp
	return Marker(ok: true, ordered: ordered, ch: ch, num: num, w: w, nonempty: rest != "")

fn starts_block(l: String) Bool:
	if parse_fence(l).ok: return true
	if parse_atx(l).ok: return true
	if is_hr(l): return true
	return is_quote(l)

fn interrupts(l: String) Bool:
	if starts_block(l): return true
	mk := parse_marker(l)
	return mk.ok and mk.nonempty and ((not mk.ordered) or mk.num == 1)

fn split_cells(line: String) List[String]:
	var s = line.trim()
	if s.starts_with("|"):
		s = s.view(1, s.length()).clone()
	if s.ends_with("|") and at(s, s.length() - 2) != "\\":
		s = s.view(0, s.length() - 1).clone()
	var cells = List[String]()
	var cur = ""
	for i in 0..s.length():
		c := at(s, i)
		if c == "|" and (i == 0 or at(s, i - 1) != "\\"):
			cells.append(cur.trim())
			cur = ""
		else:
			cur += c
	cells.append(cur.trim())
	return cells

fn delim_ok(cell: String) Bool:
	var c = cell
	if c.starts_with(":"):
		c = c.view(1, c.length()).clone()
	if c.ends_with(":"):
		c = c.view(0, c.length() - 1).clone()
	return c.length() > 0 and c.replace("-", "") == ""

fn align_attr(cell: String) String:
	l := cell.starts_with(":")
	r := cell.ends_with(":")
	if l and r: return " align=\"center\""
	if l: return " align=\"left\""
	if r: return " align=\"right\""
	return ""

fn full(b: Block) String:
	if b.para: return "<p>" + b.html + "</p>\n"
	return b.html.clone()

fn parse_list(lines: List[String], start: Int, first: Marker) ListRes:
	n := lines.length()
	var i = start
	var loose = false
	var items = List[List[Block]]()
	var end = start
	while true:
		mk := parse_marker(lines[i])
		line := lines[i]
		var content = List[String]()
		if mk.w <= line.length():
			content.append(line.view(mk.w, line.length()).clone())
		else:
			content.append("")
		var j = i + 1
		var pending = 0
		while j < n:
			l := lines[j]
			if is_blank(l):
				pending += 1
				j += 1
				continue
			if indent(l) >= mk.w:
				for _p in 0..pending:
					content.append("")
				pending = 0
				content.append(l.view(mk.w, l.length()).clone())
				j += 1
			else:
				break
		lastend := j - pending
		blocks := parse_blocks(content)
		for b in 1..blocks.length():
			if blocks[b].blank_before:
				loose = true
		items.append(blocks)
		var k = lastend
		while k < n and is_blank(lines[k]):
			k += 1
		end = lastend
		if k < n:
			nm := parse_marker(lines[k])
			if nm.ok and not is_hr(lines[k]) and nm.ordered == first.ordered and nm.ch == first.ch:
				if k > lastend:
					loose = true
				i = k
				continue
		break
	var html = ""
	if first.ordered:
		if first.num != 1:
			html += "<ol start=\"" + "{first.num}" + "\">\n"
		else:
			html += "<ol>\n"
	else:
		html += "<ul>\n"
	for item in items:
		var body = ""
		for b in item:
			if b.para and not loose:
				body += b.html
			else:
				if not body.ends_with("\n"):
					body += "\n"
				body += full(b)
		html += "<li>" + body + "</li>\n"
	if first.ordered:
		html += "</ol>\n"
	else:
		html += "</ul>\n"
	return ListRes(html: html, next: end)

fn code_html(lines: List[String], cls: String) String:
	var html = "<pre><code" + cls + ">"
	for l in lines:
		html += esc(l) + "\n"
	return html + "</code></pre>\n"

fn parse_blocks(lines: List[String]) List[Block]:
	var blocks = List[Block]()
	var i = 0
	var skipped = false
	n := lines.length()
	while i < n:
		line := lines[i]
		if is_blank(line):
			i += 1
			skipped = true
			continue
		bb := skipped and blocks.length() > 0
		skipped = false
		f := parse_fence(line)
		if f.ok:
			var cl = ""
			if f.info != "":
				cl = " class=\"language-" + esc(f.info.split(" ").get(0, "")) + "\""
			var cl2 = List[String]()
			var j = i + 1
			while j < n and not is_close_fence(lines[j], f):
				cl2.append(strip_lead(lines[j], f.ind))
				j += 1
			blocks.append(Block(html: code_html(cl2, cl), blank_before: bb))
			i = if j < n: j + 1 else: n
			continue
		a := parse_atx(line)
		if a.ok:
			blocks.append(Block(html: "<h{a.level}>" + inline(a.content) + "</h{a.level}>\n", blank_before: bb))
			i += 1
			continue
		if is_hr(line):
			blocks.append(Block(html: "<hr />\n", blank_before: bb))
			i += 1
			continue
		if is_quote(line):
			var inner = List[String]()
			var j = i
			while j < n and is_quote(lines[j]):
				l := lines[j]
				ind := indent(l)
				var r = l.view(ind + 1, l.length()).clone()
				if r.starts_with(" "):
					r = r.view(1, r.length()).clone()
				inner.append(r)
				j += 1
			var h = "<blockquote>\n"
			for b in parse_blocks(inner):
				h += full(b)
			h += "</blockquote>\n"
			blocks.append(Block(html: h, blank_before: bb))
			i = j
			continue
		mk := parse_marker(line)
		if mk.ok:
			res := parse_list(lines, i, mk)
			blocks.append(Block(html: res.html, blank_before: bb))
			i = res.next
			continue
		if indent(line) >= 4:
			var cl2 = List[String]()
			var j = i
			while j < n and (is_blank(lines[j]) or indent(lines[j]) >= 4):
				cl2.append(strip_lead(lines[j], 4))
				j += 1
			while cl2.length() > 0 and is_blank(cl2.get(cl2.length() - 1, "")):
				cl2.pop()
			blocks.append(Block(html: code_html(cl2, ""), blank_before: bb))
			i = j
			continue
		if i + 1 < n and line.contains("|") and lines[i + 1].contains("|"):
			hc := split_cells(line)
			dc := split_cells(lines[i + 1])
			var okd = hc.length() == dc.length()
			for d in dc:
				if not delim_ok(d.clone()):
					okd = false
			if okd:
				cols := hc.length()
				var h = "<table>\n<thead>\n<tr>\n"
				for c in 0..cols:
					h += "<th" + align_attr(dc[c]) + ">" + inline(hc[c]) + "</th>\n"
				h += "</tr>\n</thead>\n"
				var j = i + 2
				var body = ""
				while j < n and not is_blank(lines[j]) and not starts_block(lines[j]):
					cells := split_cells(lines[j])
					body += "<tr>\n"
					for c in 0..cols:
						body += "<td" + align_attr(dc[c]) + ">" + inline(cells.get(c, "")) + "</td>\n"
					body += "</tr>\n"
					j += 1
				if body != "":
					h += "<tbody>\n" + body + "</tbody>\n"
				h += "</table>\n"
				blocks.append(Block(html: h, blank_before: bb))
				i = j
				continue
		var j = i
		var text = ""
		while j < n:
			l := lines[j]
			if j > i and (is_blank(l) or interrupts(l)):
				break
			var t = l.trim_start()
			nxt := j + 1 < n and not is_blank(lines[j + 1]) and not interrupts(lines[j + 1])
			if nxt:
				hard := t.ends_with("  ")
				t = t.trim_end()
				if hard:
					t += "\r"
				text += t + "\n"
			else:
				text += t.trim_end()
			j += 1
		blocks.append(Block(para: true, html: inline(text), blank_before: bb))
		i = j
	return blocks

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	bytes := read_all(stdin())?
	text := bytes.decode_utf8().ok_or(Error("bad utf8"))?
	var lines = List[String]()
	if text != "":
		lines = text.split("\n").clone()
		if text.ends_with("\n"):
			lines.pop()
	var out = ""
	for b in parse_blocks(lines):
		out += full(b)
	print(out, end: "")

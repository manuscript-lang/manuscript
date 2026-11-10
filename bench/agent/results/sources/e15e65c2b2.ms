import stdin, stdout from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

// ---------------------------------------------------------------
// Data types
// ---------------------------------------------------------------

// A block: kind 0 = pre-rendered html, kind 1 = paragraph (text, rendered later).
// blank = blank lines precede it (between siblings); nxt = next line index.
type Block:
    kind: Int
    html: String
    text: String
    blank: Bool
    nxt: Int

type Item:
    kids: List[Block]
    loose: Bool

type Marker:
    ok: Bool
    ordered: Bool
    ch: String
    num: Int
    w: Int
    empty: Bool

type Tail:
    ok: Bool
    dest: String
    title: String
    has_title: Bool
    stop: Int

// Inline node kinds: 0 text, 1 hard break, 2 code, 3 delimiter run,
// 4 bracket opener, 5 link or image, 6 emphasis.
type Node:
    kind: Int
    text: String
    title: String
    has_title: Bool
    img: Bool
    active: Bool
    cnt: Int
    orig: Int
    can_open: Bool
    can_close: Bool
    strong: Bool
    kids: List[Node]

// ---------------------------------------------------------------
// Small string helpers
// ---------------------------------------------------------------

// Character at k (as a fresh string), or "" when out of range.
fn chr(s: String, k: Int) String:
    if k >= 0 and k < s.length():
        return s.get(k)

    return ""

// Scalar at k of a char list, or "" when out of range.
fn cat(cs: List[String], k: Int) String:
    if k >= 0 and k < cs.length():
        return cs[k].clone()

    return ""

// Substring [a, b), clamped.
fn sub(s: String, a: Int, b: Int) String:
    var x = a
    var y = b
    if x < 0:
        x = 0
    if y > s.length():
        y = s.length()
    if y <= x:
        return ""

    return s.slice(x, y).get("")

// Joins cs[a..b).
fn join_range(cs: List[String], a: Int, b: Int) String:
    var r = ""
    var k = a

    while k < b:
        r = r + cs[k]
        k += 1

    return r

fn rep(s: String, n: Int) String:
    var r = ""
    var k = 0

    while k < n:
        r = r + s
        k += 1

    return r

fn leading(s: String) Int:
    var i = 0
    while i < s.length() and s.get(i) == " ":
        i += 1
    return i

fn is_blank(s: String) Bool:
    return leading(s) == s.length()

fn ltrim_sp(s: String) String:
    return sub(s, leading(s), s.length())

fn rtrim_sp(s: String) String:
    var e = s.length()
    while e > 0 and s.get(e - 1) == " ":
        e -= 1
    return sub(s, 0, e)

fn trim_sp(s: String) String:
    return rtrim_sp(ltrim_sp(s))

fn esc(s: String) String:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
        "\"", "&quot;"
    )

fn is_digit(c: String) Bool:
    return c != "" and "0123456789".contains(c)

fn is_punct(c: String) Bool:
    return c.length() == 1 and "!\"#$%&'()*+,-./:;<=>?@[\\]^_`\{|\}~".contains(c)

fn is_ws(c: String) Bool:
    return c == "" or c == " " or c == "\n" or c == "\r"

fn is_space_nl(c: String) Bool:
    return c == " " or c == "\n" or c == "\r"

fn html_block(h: String, nxt: Int) Block:
    return Block(kind: 0, html: h, text: "", blank: false, nxt: nxt)

// ---------------------------------------------------------------
// Block-level recognizers
// ---------------------------------------------------------------

// Length of the opening fence run, or 0 when the line is not a fence opener.
fn fence_run(line: String) Int:
    ind := leading(line)
    if ind > 3 or ind >= line.length():
        return 0

    c := line.get(ind)
    if c != "`" and c != "~":
        return 0

    var n = 0
    while ind + n < line.length() and line.get(ind + n) == c:
        n += 1
    if n < 3:
        return 0
    if c == "`" and sub(line, ind + n, line.length()).contains("`"):
        return 0

    return n

fn is_fence(line: String) Bool:
    return fence_run(line) > 0

// ATX heading level, or 0.
fn heading_level(line: String) Int:
    ind := leading(line)
    if ind > 3:
        return 0

    var n = 0
    while ind + n < line.length() and line.get(ind + n) == "#":
        n += 1
    if n < 1 or n > 6:
        return 0
    if ind + n == line.length() or line.get(ind + n) == " ":
        return n

    return 0

fn is_hr(line: String) Bool:
    ind := leading(line)
    if ind > 3:
        return false

    var mark = ""
    var cnt = 0
    var k = ind

    while k < line.length():
        c := line.get(k)

        if c != " ":
            if mark == "":
                if c != "-" and c != "*" and c != "_":
                    return false

                mark = c.clone()

            if c != mark:
                return false

            cnt += 1

        k += 1

    return cnt >= 3

fn is_quote(line: String) Bool:
    return leading(line) <= 3 and chr(line, leading(line)) == ">"

// List marker recognition (see spec: Lists).
fn marker(line: String) Marker:
    none := Marker(ok: false, ordered: false, ch: "", num: 0, w: 0, empty: true)
    ind := leading(line)
    if ind > 3 or ind >= line.length():
        return none

    c := line.get(ind)
    var after = ind + 1
    var ordered = false
    var ch = c.clone()
    var num = 0

    if c == "-" or c == "*" or c == "+":
        after = ind + 1
    else:
        var k = ind
        while k < line.length() and is_digit(line.get(k)):
            k += 1

        nd := k - ind
        if nd < 1 or nd > 9 or k >= line.length():
            return none

        d := line.get(k)
        if d != "." and d != ")":
            return none

        ordered = true
        ch = d
        num = sub(line, ind, k).parse_int().get(0)
        after = k + 1

    if after < line.length() and line.get(after) != " ":
        return none

    var sp = 0
    var p = after

    while p < line.length() and line.get(p) == " ":
        sp += 1
        p += 1

    var w = after + sp
    if after == line.length() or sp >= 5:
        w = after + 1
    return Marker(
        ok: true, ordered: ordered, ch: ch, num: num, w: w, empty: p == line.length()
    )

// Splits a table row into trimmed cells.
fn split_cells(line: String) List[String]:
    var s = trim_sp(line)
    if chr(s, 0) == "|":
        s = sub(s, 1, s.length())

    m := s.length()
    if m > 0 and s.get(m - 1) == "|" and not (m >= 2 and s.get(m - 2) == "\\"):
        s = sub(s, 0, m - 1)

    var cells = List[String]()
    var cur = ""
    var k = 0

    while k < s.length():
        c := s.get(k)

        if c == "|" and not (k > 0 and s.get(k - 1) == "\\"):
            cells.append(trim_sp(cur))
            cur = ""
        else:
            cur = cur + c

        k += 1

    cells.append(trim_sp(cur))
    return cells

// Alignment of a delimiter cell: -1 invalid, 0 none, 1 left, 2 center, 3 right.
fn align_of(cell: String) Int:
    var a = 0
    var b = cell.length()
    var lead = false
    var trail = false

    if chr(cell, 0) == ":":
        lead = true
        a = 1

    if b > a and cell.get(b - 1) == ":":
        trail = true
        b -= 1

    if b <= a:
        return -1

    var k = a

    while k < b:
        if cell.get(k) != "-":
            return -1

        k += 1

    if lead and trail:
        return 2
    if lead:
        return 1
    if trail:
        return 3

    return 0

fn is_delim_row(line: String) Bool:
    if not line.contains("|"):
        return false

    cells := split_cells(line)
    for c in cells:
        if align_of(c) < 0:
            return false
    return true

fn table_start(lines: List[String], i: Int) Bool:
    if i + 1 >= lines.length():
        return false
    if not lines[i].contains("|"):
        return false
    if not is_delim_row(lines[i + 1]):
        return false

    return split_cells(lines[i]).length() == split_cells(lines[i + 1]).length()

// Lines that end a table body or interrupt a paragraph (rules 1-4 on their own).
fn is_block_start(line: String) Bool:
    return is_fence(line) or heading_level(line) > 0 or is_hr(line) or is_quote(line)

fn interrupts_para(line: String) Bool:
    if is_blank(line):
        return true
    if is_block_start(line):
        return true

    m := marker(line)
    return m.ok and not m.empty and (not m.ordered or m.num == 1)

// ---------------------------------------------------------------
// Block parsing and rendering
// ---------------------------------------------------------------

fn parse_fence(lines: List[String], i: Int) Block:
    line := lines[i]
    ind := leading(line)
    c := line.get(ind)
    n := fence_run(line)
    info := trim_sp(sub(line, ind + n, line.length()))
    var open = "<pre><code>"

    if info.length() > 0:
        word := info.split(" ").get(0, "")
        open = "<pre><code class=\"language-" + esc(word) + "\">"

    var body = ""
    var j = i + 1
    var closed = false

    while j < lines.length():
        l := lines[j]
        li := leading(l)

        if li <= 3 and li < l.length() and l.get(li) == c:
            var m = 0
            while li + m < l.length() and l.get(li + m) == c:
                m += 1

            if m >= n and is_blank(sub(l, li + m, l.length())):
                closed = true
                break

        var k = li
        if k > ind:
            k = ind
        body = body + esc(sub(l, k, l.length())) + "\n"
        j += 1

    var nxt = j
    if closed:
        nxt = j + 1
    return html_block(open + body + "</code></pre>\n", nxt)

fn parse_heading(line: String, i: Int) Block:
    lvl := heading_level(line)
    var content = trim_sp(sub(line, leading(line) + lvl, line.length()))
    m := content.length()
    var e = m
    while e > 0 and content.get(e - 1) == "#":
        e -= 1
    if e < m and (e == 0 or content.get(e - 1) == " "):
        content = rtrim_sp(sub(content, 0, e))
    return html_block(
        "<h" + lvl.to_string() + ">" + inline(
            content
        ) + "</h" + lvl.to_string() + ">\n",
        i + 1
    )

fn parse_quote(lines: List[String], i: Int) Block:
    var inner = List[String]()
    var j = i

    while j < lines.length() and is_quote(lines[j]):
        l := lines[j]
        var rest = sub(l, leading(l) + 1, l.length())
        if chr(rest, 0) == " ":
            rest = sub(rest, 1, rest.length())
        inner.append(rest)
        j += 1

    body := render_top(parse_blocks(inner))
    return html_block("<blockquote>\n" + body + "</blockquote>\n", j)

fn parse_indented(lines: List[String], i: Int) Block:
    var last = i
    var j = i

    while j < lines.length() and (is_blank(lines[j]) or leading(lines[j]) >= 4):
        if not is_blank(lines[j]):
            last = j
        j += 1

    var html = "<pre><code>"
    var k = i

    while k <= last:
        l := lines[k]
        var r = leading(l)
        if r > 4:
            r = 4
        html = html + esc(sub(l, r, l.length())) + "\n"
        k += 1

    return html_block(html + "</code></pre>\n", last + 1)

fn align_attr(a: Int) String:
    if a == 1:
        return " align=\"left\""
    if a == 2:
        return " align=\"center\""
    if a == 3:
        return " align=\"right\""

    return ""

fn parse_table(lines: List[String], i: Int) Block:
    head := split_cells(lines[i])
    delim := split_cells(lines[i + 1])
    var aligns = List[Int]()
    for c in delim:
        aligns.append(align_of(c))

    nc := head.length()
    var html = "<table>\n<thead>\n<tr>\n"
    var k = 0

    while k < nc:
        html = html + "<th" + align_attr(aligns[k]) + ">" + inline(head[k]) + "</th>\n"
        k += 1

    html = html + "</tr>\n</thead>\n"

    var rows = ""
    var nrows = 0
    var j = i + 2

    while (
        j < lines.length()
        and not is_blank(lines[j])
        and not is_block_start(lines[j])
    ):
        cells := split_cells(lines[j])
        var r = "<tr>\n"
        k = 0

        while k < nc:
            var cell = ""
            if k < cells.length():
                cell = cells[k].clone()
            r = r + "<td" + align_attr(aligns[k]) + ">" + inline(cell) + "</td>\n"
            k += 1

        rows = rows + r + "</tr>\n"
        nrows += 1
        j += 1

    if nrows > 0:
        html = html + "<tbody>\n" + rows + "</tbody>\n"
    html = html + "</table>\n"
    return html_block(html, j)

fn parse_para(lines: List[String], i: Int) Block:
    var j = i + 1
    while j < lines.length() and not interrupts_para(lines[j]):
        j += 1

    var text = ""
    var k = i

    while k < j:
        l := lines[k]
        var s = ltrim_sp(l)

        if k == j - 1:
            s = rtrim_sp(s)
        else:
            trailing := l.length() - rtrim_sp(l).length()
            s = rtrim_sp(s)
            if trailing >= 2:
                s = s + "\r"
            s = s + "\n"

        text = text + s
        k += 1

    return Block(kind: 1, html: "", text: text, blank: false, nxt: j)

fn parse_list(lines: List[String], i: Int) Block:
    first := marker(lines[i])
    var items = List[Item]()
    var cur = i
    var nxt = i + 1
    var any_gap = false
    var go = true

    while go:
        m := marker(lines[cur])
        var content = List[String]()
        content.append(sub(lines[cur], m.w, lines[cur].length()))

        var k = cur + 1
        var end = cur + 1
        var pend = 0

        while k < lines.length():
            l := lines[k]

            if is_blank(l):
                pend += 1
            else if leading(l) >= m.w:
                var z = 0

                while z < pend:
                    content.append("")
                    z += 1

                pend = 0
                content.append(sub(l, m.w, l.length()))
                end = k + 1
            else:
                break

            k += 1

        kids := parse_blocks(content)
        var loose_item = false
        var q = 1

        while q < kids.length():
            if kids[q].blank:
                loose_item = true
            q += 1

        items.append(Item(kids: kids, loose: loose_item))

        var r = end
        while r < lines.length() and is_blank(lines[r]):
            r += 1

        var more = false

        if r < lines.length():
            nm := marker(lines[r])
            if (
                nm.ok
                and not is_hr(lines[r])
                and nm.ordered == first.ordered
                and nm.ch == first.ch
            ):
                more = true

        if more:
            if r > end:
                any_gap = true
            cur = r
        else:
            go = false
            nxt = end

    var loose = any_gap
    for it in items:
        if it.loose:
            loose = true

    var html = "<ul>\n"
    var close = "</ul>\n"

    if first.ordered:
        close = "</ol>\n"
        html = "<ol>\n"
        if first.num != 1:
            html = "<ol start=\"" + first.num.to_string() + "\">\n"

    for it in items:
        html = html + "<li>" + render_body(it.kids, not loose) + "</li>\n"
    return html_block(html + close, nxt)

// Body of a list item: see spec (tight paragraphs contribute inline only).
fn render_body(kids: List[Block], tight: Bool) String:
    var body = ""

    for k in kids:
        if k.kind == 1:
            if tight:
                body = body + inline(k.text)
            else:
                if not body.ends_with("\n"):
                    body = body + "\n"
                body = body + "<p>" + inline(k.text) + "</p>\n"
        else:
            if not body.ends_with("\n"):
                body = body + "\n"
            body = body + k.html

    return body

fn block_at(lines: List[String], i: Int) Block:
    line := lines[i]
    if leading(line) >= 4:
        return parse_indented(lines, i)
    if is_fence(line):
        return parse_fence(lines, i)
    if heading_level(line) > 0:
        return parse_heading(line, i)
    if is_hr(line):
        return html_block("<hr />\n", i + 1)
    if is_quote(line):
        return parse_quote(lines, i)
    if marker(line).ok:
        return parse_list(lines, i)
    if table_start(lines, i):
        return parse_table(lines, i)

    return parse_para(lines, i)

fn parse_blocks(lines: List[String]) List[Block]:
    var out = List[Block]()
    var i = 0
    var blank = false

    while i < lines.length():
        if is_blank(lines[i]):
            blank = true
            i += 1
        else:
            var b = block_at(lines, i)
            b.blank = blank
            blank = false
            i = b.nxt
            out.append(b)

    return out

fn render_top(blocks: List[Block]) String:
    var s = ""

    for b in blocks:
        if b.kind == 1:
            s = s + "<p>" + inline(b.text) + "</p>\n"
        else:
            s = s + b.html

    return s

// ---------------------------------------------------------------
// Inline processing
// ---------------------------------------------------------------

fn mk(kind: Int, text: String) Node:
    return Node(
        kind: kind, text: text, title: "", has_title: false, img: false, active: false,
        cnt: 0, orig: 0, can_open: false, can_close: false, strong: false,
        kids: List[Node]()
    )

// Link destination and title after "[text]"; p is the index of "(".
fn parse_tail(cs: List[String], p: Int) Tail:
    n := cs.length()
    failed := Tail(ok: false, dest: "", title: "", has_title: false, stop: 0)
    if cat(cs, p) != "(":
        return failed

    var k = p + 1
    while k < n and is_space_nl(cat(cs, k)):
        k += 1

    var dest = ""

    if cat(cs, k) == "<":
        k += 1

        while k < n and cat(cs, k) != ">":
            c := cat(cs, k)
            if c == "\n" or c == "\r" or c == "<":
                return failed

            if c == "\\" and is_punct(cat(cs, k + 1)):
                dest = dest + cat(cs, k + 1)
                k += 2
            else:
                dest = dest + c
                k += 1

        if k >= n:
            return failed

        k += 1
    else:
        var depth = 0

        while k < n:
            c := cat(cs, k)
            if is_space_nl(c):
                break

            if c == "\\" and is_punct(cat(cs, k + 1)):
                dest = dest + cat(cs, k + 1)
                k += 2
                continue

            if c == "(":
                depth += 1
            else if c == ")":
                if depth == 0:
                    break

                depth -= 1

            dest = dest + c
            k += 1

    var ws = 0

    while k < n and is_space_nl(cat(cs, k)):
        k += 1
        ws += 1

    var title = ""
    var has_title = false

    if ws > 0 and cat(cs, k) == "\"":
        k += 1

        while k < n and cat(cs, k) != "\"":
            if cat(cs, k) == "\\" and cat(cs, k + 1) == "\"":
                title = title + "\""
                k += 2
            else:
                title = title + cat(cs, k)
                k += 1

        if k >= n:
            return failed

        k += 1
        has_title = true
        while k < n and is_space_nl(cat(cs, k)):
            k += 1

    if cat(cs, k) != ")":
        return failed

    return Tail(ok: true, dest: dest, title: title, has_title: has_title, stop: k + 1)

// Contents of a code span from cs[a..b): line endings become spaces.
fn code_content(cs: List[String], a: Int, b: Int) String:
    var s = ""
    var k = a

    while k < b:
        c := cs[k]

        if c == "\r" and k + 1 < b and cs[k + 1] == "\n":
            s = s + " "
            k += 2
        else if c == "\n":
            s = s + " "
            k += 1
        else:
            s = s + c
            k += 1

    if (
        s.length() >= 2
        and s.get(0) == " "
        and s.get(s.length() - 1) == " "
        and trim_sp(s).length() > 0
    ):
        s = sub(s, 1, s.length() - 1)
    return s

// Scans the text into a flat node list (links already formed).
fn scan(text: String) List[Node]:
    cs := text.chars()
    n := cs.length()
    var nodes = List[Node]()
    var i = 0

    while i < n:
        c := cs[i]

        if c == "\\":
            d := cat(cs, i + 1)

            if d == "\n":
                nodes.append(mk(1, ""))
                i += 2
            else if is_punct(d):
                nodes.append(mk(0, d))
                i += 2
            else:
                nodes.append(mk(0, "\\"))
                i += 1
        else if c == "\r" and cat(cs, i + 1) == "\n":
            nodes.append(mk(1, ""))
            i += 2
        else if c == "`":
            var m = 0
            while i + m < n and cat(cs, i + m) == "`":
                m += 1

            var k = i + m
            var found = -1

            while k < n:
                if cat(cs, k) == "`":
                    var r = 0
                    while k + r < n and cat(cs, k + r) == "`":
                        r += 1

                    if r == m:
                        found = k
                        break

                    k += r
                else:
                    k += 1

            if found >= 0:
                nodes.append(mk(2, code_content(cs, i + m, found)))
                i = found + m
            else:
                nodes.append(mk(0, join_range(cs, i, i + m)))
                i += m
        else if c == "*" or c == "_":
            var r = 0
            while i + r < n and cat(cs, i + r) == c:
                r += 1

            before := cat(cs, i - 1)
            after_c := cat(cs, i + r)
            pw := is_ws(before)
            nw := is_ws(after_c)
            pp := is_punct(before)
            np := is_punct(after_c)
            left := (not nw) and ((not np) or pw or pp)
            right := (not pw) and ((not pp) or nw or np)
            var can_open = left
            var can_close = right

            if c == "_":
                can_open = left and ((not right) or pp)
                can_close = right and ((not left) or np)

            var d = mk(3, c.clone())
            d.cnt = r
            d.orig = r
            d.can_open = can_open
            d.can_close = can_close
            nodes.append(d)
            i += r
        else if c == "!" and cat(cs, i + 1) == "[":
            var b = mk(4, "![")
            b.img = true
            b.active = true
            nodes.append(b)
            i += 2
        else if c == "[":
            var b = mk(4, "[")
            b.active = true
            nodes.append(b)
            i += 1
        else if c == "]":
            var idx = -1
            var q = nodes.length() - 1

            while q >= 0:
                if nodes[q].kind == 4:
                    idx = q
                    break

                q -= 1

            if idx < 0:
                nodes.append(mk(0, "]"))
                i += 1
            else if not nodes[idx].img and not nodes[idx].active:
                nodes[idx] = mk(0, "[")
                nodes.append(mk(0, "]"))
                i += 1
            else:
                tl := parse_tail(cs, i + 1)

                if not tl.ok:
                    if nodes[idx].img:
                        nodes[idx] = mk(0, "![")
                    else:
                        nodes[idx] = mk(0, "[")

                    nodes.append(mk(0, "]"))
                    i += 1
                else:
                    was_img := nodes[idx].img
                    var kids = List[Node]()
                    while nodes.length() > idx + 1:
                        if x := nodes.pop():
                            kids.append(x)
                    kids.reverse()
                    nodes.pop()

                    if not was_img:
                        var z = 0

                        while z < nodes.length():
                            if nodes[z].kind == 4 and not nodes[z].img:
                                nodes[z].active = false
                            z += 1

                    var ln = mk(5, tl.dest)
                    ln.title = tl.title
                    ln.has_title = tl.has_title
                    ln.img = was_img
                    ln.kids = resolve(kids)
                    nodes.append(ln)
                    i = tl.stop
        else:
            add_text(var nodes, c)
            i += 1

    return nodes

// Appends literal text, merging into a directly preceding text node.
fn add_text(var nodes: List[Node], s: String) Unit:
    last := nodes.length() - 1

    if last >= 0 and nodes[last].kind == 0:
        nodes[last].text = nodes[last].text + s
    else:
        nodes.append(mk(0, s.clone()))

fn delim_to_text(x: Node) Node:
    if x.kind == 3:
        return mk(0, rep(x.text, x.cnt))

    return x.clone()

fn mult_ok(o: Node, c: Node) Bool:
    if not (o.can_close or c.can_open):
        return true

    s := o.orig + c.orig
    if s % 3 != 0:
        return true

    return o.orig % 3 == 0 and c.orig % 3 == 0

// Emphasis resolution over one node list; leftover delimiters become text.
fn resolve(input: List[Node]) List[Node]:
    var ns = List[Node]()
    for x in input:
        ns.append(x.clone())

    var i = 0

    while i < ns.length():
        if ns[i].kind == 3 and ns[i].can_close and ns[i].cnt > 0:
            var found = -1
            var j = i - 1

            while j >= 0:
                if (
                    ns[j].kind == 3
                    and ns[j].text == ns[i].text
                    and ns[j].can_open
                    and ns[j].cnt > 0
                    and mult_ok(ns[j], ns[i])
                ):
                    found = j
                    break

                j -= 1

            if found < 0:
                i += 1
            else:
                o := found
                var use = 1
                if ns[o].cnt >= 2 and ns[i].cnt >= 2:
                    use = 2

                var inner = List[Node]()
                between := i - o - 1
                var t = 0

                while t < between:
                    inner.append(delim_to_text(ns[o + 1].clone()))
                    ns.remove(o + 1)
                    t += 1

                ns[o].cnt = ns[o].cnt - use
                ns[o + 1].cnt = ns[o + 1].cnt - use

                var em = mk(6, "")
                em.strong = use == 2
                em.kids = inner
                ns.insert(o + 1, em)

                var next_i = o + 2
                if ns[o + 2].cnt == 0:
                    ns.remove(o + 2)

                if ns[o].cnt == 0:
                    ns.remove(o)
                    next_i -= 1

                i = next_i
        else:
            i += 1

    var z = 0

    while z < ns.length():
        x := ns[z].clone()

        if x.kind == 3:
            ns[z] = mk(0, rep(x.text, x.cnt))
        else if x.kind == 4:
            if x.img:
                ns[z] = mk(0, "![")
            else:
                ns[z] = mk(0, "[")

        z += 1

    return ns

fn plain(ns: List[Node]) String:
    var s = ""

    for x in ns:
        if x.kind == 0 or x.kind == 2:
            s = s + x.text.replace("\n", " ")
        else if x.kind == 1:
            s = s + " "
        else:
            s = s + plain(x.kids)

    return s

fn render_nodes(ns: List[Node]) String:
    var s = ""
    for x in ns:
        s = s + render_node(x)
    return s

fn render_node(x: Node) String:
    if x.kind == 0:
        return esc(x.text)
    if x.kind == 1:
        return "<br />\n"
    if x.kind == 2:
        return "<code>" + esc(x.text) + "</code>"

    if x.kind == 5:
        var t = ""
        if x.has_title:
            t = " title=\"" + esc(x.title) + "\""
        if x.img:
            return (
                "<img src=\""
                + esc(x.text)
                + "\" alt=\""
                + esc(plain(x.kids))
                + "\""
                + t
                + " />"
            )

        return (
            "<a href=\""
            + esc(x.text)
            + "\""
            + t
            + ">"
            + render_nodes(x.kids)
            + "</a>"
        )

    if x.kind == 6:
        if x.strong:
            return "<strong>" + render_nodes(x.kids) + "</strong>"

        return "<em>" + render_nodes(x.kids) + "</em>"

    return ""

fn inline(text: String) String:
    return render_nodes(resolve(scan(text)))

// ---------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------

export fn main() Int:
    data := read_all(stdin()).get()
    text := data.decode_utf8().get("")
    var lines = text.split("\n")
    if lines.length() > 0 and lines[lines.length() - 1] == "":
        lines.pop()
    stdout().write(render_top(parse_blocks(lines))).get()
    return 0

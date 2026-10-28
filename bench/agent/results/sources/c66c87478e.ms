import {read_lines} from "@std/streams.ms"
import stdin from "@std/io.ms"
import stdout from "@std/io.ms"

# Stands in for a hard break inside paragraph text. Input is ASCII, so it cannot clash with source text.
let HARD = "\u{E000}"
let DIGITS = "0123456789"
let PUNCT = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`\{|\}~"

# kind: 0 ready HTML in text, 1 paragraph (text is the paragraph text), 2 list, 3 list item.
# next_line is the index of the first line after the block.
type Block:
    kind: Int = 0
    text: String = ""
    children: List[Block]
    ordered: Bool = false
    start: Int = 1
    loose: Bool = false
    next_line: Int = 0
    blank_before: Bool = false

type Fence:
    ok: Bool = false
    ch: String = ""
    len: Int = 0
    indent: Int = 0
    info: String = ""

type Atx:
    level: Int = 0
    text: String = ""

type Marker:
    ok: Bool = false
    ordered: Bool = false
    ch: String = ""
    num: Int = 0
    width: Int = 0
    blank_item: Bool = true

# kind: 0 text, 1 code, 2 hard break, 3 soft break, 4 delimiter run, 5 bracket opener,
# 6 link, 7 image, 8 emphasis, 9 strong.
type Node:
    kind: Int = 0
    text: String = ""
    title: String = ""
    has_title: Bool = false
    ch: String = ""
    count: Int = 0
    orig: Int = 0
    can_open: Bool = false
    can_close: Bool = false
    active: Bool = true
    image: Bool = false
    children: List[Node]

type Tail:
    ok: Bool = false
    dest: String = ""
    title: String = ""
    has_title: Bool = false
    end: Int = 0

# ---- string helpers ----

fn sub2(s: String, a: Int, b: Int) String:
    var stop = b
    if stop > s.length():
        stop = s.length()
    if a >= stop:
        return ""

    return s.slice_scalars(a, stop).get()

fn sub(s: String, a: Int) String:
    return sub2(s, a, s.length())

fn indent_of(s: String) Int:
    var n = 0
    while n < s.length() and s.get(n) == " ":
        n += 1
    return n

fn is_blank(s: String) Bool:
    return indent_of(s) == s.length()

fn ltrim(s: String) String:
    return sub(s, indent_of(s))

fn rtrim(s: String) String:
    var b = s.length()
    while b > 0 and s.get(b - 1) == " ":
        b -= 1
    return sub2(s, 0, b)

fn trim_sp(s: String) String:
    return rtrim(ltrim(s))

fn strip_up_to(s: String, k: Int) String:
    var n = indent_of(s)
    if n > k:
        n = k
    return sub(s, n)

fn repeat_str(s: String, count: Int) String:
    var out = ""
    for t in 0..count:
        out += s
    return out

fn digit_value(c: String) Int:
    for k in 0..10:
        if DIGITS.get(k) == c:
            return k
    return -1

fn esc(s: String) String:
    var out = ""

    for c in s.chars():
        if c == "&":
            out += "&amp;"
        else if c == "<":
            out += "&lt;"
        else if c == ">":
            out += "&gt;"
        else if c == "\"":
            out += "&quot;"
        else:
            out += c

    return out

fn html_block(html: String, next_line: Int) Block:
    return Block(text: html, children: List[Block](), next_line: next_line)

# ---- block recognizers ----

fn fence_of(s: String) Fence:
    let ind = indent_of(s)
    if ind > 3 or ind == s.length():
        return Fence()

    let t = sub(s, ind)
    let c = t.get(0)
    if c != "`" and c != "~":
        return Fence()

    var n = 0
    while n < t.length() and t.get(n) == c:
        n += 1
    if n < 3:
        return Fence()

    let info = trim_sp(sub(t, n))
    if c == "`" and info.contains("`"):
        return Fence()

    return Fence(ok: true, ch: c, len: n, indent: ind, info: info)

fn closes_fence(s: String, f: Fence) Bool:
    let ind = indent_of(s)
    if ind > 3:
        return false

    let t = sub(s, ind)
    var n = 0
    while n < t.length() and t.get(n) == f.ch:
        n += 1
    return n >= f.len and is_blank(sub(t, n))

fn atx_of(s: String) Atx:
    let ind = indent_of(s)
    if ind > 3:
        return Atx()

    let t = sub(s, ind)
    var k = 0
    while k < t.length() and t.get(k) == "#":
        k += 1
    if k < 1 or k > 6:
        return Atx()
    if k < t.length() and t.get(k) != " ":
        return Atx()

    var content = trim_sp(sub(t, k))
    var r = content.length()
    while r > 0 and content.get(r - 1) == "#":
        r -= 1
    if r < content.length() and (r == 0 or content.get(r - 1) == " "):
        content = trim_sp(sub2(content, 0, r))
    return Atx(level: k, text: content)

fn is_hr(s: String) Bool:
    if indent_of(s) > 3:
        return false

    var mark = ""
    var n = 0

    for k in 0..s.length():
        let c = s.get(k)
        if c == " ":
            continue
        if c != "-" and c != "*" and c != "_":
            return false

        if mark == "":
            mark = c
        else if c != mark:
            return false

        n += 1

    return n >= 3

fn is_quote(s: String) Bool:
    let ind = indent_of(s)
    return ind <= 3 and ind < s.length() and s.get(ind) == ">"

fn marker_of(s: String) Marker:
    let ind = indent_of(s)
    if ind > 3 or ind == s.length():
        return Marker()

    let t = sub(s, ind)
    var m = 0
    var ordered = false
    var ch = t.get(0)
    var num = 0

    if ch == "-" or ch == "*" or ch == "+":
        m = 1
    else:
        var d = 0

        while d < t.length() and d < 9 and digit_value(t.get(d)) >= 0:
            num = num * 10 + digit_value(t.get(d))
            d += 1

        if d == 0 or d >= t.length():
            return Marker()

        ch = t.get(d)
        if ch != "." and ch != ")":
            return Marker()

        ordered = true
        m = d + 1

    if m < t.length() and t.get(m) != " ":
        return Marker()

    var sp = 0
    while m + sp < t.length() and t.get(m + sp) == " ":
        sp += 1

    let column = ind + m
    if m + sp == t.length():
        return Marker(
            ok: true, ordered: ordered, ch: ch, num: num, width: column + 1,
            blank_item: true
        )
    if sp >= 5:
        return Marker(
            ok: true, ordered: ordered, ch: ch, num: num, width: column + 1,
            blank_item: false
        )

    return Marker(
        ok: true, ordered: ordered, ch: ch, num: num, width: column + sp,
        blank_item: false
    )

fn same_list(s: String, first: Marker) Bool:
    let m = marker_of(s)
    return m.ok and not is_hr(s) and m.ordered == first.ordered and m.ch == first.ch

fn interrupts_paragraph(s: String) Bool:
    let m = marker_of(s)
    return m.ok and not m.blank_item and (not m.ordered or m.num == 1)

fn opens_block(s: String) Bool:
    return fence_of(s).ok or atx_of(s).level > 0 or is_hr(s) or is_quote(s)

fn split_cells(line: String) List[String]:
    var t = trim_sp(line)
    if t.starts_with("|"):
        t = sub(t, 1)
    if t.ends_with("|") and not (t.length() >= 2 and t.get(t.length() - 2) == "\\"):
        t = sub2(t, 0, t.length() - 1)

    var cells = List[String]()
    var cur = ""

    for k in 0..t.length():
        let c = t.get(k)

        if c == "|" and not (k > 0 and t.get(k - 1) == "\\"):
            cells.append(trim_sp(cur))
            cur = ""
        else:
            cur += c

    cells.append(trim_sp(cur))
    return cells

fn is_delim_cell(c: String) Bool:
    var a = 0
    var b = c.length()
    if b > 0 and c.get(0) == ":":
        a = 1
    if b > a and c.get(b - 1) == ":":
        b -= 1
    if b <= a:
        return false

    for k in a..b:
        if c.get(k) != "-":
            return false
    return true

fn is_delim_row(s: String) Bool:
    if not s.contains("|"):
        return false

    for cell in split_cells(s):
        if not is_delim_cell(cell):
            return false
    return true

fn align_of(cell: String) String:
    let left = cell.starts_with(":")
    let right = cell.ends_with(":")
    if left and right:
        return "center"
    if left:
        return "left"
    if right:
        return "right"

    return ""

# ---- block parsing ----

fn parse_blocks(lines: List[String]) List[Block]:
    var out = List[Block]()
    var i = 0
    var blank = false

    while i < lines.length():
        if is_blank(lines[i]):
            blank = true
            i += 1
        else:
            var b = parse_block(lines, i)
            b.blank_before = blank
            blank = false
            i = b.next_line
            out.append(b)

    return out

fn parse_block(lines: List[String], i: Int) Block:
    let s = lines[i]
    let ind = indent_of(s)
    let f = fence_of(s)
    if f.ok:
        return parse_fence(lines, i, f)

    let h = atx_of(s)
    if h.level > 0:
        return html_block("<h{h.level}>" + inline(h.text) + "</h{h.level}>\n", i + 1)
    if is_hr(s):
        return html_block("<hr />\n", i + 1)
    if is_quote(s):
        return parse_quote(lines, i)
    if marker_of(s).ok:
        return parse_list(lines, i)
    if ind >= 4:
        return parse_indented(lines, i)

    if s.contains("|") and i + 1 < lines.length() and is_delim_row(lines[i + 1]):
        if split_cells(s).length() == split_cells(lines[i + 1]).length():
            return parse_table(lines, i)
    return parse_para(lines, i)

fn parse_fence(lines: List[String], i: Int, f: Fence) Block:
    var html = "<pre><code>"

    if f.info.length() > 0:
        let words = f.info.split(" ")
        html = "<pre><code class=\"language-" + esc(words[0]) + "\">"

    var j = i + 1

    while j < lines.length() and not closes_fence(lines[j], f):
        html += esc(strip_up_to(lines[j], f.indent)) + "\n"
        j += 1

    let closed = j < lines.length()
    html += "</code></pre>\n"
    if closed:
        j += 1
    return html_block(html, j)

fn parse_quote(lines: List[String], i: Int) Block:
    var inner = List[String]()
    var j = i

    while j < lines.length() and is_quote(lines[j]):
        let s = lines[j]
        var rest = sub(s, indent_of(s) + 1)
        if rest.starts_with(" "):
            rest = sub(rest, 1)
        inner.append(rest)
        j += 1

    return html_block(
        "<blockquote>\n" + render_blocks(
            parse_blocks(inner)
        ) + "</blockquote>\n",
        j
    )

fn parse_indented(lines: List[String], i: Int) Block:
    var j = i
    var last = i

    while j < lines.length() and (is_blank(lines[j]) or indent_of(lines[j]) >= 4):
        if not is_blank(lines[j]):
            last = j + 1
        j += 1

    var html = "<pre><code>"
    for k in i..last:
        html += esc(strip_up_to(lines[k], 4)) + "\n"
    html += "</code></pre>\n"
    return html_block(html, last)

fn cell_html(tag: String, text: String, align: String) String:
    var open = "<" + tag + ">"
    if align.length() > 0:
        open = "<" + tag + " align=\"" + align + "\">"
    return open + inline(text) + "</" + tag + ">\n"

fn parse_table(lines: List[String], i: Int) Block:
    let head = split_cells(lines[i])
    let delim = split_cells(lines[i + 1])
    var html = "<table>\n<thead>\n<tr>\n"
    for k in 0..head.length():
        html += cell_html("th", head[k], align_of(delim[k]))
    html += "</tr>\n</thead>\n"

    var body = ""
    var j = i + 2

    while j < lines.length() and not is_blank(lines[j]) and not opens_block(lines[j]):
        let cells = split_cells(lines[j])
        body += "<tr>\n"

        for k in 0..head.length():
            var cell = ""
            if k < cells.length():
                cell = cells[k].clone()
            body += cell_html("td", cell, align_of(delim[k]))

        body += "</tr>\n"
        j += 1

    if body.length() > 0:
        html += "<tbody>\n" + body + "</tbody>\n"
    html += "</table>\n"
    return html_block(html, j)

fn parse_para(lines: List[String], i: Int) Block:
    var j = i + 1
    while (
        j < lines.length()
        and not is_blank(lines[j])
        and not opens_block(lines[j])
        and not interrupts_paragraph(lines[j])
    ):
        j += 1

    var text = ""

    for k in i..j:
        let raw = ltrim(lines[k])
        text += rtrim(raw)

        if k < j - 1:
            if raw.ends_with("  "):
                text += HARD
            else:
                text += "\n"

    return Block(kind: 1, text: text, children: List[Block](), next_line: j)

fn parse_list(lines: List[String], i: Int) Block:
    let first = marker_of(lines[i])
    var items = List[Block]()
    var loose = false
    var k = i
    var next = i + 1
    var going = true

    while going:
        let m = marker_of(lines[k])
        var item = List[String]()
        if not m.blank_item:
            item.append(sub(lines[k], m.width))

        var q = k + 1
        var pending = 0
        next = k + 1

        while q < lines.length():
            let s = lines[q]

            if is_blank(s):
                pending += 1
                q += 1
            else if indent_of(s) >= m.width:
                for t in 0..pending:
                    item.append("")
                pending = 0
                item.append(sub(s, m.width))
                q += 1
                next = q
            else:
                break

        let children = parse_blocks(item)
        var item_loose = false
        for t in 1..children.length():
            if children[t].blank_before:
                item_loose = true
        if item_loose:
            loose = true
        items.append(Block(kind: 3, children: children, next_line: next))

        var r = next
        while r < lines.length() and is_blank(lines[r]):
            r += 1

        if r < lines.length() and same_list(lines[r], first):
            if r > next:
                loose = true
            k = r
        else:
            going = false

    return Block(
        kind: 2, children: items, ordered: first.ordered, start: first.num,
        loose: loose, next_line: next
    )

# ---- block rendering ----

fn render_blocks(blocks: List[Block]) String:
    var html = ""
    for b in blocks:
        html += render_block(b)
    return html

fn render_block(b: Block) String:
    if b.kind == 1:
        return "<p>" + inline(b.text) + "</p>\n"
    if b.kind == 2:
        return render_list(b)

    return b.text.clone()

fn render_list(b: Block) String:
    var html = "<ul>\n"

    if b.ordered:
        html = "<ol>\n"
        if b.start != 1:
            html = "<ol start=\"{b.start}\">\n"

    for item in b.children:
        html += "<li>" + render_body(item.children, not b.loose) + "</li>\n"

    if b.ordered:
        html += "</ol>\n"
    else:
        html += "</ul>\n"

    return html

fn render_body(children: List[Block], tight: Bool) String:
    var body = ""

    for c in children:
        if c.kind == 1 and tight:
            body += inline(c.text)
        else:
            if body.length() == 0 or not body.ends_with("\n"):
                body += "\n"
            body += render_block(c)

    return body

# ---- inline scanning ----

fn is_ws(c: String) Bool:
    return c == " " or c == "\n" or c == HARD

fn is_punct(c: String) Bool:
    return PUNCT.contains(c)

fn node(kind: Int, text: String) Node:
    return Node(kind: kind, text: text, children: List[Node]())

fn literal(n: Node) String:
    if n.kind == 5:
        return n.ch.clone()

    return repeat_str(n.ch, n.count)

fn delim_node(c: String, run: Int, before: String, after: String) Node:
    let left = (
        not is_ws(after)
        and (not is_punct(after) or is_ws(before) or is_punct(before))
    )
    let right = (
        not is_ws(before)
        and (not is_punct(before) or is_ws(after) or is_punct(after))
    )
    var can_open = left
    var can_close = right

    if c == "_":
        can_open = left and (not right or is_punct(before))
        can_close = right and (not left or is_punct(after))

    return Node(
        kind: 4, ch: c, count: run, orig: run, can_open: can_open, can_close: can_close,
        children: List[Node]()
    )

fn find_run(cs: List[String], from: Int, k: Int) Int:
    var p = from

    while p < cs.length():
        if cs[p] == "`":
            var q = p
            while q < cs.length() and cs[q] == "`":
                q += 1
            if q - p == k:
                return p

            p = q
        else:
            p += 1

    return -1

fn parse_tail(cs: List[String], p: Int) Tail:
    let n = cs.length()
    if p >= n or cs[p] != "(":
        return Tail()

    var q = p + 1
    while q < n and is_ws(cs[q]):
        q += 1

    var dest = ""

    if q < n and cs[q] == "<":
        var r = q + 1

        while r < n:
            let c = cs[r]
            if c == ">":
                break
            if c == "<" or c == "\n" or c == HARD:
                return Tail()

            if c == "\\" and r + 1 < n and is_punct(cs[r + 1]):
                dest += cs[r + 1]
                r += 2
            else:
                dest += c
                r += 1

        if r >= n:
            return Tail()

        q = r + 1
    else:
        var depth = 0
        var r = q

        while r < n:
            let c = cs[r]

            if c == "\\" and r + 1 < n and is_punct(cs[r + 1]):
                dest += cs[r + 1]
                r += 2
                continue

            if is_ws(c):
                break

            if c == "(":
                depth += 1
            else if c == ")":
                if depth == 0:
                    break

                depth -= 1

            dest += c
            r += 1

        if depth != 0:
            return Tail()

        q = r

    var title = ""
    var has_title = false
    var w = q
    while w < n and is_ws(cs[w]):
        w += 1

    if w > q and w < n and cs[w] == "\"":
        var r = w + 1
        var t = ""

        while r < n and cs[r] != "\"":
            if cs[r] == "\\" and r + 1 < n and cs[r + 1] == "\"":
                t += "\""
                r += 2
            else:
                t += cs[r]
                r += 1

        if r < n:
            title = t
            has_title = true
            q = r + 1

    while q < n and is_ws(cs[q]):
        q += 1
    if q < n and cs[q] == ")":
        return Tail(
            ok: true, dest: dest, title: title, has_title: has_title, end: q + 1
        )

    return Tail()

fn scan(text: String) List[Node]:
    let cs = text.chars()
    let n = cs.length()
    var nodes = List[Node]()
    var i = 0

    while i < n:
        let c = cs[i]

        if c == "\\" and i + 1 < n and cs[i + 1] == "\n":
            nodes.append(node(2, ""))
            i += 2
        else if c == "\\" and i + 1 < n and is_punct(cs[i + 1]):
            nodes.append(node(0, cs[i + 1].clone()))
            i += 2
        else if c == "\\":
            nodes.append(node(0, "\\"))
            i += 1
        else if c == HARD:
            nodes.append(node(2, ""))
            i += 1
        else if c == "\n":
            nodes.append(node(3, ""))
            i += 1
        else if c == "`":
            var run = 0
            while i + run < n and cs[i + run] == "`":
                run += 1

            let close = find_run(cs, i + run, run)

            if close < 0:
                nodes.append(node(0, repeat_str("`", run)))
                i += run
            else:
                var content = ""
                let from = i + run

                for t in from..close:
                    let x = cs[t]

                    if x == "\n" or x == HARD:
                        content += " "
                    else:
                        content += x

                if (
                    content.starts_with(" ")
                    and content.ends_with(" ")
                    and trim_sp(content).length() > 0
                ):
                    content = sub2(content, 1, content.length() - 1)
                nodes.append(node(1, content))
                i = close + run
        else if c == "*" or c == "_":
            var run = 0
            while i + run < n and cs[i + run] == c:
                run += 1

            var before = " "
            if i > 0:
                before = cs[i - 1].clone()

            var after = " "
            if i + run < n:
                after = cs[i + run].clone()
            nodes.append(delim_node(c.clone(), run, before, after))
            i += run
        else if c == "!" and i + 1 < n and cs[i + 1] == "[":
            nodes.append(Node(kind: 5, ch: "![", image: true, children: List[Node]()))
            i += 2
        else if c == "[":
            nodes.append(Node(kind: 5, ch: "[", children: List[Node]()))
            i += 1
        else if c == "]":
            var oi = nodes.length() - 1
            while oi >= 0 and nodes[oi].kind != 5:
                oi -= 1

            if oi < 0:
                nodes.append(node(0, "]"))
                i += 1
            else if not nodes[oi].image and not nodes[oi].active:
                nodes[oi].kind = 0
                nodes[oi].text = "["
                nodes.append(node(0, "]"))
                i += 1
            else:
                let tail = parse_tail(cs, i + 1)

                if not tail.ok:
                    nodes[oi].kind = 0
                    nodes[oi].text = nodes[oi].ch.clone()
                    nodes.append(node(0, "]"))
                    i += 1
                else:
                    let is_image = nodes[oi].image
                    var kids = List[Node]()
                    while nodes.length() > oi + 1:
                        if let moved = nodes.pop():
                            kids.insert(0, moved)

                    let _opener = nodes.pop()
                    if not is_image:
                        for k in 0..nodes.length():
                            if nodes[k].kind == 5 and not nodes[k].image:
                                nodes[k].active = false

                    var kind = 6
                    if is_image:
                        kind = 7
                    nodes.append(
                        Node(
                            kind: kind, text: tail.dest.clone(),
                            title: tail.title.clone(), has_title: tail.has_title,
                            children: resolve_emphasis(kids)
                        )
                    )
                    i = tail.end
        else:
            nodes.append(node(0, c.clone()))
            i += 1

    return resolve_emphasis(nodes)

# ---- emphasis ----

fn is_closer(x: Node) Bool:
    return x.kind == 4 and x.can_close and x.count > 0

fn pair_ok(o: Node, c: Node) Bool:
    if (o.can_close or c.can_open) and (o.orig + c.orig) % 3 == 0:
        return o.orig % 3 == 0 and c.orig % 3 == 0

    return true

fn find_opener(cur: List[Node], ci: Int) Int:
    var k = ci - 1

    while k >= 0:
        let o = cur[k]
        if (
            o.kind == 4
            and o.can_open
            and o.count > 0
            and o.ch == cur[ci].ch
            and pair_ok(o, cur[ci])
        ):
            return k

        k -= 1

    return -1

fn literal_if_delim(x: Node) Node:
    if x.kind == 4:
        return node(0, literal(x).clone())

    return x.clone()

fn wrap_emphasis(cur: List[Node], oi: Int, ci: Int, use: Int) List[Node]:
    var out = List[Node]()
    for k in 0..oi:
        out.append(cur[k].clone())

    if cur[oi].count - use > 0:
        var op = cur[oi].clone()
        op.count -= use
        out.append(op)

    var kids = List[Node]()
    let from = oi + 1
    for k in from..ci:
        kids.append(literal_if_delim(cur[k]))

    var kind = 8
    if use == 2:
        kind = 9
    out.append(Node(kind: kind, children: kids))

    if cur[ci].count - use > 0:
        var cl = cur[ci].clone()
        cl.count -= use
        out.append(cl)

    for k in ci + 1..cur.length():
        out.append(cur[k].clone())
    return out

fn resolve_emphasis(nodes: List[Node]) List[Node]:
    var cur = nodes
    var ci = 0

    while ci < cur.length():
        if not is_closer(cur[ci]):
            ci += 1
        else:
            var removed = false
            var oi = find_opener(cur, ci)

            while oi >= 0:
                var use = 1
                if cur[oi].count >= 2 and cur[ci].count >= 2:
                    use = 2

                let opener_left = cur[oi].count - use > 0
                let closer_left = cur[ci].count - use > 0
                cur = wrap_emphasis(cur, oi, ci, use)
                ci = oi + 1
                if opener_left:
                    ci += 1

                if not closer_left:
                    removed = true
                    break

                oi = find_opener(cur, ci)

            if not removed:
                ci += 1

    return cur

# ---- inline rendering ----

fn title_attr(n: Node) String:
    if n.has_title:
        return " title=\"" + esc(n.title) + "\""

    return ""

fn plain(nodes: List[Node]) String:
    var s = ""

    for n in nodes:
        if n.kind == 0 or n.kind == 1:
            s += n.text
        else if n.kind == 2 or n.kind == 3:
            s += " "
        else if n.kind == 4 or n.kind == 5:
            s += literal(n)
        else:
            s += plain(n.children)

    return s

fn render_nodes(nodes: List[Node]) String:
    var html = ""
    for n in nodes:
        html += render_node(n)
    return html

fn render_node(n: Node) String:
    if n.kind == 0:
        return esc(n.text)
    if n.kind == 1:
        return "<code>" + esc(n.text) + "</code>"
    if n.kind == 2:
        return "<br />\n"
    if n.kind == 3:
        return "\n"
    if n.kind == 4 or n.kind == 5:
        return esc(literal(n))
    if n.kind == 6:
        return (
            "<a href=\""
            + esc(n.text)
            + "\""
            + title_attr(n)
            + ">"
            + render_nodes(n.children)
            + "</a>"
        )
    if n.kind == 7:
        return (
            "<img src=\""
            + esc(n.text)
            + "\" alt=\""
            + esc(plain(n.children))
            + "\""
            + title_attr(n)
            + " />"
        )
    if n.kind == 8:
        return "<em>" + render_nodes(n.children) + "</em>"

    return "<strong>" + render_nodes(n.children) + "</strong>"

fn inline(text: String) String:
    return render_nodes(scan(text))

export fn main() Int:
    let lines = read_lines(stdin()).get()
    stdout().write(render_blocks(parse_blocks(lines))).get()
    return 0

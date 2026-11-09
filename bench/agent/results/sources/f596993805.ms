import stdin, stdout from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

// ---------------------------------------------------------------------------
// Records
// ---------------------------------------------------------------------------

// Inline node. kind: "t" text, "d" delimiter run, "c" code, "s" soft break,
// "h" hard break, "m" bracket marker, "e" emphasis, "l" link, "i" image.
type Node:
    kind: String = "t"
    text: String = ""
    title: String = ""
    has_title: Bool = false
    ch: String = ""
    count: Int = 0
    orig: Int = 0
    can_open: Bool = false
    can_close: Bool = false
    level: Int = 0
    active: Bool = false
    kids: List[Node] = List[Node]()

// Block. kind: "p" paragraph, "o" other. html is the full rendering, inner the
// inline HTML of a paragraph, gap is true when blank lines precede the block
// (within its container), next is the index of the following line.
type Block:
    kind: String = "o"
    html: String = ""
    inner: String = ""
    gap: Bool = false
    next: Int = 0

type Fence:
    ch: String
    len: Int
    indent: Int
    info: String

type Heading:
    level: Int
    text: String

type Marker:
    ordered: Bool
    ch: String
    num: Int
    indent: Int
    mend: Int
    blank_item: Bool
    w: Int

type Tail:
    dest: String
    title: String
    has_title: Bool
    stop: Int

// ---------------------------------------------------------------------------
// Small string helpers
// ---------------------------------------------------------------------------

// Hard-break sentinel used inside paragraph text (cannot occur in ASCII input).
fn hard() String:
    return ""

// Scalar at index i, or "" when out of range.
fn chr_at(s: String, i: Int) String:
    if i < 0 or i >= s.length():
        return ""

    return s.get(i)

// Substring [a, b) with the bounds clamped.
fn sub(s: String, a: Int, b: Int) String:
    var lo = a
    var hi = b
    if hi > s.length():
        hi = s.length()
    if lo < 0:
        lo = 0
    if lo > hi:
        lo = hi
    return s.slice_scalars(lo, hi).get("")

fn rest(s: String, a: Int) String:
    return sub(s, a, s.length())

fn esc(s: String) String:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
        "\"", "&quot;"
    )

fn repeat_str(s: String, n: Int) String:
    var out = ""
    var k = 0

    while k < n:
        out = out + s
        k += 1

    return out

fn is_punct(c: String) Bool:
    if c.length() != 1:
        return false

    return "!\"#$%&'()*+,-./:;<=>?@[\\]^_`\{|\}~".contains(c)

fn is_digit(c: String) Bool:
    if c.length() != 1:
        return false

    return "0123456789".contains(c)

fn indent_of(s: String) Int:
    var k = 0
    while chr_at(s, k) == " ":
        k += 1
    return k

fn is_blank(s: String) Bool:
    return indent_of(s) == s.length()

fn lstrip_sp(s: String) String:
    return rest(s, indent_of(s))

fn rstrip_sp(s: String) String:
    var k = s.length()
    while k > 0 and chr_at(s, k - 1) == " ":
        k -= 1
    return sub(s, 0, k)

// ---------------------------------------------------------------------------
// Line classifiers (rules 1-4 on a single line)
// ---------------------------------------------------------------------------

fn fence_open(line: String) Fence?:
    let ind = indent_of(line)
    if ind > 3:
        return none

    let c = chr_at(line, ind)
    if c != "`" and c != "~":
        return none

    var n = 0
    while chr_at(line, ind + n) == c:
        n += 1
    if n < 3:
        return none

    let info = rest(line, ind + n).trim()
    if c == "`" and info.contains("`"):
        return none

    return Fence(ch: c, len: n, indent: ind, info: info)

fn is_fence(line: String) Bool:
    return not fence_open(line).is_none()

fn fence_close(line: String, f: Fence) Bool:
    let ind = indent_of(line)
    if ind > 3:
        return false

    var n = 0
    while chr_at(line, ind + n) == f.ch:
        n += 1
    if n < f.len:
        return false

    return is_blank(rest(line, ind + n))

fn atx_parse(line: String) Heading?:
    let ind = indent_of(line)
    if ind > 3:
        return none

    var n = 0
    while chr_at(line, ind + n) == "#":
        n += 1
    if n < 1 or n > 6:
        return none

    let after = ind + n
    if after < line.length() and chr_at(line, after) != " ":
        return none

    var content = rest(line, after).trim()
    var k = content.length()
    while k > 0 and chr_at(content, k - 1) == "#":
        k -= 1
    if k < content.length():
        if k == 0 or chr_at(content, k - 1) == " ":
            content = sub(content, 0, k).trim()
    return Heading(level: n, text: content)

fn is_thematic(line: String) Bool:
    if indent_of(line) > 3:
        return false

    let s = line.replace(" ", "")
    if s.length() < 3:
        return false

    let c = chr_at(s, 0)
    if c != "-" and c != "*" and c != "_":
        return false

    var k = 0

    while k < s.length():
        if chr_at(s, k) != c:
            return false

        k += 1

    return true

fn is_quote(line: String) Bool:
    let ind = indent_of(line)
    return ind <= 3 and chr_at(line, ind) == ">"

// A list marker line (rule 5 test). Thematic breaks are tested by the caller.
fn list_marker(line: String) Marker?:
    let ind = indent_of(line)
    if ind > 3:
        return none

    let c = chr_at(line, ind)
    var ordered = false
    var mlen = 0
    var num = 0
    var delim = ""

    if c == "-" or c == "*" or c == "+":
        mlen = 1
        delim = c
    else:
        var d = 0
        while is_digit(chr_at(line, ind + d)):
            d += 1
        if d < 1 or d > 9:
            return none

        let dc = chr_at(line, ind + d)
        if dc != "." and dc != ")":
            return none

        var k = 0

        while k < d:
            num = num * 10 + "0123456789".index_of(chr_at(line, ind + k)).get(0)
            k += 1

        ordered = true
        mlen = d + 1
        delim = dc

    let mend = ind + mlen
    if mend < line.length() and chr_at(line, mend) != " ":
        return none

    var sp = 0
    while chr_at(line, mend + sp) == " ":
        sp += 1

    let blank_item = mend + sp >= line.length()
    var w = mend + sp
    if blank_item or sp >= 5:
        w = mend + 1
    return Marker(
        ordered: ordered, ch: delim, num: num, indent: ind, mend: mend,
        blank_item: blank_item, w: w
    )

// Table cells of a line (see the Tables section).
fn split_cells(line: String) List[String]:
    var t = line.trim()
    if chr_at(t, 0) == "|":
        t = rest(t, 1)

    let tl = t.length()
    if (
        tl > 0
        and chr_at(t, tl - 1) == "|"
        and not (tl >= 2 and chr_at(t, tl - 2) == "\\")
    ):
        t = sub(t, 0, tl - 1)

    var cells = List[String]()
    var cur = ""
    var prev = ""
    var k = 0

    while k < t.length():
        let c = chr_at(t, k)

        if c == "|" and prev != "\\":
            cells.append(cur.trim())
            cur = ""
        else:
            cur = cur + c

        prev = c
        k += 1

    cells.append(cur.trim())
    return cells

fn is_delim_cell(c: String) Bool:
    var k = 0
    if chr_at(c, 0) == ":":
        k = 1

    var dashes = 0

    while chr_at(c, k) == "-":
        k += 1
        dashes += 1

    if dashes == 0:
        return false

    if chr_at(c, k) == ":":
        k += 1
    return k == c.length()

fn is_delim_row(line: String) Bool:
    if not line.contains("|"):
        return false

    let cells = split_cells(line)
    if cells.length() == 0:
        return false

    for c in cells:
        if not is_delim_cell(c):
            return false
    return true

fn align_of(d: String) String:
    let l = chr_at(d, 0) == ":"
    let r = chr_at(d, d.length() - 1) == ":"
    if l and r:
        return "center"
    if l:
        return "left"
    if r:
        return "right"

    return ""

// A line that may continue a table body: not blank and not a block starter.
fn table_row_ok(line: String) Bool:
    if is_blank(line):
        return false
    if is_fence(line):
        return false
    if not atx_parse(line).is_none():
        return false
    if is_thematic(line):
        return false

    return not is_quote(line)

// Returns the marker when line is a same-kind list item marker after a list item.
fn same_kind(lines: List[String], q: Int, base: Marker) Marker?:
    if q >= lines.length():
        return none

    let line = lines[q]
    if is_thematic(line):
        return none

    if let mk = list_marker(line):
        if mk.ordered == base.ordered and mk.ch == base.ch:
            return mk
    return none

// Whether a line may continue a paragraph.
fn para_continues(line: String) Bool:
    if is_blank(line):
        return false
    if is_fence(line):
        return false
    if not atx_parse(line).is_none():
        return false
    if is_thematic(line):
        return false
    if is_quote(line):
        return false

    if let mk = list_marker(line):
        if not mk.blank_item and (not mk.ordered or mk.num == 1):
            return false
    return true

// ---------------------------------------------------------------------------
// Block structure
// ---------------------------------------------------------------------------

fn html_of(blocks: List[Block]) String:
    var out = ""
    for b in blocks:
        out = out + b.html
    return out

// Body of a list item, given its child blocks and the list's tightness.
fn item_body(kids: List[Block], tight: Bool) String:
    var body = ""

    for b in kids:
        if tight and b.kind == "p":
            body = body + b.inner
        else:
            if body.length() == 0 or not body.ends_with("\n"):
                body = body + "\n"
            body = body + b.html

    return body

fn fenced(lines: List[String], i: Int, f: Fence) Block:
    var code = ""
    var j = i + 1
    var closed = false

    while j < lines.length() and not closed:
        if fence_close(lines[j], f):
            closed = true
        else:
            let content = lines[j]
            var k = 0
            while k < f.indent and chr_at(content, k) == " ":
                k += 1
            code = code + esc(rest(content, k)) + "\n"

        j += 1

    var lang = ""
    if f.info.length() > 0:
        lang = f.info.split(" ")[0]

    var html = "<pre><code>"
    if lang.length() > 0:
        html = "<pre><code class=\"language-" + esc(lang) + "\">"
    return Block(kind: "o", html: html + code + "</code></pre>\n", next: j)

fn quote(lines: List[String], i: Int) Block:
    var inner = List[String]()
    var j = i

    while j < lines.length() and is_quote(lines[j]):
        let l = lines[j]
        var k = indent_of(l) + 1
        if chr_at(l, k) == " ":
            k += 1
        inner.append(rest(l, k))
        j += 1

    let kids = parse_blocks(inner)
    return Block(
        kind: "o", html: "<blockquote>\n" + html_of(kids) + "</blockquote>\n", next: j
    )

fn indented(lines: List[String], i: Int) Block:
    var j = i
    var last = i

    while j < lines.length() and (is_blank(lines[j]) or indent_of(lines[j]) >= 4):
        if not is_blank(lines[j]):
            last = j
        j += 1

    var code = ""
    var k = i

    while k <= last:
        let l = lines[k]
        var m = indent_of(l)
        if m > 4:
            m = 4
        code = code + esc(rest(l, m)) + "\n"
        k += 1

    return Block(
        kind: "o", html: "<pre><code>" + code + "</code></pre>\n", next: last + 1
    )

fn cell_tag(tag: String, text: String, align: String) String:
    let inl = inline(text)
    if align == "":
        return "<" + tag + ">" + inl + "</" + tag + ">\n"

    return "<" + tag + " align=\"" + align + "\">" + inl + "</" + tag + ">\n"

fn table(lines: List[String], i: Int) Block:
    let head = split_cells(lines[i])
    let delim = split_cells(lines[i + 1])
    var aligns = List[String]()
    for d in delim:
        aligns.append(align_of(d))

    var html = "<table>\n<thead>\n<tr>\n"
    var k = 0

    while k < head.length():
        html = html + cell_tag("th", head[k], aligns[k])
        k += 1

    html = html + "</tr>\n</thead>\n"

    var body = ""
    var rows = 0
    var j = i + 2

    while j < lines.length() and table_row_ok(lines[j]):
        let cells = split_cells(lines[j])
        body = body + "<tr>\n"

        var c = 0

        while c < head.length():
            var text = ""
            if c < cells.length():
                text = cells[c].clone()
            body = body + cell_tag("td", text, aligns[c])
            c += 1

        body = body + "</tr>\n"
        rows += 1
        j += 1

    if rows > 0:
        html = html + "<tbody>\n" + body + "</tbody>\n"
    html = html + "</table>\n"
    return Block(kind: "o", html: html, next: j)

fn paragraph(lines: List[String], i: Int) Block:
    var j = i + 1
    while j < lines.length() and para_continues(lines[j]):
        j += 1

    var text = ""
    var k = i

    while k < j:
        let l = lstrip_sp(lines[k])
        let base = rstrip_sp(l)
        text = text + base

        if k < j - 1:
            if l.length() - base.length() >= 2:
                text = text + hard()
            else:
                text = text + "\n"

        k += 1

    let inl = inline(text)
    return Block(kind: "p", html: "<p>" + inl + "</p>\n", inner: inl, next: j)

fn list_block(lines: List[String], i: Int, m0: Marker) Block:
    var items = List[List[Block]]()
    var loose = false
    var j = i
    var m = m0.clone()
    var go = true
    var next = i + 1

    while go:
        var content = List[String]()
        content.append(rest(lines[j], m.w))

        var k = j + 1
        var pending = 0
        var stop = j + 1
        var broke = false

        while k < lines.length() and not broke:
            let l = lines[k]

            if is_blank(l):
                pending += 1
            else if indent_of(l) >= m.w:
                var p = 0

                while p < pending:
                    content.append("")
                    p += 1

                pending = 0
                content.append(rest(l, m.w))
                stop = k + 1
            else:
                broke = true

            if not broke:
                k += 1

        let kids = parse_blocks(content)
        var c = 1

        while c < kids.length():
            if kids[c].gap:
                loose = true
            c += 1

        items.append(kids)

        var q = stop
        while q < lines.length() and is_blank(lines[q]):
            q += 1

        if let mk = same_kind(lines, q, m0):
            if q > stop:
                loose = true
            m = mk
            j = q
        else:
            go = false
            next = stop

    var tag = "ul"
    var html = ""

    if m0.ordered:
        tag = "ol"

        if m0.num != 1:
            html = "<ol start=\"" + "{m0.num}" + "\">\n"
        else:
            html = "<ol>\n"
    else:
        html = "<ul>\n"

    for kids in items:
        html = html + "<li>" + item_body(kids, not loose) + "</li>\n"
    html = html + "</" + tag + ">\n"
    return Block(kind: "o", html: html, next: next)

// Parses the block starting at line i (which is not blank).
fn block_at(lines: List[String], i: Int) Block:
    let line = lines[i]
    if let f = fence_open(line):
        return fenced(lines, i, f)

    if let h = atx_parse(line):
        let inl = inline(h.text)
        return Block(
            kind: "o",
            html: "<h" + "{h.level}" + ">" + inl + "</h" + "{h.level}" + ">\n",
            next: i + 1
        )

    if is_thematic(line):
        return Block(kind: "o", html: "<hr />\n", next: i + 1)
    if is_quote(line):
        return quote(lines, i)
    if let m = list_marker(line):
        return list_block(lines, i, m)
    if indent_of(line) >= 4:
        return indented(lines, i)

    if line.contains("|") and i + 1 < lines.length() and is_delim_row(lines[i + 1]):
        if split_cells(line).length() == split_cells(lines[i + 1]).length():
            return table(lines, i)
    return paragraph(lines, i)

fn parse_blocks(lines: List[String]) List[Block]:
    var out = List[Block]()
    var gap = false
    var i = 0

    while i < lines.length():
        if is_blank(lines[i]):
            gap = true
            i += 1
        else:
            let b = block_at(lines, i)
            out.append(
                Block(
                    kind: b.kind, html: b.html, inner: b.inner,
                    gap: gap and out.length() > 0, next: b.next
                )
            )
            gap = false
            i = b.next

    return out

// ---------------------------------------------------------------------------
// Inline processing
// ---------------------------------------------------------------------------

fn is_ws(c: String) Bool:
    return c == "" or c == " " or c == "\n" or c == hard()

fn is_space_nl(c: String) Bool:
    return c == " " or c == "\n" or c == hard()

// Adds literal text, merging with a trailing text node.
fn add_text(var nodes: List[Node], s: String) Unit:
    let last = nodes.length() - 1

    if last >= 0 and nodes[last].kind == "t":
        nodes[last] = Node(kind: "t", text: nodes[last].text + s)
    else:
        nodes.append(Node(kind: "t", text: s))

// Parses an inline link tail starting at the "(" at index open.
fn parse_tail(cs: List[String], open: Int) Tail?:
    let n = cs.length()
    var j = open + 1
    var dest = ""
    while j < n and is_space_nl(cs[j]):
        j += 1

    if cs_at(cs, j) == "<":
        var k = j + 1
        var closed = false
        var bad = false

        while k < n and not closed and not bad:
            let x = cs[k]

            if x == ">":
                closed = true
                k += 1
            else if x == "\n" or x == hard() or x == "<":
                bad = true
            else if x == "\\" and is_punct(cs_at(cs, k + 1)):
                dest = dest + cs_at(cs, k + 1)
                k += 2
            else:
                dest = dest + x
                k += 1

        if not closed:
            return none

        j = k
    else:
        var depth = 0
        var k = j
        var stop = false

        while k < n and not stop:
            let x = cs[k]

            if x == "\\" and is_punct(cs_at(cs, k + 1)):
                dest = dest + cs_at(cs, k + 1)
                k += 2
            else if is_space_nl(x):
                stop = true
            else if x == "(":
                depth += 1
                dest = dest + x
                k += 1
            else if x == ")":
                if depth == 0:
                    stop = true
                else:
                    depth -= 1
                    dest = dest + x
                    k += 1
            else:
                dest = dest + x
                k += 1

        if depth != 0:
            return none

        j = k

    var title = ""
    var has_title = false
    var k2 = j
    while k2 < n and is_space_nl(cs[k2]):
        k2 += 1

    if k2 > j and cs_at(cs, k2) == "\"":
        var m = k2 + 1
        var closed = false

        while m < n and not closed:
            let x = cs[m]

            if x == "\\" and cs_at(cs, m + 1) == "\"":
                title = title + "\""
                m += 2
            else if x == "\"":
                closed = true
                m += 1
            else if x == hard():
                title = title + "\n"
                m += 1
            else:
                title = title + x
                m += 1

        if not closed:
            return none

        has_title = true
        j = m

    var k3 = j
    while k3 < n and is_space_nl(cs[k3]):
        k3 += 1
    if cs_at(cs, k3) != ")":
        return none

    return Tail(dest: dest, title: title, has_title: has_title, stop: k3 + 1)

fn cs_at(cs: List[String], i: Int) String:
    if i < 0 or i >= cs.length():
        return ""

    return cs[i].clone()

// Link tail for the "]" at index close, when a "(" follows it.
fn tail_at(cs: List[String], close: Int) Tail?:
    if cs_at(cs, close + 1) != "(":
        return none

    return parse_tail(cs, close + 1)

// Text of cs[a, b) with line breaks turned into spaces (code span content).
fn span_text(cs: List[String], a: Int, b: Int) String:
    var out = ""
    var k = a

    while k < b:
        let x = cs[k]

        if x == "\n" or x == hard():
            out = out + " "
        else:
            out = out + x

        k += 1

    return out

// Scans the paragraph/heading text into a node list, resolving links as it goes.
fn scan(cs: List[String]) List[Node]:
    var nodes = List[Node]()
    let n = cs.length()
    var i = 0

    while i < n:
        let c = cs[i]

        if c == "\\":
            let nx = cs_at(cs, i + 1)

            if nx == "\n":
                nodes.append(Node(kind: "h"))
                i += 2
            else if is_punct(nx):
                add_text(var nodes, nx)
                i += 2
            else:
                add_text(var nodes, "\\")
                i += 1
        else if c == hard():
            nodes.append(Node(kind: "h"))
            i += 1
        else if c == "\n":
            nodes.append(Node(kind: "s"))
            i += 1
        else if c == "`":
            var run = 0
            while cs_at(cs, i + run) == "`":
                run += 1

            var j = i + run
            var found = -1

            while j < n and found < 0:
                if cs[j] == "`":
                    var r = 0
                    while cs_at(cs, j + r) == "`":
                        r += 1
                    if r == run:
                        found = j
                    j += r
                else:
                    j += 1

            if found < 0:
                add_text(var nodes, repeat_str("`", run))
                i += run
            else:
                var content = span_text(cs, i + run, found)
                let cl = content.length()
                if (
                    cl >= 2
                    and chr_at(content, 0) == " "
                    and chr_at(content, cl - 1) == " "
                    and content.trim_chars(" ").length() > 0
                ):
                    content = sub(content, 1, cl - 1)
                nodes.append(Node(kind: "c", text: content))
                i = found + run
        else if c == "*" or c == "_":
            var run = 0
            while cs_at(cs, i + run) == c:
                run += 1

            let pc = cs_at(cs, i - 1)
            let nc = cs_at(cs, i + run)
            let pw = is_ws(pc)
            let pp = is_punct(pc)
            let nw = is_ws(nc)
            let np = is_punct(nc)
            let left = (not nw) and ((not np) or pw or pp)
            let right = (not pw) and ((not pp) or nw or np)
            var op = left
            var cl = right

            if c == "_":
                op = left and ((not right) or pp)
                cl = right and ((not left) or np)

            nodes.append(
                Node(
                    kind: "d", ch: c.clone(), count: run, orig: run, can_open: op,
                    can_close: cl
                )
            )
            i += run
        else if c == "!" and cs_at(cs, i + 1) == "[":
            nodes.append(Node(kind: "m", text: "![", active: true))
            i += 2
        else if c == "[":
            nodes.append(Node(kind: "m", text: "[", active: true))
            i += 1
        else if c == "]":
            var p = -1
            var k = nodes.length() - 1

            while k >= 0 and p < 0:
                if nodes[k].kind == "m":
                    p = k
                k -= 1

            if p < 0:
                add_text(var nodes, "]")
                i += 1
            else if nodes[p].text == "[" and not nodes[p].active:
                nodes[p] = Node(kind: "t", text: "[")
                add_text(var nodes, "]")
                i += 1
            else:
                if let t = tail_at(cs, i):
                    let is_image = nodes[p].text == "!["
                    var kids = List[Node]()
                    while nodes.length() > p + 1:
                        kids.insert(0, nodes.pop().get(Node()))
                    nodes.pop()
                    kids = resolve(kids)

                    if is_image:
                        nodes.append(
                            Node(
                                kind: "i", text: t.dest, title: t.title,
                                has_title: t.has_title, kids: kids
                            )
                        )
                    else:
                        // Links never nest: deactivate earlier link openers.
                        var k2 = 0

                        while k2 < nodes.length():
                            if nodes[k2].kind == "m" and nodes[k2].text == "[":
                                nodes[k2] = Node(kind: "m", text: "[", active: false)
                            k2 += 1

                        nodes.append(
                            Node(
                                kind: "l", text: t.dest, title: t.title,
                                has_title: t.has_title, kids: kids
                            )
                        )

                    i = t.stop
                else:
                    nodes[p] = Node(kind: "t", text: nodes[p].text.clone())
                    add_text(var nodes, "]")
                    i += 1
        else:
            add_text(var nodes, c.clone())
            i += 1

    return nodes

fn is_closer(nd: Node) Bool:
    return nd.kind == "d" and nd.can_close and nd.count > 0

// Index of the nearest opener for the closer at pos, or -1.
fn find_opener(cur: List[Node], pos: Int) Int:
    let closer = cur[pos]
    var j = pos - 1

    while j >= 0:
        let o = cur[j]

        if o.kind == "d" and o.ch == closer.ch and o.can_open and o.count > 0:
            var skip = false
            if (o.can_close or closer.can_open) and (o.orig + closer.orig) % 3 == 0:
                if not (o.orig % 3 == 0 and closer.orig % 3 == 0):
                    skip = true
            if not skip:
                return j

        j -= 1

    return -1

// A delimiter run left unmatched inside emphasis becomes literal text.
fn literal_of(nd: Node) Node:
    if nd.kind == "d":
        return Node(kind: "t", text: repeat_str(nd.ch, nd.count))

    return nd.clone()

// Builds the emphasis node between opener j and closer pos, consuming amount chars.
fn apply_emph(cur: List[Node], j: Int, pos: Int, amount: Int) List[Node]:
    var out = List[Node]()
    var k = 0

    while k < j:
        out.append(cur[k].clone())
        k += 1

    let o = cur[j].count - amount

    if o > 0:
        var op = cur[j].clone()
        op.count = o
        out.append(op)

    var kids = List[Node]()
    k = j + 1

    while k < pos:
        kids.append(literal_of(cur[k]))
        k += 1

    out.append(Node(kind: "e", level: amount, kids: kids))

    let c = cur[pos].count - amount

    if c > 0:
        var cl = cur[pos].clone()
        cl.count = c
        out.append(cl)

    k = pos + 1

    while k < cur.length():
        out.append(cur[k].clone())
        k += 1

    return out

// Emphasis resolution over one node list (the whole text, or a link's children).
fn resolve(nodes: List[Node]) List[Node]:
    var cur = nodes
    var pos = 0

    while pos < cur.length():
        if is_closer(cur[pos]):
            let j = find_opener(cur, pos)

            if j >= 0:
                var amount = 1
                if cur[j].count >= 2 and cur[pos].count >= 2:
                    amount = 2

                let o = cur[j].count - amount
                cur = apply_emph(cur, j, pos, amount)

                if o > 0:
                    pos = j + 2
                else:
                    pos = j + 1
            else:
                pos += 1
        else:
            pos += 1

    return cur

fn title_attr(nd: Node) String:
    if nd.has_title:
        return " title=\"" + esc(nd.title) + "\""

    return ""

// Plain text of nodes, for image alt text.
fn alt_text(kids: List[Node]) String:
    var out = ""

    for nd in kids:
        if nd.kind == "t" or nd.kind == "m" or nd.kind == "c":
            out = out + nd.text
        else if nd.kind == "d":
            out = out + repeat_str(nd.ch, nd.count)
        else if nd.kind == "s" or nd.kind == "h":
            out = out + " "
        else:
            out = out + alt_text(nd.kids)

    return out

fn render(nodes: List[Node]) String:
    var out = ""

    for nd in nodes:
        if nd.kind == "t" or nd.kind == "m":
            out = out + esc(nd.text)
        else if nd.kind == "d":
            out = out + esc(repeat_str(nd.ch, nd.count))
        else if nd.kind == "c":
            out = out + "<code>" + esc(nd.text) + "</code>"
        else if nd.kind == "s":
            out = out + "\n"
        else if nd.kind == "h":
            out = out + "<br />\n"
        else if nd.kind == "e":
            var tag = "em"
            if nd.level == 2:
                tag = "strong"
            out = out + "<" + tag + ">" + render(nd.kids) + "</" + tag + ">"
        else if nd.kind == "l":
            out = (
                out
                + "<a href=\""
                + esc(nd.text)
                + "\""
                + title_attr(nd)
                + ">"
                + render(nd.kids)
                + "</a>"
            )
        else if nd.kind == "i":
            out = (
                out
                + "<img src=\""
                + esc(nd.text)
                + "\" alt=\""
                + esc(alt_text(nd.kids))
                + "\""
                + title_attr(nd)
                + " />"
            )

    return out

fn inline(text: String) String:
    var nodes = scan(split_chars(text))
    nodes = resolve(nodes)
    return render(nodes)

fn split_chars(text: String) List[String]:
    return text.chars()

export fn main() Int:
    let s = read_all(stdin()).get().decode_utf8().get("")
    let parts = s.split("\n")
    var count = parts.length()
    if s.length() == 0 or s.ends_with("\n"):
        count -= 1

    var lines = List[String]()
    var k = 0

    while k < count:
        lines.append(parts[k].clone())
        k += 1

    let blocks = parse_blocks(lines)
    stdout().write(html_of(blocks)).get()
    return 0

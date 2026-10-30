import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

# Marks a two-space hard break inside paragraph text; always directly followed by "\n".
let HARD = "\u{2}"

type Block:
    html: String
    inner: String
    para: Bool

type Parsed:
    blocks: List[Block]
    gap: Bool

type Taken:
    block: Block
    next: Int

type Item:
    parsed: Parsed
    end: Int

type Marker:
    ordered: Bool
    delim: String
    num: Int
    content: Int
    empty: Bool

type Fence:
    ch: String
    count: Int
    indent: Int
    info: String

type Tail:
    dest: String
    title: Optional[String]
    next: Int

type Run:
    ch: String
    count: Int
    orig: Int
    can_open: Bool
    can_close: Bool

type Node:
    case Text(value: String)
    case Delim(run: Run)
    case Opener(image: Bool, active: Bool)
    case Code(content: String)
    case Break
    case Link(dest: String, title: Optional[String], children: List[Node])
    case Image(dest: String, title: Optional[String], children: List[Node])
    case Emph(level: Int, children: List[Node])

export fn main() Int:
    let lines = read_lines(stdin()).get(List[String]())
    let parsed = parse_blocks(lines)
    var out = ""
    for b in parsed.blocks:
        out += b.html
    stdout().write(out).get()
    return 0

# ---------- helpers ----------

fn at(s: String, k: Int) String:
    return s.get(k, "")

fn sub(s: String, a: Int, b: Int) String:
    return s.slice_scalars(a, b).get("")

fn rest_from(s: String, k: Int) String:
    return sub(s, k, s.length())

fn esc(s: String) String:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
        "\"", "&quot;"
    )

fn is_punct(c: String) Bool:
    return c.length() == 1 and "!\"#$%&'()*+,-./:;<=>?@[\\]^_`\{|\}~".contains(c)

fn is_space_char(c: String) Bool:
    return c == " " or c == "\n" or c == HARD

fn is_blank(line: String) Bool:
    return line.trim().is_empty()

fn indent_of(line: String) Int:
    var n = 0
    while n < line.length() and at(line, n) == " ":
        n += 1
    return n

fn strip_up_to(line: String, n: Int) String:
    var k = 0
    while k < n and k < line.length() and at(line, k) == " ":
        k += 1
    return rest_from(line, k)

fn is_digit(c: String) Bool:
    return c.length() == 1 and "0123456789".contains(c)

fn is_hr(line: String) Bool:
    if indent_of(line) > 3:
        return false

    let s = line.replace(" ", "")
    if s.length() < 3:
        return false

    let c = at(s, 0)
    if c != "-" and c != "*" and c != "_":
        return false

    return s.replace(c, "").is_empty()

fn code_html(lines: List[String], lang: String) String:
    var html = "<pre><code>"
    if lang != "":
        html = "<pre><code class=\"language-" + esc(lang) + "\">"
    for l in lines:
        html += esc(l) + "\n"
    return html + "</code></pre>\n"

# ---------- block structure ----------

fn parse_blocks(lines: List[String]) Parsed:
    var blocks = List[Block]()
    var gap = false
    var blank = false
    var i = 0

    while i < lines.length():
        if is_blank(lines[i]):
            blank = true
            i += 1
        else:
            if blank and blocks.length() > 0:
                gap = true
            blank = false

            let t = take_block(lines, i)
            blocks.append(t.block.clone())
            i = t.next

    return Parsed(blocks: blocks, gap: gap)

fn take_block(lines: List[String], i: Int) Taken:
    if let t = try_fence(lines, i):
        return t
    if let t = try_atx(lines, i):
        return t
    if is_hr(lines[i]):
        return Taken(
            block: Block(html: "<hr />\n", inner: "", para: false), next: i + 1
        )
    if let t = try_quote(lines, i):
        return t
    if let t = try_list(lines, i):
        return t
    if let t = try_indented(lines, i):
        return t
    if let t = try_table(lines, i):
        return t

    return try_para(lines, i)

fn fence_of(line: String) Optional[Fence]:
    let ind = indent_of(line)
    if ind > 3:
        return none

    let rest = rest_from(line, ind)
    let c = at(rest, 0)
    if c != "`" and c != "~":
        return none

    var n = 0
    while n < rest.length() and at(rest, n) == c:
        n += 1
    if n < 3:
        return none

    let info = rest_from(rest, n).trim()
    if c == "`" and info.contains("`"):
        return none

    return Fence(ch: c, count: n, indent: ind, info: info)

fn is_fence_close(line: String, f: Fence) Bool:
    let ind = indent_of(line)
    if ind > 3:
        return false

    let rest = rest_from(line, ind)
    var n = 0
    while n < rest.length() and at(rest, n) == f.ch:
        n += 1
    if n < f.count:
        return false

    return rest_from(rest, n).trim().is_empty()

fn starts_fence(line: String) Bool:
    if let _f = fence_of(line):
        return true

    return false

fn try_fence(lines: List[String], i: Int) Optional[Taken]:
    if let f = fence_of(lines[i]):
        var body = List[String]()
        var j = i + 1
        var closed = false

        while j < lines.length() and not closed:
            if is_fence_close(lines[j], f):
                closed = true
            else:
                body.append(strip_up_to(lines[j], f.indent))
                j += 1

        let next = if closed: j + 1 else: j

        let lang = if f.info.is_empty(): "" else: f.info.split(" ").get(0, "")

        return Taken(
            block: Block(
                html: code_html(body, lang), inner: "", para: false
            ),
            next: next
        )

    return none

# Returns the ATX heading level, or 0 when the line is not an ATX heading.
fn atx_level(line: String) Int:
    let ind = indent_of(line)
    if ind > 3:
        return 0

    let rest = rest_from(line, ind)
    var n = 0
    while n < rest.length() and at(rest, n) == "#":
        n += 1
    if n < 1 or n > 6:
        return 0
    if n < rest.length() and at(rest, n) != " ":
        return 0

    return n

fn try_atx(lines: List[String], i: Int) Optional[Taken]:
    let level = atx_level(lines[i])
    if level == 0:
        return none

    var content = rest_from(lines[i], indent_of(lines[i]) + level).trim()
    var k = content.length()
    while k > 0 and at(content, k - 1) == "#":
        k -= 1
    if k < content.length() and (k == 0 or at(content, k - 1) == " "):
        content = sub(content, 0, k).trim()

    let html = "<h{level}>{inline_html(content)}</h{level}>\n"
    return Taken(block: Block(html: html, inner: "", para: false), next: i + 1)

fn starts_quote(line: String) Bool:
    let ind = indent_of(line)
    return ind <= 3 and at(line, ind) == ">"

fn try_quote(lines: List[String], i: Int) Optional[Taken]:
    if not starts_quote(lines[i]):
        return none

    var inner = List[String]()
    var j = i

    while j < lines.length() and starts_quote(lines[j]):
        let l = lines[j]
        var k = indent_of(l) + 1
        if at(l, k) == " ":
            k += 1
        inner.append(rest_from(l, k))
        j += 1

    let parsed = parse_blocks(inner)
    var html = "<blockquote>\n"
    for b in parsed.blocks:
        html += b.html
    html += "</blockquote>\n"
    return Taken(block: Block(html: html, inner: "", para: false), next: j)

# Parses a list marker; none when the line is not a list marker line.
fn marker_of(line: String) Optional[Marker]:
    let ind = indent_of(line)
    if ind > 3 or is_hr(line):
        return none

    let rest = rest_from(line, ind)
    let c = at(rest, 0)
    var width = 1
    var ordered = false
    var num = 0
    var delim = c.clone()

    if c != "-" and c != "*" and c != "+":
        var d = 0
        while d < rest.length() and is_digit(at(rest, d)):
            d += 1
        if d == 0 or d > 9 or d >= rest.length():
            return none

        delim = at(rest, d)
        if delim != "." and delim != ")":
            return none

        ordered = true
        num = sub(rest, 0, d).parse_int().get(0)
        width = d + 1

    let end = ind + width
    if end < line.length() and at(line, end) != " ":
        return none

    let tail = rest_from(line, end)
    if tail.trim().is_empty():
        return Marker(
            ordered: ordered, delim: delim, num: num, content: end + 1, empty: true
        )

    var sp = 0
    while sp < tail.length() and at(tail, sp) == " ":
        sp += 1

    let content = if sp >= 5: end + 1 else: end + sp

    return Marker(
        ordered: ordered, delim: delim, num: num, content: content, empty: false
    )

fn same_list(line: String, mk: Marker) Bool:
    if let other = marker_of(line):
        return other.ordered == mk.ordered and other.delim == mk.delim

    return false

fn parse_item(lines: List[String], i: Int, mk: Marker) Item:
    var body = List[String]()

    if mk.empty:
        body.append("")
    else:
        body.append(rest_from(lines[i], mk.content))

    var end = i + 1
    var j = i + 1
    var blanks = 0

    while j < lines.length():
        let l = lines[j]

        if is_blank(l):
            blanks += 1
        else if indent_of(l) >= mk.content:
            for k in 0..blanks:
                body.append("")
            blanks = 0
            body.append(rest_from(l, mk.content))
            end = j + 1
        else:
            break

        j += 1

    return Item(parsed: parse_blocks(body), end: end)

fn try_list(lines: List[String], i: Int) Optional[Taken]:
    if let first = marker_of(lines[i]):
        var items = List[Parsed]()
        var loose = false
        var mk = first.clone()
        var at_item = i
        var last_end = i
        var stop = false

        while not stop:
            let item = parse_item(lines, at_item, mk)
            items.append(item.parsed.clone())
            if item.parsed.gap:
                loose = true
            last_end = item.end

            var k = last_end
            var blank_seen = false

            while k < lines.length() and is_blank(lines[k]):
                k += 1
                blank_seen = true

            stop = true

            if k < lines.length():
                if let nxt = marker_of(lines[k]):
                    if same_list(lines[k], mk):
                        stop = false
                        at_item = k
                        mk = nxt
                        if blank_seen:
                            loose = true

        let html = render_list(items, loose, first.ordered, first.num)
        return Taken(block: Block(html: html, inner: "", para: false), next: last_end)

    return none

fn render_list(items: List[Parsed], loose: Bool, ordered: Bool, start: Int) String:
    let tag = if ordered: "ol" else: "ul"

    var html = "<{tag}>\n"
    if ordered and start != 1:
        html = "<ol start=\"{start}\">\n"

    for item in items:
        var body = ""

        for b in item.blocks:
            if b.para and not loose:
                body += b.inner
            else:
                if body.is_empty() or not body.ends_with("\n"):
                    body += "\n"
                body += b.html

        html += "<li>" + body + "</li>\n"

    return html + "</{tag}>\n"

fn try_indented(lines: List[String], i: Int) Optional[Taken]:
    if indent_of(lines[i]) < 4:
        return none

    var end = i
    var j = i

    while j < lines.length() and (is_blank(lines[j]) or indent_of(lines[j]) >= 4):
        if not is_blank(lines[j]):
            end = j
        j += 1

    var body = List[String]()
    for k in i..end + 1:
        body.append(strip_up_to(lines[k], 4))
    return Taken(
        block: Block(html: code_html(body, ""), inner: "", para: false), next: end + 1
    )

fn split_cells(line: String) List[String]:
    var s = line.trim().clone()
    if at(s, 0) == "|":
        s = rest_from(s, 1)
    if s.ends_with("|") and not (s.length() >= 2 and at(s, s.length() - 2) == "\\"):
        s = sub(s, 0, s.length() - 1)

    var cells = List[String]()
    var cur = ""
    var k = 0

    while k < s.length():
        let c = at(s, k)

        if c == "|" and not (k > 0 and at(s, k - 1) == "\\"):
            cells.append(cur.trim().clone())
            cur = ""
        else:
            cur += c

        k += 1

    cells.append(cur.trim().clone())
    return cells

fn is_delim_cell(c: String) Bool:
    var s = c
    if at(s, 0) == ":":
        s = rest_from(s, 1)
    if s.ends_with(":"):
        s = sub(s, 0, s.length() - 1)
    if s.is_empty():
        return false

    return s.replace("-", "").is_empty()

fn align_of(c: String) String:
    let left = at(c, 0) == ":"
    let right = c.ends_with(":")
    if left and right:
        return "center"
    if left:
        return "left"
    if right:
        return "right"

    return ""

fn align_attr(align: String) String:
    if align.is_empty():
        return ""

    return " align=\"" + align + "\""

fn try_table(lines: List[String], i: Int) Optional[Taken]:
    if i + 1 >= lines.length():
        return none

    let head = lines[i]
    let delim = lines[i + 1]
    if not head.contains("|") or not delim.contains("|"):
        return none

    let hcells = split_cells(head)
    let dcells = split_cells(delim)
    if hcells.length() != dcells.length():
        return none

    var aligns = List[String]()

    for c in dcells:
        if not is_delim_cell(c.clone()):
            return none

        aligns.append(align_of(c))

    let ncols = hcells.length()
    var html = "<table>\n<thead>\n<tr>\n"
    for c in 0..ncols:
        html += "<th" + align_attr(aligns[c]) + ">" + inline_html(hcells[c]) + "</th>\n"
    html += "</tr>\n</thead>\n"

    var j = i + 2
    var rows = ""

    while (
        j < lines.length()
        and not is_blank(lines[j])
        and not starts_fence(lines[j])
        and atx_level(lines[j]) == 0
        and not is_hr(lines[j])
        and not starts_quote(lines[j])
    ):
        let cells = split_cells(lines[j])
        rows += "<tr>\n"
        for c in 0..ncols:
            rows += (
                "<td"
                + align_attr(aligns[c])
                + ">"
                + inline_html(cells.get(c, ""))
                + "</td>\n"
            )
        rows += "</tr>\n"
        j += 1

    if rows != "":
        html += "<tbody>\n" + rows + "</tbody>\n"
    html += "</table>\n"
    return Taken(block: Block(html: html, inner: "", para: false), next: j)

fn interrupts_para(line: String) Bool:
    if (
        is_blank(line)
        or starts_fence(line)
        or atx_level(line) > 0
        or is_hr(line)
        or starts_quote(line)
    ):
        return true
    if let mk = marker_of(line):
        return not mk.empty and (not mk.ordered or mk.num == 1)

    return false

fn try_para(lines: List[String], i: Int) Taken:
    var end = i + 1
    while end < lines.length() and not interrupts_para(lines[end]):
        end += 1

    var text = ""

    for k in i..end:
        let line = lines[k].trim_start()
        let trimmed = line.trim_end()

        if k == end - 1:
            text += trimmed
        else if line.length() - trimmed.length() >= 2:
            text += trimmed + HARD + "\n"
        else:
            text += trimmed + "\n"

    let inner = inline_html(text)
    return Taken(
        block: Block(html: "<p>" + inner + "</p>\n", inner: inner, para: true),
        next: end
    )

# ---------- inline structure ----------

fn inline_html(text: String) String:
    return render(resolve(scan(text)))

fn opener_label(node: Node) String:
    match node:
        Opener(image, _active):
            if image:
                return "!["

            return "["
        _:
            return ""

fn opener_active(node: Node) Bool:
    match node:
        Opener(_image, active):
            return active
        _:
            return true

fn run_of(node: Node) Optional[Run]:
    match node:
        Delim(run):
            return run
        _:
            return none

fn last_opener(nodes: List[Node]) Int:
    var k = nodes.length() - 1

    while k >= 0:
        match nodes[k]:
            Opener(_image, _active):
                return k
            _:
                k -= 1

    return -1

fn code_content(cs: List[String], a: Int, b: Int) String:
    var s = ""

    for k in a..b:
        if cs[k] == "\n":
            s += " "
        else if cs[k] != HARD:
            s += cs[k]

    if (
        s.length() >= 2
        and s.starts_with(" ")
        and s.ends_with(" ")
        and not s.trim().is_empty()
    ):
        s = sub(s, 1, s.length() - 1)
    return s

fn parse_tail(cs: List[String], start: Int) Optional[Tail]:
    let n = cs.length()
    if start >= n or cs[start] != "(":
        return none

    var k = start + 1
    var dest = ""
    while k < n and is_space_char(cs[k]):
        k += 1

    if k < n and cs[k] == "<":
        k += 1

        while k < n and cs[k] != ">":
            if cs[k] == "\\" and k + 1 < n and is_punct(cs[k + 1]):
                dest += cs[k + 1]
                k += 2
            else if cs[k] == "\n" or cs[k] == "<":
                return none
            else:
                dest += cs[k]
                k += 1

        if k >= n:
            return none

        k += 1
    else:
        var depth = 0

        while k < n:
            let c = cs[k]

            if c == "\\" and k + 1 < n and is_punct(cs[k + 1]):
                dest += cs[k + 1]
                k += 2
            else if is_space_char(c):
                break
            else if c == ")" and depth == 0:
                break
            else:
                if c == "(":
                    depth += 1
                if c == ")":
                    depth -= 1
                dest += c
                k += 1

        if depth != 0 or k >= n:
            return none

    var saw_space = false

    while k < n and is_space_char(cs[k]):
        k += 1
        saw_space = true

    var title: Optional[String] = none

    if saw_space and k < n and cs[k] == "\"":
        k += 1

        var t = ""

        while k < n and cs[k] != "\"":
            if cs[k] == "\\" and k + 1 < n and cs[k + 1] == "\"":
                t += "\""
                k += 2
            else:
                t += cs[k]
                k += 1

        if k >= n:
            return none

        k += 1
        title = t
        while k < n and is_space_char(cs[k]):
            k += 1

    if k < n and cs[k] == ")":
        return Tail(dest: dest, title: title, next: k + 1)

    return none

# Turns an unresolved delimiter or bracket marker into literal text.
fn literal(node: Node) Node:
    match node:
        Delim(run):
            var s = ""
            for k in 0..run.count:
                s += run.ch
            return Node.Text(s)
        Opener(_image, _active):
            return Node.Text(opener_label(node))
        _:
            return node

fn deactivate(node: Node) Node:
    match node:
        Opener(image, _active):
            if image:
                return node

            return Node.Opener(image: false, active: false)
        _:
            return node

fn scan(text: String) List[Node]:
    let cs = text.chars()
    let n = cs.length()
    var nodes = List[Node]()
    var i = 0

    while i < n:
        let c = cs[i]

        if c == "\\" and i + 1 < n and cs[i + 1] == "\n":
            nodes.append(Node.Break)
            i += 2
        else if c == "\\" and i + 1 < n and is_punct(cs[i + 1]):
            nodes.append(Node.Text(cs[i + 1].clone()))
            i += 2
        else if c == HARD and i + 1 < n and cs[i + 1] == "\n":
            nodes.append(Node.Break)
            i += 2
        else if c == "`":
            var m = 0
            while i + m < n and cs[i + m] == "`":
                m += 1

            var j = i + m
            var found = -1

            while j < n and found < 0:
                if cs[j] == "`":
                    var r = 0
                    while j + r < n and cs[j + r] == "`":
                        r += 1
                    if r == m:
                        found = j
                    j += r
                else:
                    j += 1

            if found >= 0:
                nodes.append(Node.Code(code_content(cs, i + m, found)))
                i = found + m
            else:
                let stop = i + m
                for k in i..stop:
                    nodes.append(Node.Text(cs[k].clone()))
                i = stop
        else if c == "*" or c == "_":
            var r = 0
            while i + r < n and cs[i + r] == c:
                r += 1

            let prev = if i == 0: " " else: cs[i - 1].clone()

            let next = if i + r >= n: " " else: cs[i + r].clone()

            let lf = (
                next != " "
                and next != "\n"
                and next != HARD
                and (
                    not is_punct(next)
                    or prev == " "
                    or prev == "\n"
                    or prev == HARD
                    or is_punct(prev)
                )
            )
            let rf = (
                prev != " "
                and prev != "\n"
                and prev != HARD
                and (
                    not is_punct(prev)
                    or next == " "
                    or next == "\n"
                    or next == HARD
                    or is_punct(next)
                )
            )
            var can_open = lf
            var can_close = rf

            if c == "_":
                can_open = lf and (not rf or is_punct(prev))
                can_close = rf and (not lf or is_punct(next))

            nodes.append(
                Node.Delim(
                    run: Run(
                        ch: c.clone(), count: r, orig: r, can_open: can_open,
                        can_close: can_close
                    )
                )
            )
            i += r
        else if c == "!" and i + 1 < n and cs[i + 1] == "[":
            nodes.append(Node.Opener(image: true, active: true))
            i += 2
        else if c == "[":
            nodes.append(Node.Opener(image: false, active: true))
            i += 1
        else if c == "]":
            let m = last_opener(nodes)

            if m < 0:
                nodes.append(Node.Text("]"))
                i += 1
            else if not opener_active(nodes[m]):
                nodes[m] = Node.Text(opener_label(nodes[m]))
                nodes.append(Node.Text("]"))
                i += 1
            else:
                let is_image = opener_label(nodes[m]) == "!["

                if let t = parse_tail(cs, i + 1):
                    nodes = close_bracket(nodes, m, t, is_image)
                    i = t.next
                else:
                    nodes[m] = Node.Text(opener_label(nodes[m]))
                    nodes.append(Node.Text("]"))
                    i += 1
        else:
            nodes.append(Node.Text(c.clone()))
            i += 1

    return nodes

fn close_bracket(nodes: List[Node], m: Int, t: Tail, is_image: Bool) List[Node]:
    var out = List[Node]()

    for k in 0..m:
        if is_image:
            out.append(nodes[k].clone())
        else:
            out.append(deactivate(nodes[k].clone()))

    var kids = List[Node]()
    for k in m + 1..nodes.length():
        kids.append(nodes[k].clone())

    let resolved = resolve(kids)

    if is_image:
        out.append(
            Node.Image(
                dest: t.dest.clone(), title: t.title.clone(), children: resolved
            )
        )
    else:
        out.append(
            Node.Link(
                dest: t.dest.clone(), title: t.title.clone(), children: resolved
            )
        )

    return out

# Returns the index of the opener matching the closer at index i, or -1.
fn find_opener(nodes: List[Node], i: Int, closer: Run) Int:
    var j = i - 1

    while j >= 0:
        if let o = run_of(nodes[j].clone()):
            if o.ch == closer.ch and o.can_open and o.count > 0:
                let both = o.can_close or closer.can_open
                let sum = o.orig + closer.orig
                let ok = (
                    not both
                    or sum % 3 != 0
                    or (o.orig % 3 == 0 and closer.orig % 3 == 0)
                )
                if ok:
                    return j

        j -= 1

    return -1

fn resolve(input: List[Node]) List[Node]:
    var nodes = List[Node]()
    for node in input:
        nodes.append(node)

    var i = 0

    while i < nodes.length():
        var matched = false

        if let closer = run_of(nodes[i].clone()):
            if closer.can_close and closer.count > 0:
                let j = find_opener(nodes, i, closer)

                if j >= 0:
                    if let opener = run_of(nodes[j].clone()):
                        matched = true

                        let use = if opener.count >= 2 and closer.count >= 2: 2 else: 1

                        let orem = opener.count - use
                        let crem = closer.count - use
                        var kids = List[Node]()
                        for k in j + 1..i:
                            kids.append(literal(nodes[k].clone()))

                        var out = List[Node]()
                        for k in 0..j:
                            out.append(nodes[k].clone())
                        if orem > 0:
                            out.append(
                                Node.Delim(
                                    run: Run(
                                        ch: opener.ch.clone(), count: orem,
                                        orig: opener.orig, can_open: opener.can_open,
                                        can_close: opener.can_close
                                    )
                                )
                            )
                        out.append(Node.Emph(level: use, children: kids))
                        if crem > 0:
                            out.append(
                                Node.Delim(
                                    run: Run(
                                        ch: closer.ch.clone(), count: crem,
                                        orig: closer.orig, can_open: closer.can_open,
                                        can_close: closer.can_close
                                    )
                                )
                            )
                        for k in i + 1..nodes.length():
                            out.append(nodes[k].clone())
                        nodes = out
                        i = j + (if orem > 0: 1 else: 0) + 1

        if not matched:
            i += 1

    var result = List[Node]()
    for node in nodes:
        result.append(literal(node))
    return result

fn title_attr(title: Optional[String]) String:
    if let t = title:
        return " title=\"" + esc(t) + "\""

    return ""

fn plain(nodes: List[Node]) String:
    var s = ""

    for node in nodes:
        match node:
            Text(value):
                s += value.replace("\n", " ")
            Code(content):
                s += content
            Break:
                s += " "
            Emph(_level, children):
                s += plain(children)
            Link(_dest, _title, children):
                s += plain(children)
            Image(_dest, _title, children):
                s += plain(children)
            _:
                s += ""

    return s

fn render(nodes: List[Node]) String:
    var out = ""

    for node in nodes:
        match node:
            Text(value):
                out += esc(value)
            Code(content):
                out += "<code>" + esc(content) + "</code>"
            Break:
                out += "<br />\n"
            Emph(level, children):
                let tag = if level == 2: "strong" else: "em"

                out += "<" + tag + ">" + render(children) + "</" + tag + ">"
            Link(dest, title, children):
                out += (
                    "<a href=\""
                    + esc(dest)
                    + "\""
                    + title_attr(title)
                    + ">"
                    + render(children)
                    + "</a>"
                )
            Image(dest, title, children):
                out += (
                    "<img src=\""
                    + esc(dest)
                    + "\" alt=\""
                    + esc(plain(children))
                    + "\""
                    + title_attr(title)
                    + " />"
                )
            _:
                out += ""

    return out

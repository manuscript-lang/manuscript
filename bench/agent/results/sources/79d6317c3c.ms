from "@std/io.ms" import read_all, stdin, stdout
from "@std/string.ms" import from_scalars
from "@std/collections.ms" import range

# Code points used by the scanners. The input is ASCII, so SENT (a private-use
# character) can only come from the converter itself: it marks a two-space hard break.
let SP = 32
let NL = 10
let BANG = 33
let DQ = 34
let HASH = 35
let LPAREN = 40
let RPAREN = 41
let STAR = 42
let PLUS = 43
let DASH = 45
let DOT = 46
let COLON = 58
let LT = 60
let GT = 62
let LBRACK = 91
let BS = 92
let RBRACK = 93
let UNDER = 95
let BT = 96
let PIPE = 124
let TILDE = 126
let SENT = 57344

type Block:
    case Html(text: String)
    case Para(html: String)

type Parsed:
    blocks: List[Block]
    loose: Bool

type Step:
    block: Block
    next: Int

type Fence:
    ch: Int
    len: Int
    indent: Int
    info: String

type Heading:
    level: Int
    content: String

type Marker:
    ordered: Bool
    ch: Int
    num: Int
    width: Int
    empty: Bool

type Node:
    case Text(value: String)
    case Break(hard: Bool)
    case Code(value: String)
    case Delim(ch: String, count: Int, orig: Int, can_open: Bool, can_close: Bool)
    case Opener(image: Bool, active: Bool)
    case Emph(strong: Bool, children: List[Node])
    case Link(image: Bool, dest: String, title: Optional[String], children: List[Node])

type Flags:
    can_open: Bool
    can_close: Bool

type Scan:
    nodes: List[Node]
    next: Int

type Tail:
    dest: String
    title: Optional[String]
    end: Int

export def main() -> Int:
    let input = read_all(stdin()).get()
    let text = input.decode_utf8().get()
    var lines = text.split("\n")
    if lines.length() > 0 and lines.get(lines.length() - 1) == "":
        lines.pop()

    let parsed = parse_blocks(lines)
    stdout().write(render_blocks(parsed.blocks.clone())).get()
    stdout().flush().get()
    return 0

# ---------------------------------------------------------------- helpers
def at(cs: List[Int], i: Int) -> Int:
    if i < 0 or i >= cs.length():
        return 0

    return cs.get(i)

def at_or_space(cs: List[Int], i: Int) -> Int:
    if i < 0 or i >= cs.length():
        return SP

    return cs.get(i)

def to_str(cs: List[Int]) -> String:
    return from_scalars(cs).get()

def sent_str() -> String:
    return to_str([SENT])

def is_ws(c: Int) -> Bool:
    return c == SP or c == NL or c == SENT

def is_punct(c: Int) -> Bool:
    return (
        (c >= 33 and c <= 47)
        or (c >= 58 and c <= 64)
        or (c >= 91 and c <= 96)
        or (c >= 123 and c <= 126)
    )

def is_digit(c: Int) -> Bool:
    return c >= 48 and c <= 57

def esc(s: String) -> String:
    let a = s.replace_all("&", "&amp;").get()
    let b = a.replace_all("<", "&lt;").get()
    let c = b.replace_all(">", "&gt;").get()
    return c.replace_all("\"", "&quot;").get()

def run_length(cs: List[Int], i: Int, c: Int) -> Int:
    var k = i
    while at(cs, k) == c:
        k += 1
    return k - i

def indent_of(line: String) -> Int:
    let cs = line.scalar_values()
    var k = 0
    while at(cs, k) == SP:
        k += 1
    return k

def is_blank(line: String) -> Bool:
    return indent_of(line) == line.length()

def drop_cols(line: String, k: Int) -> String:
    let n = line.length()
    if k >= n:
        return ""

    return line.slice_scalars(k, n).get()

def strip_upto(line: String, k: Int) -> String:
    let ind = indent_of(line)
    if ind < k:
        return drop_cols(line, ind)

    return drop_cols(line, k)

def rtrim_sp(s: String) -> String:
    let cs = s.scalar_values()
    var b = cs.length()
    while b > 0 and cs.get(b - 1) == SP:
        b -= 1
    return to_str(cs.slice(0, b).get())

def trim_sp(s: String) -> String:
    let cs = s.scalar_values()
    var a = 0
    while at(cs, a) == SP:
        a += 1

    var b = cs.length()
    while b > a and cs.get(b - 1) == SP:
        b -= 1
    return to_str(cs.slice(a, b).get())

def has_hard_end(line: String) -> Bool:
    let cs = line.scalar_values()
    let n = cs.length()
    return at(cs, n - 1) == SP and at(cs, n - 2) == SP

# ---------------------------------------------------------------- blocks
def parse_blocks(lines: List[String]) -> Parsed:
    var blocks: List[Block] = []
    var loose = False
    var blank = False
    var i = 0
    let n = lines.length()

    while i < n:
        if is_blank(lines.get(i)):
            blank = True
            i += 1
        else:
            if blank and blocks.length() > 0:
                loose = True
            blank = False

            let step = parse_block(lines.clone(), i)
            blocks.append(step.block)
            i = step.next

    return Parsed(blocks: blocks, loose: loose)

def render_blocks(blocks: List[Block]) -> String:
    var out = ""

    for b in blocks:
        match b:
            case Html(text):
                out = out.concat(text)
            case Para(html):
                out = out.concat("<p>").concat(html).concat("</p>\n")

    return out

def parse_block(lines: List[String], i: Int) -> Step:
    let line = lines.get(i)
    if let f = fence_of(line):
        return fence_block(lines.clone(), i, f)
    if let h = heading_of(line):
        return Step(
            block: Html(
                text: f"<h{h.level}>{inline(h.content)}</h{h.level}>\n"
            ),
            next: i + 1
        )
    if hr_line(line):
        return Step(block: Html(text: "<hr />\n"), next: i + 1)
    if is_quote_line(line):
        return quote_block(lines.clone(), i)
    if let m = list_marker(line):
        return parse_list(lines.clone(), i, m)
    if indent_of(line) >= 4:
        return indented_code(lines.clone(), i)
    if let t = table_at(lines.clone(), i):
        return t

    return paragraph(lines.clone(), i)

def fence_of(line: String) -> Optional[Fence]:
    let cs = line.scalar_values()
    let ind = indent_of(line)
    if ind > 3:
        return none

    let c = at(cs, ind)
    if c != BT and c != TILDE:
        return none

    let run = run_length(cs, ind, c)
    if run < 3:
        return none

    let info = trim_sp(drop_cols(line, ind + run))
    if c == BT and info.contains("`"):
        return none

    return some(Fence(ch: c, len: run, indent: ind, info: info))

def fence_close(line: String, f: Fence) -> Bool:
    let ind = indent_of(line)
    if ind > 3:
        return False

    let cs = line.scalar_values()
    let run = run_length(cs, ind, f.ch)
    if run < f.len:
        return False

    var k = ind + run

    while k < cs.length():
        if cs.get(k) != SP:
            return False

        k += 1

    return True

def fence_block(lines: List[String], i: Int, f: Fence) -> Step:
    var body = ""
    var j = i + 1
    let n = lines.length()

    while j < n and not fence_close(lines.get(j), f):
        body = body.concat(esc(strip_upto(lines.get(j), f.indent))).concat("\n")
        j += 1

    var next = n
    if j < n:
        next = j + 1

    var open = "<pre><code>"

    if f.info.length() > 0:
        let word = f.info.split(" ").get(0)
        open = f"<pre><code class=\"language-{esc(word)}\">"

    return Step(
        block: Html(text: open.concat(body).concat("</code></pre>\n")), next: next
    )

def heading_of(line: String) -> Optional[Heading]:
    let cs = line.scalar_values()
    let ind = indent_of(line)
    if ind > 3:
        return none

    let h = run_length(cs, ind, HASH)
    if h < 1 or h > 6:
        return none

    let after = ind + h
    if after < cs.length() and cs.get(after) != SP:
        return none

    let content = trim_sp(drop_cols(line, after))
    let ccs = content.scalar_values()
    var k = ccs.length()
    while k > 0 and ccs.get(k - 1) == HASH:
        k -= 1

    var text = content
    if k < ccs.length() and (k == 0 or ccs.get(k - 1) == SP):
        text = rtrim_sp(to_str(ccs.slice(0, k).get()))
    return some(Heading(level: h, content: text))

def hr_line(line: String) -> Bool:
    if indent_of(line) > 3:
        return False

    var kind = 0
    var count = 0

    for c in line.scalar_values():
        if c != SP:
            if kind == 0:
                kind = c
            if c != kind:
                return False

            count += 1

    return (kind == STAR or kind == DASH or kind == UNDER) and count >= 3

def is_quote_line(line: String) -> Bool:
    let ind = indent_of(line)
    return ind <= 3 and at(line.scalar_values(), ind) == GT

def strip_quote(line: String) -> String:
    var p = indent_of(line) + 1
    if at(line.scalar_values(), p) == SP:
        p += 1
    return drop_cols(line, p)

def quote_block(lines: List[String], i: Int) -> Step:
    var inner: List[String] = []
    var j = i

    while j < lines.length() and is_quote_line(lines.get(j)):
        inner.append(strip_quote(lines.get(j)))
        j += 1

    let parsed = parse_blocks(inner)
    let html = (
        "<blockquote>\n"
        .concat(render_blocks(parsed.blocks.clone()))
        .concat("</blockquote>\n")
    )
    return Step(block: Html(text: html), next: j)

def indented_code(lines: List[String], i: Int) -> Step:
    let n = lines.length()
    var last = i
    var j = i

    while j < n:
        let l = lines.get(j)

        if is_blank(l) or indent_of(l) >= 4:
            if not is_blank(l):
                last = j
            j += 1
        else:
            break

    var body = ""
    for k in range(i, last + 1):
        body = body.concat(esc(strip_upto(lines.get(k), 4))).concat("\n")
    return Step(
        block: Html(text: "<pre><code>".concat(body).concat("</code></pre>\n")),
        next: last + 1
    )

def paragraph(lines: List[String], i: Int) -> Step:
    let n = lines.length()
    var j = i + 1
    while j < n and para_continues(lines.get(j)):
        j += 1

    var text = ""

    for k in range(i, j):
        var line = drop_cols(lines.get(k), indent_of(lines.get(k)))

        if k < j - 1:
            let hard = has_hard_end(line)
            line = rtrim_sp(line)

            var sep = "\n"
            if hard:
                sep = sent_str()
            text = text.concat(line).concat(sep)
        else:
            text = text.concat(rtrim_sp(line))

    return Step(block: Para(html: inline(text)), next: j)

def starts_block(line: String) -> Bool:
    return fence_of(line).is_some() or heading_of(line).is_some()

def para_continues(line: String) -> Bool:
    if is_blank(line):
        return False
    if starts_block(line):
        return False
    if hr_line(line) or is_quote_line(line):
        return False

    if let m = list_marker(line):
        if not m.empty and (not m.ordered or m.num == 1):
            return False
    return True

def row_continues(line: String) -> Bool:
    if is_blank(line):
        return False
    if starts_block(line):
        return False

    return not hr_line(line) and not is_quote_line(line)

# ---------------------------------------------------------------- lists
def list_marker(line: String) -> Optional[Marker]:
    let cs = line.scalar_values()
    let n = cs.length()
    let ind = indent_of(line)
    if ind > 3:
        return none

    var p = ind
    var ordered = False
    var num = 0
    var ch = at(cs, p)

    if ch == DASH or ch == STAR or ch == PLUS:
        p += 1
    else:
        let digits = run_digits(cs.clone(), p)
        if digits < 1 or digits > 9:
            return none

        num = to_str(cs.slice(p, p + digits).get()).parse_int().get()
        p += digits
        ch = at(cs, p)
        if ch != DOT and ch != RPAREN:
            return none

        ordered = True
        p += 1

    if p < n and cs.get(p) != SP:
        return none

    var width = p + 1

    if p < n:
        var spaces = 0
        while at(cs, p + spaces) == SP:
            spaces += 1
        if spaces < 5:
            width = p + spaces

    let empty = is_blank(drop_cols(line, width))
    return some(Marker(ordered: ordered, ch: ch, num: num, width: width, empty: empty))

def run_digits(cs: List[Int], i: Int) -> Int:
    var k = i
    while is_digit(at(cs, k)):
        k += 1
    return k - i

def same_list(line: String, first: Marker) -> Bool:
    if let m = list_marker(line):
        return not hr_line(line) and m.ordered == first.ordered and m.ch == first.ch

    return False

def parse_list(lines: List[String], i0: Int, first: Marker) -> Step:
    let n = lines.length()
    var items: List[List[Block]] = []
    var loose = False
    var i = i0
    var m = first
    var go = True
    var stop = i0 + 1

    while go:
        var item: List[String] = [drop_cols(lines.get(i), m.width)]
        var pending = 0
        var end = i + 1
        var j = i + 1

        while j < n:
            let l = lines.get(j)

            if is_blank(l):
                pending += 1
            else:
                if indent_of(l) < m.width:
                    break

                for k in range(0, pending):
                    item.append("")
                pending = 0
                item.append(drop_cols(l, m.width))
                end = j + 1

            j += 1

        let parsed = parse_blocks(item)
        if parsed.loose:
            loose = True
        items.append(parsed.blocks.clone())
        stop = end

        var k = end
        while k < n and is_blank(lines.get(k)):
            k += 1

        if k < n and same_list(lines.get(k), first):
            if k > end:
                loose = True
            i = k
            m = list_marker(lines.get(k)).get()
        else:
            go = False

    var body = ""
    for blocks in items:
        body = (
            body
            .concat("<li>")
            .concat(item_html(blocks, not loose))
            .concat("</li>\n")
        )

    var open = "<ul>\n"
    var close = "</ul>\n"

    if first.ordered:
        open = "<ol>\n"
        if first.num != 1:
            open = f"<ol start=\"{first.num}\">\n"
        close = "</ol>\n"

    return Step(block: Html(text: open.concat(body).concat(close)), next: stop)

def item_html(blocks: List[Block], tight: Bool) -> String:
    var body = ""

    for b in blocks:
        match b:
            case Para(html):
                if tight:
                    body = body.concat(html)
                else:
                    body = separate(body).concat("<p>").concat(html).concat("</p>\n")
            case Html(text):
                body = separate(body).concat(text)

    return body

def separate(body: String) -> String:
    if body.ends_with("\n"):
        return body

    return body.concat("\n")

# ---------------------------------------------------------------- tables
def split_cells(line: String) -> List[String]:
    var cs = trim_sp(line).scalar_values()
    if at(cs, 0) == PIPE and cs.length() > 0:
        cs = cs.drop(1)

    let m = cs.length()
    if m > 0 and cs.get(m - 1) == PIPE and not (m >= 2 and cs.get(m - 2) == BS):
        cs = cs.take(m - 1)

    var cells: List[String] = []
    var cur: List[Int] = []

    for k in range(0, cs.length()):
        let c = cs.get(k)

        if c == PIPE and at(cs, k - 1) != BS:
            cells.append(trim_sp(to_str(cur)))
            cur = []
        else:
            cur.append(c)

    cells.append(trim_sp(to_str(cur)))
    return cells

def is_delim_cell(cell: String) -> Bool:
    let cs = cell.scalar_values()
    let n = cs.length()
    var a = 0
    if at(cs, 0) == COLON:
        a = 1

    var b = n
    if b - 1 >= a and at(cs, b - 1) == COLON:
        b -= 1
    if b - a < 1:
        return False

    for k in range(a, b):
        if cs.get(k) != DASH:
            return False
    return True

def align_of(cell: String) -> String:
    let cs = cell.scalar_values()
    let left = at(cs, 0) == COLON
    let right = at(cs, cs.length() - 1) == COLON
    if left and right:
        return "center"
    if left:
        return "left"
    if right:
        return "right"

    return ""

def align_attr(align: String) -> String:
    if align == "":
        return ""

    return f" align=\"{align}\""

def table_at(lines: List[String], i: Int) -> Optional[Step]:
    let n = lines.length()
    if i + 1 >= n:
        return none

    let head = lines.get(i)
    let delim = lines.get(i + 1)
    if not head.contains("|") or not delim.contains("|"):
        return none

    let aligns = split_cells(delim)
    for cell in aligns:
        if not is_delim_cell(cell):
            return none

    let heads = split_cells(head)
    if heads.length() != aligns.length():
        return none

    var rows: List[List[String]] = []
    var j = i + 2

    while j < n and row_continues(lines.get(j)):
        rows.append(split_cells(lines.get(j)))
        j += 1

    var html = "<table>\n<thead>\n<tr>\n"

    for c in range(0, heads.length()):
        html = (
            html
            .concat("<th")
            .concat(align_attr(align_of(aligns.get(c))))
            .concat(">")
        )
        html = html.concat(inline(heads.get(c))).concat("</th>\n")

    html = html.concat("</tr>\n</thead>\n")

    if rows.length() > 0:
        html = html.concat("<tbody>\n")

        for row in rows:
            html = html.concat("<tr>\n")

            for c in range(0, heads.length()):
                var cell = ""
                if c < row.length():
                    cell = row.get(c)
                html = (
                    html
                    .concat("<td")
                    .concat(align_attr(align_of(aligns.get(c))))
                    .concat(">")
                )
                html = html.concat(inline(cell)).concat("</td>\n")

            html = html.concat("</tr>\n")

        html = html.concat("</tbody>\n")

    html = html.concat("</table>\n")
    return some(Step(block: Html(text: html), next: j))

# ---------------------------------------------------------------- inline
def inline(text: String) -> String:
    return render_nodes(scan(text))

def scan(text: String) -> List[Node]:
    let cs = text.scalar_values()
    let n = cs.length()
    var nodes: List[Node] = []
    var i = 0

    while i < n:
        let c = cs.get(i)

        if c == BS:
            let nx = at(cs, i + 1)

            if i + 1 < n and nx == NL:
                nodes.append(Break(hard: True))
                i += 2
            else:
                if i + 1 < n and is_punct(nx):
                    nodes.append(Text(value: to_str([nx])))
                    i += 2
                else:
                    nodes.append(Text(value: "\\"))
                    i += 1
        elif c == NL:
            nodes.append(Break(hard: False))
            i += 1
        elif c == SENT:
            nodes.append(Break(hard: True))
            i += 1
        elif c == BT:
            let run = run_length(cs.clone(), i, BT)
            let close = find_run(cs.clone(), i + run, run, BT)

            if close < 0:
                nodes.append(Text(value: "`".repeat(run).get()))
                i += run
            else:
                nodes.append(Code(value: code_span(cs.clone(), i + run, close)))
                i = close + run
        elif c == STAR or c == UNDER:
            let run = run_length(cs.clone(), i, c)
            let flags = run_flags(
                c, at_or_space(cs.clone(), i - 1), at_or_space(cs.clone(), i + run)
            )
            nodes.append(
                Delim(
                    ch: to_str([c]), count: run, orig: run, can_open: flags.can_open,
                    can_close: flags.can_close
                )
            )
            i += run
        elif c == BANG and at(cs, i + 1) == LBRACK:
            nodes.append(Opener(image: True, active: True))
            i += 2
        elif c == LBRACK:
            nodes.append(Opener(image: False, active: True))
            i += 1
        elif c == RBRACK:
            let step = close_bracket(cs.clone(), nodes, i)
            nodes = step.nodes.clone()
            i = step.next
        else:
            nodes.append(Text(value: to_str([c])))
            i += 1

    var out: List[Node] = []
    for node in nodes:
        out.append(opener_to_text(node))
    return resolve(out)

def find_run(cs: List[Int], from: Int, len: Int, c: Int) -> Int:
    var j = from

    while j < cs.length():
        if cs.get(j) == c:
            let m = run_length(cs.clone(), j, c)
            if m == len:
                return j

            j += m
        else:
            j += 1

    return -1

def code_span(cs: List[Int], a: Int, b: Int) -> String:
    var codes: List[Int] = []

    for k in range(a, b):
        let c = cs.get(k)

        if c == NL or c == SENT:
            codes.append(SP)
        else:
            codes.append(c)

    let n = codes.length()
    var all_space = True
    for c in codes:
        if c != SP:
            all_space = False
    if n >= 2 and not all_space and codes.get(0) == SP and codes.get(n - 1) == SP:
        return to_str(codes.slice(1, n - 1).get())

    return to_str(codes)

def run_flags(c: Int, prev: Int, next: Int) -> Flags:
    let left = not is_ws(next) and (not is_punct(next) or is_ws(prev) or is_punct(prev))
    let right = (
        not is_ws(prev)
        and (not is_punct(prev) or is_ws(next) or is_punct(next))
    )
    if c == STAR:
        return Flags(can_open: left, can_close: right)

    let open = left and (not right or is_punct(prev))
    let close = right and (not left or is_punct(next))
    return Flags(can_open: open, can_close: close)

def close_bracket(cs: List[Int], nodes: List[Node], i: Int) -> Scan:
    var list = nodes
    let k = last_opener(list.clone())

    if k < 0:
        list.append(Text(value: "]"))
        return Scan(nodes: list, next: i + 1)

    let image = opener_image(list.get(k).clone())
    let active = opener_active(list.get(k).clone())

    if not image and not active:
        list.set(k, Text(value: "["))
        list.append(Text(value: "]"))
        return Scan(nodes: list, next: i + 1)

    if let tail = parse_tail(cs.clone(), i + 1):
        let kids = resolve(list.drop(k + 1))
        var out = list.take(k)
        if not image:
            out = deactivate_openers(out)
        out.append(
            Link(
                image: image, dest: tail.dest, title: tail.title, children: kids
            )
        )
        return Scan(nodes: out, next: tail.end)

    if image:
        list.set(k, Text(value: "!["))
    else:
        list.set(k, Text(value: "["))

    list.append(Text(value: "]"))
    return Scan(nodes: list, next: i + 1)

def deactivate_openers(nodes: List[Node]) -> List[Node]:
    var out: List[Node] = []
    for node in nodes:
        out.append(deactivate(node))
    return out

def deactivate(node: Node) -> Node:
    match node:
        case Opener(image, _):
            if not image:
                return Opener(image: False, active: False)

            return node
        case _:
            return node

def last_opener(nodes: List[Node]) -> Int:
    var k = nodes.length() - 1

    while k >= 0:
        if is_opener(nodes.get(k).clone()):
            return k

        k -= 1

    return -1

def is_opener(node: Node) -> Bool:
    match node:
        case Opener(_, _):
            return True
        case _:
            return False

def opener_image(node: Node) -> Bool:
    match node:
        case Opener(image, _):
            return image
        case _:
            return False

def opener_active(node: Node) -> Bool:
    match node:
        case Opener(_, active):
            return active
        case _:
            return False

def opener_to_text(node: Node) -> Node:
    match node:
        case Opener(image, _):
            if image:
                return Text(value: "![")

            return Text(value: "[")
        case _:
            return node

def parse_tail(cs: List[Int], start: Int) -> Optional[Tail]:
    let n = cs.length()
    if start >= n or cs.get(start) != LPAREN:
        return none

    var p = skip_ws(cs.clone(), start + 1)
    var dest: List[Int] = []

    if p < n and cs.get(p) == LT:
        p += 1

        while p < n and cs.get(p) != GT:
            let c = cs.get(p)
            if c == NL or c == SENT or c == LT:
                return none

            if c == BS and p + 1 < n and is_punct(cs.get(p + 1)):
                dest.append(cs.get(p + 1))
                p += 2
            else:
                dest.append(c)
                p += 1

        if p >= n:
            return none

        p += 1
    else:
        var depth = 0

        while p < n:
            let c = cs.get(p)
            if is_ws(c):
                break

            if c == BS and p + 1 < n and is_punct(cs.get(p + 1)):
                dest.append(cs.get(p + 1))
                p += 2
            else:
                if c == LPAREN:
                    depth += 1

                if c == RPAREN:
                    if depth == 0:
                        break

                    depth -= 1

                dest.append(c)
                p += 1

        if depth != 0:
            return none

    let after_dest = p
    p = skip_ws(cs.clone(), p)

    var title: Optional[String] = none

    if p > after_dest and p < n and cs.get(p) == DQ:
        p += 1

        var t: List[Int] = []
        var closed = False

        while p < n and not closed:
            let c = cs.get(p)

            if c == BS and p + 1 < n and cs.get(p + 1) == DQ:
                t.append(DQ)
                p += 2
            else:
                if c == DQ:
                    closed = True
                else:
                    t.append(c)

                p += 1

        if not closed:
            return none

        title = some(to_str(t))
        p = skip_ws(cs.clone(), p)

    if p >= n or cs.get(p) != RPAREN:
        return none

    return some(Tail(dest: to_str(dest), title: title, end: p + 1))

def skip_ws(cs: List[Int], p: Int) -> Int:
    var k = p
    while k < cs.length() and is_ws(cs.get(k)):
        k += 1
    return k

# Emphasis resolution (rule set from the spec): pairs the closest opener for each closer.
def delim_ch(node: Node) -> String:
    match node:
        case Delim(ch, _, _, _, _):
            return ch
        case _:
            return ""

def delim_count(node: Node) -> Int:
    match node:
        case Delim(_, count, _, _, _):
            return count
        case _:
            return 0

def delim_orig(node: Node) -> Int:
    match node:
        case Delim(_, _, orig, _, _):
            return orig
        case _:
            return 0

def delim_open(node: Node) -> Bool:
    match node:
        case Delim(_, _, _, can_open, _):
            return can_open
        case _:
            return False

def delim_close(node: Node) -> Bool:
    match node:
        case Delim(_, _, _, _, can_close):
            return can_close
        case _:
            return False

def with_count(node: Node, count: Int) -> Node:
    match node:
        case Delim(ch, _, orig, can_open, can_close):
            return Delim(
                ch: ch, count: count, orig: orig, can_open: can_open,
                can_close: can_close
            )
        case _:
            return node

def as_text(node: Node) -> Node:
    match node:
        case Delim(ch, count, _, _, _):
            return Text(value: ch.repeat(count).get())
        case _:
            return node

def pair_ok(op: Node, cl: Node) -> Bool:
    if delim_ch(op.clone()) != delim_ch(cl.clone()):
        return False
    if not delim_open(op.clone()) or delim_count(op.clone()) == 0:
        return False

    if delim_close(op.clone()) or delim_open(cl.clone()):
        let sum = delim_orig(op.clone()) + delim_orig(cl.clone())
        if (
            sum % 3 == 0
            and not (
                delim_orig(op.clone()) % 3 == 0
                and delim_orig(cl.clone()) % 3 == 0
            )
        ):
            return False

    return True

def resolve(nodes: List[Node]) -> List[Node]:
    var list = nodes
    var c = 0

    while c < list.length():
        let closer = list.get(c).clone()

        if delim_close(closer.clone()) and delim_count(closer.clone()) > 0:
            var o = c - 1
            while o >= 0 and not pair_ok(list.get(o).clone(), closer.clone()):
                o -= 1

            if o >= 0:
                let oc = delim_count(list.get(o).clone())
                let cc = delim_count(closer.clone())
                var use = 1
                if oc >= 2 and cc >= 2:
                    use = 2

                var kids: List[Node] = []
                for k in range(o + 1, c):
                    kids.append(as_text(list.get(k).clone()))

                var repl: List[Node] = []
                if oc - use > 0:
                    repl.append(with_count(list.get(o).clone(), oc - use))

                let em = o + repl.length()
                repl.append(Emph(strong: use == 2, children: kids))
                if cc - use > 0:
                    repl.append(with_count(closer.clone(), cc - use))
                list.splice(o, c - o + 1, repl)
                c = em + 1
                continue

        c += 1

    var out: List[Node] = []
    for node in list:
        out.append(as_text(node.clone()))
    return out

def render_nodes(nodes: List[Node]) -> String:
    var out = ""
    for node in nodes:
        out = out.concat(render_node(node.clone()))
    return out

def render_node(node: Node) -> String:
    match node:
        case Text(value):
            return esc(value)
        case Break(hard):
            if hard:
                return "<br />\n"

            return "\n"
        case Code(value):
            return "<code>".concat(esc(value)).concat("</code>")
        case Emph(strong, children):
            if strong:
                return (
                    "<strong>"
                    .concat(render_nodes(children.clone()))
                    .concat("</strong>")
                )

            return "<em>".concat(render_nodes(children.clone())).concat("</em>")
        case Link(image, dest, title, children):
            if image:
                let alt = esc(plain(children.clone()))
                return (
                    "<img src=\""
                    .concat(esc(dest))
                    .concat("\" alt=\"")
                    .concat(alt)
                    .concat("\"")
                    .concat(title_attr(title))
                    .concat(" />")
                )

            return (
                "<a href=\""
                .concat(esc(dest))
                .concat("\"")
                .concat(title_attr(title))
                .concat(">")
                .concat(render_nodes(children.clone()))
                .concat("</a>")
            )
        case _:
            return esc(plain_one(node))

def title_attr(title: Optional[String]) -> String:
    if let t = title:
        return " title=\"".concat(esc(t)).concat("\"")

    return ""

def plain(nodes: List[Node]) -> String:
    var out = ""
    for node in nodes:
        out = out.concat(plain_one(node.clone()))
    return out

def plain_one(node: Node) -> String:
    match node:
        case Text(value):
            return value
        case Code(value):
            return value
        case Break(_):
            return " "
        case Emph(_, children):
            return plain(children)
        case Link(_, _, _, children):
            return plain(children)
        case Delim(ch, count, _, _, _):
            return ch.repeat(count).get()
        case Opener(image, _):
            if image:
                return "!["

            return "["

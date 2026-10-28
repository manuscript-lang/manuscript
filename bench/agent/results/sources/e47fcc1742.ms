from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines

# Hard-break marker placed before a line break in paragraph text (two trailing spaces).
let SENT = "\u{1}"
let PUNCT = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
let DIGITS = "0123456789"

type Blk:
    para: Bool
    html: String
    inner: String
    gap: Bool

type Chunk:
    blk: Blk
    end: Int

type Fence:
    ch: String
    len: Int
    indent: Int
    info: String

type ItemStart:
    ordered: Bool
    kind: String
    num: Int
    width: Int
    text: String
    blank: Bool

type Run:
    ch: String
    n: Int
    orig: Int
    can_open: Bool
    can_close: Bool

type Tail:
    dest: String
    title: Optional[String]
    end: Int

type Node:
    case Text(s: String)
    case Raw(html: String, plain: String)
    case Delim(run: Run)
    case Mark(image: Bool, active: Bool)
    case Link(dest: String, title: Optional[String], children: List[Node], image: Bool)
    case Emph(children: List[Node], strong: Bool)

# ---------- small string and line helpers ----------

def esc(s: String) -> String:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
        "\"", "&quot;"
    )

def first_char(s: String) -> String:
    if s.is_empty():
        return ""

    return s.take(1)

def at(cs: List[String], i: Int) -> String:
    if i < 0 or i >= cs.length():
        return ""

    return cs[i].clone()

def rep(ch: String, count: Int) -> String:
    var out = ""
    var k = 0

    while k < count:
        out += ch
        k += 1

    return out

def min_int(a: Int, b: Int) -> Int:
    if a < b:
        return a

    return b

def is_blank(line: String) -> Bool:
    return line.replace(" ", "") == ""

def indent_of(line: String) -> Int:
    var n = 0
    while n < line.scalar_length() and line.get(n) == " ":
        n += 1
    return n

def rstrip(s: String) -> String:
    var n = s.scalar_length()
    while n > 0 and s.get(n - 1) == " ":
        n -= 1
    return s.take(n)

def trailing_spaces(s: String) -> Int:
    return s.scalar_length() - rstrip(s).scalar_length()

def trim(s: String) -> String:
    return rstrip(s.drop(indent_of(s)))

def is_digit(c: String) -> Bool:
    return c != "" and DIGITS.contains(c)

# ---------- block constructs ----------

def open_fence(line: String) -> Optional[Fence]:
    let ind = indent_of(line)
    if ind > 3:
        return none

    let body = line.drop(ind)
    let ch = first_char(body)
    if ch != "`" and ch != "~":
        return none

    var run = 0
    while first_char(body.drop(run)) == ch:
        run += 1
    if run < 3:
        return none

    let info = trim(body.drop(run))
    if ch == "`" and info.contains("`"):
        return none

    return Fence(ch, run, ind, info)

def is_fence_open(line: String) -> Bool:
    if let _f = open_fence(line):
        return True

    return False

def closes_fence(line: String, f: Fence) -> Bool:
    let ind = indent_of(line)
    if ind > 3:
        return False

    let body = line.drop(ind)
    var run = 0
    while first_char(body.drop(run)) == f.ch:
        run += 1
    return run >= f.len and body.drop(run).replace(" ", "") == ""

def atx_level(line: String) -> Int:
    let ind = indent_of(line)
    if ind > 3:
        return 0

    let body = line.drop(ind)
    var n = 0
    while first_char(body.drop(n)) == "#":
        n += 1
    if n < 1 or n > 6:
        return 0

    let after = first_char(body.drop(n))
    if after == "" or after == " ":
        return n

    return 0

def atx_text(line: String, level: Int) -> String:
    let t = trim(line.drop(indent_of(line)).drop(level))
    let count = t.scalar_length()
    var m = 0
    while m < count and t.get(count - 1 - m) == "#":
        m += 1
    if m > 0 and (m == count or t.get(count - m - 1) == " "):
        return rstrip(t.take(count - m))

    return t

def is_thematic(line: String) -> Bool:
    if indent_of(line) > 3:
        return False

    let s = line.replace(" ", "")
    if s.scalar_length() < 3:
        return False

    let c = first_char(s)
    if c != "-" and c != "*" and c != "_":
        return False

    return s.replace(c, "") == ""

def is_quote_start(line: String) -> Bool:
    let ind = indent_of(line)
    return ind <= 3 and first_char(line.drop(ind)) == ">"

def strip_quote(line: String) -> String:
    var body = line.drop(indent_of(line)).drop(1)
    if body.starts_with(" "):
        body = body.drop(1)
    return body

def list_marker(line: String) -> Optional[ItemStart]:
    let ind = indent_of(line)
    if ind > 3:
        return none

    let body = line.drop(ind)
    let c = first_char(body)
    var kind = c.clone()
    var ordered = False
    var num = 0
    var mlen = 1

    if c != "-" and c != "*" and c != "+":
        var d = 0
        while is_digit(first_char(body.drop(d))):
            d += 1
        if d < 1 or d > 9:
            return none

        let delim = first_char(body.drop(d))
        if delim != "." and delim != ")":
            return none

        kind = delim
        ordered = True
        mlen = d + 1
        num = body.take(d).parse_int().get(0)

    let rest = body.drop(mlen)
    let rc = first_char(rest)
    if rc != "" and rc != " ":
        return none

    let sp = indent_of(rest)
    let marker_end = ind + mlen
    if rest.drop(sp) == "":
        return ItemStart(ordered, kind, num, marker_end + 1, "", True)
    if sp >= 5:
        return ItemStart(ordered, kind, num, marker_end + 1, rest.drop(1), False)

    return ItemStart(ordered, kind, num, marker_end + sp, rest.drop(sp), False)

def same_item(line: String, mark: ItemStart) -> Optional[ItemStart]:
    if is_thematic(line):
        return none

    if let m = list_marker(line):
        if m.kind == mark.kind:
            return m
    return none

def split_cells(line: String) -> List[String]:
    var t = trim(line)
    if t.starts_with("|"):
        t = t.drop(1)

    let count = t.scalar_length()
    if t.ends_with("|") and not (count >= 2 and t.get(count - 2) == "\\"):
        t = t.take(count - 1)

    var cells = List[String]()
    var cur = ""
    var prev = ""

    for c in t.chars():
        if c == "|" and prev != "\\":
            cells.append(trim(cur))
            cur = ""
        else:
            cur += c

        prev = c

    cells.append(trim(cur))
    return cells

def delim_cell(c: String) -> Bool:
    var s = c
    if s.starts_with(":"):
        s = s.drop(1)
    if s.ends_with(":"):
        s = s.take(s.scalar_length() - 1)
    return s != "" and s.replace("-", "") == ""

def is_delim_row(line: String) -> Bool:
    if not line.contains("|"):
        return False

    for c in split_cells(line):
        if not delim_cell(c):
            return False
    return True

def align_of(c: String) -> String:
    let left = c.starts_with(":")
    let right = c.ends_with(":")
    if left and right:
        return "center"
    if left:
        return "left"
    if right:
        return "right"

    return ""

def align_attr(a: String) -> String:
    if a == "":
        return ""

    return " align=\"" + a + "\""

def is_table_start(lines: List[String], i: Int) -> Bool:
    if i + 1 >= lines.length():
        return False
    if not lines[i].contains("|") or not is_delim_row(lines[i + 1]):
        return False

    return split_cells(lines[i]).length() == split_cells(lines[i + 1]).length()

def ends_table(line: String) -> Bool:
    return (
        is_blank(line)
        or is_fence_open(line)
        or atx_level(line) > 0
        or is_thematic(line)
        or is_quote_start(line)
    )

def interrupts(line: String) -> Bool:
    if (
        is_fence_open(line)
        or atx_level(line) > 0
        or is_thematic(line)
        or is_quote_start(line)
    ):
        return True
    if let m = list_marker(line):
        return not m.blank and (not m.ordered or m.num == 1)

    return False

def render_blocks(blocks: List[Blk]) -> String:
    var out = ""
    for b in blocks:
        out += b.html
    return out

def item_body(blocks: List[Blk], tight: Bool) -> String:
    var body = ""

    for b in blocks:
        if tight and b.para:
            body += b.inner
        else:
            if not body.ends_with("\n"):
                body += "\n"
            body += b.html

    return body

def parse_fence(lines: List[String], i: Int, f: Fence) -> Chunk:
    var j = i + 1
    while j < lines.length() and not closes_fence(lines[j], f):
        j += 1

    let content = lines.slice(i + 1, j).get()

    let stop = j + 1 if j < lines.length() else j

    var code = ""
    for c in content:
        code += esc(c.drop(min_int(indent_of(c), f.indent))) + "\n"

    var opening = "<pre><code>"
    if f.info != "":
        opening = "<pre><code class=\"language-" + esc(f.info.split(" ") [0]) + "\">"
    return Chunk(Blk(False, opening + code + "</code></pre>\n", "", False), stop)

def parse_quote(lines: List[String], i: Int) -> Chunk:
    var inner = List[String]()
    var j = i

    while j < lines.length() and is_quote_start(lines[j]):
        inner.append(strip_quote(lines[j]))
        j += 1

    let html = "<blockquote>\n" + render_blocks(parse_blocks(inner)) + "</blockquote>\n"
    return Chunk(Blk(False, html, "", False), j)

def parse_indented(lines: List[String], i: Int) -> Chunk:
    var last = i
    var j = i

    while j < lines.length() and (is_blank(lines[j]) or indent_of(lines[j]) >= 4):
        if not is_blank(lines[j]):
            last = j
        j += 1

    var code = ""
    for k in i..last + 1:
        code += esc(lines[k].drop(min_int(indent_of(lines[k]), 4))) + "\n"
    return Chunk(
        Blk(False, "<pre><code>" + code + "</code></pre>\n", "", False), last + 1
    )

def parse_para(lines: List[String], i: Int) -> Chunk:
    var raw = List[String]()
    raw.append(lines[i].clone())

    var j = i + 1

    while j < lines.length() and not is_blank(lines[j]) and not interrupts(lines[j]):
        raw.append(lines[j].clone())
        j += 1

    var text = ""
    var k = 0

    while k < raw.length():
        var t = raw[k].drop(indent_of(raw[k]))

        if k < raw.length() - 1 and trailing_spaces(t) >= 2:
            t = rstrip(t) + SENT
        else:
            t = rstrip(t)

        if k > 0:
            text += "\n"
        text += t
        k += 1

    let body = inline(text)
    return Chunk(Blk(True, "<p>" + body + "</p>\n", body, False), j)

def parse_table(lines: List[String], i: Int) -> Chunk:
    let head = split_cells(lines[i])
    let delims = split_cells(lines[i + 1])
    var html = "<table>\n<thead>\n<tr>\n"
    var c = 0

    while c < head.length():
        html += (
            "<th"
            + align_attr(align_of(delims[c]))
            + ">"
            + inline(head[c])
            + "</th>\n"
        )
        c += 1

    html += "</tr>\n</thead>\n"

    var body = ""
    var j = i + 2

    while j < lines.length() and not ends_table(lines[j]):
        let cells = split_cells(lines[j])
        body += "<tr>\n"
        c = 0

        while c < head.length():
            var cell = ""
            if c < cells.length():
                cell = cells[c].clone()
            body += (
                "<td"
                + align_attr(align_of(delims[c]))
                + ">"
                + inline(cell)
                + "</td>\n"
            )
            c += 1

        body += "</tr>\n"
        j += 1

    if body != "":
        html += "<tbody>\n" + body + "</tbody>\n"
    html += "</table>\n"
    return Chunk(Blk(False, html, "", False), j)

def parse_list(lines: List[String], start: Int, first: ItemStart) -> Chunk:
    var items = List[List[Blk]]()
    var loose = False
    var mark = first.clone()
    var i = start
    var end = start + 1
    var more = True

    while more:
        var content = List[String]()
        content.append(mark.text.clone())

        var last = i
        var j = i + 1

        while (
            j < lines.length()
            and (is_blank(lines[j]) or indent_of(lines[j]) >= mark.width)
        ):
            if is_blank(lines[j]):
                content.append("")
            else:
                content.append(lines[j].drop(mark.width))
                last = j

            j += 1

        let blocks = parse_blocks(content.slice(0, last - i + 1).get())
        for b in blocks:
            if b.gap:
                loose = True
        items.append(blocks)
        end = last + 1

        var k = last + 1
        while k < lines.length() and is_blank(lines[k]):
            k += 1

        var following: Optional[ItemStart] = none
        if k < lines.length():
            following = same_item(lines[k], mark)

        if let nm = following:
            if k > last + 1:
                loose = True
            mark = nm
            i = k
        else:
            more = False

    var html = "<ul>\n"
    var close = "</ul>\n"

    if first.ordered:
        html = "<ol>\n"
        if first.num != 1:
            html = "<ol start=\"" + first.num.to_string() + "\">\n"
        close = "</ol>\n"

    for blocks in items:
        html += "<li>" + item_body(blocks, not loose) + "</li>\n"
    return Chunk(Blk(False, html + close, "", False), end)

def parse_at(lines: List[String], i: Int) -> Chunk:
    let line = lines[i]
    if let f = open_fence(line):
        return parse_fence(lines, i, f)

    let level = atx_level(line)

    if level > 0:
        let body = inline(atx_text(line, level))
        return Chunk(
            Blk(False, f"<h{level}>" + body + f"</h{level}>\n", "", False), i + 1
        )

    if is_thematic(line):
        return Chunk(Blk(False, "<hr />\n", "", False), i + 1)
    if is_quote_start(line):
        return parse_quote(lines, i)
    if let m = list_marker(line):
        return parse_list(lines, i, m)
    if indent_of(line) >= 4:
        return parse_indented(lines, i)
    if is_table_start(lines, i):
        return parse_table(lines, i)

    return parse_para(lines, i)

def parse_blocks(lines: List[String]) -> List[Blk]:
    var out = List[Blk]()
    var gap = False
    var i = 0

    while i < lines.length():
        if is_blank(lines[i]):
            gap = True
            i += 1
        else:
            let c = parse_at(lines, i)
            out.append(
                Blk(
                    c.blk.para, c.blk.html.clone(), c.blk.inner.clone(),
                    gap and out.length() > 0
                )
            )
            gap = False
            i = c.end

    return out

# ---------- inline: scanning ----------

def is_ws(c: String) -> Bool:
    return c == "" or c == " " or c == "\n" or c == SENT

def is_punct(c: String) -> Bool:
    return c != "" and PUNCT.contains(c)

def count_run(cs: List[String], i: Int, ch: String) -> Int:
    var k = i
    while k < cs.length() and cs[k] == ch:
        k += 1
    return k - i

def find_run(cs: List[String], from: Int, run: Int) -> Int:
    var k = from

    while k < cs.length():
        if cs[k] == "`":
            let r = count_run(cs, k, "`")
            if r == run:
                return k

            k += r
        else:
            k += 1

    return -1

def code_content(cs: List[String], a: Int, b: Int) -> String:
    var s = ""
    var k = a

    while k < b:
        if cs[k] == "\n":
            s += " "
        elif cs[k] != SENT:
            s += cs[k]

        k += 1

    if s.starts_with(" ") and s.ends_with(" ") and s.replace(" ", "") != "":
        s = s.drop(1).take(s.scalar_length() - 2)
    return s

def delim_at(cs: List[String], i: Int, run: Int) -> Run:
    let c = cs[i]
    let prev = at(cs, i - 1)
    let next = at(cs, i + run)
    let left = not is_ws(next) and (not is_punct(next) or is_ws(prev) or is_punct(prev))
    let right = (
        not is_ws(prev)
        and (not is_punct(prev) or is_ws(next) or is_punct(next))
    )
    if c == "_":
        return Run(
            c.clone(), run, run, left and (not right or is_punct(prev)),
            right and (not left or is_punct(next))
        )

    return Run(c.clone(), run, run, left, right)

def mark_image(node: Node) -> Bool:
    match node:
        case Mark(image, _):
            return image
        case _:
            return False

def mark_active(node: Node) -> Bool:
    match node:
        case Mark(_, active):
            return active
        case _:
            return False

def run_at(ns: List[Node], i: Int) -> Optional[Run]:
    match ns[i]:
        case Delim(run):
            return run.clone()
        case _:
            return none

def open_text(image: Bool) -> String:
    if image:
        return "!["

    return "["

def title_attr(title: Optional[String]) -> String:
    if let t = title:
        return " title=\"" + esc(t) + "\""

    return ""

def skip_space(cs: List[String], k: Int) -> Int:
    var j = k
    while j < cs.length() and (cs[j] == " " or cs[j] == "\n" or cs[j] == SENT):
        j += 1
    return j

def parse_tail(cs: List[String], p: Int) -> Optional[Tail]:
    let n = cs.length()
    var k = skip_space(cs, p + 1)
    var dest = ""

    if at(cs, k) == "<":
        k += 1

        while k < n and cs[k] != ">":
            if cs[k] == "\n" or cs[k] == "<":
                return none

            if cs[k] == "\\" and is_punct(at(cs, k + 1)):
                dest += cs[k + 1]
                k += 2
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

            if c == "\\" and is_punct(at(cs, k + 1)):
                dest += cs[k + 1]
                k += 2
            elif is_ws(c):
                break
            elif c == ")" and depth == 0:
                break
            else:
                if c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1

                dest += c
                k += 1

    let before = k
    k = skip_space(cs, k)

    var title: Optional[String] = none

    if k > before and at(cs, k) == "\"":
        var t = ""
        k += 1

        while k < n and cs[k] != "\"":
            if cs[k] == "\\" and at(cs, k + 1) == "\"":
                t += "\""
                k += 2
            else:
                t += cs[k]
                k += 1

        if k >= n:
            return none

        k += 1
        title = t
        k = skip_space(cs, k)

    if at(cs, k) == ")":
        return Tail(dest, title, k + 1)

    return none

def close_bracket(
    cs: List[String],
    var nodes: List[Node],
    var marks: List[Int],
    i: Int
) -> Int:
    if marks.length() == 0:
        nodes.append(Text("]"))
        return i + 1

    let idx = marks[marks.length() - 1]
    marks.pop()

    let image = mark_image(nodes[idx])

    if not mark_active(nodes[idx]):
        nodes[idx] = Text("[")
        nodes.append(Text("]"))
        return i + 1

    if at(cs, i + 1) == "(":
        if let t = parse_tail(cs, i + 1):
            var kids = nodes.slice(idx + 1, nodes.length()).get()
            resolve(var kids)
            nodes.splice(
                idx, nodes.length() - idx,
                [Link(t.dest.clone(), t.title.clone(), kids, image)]
            )
            if not image:
                deactivate_links(var nodes, marks)
            return t.end

    nodes[idx] = Text(open_text(image))
    nodes.append(Text("]"))
    return i + 1

def deactivate_links(var nodes: List[Node], marks: List[Int]) -> Unit:
    var k = marks.length() - 1

    while k >= 0:
        let p = marks[k]

        if not mark_image(nodes[p]):
            if not mark_active(nodes[p]):
                return ()

            nodes[p] = Mark(False, False)

        k -= 1

def scan(cs: List[String]) -> List[Node]:
    var nodes = List[Node]()
    var marks = List[Int]()
    var i = 0

    while i < cs.length():
        let c = cs[i]
        let nx = at(cs, i + 1)

        if c == "\\" and nx == "\n":
            nodes.append(Raw("<br />\n", " "))
            i += 2
        elif c == "\\" and is_punct(nx):
            nodes.append(Text(nx.clone()))
            i += 2
        elif c == SENT:
            nodes.append(Raw("<br />\n", " "))
            i += 1
            if at(cs, i) == "\n":
                i += 1
        elif c == "`":
            let run = count_run(cs, i, "`")
            let close = find_run(cs, i + run, run)

            if close < 0:
                nodes.append(Text(rep("`", run)))
                i += run
            else:
                let code = code_content(cs, i + run, close)
                nodes.append(Raw("<code>" + esc(code) + "</code>", code.clone()))
                i = close + run
        elif c == "*" or c == "_":
            let run = count_run(cs, i, c)
            nodes.append(Delim(delim_at(cs, i, run)))
            i += run
        elif c == "!" and nx == "[":
            marks.append(nodes.length())
            nodes.append(Mark(True, True))
            i += 2
        elif c == "[":
            marks.append(nodes.length())
            nodes.append(Mark(False, True))
            i += 1
        elif c == "]":
            i = close_bracket(cs, var nodes, var marks, i)
        else:
            nodes.append(Text(c.clone()))
            i += 1

    resolve(var nodes)
    return nodes

# ---------- inline: emphasis ----------

def literal(node: Node) -> Node:
    match node:
        case Delim(run):
            return Text(rep(run.ch, run.n))
        case _:
            return node

def mult3_ok(o: Run, c: Run) -> Bool:
    if (o.can_close or c.can_open) and (o.orig + c.orig) % 3 == 0:
        return o.orig % 3 == 0 and c.orig % 3 == 0

    return True

def find_opener(ns: List[Node], i: Int, c: Run) -> Int:
    var k = i - 1

    while k >= 0:
        if let o = run_at(ns, k):
            if o.ch == c.ch and o.can_open and o.n > 0 and mult3_ok(o, c):
                return k
        k -= 1

    return -1

def wrap(var ns: List[Node], j: Int, i: Int, use: Int, o: Run, c: Run) -> Unit:
    var inner = List[Node]()
    var k = j + 1

    while k < i:
        inner.append(literal(ns[k].clone()))
        k += 1

    var repl = List[Node]()
    if o.n - use > 0:
        repl.append(
            Delim(
                Run(
                    o.ch.clone(), o.n - use, o.orig, o.can_open, o.can_close
                )
            )
        )
    repl.append(Emph(inner, use == 2))
    if c.n - use > 0:
        repl.append(
            Delim(
                Run(
                    c.ch.clone(), c.n - use, c.orig, c.can_open, c.can_close
                )
            )
        )
    ns.splice(j, i - j + 1, repl)

def resolve_at(var ns: List[Node], i: Int) -> Int:
    if let c = run_at(ns, i):
        if c.can_close and c.n > 0:
            let j = find_opener(ns, i, c)

            if j >= 0:
                if let o = run_at(ns, j):
                    let use = 2 if o.n >= 2 and c.n >= 2 else 1

                    let emph_at = j + 1 if o.n - use > 0 else j

                    wrap(var ns, j, i, use, o, c)
                    return emph_at + 1

    return i + 1

def resolve(var ns: List[Node]) -> Unit:
    var i = 0
    while i < ns.length():
        i = resolve_at(var ns, i)

# ---------- inline: rendering ----------

def plain_node(node: Node) -> String:
    match node:
        case Text(s):
            return s.replace("\n", " ")
        case Raw(_, text):
            return text
        case Delim(run):
            return rep(run.ch, run.n)
        case Mark(image, _):
            return open_text(image)
        case Emph(children, _):
            return plain(children)
        case Link(_, _, children, _):
            return plain(children)

def plain(ns: List[Node]) -> String:
    var out = ""
    for n in ns:
        out += plain_node(n)
    return out

def render_node(node: Node) -> String:
    match node:
        case Text(s):
            return esc(s)
        case Raw(html, _):
            return html
        case Delim(run):
            return esc(rep(run.ch, run.n))
        case Mark(image, _):
            return esc(open_text(image))
        case Emph(children, strong):
            if strong:
                return "<strong>" + render(children) + "</strong>"

            return "<em>" + render(children) + "</em>"
        case Link(dest, title, children, image):
            if image:
                return (
                    "<img src=\""
                    + esc(dest)
                    + "\" alt=\""
                    + esc(plain(children))
                    + "\""
                    + title_attr(title)
                    + " />"
                )

            return (
                "<a href=\""
                + esc(dest)
                + "\""
                + title_attr(title)
                + ">"
                + render(children)
                + "</a>"
            )

def render(ns: List[Node]) -> String:
    var out = ""
    for n in ns:
        out += render_node(n)
    return out

def inline(text: String) -> String:
    return render(scan(text.chars()))

# ---------- entry point ----------

export def main() -> Int:
    let lines = read_lines(stdin()).get()
    var out = ""
    for b in parse_blocks(lines):
        out += b.html
    stdout().write(out).get()
    return 0

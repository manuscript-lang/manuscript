# Markdown subset to HTML converter (see TASK.md).

import read_line, stdin, stdout from "@std/io.ms"

# Sentinel for a two-space hard break inside paragraph text; never occurs in input.
let HB = "§"
let PUNCT = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`\{|\}~"
let DIGITS = "0123456789"

type Blk:
    kind: Int = 0
    text: String = ""
    lang: String = ""
    level: Int = 0
    ordered: Bool = false
    loose: Bool = false
    children: List[Blk] = List[Blk]()
    items: List[List[Blk]] = List[List[Blk]]()
    aligns: List[Int] = List[Int]()
    head: List[String] = List[String]()
    rows: List[List[String]] = List[List[String]]()

type Parsed:
    blocks: List[Blk]
    loose: Bool

type Step:
    blk: Blk
    next: Int

type Marker:
    ok: Bool
    ordered: Bool
    delim: String
    num: Int
    empty: Bool
    w: Int

type Tail:
    ok: Bool
    dest: String
    title: String
    hasTitle: Bool
    end: Int

type Node:
    kind: Int = 0
    text: String = ""
    ch: String = ""
    count: Int = 0
    orig: Int = 0
    canOpen: Bool = false
    canClose: Bool = false
    image: Bool = false
    active: Bool = true
    strong: Bool = false
    dest: String = ""
    title: String = ""
    hasTitle: Bool = false
    children: List[Node] = List[Node]()

type Joined:
    nodes: List[Node]
    next: Int

# ---------- string helpers ----------

fn joinc(cs: List[String], a: Int, b: Int) String:
    var s = ""
    var k = a

    while k < b:
        s = s + cs[k]
        k += 1

    return s

# Substring from index a (in scalars) to the end.
fn sub(s: String, a: Int) String:
    let cs = s.chars()
    return joinc(cs, a, cs.length())

fn esc(s: String) String:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
        "\"", "&quot;"
    )

fn repeatStr(s: String, n: Int) String:
    var out = ""
    var k = 0

    while k < n:
        out = out + s
        k += 1

    return out

fn isPunct(c: String) Bool:
    return c != "" and PUNCT.contains(c)

fn isWs(c: String) Bool:
    return c == " " or c == "\n" or c == HB

# Number of leading spaces.
fn lead(s: String) Int:
    let cs = s.chars()
    var n = 0
    while n < cs.length() and cs[n] == " ":
        n += 1
    return n

# Number of consecutive copies of c starting at p.
fn runAt(cs: List[String], p: Int, c: String) Int:
    var n = 0
    while p + n < cs.length() and cs[p + n] == c:
        n += 1
    return n

fn isBlank(s: String) Bool:
    return s.trim() == ""

fn isThematic(line: String) Bool:
    let t = line.replace(" ", "")
    if t.length() < 3:
        return false

    let cs = t.chars()
    let c = cs[0]
    if c != "-" and c != "*" and c != "_":
        return false

    return runAt(cs, 0, c) == cs.length()

# Fence length of a line body (already left-trimmed), or 0 when it is not a fence opener.
fn fenceOpen(body: String) Int:
    let cs = body.chars()
    if cs.length() == 0:
        return 0

    let c = cs[0]
    if c != "`" and c != "~":
        return 0

    let f = runAt(cs, 0, c)
    if f < 3:
        return 0
    if c == "`" and sub(body, f).contains("`"):
        return 0

    return f

# ATX heading level of a left-trimmed body, or 0.
fn atxLevel(body: String) Int:
    let cs = body.chars()
    let h = runAt(cs, 0, "#")
    if h < 1 or h > 6:
        return 0
    if h == cs.length() or cs[h] == " ":
        return h

    return 0

fn isQuoteLine(line: String) Bool:
    return lead(line) <= 3 and line.trim_start().starts_with(">")

# Rules 1-4 tested for a line on its own (indent <= 3).
fn interruptsStruct(line: String) Bool:
    if lead(line) > 3:
        return false

    let body = line.trim_start()
    if fenceOpen(body) > 0:
        return true
    if atxLevel(body) > 0:
        return true
    if isThematic(line):
        return true

    return body.starts_with(">")

fn parseMarker(line: String) Marker:
    let none = Marker(ok: false, ordered: false, delim: "", num: 0, empty: false, w: 0)
    let ind = lead(line)
    if ind > 3:
        return none

    let cs = line.chars()
    let n = cs.length()
    let p = ind
    if p >= n:
        return none

    let c = cs[p]
    var mlen = 0
    var ordered = false
    var num = 0
    var delim = c.clone()

    if c == "-" or c == "*" or c == "+":
        mlen = 1
    else:
        var d = 0
        while p + d < n and DIGITS.contains(cs[p + d]) and d < 10:
            d += 1
        if d < 1 or d > 9 or p + d >= n:
            return none
        if cs[p + d] != "." and cs[p + d] != ")":
            return none

        ordered = true
        mlen = d + 1
        delim = cs[p + d].clone()

        var k = 0

        while k < d:
            num = num * 10 + DIGITS.index_of(cs[p + k]).get(0)
            k += 1

    let q = p + mlen
    if q < n and cs[q] != " ":
        return none

    var sp = 0
    var r = q

    while r < n and cs[r] == " ":
        sp += 1
        r += 1

    let empty = r >= n
    let m = p + mlen
    var w = m + sp
    if empty or sp >= 5:
        w = m + 1
    return Marker(
        ok: true, ordered: ordered, delim: delim, num: num, empty: empty, w: w
    )

fn isDelimCell(c: String) Bool:
    let cs = c.chars()
    var a = 0
    var b = cs.length()
    if b > a and cs[a] == ":":
        a = 1
    if b > a and cs[b - 1] == ":":
        b = b - 1
    if b <= a:
        return false

    return runAt(cs, a, "-") == b - a

fn alignOf(c: String) Int:
    let cs = c.chars()
    let n = cs.length()
    let lead = n > 0 and cs[0] == ":"
    let trail = n > 1 and cs[n - 1] == ":"
    if lead and trail:
        return 2
    if lead:
        return 1
    if trail:
        return 3

    return 0

# Splits a table row into trimmed cells.
fn splitRow(line: String) List[String]:
    let cs = line.trim().chars()
    let n = cs.length()
    var a = 0
    var b = n
    if b > 0 and cs[0] == "|":
        a = 1
    if b > a and cs[b - 1] == "|" and not (b - 2 >= 0 and cs[b - 2] == "\\"):
        b = b - 1

    var cells = List[String]()
    var cur = ""
    var k = a

    while k < b:
        let c = cs[k]

        if c == "|" and not (k > 0 and cs[k - 1] == "\\"):
            cells.append(cur.trim())
            cur = ""
        else:
            cur = cur + c

        k += 1

    cells.append(cur.trim())
    return cells

fn isDelimRow(line: String) Bool:
    if not line.contains("|"):
        return false

    for c in splitRow(line):
        if not isDelimCell(c):
            return false
    return true

fn mkPara(text: String) Blk:
    return Blk(kind: 5, text: text)

# ---------- block parsing ----------

fn parseBlocks(lines: List[String]) Parsed:
    var blocks = List[Blk]()
    var loose = false
    var sawBlank = false
    var i = 0
    let n = lines.length()

    while i < n:
        if isBlank(lines[i]):
            sawBlank = true
            i += 1
        else:
            if sawBlank and blocks.length() > 0:
                loose = true
            sawBlank = false

            let st = parseOne(lines, i)
            blocks.append(st.blk)
            i = st.next

    return Parsed(blocks: blocks, loose: loose)

fn parseOne(lines: List[String], i: Int) Step:
    let line = lines[i]
    let ind = lead(line)
    let body = line.trim_start()
    let n = lines.length()

    if ind <= 3:
        let f = fenceOpen(body)
        if f > 0:
            return parseFence(lines, i, ind, f)

        let h = atxLevel(body)

        if h > 0:
            var content = sub(body, h).trim()
            let ccs = content.chars()
            let cn = ccs.length()
            var r = 0
            while r < cn and ccs[cn - 1 - r] == "#":
                r += 1
            if r > 0 and (r == cn or ccs[cn - r - 1] == " "):
                content = joinc(ccs, 0, cn - r).trim_end()
            return Step(blk: Blk(kind: 1, text: content, level: h), next: i + 1)

        if isThematic(line):
            return Step(blk: Blk(kind: 2), next: i + 1)
        if body.starts_with(">"):
            return parseQuote(lines, i)

        let m = parseMarker(line)
        if m.ok:
            return parseList(lines, i, m)

        if i + 1 < n and line.contains("|") and isDelimRow(lines[i + 1]):
            if splitRow(line).length() == splitRow(lines[i + 1]).length():
                return parseTable(lines, i)

    if ind >= 4:
        return parseIndented(lines, i)

    return parsePara(lines, i)

fn parseFence(lines: List[String], i: Int, ind: Int, f: Int) Step:
    let first = lines[i].trim_start()
    let c = first.get(0)
    let info = sub(first, f).trim()
    var lang = ""
    if info != "":
        lang = info.split(" ").get(0)

    let n = lines.length()
    var body = ""
    var j = i + 1
    var closed = false

    while j < n:
        let l = lines[j]

        if lead(l) <= 3:
            let lb = l.trim_start()
            let r = runAt(lb.chars(), 0, c)

            if r >= f and sub(lb, r).trim() == "":
                closed = true
                break

        let k = if lead(l) < ind: lead(l) else: ind
        body = body + sub(l, k) + "\n"
        j += 1

    var next = n
    if closed:
        next = j + 1
    return Step(blk: Blk(kind: 0, text: body, lang: lang), next: next)

fn parseQuote(lines: List[String], i: Int) Step:
    var inner = List[String]()
    var j = i

    while j < lines.length() and isQuoteLine(lines[j]):
        let body = lines[j].trim_start()
        var rest = sub(body, 1)
        if rest.starts_with(" "):
            rest = sub(rest, 1)
        inner.append(rest)
        j += 1

    let p = parseBlocks(inner)
    return Step(blk: Blk(kind: 3, children: p.blocks), next: j)

fn parseIndented(lines: List[String], i: Int) Step:
    let n = lines.length()
    var last = i
    var j = i

    while j < n:
        let l = lines[j]

        if isBlank(l):
            j += 1
        else if lead(l) >= 4:
            last = j
            j += 1
        else:
            break

    var body = ""
    var k = i

    while k <= last:
        let l = lines[k]
        let r = if lead(l) < 4: lead(l) else: 4
        body = body + sub(l, r) + "\n"
        k += 1

    return Step(blk: Blk(kind: 0, text: body), next: last + 1)

fn parseList(lines: List[String], i: Int, m0: Marker) Step:
    let n = lines.length()
    var items = List[List[Blk]]()
    var anyItemLoose = false
    var listLoose = false
    var cur = i
    var m = m0.clone()
    var go = true

    while go:
        let w = m.w
        var content = List[String]()
        content.append(sub(lines[cur], w))

        var last = cur
        var j = cur + 1

        while j < n:
            let l = lines[j]

            if isBlank(l):
                j += 1
            else if lead(l) >= w:
                var k = last + 1

                while k < j:
                    content.append("")
                    k += 1

                content.append(sub(l, w))
                last = j
                j += 1
            else:
                break

        let p = parseBlocks(content)
        items.append(p.blocks)
        if p.loose:
            anyItemLoose = true
        go = false

        if j < n:
            let nm = parseMarker(lines[j])

            if (
                nm.ok
                and not isThematic(lines[j])
                and nm.ordered == m0.ordered
                and nm.delim == m0.delim
            ):
                if j > last + 1:
                    listLoose = true
                cur = j
                m = nm
                go = true

        if not go:
            return Step(
                blk: Blk(
                    kind: 4, ordered: m0.ordered, loose: listLoose or anyItemLoose,
                    level: m0.num, items: items
                ),
                next: j
            )

    return Step(blk: Blk(kind: 4), next: n)

fn parseTable(lines: List[String], i: Int) Step:
    let head = splitRow(lines[i])
    let delims = splitRow(lines[i + 1])
    let h = head.length()
    var aligns = List[Int]()
    for c in delims:
        aligns.append(alignOf(c))

    var rows = List[List[String]]()
    var j = i + 2

    while j < lines.length():
        let l = lines[j]
        if isBlank(l) or interruptsStruct(l):
            break

        let cells = splitRow(l)
        var row = List[String]()
        var k = 0

        while k < h:
            row.append(cells.get(k, ""))
            k += 1

        rows.append(row)
        j += 1

    return Step(blk: Blk(kind: 6, head: head, aligns: aligns, rows: rows), next: j)

fn interruptsPara(line: String) Bool:
    if interruptsStruct(line):
        return true

    let m = parseMarker(line)
    return m.ok and not m.empty and (not m.ordered or m.num == 1)

fn parsePara(lines: List[String], i: Int) Step:
    let n = lines.length()
    var raw = List[String]()
    var j = i

    while j < n:
        let l = lines[j]
        if j > i and (isBlank(l) or interruptsPara(l)):
            break

        raw.append(l.trim_start())
        j += 1

    var text = ""
    let m = raw.length()
    var k = 0

    while k < m:
        var s = raw[k].clone()

        if k == m - 1:
            s = s.trim_end()
        else if s.ends_with("  "):
            s = s.trim_end() + HB
        else:
            s = s.trim_end()

        if k > 0:
            text = text + "\n"
        text = text + s
        k += 1

    return Step(blk: mkPara(text), next: j)

# ---------- block rendering ----------

fn renderBlocks(blocks: List[Blk]) String:
    var out = ""
    for b in blocks:
        out = out + renderBlock(b)
    return out

fn alignAttr(a: Int) String:
    if a == 1:
        return " align=\"left\""
    if a == 2:
        return " align=\"center\""
    if a == 3:
        return " align=\"right\""

    return ""

fn renderTable(b: Blk) String:
    var out = "<table>\n<thead>\n<tr>\n"
    var k = 0

    while k < b.head.length():
        out = (
            out
            + "<th"
            + alignAttr(b.aligns.get(k, 0))
            + ">"
            + inline(b.head[k])
            + "</th>\n"
        )
        k += 1

    out = out + "</tr>\n</thead>\n"

    if b.rows.length() > 0:
        out = out + "<tbody>\n"

        for row in b.rows:
            out = out + "<tr>\n"

            var c = 0

            while c < row.length():
                out = (
                    out
                    + "<td"
                    + alignAttr(b.aligns.get(c, 0))
                    + ">"
                    + inline(row[c])
                    + "</td>\n"
                )
                c += 1

            out = out + "</tr>\n"

        out = out + "</tbody>\n"

    return out + "</table>\n"

fn renderItem(children: List[Blk], tight: Bool) String:
    var body = ""

    for c in children:
        if c.kind == 5 and tight:
            body = body + inline(c.text)
        else:
            if body == "" or not body.ends_with("\n"):
                body = body + "\n"
            body = body + renderBlock(c)

    return body

fn renderList(b: Blk) String:
    var out = "<ul>\n"

    if b.ordered:
        out = "<ol>\n"
        if b.level != 1:
            out = "<ol start=\"{b.level}\">\n"

    for item in b.items:
        out = out + "<li>" + renderItem(item, not b.loose) + "</li>\n"
    if b.ordered:
        return out + "</ol>\n"

    return out + "</ul>\n"

fn renderBlock(b: Blk) String:
    if b.kind == 0:
        var cls = ""
        if b.lang != "":
            cls = " class=\"language-" + esc(b.lang) + "\""
        return "<pre><code" + cls + ">" + esc(b.text) + "</code></pre>\n"

    if b.kind == 1:
        return "<h{b.level}>" + inline(b.text) + "</h{b.level}>\n"
    if b.kind == 2:
        return "<hr />\n"
    if b.kind == 3:
        return "<blockquote>\n" + renderBlocks(b.children) + "</blockquote>\n"
    if b.kind == 4:
        return renderList(b)
    if b.kind == 5:
        return "<p>" + inline(b.text) + "</p>\n"

    return renderTable(b)

# ---------- inline processing ----------

fn nText(s: String) Node:
    return Node(kind: 0, text: s)

fn nDelim(c: String, count: Int, co: Bool, cc: Bool) Node:
    return Node(kind: 1, ch: c, count: count, orig: count, canOpen: co, canClose: cc)

fn delimWith(d: Node, count: Int) Node:
    return Node(
        kind: 1, ch: d.ch, count: count, orig: d.orig, canOpen: d.canOpen,
        canClose: d.canClose
    )

fn nOpener(image: Bool, active: Bool) Node:
    return Node(kind: 6, image: image, active: active)

fn openerText(image: Bool) String:
    if image:
        return "!["

    return "["

fn nBr() Node:
    return Node(kind: 5)

fn nCode(s: String) Node:
    return Node(kind: 4, text: s)

fn nEmph(children: List[Node], strong: Bool) Node:
    return Node(kind: 2, strong: strong, children: children)

fn nLink(
    children: List[Node],
    dest: String,
    title: String,
    hasTitle: Bool,
    image: Bool
) Node:
    return Node(
        kind: 3, children: children, dest: dest, title: title, hasTitle: hasTitle,
        image: image
    )

fn failTail() Tail:
    return Tail(ok: false, dest: "", title: "", hasTitle: false, end: 0)

# Inline link tail starting just after "(".
fn parseTail(cs: List[String], p0: Int) Tail:
    let n = cs.length()
    var p = p0
    while p < n and isWs(cs[p]):
        p += 1

    var dest = ""

    if p < n and cs[p] == "<":
        var q = p + 1
        var buf = ""
        var found = false

        while q < n:
            let c = cs[q]

            if c == ">":
                found = true
                break

            if c == "\n" or c == "<":
                break

            if c == "\\" and q + 1 < n and isPunct(cs[q + 1]):
                buf = buf + cs[q + 1]
                q += 2
            else:
                buf = buf + c
                q += 1

        if not found:
            return failTail()

        dest = buf
        p = q + 1
    else:
        var buf = ""
        var depth = 0
        var q = p

        while q < n:
            let c = cs[q]
            if isWs(c):
                break

            if c == "\\" and q + 1 < n and isPunct(cs[q + 1]):
                buf = buf + cs[q + 1]
                q += 2
                continue

            if c == "(":
                depth += 1
            else if c == ")":
                if depth == 0:
                    break

                depth -= 1

            buf = buf + c
            q += 1

        dest = buf
        p = q

    var pos = p
    var p2 = p
    while p2 < n and isWs(cs[p2]):
        p2 += 1

    var title = ""
    var hasTitle = false

    if p2 > p and p2 < n and cs[p2] == "\"":
        var q = p2 + 1
        var buf = ""
        var closed = false

        while q < n:
            let c = cs[q]

            if c == "\\" and q + 1 < n and cs[q + 1] == "\"":
                buf = buf + "\""
                q += 2
            else if c == "\"":
                closed = true
                break
            else:
                buf = buf + c
                q += 1

        if not closed:
            return failTail()

        title = buf
        hasTitle = true
        pos = q + 1

    while pos < n and isWs(cs[pos]):
        pos += 1
    if pos < n and cs[pos] == ")":
        return Tail(
            ok: true, dest: dest, title: title, hasTitle: hasTitle, end: pos + 1
        )

    return failTail()

fn lastOpener(nodes: List[Node]) Int:
    var k = nodes.length() - 1

    while k >= 0:
        if nodes[k].kind == 6:
            return k

        k -= 1

    return -1

fn findRun(cs: List[String], from: Int, run: Int) Int:
    var j = from

    while j < cs.length():
        if cs[j] == "`":
            let len = runAt(cs, j, "`")
            if len == run:
                return j

            j += len
        else:
            j += 1

    return -1

fn codeContent(cs: List[String], a: Int, b: Int) String:
    var s = ""
    var k = a

    while k < b:
        let c = cs[k]

        if c == "\n":
            s = s + " "
        else if c != HB:
            s = s + c

        k += 1

    let sc = s.chars()
    let m = sc.length()
    if m >= 2 and sc[0] == " " and sc[m - 1] == " " and s.trim() != "":
        return joinc(sc, 1, m - 1)

    return s

# Builds the inline node list for a paragraph, heading, or cell.
fn scan(text: String) List[Node]:
    let cs = text.chars()
    let n = cs.length()
    var nodes = List[Node]()
    var i = 0

    while i < n:
        let c = cs[i]

        if c == "\\":
            if i + 1 < n and cs[i + 1] == "\n":
                nodes.append(nBr())
                i += 2
            else if i + 1 < n and isPunct(cs[i + 1]):
                nodes.append(nText(cs[i + 1].clone()))
                i += 2
            else:
                nodes.append(nText("\\"))
                i += 1
        else if c == HB and i + 1 < n and cs[i + 1] == "\n":
            nodes.append(nBr())
            i += 2
        else if c == "`":
            let run = runAt(cs, i, "`")
            let close = findRun(cs, i + run, run)

            if close >= 0:
                nodes.append(nCode(codeContent(cs, i + run, close)))
                i = close + run
            else:
                nodes.append(nText(joinc(cs, i, i + run)))
                i += run
        else if c == "*" or c == "_":
            let run = runAt(cs, i, c)
            let pc = if i > 0: cs[i - 1].clone() else: " "
            let nc = if i + run < n: cs[i + run].clone() else: " "
            let lf = (not isWs(nc)) and ((not isPunct(nc)) or isWs(pc) or isPunct(pc))
            let rf = (not isWs(pc)) and ((not isPunct(pc)) or isWs(nc) or isPunct(nc))
            var co = lf
            var cc = rf

            if c == "_":
                co = lf and ((not rf) or isPunct(pc))
                cc = rf and ((not lf) or isPunct(nc))

            nodes.append(nDelim(c.clone(), run, co, cc))
            i += run
        else if c == "!" and i + 1 < n and cs[i + 1] == "[":
            nodes.append(nOpener(true, true))
            i += 2
        else if c == "[":
            nodes.append(nOpener(false, true))
            i += 1
        else if c == "]":
            let k = lastOpener(nodes)

            if k < 0:
                nodes.append(nText("]"))
                i += 1
            else:
                var tail = failTail()
                if nodes[k].active and i + 1 < n and cs[i + 1] == "(":
                    tail = parseTail(cs, i + 2)

                if tail.ok:
                    nodes = makeLink(var nodes, k, tail.clone())
                    i = tail.end
                else:
                    nodes[k] = nText(openerText(nodes[k].image))
                    nodes.append(nText("]"))
                    i += 1
        else:
            nodes.append(nText(c.clone()))
            i += 1

    return nodes

# Replaces the opener at k and the nodes after it with a link or image node.
fn makeLink(var nodes: List[Node], k: Int, t: Tail) List[Node]:
    let image = nodes[k].image
    var children = List[Node]()
    var q = k + 1

    while q < nodes.length():
        children.append(nodes[q].clone())
        q += 1

    let inner = resolve(var children)
    var out = List[Node]()
    var p = 0

    while p < k:
        if not image and nodes[p].kind == 6 and not nodes[p].image:
            out.append(nOpener(false, false))
        else:
            out.append(nodes[p].clone())

        p += 1

    out.append(nLink(inner, t.dest, t.title, t.hasTitle, image))
    return out

fn findOpener(nodes: List[Node], c: Int) Int:
    let cl = nodes[c]
    var j = c - 1

    while j >= 0:
        let o = nodes[j]

        if o.kind == 1 and o.ch == cl.ch and o.canOpen and o.count > 0:
            let blocked = (
                (o.canClose or cl.canOpen)
                and ((o.orig + cl.orig) % 3 == 0)
                and not (o.orig % 3 == 0 and cl.orig % 3 == 0)
            )
            if not blocked:
                return j

        j -= 1

    return -1

fn joinEmph(nodes: List[Node], f: Int, c: Int) Joined:
    let amount = if nodes[f].count >= 2 and nodes[c].count >= 2: 2 else: 1
    let oLeft = nodes[f].count - amount
    let cLeft = nodes[c].count - amount
    var inner = List[Node]()
    var k = f + 1

    while k < c:
        let x = nodes[k]

        if x.kind == 1:
            inner.append(nText(repeatStr(x.ch, x.count)))
        else:
            inner.append(x.clone())

        k += 1

    var out = List[Node]()
    k = 0

    while k < f:
        out.append(nodes[k].clone())
        k += 1

    if oLeft > 0:
        out.append(delimWith(nodes[f].clone(), oLeft))
    out.append(nEmph(inner, amount == 2))
    if cLeft > 0:
        out.append(delimWith(nodes[c].clone(), cLeft))
    k = c + 1

    while k < nodes.length():
        out.append(nodes[k].clone())
        k += 1

    var next = f + 1
    if oLeft > 0:
        next = f + 2
    return Joined(nodes: out, next: next)

# Emphasis resolution over one node list (the paragraph, or a link's children).
fn resolve(var nodes: List[Node]) List[Node]:
    var i = 0

    while i < nodes.length():
        if nodes[i].kind == 1 and nodes[i].canClose and nodes[i].count > 0:
            let f = findOpener(nodes, i)

            if f >= 0:
                let j = joinEmph(nodes, f, i)
                nodes = j.nodes
                i = j.next
            else:
                i += 1
        else:
            i += 1

    return nodes.clone()

fn plain(nodes: List[Node]) String:
    var out = ""

    for x in nodes:
        if x.kind == 0:
            out = out + x.text.replace("\n", " ")
        else if x.kind == 1:
            out = out + repeatStr(x.ch, x.count)
        else if x.kind == 2 or x.kind == 3:
            out = out + plain(x.children)
        else if x.kind == 4:
            out = out + x.text
        else if x.kind == 5:
            out = out + " "
        else:
            out = out + openerText(x.image)

    return out

fn renderNodes(nodes: List[Node]) String:
    var out = ""
    for x in nodes:
        out = out + renderNode(x)
    return out

fn renderNode(x: Node) String:
    if x.kind == 0:
        return esc(x.text)
    if x.kind == 1:
        return repeatStr(x.ch, x.count)

    if x.kind == 2:
        if x.strong:
            return "<strong>" + renderNodes(x.children) + "</strong>"

        return "<em>" + renderNodes(x.children) + "</em>"

    if x.kind == 3:
        var titleAttr = ""
        if x.hasTitle:
            titleAttr = " title=\"" + esc(x.title) + "\""
        if x.image:
            return (
                "<img src=\""
                + esc(x.dest)
                + "\" alt=\""
                + esc(plain(x.children))
                + "\""
                + titleAttr
                + " />"
            )

        return (
            "<a href=\""
            + esc(x.dest)
            + "\""
            + titleAttr
            + ">"
            + renderNodes(x.children)
            + "</a>"
        )

    if x.kind == 4:
        return "<code>" + esc(x.text) + "</code>"
    if x.kind == 5:
        return "<br />\n"

    return openerText(x.image)

fn inline(text: String) String:
    var parts = scan(text)
    return renderNodes(resolve(var parts))

# ---------- entry point ----------

export fn main() Int:
    var lines = List[String]()
    let input = stdin()

    while true:
        let next = read_line(input).get()

        if let line = next:
            lines.append(line)
        else:
            break

    let p = parseBlocks(lines)
    stdout().write(renderBlocks(p.blocks)).get()
    return 0

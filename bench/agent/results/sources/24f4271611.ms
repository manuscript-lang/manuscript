import stdout from "@std/io/io.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

// ---------- records ----------

type Block:
    kind: Int = 0
    blank: Bool = false
    text: String = ""
    level: Int = 0
    ordered: Bool = false
    loose: Bool = false
    lines: List[String] = List[String]()
    kids: List[Block] = List[Block]()
    items: List[List[Block]] = List[List[Block]]()
    aligns: List[String] = List[String]()
    head: List[String] = List[String]()
    rows: List[List[String]] = List[List[String]]()

type Step:
    blk: Block = Block()
    stop: Int = 0

type Fence:
    ok: Bool = false
    fc: String = ""
    n: Int = 0
    ind: Int = 0
    info: String = ""

type Marker:
    ok: Bool = false
    ordered: Bool = false
    mk: String = ""
    num: Int = 0
    m: Int = 0
    w: Int = 0
    empty: Bool = false

type Atx:
    ok: Bool = false
    level: Int = 0
    text: String = ""

type Node:
    kind: Int = 0
    text: String = ""
    dc: String = ""
    count: Int = 0
    orig: Int = 0
    can_open: Bool = false
    can_close: Bool = false
    active: Bool = true
    image: Bool = false
    dest: String = ""
    title: String = ""
    has_title: Bool = false
    strong: Bool = false
    kids: List[Node] = List[Node]()

type Tail:
    ok: Bool = false
    dest: String = ""
    title: String = ""
    has_title: Bool = false
    stop: Int = 0

// ---------- small helpers ----------

fn sent() String:
    return "\u{2}"

fn punct() String:
    return "!\"#$%&'()*+,-./:;<=>?@[\\]^_`\{|\}~"

fn digits() String:
    return "0123456789"

fn slen(s: String) Int:
    return s.scalar_length()

fn cat(s: String, i: Int) String:
    return s.get(i, "")

fn sub(s: String, a: Int, b: Int) String:
    var lo = a
    var hi = b
    let n = slen(s)
    if hi > n:
        hi = n
    if lo < 0:
        lo = 0
    if lo >= hi:
        return ""
    return s.slice_scalars(lo, hi).get("")

fn dropn(s: String, a: Int) String:
    return sub(s, a, slen(s))

fn indent_of(s: String) Int:
    let n = slen(s)
    var i = 0
    while i < n and cat(s, i) == " ":
        i += 1
    return i

fn is_blank(s: String) Bool:
    return indent_of(s) == slen(s)

fn rtrim_sp(s: String) String:
    var k = slen(s)
    while k > 0 and cat(s, k - 1) == " ":
        k -= 1
    return sub(s, 0, k)

fn trim_sp(s: String) String:
    return rtrim_sp(dropn(s, indent_of(s)))

fn count_run(s: String, start: Int, c: String) Int:
    let n = slen(s)
    var k = 0
    while start + k < n and cat(s, start + k) == c:
        k += 1
    return k

fn strip_up_to(l: String, k: Int) String:
    let ind = indent_of(l)
    let m = if ind < k: ind else: k
    return dropn(l, m)

fn esc(s: String) String:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

fn isspc(c: String) Bool:
    return c == " " or c == "\n" or c == sent()

fn wsc(c: String) Bool:
    return c == " " or c == "\n" or c == sent()

fn punctc(c: String) Bool:
    return c != "" and punct().contains(c)

fn repeat_str(s: String, k: Int) String:
    var out = ""
    var q = 0
    while q < k:
        out += s
        q += 1
    return out

// ---------- block-level recognizers ----------

fn fence_open(line: String) Fence:
    let ind = indent_of(line)
    if ind > 3:
        return Fence()
    let c = cat(line, ind)
    if c != "`" and c != "~":
        return Fence()
    let k = count_run(line, ind, c)
    if k < 3:
        return Fence()
    let info = trim_sp(dropn(line, ind + k))
    if c == "`" and info.contains("`"):
        return Fence()
    return Fence(ok: true, fc: c, n: k, ind: ind, info: info)

fn is_fence_close(line: String, f: Fence) Bool:
    let ind = indent_of(line)
    if ind > 3:
        return false
    let k = count_run(line, ind, f.fc)
    if k < f.n:
        return false
    return is_blank(dropn(line, ind + k))

fn atx_of(line: String) Atx:
    let ind = indent_of(line)
    if ind > 3:
        return Atx()
    let k = count_run(line, ind, "#")
    if k < 1 or k > 6:
        return Atx()
    let after = ind + k
    if after < slen(line) and cat(line, after) != " ":
        return Atx()
    var t = trim_sp(dropn(line, after))
    let tl = slen(t)
    var m = 0
    while m < tl and cat(t, tl - 1 - m) == "#":
        m += 1
    if m > 0 and (m == tl or cat(t, tl - m - 1) == " "):
        t = trim_sp(sub(t, 0, tl - m))
    return Atx(ok: true, level: k, text: t)

fn is_hr(line: String) Bool:
    if indent_of(line) > 3:
        return false
    let t = line.replace(" ", "")
    let n = slen(t)
    if n < 3:
        return false
    let c = cat(t, 0)
    if c != "-" and c != "*" and c != "_":
        return false
    var i = 0
    while i < n:
        if cat(t, i) != c:
            return false
        i += 1
    return true

fn is_quote_start(line: String) Bool:
    let ind = indent_of(line)
    return ind <= 3 and cat(line, ind) == ">"

fn list_marker(line: String) Marker:
    let ind = indent_of(line)
    let n = slen(line)
    if ind > 3:
        return Marker()
    var p = ind
    let c = cat(line, p)
    var ordered = false
    var mk = ""
    var num = 0
    if c == "-" or c == "*" or c == "+":
        mk = c
        p += 1
    else:
        var k = 0
        while p + k < n and digits().contains(cat(line, p + k)):
            k += 1
        if k == 0 or k > 9:
            return Marker()
        let d = cat(line, p + k)
        if d != "." and d != ")":
            return Marker()
        num = sub(line, p, p + k).parse_int().get(0)
        ordered = true
        mk = d
        p = p + k + 1
    if p < n and cat(line, p) != " ":
        return Marker()
    var sp = 0
    while p + sp < n and cat(line, p + sp) == " ":
        sp += 1
    let empty = p + sp == n
    var w = p + sp
    if empty or sp >= 5:
        w = p + 1
    return Marker(ok: true, ordered: ordered, mk: mk, num: num, m: p, w: w, empty: empty)

fn interrupts_para(line: String) Bool:
    if fence_open(line).ok:
        return true
    if atx_of(line).ok:
        return true
    if is_hr(line):
        return true
    if is_quote_start(line):
        return true
    let mk = list_marker(line)
    if mk.ok and not mk.empty and (not mk.ordered or mk.num == 1):
        return true
    return false

fn split_cells(line: String) List[String]:
    var t = trim_sp(line)
    let n0 = slen(t)
    if n0 > 0 and cat(t, 0) == "|":
        t = dropn(t, 1)
    let n1 = slen(t)
    if n1 > 0 and cat(t, n1 - 1) == "|" and not (n1 >= 2 and cat(t, n1 - 2) == "\\"):
        t = sub(t, 0, n1 - 1)
    var cells = List[String]()
    var cur = ""
    let m = slen(t)
    var p = 0
    while p < m:
        let c = cat(t, p)
        if c == "|" and not (p > 0 and cat(t, p - 1) == "\\"):
            cells.append(trim_sp(cur))
            cur = ""
        else:
            cur += c
        p += 1
    cells.append(trim_sp(cur))
    return cells

fn is_delim_cell(c: String) Bool:
    var s = c
    if cat(s, 0) == ":":
        s = dropn(s, 1)
    let n = slen(s)
    if n > 0 and cat(s, n - 1) == ":":
        s = sub(s, 0, n - 1)
    let m = slen(s)
    if m == 0:
        return false
    var i = 0
    while i < m:
        if cat(s, i) != "-":
            return false
        i += 1
    return true

fn is_delim_row(l: String) Bool:
    if not l.contains("|"):
        return false
    for c in split_cells(l):
        if not is_delim_cell(c):
            return false
    return true

fn align_of(c: String) String:
    let s = c.starts_with(":")
    let e = c.ends_with(":")
    if s and e:
        return "center"
    if s:
        return "left"
    if e:
        return "right"
    return ""

fn table_start(lines: List[String], i: Int) Bool:
    if i + 1 >= lines.length():
        return false
    let l1 = lines[i]
    let l2 = lines[i + 1]
    if not l1.contains("|"):
        return false
    if not is_delim_row(l2):
        return false
    return split_cells(l1).length() == split_cells(l2).length()

fn row_breaks(l: String) Bool:
    return fence_open(l).ok or atx_of(l).ok or is_hr(l) or is_quote_start(l)

fn normalize(cells: List[String], nc: Int) List[String]:
    var out = List[String]()
    var k = 0
    while k < nc:
        if k < cells.length():
            out.append(cells[k].clone())
        else:
            out.append("")
        k += 1
    return out

// ---------- block parsing ----------

fn fence_block(lines: List[String], i: Int, f: Fence) Step:
    let n = lines.length()
    var out = List[String]()
    var j = i + 1
    while j < n:
        if is_fence_close(lines[j], f):
            j += 1
            break
        out.append(strip_up_to(lines[j], f.ind))
        j += 1
    let cls = f.info.split(" ").get(0, "")
    return Step(blk: Block(kind: 5, text: cls, lines: out), stop: j)

fn indented_block(lines: List[String], i: Int) Step:
    let n = lines.length()
    var j = i
    var last = i
    while j < n and (is_blank(lines[j]) or indent_of(lines[j]) >= 4):
        if not is_blank(lines[j]):
            last = j
        j += 1
    var out = List[String]()
    var k = i
    while k <= last:
        out.append(strip_up_to(lines[k], 4))
        k += 1
    return Step(blk: Block(kind: 5, lines: out), stop: last + 1)

fn quote_block(lines: List[String], i: Int) Step:
    let n = lines.length()
    var inner = List[String]()
    var j = i
    while j < n and is_quote_start(lines[j]):
        let l = lines[j]
        var r = dropn(l, indent_of(l) + 1)
        if cat(r, 0) == " ":
            r = dropn(r, 1)
        inner.append(r)
        j += 1
    let kids = parse_blocks(inner)
    return Step(blk: Block(kind: 3, kids: kids), stop: j)

fn same_kind(line: String, mk: Marker) Bool:
    if is_hr(line):
        return false
    let nx = list_marker(line)
    if not nx.ok:
        return false
    return nx.ordered == mk.ordered and nx.mk == mk.mk

fn list_block(lines: List[String], i: Int, first: Marker) Step:
    let n = lines.length()
    var items = List[List[Block]]()
    var loose = false
    var mk = first.clone()
    var j = i
    var stop = i + 1
    var going = true
    while going:
        let w = mk.w
        var content = List[String]()
        content.append(dropn(lines[j], w))
        var last_nb = j
        var pend = 0
        var k = j + 1
        var more = true
        while k < n and more:
            let l = lines[k]
            if is_blank(l):
                pend += 1
                k += 1
            else if indent_of(l) >= w:
                var q = 0
                while q < pend:
                    content.append("")
                    q += 1
                pend = 0
                content.append(dropn(l, w))
                last_nb = k
                k += 1
            else:
                more = false
        let kids = parse_blocks(content)
        items.append(kids)
        stop = last_nb + 1
        var q2 = stop
        while q2 < n and is_blank(lines[q2]):
            q2 += 1
        if q2 < n and same_kind(lines[q2], mk):
            if q2 > stop:
                loose = true
            mk = list_marker(lines[q2])
            j = q2
        else:
            going = false
    for it in items:
        for kd in it:
            if kd.blank:
                loose = true
    return Step(blk: Block(kind: 4, ordered: first.ordered, level: first.num, loose: loose, items: items), stop: stop)

fn table_block(lines: List[String], i: Int) Step:
    let n = lines.length()
    let hc = split_cells(lines[i])
    let dc = split_cells(lines[i + 1])
    var aligns = List[String]()
    for c in dc:
        aligns.append(align_of(c))
    let nc = aligns.length()
    let head = normalize(hc, nc)
    var rows = List[List[String]]()
    var j = i + 2
    while j < n and not is_blank(lines[j]) and not row_breaks(lines[j]):
        rows.append(normalize(split_cells(lines[j]), nc))
        j += 1
    return Step(blk: Block(kind: 6, aligns: aligns, head: head, rows: rows), stop: j)

fn para_block(lines: List[String], i: Int) Step:
    let n = lines.length()
    var raw = List[String]()
    raw.append(lines[i].clone())
    var j = i + 1
    while j < n and not is_blank(lines[j]) and not interrupts_para(lines[j]):
        raw.append(lines[j].clone())
        j += 1
    var text = ""
    let last = raw.length() - 1
    var k = 0
    while k <= last:
        let l = raw[k]
        let t0 = dropn(l, indent_of(l))
        let t = rtrim_sp(t0)
        text += t
        if k < last:
            if slen(t0) - slen(t) >= 2:
                text += sent()
            text += "\n"
        k += 1
    return Step(blk: Block(kind: 0, text: text), stop: j)

fn block_at(lines: List[String], i: Int) Step:
    let line = lines[i]
    let f = fence_open(line)
    if f.ok:
        return fence_block(lines, i, f)
    if indent_of(line) >= 4:
        return indented_block(lines, i)
    let a = atx_of(line)
    if a.ok:
        return Step(blk: Block(kind: 1, level: a.level, text: a.text), stop: i + 1)
    if is_hr(line):
        return Step(blk: Block(kind: 2), stop: i + 1)
    if is_quote_start(line):
        return quote_block(lines, i)
    let mk = list_marker(line)
    if mk.ok:
        return list_block(lines, i, mk)
    if table_start(lines, i):
        return table_block(lines, i)
    return para_block(lines, i)

fn parse_blocks(lines: List[String]) List[Block]:
    var out = List[Block]()
    let n = lines.length()
    var i = 0
    var sawblank = false
    while i < n:
        if is_blank(lines[i]):
            sawblank = true
            i += 1
        else:
            var st = block_at(lines, i)
            var b = st.blk.clone()
            b.blank = sawblank and out.length() > 0
            out.append(b)
            i = st.stop
            sawblank = false
    return out

// ---------- inline: scan ----------

fn count_chars(cs: List[String], start: Int, c: String) Int:
    var k = 0
    while start + k < cs.length() and cs[start + k] == c:
        k += 1
    return k

fn find_run(cs: List[String], from_i: Int, k: Int, c: String) Int:
    let n = cs.length()
    var p = from_i
    while p < n:
        if cs[p] == c:
            let r = count_chars(cs, p, c)
            if r == k:
                return p
            p += r
        else:
            p += 1
    return -1

fn code_text(cs: List[String], a: Int, b: Int) String:
    var s = ""
    var p = a
    while p < b:
        let c = cs[p]
        if c == "\n":
            s += " "
        else if c != sent():
            s += c
        p += 1
    let n = slen(s)
    var allsp = true
    var q = 0
    while q < n:
        if cat(s, q) != " ":
            allsp = false
        q += 1
    if n >= 2 and cat(s, 0) == " " and cat(s, n - 1) == " " and not allsp:
        return sub(s, 1, n - 1)
    return s

fn parse_tail(cs: List[String], start: Int) Tail:
    let n = cs.length()
    var p = start
    while p < n and isspc(cs[p]):
        p += 1
    var dest = ""
    if p < n and cs[p] == "<":
        var q = p + 1
        while q < n and cs[q] != ">" and cs[q] != "<" and cs[q] != "\n" and cs[q] != sent():
            if cs[q] == "\\" and q + 1 < n and punctc(cs[q + 1]):
                dest += cs[q + 1]
                q += 2
            else:
                dest += cs[q]
                q += 1
        if q >= n or cs[q] != ">":
            return Tail()
        p = q + 1
    else:
        var depth = 0
        while p < n:
            let c = cs[p]
            if c == "\\" and p + 1 < n and punctc(cs[p + 1]):
                dest += cs[p + 1]
                p += 2
            else if isspc(c):
                break
            else if c == "(":
                depth += 1
                dest += c
                p += 1
            else if c == ")":
                if depth == 0:
                    break
                depth -= 1
                dest += c
                p += 1
            else:
                dest += c
                p += 1
    var sp2 = false
    while p < n and isspc(cs[p]):
        p += 1
        sp2 = true
    var title = ""
    var has_title = false
    if sp2 and p < n and cs[p] == "\"":
        var q = p + 1
        var closed = false
        while q < n:
            if cs[q] == "\\" and q + 1 < n and cs[q + 1] == "\"":
                title += "\""
                q += 2
            else if cs[q] == "\"":
                closed = true
                break
            else:
                title += cs[q]
                q += 1
        if not closed:
            return Tail()
        has_title = true
        p = q + 1
        while p < n and isspc(cs[p]):
            p += 1
    if p < n and cs[p] == ")":
        return Tail(ok: true, dest: dest, title: title, has_title: has_title, stop: p + 1)
    return Tail()

fn scan(cs: List[String]) List[Node]:
    var nodes = List[Node]()
    let n = cs.length()
    var i = 0
    while i < n:
        let c = cs[i]
        if c == "\\":
            if i + 1 < n and cs[i + 1] == "\n":
                nodes.append(Node(kind: 5))
                i += 2
            else if i + 1 < n and punctc(cs[i + 1]):
                nodes.append(Node(kind: 0, text: cs[i + 1].clone()))
                i += 2
            else:
                nodes.append(Node(kind: 0, text: "\\"))
                i += 1
        else if c == sent() and i + 1 < n and cs[i + 1] == "\n":
            nodes.append(Node(kind: 5))
            i += 2
        else if c == "`":
            let k = count_chars(cs, i, "`")
            let j = find_run(cs, i + k, k, "`")
            if j >= 0:
                nodes.append(Node(kind: 1, text: code_text(cs, i + k, j)))
                i = j + k
            else:
                nodes.append(Node(kind: 0, text: repeat_str("`", k)))
                i += k
        else if c == "*" or c == "_":
            let k = count_chars(cs, i, c)
            let prev = if i == 0: " " else: cs[i - 1].clone()
            let nxt = if i + k >= n: " " else: cs[i + k].clone()
            let lf = not wsc(nxt) and (not punctc(nxt) or wsc(prev) or punctc(prev))
            let rf = not wsc(prev) and (not punctc(prev) or wsc(nxt) or punctc(nxt))
            var co = lf
            var cc = rf
            if c == "_":
                co = lf and (not rf or punctc(prev))
                cc = rf and (not lf or punctc(nxt))
            nodes.append(Node(kind: 2, dc: c.clone(), count: k, orig: k, can_open: co, can_close: cc))
            i += k
        else if c == "!" and i + 1 < n and cs[i + 1] == "[":
            nodes.append(Node(kind: 3, image: true, active: true))
            i += 2
        else if c == "[":
            nodes.append(Node(kind: 3, image: false, active: true))
            i += 1
        else if c == "]":
            var m = nodes.length() - 1
            while m >= 0 and nodes[m].kind != 3:
                m -= 1
            if m < 0:
                nodes.append(Node(kind: 0, text: "]"))
                i += 1
            else if not nodes[m].image and not nodes[m].active:
                nodes[m].kind = 0
                nodes[m].text = "["
                nodes.append(Node(kind: 0, text: "]"))
                i += 1
            else:
                var t = Tail()
                if i + 1 < n and cs[i + 1] == "(":
                    t = parse_tail(cs, i + 2)
                if t.ok:
                    let img = nodes[m].image
                    var kids = List[Node]()
                    var p = m + 1
                    while p < nodes.length():
                        kids.append(nodes[p].clone())
                        p += 1
                    let resolved = resolve(var kids)
                    while nodes.length() > m:
                        nodes.pop()
                    if not img:
                        var q = 0
                        while q < m:
                            if nodes[q].kind == 3 and not nodes[q].image:
                                nodes[q].active = false
                            q += 1
                    nodes.append(Node(kind: 4, image: img, dest: t.dest, title: t.title, has_title: t.has_title, kids: resolved.clone()))
                    i = t.stop
                else:
                    if nodes[m].image:
                        nodes[m].text = "!["
                    else:
                        nodes[m].text = "["
                    nodes[m].kind = 0
                    nodes.append(Node(kind: 0, text: "]"))
                    i += 1
        else:
            nodes.append(Node(kind: 0, text: c.clone()))
            i += 1
    return nodes

// ---------- inline: emphasis ----------

fn finalize(var nodes: List[Node]) Unit:
    var p = 0
    while p < nodes.length():
        if nodes[p].kind == 2:
            nodes[p].kind = 0
            nodes[p].text = repeat_str(nodes[p].dc, nodes[p].count)
        else if nodes[p].kind == 3:
            nodes[p].kind = 0
            if nodes[p].image:
                nodes[p].text = "!["
            else:
                nodes[p].text = "["
        p += 1

fn resolve(var nodes: List[Node]) List[Node]:
    var ci = 0
    while ci < nodes.length():
        if nodes[ci].kind == 2 and nodes[ci].can_close and nodes[ci].count > 0:
            let cch = nodes[ci].dc.clone()
            var found = -1
            var j = ci - 1
            while j >= 0:
                if nodes[j].kind == 2 and nodes[j].dc == cch and nodes[j].can_open and nodes[j].count > 0:
                    let either = nodes[j].can_close or nodes[ci].can_open
                    let sum3 = (nodes[j].orig + nodes[ci].orig) % 3 == 0
                    let both3 = nodes[j].orig % 3 == 0 and nodes[ci].orig % 3 == 0
                    if not (either and sum3 and not both3):
                        found = j
                        break
                j -= 1
            if found >= 0:
                let amt = if nodes[found].count >= 2 and nodes[ci].count >= 2: 2 else: 1
                nodes[found].count -= amt
                nodes[ci].count -= amt
                var kids = List[Node]()
                var p = found + 1
                while p < ci:
                    kids.append(nodes[p].clone())
                    p += 1
                finalize(var kids)
                var nl = List[Node]()
                p = 0
                while p < found:
                    nl.append(nodes[p].clone())
                    p += 1
                if nodes[found].count > 0:
                    nl.append(nodes[found].clone())
                let emph_idx = nl.length()
                nl.append(Node(kind: 6, strong: amt == 2, kids: kids.clone()))
                if nodes[ci].count > 0:
                    nl.append(nodes[ci].clone())
                p = ci + 1
                while p < nodes.length():
                    nl.append(nodes[p].clone())
                    p += 1
                nodes = nl
                ci = emph_idx + 1
            else:
                ci += 1
        else:
            ci += 1
    finalize(var nodes)
    return nodes.clone()

// ---------- inline: render ----------

fn plain(nodes: List[Node]) String:
    var out = ""
    for nd in nodes:
        if nd.kind == 0 or nd.kind == 1:
            out += nd.text.replace("\n", " ")
        else if nd.kind == 5:
            out += " "
        else if nd.kind == 4 or nd.kind == 6:
            out += plain(nd.kids)
    return out

fn render(nodes: List[Node]) String:
    var out = ""
    for nd in nodes:
        if nd.kind == 0:
            out += esc(nd.text)
        else if nd.kind == 1:
            out += "<code>" + esc(nd.text) + "</code>"
        else if nd.kind == 5:
            out += "<br />\n"
        else if nd.kind == 6:
            if nd.strong:
                out += "<strong>" + render(nd.kids) + "</strong>"
            else:
                out += "<em>" + render(nd.kids) + "</em>"
        else if nd.kind == 4:
            let tt = if nd.has_title: " title=\"" + esc(nd.title) + "\"" else: ""
            if nd.image:
                out += "<img src=\"" + esc(nd.dest) + "\" alt=\"" + esc(plain(nd.kids)) + "\"" + tt + " />"
            else:
                out += "<a href=\"" + esc(nd.dest) + "\"" + tt + ">" + render(nd.kids) + "</a>"
    return out

fn inline(text: String) String:
    var sc = scan(text.chars())
    let nodes = resolve(var sc)
    return render(nodes)

// ---------- block rendering ----------

fn render_item(kids: List[Block], tight: Bool) String:
    var body = ""
    for k in kids:
        if tight and k.kind == 0:
            body += inline(k.text)
        else:
            if body == "" or not body.ends_with("\n"):
                body += "\n"
            body += render_block(k)
    return body

fn render_list(b: Block) String:
    var out = ""
    let tight = not b.loose
    if b.ordered:
        if b.level == 1:
            out += "<ol>\n"
        else:
            out += "<ol start=\"{b.level}\">\n"
    else:
        out += "<ul>\n"
    for it in b.items:
        out += "<li>" + render_item(it, tight) + "</li>\n"
    if b.ordered:
        out += "</ol>\n"
    else:
        out += "</ul>\n"
    return out

fn render_code(b: Block) String:
    var out = ""
    if b.text == "":
        out += "<pre><code>"
    else:
        out += "<pre><code class=\"language-" + esc(b.text) + "\">"
    for l in b.lines:
        out += esc(l) + "\n"
    out += "</code></pre>\n"
    return out

fn align_attr(a: String) String:
    if a == "":
        return ""
    return " align=\"" + a + "\""

fn render_table(b: Block) String:
    var out = "<table>\n<thead>\n<tr>\n"
    var c = 0
    while c < b.head.length():
        out += "<th" + align_attr(b.aligns[c]) + ">" + inline(b.head[c]) + "</th>\n"
        c += 1
    out += "</tr>\n</thead>\n"
    if b.rows.length() > 0:
        out += "<tbody>\n"
        for row in b.rows:
            out += "<tr>\n"
            var d = 0
            while d < row.length():
                out += "<td" + align_attr(b.aligns[d]) + ">" + inline(row[d]) + "</td>\n"
                d += 1
            out += "</tr>\n"
        out += "</tbody>\n"
    out += "</table>\n"
    return out

fn render_block(b: Block) String:
    if b.kind == 0:
        return "<p>" + inline(b.text) + "</p>\n"
    if b.kind == 1:
        return "<h{b.level}>" + inline(b.text) + "</h{b.level}>\n"
    if b.kind == 2:
        return "<hr />\n"
    if b.kind == 3:
        return "<blockquote>\n" + render_blocks(b.kids) + "</blockquote>\n"
    if b.kind == 4:
        return render_list(b)
    if b.kind == 5:
        return render_code(b)
    return render_table(b)

fn render_blocks(blocks: List[Block]) String:
    var out = ""
    for b in blocks:
        out += render_block(b)
    return out

// ---------- entry point ----------

export fn main() Int:
    let data = read_all(stdin()).get()
    let text = data.decode_utf8().get("")
    let parts = text.split("\n")
    var n = parts.length()
    if n > 0 and parts[n - 1] == "":
        n -= 1
    var lines = List[String]()
    var i = 0
    while i < n:
        lines.append(parts[i].clone())
        i += 1
    let blocks = parse_blocks(lines)
    stdout().write(render_blocks(blocks)).get()
    return 0

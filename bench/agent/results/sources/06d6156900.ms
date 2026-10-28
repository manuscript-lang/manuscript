# Markdown subset to HTML, following the exact rules in TASK.md.
from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines

let K_TEXT = 0
let K_RAW = 1
let K_DELIM = 2
let K_BRACKET = 3
# Marks a two-space hard break inside paragraph text; never occurs in the input.
let SENT = "\u{1}"
let PUNCT = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
let DIGITS = "0123456789"

type Blk:
    para: Bool = False
    text: String = ""

type Parsed:
    blks: List[Blk]
    gap: Bool = False

type Step:
    nxt: Int
    blk: Blk

type Fence:
    ch: String
    size: Int
    ind: Int
    info: String

type Marker:
    ind: Int = 0
    ordered: Bool = False
    delim: String = ""
    num: Int = 0
    width: Int = 0
    empty: Bool = True

type Tok:
    kind: Int = 0
    html: String = ""
    plain: String = ""
    ch: String = ""
    cnt: Int = 0
    orig: Int = 0
    can_open: Bool = False
    can_close: Bool = False
    image: Bool = False
    active: Bool = False

type Tail:
    dest: String = ""
    title: String = ""
    has_title: Bool = False
    stop: Int = 0

# ---------- string helpers ----------

def at(s: String, i: Int) -> String:
    if i < 0 or i >= s.length():
        return ""

    return s.get(i)

def sub(s: String, a: Int, b: Int) -> String:
    let e = s.length() if b > s.length() else b

    if e <= a:
        return ""

    return s.slice(a, e).get()

def esc(s: String) -> String:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
        "\"", "&quot;"
    )

def indentOf(s: String) -> Int:
    var k = 0
    while k < s.length() and s.get(k) == " ":
        k += 1
    return k

def isBlank(s: String) -> Bool:
    return indentOf(s) == s.length()

def dropSpaces(s: String, n: Int) -> String:
    let k = indentOf(s) if indentOf(s) < n else n

    return sub(s, k, s.length())

def runLen(s: String, start: Int, c: String) -> Int:
    var k = start
    while at(s, k) == c:
        k += 1
    return k - start

def isDigit(c: String) -> Bool:
    return c != "" and DIGITS.contains(c)

def isPunct(c: String) -> Bool:
    return c != "" and PUNCT.contains(c)

def isWsC(c: String) -> Bool:
    return c == "" or c == " " or c == "\n" or c == SENT

def firstWord(s: String) -> String:
    var k = 0
    while k < s.length() and s.get(k) != " ":
        k += 1
    return sub(s, 0, k)

# ---------- block-level recognizers ----------

def isHr(line: String) -> Bool:
    if indentOf(line) > 3:
        return False

    let t = line.replace(" ", "")
    if t.length() < 3:
        return False

    let c = t.get(0)
    if c != "-" and c != "*" and c != "_":
        return False

    return t.replace(c, "") == ""

def atxLevel(line: String) -> Int:
    let ind = indentOf(line)
    if ind > 3:
        return 0

    let k = runLen(line, ind, "#")
    if k < 1 or k > 6:
        return 0

    let after = at(line, ind + k)
    if after != "" and after != " ":
        return 0

    return k

def atxText(line: String) -> String:
    let ind = indentOf(line)
    let k = runLen(line, ind, "#")
    var t = sub(line, ind + k, line.length()).trim()
    var r = 0
    while r < t.length() and t.get(t.length() - 1 - r) == "#":
        r += 1
    if r > 0 and (r == t.length() or t.get(t.length() - r - 1) == " "):
        t = sub(t, 0, t.length() - r).trim()
    return t

def fenceOpen(line: String) -> Optional[Fence]:
    let ind = indentOf(line)
    if ind > 3:
        return none

    let c = at(line, ind)
    if c != "`" and c != "~":
        return none

    let k = runLen(line, ind, c)
    if k < 3:
        return none

    let info = sub(line, ind + k, line.length()).trim()
    if c == "`" and info.contains("`"):
        return none

    return Fence(ch: c, size: k, ind: ind, info: info)

def isFenceClose(line: String, f: Fence) -> Bool:
    let ind = indentOf(line)
    if ind > 3:
        return False

    let k = runLen(line, ind, f.ch)
    if k < f.size:
        return False

    return sub(line, ind + k, line.length()).trim() == ""

def isQuote(line: String) -> Bool:
    return indentOf(line) <= 3 and at(line, indentOf(line)) == ">"

def quoteLine(line: String) -> String:
    var start = indentOf(line) + 1
    if at(line, start) == " ":
        start += 1
    return sub(line, start, line.length())

def digitsRun(line: String, start: Int) -> Int:
    var k = start
    while isDigit(at(line, k)):
        k += 1
    return k - start

def markerAt(line: String) -> Optional[Marker]:
    let ind = indentOf(line)
    if ind > 3:
        return none

    let c = at(line, ind)
    var m = ind + 1
    var ordered = False
    var num = 0
    var delim = c.clone()

    if c == "-" or c == "*" or c == "+":
        m = ind + 1
    else:
        let d = digitsRun(line, ind)
        if d < 1 or d > 9:
            return none

        let dl = at(line, ind + d)
        if dl != "." and dl != ")":
            return none

        ordered = True
        delim = dl

        var q = 0

        while q < d:
            num = num * 10 + (line.scalar_at(ind + q) - 48)
            q += 1

        m = ind + d + 1

    if m < line.length() and at(line, m) != " ":
        return none

    let restBlank = isBlank(sub(line, m, line.length()))
    var k = 0
    while at(line, m + k) == " ":
        k += 1

    var w = m + k
    if restBlank or k >= 5:
        w = m + 1
    return Marker(
        ind: ind, ordered: ordered, delim: delim, num: num, width: w, empty: restBlank
    )

def isDelimCell(c: String) -> Bool:
    var t = c
    if t.starts_with(":"):
        t = sub(t, 1, t.length())
    if t.ends_with(":"):
        t = sub(t, 0, t.length() - 1)
    return t.length() > 0 and t.replace("-", "") == ""

def splitCells(line: String) -> List[String]:
    var t = line.trim().clone()
    if t.starts_with("|"):
        t = sub(t, 1, t.length())
    if t.ends_with("|") and (t.length() < 2 or t.get(t.length() - 2) != "\\"):
        t = sub(t, 0, t.length() - 1)

    var cells = List[String]()
    var cur = ""
    var k = 0

    while k < t.length():
        let c = t.get(k)

        if c == "|" and at(t, k - 1) != "\\":
            cells.append(cur.trim().clone())
            cur = ""
        else:
            cur += c

        k += 1

    cells.append(cur.trim().clone())
    return cells

def isDelimRow(line: String) -> Bool:
    if not line.contains("|"):
        return False

    let cells = splitCells(line)
    for c in cells:
        if not isDelimCell(c):
            return False
    return True

def alignOf(c: String) -> String:
    let t = c.trim()
    let l = t.starts_with(":")
    let r = t.ends_with(":")
    if l and r:
        return "center"
    if r:
        return "right"
    if l:
        return "left"

    return ""

def alignAttr(a: String) -> String:
    if a == "":
        return ""

    return " align=\"" + a + "\""

def tableAt(lines: List[String], i: Int) -> Bool:
    if i + 1 >= lines.length():
        return False
    if not lines[i].contains("|"):
        return False
    if not isDelimRow(lines[i + 1]):
        return False

    return splitCells(lines[i]).length() == splitCells(lines[i + 1]).length()

def isBodyStop(line: String) -> Bool:
    if isBlank(line) or atxLevel(line) > 0 or isHr(line) or isQuote(line):
        return True
    if let _f = fenceOpen(line):
        return True

    return False

def interrupts(line: String) -> Bool:
    if isBlank(line) or atxLevel(line) > 0 or isHr(line) or isQuote(line):
        return True
    if let _f = fenceOpen(line):
        return True

    if let mk = markerAt(line):
        if not mk.empty and (not mk.ordered or mk.num == 1):
            return True
    return False

# ---------- block parsing ----------

def renderTop(blks: List[Blk]) -> String:
    var out = ""

    for b in blks:
        if b.para:
            out += "<p>" + b.text + "</p>\n"
        else:
            out += b.text

    return out

def renderBody(blks: List[Blk], tight: Bool) -> String:
    var body = ""

    for b in blks:
        if b.para and tight:
            body += b.text
        else:
            if body == "" or not body.ends_with("\n"):
                body += "\n"

            if b.para:
                body += "<p>" + b.text + "</p>\n"
            else:
                body += b.text

    return body

def parseBlocks(lines: List[String]) -> Parsed:
    var blks = List[Blk]()
    var gap = False
    var blank = False
    var i = 0
    let n = lines.length()

    while i < n:
        if isBlank(lines[i]):
            blank = True
            i += 1
            continue

        if blank and blks.length() > 0:
            gap = True
        blank = False

        let st = parseOne(lines, i)
        blks.append(st.blk.clone())
        i = st.nxt

    return Parsed(blks: blks, gap: gap)

def parseOne(lines: List[String], i: Int) -> Step:
    let line = lines[i]
    if let f = fenceOpen(line):
        return parseFence(lines, i, f)

    let lvl = atxLevel(line)
    if lvl > 0:
        return Step(
            nxt: i + 1,
            blk: Blk(
                para: False,
                text: f"<h{lvl}>" + inline(
                    atxText(line)
                ) + f"</h{lvl}>\n"
            )
        )
    if isHr(line):
        return Step(nxt: i + 1, blk: Blk(para: False, text: "<hr />\n"))
    if isQuote(line):
        return parseQuote(lines, i)
    if let mk = markerAt(line):
        return parseList(lines, i, mk)
    if indentOf(line) >= 4:
        return parseIndented(lines, i)
    if tableAt(lines, i):
        return parseTable(lines, i)

    return parsePara(lines, i)

def parseFence(lines: List[String], i: Int, f: Fence) -> Step:
    let n = lines.length()
    var html = "<pre><code"
    if f.info != "":
        html += " class=\"language-" + esc(firstWord(f.info)) + "\""
    html += ">"

    var j = i + 1

    while j < n and not isFenceClose(lines[j], f):
        html += esc(dropSpaces(lines[j], f.ind)) + "\n"
        j += 1

    html += "</code></pre>\n"

    let nxt = j + 1 if j < n else n

    return Step(nxt: nxt, blk: Blk(para: False, text: html))

def parseQuote(lines: List[String], i: Int) -> Step:
    let n = lines.length()
    var body = List[String]()
    var j = i

    while j < n and isQuote(lines[j]):
        body.append(quoteLine(lines[j]))
        j += 1

    let inner = renderTop(parseBlocks(body).blks)
    return Step(
        nxt: j,
        blk: Blk(
            para: False, text: "<blockquote>\n" + inner + "</blockquote>\n"
        )
    )

def parseIndented(lines: List[String], i: Int) -> Step:
    let n = lines.length()
    var j = i
    var last = i

    while j < n and (isBlank(lines[j]) or indentOf(lines[j]) >= 4):
        if not isBlank(lines[j]):
            last = j
        j += 1

    var html = "<pre><code>"
    var k = i

    while k <= last:
        html += esc(dropSpaces(lines[k], 4)) + "\n"
        k += 1

    html += "</code></pre>\n"
    return Step(nxt: last + 1, blk: Blk(para: False, text: html))

def parseTable(lines: List[String], i: Int) -> Step:
    let n = lines.length()
    let head = splitCells(lines[i])
    let delims = splitCells(lines[i + 1])
    var aligns = List[String]()
    for c in delims:
        aligns.append(alignOf(c))

    var html = "<table>\n<thead>\n<tr>\n"
    for c in 0..head.length():
        html += "<th" + alignAttr(aligns[c]) + ">" + inline(head[c]) + "</th>\n"
    html += "</tr>\n</thead>\n"

    let bodyStart = i + 2
    var e = bodyStart
    while e < n and not isBodyStop(lines[e]):
        e += 1

    if e > bodyStart:
        html += "<tbody>\n"

        var r = bodyStart

        while r < e:
            let cells = splitCells(lines[r])
            html += "<tr>\n"

            for c in 0..head.length():
                var cell = ""
                if c < cells.length():
                    cell = cells[c].clone()
                html += "<td" + alignAttr(aligns[c]) + ">" + inline(cell) + "</td>\n"

            html += "</tr>\n"
            r += 1

        html += "</tbody>\n"

    html += "</table>\n"
    return Step(nxt: e, blk: Blk(para: False, text: html))

def parsePara(lines: List[String], i: Int) -> Step:
    let n = lines.length()
    var j = i + 1
    while j < n and not interrupts(lines[j]):
        j += 1
    return Step(nxt: j, blk: Blk(para: True, text: inline(paraText(lines, i, j))))

def paraText(lines: List[String], a: Int, b: Int) -> String:
    var out = ""
    var k = a

    while k < b:
        let line = sub(lines[k], indentOf(lines[k]), lines[k].length())
        let last = k == b - 1
        let hard = not last and line.ends_with("  ")
        out += line.trim()

        if not last:
            if hard:
                out += SENT
            else:
                out += "\n"

        k += 1

    return out

def parseList(lines: List[String], start: Int, first: Marker) -> Step:
    let n = lines.length()
    var items = List[Parsed]()
    var loose = False
    var cur = first.clone()
    var atLine = start
    var last = start

    while True:
        let w = cur.width
        var body = List[String]()
        body.append(sub(lines[atLine], w, lines[atLine].length()))

        var j = atLine + 1
        var pending = 0
        last = atLine + 1

        while j < n:
            let l = lines[j]

            if isBlank(l):
                pending += 1
                j += 1
                continue

            if indentOf(l) < w:
                break

            var q = 0

            while q < pending:
                body.append("")
                q += 1

            pending = 0
            body.append(sub(l, w, l.length()))
            j += 1
            last = j

        let parsed = parseBlocks(body)
        if parsed.gap:
            loose = True
        items.append(parsed)

        var k = last
        while k < n and isBlank(lines[k]):
            k += 1

        var more = False

        if k < n:
            if let nm = markerAt(lines[k]):
                if (
                    nm.delim == first.delim
                    and nm.ordered == first.ordered
                    and not isHr(lines[k])
                ):
                    if k > last:
                        loose = True
                    cur = nm
                    atLine = k
                    more = True

        if not more:
            break

    var html = "<ul>\n"
    var close = "</ul>\n"

    if first.ordered:
        html = "<ol>\n" if first.num == 1 else f"<ol start=\"{first.num}\">\n"

        close = "</ol>\n"

    for it in items:
        html += "<li>" + renderBody(it.blks, not loose) + "</li>\n"
    html += close
    return Step(nxt: last, blk: Blk(para: False, text: html))

# ---------- inline processing ----------

def pushText(var toks: List[Tok], s: String) -> Unit:
    let k = toks.length() - 1

    if k >= 0 and toks[k].kind == K_TEXT:
        var t = toks[k].clone()
        t.plain += s
        toks[k] = t
    else:
        toks.append(Tok(kind: K_TEXT, plain: s))

def findRun(text: String, from: Int, size: Int) -> Int:
    var p = from

    while p < text.length():
        if text.get(p) == "`":
            let r = runLen(text, p, "`")
            if r == size:
                return p

            p += r
        else:
            p += 1

    return -1

def isLinkSpace(c: String) -> Bool:
    return c == " " or c == "\n" or c == SENT

def parseTail(text: String, start: Int) -> Optional[Tail]:
    let n = text.length()
    var p = start
    while p < n and isLinkSpace(text.get(p)):
        p += 1

    var dest = ""

    if at(text, p) == "<":
        var q = p + 1
        while (
            q < n
            and at(text, q) != ">"
            and at(text, q) != "\n"
            and at(text, q) != "<"
        ):
            q += 1
        if at(text, q) != ">":
            return none

        dest = sub(text, p + 1, q)
        p = q + 1
    else:
        var depth = 0

        while p < n:
            let c = text.get(p)
            if c == " " or c == "\n":
                break

            if c == "\\" and isPunct(at(text, p + 1)):
                dest += at(text, p + 1)
                p += 2
                continue

            if c == "(":
                depth += 1
            elif c == ")":
                if depth == 0:
                    break

                depth -= 1

            dest += c
            p += 1

    var q = p
    while q < n and isLinkSpace(text.get(q)):
        q += 1

    let skipped = q > p
    var title = ""
    var hasTitle = False

    if skipped and at(text, q) == "\"":
        var r = q + 1

        while r < n and text.get(r) != "\"":
            if text.get(r) == "\\" and at(text, r + 1) == "\"":
                title += "\""
                r += 2
                continue

            title += text.get(r)
            r += 1

        if r >= n:
            return none

        hasTitle = True
        q = r + 1
        while q < n and isLinkSpace(text.get(q)):
            q += 1

    if at(text, q) != ")":
        return none

    return Tail(dest: dest, title: title, has_title: hasTitle, stop: q + 1)

def literal(t: Tok) -> Tok:
    if t.kind == K_DELIM:
        var s = ""
        var k = 0

        while k < t.cnt:
            s += t.ch
            k += 1

        return Tok(kind: K_TEXT, plain: s)

    return t.clone()

def canMatch(o: Tok, c: Tok) -> Bool:
    if o.kind != K_DELIM or not o.can_open or o.cnt == 0 or o.ch != c.ch:
        return False
    if (
        (o.can_close or c.can_open)
        and (o.orig + c.orig) % 3 == 0
        and not (o.orig % 3 == 0 and c.orig % 3 == 0)
    ):
        return False

    return True

def resolve(toks: List[Tok]) -> List[Tok]:
    var cur = toks
    var i = 0

    while i < cur.length():
        if cur[i].kind != K_DELIM or not cur[i].can_close or cur[i].cnt == 0:
            i += 1
            continue

        var j = i - 1
        while j >= 0 and not canMatch(cur[j], cur[i]):
            j -= 1

        if j < 0:
            i += 1
            continue

        let take = 2 if cur[j].cnt >= 2 and cur[i].cnt >= 2 else 1

        var out = List[Tok]()
        var q = 0

        while q < j:
            out.append(cur[q].clone())
            q += 1

        var op = cur[j].clone()
        op.cnt -= take
        if op.cnt > 0:
            out.append(op)
        out.append(Tok(kind: K_RAW, html: "<strong>" if take == 2 else "<em>"))
        q = j + 1

        while q < i:
            out.append(literal(cur[q]))
            q += 1

        out.append(Tok(kind: K_RAW, html: "</strong>" if take == 2 else "</em>"))

        var cl = cur[i].clone()
        cl.cnt -= take

        var nxt = out.length()

        if cl.cnt > 0:
            out.append(cl)
            nxt = out.length() - 1

        q = i + 1

        while q < cur.length():
            out.append(cur[q].clone())
            q += 1

        cur = out
        i = nxt

    var res = List[Tok]()

    for t in cur:
        if t.kind == K_DELIM and t.cnt == 0:
            continue

        res.append(literal(t))

    return res

def htmlOf(toks: List[Tok]) -> String:
    var out = ""

    for t in toks:
        if t.kind == K_TEXT or t.kind == K_BRACKET:
            out += esc(t.plain)
        else:
            out += t.html

    return out

def plainOf(toks: List[Tok]) -> String:
    var out = ""
    for t in toks:
        out += t.plain
    return out

def scanInline(text: String) -> List[Tok]:
    var toks = List[Tok]()
    let n = text.length()
    var i = 0

    while i < n:
        let c = text.get(i)

        if c == "\\":
            let d = at(text, i + 1)

            if d == "\n":
                toks.append(Tok(kind: K_RAW, html: "<br />\n", plain: " "))
                i += 2
            elif isPunct(d):
                pushText(var toks, d)
                i += 2
            else:
                pushText(var toks, "\\")
                i += 1

            continue

        if c == SENT:
            toks.append(Tok(kind: K_RAW, html: "<br />\n", plain: " "))
            i += 1
            continue

        if c == "\n":
            toks.append(Tok(kind: K_RAW, html: "\n", plain: " "))
            i += 1
            continue

        if c == "`":
            let run = runLen(text, i, "`")
            let close = findRun(text, i + run, run)

            if close < 0:
                pushText(var toks, sub(text, i, i + run))
                i += run
                continue

            var content = sub(text, i + run, close).replace("\n", " ").replace(
                SENT, " "
            )
            if (
                content.length() >= 2
                and content.starts_with(" ")
                and content.ends_with(" ")
                and content.trim() != ""
            ):
                content = sub(content, 1, content.length() - 1)
            toks.append(
                Tok(
                    kind: K_RAW, html: "<code>" + esc(content) + "</code>",
                    plain: content
                )
            )
            i = close + run
            continue

        if c == "*" or c == "_":
            let run = runLen(text, i, c)

            let prev = at(text, i - 1) if i > 0 else " "

            let nxt = at(text, i + run)
            let leftFlank = (
                not isWsC(nxt)
                and (not isPunct(nxt) or isWsC(prev) or isPunct(prev))
            )
            let rightFlank = (
                not isWsC(prev)
                and (not isPunct(prev) or isWsC(nxt) or isPunct(nxt))
            )
            var canOpen = leftFlank
            var canClose = rightFlank

            if c == "_":
                canOpen = leftFlank and (not rightFlank or isPunct(prev))
                canClose = rightFlank and (not leftFlank or isPunct(nxt))

            toks.append(
                Tok(
                    kind: K_DELIM, ch: c, cnt: run, orig: run, can_open: canOpen,
                    can_close: canClose
                )
            )
            i += run
            continue

        if c == "!" and at(text, i + 1) == "[":
            toks.append(Tok(kind: K_BRACKET, plain: "![", image: True, active: True))
            i += 2
            continue

        if c == "[":
            toks.append(Tok(kind: K_BRACKET, plain: "[", image: False, active: True))
            i += 1
            continue

        if c == "]":
            var k = toks.length() - 1
            while k >= 0 and toks[k].kind != K_BRACKET:
                k -= 1

            if k < 0:
                pushText(var toks, "]")
                i += 1
                continue

            let br = toks[k].clone()

            if not br.image and not br.active:
                toks[k] = Tok(kind: K_TEXT, plain: br.plain.clone())
                pushText(var toks, "]")
                i += 1
                continue

            var tl: Optional[Tail] = none
            if at(text, i + 1) == "(":
                tl = parseTail(text, i + 2)

            if let t = tl:
                var kept = List[Tok]()

                for q in 0..k:
                    var kt = toks[q].clone()
                    if not br.image and kt.kind == K_BRACKET and not kt.image:
                        kt.active = False
                    kept.append(kt)

                var kids = List[Tok]()
                var q = k + 1

                while q < toks.length():
                    kids.append(toks[q].clone())
                    q += 1

                let kidToks = resolve(kids)
                let kidPlain = plainOf(kidToks)

                let title = " title=\"" + esc(t.title) + "\"" if t.has_title else ""

                if br.image:
                    kept.append(
                        Tok(
                            kind: K_RAW,
                            html: "<img src=\"" + esc(
                                t.dest
                            ) + "\" alt=\"" + esc(kidPlain) + "\"" + title + " />",
                            plain: kidPlain
                        )
                    )
                else:
                    kept.append(
                        Tok(
                            kind: K_RAW,
                            html: "<a href=\"" + esc(
                                t.dest
                            ) + "\"" + title + ">" + htmlOf(kidToks) + "</a>",
                            plain: kidPlain
                        )
                    )

                toks = kept
                i = t.stop
                continue

            toks[k] = Tok(kind: K_TEXT, plain: br.plain.clone())
            pushText(var toks, "]")
            i += 1
            continue

        pushText(var toks, c)
        i += 1

    return toks

def inline(text: String) -> String:
    return htmlOf(resolve(scanInline(text)))

# ---------- entry point ----------

export def main() -> Int:
    let lines = read_lines(stdin()).get()
    let doc = parseBlocks(lines)
    stdout().write(renderTop(doc.blks)).get()
    return 0

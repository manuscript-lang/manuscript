import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

# AST node kinds
let K_CHR = 1
let K_CLS = 2
let K_BOL = 3
let K_EOL = 4
let K_WB = 5
let K_BREF = 6
let K_GROUP = 7
let K_LOOK = 8
let K_REP = 9
let K_SEQ = 10
let K_ALT = 11
# VM opcodes
let O_CHR = 1
let O_CLS = 2
let O_SPLIT = 3
let O_JMP = 4
let O_SETPOS = 5
let O_SETCONST = 6
let O_OPEN = 7
let O_CLOSE = 8
let O_BOL = 9
let O_EOL = 10
let O_WB = 11
let O_BREF = 12
let O_LOOK = 13
let O_LOOKEND = 14
let O_MATCH = 15
let O_HEADG = 16
let O_HEADL = 17
let O_TAIL = 18
let TABLE = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz\{|\}~"
let HEX = "0123456789abcdef"

fn is_digit(c: Int) Bool:
    return c >= 48 and c <= 57

fn is_alpha(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_alnum(c: Int) Bool:
    return is_digit(c) or is_alpha(c)

fn is_word(c: Int) Bool:
    return is_alnum(c) or c == 95

fn is_short(e: Int) Bool:
    return e == 100 or e == 68 or e == 119 or e == 87 or e == 115 or e == 83

fn short_has(e: Int, c: Int) Bool:
    var r = false
    let l = lower_of(e)

    if l == 100:
        r = is_digit(c)
    else if l == 119:
        r = is_word(c)
    else:
        r = c == 32 or c == 9 or c == 10 or c == 13 or c == 12 or c == 11

    if e < 97:
        return not r

    return r

fn hexval(c: Int) Int:
    if c >= 48 and c <= 57:
        return c - 48
    if c >= 97 and c <= 102:
        return c - 87
    if c >= 65 and c <= 70:
        return c - 55

    return -1

fn lower_of(c: Int) Int:
    if c >= 65 and c <= 90:
        return c + 32

    return c

fn b01(x: Bool) Int:
    if x:
        return 1

    return 0

fn to_bytes_list(s: String) List[Int]:
    let b = s.to_bytes()
    var out = List[Int]()
    for i in 0..b.length():
        out.append(b.get(i).to_int())
    return out

fn name_string(p: List[Int], a: Int, b: Int) String:
    var s = ""
    for i in a..b:
        s = s.concat(TABLE.get(p[i] - 32))
    return s

fn esc_byte(c: Int) String:
    if c == 92:
        return "\\\\"
    if c == 34:
        return "\\\""
    if c == 10:
        return "\\n"
    if c == 9:
        return "\\t"
    if c == 13:
        return "\\r"
    if c < 32 or c > 126:
        return "\\x".concat(HEX.get(c / 16)).concat(HEX.get(c % 16))

    return TABLE.get(c - 32)

fn quoted(s: List[Int], a: Int, b: Int) String:
    var out = "\""
    for i in a..b:
        out = out.concat(esc_byte(s[i]))
    return out.concat("\"")

fn bad_list() List[Int]:
    var r = List[Int]()
    r.append(-1)
    return r

fn is_bad(l: List[Int]) Bool:
    return l.length() == 1 and l[0] == -1

# Decodes \n \t \\ \xHH in a subject or replacement. Returns [-1] on error.
fn unescape(raw: List[Int]) List[Int]:
    var out = List[Int]()
    var i = 0
    let L = raw.length()

    while i < L:
        let c = raw[i]

        if c != 92:
            out.append(c)
            i += 1
        else:
            if i + 1 >= L:
                return bad_list()

            let e = raw[i + 1]

            if e == 110:
                out.append(10)
                i += 2
            else if e == 116:
                out.append(9)
                i += 2
            else if e == 92:
                out.append(92)
                i += 2
            else if e == 120:
                if i + 3 >= L:
                    return bad_list()

                let h1 = hexval(raw[i + 2])
                let h2 = hexval(raw[i + 3])
                if h1 < 0 or h2 < 0:
                    return bad_list()

                out.append(h1 * 16 + h2)
                i += 4
            else:
                return bad_list()

    return out

type Re:
    pat: List[Int]
    pos: Int
    err: String
    icase: Bool
    multi: Bool
    dotall: Bool
    ngroups: Int
    gnames: List[String]
    bnames: List[String]
    nk: List[Int]
    na: List[Int]
    nb: List[Int]
    nc: List[Int]
    nch: List[Int]
    nnx: List[Int]
    cls: List[Bool]
    ncls: Int
    qmin: Int
    qmax: Int
    root: Int
    anchored_end: Bool
    op: List[Int]
    oa: List[Int]
    ob: List[Int]
    oc: List[Int]
    od: List[Int]
    nslots: Int
    st: List[Int]
    sk: List[Int]
    sa: List[Int]
    sb: List[Int]
    sp: Int
    subj: List[Int]
    endpos: Int

impl Re:
    fn peek(off: Int) Int:
        let i = self.pos + off
        if i >= 0 and i < self.pat.length():
            return self.pat[i]

        return -1

    var fn node(kind: Int, a: Int, b: Int, c: Int) Int:
        self.nk.append(kind)
        self.na.append(a)
        self.nb.append(b)
        self.nc.append(c)
        self.nch.append(-1)
        self.nnx.append(-1)
        return self.nk.length() - 1

    var fn new_class() Int:
        for i in 0..256:
            self.cls.append(false)
        self.ncls += 1
        return self.ncls - 1

    fn find_name(name: String) Int:
        for g in 0..self.ngroups:
            if self.gnames[g] == name:
                return g + 1
        return -1

    # Returns index of '>' if a valid group name starts at `start`, else -1.
    fn name_end(start: Int) Int:
        let L = self.pat.length()
        if start >= L:
            return -1

        let f = self.pat[start]
        if not (is_alpha(f) or f == 95):
            return -1

        var i = start + 1
        while i < L and is_word(self.pat[i]):
            i += 1
        if i < L and self.pat[i] == 62:
            return i

        return -1

    var fn hex2() Int:
        let h1 = hexval(self.peek(0))
        let h2 = hexval(self.peek(1))

        if h1 < 0 or h2 < 0:
            self.err = "bad escape"
            return -1

        self.pos += 2
        return h1 * 16 + h2

    var fn chr_node(c: Int) Int:
        var d = c

        if self.icase:
            if c >= 65 and c <= 90:
                d = c + 32
            else if c >= 97 and c <= 122:
                d = c - 32

        return self.node(K_CHR, c, d, 0)

    var fn class_item(cl: Int) Int:
        let c = self.pat[self.pos]
        self.pos += 1
        if c != 92:
            return c

        if self.pos >= self.pat.length():
            self.err = "unterminated class"
            return -1

        let e = self.pat[self.pos]
        self.pos += 1

        if is_short(e):
            for x in 0..256:
                if short_has(e, x):
                    self.cls[cl * 256 + x] = true
            return -1

        if e == 110:
            return 10
        if e == 116:
            return 9
        if e == 114:
            return 13
        if e == 120:
            return self.hex2()
        if e < 128 and not is_alnum(e):
            return e

        self.err = "bad escape"
        return -1

    var fn parse_class() Int:
        let cl = self.new_class()
        var negate = false

        if self.peek(0) == 94:
            negate = true
            self.pos += 1

        var first = true
        var done = false

        while not done:
            if self.pos >= self.pat.length():
                self.err = "unterminated class"
                return -1

            if self.pat[self.pos] == 93 and not first:
                self.pos += 1
                done = true
            else:
                let lo = self.class_item(cl)
                if self.err != "":
                    return -1

                if self.peek(0) == 45 and self.peek(1) != 93 and self.peek(1) != -1:
                    self.pos += 1

                    let hi = self.class_item(cl)
                    if self.err != "":
                        return -1

                    if lo < 0 or hi < 0 or hi < lo:
                        self.err = "bad range"
                        return -1

                    for x in lo..hi + 1:
                        self.cls[cl * 256 + x] = true
                else if lo >= 0:
                    self.cls[cl * 256 + lo] = true

                first = false

        if self.icase:
            for x in 0..26:
                let up = cl * 256 + 65 + x
                let lw = cl * 256 + 97 + x

                if self.cls[up] or self.cls[lw]:
                    self.cls[up] = true
                    self.cls[lw] = true

        if negate:
            for x in 0..256:
                self.cls[cl * 256 + x] = not self.cls[cl * 256 + x]
        return cl

    var fn parse_escape() Int:
        if self.pos >= self.pat.length():
            self.err = "bad escape"
            return -1

        let e = self.pat[self.pos]
        self.pos += 1

        if is_short(e):
            let cl = self.new_class()
            for x in 0..256:
                if short_has(e, x):
                    self.cls[cl * 256 + x] = true
            return self.node(K_CLS, cl * 256, 0, 0)

        if e == 98:
            return self.node(K_WB, 0, 0, 0)
        if e == 66:
            return self.node(K_WB, 1, 0, 0)
        if e >= 49 and e <= 57:
            return self.node(K_BREF, e - 48, b01(self.icase), -1)
        if e == 110:
            return self.chr_node(10)
        if e == 116:
            return self.chr_node(9)
        if e == 114:
            return self.chr_node(13)

        if e == 120:
            let v = self.hex2()
            if self.err != "":
                return -1

            return self.chr_node(v)

        if e == 107:
            if self.peek(0) != 60:
                self.err = "bad escape"
                return -1

            let st = self.pos + 1
            let en = self.name_end(st)

            if en < 0:
                self.err = "bad escape"
                return -1

            self.bnames.append(name_string(self.pat, st, en))
            self.pos = en + 1
            return self.node(K_BREF, -1, b01(self.icase), self.bnames.length() - 1)

        if e < 128 and not is_alnum(e):
            return self.chr_node(e)

        self.err = "bad escape"
        return -1

    var fn brace() Bool:
        let L = self.pat.length()
        var i = self.pos + 1
        var n = 0
        var nd = 0

        while i < L and is_digit(self.pat[i]):
            if n <= 1000:
                n = n * 10 + self.pat[i] - 48
            i += 1
            nd += 1

        if nd == 0 or i >= L:
            return false

        if self.pat[i] == 125:
            self.qmin = n
            self.qmax = n
            self.pos = i + 1
            return true

        if self.pat[i] != 44:
            return false

        i += 1

        var m = 0
        var md = 0

        while i < L and is_digit(self.pat[i]):
            if m <= 1000:
                m = m * 10 + self.pat[i] - 48
            i += 1
            md += 1

        if i >= L or self.pat[i] != 125:
            return false

        self.qmin = n

        if md == 0:
            self.qmax = -1
        else:
            self.qmax = m

        self.pos = i + 1
        return true

    var fn quant(atom: Int) Int:
        let c = self.peek(0)
        var mn = 0
        var mx = -1
        var found = false

        if c == 42:
            found = true
            self.pos += 1
        else if c == 43:
            found = true
            mn = 1
            self.pos += 1
        else if c == 63:
            found = true
            mx = 1
            self.pos += 1
        else if c == 123:
            found = self.brace()

            if found:
                mn = self.qmin
                mx = self.qmax

        if not found:
            return atom

        let k = self.nk[atom]

        if k == K_BOL or k == K_EOL or k == K_WB or k == K_LOOK:
            self.err = "nothing to repeat"
            return -1

        var greedy = 1

        if self.peek(0) == 63:
            greedy = 0
            self.pos += 1

        if (mx >= 0 and mn > mx) or mn > 1000 or mx > 1000:
            self.err = "bad repeat"
            return -1

        let c2 = self.peek(0)

        if c2 == 42 or c2 == 43 or c2 == 63:
            self.err = "nothing to repeat"
            return -1

        if c2 == 123:
            let save = self.pos
            let isq = self.brace()
            self.pos = save

            if isq:
                self.err = "nothing to repeat"
                return -1

        let r = self.node(K_REP, mn, mx, greedy)
        self.nch[r] = atom
        return r

    var fn parse_group() Int:
        var num = -1
        var name = ""
        var kind = 0

        if self.peek(0) == 63:
            let c1 = self.peek(1)

            if c1 == 58:
                self.pos += 2
                kind = 1
            else if c1 == 61:
                self.pos += 2
                kind = 2
            else if c1 == 33:
                self.pos += 2
                kind = 3
            else if c1 == 60:
                let en = self.name_end(self.pos + 2)

                if en < 0:
                    self.err = "bad group"
                    return -1

                name = name_string(self.pat, self.pos + 2, en)
                self.pos = en + 1

                if self.find_name(name) >= 0:
                    self.err = "duplicate group name"
                    return -1
            else:
                self.err = "bad group"
                return -1

        if kind == 0:
            self.ngroups += 1
            num = self.ngroups
            self.gnames.append(name)

        let body = self.parse_alt()
        if self.err != "":
            return -1

        if self.peek(0) != 41:
            self.err = "unmatched ("
            return -1

        self.pos += 1

        if kind == 2 or kind == 3:
            let ln = self.node(K_LOOK, b01(kind == 3), 0, 0)
            self.nch[ln] = body
            return ln

        let gn = self.node(K_GROUP, num, 0, 0)
        self.nch[gn] = body
        return gn

    var fn parse_atom() Int:
        let c = self.pat[self.pos]

        if c == 42 or c == 43 or c == 63:
            self.err = "nothing to repeat"
            return -1

        if c == 40:
            self.pos += 1
            return self.parse_group()

        if c == 91:
            self.pos += 1

            let cl = self.parse_class()
            if self.err != "":
                return -1

            return self.node(K_CLS, cl * 256, 0, 0)

        if c == 46:
            self.pos += 1

            let cl = self.new_class()
            for x in 0..256:
                self.cls[cl * 256 + x] = true
            if not self.dotall:
                self.cls[cl * 256 + 10] = false
            return self.node(K_CLS, cl * 256, 0, 0)

        if c == 94:
            self.pos += 1
            return self.node(K_BOL, 0, b01(self.multi), 0)

        if c == 36:
            self.pos += 1
            return self.node(K_EOL, 0, b01(self.multi), 0)

        if c == 92:
            self.pos += 1
            return self.parse_escape()

        self.pos += 1
        return self.chr_node(c)

    var fn parse_seq() Int:
        let sn = self.node(K_SEQ, 0, 0, 0)
        var last = -1
        let L = self.pat.length()

        while self.pos < L and self.pat[self.pos] != 124 and self.pat[self.pos] != 41:
            let atom = self.parse_atom()
            if self.err != "":
                return -1

            let q = self.quant(atom)
            if self.err != "":
                return -1

            if last < 0:
                self.nch[sn] = q
            else:
                self.nnx[last] = q

            last = q

        return sn

    var fn parse_alt() Int:
        let an = self.node(K_ALT, 0, 0, 0)
        var last = -1

        while true:
            let s = self.parse_seq()
            if self.err != "":
                return -1

            if last < 0:
                self.nch[an] = s
            else:
                self.nnx[last] = s

            last = s

            if self.peek(0) == 124:
                self.pos += 1
            else:
                break

        return an

    var fn parse_top() Unit:
        let L = self.pat.length()

        if L >= 2 and self.pat[0] == 40 and self.pat[1] == 63:
            var i = 2
            var fi = false
            var fm = false
            var fs = false
            var cnt = 0

            while (
                i < L
                and (
                    self.pat[i] == 105
                    or self.pat[i] == 109
                    or self.pat[i] == 115
                )
            ):
                if self.pat[i] == 105:
                    fi = true
                else if self.pat[i] == 109:
                    fm = true
                else:
                    fs = true

                cnt += 1
                i += 1

            if cnt > 0 and i < L and self.pat[i] == 41:
                self.icase = fi
                self.multi = fm
                self.dotall = fs
                self.pos = i + 1

        self.root = self.parse_alt()
        if self.err != "":
            return

        if self.pos < L:
            self.err = "unmatched )"
            return

        for i in 0..self.nk.length():
            if self.nk[i] == K_BREF:
                if self.nc[i] >= 0:
                    let g = self.find_name(self.bnames[self.nc[i]])

                    if g < 0:
                        self.err = "bad backreference"
                        return

                    self.na[i] = g
                else if self.na[i] > self.ngroups:
                    self.err = "bad backreference"
                    return

    # ---- code generation ----

    var fn newslot() Int:
        let s = self.nslots
        self.nslots += 1
        return s

    fn gslot(g: Int) Int:
        return 2 * (self.ngroups + 1) + g - 1

    var fn emit(o: Int, a: Int, b: Int, c: Int, d: Int) Int:
        self.op.append(o)
        self.oa.append(a)
        self.ob.append(b)
        self.oc.append(c)
        self.od.append(d)
        return self.op.length() - 1

    var fn gen(n: Int) Unit:
        let k = self.nk[n]

        if k == K_CHR:
            self.emit(O_CHR, self.na[n], self.nb[n], 0, 0)
        else if k == K_CLS:
            self.emit(O_CLS, self.na[n], 0, 0, 0)
        else if k == K_BOL:
            self.emit(O_BOL, 0, self.nb[n], 0, 0)
        else if k == K_EOL:
            self.emit(O_EOL, 0, self.nb[n], 0, 0)
        else if k == K_WB:
            self.emit(O_WB, self.na[n], 0, 0, 0)
        else if k == K_BREF:
            self.emit(O_BREF, self.na[n], self.nb[n], 0, 0)
        else if k == K_GROUP:
            let g = self.na[n]

            if g < 0:
                self.gen(self.nch[n])
            else:
                let gs = self.gslot(g)
                self.emit(O_OPEN, 2 * g, gs, 0, 0)
                self.gen(self.nch[n])
                self.emit(O_CLOSE, 2 * g, gs, 0, 0)
        else if k == K_LOOK:
            let p = self.emit(O_LOOK, self.na[n], 0, 0, 0)
            self.gen(self.nch[n])
            self.emit(O_LOOKEND, 0, 0, 0, 0)
            self.ob[p] = self.op.length()
        else if k == K_SEQ:
            var c = self.nch[n] + 0

            while c >= 0:
                self.gen(c)
                c = self.nnx[c] + 0
        else if k == K_ALT:
            var jumps = List[Int]()
            var alt = self.nch[n] + 0

            while alt >= 0:
                let has_next = self.nnx[alt] >= 0

                if has_next:
                    let sp = self.emit(O_SPLIT, self.op.length() + 1, 0, 0, 0)
                    self.gen(alt)

                    let j = self.emit(O_JMP, 0, 0, 0, 0)
                    jumps.append(j)
                    self.ob[sp] = self.op.length()
                else:
                    self.gen(alt)

                alt = self.nnx[alt] + 0

            for j in jumps:
                self.oa[j] = self.op.length()
        else if k == K_REP:
            let mn = self.na[n]
            let mx = self.nb[n]
            let greedy = self.nc[n] == 1
            let cnt = self.newslot()
            let ss = self.newslot()
            self.emit(O_SETCONST, cnt, 0, 0, 0)

            var head_op = O_HEADL
            if greedy:
                head_op = O_HEADG

            let head = self.emit(head_op, cnt, mn, mx, 0)
            self.emit(O_SETPOS, ss, 0, 0, 0)
            self.gen(self.nch[n])
            self.emit(O_TAIL, cnt, ss, mn, head)
            self.od[head] = self.op.length()

    var fn compile() Unit:
        self.nslots = 2 * (self.ngroups + 1) + self.ngroups
        self.gen(self.root)
        self.emit(O_MATCH, 0, 0, 0, 0)
        for i in 0..self.nslots:
            self.st.append(-1)

    # ---- matching ----

    var fn push(k: Int, a: Int, b: Int) Unit:
        if self.sp < self.sk.length():
            self.sk[self.sp] = k
            self.sa[self.sp] = a
            self.sb[self.sp] = b
        else:
            self.sk.append(k)
            self.sa.append(a)
            self.sb.append(b)

        self.sp += 1

    var fn setslot(s: Int, v: Int) Unit:
        self.push(1, s, self.st[s])
        self.st[s] = v

    # Pops everything above mark, restoring captures.
    var fn unwind(mark: Int) Unit:
        while self.sp > mark:
            self.sp -= 1
            if self.sk[self.sp] == 1:
                self.st[self.sa[self.sp]] = self.sb[self.sp]

    # Drops backtrack points above mark but keeps capture restores.
    var fn compact(mark: Int) Unit:
        var w = mark

        for i in mark..self.sp:
            if self.sk[i] == 1:
                self.sk[w] = 1
                self.sa[w] = self.sa[i]
                self.sb[w] = self.sb[i]
                w += 1

        self.sp = w

    var fn run(start_pc: Int, start_pos: Int) Bool:
        let base = self.sp
        var pc = start_pc
        var pos = start_pos
        let n = self.subj.length()

        while true:
            let o = self.op[pc]
            let a = self.oa[pc]
            let b = self.ob[pc]
            let c = self.oc[pc]
            let d = self.od[pc]
            var ok = true

            if o == O_CHR:
                if pos < n and (self.subj[pos] == a or self.subj[pos] == b):
                    pos += 1
                    pc += 1
                else:
                    ok = false
            else if o == O_CLS:
                if pos < n and self.cls[a + self.subj[pos]]:
                    pos += 1
                    pc += 1
                else:
                    ok = false
            else if o == O_SPLIT:
                self.push(0, b, pos)
                pc = a
            else if o == O_JMP:
                pc = a
            else if o == O_SETPOS:
                self.setslot(a, pos)
                pc += 1
            else if o == O_SETCONST:
                self.setslot(a, b)
                pc += 1
            else if o == O_OPEN:
                self.setslot(a, -1)
                self.setslot(a + 1, -1)
                self.setslot(b, pos)
                pc += 1
            else if o == O_CLOSE:
                self.setslot(a, self.st[b])
                self.setslot(a + 1, pos)
                pc += 1
            else if o == O_BOL:
                if pos == 0 or (b == 1 and self.subj[pos - 1] == 10):
                    pc += 1
                else:
                    ok = false
            else if o == O_EOL:
                if pos == n or (b == 1 and self.subj[pos] == 10):
                    pc += 1
                else:
                    ok = false
            else if o == O_WB:
                let before = pos > 0 and is_word(self.subj[pos - 1])
                let after = pos < n and is_word(self.subj[pos])
                let boundary = before != after

                if boundary == (a == 0):
                    pc += 1
                else:
                    ok = false
            else if o == O_BREF:
                let s = self.st[2 * a]
                let e = self.st[2 * a + 1]

                if s < 0 or e < 0:
                    ok = false
                else:
                    let ln = e - s

                    if pos + ln > n:
                        ok = false
                    else:
                        var same = true

                        for i in 0..ln:
                            let x = self.subj[s + i]
                            let y = self.subj[pos + i]

                            if x != y:
                                if b == 0:
                                    same = false
                                else if lower_of(x) != lower_of(y):
                                    same = false

                        if same:
                            pos += ln
                            pc += 1
                        else:
                            ok = false
            else if o == O_LOOK:
                let mark = self.sp
                let r = self.run(pc + 1, pos)

                if a == 0:
                    if r:
                        self.compact(mark)
                        pc = b
                    else:
                        ok = false
                else:
                    if r:
                        self.unwind(mark)
                        ok = false
                    else:
                        pc = b
            else if o == O_LOOKEND:
                self.endpos = pos
                return true
            else if o == O_MATCH:
                if self.anchored_end and pos != n:
                    ok = false
                else:
                    self.endpos = pos
                    return true
            else if o == O_HEADG:
                let cnt = self.st[a]

                if cnt < b:
                    pc += 1
                else if c >= 0 and cnt >= c:
                    pc = d
                else:
                    self.push(0, d, pos)
                    pc += 1
            else if o == O_HEADL:
                let cnt = self.st[a]

                if cnt < b:
                    pc += 1
                else if c >= 0 and cnt >= c:
                    pc = d
                else:
                    self.push(0, pc + 1, pos)
                    pc = d
            else if o == O_TAIL:
                let cnt = self.st[a]

                if cnt >= c and pos == self.st[b]:
                    pc += 1
                else:
                    self.setslot(a, cnt + 1)
                    pc = d

            if not ok:
                var resumed = false

                while not resumed:
                    if self.sp == base:
                        return false

                    self.sp -= 1

                    if self.sk[self.sp] == 1:
                        self.st[self.sa[self.sp]] = self.sb[self.sp]
                    else:
                        pc = self.sa[self.sp]
                        pos = self.sb[self.sp]
                        resumed = true

        return false

    # Leftmost match starting at or after begin. Fills st on success.
    var fn search(begin: Int) Bool:
        let L = self.subj.length()
        var s = begin

        while s <= L:
            for i in 0..self.st.length():
                self.st[i] = -1
            self.sp = 0

            if self.run(0, s):
                self.st[0] = s
                self.st[1] = self.endpos
                return true

            if self.anchored_end:
                return false

            s += 1

        return false

    var fn all_matches() List[List[Int]]:
        var res = List[List[Int]]()
        var start0 = 0
        let L = self.subj.length()
        let width = 2 * (self.ngroups + 1)

        while start0 <= L:
            if not self.search(start0):
                break

            var snap = List[Int]()
            for i in 0..width:
                snap.append(self.st[i])
            res.append(snap)

            if self.st[1] > self.st[0]:
                start0 = self.st[1]
            else:
                start0 = self.st[1] + 1

        return res

    fn group_by_name(s: List[Int], a: Int, b: Int) Int:
        if b <= a:
            return -1

        for g in 1..self.ngroups + 1:
            let nm = to_bytes_list(self.gnames[g - 1])

            if nm.length() == b - a:
                var same = true
                for k in 0..nm.length():
                    if nm[k] != s[a + k]:
                        same = false
                if same:
                    return g

        return -1

    fn append_group(out: List[Int], m: List[Int], g: Int) List[Int]:
        var r = out
        let s = m[2 * g]
        let e = m[2 * g + 1]
        if s >= 0 and e >= 0:
            for k in s..e:
                r.append(self.subj[k])
        return r

    var fn expand(repl: List[Int], m: List[Int]) List[Int]:
        var out = List[Int]()
        let L = repl.length()
        var i = 0

        while i < L:
            let c = repl[i]

            if c == 36 and i + 1 < L:
                let d = repl[i + 1]

                if is_digit(d):
                    let g = d - 48

                    if g > self.ngroups:
                        self.err = "bad replacement"
                        return out

                    out = self.append_group(out, m, g)
                    i += 2
                else if d == 36:
                    out.append(36)
                    i += 2
                else if d == 123:
                    var j = i + 2
                    while j < L and repl[j] != 125:
                        j += 1

                    if j >= L:
                        self.err = "bad replacement"
                        return out

                    let g = self.group_by_name(repl, i + 2, j)

                    if g < 0:
                        self.err = "bad replacement"
                        return out

                    out = self.append_group(out, m, g)
                    i = j + 1
                else:
                    out.append(36)
                    i += 1
            else:
                out.append(c)
                i += 1

        return out

    fn group_lines(snap: List[Int]) List[String]:
        var lines = List[String]()

        for g in 0..self.ngroups + 1:
            var label = "{g}"

            if g > 0:
                let nm = self.gnames[g - 1]
                if nm != "":
                    label = "{g} ({nm})"

            let s = snap[2 * g]
            let e = snap[2 * g + 1]

            if s >= 0 and e >= 0:
                lines.append("{label}: {s}..{e} ".concat(quoted(self.subj, s, e)))
            else:
                lines.append("{label}: unset")

        return lines

fn new_re(pat: List[Int]) Re:
    return Re(
        pat: pat, pos: 0, err: "", icase: false, multi: false, dotall: false,
        ngroups: 0, gnames: List[String](), bnames: List[String](), nk: List[Int](),
        na: List[Int](), nb: List[Int](), nc: List[Int](), nch: List[Int](),
        nnx: List[Int](), cls: List[Bool](), ncls: 0, qmin: 0, qmax: 0, root: -1,
        anchored_end: false, op: List[Int](), oa: List[Int](), ob: List[Int](),
        oc: List[Int](), od: List[Int](), nslots: 0, st: List[Int](), sk: List[Int](),
        sa: List[Int](), sb: List[Int](), sp: 0, subj: List[Int](), endpos: 0
    )

fn span_line(s: Int, e: Int, subj: List[Int]) String:
    return "{s}..{e} ".concat(quoted(subj, s, e))

fn run_cmd(f: List[String]) String:
    let cmd = f[0]
    let is_replace = cmd == "replace"
    let known = (
        is_replace
        or cmd == "test"
        or cmd == "match"
        or cmd == "full"
        or cmd == "find-all"
        or cmd == "split"
    )
    if not known:
        return "error: bad command"
    if is_replace and f.length() != 4:
        return "error: bad command"
    if not is_replace and f.length() != 3:
        return "error: bad command"

    let subj = unescape(to_bytes_list(f[2]))
    if is_bad(subj):
        return "error: bad command"

    var repl = List[Int]()

    if is_replace:
        repl = unescape(to_bytes_list(f[3]))
        if is_bad(repl):
            return "error: bad command"

    var re = new_re(to_bytes_list(f[1]))
    re.parse_top()
    if re.err != "":
        return "error: " + re.err

    re.compile()
    re.subj = subj

    if cmd == "test":
        if re.search(0):
            return "true"

        return "false"

    if cmd == "match" or cmd == "full":
        re.anchored_end = cmd == "full"
        if not re.search(0):
            return "no match"

        var snap = List[Int]()
        for i in 0..2 * (re.ngroups + 1):
            snap.append(re.st[i])
        return re.group_lines(snap).join("\n")

    if cmd == "find-all":
        let ms = re.all_matches()
        var lines = List[String]()
        for m in ms:
            lines.append(span_line(m[0], m[1], re.subj))
        lines.append("({ms.length()} matches)")
        return lines.join("\n")

    if cmd == "split":
        let ms = re.all_matches()
        var pieces = List[String]()
        var last = 0

        for m in ms:
            if m[1] > m[0]:
                pieces.append(quoted(re.subj, last, m[0]))
                last = m[1]

        pieces.append(quoted(re.subj, last, re.subj.length()))
        pieces.append("({pieces.length()} pieces)")
        return pieces.join("\n")

    # replace
    let ms = re.all_matches()
    var res = List[Int]()
    var last = 0
    let L = re.subj.length()

    for m in ms:
        for i in last..m[0]:
            res.append(re.subj[i])

        let piece = re.expand(repl, m)
        if re.err != "":
            return "error: " + re.err

        for x in piece:
            res.append(x)
        last = m[1]

    for i in last..L:
        res.append(re.subj[i])
    return quoted(res, 0, res.length())

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var out = List[String]()
    for line in lines:
        if line.length() > 0:
            out.append(run_cmd(line.split("\t")))
    if out.length() > 0:
        stdout().write(out.join("\n").concat("\n")).get()
    return 0

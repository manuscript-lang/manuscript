// In-memory SQL engine: reads a script on stdin, executes statements in order.

import read_all from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"

// ---------- values and records ----------

enum Val:
    I(v: Int)
    T(s: String)
    B(b: Bool)
    N

type Tok:
    kind: String
    text: String

type ColDef:
    name: String
    typ: String
    pk: Bool
    notnull: Bool

type Expr:
    kind: String
    op: String
    tbl: String
    name: String
    lv: Val
    kids: List[Expr]
    neg: Bool
    distinct: Bool
    star: Bool
    idx: Int

type Assign:
    col: String
    expr: Expr

type TRef:
    name: String
    alias: String

type Join:
    is_left: Bool
    tref: TRef
    onc: Expr

type SelItem:
    kind: String
    tbl: String
    expr: Expr
    alias: String
    has_alias: Bool

type OrdItem:
    expr: Expr
    desc: Bool

type Select:
    distinct: Bool
    items: List[SelItem]
    froms: List[TRef]
    joins: List[Join]
    has_where: Bool
    cond: Expr
    gcols: List[Expr]
    has_hcond: Bool
    hcond: Expr
    ords: List[OrdItem]
    has_limit: Bool
    lim: Int
    off: Int

type Stmt:
    kind: String
    name: String
    coldefs: List[ColDef]
    has_cols: Bool
    cols: List[String]
    rows: List[List[Expr]]
    assigns: List[Assign]
    has_where: Bool
    cond: Expr
    sel: Select

type Table:
    name: String
    cols: List[ColDef]
    rows: List[List[Val]]

type Src:
    alias: String
    cols: List[String]
    off: Int

type OutCol:
    name: String
    expr: Expr

type OutRow:
    vals: List[Val]
    keys: List[Val]

type OKey:
    pos: Int
    expr: Expr
    desc: Bool

type P:
    toks: List[Tok]
    pos: Int

// ---------- constructors ----------

fn mk(kind: String) Expr:
    return Expr(kind: kind, op: "", tbl: "", name: "", lv: Val.N, kids: List[Expr](), neg: false, distinct: false, star: false, idx: -1)

fn blank_expr() Expr:
    return mk("lit")

fn lit_e(v: Val) Expr:
    var e = mk("lit")
    e.lv = v
    return e

fn colref(tbl: String, name: String) Expr:
    var e = mk("col")
    e.tbl = tbl
    e.name = name
    return e

fn colexpr(idx: Int, name: String) Expr:
    var e = mk("col")
    e.idx = idx
    e.name = name
    return e

fn un_e(op: String, a: Expr) Expr:
    var e = mk("un")
    e.op = op
    e.kids.append(a)
    return e

fn bin_e(op: String, a: Expr, b: Expr) Expr:
    var e = mk("bin")
    e.op = op
    e.kids.append(a)
    e.kids.append(b)
    return e

fn blank_select() Select:
    return Select(distinct: false, items: List[SelItem](), froms: List[TRef](), joins: List[Join](), has_where: false, cond: blank_expr(), gcols: List[Expr](), has_hcond: false, hcond: blank_expr(), ords: List[OrdItem](), has_limit: false, lim: 0, off: 0)

fn blank_stmt() Stmt:
    return Stmt(kind: "", name: "", coldefs: List[ColDef](), has_cols: false, cols: List[String](), rows: List[List[Expr]](), assigns: List[Assign](), has_where: false, cond: blank_expr(), sel: blank_select())

// ---------- lexer ----------

fn is_space(c: String) Bool:
    return c == " " or c == "\t" or c == "\r" or c == "\n"

fn is_digit(c: String) Bool:
    return "0123456789".contains(c)

fn is_alpha(c: String) Bool:
    return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_".contains(c)

fn is_keyword(up: String) Bool:
    let kws = ["SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET", "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN", "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"]
    return kws.contains(up)

fn chars_of(s: String) List[String]:
    var out = List[String]()
    if s.length() == 0:
        return out
    return s.split("")

// True when the digit string fits in a signed 64-bit integer.
fn int_ok(num: String) Bool:
    let ds = chars_of(num)
    var v = 0
    for d in ds:
        let x = "0123456789".index_of(d).get(default: 0)
        if v > 922337203685477580:
            return false
        if v == 922337203685477580 and x > 7:
            return false
        v = v * 10 + x
    return true

fn int_of(num: String) Int:
    var v = 0
    for d in chars_of(num):
        let x = "0123456789".index_of(d).get(default: 0)
        v = v * 10 + x
    return v

fn lex(cs: List[String]) List[Tok]:
    var toks = List[Tok]()
    let n = cs.length()
    var i = 0
    while i < n:
        let c = cs[i]
        if is_space(c):
            i += 1
        else if c == "-" and i + 1 < n and cs[i + 1] == "-":
            while i < n and cs[i] != "\n":
                i += 1
        else if c == ";":
            toks.append(Tok(kind: "semi", text: ";"))
            i += 1
        else if c == "'":
            var s = ""
            var closed = false
            i += 1
            while i < n:
                if cs[i] == "'":
                    if i + 1 < n and cs[i + 1] == "'":
                        s = s.concat("'")
                        i += 2
                    else:
                        closed = true
                        i += 1
                        break
                else:
                    s = s.concat(cs[i])
                    i += 1
            if closed:
                toks.append(Tok(kind: "str", text: s))
            else:
                toks.append(Tok(kind: "err", text: "unterminated"))
        else if is_digit(c):
            var num = ""
            while i < n and is_digit(cs[i]):
                num = num.concat(cs[i])
                i += 1
            if int_ok(num):
                toks.append(Tok(kind: "int", text: num))
            else:
                toks.append(Tok(kind: "err", text: num))
        else if is_alpha(c):
            var word = ""
            while i < n and (is_alpha(cs[i]) or is_digit(cs[i])):
                word = word.concat(cs[i])
                i += 1
            let up = word.upper()
            if is_keyword(up):
                toks.append(Tok(kind: "kw", text: up))
            else:
                toks.append(Tok(kind: "id", text: word))
        else:
            var two = ""
            if i + 1 < n:
                two = c.concat(cs[i + 1])
            if two == "<>" or two == "!=" or two == "<=" or two == ">=" or two == "||":
                if two == "!=":
                    toks.append(Tok(kind: "op", text: "<>"))
                else:
                    toks.append(Tok(kind: "op", text: two))
                i += 2
            else if "=<>+-*/%(),.".contains(c):
                toks.append(Tok(kind: "op", text: c.clone()))
                i += 1
            else:
                toks.append(Tok(kind: "err", text: c.clone()))
                i += 1
    return toks

// ---------- parser ----------

impl P:
    fn k() String:
        if self.pos < self.toks.length():
            return self.toks[self.pos].kind.clone()
        return "eof"

    fn t() String:
        if self.pos < self.toks.length():
            return self.toks[self.pos].text.clone()
        return ""

    fn kat(off: Int) String:
        if self.pos + off < self.toks.length():
            return self.toks[self.pos + off].kind.clone()
        return "eof"

    fn tat(off: Int) String:
        if self.pos + off < self.toks.length():
            return self.toks[self.pos + off].text.clone()
        return ""

    fn is_kw(s: String) Bool:
        return self.k() == "kw" and self.t() == s

    fn is_op(s: String) Bool:
        return self.k() == "op" and self.t() == s

    var fn accept_kw(s: String) Bool:
        if self.is_kw(s):
            self.pos += 1
            return true
        return false

    var fn accept_op(s: String) Bool:
        if self.is_op(s):
            self.pos += 1
            return true
        return false

    var fn expect_kw(s: String) Unit!String:
        if not self.accept_kw(s):
            return error("syntax error")
        return ok(unit)

    var fn expect_op(s: String) Unit!String:
        if not self.accept_op(s):
            return error("syntax error")
        return ok(unit)

    var fn ident() String!String:
        if self.k() != "id":
            return error("syntax error")
        let s = self.t()
        self.pos += 1
        return ok(s)

    var fn p_colref() Expr!String:
        let a = try self.ident()
        if self.accept_op("."):
            let b = try self.ident()
            return ok(colref(a, b))
        return ok(colref("", a))

    var fn p_primary() Expr!String:
        let kd = self.k()
        if kd == "int":
            let v = int_of(self.t())
            self.pos += 1
            return ok(lit_e(Val.I(v)))
        if kd == "str":
            let s = self.t()
            self.pos += 1
            return ok(lit_e(Val.T(s)))
        if self.is_kw("NULL"):
            self.pos += 1
            return ok(lit_e(Val.N))
        if self.is_op("("):
            self.pos += 1
            let inner = try self.p_or()
            try self.expect_op(")")
            return ok(inner)
        if kd == "id":
            let name = self.t()
            self.pos += 1
            if self.is_op("("):
                self.pos += 1
                var e = mk("call")
                e.op = name.upper()
                if self.accept_kw("DISTINCT"):
                    e.distinct = true
                if self.accept_op("*"):
                    e.star = true
                else if not self.is_op(")"):
                    let a1 = try self.p_or()
                    e.kids.append(a1)
                    while self.accept_op(","):
                        let a2 = try self.p_or()
                        e.kids.append(a2)
                try self.expect_op(")")
                return ok(e)
            if self.is_op("."):
                self.pos += 1
                let col = try self.ident()
                return ok(colref(name, col))
            return ok(colref("", name))
        return error("syntax error")

    var fn p_unary() Expr!String:
        if self.is_op("-"):
            self.pos += 1
            let inner = try self.p_unary()
            return ok(un_e("NEG", inner))
        return self.p_primary()

    var fn p_mul() Expr!String:
        var l = try self.p_unary()
        while self.k() == "op" and (self.t() == "*" or self.t() == "/" or self.t() == "%"):
            let op = self.t()
            self.pos += 1
            let r = try self.p_unary()
            l = bin_e(op, l, r)
        return ok(l)

    var fn p_add() Expr!String:
        var l = try self.p_mul()
        while self.k() == "op" and (self.t() == "+" or self.t() == "-" or self.t() == "||"):
            let op = self.t()
            self.pos += 1
            let r = try self.p_mul()
            l = bin_e(op, l, r)
        return ok(l)

    var fn p_cmp() Expr!String:
        let l = try self.p_add()
        if self.k() == "op" and (self.t() == "=" or self.t() == "<>" or self.t() == "<" or self.t() == "<=" or self.t() == ">" or self.t() == ">="):
            let op = self.t()
            self.pos += 1
            let r = try self.p_add()
            return ok(bin_e(op, l, r))
        if self.accept_kw("IS"):
            let neg_is = self.accept_kw("NOT")
            try self.expect_kw("NULL")
            var e = un_e("ISNULL", l)
            e.neg = neg_is
            return ok(e)
        var neg = false
        if self.is_kw("NOT") and self.kat(1) == "kw" and (self.tat(1) == "LIKE" or self.tat(1) == "IN" or self.tat(1) == "BETWEEN"):
            self.pos += 1
            neg = true
        if self.accept_kw("LIKE"):
            let r = try self.p_add()
            var e = bin_e("LIKE", l, r)
            e.neg = neg
            return ok(e)
        if self.accept_kw("IN"):
            try self.expect_op("(")
            var kids = List[Expr]()
            kids.append(l)
            let first = try self.p_or()
            kids.append(first)
            while self.accept_op(","):
                let more = try self.p_or()
                kids.append(more)
            try self.expect_op(")")
            var e = mk("in")
            e.kids = kids
            e.neg = neg
            return ok(e)
        if self.accept_kw("BETWEEN"):
            let lo = try self.p_add()
            try self.expect_kw("AND")
            let hi = try self.p_add()
            var kids = List[Expr]()
            kids.append(l)
            kids.append(lo)
            kids.append(hi)
            var e = mk("between")
            e.kids = kids
            e.neg = neg
            return ok(e)
        if neg:
            return error("syntax error")
        return ok(l)

    var fn p_not() Expr!String:
        if self.accept_kw("NOT"):
            let inner = try self.p_not()
            return ok(un_e("NOT", inner))
        return self.p_cmp()

    var fn p_and() Expr!String:
        var l = try self.p_not()
        while self.accept_kw("AND"):
            let r = try self.p_not()
            l = bin_e("AND", l, r)
        return ok(l)

    var fn p_or() Expr!String:
        var l = try self.p_and()
        while self.accept_kw("OR"):
            let r = try self.p_and()
            l = bin_e("OR", l, r)
        return ok(l)

    var fn p_item() SelItem!String:
        var it = SelItem(kind: "expr", tbl: "", expr: blank_expr(), alias: "", has_alias: false)
        if self.accept_op("*"):
            it.kind = "all"
            return ok(it)
        if self.k() == "id" and self.kat(1) == "op" and self.tat(1) == "." and self.kat(2) == "op" and self.tat(2) == "*":
            it.kind = "tstar"
            it.tbl = self.t()
            self.pos += 3
            return ok(it)
        it.expr = try self.p_or()
        if self.accept_kw("AS"):
            it.alias = try self.ident()
            it.has_alias = true
        return ok(it)

    var fn p_tref() TRef!String:
        let nm = try self.ident()
        var tr = TRef(name: nm.clone(), alias: nm)
        if self.accept_kw("AS"):
            tr.alias = try self.ident()
        else if self.k() == "id":
            tr.alias = try self.ident()
        return ok(tr)

    var fn p_select() Select!String:
        var s = blank_select()
        s.distinct = self.accept_kw("DISTINCT")
        let first = try self.p_item()
        s.items.append(first)
        while self.accept_op(","):
            let it = try self.p_item()
            s.items.append(it)
        if self.accept_kw("FROM"):
            let tr = try self.p_tref()
            s.froms.append(tr)
            while self.is_kw("JOIN") or self.is_kw("LEFT") or self.is_kw("INNER"):
                var is_left = false
                if self.is_kw("LEFT"):
                    is_left = true
                    self.pos += 1
                else if self.is_kw("INNER"):
                    self.pos += 1
                try self.expect_kw("JOIN")
                let jt = try self.p_tref()
                try self.expect_kw("ON")
                let on = try self.p_or()
                s.joins.append(Join(is_left: is_left, tref: jt, onc: on))
        if self.accept_kw("WHERE"):
            s.has_where = true
            s.cond = try self.p_or()
        if self.accept_kw("GROUP"):
            try self.expect_kw("BY")
            let g1 = try self.p_colref()
            s.gcols.append(g1)
            while self.accept_op(","):
                let g2 = try self.p_colref()
                s.gcols.append(g2)
        if self.accept_kw("HAVING"):
            s.has_hcond = true
            s.hcond = try self.p_or()
        if self.accept_kw("ORDER"):
            try self.expect_kw("BY")
            var more = true
            while more:
                let oe = try self.p_or()
                var desc = false
                if self.accept_kw("DESC"):
                    desc = true
                else:
                    let _asc = self.accept_kw("ASC")
                s.ords.append(OrdItem(expr: oe, desc: desc))
                more = self.accept_op(",")
        if self.accept_kw("LIMIT"):
            if self.k() != "int":
                return error("syntax error")
            s.has_limit = true
            s.lim = int_of(self.t())
            self.pos += 1
            if self.accept_kw("OFFSET"):
                if self.k() != "int":
                    return error("syntax error")
                s.off = int_of(self.t())
                self.pos += 1
        return ok(s)

    var fn p_coldef() ColDef!String:
        var cd = ColDef(name: "", typ: "", pk: false, notnull: false)
        cd.name = try self.ident()
        let tw = try self.ident()
        let up = tw.upper()
        if up != "INT" and up != "TEXT":
            return error("syntax error")
        cd.typ = up
        var more = true
        while more:
            if self.accept_kw("PRIMARY"):
                try self.expect_kw("KEY")
                cd.pk = true
            else if self.accept_kw("NOT"):
                try self.expect_kw("NULL")
                cd.notnull = true
            else:
                more = false
        return ok(cd)

    var fn p_value_row() List[Expr]!String:
        try self.expect_op("(")
        var row = List[Expr]()
        let first = try self.p_or()
        row.append(first)
        while self.accept_op(","):
            let nxt = try self.p_or()
            row.append(nxt)
        try self.expect_op(")")
        return ok(row)

    var fn statement() Stmt!String:
        var st = blank_stmt()
        if self.accept_kw("CREATE"):
            try self.expect_kw("TABLE")
            st.kind = "create"
            st.name = try self.ident()
            try self.expect_op("(")
            let c1 = try self.p_coldef()
            st.coldefs.append(c1)
            while self.accept_op(","):
                let c2 = try self.p_coldef()
                st.coldefs.append(c2)
            try self.expect_op(")")
            return ok(st)
        if self.accept_kw("DROP"):
            try self.expect_kw("TABLE")
            st.kind = "drop"
            st.name = try self.ident()
            return ok(st)
        if self.accept_kw("INSERT"):
            try self.expect_kw("INTO")
            st.kind = "insert"
            st.name = try self.ident()
            if self.accept_op("("):
                st.has_cols = true
                let c1 = try self.ident()
                st.cols.append(c1)
                while self.accept_op(","):
                    let c2 = try self.ident()
                    st.cols.append(c2)
                try self.expect_op(")")
            try self.expect_kw("VALUES")
            let r1 = try self.p_value_row()
            st.rows.append(r1)
            while self.accept_op(","):
                let r2 = try self.p_value_row()
                st.rows.append(r2)
            return ok(st)
        if self.accept_kw("UPDATE"):
            st.kind = "update"
            st.name = try self.ident()
            try self.expect_kw("SET")
            var more = true
            while more:
                let cn = try self.ident()
                try self.expect_op("=")
                let ve = try self.p_or()
                st.assigns.append(Assign(col: cn, expr: ve))
                more = self.accept_op(",")
            if self.accept_kw("WHERE"):
                st.has_where = true
                st.cond = try self.p_or()
            return ok(st)
        if self.accept_kw("DELETE"):
            try self.expect_kw("FROM")
            st.kind = "delete"
            st.name = try self.ident()
            if self.accept_kw("WHERE"):
                st.has_where = true
                st.cond = try self.p_or()
            return ok(st)
        if self.accept_kw("SELECT"):
            st.kind = "select"
            st.sel = try self.p_select()
            return ok(st)
        return error("syntax error")

fn parse_stmt(toks: List[Tok]) Stmt!String:
    for t in toks:
        if t.kind == "err":
            return error("syntax error")
    var p = P(toks: toks, pos: 0)
    let st = try p.statement()
    if p.pos != p.toks.length():
        return error("syntax error")
    return ok(st)

// ---------- value helpers ----------

fn tag(v: Val) Int:
    match v:
        I(_x):
            return 1
        T(_s):
            return 2
        B(_b):
            return 3
        N:
            return 0

fn is_null(v: Val) Bool:
    return tag(v) == 0

fn is_false(v: Val) Bool:
    return tag(v) == 3 and not bval(v)

fn ival(v: Val) Int:
    match v:
        I(x):
            return x
        _:
            return 0

fn sval(v: Val) String:
    match v:
        T(s):
            return s.clone()
        _:
            return ""

fn bval(v: Val) Bool:
    match v:
        B(b):
            return b
        _:
            return false

fn fmt_val(v: Val) String:
    match v:
        I(x):
            return "{x}"
        T(s):
            return s.clone()
        B(b):
            if b:
                return "true"
            return "false"
        N:
            return "NULL"

fn key_str(v: Val) String:
    match v:
        I(x):
            return "I{x}|"
        T(s):
            return "T{s.byte_length()}:{s}|"
        B(b):
            if b:
                return "B1|"
            return "B0|"
        N:
            return "N|"

fn rowkey(vals: List[Val]) String:
    var out = ""
    for v in vals:
        out = out.concat(key_str(v))
    return out

// Three-valued truth for WHERE / HAVING / ON conditions.
fn truth(v: Val) Bool!String:
    if tag(v) == 3:
        return ok(bval(v))
    if tag(v) == 0:
        return ok(false)
    return error("type error")

fn cmp_vals(a: Val, b: Val) Int!String:
    let ta = tag(a)
    let tb = tag(b)
    if ta == 1 and tb == 1:
        let x = ival(a)
        let y = ival(b)
        if x < y:
            return ok(-1)
        if x > y:
            return ok(1)
        return ok(0)
    if ta == 2 and tb == 2:
        let x = sval(a)
        let y = sval(b)
        if x < y:
            return ok(-1)
        if x > y:
            return ok(1)
        return ok(0)
    return error("type error")

fn rank(v: Val) Int:
    let t = tag(v)
    if t == 0:
        return 0
    if t == 3:
        return 1
    if t == 1:
        return 2
    return 3

// Total order used by ORDER BY: NULL < boolean < INT < TEXT.
fn cmp_key(a: Val, b: Val) Int:
    let ra = rank(a)
    let rb = rank(b)
    if ra != rb:
        if ra < rb:
            return -1
        return 1
    if ra == 2:
        let x = ival(a)
        let y = ival(b)
        if x < y:
            return -1
        if x > y:
            return 1
        return 0
    if ra == 3:
        let x = sval(a)
        let y = sval(b)
        if x < y:
            return -1
        if x > y:
            return 1
        return 0
    if ra == 1:
        let x = bval(a)
        let y = bval(b)
        if x == y:
            return 0
        if y:
            return -1
        return 1
    return 0

fn and3(a: Val, b: Val) Val:
    if is_false(a) or is_false(b):
        return Val.B(false)
    if is_null(a) or is_null(b):
        return Val.N
    return Val.B(true)

fn not3(a: Val) Val:
    if is_null(a):
        return Val.N
    return Val.B(not bval(a))

fn dedupe_if(vals: List[Val], on: Bool) List[Val]:
    if not on:
        return vals.clone()
    var seen = Set[String]()
    var out = List[Val]()
    for v in vals:
        let k = key_str(v)
        if not seen.contains(k):
            seen.add(k)
            out.append(v.clone())
    return out

fn chars_eq(a: String, b: String) Bool:
    return a == b

fn like_match(s: List[String], p: List[String]) Bool:
    var i = 0
    var j = 0
    var star = -1
    var mark = 0
    let ns = s.length()
    let np = p.length()
    while i < ns:
        if j < np and p[j] == "%":
            star = j
            mark = i
            j += 1
        else if j < np and (p[j] == "_" or p[j] == s[i]):
            i += 1
            j += 1
        else if star >= 0:
            j = star + 1
            mark += 1
            i = mark
        else:
            return false
    while j < np and p[j] == "%":
        j += 1
    return j == np

fn ascii_case(s: String, up: Bool) String:
    var out = ""
    let cs = chars_of(s)
    for c in cs:
        if up and "abcdefghijklmnopqrstuvwxyz".contains(c):
            out = out.concat(c.upper())
        else if not up and "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(c):
            out = out.concat(c.lower())
        else:
            out = out.concat(c)
    return out

fn substr(s: String, start: Int, len: Int) String:
    if len <= 0:
        return ""
    let cs = chars_of(s)
    let n = cs.length()
    var lo = start
    if lo < 1:
        lo = 1
    var hi = start + len - 1
    if hi > n:
        hi = n
    var out = ""
    var p = lo
    while p <= hi:
        out = out.concat(cs[p - 1])
        p += 1
    return out

// ---------- expression analysis ----------

fn is_agg(nm: String) Bool:
    return nm == "COUNT" or nm == "SUM" or nm == "MIN" or nm == "MAX"

fn is_scalar_fn(nm: String) Bool:
    return nm == "UPPER" or nm == "LOWER" or nm == "LENGTH" or nm == "ABS" or nm == "SUBSTR" or nm == "COALESCE"

fn scalar_arity_ok(nm: String, n: Int, star: Bool) Bool:
    if star:
        return false
    if nm == "SUBSTR":
        return n == 3
    if nm == "COALESCE":
        return n >= 1
    return n == 1

fn has_agg(e: Expr) Bool:
    if e.kind == "call" and is_agg(e.op):
        return true
    for k in e.kids:
        if has_agg(k):
            return true
    return false

fn lookup_col(sc: List[Src], nsrc: Int, tbl: String, name: String) Int!String:
    var found = -1
    var count = 0
    var i = 0
    while i < nsrc:
        if tbl == "" or tbl == sc[i].alias:
            var j = 0
            while j < sc[i].cols.length():
                if sc[i].cols[j] == name:
                    found = sc[i].off + j
                    count += 1
                j += 1
        i += 1
    if count == 0:
        if tbl == "":
            return error("no such column: {name}")
        return error("no such column: {tbl}.{name}")
    if count > 1:
        return error("ambiguous column: {name}")
    return ok(found)

// Resolves column references to row indexes and checks names, functions,
// arities and aggregate placement.
fn resolve(e: Expr, sc: List[Src], nsrc: Int, agg_ok: Bool) Expr!String:
    if e.kind == "lit":
        return ok(e.clone())
    if e.kind == "col":
        var c = e.clone()
        c.idx = try lookup_col(sc, nsrc, e.tbl, e.name)
        return ok(c)
    var r = e.clone()
    var kid_agg = agg_ok
    if e.kind == "call":
        let nm = e.op
        if is_agg(nm):
            if nm == "COUNT":
                if e.star:
                    if e.distinct:
                        return error("wrong number of arguments to COUNT")
                else if e.kids.length() != 1:
                    return error("wrong number of arguments to COUNT")
            else if e.star or e.kids.length() != 1:
                return error("wrong number of arguments to {nm}")
            if not agg_ok:
                return error("misuse of aggregate")
            kid_agg = false
        else:
            if not is_scalar_fn(nm):
                return error("no such function: {nm}")
            if not scalar_arity_ok(nm, e.kids.length(), e.star):
                return error("wrong number of arguments to {nm}")
    var nk = List[Expr]()
    for k in e.kids:
        let rk = try resolve(k, sc, nsrc, kid_agg)
        nk.append(rk)
    r.kids = nk
    return ok(r)

// In an aggregated query, columns outside aggregates must be grouped.
fn check_grouped(e: Expr, gidx: List[Int]) Unit!String:
    if e.kind == "col":
        if not gidx.contains(e.idx):
            if e.tbl == "":
                return error("column {e.name} must appear in GROUP BY")
            return error("column {e.tbl}.{e.name} must appear in GROUP BY")
        return ok(unit)
    if e.kind == "call" and is_agg(e.op):
        return ok(unit)
    for k in e.kids:
        try check_grouped(k, gidx)
    return ok(unit)

// ---------- evaluation ----------

fn logic(e: Expr, row: List[Val], grp: List[List[Val]]) Val!String:
    let is_and = e.op == "AND"
    let l = try eval(e.kids[0], row, grp)
    if is_and and is_false(l):
        return ok(Val.B(false))
    if not is_and and tag(l) == 3 and bval(l):
        return ok(Val.B(true))
    let r = try eval(e.kids[1], row, grp)
    if tag(l) != 0 and tag(l) != 3:
        return error("type error")
    if tag(r) != 0 and tag(r) != 3:
        return error("type error")
    let ln = is_null(l)
    let rn = is_null(r)
    if is_and:
        if is_false(r):
            return ok(Val.B(false))
        if ln or rn:
            return ok(Val.N)
        return ok(Val.B(true))
    if tag(r) == 3 and bval(r):
        return ok(Val.B(true))
    if ln or rn:
        return ok(Val.N)
    return ok(Val.B(false))

fn binop(op: String, l: Val, r: Val, neg: Bool) Val!String:
    if op == "||":
        if is_null(l) or is_null(r):
            return ok(Val.N)
        if tag(l) != 2 or tag(r) != 2:
            return error("type error")
        return ok(Val.T(sval(l).concat(sval(r))))
    if op == "LIKE":
        if is_null(l) or is_null(r):
            return ok(Val.N)
        if tag(l) != 2 or tag(r) != 2:
            return error("type error")
        var m = like_match(chars_of(sval(l)), chars_of(sval(r)))
        if neg:
            m = not m
        return ok(Val.B(m))
    if is_null(l) or is_null(r):
        return ok(Val.N)
    if op == "+" or op == "-" or op == "*" or op == "/" or op == "%":
        if tag(l) != 1 or tag(r) != 1:
            return error("type error")
        let a = ival(l)
        let b = ival(r)
        if op == "+":
            return ok(Val.I(a + b))
        if op == "-":
            return ok(Val.I(a - b))
        if op == "*":
            return ok(Val.I(a * b))
        if b == 0:
            return error("division by zero")
        if op == "/":
            return ok(Val.I(a / b))
        return ok(Val.I(a % b))
    let c = try cmp_vals(l, r)
    if op == "=":
        return ok(Val.B(c == 0))
    if op == "<>":
        return ok(Val.B(c != 0))
    if op == "<":
        return ok(Val.B(c < 0))
    if op == "<=":
        return ok(Val.B(c <= 0))
    if op == ">":
        return ok(Val.B(c > 0))
    return ok(Val.B(c >= 0))

fn eval_in(e: Expr, row: List[Val], grp: List[List[Val]]) Val!String:
    let x = try eval(e.kids[0], row, grp)
    var found = false
    var sawnull = false
    var i = 1
    while i < e.kids.length() and not found:
        let v = try eval(e.kids[i], row, grp)
        if is_null(v):
            sawnull = true
        else if not is_null(x):
            let c = try cmp_vals(x, v)
            if c == 0:
                found = true
        i += 1
    var res = Val.B(false)
    if is_null(x):
        res = Val.N
    else if found:
        res = Val.B(true)
    else if sawnull:
        res = Val.N
    if e.neg:
        res = not3(res)
    return ok(res)

fn eval_between(e: Expr, row: List[Val], grp: List[List[Val]]) Val!String:
    let x = try eval(e.kids[0], row, grp)
    let lo = try eval(e.kids[1], row, grp)
    let hi = try eval(e.kids[2], row, grp)
    let ge = try binop(">=", x.clone(), lo, false)
    var res = ge.clone()
    if not is_false(ge):
        let le = try binop("<=", x, hi, false)
        res = and3(ge, le)
    if e.neg:
        res = not3(res)
    return ok(res)

fn scalar_fn(nm: String, vals: List[Val]) Val!String:
    if nm == "COALESCE":
        for v in vals:
            if not is_null(v):
                return ok(v.clone())
        return ok(Val.N)
    for v in vals:
        if is_null(v):
            return ok(Val.N)
    if nm == "UPPER":
        if tag(vals[0]) != 2:
            return error("type error")
        return ok(Val.T(ascii_case(sval(vals[0]), true)))
    if nm == "LOWER":
        if tag(vals[0]) != 2:
            return error("type error")
        return ok(Val.T(ascii_case(sval(vals[0]), false)))
    if nm == "LENGTH":
        if tag(vals[0]) != 2:
            return error("type error")
        return ok(Val.I(sval(vals[0]).byte_length()))
    if nm == "ABS":
        if tag(vals[0]) != 1:
            return error("type error")
        let x = ival(vals[0])
        if x < 0:
            return ok(Val.I(0 - x))
        return ok(Val.I(x))
    // SUBSTR
    if tag(vals[0]) != 2 or tag(vals[1]) != 1 or tag(vals[2]) != 1:
        return error("type error")
    return ok(Val.T(substr(sval(vals[0]), ival(vals[1]), ival(vals[2]))))

fn eval_agg(e: Expr, grp: List[List[Val]]) Val!String:
    let nm = e.op
    if nm == "COUNT" and e.star:
        return ok(Val.I(grp.length()))
    let none_g = List[List[Val]]()
    var vals = List[Val]()
    for r in grp:
        let v = try eval(e.kids[0], r, none_g)
        if is_null(v):
            continue
        if nm == "SUM" and tag(v) != 1:
            return error("type error")
        if nm == "MIN" or nm == "MAX":
            if tag(v) != 1 and tag(v) != 2:
                return error("type error")
            if vals.length() > 0 and tag(vals[0]) != tag(v):
                return error("type error")
        vals.append(v)
    let src = dedupe_if(vals, e.distinct)
    if nm == "COUNT":
        return ok(Val.I(src.length()))
    if src.length() == 0:
        return ok(Val.N)
    if nm == "SUM":
        var total = 0
        for v in src:
            total += ival(v)
        return ok(Val.I(total))
    var best = src[0].clone()
    for v in src:
        let c = try cmp_vals(v, best)
        if nm == "MIN" and c < 0:
            best = v.clone()
        if nm == "MAX" and c > 0:
            best = v.clone()
    return ok(best)

fn eval(e: Expr, row: List[Val], grp: List[List[Val]]) Val!String:
    if e.kind == "lit":
        return ok(e.lv.clone())
    if e.kind == "col":
        return ok(row[e.idx].clone())
    if e.kind == "un":
        let v = try eval(e.kids[0], row, grp)
        if e.op == "NEG":
            if is_null(v):
                return ok(Val.N)
            if tag(v) != 1:
                return error("type error")
            return ok(Val.I(0 - ival(v)))
        if e.op == "NOT":
            if is_null(v):
                return ok(Val.N)
            if tag(v) != 3:
                return error("type error")
            return ok(Val.B(not bval(v)))
        var isn = is_null(v)
        if e.neg:
            isn = not isn
        return ok(Val.B(isn))
    if e.kind == "bin":
        if e.op == "AND" or e.op == "OR":
            return logic(e, row, grp)
        let l = try eval(e.kids[0], row, grp)
        let r = try eval(e.kids[1], row, grp)
        return binop(e.op, l, r, e.neg)
    if e.kind == "in":
        return eval_in(e, row, grp)
    if e.kind == "between":
        return eval_between(e, row, grp)
    if e.kind == "call":
        if is_agg(e.op):
            return eval_agg(e, grp)
        var vals = List[Val]()
        for a in e.kids:
            let v = try eval(a, row, grp)
            vals.append(v)
        return scalar_fn(e.op, vals)
    return error("type error")

// ---------- catalog helpers ----------

fn find_table(db: List[Table], name: String) Int:
    var i = 0
    while i < db.length():
        if db[i].name == name:
            return i
        i += 1
    return -1

fn col_index(cols: List[ColDef], name: String) Int:
    var i = 0
    while i < cols.length():
        if cols[i].name == name:
            return i
        i += 1
    return -1

fn pk_index(cols: List[ColDef]) Int:
    var i = 0
    while i < cols.length():
        if cols[i].pk:
            return i
        i += 1
    return -1

// Per-row constraints in column declaration order.
fn check_row(cols: List[ColDef], vals: List[Val]) Unit!String:
    var j = 0
    while j < cols.length():
        let v = vals[j]
        if is_null(v):
            if cols[j].notnull or cols[j].pk:
                return error("NOT NULL constraint failed: {cols[j].name}")
        else if cols[j].typ == "INT" and tag(v) != 1:
            return error("type mismatch in column {cols[j].name}")
        else if cols[j].typ == "TEXT" and tag(v) != 2:
            return error("type mismatch in column {cols[j].name}")
        j += 1
    return ok(unit)

// Duplicate primary key check over existing rows followed by added rows.
fn check_dups(cols: List[ColDef], old: List[List[Val]], added: List[List[Val]]) Unit!String:
    let p = pk_index(cols)
    if p < 0:
        return ok(unit)
    var seen = Set[String]()
    for r in old:
        seen.add(key_str(r[p]))
    for r in added:
        let k = key_str(r[p])
        if seen.contains(k):
            return error("duplicate primary key: {fmt_val(r[p])}")
        seen.add(k)
    return ok(unit)

fn rep_of(g: List[List[Val]]) List[Val]:
    if g.length() > 0:
        return g[0].clone()
    return List[Val]()

// ---------- statements ----------

fn exec_create(var db: List[Table], st: Stmt) List[String]!String:
    if find_table(db, st.name) >= 0:
        return error("table {st.name} already exists")
    var i = 0
    while i < st.coldefs.length():
        var j = 0
        while j < i:
            if st.coldefs[j].name == st.coldefs[i].name:
                return error("duplicate column: {st.coldefs[i].name}")
            j += 1
        i += 1
    var npk = 0
    for cd in st.coldefs:
        if cd.pk:
            npk += 1
    if npk > 1:
        return error("multiple primary keys")
    db.append(Table(name: st.name.clone(), cols: st.coldefs.clone(), rows: List[List[Val]]()))
    return ok(["ok"])

fn exec_drop(var db: List[Table], st: Stmt) List[String]!String:
    let idx = find_table(db, st.name)
    if idx < 0:
        return error("no such table: {st.name}")
    db.remove(idx)
    return ok(["ok"])

fn exec_insert(var db: List[Table], st: Stmt) List[String]!String:
    let idx = find_table(db, st.name)
    if idx < 0:
        return error("no such table: {st.name}")
    let cols = db[idx].cols.clone()
    let ncols = cols.length()
    var colmap = List[Int]()
    if st.has_cols:
        for cn in st.cols:
            let j = col_index(cols, cn)
            if j < 0:
                return error("no such column: {cn}")
            if colmap.contains(j):
                return error("duplicate column: {cn}")
            colmap.append(j)
    else:
        var j = 0
        while j < ncols:
            colmap.append(j)
            j += 1
    let none_r = List[Val]()
    let none_g = List[List[Val]]()
    let none_s = List[Src]()
    var newrows = List[List[Val]]()
    for row in st.rows:
        if row.length() != colmap.length():
            return error("wrong number of values")
        var vals = List[Val]()
        var j = 0
        while j < ncols:
            vals.append(Val.N)
            j += 1
        var k = 0
        while k < row.length():
            let re = try resolve(row[k], none_s, 0, false)
            let v = try eval(re, none_r, none_g)
            vals[colmap[k]] = v
            k += 1
        try check_row(cols, vals)
        newrows.append(vals)
    try check_dups(cols, db[idx].rows, newrows)
    for r in newrows:
        db[idx].rows.append(r.clone())
    return ok(["inserted {newrows.length()}"])

// Single-table scope used by UPDATE and DELETE.
fn single_scope(t: Table) List[Src]:
    var cn = List[String]()
    for cd in t.cols:
        cn.append(cd.name.clone())
    var sc = List[Src]()
    sc.append(Src(alias: t.name.clone(), cols: cn, off: 0))
    return sc

fn exec_update(var db: List[Table], st: Stmt) List[String]!String:
    let idx = find_table(db, st.name)
    if idx < 0:
        return error("no such table: {st.name}")
    let t = db[idx].clone()
    var targets = List[Int]()
    for a in st.assigns:
        let j = col_index(t.cols, a.col)
        if j < 0:
            return error("no such column: {a.col}")
        targets.append(j)
    let sc = single_scope(t)
    var exprs = List[Expr]()
    for a in st.assigns:
        let re = try resolve(a.expr, sc, 1, false)
        exprs.append(re)
    var cond = blank_expr()
    if st.has_where:
        cond = try resolve(st.cond, sc, 1, false)
    let none_g = List[List[Val]]()
    var newrows = List[List[Val]]()
    var count = 0
    for row in t.rows:
        var hit = true
        if st.has_where:
            let c = try eval(cond, row, none_g)
            let keep = try truth(c)
            hit = keep
        if hit:
            count += 1
            var nv = row.clone()
            var k = 0
            while k < exprs.length():
                let v = try eval(exprs[k], row, none_g)
                nv[targets[k]] = v
                k += 1
            try check_row(t.cols, nv)
            newrows.append(nv)
        else:
            newrows.append(row.clone())
    try check_dups(t.cols, List[List[Val]](), newrows)
    db[idx].rows = newrows
    return ok(["updated {count}"])

fn exec_delete(var db: List[Table], st: Stmt) List[String]!String:
    let idx = find_table(db, st.name)
    if idx < 0:
        return error("no such table: {st.name}")
    let t = db[idx].clone()
    let sc = single_scope(t)
    var cond = blank_expr()
    if st.has_where:
        cond = try resolve(st.cond, sc, 1, false)
    let none_g = List[List[Val]]()
    var kept = List[List[Val]]()
    var count = 0
    for row in t.rows:
        var hit = true
        if st.has_where:
            let c = try eval(cond, row, none_g)
            let keep = try truth(c)
            hit = keep
        if hit:
            count += 1
        else:
            kept.append(row.clone())
    db[idx].rows = kept
    return ok(["deleted {count}"])

fn exec_select(db: List[Table], s: Select) List[String]!String:
    let none_g = List[List[Val]]()

    // FROM / JOIN tables: existence (left to right), then alias uniqueness.
    var trefs = List[TRef]()
    for tr in s.froms:
        trefs.append(tr.clone())
    for jn in s.joins:
        trefs.append(jn.tref.clone())
    var tidx = List[Int]()
    for tr in trefs:
        let ti = find_table(db, tr.name)
        if ti < 0:
            return error("no such table: {tr.name}")
        tidx.append(ti)
    var a = 0
    while a < trefs.length():
        var b = 0
        while b < a:
            if trefs[a].alias == trefs[b].alias:
                return error("duplicate alias: {trefs[a].alias}")
            b += 1
        a += 1
    var srcs = List[Src]()
    var off = 0
    var ti = 0
    while ti < trefs.length():
        var cn = List[String]()
        for cd in db[tidx[ti]].cols:
            cn.append(cd.name.clone())
        let width = cn.length()
        srcs.append(Src(alias: trefs[ti].alias.clone(), cols: cn, off: off))
        off += width
        ti += 1
    let nall = srcs.length()

    // Pass A: name resolution in the specified order.
    var joinR = List[Expr]()
    var j = 0
    while j < s.joins.length():
        let jr = try resolve(s.joins[j].onc, srcs, j + 2, false)
        joinR.append(jr)
        j += 1
    for it in s.items:
        if it.kind == "tstar":
            var found = false
            for sr in srcs:
                if sr.alias == it.tbl:
                    found = true
            if not found:
                return error("no such table: {it.tbl}")
    var gidx = List[Int]()
    for g in s.gcols:
        let gr = try resolve(g, srcs, nall, false)
        gidx.append(gr.idx)
    var cond = blank_expr()
    if s.has_where:
        cond = try resolve(s.cond, srcs, nall, false)
    var outs = List[OutCol]()
    for it in s.items:
        if it.kind == "all":
            for sr in srcs:
                var c = 0
                while c < sr.cols.length():
                    outs.append(OutCol(name: sr.cols[c].clone(), expr: colexpr(sr.off + c, sr.cols[c].clone())))
                    c += 1
        else if it.kind == "tstar":
            for sr in srcs:
                if sr.alias == it.tbl:
                    var c = 0
                    while c < sr.cols.length():
                        outs.append(OutCol(name: sr.cols[c].clone(), expr: colexpr(sr.off + c, sr.cols[c].clone())))
                        c += 1
        else:
            let re = try resolve(it.expr, srcs, nall, true)
            var nm = "?column?"
            if it.has_alias:
                nm = it.alias.clone()
            else if it.expr.kind == "col":
                nm = it.expr.name.clone()
            outs.append(OutCol(name: nm, expr: re))
    var hcond = blank_expr()
    if s.has_hcond:
        hcond = try resolve(s.hcond, srcs, nall, true)
    var oks = List[OKey]()
    var descs = List[Bool]()
    for od in s.ords:
        var pos = -1
        if od.expr.kind == "lit" and tag(od.expr.lv) == 1:
            let p = ival(od.expr.lv)
            if p < 1 or p > outs.length():
                return error("bad ORDER BY position")
            pos = p - 1
        else if od.expr.kind == "col" and od.expr.tbl == "":
            var q = 0
            while q < outs.length():
                if pos < 0 and outs[q].name == od.expr.name:
                    pos = q
                q += 1
        var ex = blank_expr()
        if pos < 0:
            ex = try resolve(od.expr, srcs, nall, true)
        oks.append(OKey(pos: pos, expr: ex, desc: od.desc))
        descs.append(od.desc)

    var aggd = s.gcols.length() > 0 or s.has_hcond
    for o in outs:
        if has_agg(o.expr):
            aggd = true
    for ko in oks:
        if ko.pos < 0 and has_agg(ko.expr):
            aggd = true

    // Pass B: grouping rules.
    if aggd:
        for o in outs:
            try check_grouped(o.expr, gidx)
        if s.has_hcond:
            try check_grouped(hcond, gidx)
        for ko in oks:
            if ko.pos < 0:
                try check_grouped(ko.expr, gidx)

    // Rows: FROM then joins in order.
    var rows = List[List[Val]]()
    if trefs.length() == 0:
        rows.append(List[Val]())
    else:
        for r in db[tidx[0]].rows:
            rows.append(r.clone())
    var jj = 0
    while jj < s.joins.length():
        let inner_ti = tidx[jj + 1]
        let ncols = db[inner_ti].cols.length()
        var nr = List[List[Val]]()
        for outer in rows:
            var matched = false
            for inr in db[inner_ti].rows:
                let comb = outer.concat(inr)
                let c = try eval(joinR[jj], comb, none_g)
                let keep = try truth(c)
                if keep:
                    nr.append(comb)
                    matched = true
            if not matched and s.joins[jj].is_left:
                var comb = outer.clone()
                var k = 0
                while k < ncols:
                    comb.append(Val.N)
                    k += 1
                nr.append(comb)
        rows = nr
        jj += 1

    // WHERE
    var filt = List[List[Val]]()
    for r in rows:
        if s.has_where:
            let c = try eval(cond, r, none_g)
            let keep = try truth(c)
            if keep:
                filt.append(r.clone())
        else:
            filt.append(r.clone())

    // Groups: each row alone, one group for the whole input, or keyed groups.
    var groups = List[List[List[Val]]]()
    if not aggd:
        for r in filt:
            var g = List[List[Val]]()
            g.append(r.clone())
            groups.append(g)
    else if s.gcols.length() == 0:
        groups.append(filt)
    else:
        var index = Map[String, Int]()
        for r in filt:
            var key = ""
            for gi in gidx:
                key = key.concat(key_str(r[gi]))
            if let gid = index.get(key):
                groups[gid].append(r.clone())
            else:
                index[key] = groups.length()
                var g = List[List[Val]]()
                g.append(r.clone())
                groups.append(g)

    // Evaluate output rows per group.
    var outrows = List[OutRow]()
    for g in groups:
        let rep = rep_of(g)
        if s.has_hcond:
            let hv = try eval(hcond, rep, g)
            let keep = try truth(hv)
            if not keep:
                continue
        var vals = List[Val]()
        for oc in outs:
            let v = try eval(oc.expr, rep, g)
            vals.append(v)
        var keys = List[Val]()
        for ko in oks:
            if ko.pos >= 0:
                keys.append(vals[ko.pos].clone())
            else:
                let kv = try eval(ko.expr, rep, g)
                keys.append(kv)
        outrows.append(OutRow(vals: vals, keys: keys))

    if s.distinct:
        var seen = Set[String]()
        var dd = List[OutRow]()
        for o in outrows:
            let k = rowkey(o.vals)
            if not seen.contains(k):
                seen.add(k.clone())
                dd.append(o.clone())
        outrows = dd

    if oks.length() > 0:
        let dsc = descs
        outrows.sort(fn(x: OutRow, y: OutRow) Int: cmp_out(x, y, dsc))

    var start = s.off
    var stop = outrows.length()
    if s.has_limit:
        if start + s.lim < stop:
            stop = start + s.lim
    if start > stop:
        start = stop

    var lines = List[String]()
    var names = List[String]()
    for oc in outs:
        names.append(oc.name.clone())
    lines.append(names.join("|"))
    var i = start
    while i < stop:
        var parts = List[String]()
        for v in outrows[i].vals:
            parts.append(fmt_val(v))
        lines.append(parts.join("|"))
        i += 1
    let count = stop - start
    lines.append("({count} rows)")
    return ok(lines)

fn cmp_out(x: OutRow, y: OutRow, dsc: List[Bool]) Int:
    var i = 0
    while i < dsc.length():
        var c = cmp_key(x.keys[i], y.keys[i])
        if dsc[i]:
            c = 0 - c
        if c != 0:
            return c
        i += 1
    return 0

fn exec_stmt(var db: List[Table], st: Stmt) List[String]!String:
    if st.kind == "create":
        return exec_create(var db, st)
    if st.kind == "drop":
        return exec_drop(var db, st)
    if st.kind == "insert":
        return exec_insert(var db, st)
    if st.kind == "update":
        return exec_update(var db, st)
    if st.kind == "delete":
        return exec_delete(var db, st)
    return exec_select(db, st.sel)

fn exec_tokens(var db: List[Table], toks: List[Tok]) List[String]!String:
    let st = try parse_stmt(toks)
    return exec_stmt(var db, st)

fn run_segment(var db: List[Table], toks: List[Tok]) List[String]:
    if toks.length() == 0:
        return List[String]()
    let res = exec_tokens(var db, toks)
    if res.is_error():
        return ["error: {res.err()}"]
    return res.get(default: List[String]())

export fn main() Int:
    let data = read_all(stdin()).get()
    let text = data.decode_utf8().get(default: "")
    let toks = lex(chars_of(text))
    var db = List[Table]()
    var cur = List[Tok]()
    for t in toks:
        if t.kind == "semi":
            for line in run_segment(var db, cur):
                print(line)
            cur = List[Tok]()
        else:
            cur.append(t.clone())
    for line in run_segment(var db, cur):
        print(line)
    return 0

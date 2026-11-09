import stdout_bytes, stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"

let KEYWORDS = [
    "SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET",
    "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN",
    "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE",
    "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"
]

enum Value:
    VNull
    VInt(n: Int)
    VText(b: Bytes)
    VBool(v: Bool)

enum Expr:
    ELit(v: Value)
    ECol(q: String, name: String)
    ENeg(x: Expr)
    ENot(x: Expr)
    EBin(op: String, l: Expr, r: Expr)
    EIsNull(x: Expr, neg: Bool)
    ELike(x: Expr, p: Expr, neg: Bool)
    EIn(x: Expr, items: List[Expr], neg: Bool)
    EBetween(x: Expr, lo: Expr, hi: Expr, neg: Bool)
    ECall(name: String, args: List[Expr], dist: Bool, star: Bool)

type Tok:
    kind: Int
    text: String
    num: Int
    b: Bytes

// kind: 0 expression, 1 all columns (*), 2 qualifier.* (q)
type SelItem:
    kind: Int
    q: String
    e: Expr
    alias: String

// kind: 0 first table, 1 inner join, 2 left join
type TRef:
    name: String
    alias: String
    kind: Int
    cond: Expr

type OItem:
    e: Expr
    desc: Bool

type Select:
    dist: Bool
    items: List[SelItem]
    tables: List[TRef]
    has_where: Bool
    where_e: Expr
    groups: List[Expr]
    has_having: Bool
    having_e: Expr
    orders: List[OItem]
    has_limit: Bool
    lim: Int
    off: Int

// ty: 0 INT, 1 TEXT
type ColDef:
    name: String
    ty: Int
    notnull: Bool
    pk: Bool

type Table:
    name: String
    cols: List[ColDef]
    rows: List[List[Value]]

type Db:
    tables: List[Table]

enum Stmt:
    SCreate(name: String, cols: List[ColDef])
    SDrop(name: String)
    SInsert(name: String, has_cols: Bool, cols: List[String], rows: List[List[Expr]])
    SUpdate(
        name: String,
        cols: List[String],
        vals: List[Expr],
        has_where: Bool,
        where_e: Expr
    )
    SDelete(name: String, has_where: Bool, where_e: Expr)
    SSelect(sel: Select)

type Src:
    alias: String
    cols: List[String]
    off: Int

type Scope:
    srcs: List[Src]
    ns: Int
    grouped: Bool
    gidx: List[Int]

type Prow:
    out: List[Value]
    keys: List[Value]

type Parser:
    toks: List[Tok]
    pos: Int

// ---------------------------------------------------------------- lexer

fn is_alpha(c: UInt8) Bool:
    if c == 95:
        return true
    if c >= 65 and c <= 90:
        return true

    return c >= 97 and c <= 122

fn is_digit(c: UInt8) Bool:
    return c >= 48 and c <= 57

fn is_space(c: UInt8) Bool:
    return c == 32 or c == 9 or c == 10 or c == 13

fn lex(s: Bytes) List[Tok]!String:
    var toks = List[Tok]()
    let n = s.length()
    var i = 0

    while i < n:
        let c = s.get(i)

        if is_space(c):
            i += 1
        else if c == 45 and i + 1 < n and s.get(i + 1) == 45:
            while i < n and s.get(i) != 10:
                i += 1
        else if is_alpha(c):
            let st = i
            while i < n and (is_alpha(s.get(i)) or is_digit(s.get(i))):
                i += 1

            let word = s.decode_utf8_range(st, i).get("")
            let up = word.upper()

            if KEYWORDS.contains(up):
                toks.append(Tok(kind: 2, text: up, num: 0, b: "".as_bytes()))
            else:
                toks.append(Tok(kind: 1, text: word, num: 0, b: "".as_bytes()))
        else if is_digit(c):
            var v = 0

            while i < n and is_digit(s.get(i)):
                let d = s.get(i).to_int() - 48
                if v > (9223372036854775807 - d) / 10:
                    return error("syntax error")

                v = v * 10 + d
                i += 1

            toks.append(Tok(kind: 3, text: "", num: v, b: "".as_bytes()))
        else if c == 39:
            var bb = BytesBuilder()
            i += 1

            var closed = false

            while i < n:
                let q = s.get(i)

                if q == 39:
                    if i + 1 < n and s.get(i + 1) == 39:
                        bb.append(39)
                        i += 2
                    else:
                        closed = true
                        i += 1
                        break
                else:
                    bb.append(q)
                    i += 1

            if not closed:
                return error("syntax error")

            toks.append(Tok(kind: 4, text: "", num: 0, b: bb.build()))
        else:
            var op = ""
            var w = 1

            if c == 60:
                op = "<"

                if i + 1 < n and s.get(i + 1) == 61:
                    op = "<="
                    w = 2
                else if i + 1 < n and s.get(i + 1) == 62:
                    op = "<>"
                    w = 2
            else if c == 62:
                op = ">"

                if i + 1 < n and s.get(i + 1) == 61:
                    op = ">="
                    w = 2
            else if c == 33:
                if i + 1 < n and s.get(i + 1) == 61:
                    op = "!="
                    w = 2
                else:
                    return error("syntax error")
            else if c == 124:
                if i + 1 < n and s.get(i + 1) == 124:
                    op = "||"
                    w = 2
                else:
                    return error("syntax error")
            else if c == 61:
                op = "="
            else if c == 43:
                op = "+"
            else if c == 45:
                op = "-"
            else if c == 42:
                op = "*"
            else if c == 47:
                op = "/"
            else if c == 37:
                op = "%"
            else if c == 40:
                op = "("
            else if c == 41:
                op = ")"
            else if c == 44:
                op = ","
            else if c == 46:
                op = "."
            else:
                return error("syntax error")

            toks.append(Tok(kind: 5, text: op, num: 0, b: "".as_bytes()))
            i += w

    return ok(toks)

// ---------------------------------------------------------------- parser

impl Parser:
    fn at_end() Bool:
        return self.pos >= self.toks.length()

    fn kind_at(off: Int) Int:
        let j = self.pos + off
        if j >= self.toks.length():
            return 0

        return self.toks[j].kind

    fn is_kw(w: String) Bool:
        if self.kind_at(0) != 2:
            return false

        return self.toks[self.pos].text == w

    fn is_kw_at(off: Int, w: String) Bool:
        if self.kind_at(off) != 2:
            return false

        return self.toks[self.pos + off].text == w

    fn is_op(o: String) Bool:
        if self.kind_at(0) != 5:
            return false

        return self.toks[self.pos].text == o

    fn is_op_at(off: Int, o: String) Bool:
        if self.kind_at(off) != 5:
            return false

        return self.toks[self.pos + off].text == o

    var fn expect_kw(w: String) Unit!String:
        if not self.is_kw(w):
            return error("syntax error")

        self.pos += 1
        return ok(unit)

    var fn expect_op(o: String) Unit!String:
        if not self.is_op(o):
            return error("syntax error")

        self.pos += 1
        return ok(unit)

    var fn ident() String!String:
        if self.kind_at(0) != 1:
            return error("syntax error")

        let t = self.toks[self.pos].text.clone()
        self.pos += 1
        return ok(t)

    var fn colref() Expr!String:
        let a = try self.ident()

        if self.is_op("."):
            self.pos += 1

            let b = try self.ident()
            return ok(ECol(a, b))

        return ok(ECol("", a))

    var fn primary() Expr!String:
        let k = self.kind_at(0)

        if k == 3:
            let v = self.toks[self.pos].num
            self.pos += 1
            return ok(ELit(VInt(v)))

        if k == 4:
            let b = self.toks[self.pos].b.as_bytes()
            self.pos += 1
            return ok(ELit(VText(b)))

        if self.is_kw("NULL"):
            self.pos += 1
            return ok(ELit(VNull))

        if self.is_op("("):
            self.pos += 1

            let e = try self.expr()
            try self.expect_op(")")
            return ok(e)

        if k == 1:
            let name = self.toks[self.pos].text.clone()
            self.pos += 1

            if self.is_op("("):
                self.pos += 1

                var dist = false

                if self.is_kw("DISTINCT"):
                    self.pos += 1
                    dist = true

                var args = List[Expr]()
                var star = false

                if self.is_op("*"):
                    self.pos += 1
                    star = true
                else if not self.is_op(")"):
                    while true:
                        let a = try self.expr()
                        args.append(a)

                        if self.is_op(","):
                            self.pos += 1
                        else:
                            break

                try self.expect_op(")")
                return ok(ECall(name.upper(), args, dist, star))

            if self.is_op("."):
                self.pos += 1

                let col = try self.ident()
                return ok(ECol(name, col))

            return ok(ECol("", name))

        return error("syntax error")

    var fn unary() Expr!String:
        if self.is_op("-"):
            self.pos += 1

            let e = try self.unary()
            return ok(ENeg(e))

        return self.primary()

    var fn mul() Expr!String:
        var l = try self.unary()

        while self.is_op("*") or self.is_op("/") or self.is_op("%"):
            let op = self.toks[self.pos].text.clone()
            self.pos += 1

            let r = try self.unary()
            l = EBin(op, l, r)

        return ok(l)

    var fn add() Expr!String:
        var l = try self.mul()

        while self.is_op("+") or self.is_op("-") or self.is_op("||"):
            let op = self.toks[self.pos].text.clone()
            self.pos += 1

            let r = try self.mul()
            l = EBin(op, l, r)

        return ok(l)

    var fn cmp() Expr!String:
        let l = try self.add()

        if self.kind_at(0) == 5:
            let op = self.toks[self.pos].text.clone()

            if (
                op == "="
                or op == "<>"
                or op == "!="
                or op == "<"
                or op == "<="
                or op == ">"
                or op == ">="
            ):
                self.pos += 1

                let r = try self.add()
                if op == "!=":
                    return ok(EBin("<>", l, r))

                return ok(EBin(op, l, r))

        if self.is_kw("IS"):
            self.pos += 1

            var isneg = false

            if self.is_kw("NOT"):
                self.pos += 1
                isneg = true

            try self.expect_kw("NULL")
            return ok(EIsNull(l, isneg))

        var neg = false

        if (
            self.is_kw("NOT")
            and (
                self.is_kw_at(1, "LIKE")
                or self.is_kw_at(1, "IN")
                or self.is_kw_at(1, "BETWEEN")
            )
        ):
            self.pos += 1
            neg = true

        if self.is_kw("LIKE"):
            self.pos += 1

            let p = try self.add()
            return ok(ELike(l, p, neg))

        if self.is_kw("IN"):
            self.pos += 1
            try self.expect_op("(")

            var items = List[Expr]()

            while true:
                let e = try self.expr()
                items.append(e)

                if self.is_op(","):
                    self.pos += 1
                else:
                    break

            try self.expect_op(")")
            return ok(EIn(l, items, neg))

        if self.is_kw("BETWEEN"):
            self.pos += 1

            let lo = try self.add()
            try self.expect_kw("AND")

            let hi = try self.add()
            return ok(EBetween(l, lo, hi, neg))

        return ok(l)

    var fn p_not() Expr!String:
        if self.is_kw("NOT"):
            self.pos += 1

            let e = try self.p_not()
            return ok(ENot(e))

        return self.cmp()

    var fn p_and() Expr!String:
        var l = try self.p_not()

        while self.is_kw("AND"):
            self.pos += 1

            let r = try self.p_not()
            l = EBin("AND", l, r)

        return ok(l)

    var fn expr() Expr!String:
        var l = try self.p_and()

        while self.is_kw("OR"):
            self.pos += 1

            let r = try self.p_and()
            l = EBin("OR", l, r)

        return ok(l)

    var fn select_body() Select!String:
        var dist = false

        if self.is_kw("DISTINCT"):
            self.pos += 1
            dist = true

        var items = List[SelItem]()

        while true:
            if self.is_op("*"):
                self.pos += 1
                items.append(SelItem(kind: 1, q: "", e: ELit(VNull), alias: ""))
            else if (
                self.kind_at(0) == 1
                and self.is_op_at(1, ".")
                and self.is_op_at(2, "*")
            ):
                let q = self.toks[self.pos].text.clone()
                self.pos += 3
                items.append(SelItem(kind: 2, q: q, e: ELit(VNull), alias: ""))
            else:
                let e = try self.expr()
                var alias = ""

                if self.is_kw("AS"):
                    self.pos += 1
                    alias = try self.ident()

                items.append(SelItem(kind: 0, q: "", e: e, alias: alias))

            if self.is_op(","):
                self.pos += 1
            else:
                break

        var tables = List[TRef]()

        if self.is_kw("FROM"):
            self.pos += 1

            let t0 = try self.tref(0)
            tables.append(t0)

            while self.is_kw("JOIN") or self.is_kw("INNER") or self.is_kw("LEFT"):
                var jk = 1

                if self.is_kw("LEFT"):
                    jk = 2
                    self.pos += 1
                    try self.expect_kw("JOIN")
                else if self.is_kw("INNER"):
                    self.pos += 1
                    try self.expect_kw("JOIN")
                else:
                    self.pos += 1

                var tr = try self.tref(jk)
                try self.expect_kw("ON")

                let cond = try self.expr()
                tr.cond = cond
                tables.append(tr)

        var has_where = false
        var where_e = ELit(VNull)

        if self.is_kw("WHERE"):
            self.pos += 1
            has_where = true
            where_e = try self.expr()

        var groups = List[Expr]()

        if self.is_kw("GROUP"):
            self.pos += 1
            try self.expect_kw("BY")

            while true:
                let g = try self.colref()
                groups.append(g)

                if self.is_op(","):
                    self.pos += 1
                else:
                    break

        var has_having = false
        var having_e = ELit(VNull)

        if self.is_kw("HAVING"):
            self.pos += 1
            has_having = true
            having_e = try self.expr()

        var orders = List[OItem]()

        if self.is_kw("ORDER"):
            self.pos += 1
            try self.expect_kw("BY")

            while true:
                let oe = try self.expr()
                var desc = false

                if self.is_kw("DESC"):
                    self.pos += 1
                    desc = true
                else if self.is_kw("ASC"):
                    self.pos += 1

                orders.append(OItem(e: oe, desc: desc))

                if self.is_op(","):
                    self.pos += 1
                else:
                    break

        var has_limit = false
        var lim = 0
        var off = 0

        if self.is_kw("LIMIT"):
            self.pos += 1
            has_limit = true
            if self.kind_at(0) != 3:
                return error("syntax error")

            lim = self.toks[self.pos].num
            self.pos += 1

            if self.is_kw("OFFSET"):
                self.pos += 1
                if self.kind_at(0) != 3:
                    return error("syntax error")

                off = self.toks[self.pos].num
                self.pos += 1

        return ok(
            Select(
                dist: dist, items: items, tables: tables, has_where: has_where,
                where_e: where_e, groups: groups, has_having: has_having,
                having_e: having_e, orders: orders, has_limit: has_limit, lim: lim,
                off: off
            )
        )

    var fn tref(kind: Int) TRef!String:
        let name = try self.ident()
        var alias = name.clone()

        if self.is_kw("AS"):
            self.pos += 1
            alias = try self.ident()
        else if self.kind_at(0) == 1:
            alias = try self.ident()

        return ok(TRef(name: name, alias: alias, kind: kind, cond: ELit(VNull)))

    var fn coldef() ColDef!String:
        let cname = try self.ident()
        if self.kind_at(0) != 1:
            return error("syntax error")

        let tu = self.toks[self.pos].text.upper()
        self.pos += 1

        var ty = -1

        if tu == "INT":
            ty = 0
        else if tu == "TEXT":
            ty = 1

        if ty < 0:
            return error("syntax error")

        var notnull = false
        var pk = false

        while true:
            if self.is_kw("PRIMARY"):
                self.pos += 1
                try self.expect_kw("KEY")
                pk = true
                notnull = true
            else if self.is_kw("NOT"):
                self.pos += 1
                try self.expect_kw("NULL")
                notnull = true
            else:
                break

        return ok(ColDef(name: cname, ty: ty, notnull: notnull, pk: pk))

    var fn statement() Stmt!String:
        if self.is_kw("CREATE"):
            self.pos += 1
            try self.expect_kw("TABLE")

            let name = try self.ident()
            try self.expect_op("(")

            var cols = List[ColDef]()

            while true:
                let cd = try self.coldef()
                cols.append(cd)

                if self.is_op(","):
                    self.pos += 1
                else:
                    break

            try self.expect_op(")")
            return ok(SCreate(name: name, cols: cols))

        if self.is_kw("DROP"):
            self.pos += 1
            try self.expect_kw("TABLE")

            let name = try self.ident()
            return ok(SDrop(name: name))

        if self.is_kw("INSERT"):
            self.pos += 1
            try self.expect_kw("INTO")

            let name = try self.ident()
            var has_cols = false
            var cols = List[String]()

            if self.is_op("("):
                has_cols = true
                self.pos += 1

                while true:
                    let c = try self.ident()
                    cols.append(c)

                    if self.is_op(","):
                        self.pos += 1
                    else:
                        break

                try self.expect_op(")")

            try self.expect_kw("VALUES")

            var rows = List[List[Expr]]()

            while true:
                try self.expect_op("(")

                var row = List[Expr]()

                while true:
                    let e = try self.expr()
                    row.append(e)

                    if self.is_op(","):
                        self.pos += 1
                    else:
                        break

                try self.expect_op(")")
                rows.append(row)

                if self.is_op(","):
                    self.pos += 1
                else:
                    break

            return ok(SInsert(name: name, has_cols: has_cols, cols: cols, rows: rows))

        if self.is_kw("UPDATE"):
            self.pos += 1

            let name = try self.ident()
            try self.expect_kw("SET")

            var cols = List[String]()
            var vals = List[Expr]()

            while true:
                let c = try self.ident()
                try self.expect_op("=")

                let e = try self.expr()
                cols.append(c)
                vals.append(e)

                if self.is_op(","):
                    self.pos += 1
                else:
                    break

            var has_where = false
            var where_e = ELit(VNull)

            if self.is_kw("WHERE"):
                self.pos += 1
                has_where = true
                where_e = try self.expr()

            return ok(
                SUpdate(
                    name: name, cols: cols, vals: vals, has_where: has_where,
                    where_e: where_e
                )
            )

        if self.is_kw("DELETE"):
            self.pos += 1
            try self.expect_kw("FROM")

            let name = try self.ident()
            var has_where = false
            var where_e = ELit(VNull)

            if self.is_kw("WHERE"):
                self.pos += 1
                has_where = true
                where_e = try self.expr()

            return ok(SDelete(name: name, has_where: has_where, where_e: where_e))

        if self.is_kw("SELECT"):
            self.pos += 1

            let sel = try self.select_body()
            return ok(SSelect(sel: sel))

        return error("syntax error")

fn parse_stmt(toks: List[Tok]) Stmt!String:
    var p = Parser(toks: toks, pos: 0)
    let st = try p.statement()
    if not p.at_end():
        return error("syntax error")

    return ok(st)

// ---------------------------------------------------------------- values

fn kind_of(v: Value) Int:
    match v:
        VNull:
            return 0
        VBool(_b):
            return 1
        VInt(_n):
            return 2
        VText(_t):
            return 3

fn int_of(v: Value) Int:
    match v:
        VInt(n):
            return n
        _:
            return 0

fn bool_of(v: Value) Bool:
    match v:
        VBool(b):
            return b
        _:
            return false

fn text_of(v: Value) Bytes:
    match v:
        VText(t):
            return t.as_bytes()
        _:
            return "".as_bytes()

// Three-valued truth: 1 true, 0 false, 2 NULL, -1 not boolean/NULL.
fn tri(v: Value) Int:
    let k = kind_of(v)
    if k == 0:
        return 2

    if k == 1:
        if bool_of(v):
            return 1

        return 0

    return -1

fn tv(t: Int) Value:
    if t == 1:
        return VBool(true)
    if t == 0:
        return VBool(false)

    return VNull

fn negate3(t: Int) Int:
    if t == 1:
        return 0
    if t == 0:
        return 1

    return 2

fn combine(is_and: Bool, lt: Int, rt: Int) Int:
    if is_and:
        if lt == 0 or rt == 0:
            return 0
        if lt == 2 or rt == 2:
            return 2

        return 1

    if lt == 1 or rt == 1:
        return 1
    if lt == 2 or rt == 2:
        return 2

    return 0

fn keep_cond(v: Value) Bool!String:
    let t = tri(v)
    if t == -1:
        return error("type error")

    return ok(t == 1)

fn bcmp(a: Bytes, b: Bytes) Int:
    let n = a.length()
    let m = b.length()
    var i = 0

    while i < n and i < m:
        let x = a.get(i)
        let y = b.get(i)

        if x != y:
            if x < y:
                return -1

            return 1

        i += 1

    if n < m:
        return -1
    if n > m:
        return 1

    return 0

// Comparison for operands of the same type (INT or TEXT); otherwise type error.
fn cmp_vals(a: Value, b: Value) Int!String:
    let ka = kind_of(a)
    let kb = kind_of(b)
    if ka != kb or ka == 0 or ka == 1:
        return error("type error")

    if ka == 2:
        let x = int_of(a)
        let y = int_of(b)
        if x < y:
            return ok(-1)
        if x > y:
            return ok(1)

        return ok(0)

    return ok(bcmp(text_of(a), text_of(b)))

// Value identity for DISTINCT, GROUP BY and primary keys (NULL equals NULL).
fn val_same(a: Value, b: Value) Bool:
    let ka = kind_of(a)
    if ka != kind_of(b):
        return false
    if ka == 0:
        return true
    if ka == 1:
        return bool_of(a) == bool_of(b)
    if ka == 2:
        return int_of(a) == int_of(b)

    return bcmp(text_of(a), text_of(b)) == 0

fn same_row(a: List[Value], b: List[Value]) Bool:
    if a.length() != b.length():
        return false

    for i in 0..a.length():
        if not val_same(a[i], b[i]):
            return false
    return true

// Sort order: NULL < FALSE < TRUE < INT < TEXT.
fn sort_cmp(a: Value, b: Value) Int:
    let ka = kind_of(a)
    let kb = kind_of(b)

    if ka != kb:
        if ka < kb:
            return -1

        return 1

    if ka == 0:
        return 0

    if ka == 1:
        let x = bool_of(a)
        let y = bool_of(b)
        if x == y:
            return 0
        if y:
            return -1

        return 1

    if ka == 2:
        let x = int_of(a)
        let y = int_of(b)
        if x < y:
            return -1
        if x > y:
            return 1

        return 0

    return bcmp(text_of(a), text_of(b))

fn val_bytes(v: Value) Bytes:
    let k = kind_of(v)
    if k == 0:
        return "NULL".as_bytes()

    if k == 1:
        if bool_of(v):
            return "true".as_bytes()

        return "false".as_bytes()

    if k == 2:
        return "{int_of(v)}".as_bytes()

    return text_of(v)

fn val_str(v: Value) String:
    return val_bytes(v).decode_utf8().get("")

// ---------------------------------------------------------------- expression evaluation

fn is_agg(name: String) Bool:
    return name == "COUNT" or name == "SUM" or name == "MIN" or name == "MAX"

fn is_scalar(name: String) Bool:
    return (
        name == "UPPER"
        or name == "LOWER"
        or name == "LENGTH"
        or name == "ABS"
        or name == "SUBSTR"
        or name == "COALESCE"
    )

// Argument-count rule; `star` is COUNT(*)-style. DISTINCT calls take exactly one argument.
fn arity_ok(name: String, n: Int, dist: Bool, star: Bool) Bool:
    if star:
        return name == "COUNT" and not dist
    if dist and n != 1:
        return false
    if is_agg(name):
        return n == 1
    if name == "UPPER" or name == "LOWER" or name == "LENGTH" or name == "ABS":
        return n == 1
    if name == "SUBSTR":
        return n == 3
    if name == "COALESCE":
        return n >= 1

    return false

fn has_agg(e: Expr) Bool:
    match e:
        ELit(_v):
            return false
        ECol(_q, _n):
            return false
        ENeg(x):
            return has_agg(x)
        ENot(x):
            return has_agg(x)
        EBin(_op, l, r):
            if has_agg(l):
                return true

            return has_agg(r)
        EIsNull(x, _n):
            return has_agg(x)
        ELike(x, p, _n):
            if has_agg(x):
                return true

            return has_agg(p)
        EIn(x, items, _n):
            if has_agg(x):
                return true

            for it in items:
                if has_agg(it):
                    return true
            return false
        EBetween(x, lo, hi, _n):
            if has_agg(x) or has_agg(lo):
                return true

            return has_agg(hi)
        ECall(name, args, _d, _s):
            if is_agg(name):
                return true

            for a in args:
                if has_agg(a):
                    return true
            return false

fn resolve_col(sc: Scope, q: String, name: String) Int!String:
    var found = -1
    var count = 0

    for s in 0..sc.ns:
        let src = sc.srcs[s]

        if q == "" or src.alias == q:
            for j in 0..src.cols.length():
                if src.cols[j] == name:
                    found = src.off + j
                    count += 1

    if count == 0:
        if q == "":
            return error("no such column: {name}")

        return error("no such column: {q}.{name}")

    if count > 1:
        return error("ambiguous column: {name}")

    return ok(found)

// Static checks: names, functions, arity, aggregate placement, GROUP BY membership.
fn check(e: Expr, sc: Scope, allow_agg: Bool, in_agg: Bool) Unit!String:
    match e:
        ELit(_v):
            return ok(unit)
        ECol(q, name):
            let idx = try resolve_col(sc, q, name)

            if sc.grouped and not in_agg:
                if not sc.gidx.contains(idx):
                    var shown = name.clone()
                    if q != "":
                        shown = "{q}.{name}"
                    return error("column {shown} must appear in GROUP BY")

            return ok(unit)
        ENeg(x):
            return check(x, sc, allow_agg, in_agg)
        ENot(x):
            return check(x, sc, allow_agg, in_agg)
        EBin(_op, l, r):
            try check(l, sc, allow_agg, in_agg)
            return check(r, sc, allow_agg, in_agg)
        EIsNull(x, _n):
            return check(x, sc, allow_agg, in_agg)
        ELike(x, p, _n):
            try check(x, sc, allow_agg, in_agg)
            return check(p, sc, allow_agg, in_agg)
        EIn(x, items, _n):
            try check(x, sc, allow_agg, in_agg)
            for it in items:
                try check(it, sc, allow_agg, in_agg)
            return ok(unit)
        EBetween(x, lo, hi, _n):
            try check(x, sc, allow_agg, in_agg)
            try check(lo, sc, allow_agg, in_agg)
            return check(hi, sc, allow_agg, in_agg)
        ECall(name, args, dist, star):
            if is_agg(name):
                if in_agg or not allow_agg:
                    return error("misuse of aggregate")
                if not arity_ok(name, args.length(), dist, star):
                    return error("wrong number of arguments to {name}")

                for a in args:
                    try check(a, sc, allow_agg, true)
                return ok(unit)

            if not is_scalar(name):
                return error("no such function: {name}")
            if not arity_ok(name, args.length(), dist, star):
                return error("wrong number of arguments to {name}")

            for a in args:
                try check(a, sc, allow_agg, in_agg)
            return ok(unit)

fn logic(
    is_and: Bool,
    l: Expr,
    r: Expr,
    sc: Scope,
    row: List[Value],
    grp: List[List[Value]]
) Value!String:
    let a = try eval(l, sc, row, grp)
    let lt = tri(a)
    if is_and and lt == 0:
        return ok(VBool(false))
    if not is_and and lt == 1:
        return ok(VBool(true))

    let b = try eval(r, sc, row, grp)
    let rt = tri(b)
    if lt == -1 or rt == -1:
        return error("type error")

    return ok(tv(combine(is_and, lt, rt)))

fn arith(op: String, a: Value, b: Value) Value!String:
    if kind_of(a) == 0 or kind_of(b) == 0:
        return ok(VNull)
    if kind_of(a) != 2 or kind_of(b) != 2:
        return error("type error")

    let x = int_of(a)
    let y = int_of(b)
    if op == "+":
        return ok(VInt(x + y))
    if op == "-":
        return ok(VInt(x - y))
    if op == "*":
        return ok(VInt(x * y))
    if y == 0:
        return error("division by zero")
    if op == "/":
        return ok(VInt(x / y))

    return ok(VInt(x % y))

fn concat_vals(a: Value, b: Value) Value!String:
    if kind_of(a) == 0 or kind_of(b) == 0:
        return ok(VNull)
    if kind_of(a) != 3 or kind_of(b) != 3:
        return error("type error")

    return ok(VText(text_of(a).concat(text_of(b))))

fn cmp_op(op: String, a: Value, b: Value) Value!String:
    if kind_of(a) == 0 or kind_of(b) == 0:
        return ok(VNull)

    let c = try cmp_vals(a, b)
    var res = false

    if op == "=":
        res = c == 0
    else if op == "<>":
        res = c != 0
    else if op == "<":
        res = c < 0
    else if op == "<=":
        res = c <= 0
    else if op == ">":
        res = c > 0
    else:
        res = c >= 0

    return ok(VBool(res))

fn upper_bytes(b: Bytes, up: Bool) Bytes:
    var bb = BytesBuilder()

    for i in 0..b.length():
        var c = b.get(i)

        if up and c >= 97 and c <= 122:
            c = c - 32
        else if not up and c >= 65 and c <= 90:
            c = c + 32

        bb.append(c)

    return bb.build()

// Positions start .. start+len-1 (1-based, byte based), clipped to the string.
fn substr_bytes(b: Bytes, start: Int, len: Int) Bytes:
    let n = b.length()
    if len <= 0:
        return "".as_bytes()

    var lo = start
    if lo < 1:
        lo = 1

    var hi = start + len - 1
    if hi > n:
        hi = n
    if lo > hi:
        return "".as_bytes()

    return b.slice(lo - 1, hi).get()

fn like_match(s: Bytes, p: Bytes) Bool:
    let n = s.length()
    let m = p.length()
    var i = 0
    var j = 0
    var sj = -1
    var si = 0

    while i < n:
        if j < m and p.get(j) == 37:
            sj = j
            si = i
            j += 1
        else if j < m and (p.get(j) == 95 or p.get(j) == s.get(i)):
            i += 1
            j += 1
        else if sj >= 0:
            j = sj + 1
            si += 1
            i = si
        else:
            return false

    while j < m and p.get(j) == 37:
        j += 1
    return j == m

fn scalar_eval(
    name: String,
    args: List[Expr],
    sc: Scope,
    row: List[Value],
    grp: List[List[Value]]
) Value!String:
    var vals = List[Value]()

    for a in args:
        let v = try eval(a, sc, row, grp)
        vals.append(v)

    if name == "COALESCE":
        for v in vals:
            if kind_of(v) != 0:
                return ok(v.clone())
        return ok(VNull)

    for v in vals:
        if kind_of(v) == 0:
            return ok(VNull)

    if name == "UPPER" or name == "LOWER":
        if kind_of(vals[0]) != 3:
            return error("type error")

        return ok(VText(upper_bytes(text_of(vals[0]), name == "UPPER")))

    if name == "LENGTH":
        if kind_of(vals[0]) != 3:
            return error("type error")

        return ok(VInt(text_of(vals[0]).length()))

    if name == "ABS":
        if kind_of(vals[0]) != 2:
            return error("type error")

        let x = int_of(vals[0])
        if x < 0:
            return ok(VInt(0 - x))

        return ok(VInt(x))

    if name == "SUBSTR":
        if kind_of(vals[0]) != 3 or kind_of(vals[1]) != 2 or kind_of(vals[2]) != 2:
            return error("type error")

        return ok(
            VText(
                substr_bytes(
                    text_of(vals[0]), int_of(vals[1]), int_of(vals[2])
                )
            )
        )

    return error("no such function: {name}")

fn agg_eval(
    name: String,
    args: List[Expr],
    dist: Bool,
    star: Bool,
    sc: Scope,
    grp: List[List[Value]]
) Value!String:
    if star:
        return ok(VInt(grp.length()))

    var vals = List[Value]()

    for r in grp:
        let v = try eval(args[0], sc, r, grp)
        if kind_of(v) != 0:
            vals.append(v)

    if dist:
        var uniq = List[Value]()

        for v in vals:
            var seen = false
            for u in uniq:
                if val_same(u, v):
                    seen = true
            if not seen:
                uniq.append(v.clone())

        vals = uniq

    if name == "COUNT":
        return ok(VInt(vals.length()))

    if name == "SUM":
        if vals.length() == 0:
            return ok(VNull)

        var s = 0

        for v in vals:
            if kind_of(v) != 2:
                return error("type error")

            s += int_of(v)

        return ok(VInt(s))

    if vals.length() == 0:
        return ok(VNull)

    for v in vals:
        if kind_of(v) != 2 and kind_of(v) != 3:
            return error("type error")

    var best = vals[0].clone()

    for v in vals:
        let c = try cmp_vals(v, best)

        if name == "MIN" and c < 0:
            best = v.clone()
        else if name == "MAX" and c > 0:
            best = v.clone()

    return ok(best)

fn eval(e: Expr, sc: Scope, row: List[Value], grp: List[List[Value]]) Value!String:
    match e:
        ELit(v):
            return ok(v.clone())
        ECol(q, name):
            let idx = try resolve_col(sc, q, name)
            return ok(row[idx].clone())
        ENeg(x):
            let v = try eval(x, sc, row, grp)
            if kind_of(v) == 0:
                return ok(VNull)
            if kind_of(v) != 2:
                return error("type error")

            return ok(VInt(0 - int_of(v)))
        ENot(x):
            let v = try eval(x, sc, row, grp)
            let t = tri(v)
            if t == -1:
                return error("type error")

            return ok(tv(negate3(t)))
        EBin(op, l, r):
            if op == "AND":
                return logic(true, l, r, sc, row, grp)
            if op == "OR":
                return logic(false, l, r, sc, row, grp)

            let a = try eval(l, sc, row, grp)
            let b = try eval(r, sc, row, grp)
            if op == "||":
                return concat_vals(a, b)
            if op == "+" or op == "-" or op == "*" or op == "/" or op == "%":
                return arith(op, a, b)

            return cmp_op(op, a, b)
        EIsNull(x, neg):
            let v = try eval(x, sc, row, grp)
            let isn = kind_of(v) == 0
            return ok(VBool(isn != neg))
        ELike(x, p, neg):
            let a = try eval(x, sc, row, grp)
            let b = try eval(p, sc, row, grp)
            if kind_of(a) == 0 or kind_of(b) == 0:
                return ok(VNull)
            if kind_of(a) != 3 or kind_of(b) != 3:
                return error("type error")

            var m = like_match(text_of(a), text_of(b))
            if neg:
                m = not m
            return ok(VBool(m))
        EIn(x, items, neg):
            let xv = try eval(x, sc, row, grp)
            var vals = List[Value]()

            for it in items:
                let v = try eval(it, sc, row, grp)
                vals.append(v)

            if kind_of(xv) == 0:
                return ok(VNull)

            var found = false
            var sawnull = false

            for v in vals:
                if kind_of(v) == 0:
                    sawnull = true
                else:
                    let c = try cmp_vals(xv, v)
                    if c == 0:
                        found = true

            var t = 2

            if found:
                t = 1
            else if not sawnull:
                t = 0

            if neg:
                t = negate3(t)
            return ok(tv(t))
        EBetween(x, lo, hi, neg):
            let xv = try eval(x, sc, row, grp)
            let lv = try eval(lo, sc, row, grp)
            let hv = try eval(hi, sc, row, grp)
            let c1 = try cmp_op(">=", xv, lv)
            let t1 = tri(c1)
            var t = 0

            if t1 != 0:
                let c2 = try cmp_op("<=", xv, hv)
                t = combine(true, t1, tri(c2))

            if neg:
                t = negate3(t)
            return ok(tv(t))
        ECall(name, args, dist, star):
            if is_agg(name):
                return agg_eval(name, args, dist, star, sc, grp)

            return scalar_eval(name, args, sc, row, grp)

// ---------------------------------------------------------------- helpers for statements

fn find_table(db: Db, name: String) Int:
    for i in 0..db.tables.length():
        if db.tables[i].name == name:
            return i
    return -1

fn find_col(cols: List[ColDef], name: String) Int:
    for i in 0..cols.length():
        if cols[i].name == name:
            return i
    return -1

fn names_of(cols: List[ColDef]) List[String]:
    var out = List[String]()
    for c in cols:
        out.append(c.name.clone())
    return out

fn pk_index(cols: List[ColDef]) Int:
    for i in 0..cols.length():
        if cols[i].pk:
            return i
    return -1

fn empty_scope() Scope:
    return Scope(srcs: List[Src](), ns: 0, grouped: false, gidx: List[Int]())

// Constraint checks for one full row, in column declaration order.
fn check_row(cols: List[ColDef], row: List[Value]) Unit!String:
    for c in 0..cols.length():
        if kind_of(row[c]) == 0:
            if cols[c].notnull:
                return error("NOT NULL constraint failed: {cols[c].name}")
        else:
            let k = kind_of(row[c])
            if cols[c].ty == 0 and k != 2:
                return error("type mismatch in column {cols[c].name}")
            if cols[c].ty == 1 and k != 3:
                return error("type mismatch in column {cols[c].name}")

    return ok(unit)

// Duplicate primary key check over a complete set of rows.
fn check_pk(cols: List[ColDef], rows: List[List[Value]]) Unit!String:
    let pk = pk_index(cols)
    if pk < 0:
        return ok(unit)

    var keys = List[List[Value]]()

    for r in rows:
        var k = List[Value]()
        k.append(r[pk].clone())
        keys.append(k)

    // Stable sort: within equal keys the earliest row comes first; every later one is a duplicate.
    let order = sort_idx(keys, List[Bool]())
    let none_desc = List[Bool]()
    var worst = -1
    for p in 1..order.length():
        if lex_cmp(keys[order[p]], keys[order[p - 1]], none_desc) == 0:
            if worst < 0 or order[p] < worst:
                worst = order[p]
    if worst >= 0:
        return error("duplicate primary key: {val_str(rows[worst][pk])}")

    return ok(unit)

fn concat_rows(a: List[Value], b: List[Value]) List[Value]:
    var out = List[Value]()
    for v in a:
        out.append(v.clone())
    for v in b:
        out.append(v.clone())
    return out

// ---------------------------------------------------------------- SELECT

fn col_index(e: Expr, sc: Scope) Int!String:
    match e:
        ECol(q, name):
            return resolve_col(sc, q, name)
        _:
            return error("syntax error")

fn plain_name(e: Expr) String:
    match e:
        ECol(_q, name):
            return name.clone()
        _:
            return "?column?"

// ORDER BY target: output column index, or -1 for an expression.
fn order_target(e: Expr, names: List[String]) Int!String:
    match e:
        ELit(v):
            if kind_of(v) == 2:
                let p = int_of(v)
                if p < 1 or p > names.length():
                    return error("bad ORDER BY position")

                return ok(p - 1)

            return ok(-1)
        ECol(q, name):
            if q == "":
                for i in 0..names.length():
                    if names[i] == name:
                        return ok(i)
            return ok(-1)
        _:
            return ok(-1)

fn project(
    sel: Select,
    sc: Scope,
    row: List[Value],
    grp: List[List[Value]],
    okeys: List[Int]
) Prow!String:
    var out = List[Value]()

    for it in sel.items:
        if it.kind == 1:
            for v in row:
                out.append(v.clone())
        else if it.kind == 2:
            for s in sc.srcs:
                if s.alias == it.q:
                    for j in 0..s.cols.length():
                        out.append(row[s.off + j].clone())
        else:
            let v = try eval(it.e, sc, row, grp)
            out.append(v)

    var keys = List[Value]()

    for i in 0..sel.orders.length():
        let t = okeys[i]

        if t >= 0:
            keys.append(out[t].clone())
        else:
            let v = try eval(sel.orders[i].e, sc, row, grp)
            keys.append(v)

    return ok(Prow(out: out, keys: keys))

// Lexicographic order of key lists; `desc` (may be shorter) reverses the keys it covers.
fn lex_cmp(a: List[Value], b: List[Value], desc: List[Bool]) Int:
    for k in 0..a.length():
        var c = sort_cmp(a[k], b[k])
        if k < desc.length() and desc[k]:
            c = 0 - c
        if c != 0:
            return c

    return 0

// Stable bottom-up merge sort of row indices by their key lists.
fn sort_idx(keys: List[List[Value]], desc: List[Bool]) List[Int]:
    let n = keys.length()
    var cur = List[Int]()
    for i in 0..n:
        cur.append(i)

    var width = 1

    while width < n:
        var nxt = List[Int]()
        var lo = 0

        while lo < n:
            var mid = lo + width
            if mid > n:
                mid = n

            var hi = lo + 2 * width
            if hi > n:
                hi = n

            var i = lo
            var j = mid

            while i < mid and j < hi:
                if lex_cmp(keys[cur[j]], keys[cur[i]], desc) < 0:
                    nxt.append(cur[j])
                    j += 1
                else:
                    nxt.append(cur[i])
                    i += 1

            while i < mid:
                nxt.append(cur[i])
                i += 1

            while j < hi:
                nxt.append(cur[j])
                j += 1

            lo += 2 * width

        cur = nxt
        width = width * 2

    return cur

fn run_select(db: Db, sel: Select) Bytes!String:
    var srcs = List[Src]()
    var tabs = List[Int]()
    var off = 0

    for t in sel.tables:
        let ti = find_table(db, t.name)
        if ti < 0:
            return error("no such table: {t.name}")

        for s in srcs:
            if s.alias == t.alias:
                return error("duplicate alias: {t.alias}")

        let cols = names_of(db.tables[ti].cols)
        let nc = cols.length()
        srcs.append(Src(alias: t.alias.clone(), cols: cols, off: off))
        off += nc
        tabs.append(ti)

    let nsrc = srcs.length()

    // join conditions: each sees the tables up to and including its own
    for k in 1..nsrc:
        let jsc = Scope(
            srcs: srcs.clone(), ns: k + 1, grouped: false, gidx: List[Int]()
        )
        try check(sel.tables[k].cond, jsc, false, false)

    // stars
    for it in sel.items:
        if it.kind == 2:
            var found = false
            for s in srcs:
                if s.alias == it.q:
                    found = true
            if not found:
                return error("no such table: {it.q}")

    var aggd = sel.groups.length() > 0 or sel.has_having
    for it in sel.items:
        if it.kind == 0 and has_agg(it.e):
            aggd = true
    for o in sel.orders:
        if has_agg(o.e):
            aggd = true

    let full = Scope(srcs: srcs.clone(), ns: nsrc, grouped: false, gidx: List[Int]())
    var gidx = List[Int]()

    for g in sel.groups:
        let gi = try col_index(g, full)
        gidx.append(gi)

    if sel.has_where:
        try check(sel.where_e, full, false, false)

    // select items
    var names = List[String]()
    let gsc = Scope(srcs: srcs.clone(), ns: nsrc, grouped: aggd, gidx: gidx.clone())

    for it in sel.items:
        if it.kind == 1 or it.kind == 2:
            for s in srcs:
                if it.kind == 1 or s.alias == it.q:
                    for j in 0..s.cols.length():
                        if aggd and not gidx.contains(s.off + j):
                            return error("column {s.cols[j]} must appear in GROUP BY")

                        names.append(s.cols[j].clone())
        else:
            try check(it.e, gsc, true, false)

            if it.alias != "":
                names.append(it.alias.clone())
            else:
                names.append(plain_name(it.e))

    if sel.has_having:
        try check(sel.having_e, gsc, true, false)

    // ORDER BY
    var okeys = List[Int]()
    var desc = List[Bool]()

    for o in sel.orders:
        let t = try order_target(o.e, names)
        if t < 0:
            try check(o.e, gsc, true, false)
        okeys.append(t)
        desc.append(o.desc)

    // FROM and JOIN rows
    var rows = List[List[Value]]()
    let empty = List[List[Value]]()

    if tabs.length() == 0:
        rows.append(List[Value]())
    else:
        for r in db.tables[tabs[0]].rows:
            rows.append(r.clone())

        for k in 1..tabs.length():
            let tk = db.tables[tabs[k]]
            let nck = tk.cols.length()
            let tr = sel.tables[k]
            let jsc = Scope(
                srcs: srcs.clone(), ns: k + 1, grouped: false, gidx: List[Int]()
            )
            var nr = List[List[Value]]()

            for outer in rows:
                var matched = false

                for ir in tk.rows:
                    let comb = concat_rows(outer, ir)
                    let cv = try eval(tr.cond, jsc, comb, empty)
                    let ck = try keep_cond(cv)

                    if ck:
                        matched = true
                        nr.append(comb)

                if not matched and tr.kind == 2:
                    var padded = outer.clone()
                    for _c in 0..nck:
                        padded.append(VNull)
                    nr.append(padded)

            rows = nr

    // WHERE
    if sel.has_where:
        var kept = List[List[Value]]()

        for r in rows:
            let wv = try eval(sel.where_e, full, r, empty)
            let wk = try keep_cond(wv)
            if wk:
                kept.append(r.clone())

        rows = kept

    // projection (grouped or per row)
    var prows = List[Prow]()

    if aggd:
        var gkeys = List[List[Value]]()
        var grows = List[List[List[Value]]]()

        if sel.groups.length() == 0:
            gkeys.append(List[Value]())

            var one = List[List[Value]]()
            for r in rows:
                one.append(r.clone())
            grows.append(one)
        else:
            for r in rows:
                var key = List[Value]()
                for gi in gidx:
                    key.append(r[gi].clone())

                var found = -1
                for g in 0..gkeys.length():
                    if same_row(gkeys[g], key):
                        found = g

                if found < 0:
                    gkeys.append(key)

                    var one = List[List[Value]]()
                    one.append(r.clone())
                    grows.append(one)
                else:
                    grows[found].append(r.clone())

        for g in 0..grows.length():
            let grp = grows[g]
            var rep = List[Value]()
            if grp.length() > 0:
                rep = grp[0].clone()

            if sel.has_having:
                let hv = try eval(sel.having_e, full, rep, grp)
                let hk = try keep_cond(hv)
                if not hk:
                    continue

            let p = try project(sel, full, rep, grp, okeys)
            prows.append(p)
    else:
        for r in rows:
            let p = try project(sel, full, r, empty, okeys)
            prows.append(p)

    // DISTINCT keeps the first occurrence of each output row
    var kept = List[Int]()

    if sel.dist:
        var outs = List[List[Value]]()
        for p in prows:
            outs.append(p.out.clone())

        let so = sort_idx(outs, List[Bool]())
        var dup = List[Bool]()
        for _i in 0..prows.length():
            dup.append(false)

        let none_desc = List[Bool]()
        for p in 1..so.length():
            if lex_cmp(outs[so[p]], outs[so[p - 1]], none_desc) == 0:
                dup[so[p]] = true
        for i in 0..prows.length():
            if not dup[i]:
                kept.append(i)
    else:
        for i in 0..prows.length():
            kept.append(i)

    // ORDER BY (stable), then OFFSET / LIMIT
    var order = List[Int]()

    if sel.orders.length() > 0:
        var klists = List[List[Value]]()
        for i in kept:
            klists.append(prows[i].keys.clone())

        let sp = sort_idx(klists, desc)
        for p in sp:
            order.append(kept[p])
    else:
        order = kept

    let total = order.length()
    var startp = 0
    var endp = total

    if sel.has_limit:
        startp = sel.off
        if startp > total:
            startp = total
        endp = startp + sel.lim
        if endp > total:
            endp = total

    var b = BytesBuilder()

    for i in 0..names.length():
        if i > 0:
            b.append_bytes("|".as_bytes())
        b.append_bytes(names[i].as_bytes())

    b.append_bytes("\n".as_bytes())

    for k in startp..endp:
        let p = prows[order[k]]

        for c in 0..p.out.length():
            if c > 0:
                b.append_bytes("|".as_bytes())
            b.append_bytes(val_bytes(p.out[c]))

        b.append_bytes("\n".as_bytes())

    let cnt = endp - startp
    b.append_bytes("({cnt} rows)\n".as_bytes())
    return ok(b.build())

// ---------------------------------------------------------------- other statements

fn run_create(var db: Db, name: String, cols: List[ColDef]) Bytes!String:
    if find_table(db, name) >= 0:
        return error("table {name} already exists")

    for i in 0..cols.length():
        for j in 0..i:
            if cols[j].name == cols[i].name:
                return error("duplicate column: {cols[i].name}")

    var npk = 0
    for c in cols:
        if c.pk:
            npk += 1
    if npk > 1:
        return error("multiple primary keys")

    db.tables.append(Table(name: name, cols: cols, rows: List[List[Value]]()))
    return ok("ok\n".as_bytes())

fn run_drop(var db: Db, name: String) Bytes!String:
    let ti = find_table(db, name)
    if ti < 0:
        return error("no such table: {name}")

    db.tables.remove(ti)
    return ok("ok\n".as_bytes())

fn run_insert(
    var db: Db, name: String, has_cols: Bool, cols: List[String], rows: List[List[Expr]]
) Bytes!String:
    let ti = find_table(db, name)
    if ti < 0:
        return error("no such table: {name}")

    let ncols = db.tables[ti].cols.length()
    var colmap = List[Int]()

    if has_cols:
        for i in 0..cols.length():
            let ci = find_col(db.tables[ti].cols, cols[i])
            if ci < 0:
                return error("no such column: {cols[i]}")

            for j in 0..i:
                if cols[j] == cols[i]:
                    return error("duplicate column: {cols[i]}")
            colmap.append(ci)
    else:
        for c in 0..ncols:
            colmap.append(c)

    let esc = empty_scope()
    let none_row = List[Value]()
    let none_grp = List[List[Value]]()
    var pending = List[List[Value]]()

    for r in rows:
        if r.length() != colmap.length():
            return error("wrong number of values")

        var vals = List[Value]()
        for _c in 0..ncols:
            vals.append(VNull)

        for k in 0..r.length():
            try check(r[k], esc, false, false)

            let v = try eval(r[k], esc, none_row, none_grp)
            vals[colmap[k]] = v

        try check_row(db.tables[ti].cols, vals)
        pending.append(vals)

    try check_pk(db.tables[ti].cols, concat_pending(db.tables[ti].rows, pending))
    for r in pending:
        db.tables[ti].rows.append(r.clone())
    return ok("inserted {pending.length()}\n".as_bytes())

// Existing rows followed by new rows, for the duplicate primary key check.
fn concat_pending(
    existing: List[List[Value]],
    pending: List[List[Value]]
) List[List[Value]]:
    var all = List[List[Value]]()
    for r in existing:
        all.append(r.clone())
    for r in pending:
        all.append(r.clone())
    return all

fn run_update(
    var db: Db, name: String, cols: List[String], vals: List[Expr], has_where: Bool,
    where_e: Expr
) Bytes!String:
    let ti = find_table(db, name)
    if ti < 0:
        return error("no such table: {name}")

    var srcs = List[Src]()
    srcs.append(Src(alias: name.clone(), cols: names_of(db.tables[ti].cols), off: 0))

    let sc = Scope(srcs: srcs, ns: 1, grouped: false, gidx: List[Int]())
    var cidx = List[Int]()

    for i in 0..cols.length():
        let ci = find_col(db.tables[ti].cols, cols[i])
        if ci < 0:
            return error("no such column: {cols[i]}")

        cidx.append(ci)

    for e in vals:
        try check(e, sc, false, false)
    if has_where:
        try check(where_e, sc, false, false)

    let none_grp = List[List[Value]]()
    var newrows = List[List[Value]]()
    var count = 0

    for r in db.tables[ti].rows:
        var hit = true

        if has_where:
            let wv = try eval(where_e, sc, r, none_grp)
            hit = try keep_cond(wv)

        if hit:
            count += 1

            var newvals = List[Value]()

            for e in vals:
                let v = try eval(e, sc, r, none_grp)
                newvals.append(v)

            var nr = r.clone()
            for i in 0..cidx.length():
                nr[cidx[i]] = newvals[i].clone()
            try check_row(db.tables[ti].cols, nr)
            newrows.append(nr)
        else:
            newrows.append(r.clone())

    try check_pk(db.tables[ti].cols, newrows)
    db.tables[ti].rows = newrows
    return ok("updated {count}\n".as_bytes())

fn run_delete(var db: Db, name: String, has_where: Bool, where_e: Expr) Bytes!String:
    let ti = find_table(db, name)
    if ti < 0:
        return error("no such table: {name}")

    var srcs = List[Src]()
    srcs.append(Src(alias: name.clone(), cols: names_of(db.tables[ti].cols), off: 0))

    let sc = Scope(srcs: srcs, ns: 1, grouped: false, gidx: List[Int]())
    if has_where:
        try check(where_e, sc, false, false)

    let none_grp = List[List[Value]]()
    var kept = List[List[Value]]()
    var count = 0

    for r in db.tables[ti].rows:
        var hit = true

        if has_where:
            let wv = try eval(where_e, sc, r, none_grp)
            hit = try keep_cond(wv)

        if hit:
            count += 1
        else:
            kept.append(r.clone())

    db.tables[ti].rows = kept
    return ok("deleted {count}\n".as_bytes())

fn exec_stmt(var db: Db, st: Stmt) Bytes!String:
    match st:
        SCreate(name, cols):
            return run_create(var db, name.clone(), cols.clone())
        SDrop(name):
            return run_drop(var db, name.clone())
        SInsert(name, has_cols, cols, rows):
            return run_insert(
                var db, name.clone(), has_cols, cols.clone(), rows.clone()
            )
        SUpdate(name, cols, vals, has_where, where_e):
            return run_update(
                var db, name.clone(), cols.clone(), vals.clone(), has_where,
                where_e.clone()
            )
        SDelete(name, has_where, where_e):
            return run_delete(var db, name.clone(), has_where, where_e.clone())
        SSelect(sel):
            return run_select(db, sel.clone())

// Runs one statement chunk and returns its output (errors as `error: MESSAGE` lines).
fn run_chunk(var db: Db, chunk: Bytes) Bytes:
    let tr = lex(chunk)
    if tr.is_error():
        return "error: syntax error\n".as_bytes()

    let toks = tr.get()
    if toks.length() == 0:
        return "".as_bytes()

    let pr = parse_stmt(toks)
    if pr.is_error():
        return "error: syntax error\n".as_bytes()

    let st = pr.get()
    let er = exec_stmt(var db, st)
    if er.is_error():
        return "error: {er.err()}\n".as_bytes()

    return er.get()

export fn main() Int:
    let input = read_all(stdin()).get()
    var db = Db(tables: List[Table]())
    var out = BytesBuilder()
    let n = input.length()
    var i = 0
    var start = 0

    while i < n:
        let c = input.get(i)

        if c == 39:
            i += 1

            while i < n:
                if input.get(i) == 39:
                    if i + 1 < n and input.get(i + 1) == 39:
                        i += 2
                        continue

                    break

                i += 1

            i += 1
        else if c == 45 and i + 1 < n and input.get(i + 1) == 45:
            while i < n and input.get(i) != 10:
                i += 1
        else if c == 59:
            let chunk = input.slice(start, i).get()
            out.append_bytes(run_chunk(var db, chunk))
            i += 1
            start = i
        else:
            i += 1

    let last = input.slice(start, n).get()
    out.append_bytes(run_chunk(var db, last))
    stdout_bytes().write(out.build()).get()
    return 0

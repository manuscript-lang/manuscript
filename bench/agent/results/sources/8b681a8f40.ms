import (
    Bytes from "@std/bytes.ms",
    stdout from "@std/io/io.ms",
    read_all from "@std/io/streams.ms",
    stdin from "@std/io/io.ms",
)

// ---------------------------------------------------------------- values

enum Value:
    VNull
    VBool(b: Bool)
    VInt(v: Int)
    VText(s: String)

// Kind ranks double as the ORDER BY order: NULL < BOOL < INT < TEXT.
fn vkind(v: Value) Int:
    match v:
        VNull:
            return 0
        VBool(_b):
            return 1
        VInt(_x):
            return 2
        VText(_s):
            return 3

fn as_int(v: Value) Int:
    match v:
        VInt(x):
            return x
        _:
            return 0

fn as_bool(v: Value) Bool:
    match v:
        VBool(x):
            return x
        _:
            return false

fn as_text(v: Value) String:
    match v:
        VText(s):
            return s.clone()
        _:
            return ""

fn fmt_val(v: Value) String:
    match v:
        VNull:
            return "NULL"
        VBool(b):
            if b: return "true"

            return "false"
        VInt(x):
            return "{x}"
        VText(s):
            return s.clone()

fn cmp_val(a: Value, b: Value) Int:
    ka := vkind(a)
    kb := vkind(b)

    if ka != kb:
        if ka < kb: return -1

        return 1

    if ka == 2:
        x := as_int(a)
        y := as_int(b)
        if x < y: return -1
        if x > y: return 1

        return 0

    if ka == 3:
        s := as_text(a)
        t := as_text(b)
        if s < t: return -1
        if s > t: return 1

        return 0

    if ka == 1:
        x := as_bool(a)
        y := as_bool(b)
        if x == y: return 0
        if y: return -1

        return 1

    return 0

fn same_val(a: Value, b: Value) Bool:
    return cmp_val(a, b) == 0

fn same_row(a: List[Value], b: List[Value]) Bool:
    if a.length() != b.length(): return false

    for i in 0..a.length():
        if cmp_val(a[i], b[i]) != 0: return false
    return true

fn cmp_keys(a: List[Value], b: List[Value], descs: List[Bool]) Int:
    for k in 0..a.length():
        var c = cmp_val(a[k], b[k])
        if descs[k]:
            c = 0 - c
        if c != 0: return c

    return 0

fn nulls(n: Int) List[Value]:
    var out = List[Value]()
    for i in 0..n:
        out.append(VNull)
    return out

fn concat_row(a: List[Value], b: List[Value]) List[Value]:
    var out = List[Value]()
    for v in a:
        out.append(v.clone())
    for v in b:
        out.append(v.clone())
    return out

// ---------------------------------------------------------------- AST

type Tok:
    kind: String
    text: String
    iv: Int

type Seg:
    toks: List[Tok]
    err: Bool

enum Expr:
    Lit(v: Value)
    Col(q: String, name: String)
    Neg(e: Expr)
    Not(e: Expr)
    Bin(op: String, l: Expr, r: Expr)
    IsNull(e: Expr, neg: Bool)
    Like(e: Expr, p: Expr, neg: Bool)
    InList(e: Expr, items: List[Expr], neg: Bool)
    Between(e: Expr, lo: Expr, hi: Expr, neg: Bool)
    Call(name: String, args: List[Expr], distinct: Bool, star: Bool)

type ColDef:
    name: String
    typ: String
    pk: Bool
    nn: Bool

type AssignDef:
    col: String
    e: Expr

type TRef:
    name: String
    alias: String

type JoinSpec:
    left: Bool
    tref: TRef
    on: Expr

enum SelItem:
    Star
    TStar(t: String)
    Ex(e: Expr, alias: String?)

type OrdDef:
    e: Expr
    desc: Bool

type Sel:
    distinct: Bool
    items: List[SelItem]
    from_: List[TRef]
    joins: List[JoinSpec]
    where_e: Expr?
    group: List[Expr]
    having: Expr?
    order: List[OrdDef]
    limit: Int?
    offset: Int?

enum Stmt:
    Create(name: String, cols: List[ColDef])
    Drop(name: String)
    Insert(name: String, cols: List[String], has_cols: Bool, rows: List[List[Expr]])
    Update(name: String, sets: List[AssignDef], where_e: Expr?)
    Delete(name: String, where_e: Expr?)
    Query(s: Sel)

// ---------------------------------------------------------------- lexer

KEYWORDS := [
    "SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET",
    "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN",
    "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE",
    "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"
]
SINGLE_OPS := ["=", "<", ">", "+", "-", "*", "/", "%", "(", ")", ",", "."]

fn is_digit(c: String) Bool:
    return c >= "0" and c <= "9"

fn is_alpha(c: String) Bool:
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"

fn lex_all(cs: List[String]) List[Seg]:
    var segs = List[Seg]()
    var toks = List[Tok]()
    var err = false
    var i = 0
    n := cs.length()

    while i < n:
        c := cs[i]

        if c == ";":
            segs.append(Seg(toks: toks, err: err))
            toks = List[Tok]()
            err = false
            i += 1
        else if c == " " or c == "\t" or c == "\r" or c == "\n":
            i += 1
        else if c == "-" and i + 1 < n and cs[i + 1] == "-":
            while i < n and cs[i] != "\n":
                i += 1
        else if c == "'":
            var buf = ""
            i += 1

            var closed = false

            while i < n:
                if cs[i] == "'":
                    if i + 1 < n and cs[i + 1] == "'":
                        buf += "'"
                        i += 2
                    else:
                        closed = true
                        i += 1
                        break
                else:
                    buf += cs[i]
                    i += 1

            if closed:
                toks.append(Tok(kind: "str", text: buf, iv: 0))
            else:
                err = true
        else if is_alpha(c):
            var w = ""

            while i < n and (is_alpha(cs[i]) or is_digit(cs[i])):
                w += cs[i]
                i += 1

            up := w.upper()

            if KEYWORDS.contains(up):
                toks.append(Tok(kind: "kw", text: up, iv: 0))
            else:
                toks.append(Tok(kind: "id", text: w, iv: 0))
        else if is_digit(c):
            var d = ""

            while i < n and is_digit(cs[i]):
                d += cs[i]
                i += 1

            if v := d.parse_int():
                toks.append(Tok(kind: "int", text: d, iv: v))
            else:
                err = true
        else:
            var op = ""

            if i + 1 < n:
                two := c + cs[i + 1]

                if two == "<>" or two == "<=" or two == ">=" or two == "||":
                    op = two
                else if two == "!=":
                    op = "<>"

            if op != "":
                i += 2
                toks.append(Tok(kind: "op", text: op, iv: 0))
            else if SINGLE_OPS.contains(c):
                i += 1
                toks.append(Tok(kind: "op", text: c.clone(), iv: 0))
            else:
                err = true
                i += 1

    segs.append(Seg(toks: toks, err: err))
    return segs

// ---------------------------------------------------------------- parser

type Parser:
    toks: List[Tok]
    pos: Int

fn is_cmp_op(o: String) Bool:
    return o == "=" or o == "<>" or o == "<" or o == "<=" or o == ">" or o == ">="

impl Parser:
    fn kind_at(off: Int) String:
        i := self.pos + off
        if i < self.toks.length(): return self.toks[i].kind.clone()

        return "eof"

    fn kind() String:
        return self.kind_at(0)

    fn text_at(off: Int) String:
        i := self.pos + off
        if i < self.toks.length(): return self.toks[i].text.clone()

        return ""

    fn int_val() Int:
        if self.pos < self.toks.length(): return self.toks[self.pos].iv

        return 0

    fn is_kw(off: Int, w: String) Bool:
        return self.kind_at(off) == "kw" and self.text_at(off) == w

    fn is_op(off: Int, o: String) Bool:
        return self.kind_at(off) == "op" and self.text_at(off) == o

    var fn eat_kw(w: String) Bool:
        if self.is_kw(0, w):
            self.pos += 1
            return true

        return false

    var fn eat_op(o: String) Bool:
        if self.is_op(0, o):
            self.pos += 1
            return true

        return false

    var fn need_kw(w: String) Unit!String:
        if not self.eat_kw(w): return error("syntax error")


    var fn need_op(o: String) Unit!String:
        if not self.eat_op(o): return error("syntax error")


    var fn ident() String!String:
        if self.kind() == "id":
            s := self.text_at(0)
            self.pos += 1
            return ok(s)

        return error("syntax error")

    var fn int_lit() Int!String:
        if self.kind() == "int":
            v := self.int_val()
            self.pos += 1
            return ok(v)

        return error("syntax error")

    var fn colref() Expr!String:
        n := try self.ident()

        if self.eat_op("."):
            c := try self.ident()
            return ok(Col(q: n, name: c))

        return ok(Col(q: "", name: n))

    var fn call(name: String) Expr!String:
        try self.need_op("(")

        distinct := self.eat_kw("DISTINCT")
        var args = List[Expr]()

        if self.eat_op("*"):
            try self.need_op(")")
            return ok(
                Call(
                    name: name.upper(), args: args, distinct: distinct, star: true
                )
            )

        if not self.is_op(0, ")"):
            while true:
                a := try self.expr()
                args.append(a)
                if not self.eat_op(","): break

        try self.need_op(")")
        return ok(Call(name: name.upper(), args: args, distinct: distinct, star: false))

    var fn primary() Expr!String:
        k := self.kind()

        if k == "int":
            v := self.int_val()
            self.pos += 1
            return ok(Lit(v: VInt(v: v)))

        if k == "str":
            s := self.text_at(0)
            self.pos += 1
            return ok(Lit(v: VText(s: s)))

        if self.eat_kw("NULL"): return ok(Lit(v: VNull))

        if self.eat_op("("):
            e := try self.expr()
            try self.need_op(")")
            return ok(e)

        if k == "id":
            if self.is_op(1, "("):
                n := self.text_at(0)
                self.pos += 1

                c := try self.call(n)
                return ok(c)

            return self.colref()

        return error("syntax error")

    var fn unary_e() Expr!String:
        if self.eat_op("-"):
            e := try self.unary_e()
            return ok(Neg(e: e))

        return self.primary()

    var fn mul_e() Expr!String:
        var l = try self.unary_e()

        while (
            self.kind() == "op"
            and (
                self.text_at(0) == "*"
                or self.text_at(0) == "/"
                or self.text_at(0) == "%"
            )
        ):
            op := self.text_at(0)
            self.pos += 1

            r := try self.unary_e()
            l = Bin(op: op, l: l, r: r)

        return ok(l)

    var fn add_e() Expr!String:
        var l = try self.mul_e()

        while (
            self.kind() == "op"
            and (
                self.text_at(0) == "+"
                or self.text_at(0) == "-"
                or self.text_at(0) == "||"
            )
        ):
            op := self.text_at(0)
            self.pos += 1

            r := try self.mul_e()
            l = Bin(op: op, l: l, r: r)

        return ok(l)

    var fn cmp_e() Expr!String:
        a := try self.add_e()

        if self.kind() == "op" and is_cmp_op(self.text_at(0)):
            op := self.text_at(0)
            self.pos += 1

            b := try self.add_e()
            return ok(Bin(op: op, l: a, r: b))

        if self.eat_kw("IS"):
            isneg := self.eat_kw("NOT")
            try self.need_kw("NULL")
            return ok(IsNull(e: a, neg: isneg))

        var neg = false

        if (
            self.is_kw(0, "NOT")
            and (
                self.is_kw(1, "LIKE")
                or self.is_kw(1, "IN")
                or self.is_kw(1, "BETWEEN")
            )
        ):
            self.pos += 1
            neg = true

        if self.eat_kw("LIKE"):
            p := try self.add_e()
            return ok(Like(e: a, p: p, neg: neg))

        if self.eat_kw("IN"):
            try self.need_op("(")

            var items = List[Expr]()

            while true:
                x := try self.expr()
                items.append(x)
                if not self.eat_op(","): break

            try self.need_op(")")
            return ok(InList(e: a, items: items, neg: neg))

        if self.eat_kw("BETWEEN"):
            lo := try self.add_e()
            try self.need_kw("AND")

            hi := try self.add_e()
            return ok(Between(e: a, lo: lo, hi: hi, neg: neg))

        return ok(a)

    var fn not_e() Expr!String:
        if self.eat_kw("NOT"):
            e := try self.not_e()
            return ok(Not(e: e))

        return self.cmp_e()

    var fn and_e() Expr!String:
        var l = try self.not_e()

        while self.eat_kw("AND"):
            r := try self.not_e()
            l = Bin(op: "AND", l: l, r: r)

        return ok(l)

    var fn expr() Expr!String:
        var l = try self.and_e()

        while self.eat_kw("OR"):
            r := try self.and_e()
            l = Bin(op: "OR", l: l, r: r)

        return ok(l)

    var fn tref() TRef!String:
        name := try self.ident()
        var alias = name.clone()

        if self.eat_kw("AS"):
            alias = try self.ident()
        else if self.kind() == "id":
            alias = try self.ident()

        return ok(TRef(name: name, alias: alias))

    var fn select_item() SelItem!String:
        if self.eat_op("*"): return ok(Star)

        if self.kind() == "id" and self.is_op(1, ".") and self.is_op(2, "*"):
            t := try self.ident()
            self.pos += 2
            return ok(TStar(t: t))

        e := try self.expr()
        var alias: String? = none

        if self.eat_kw("AS"):
            a := try self.ident()
            alias = a

        return ok(Ex(e: e, alias: alias))

    var fn select_stmt() Sel!String:
        try self.need_kw("SELECT")

        distinct := self.eat_kw("DISTINCT")
        var items = List[SelItem]()

        while true:
            it := try self.select_item()
            items.append(it)
            if not self.eat_op(","): break

        var from_ = List[TRef]()

        if self.eat_kw("FROM"):
            t := try self.tref()
            from_.append(t)

        var joins = List[JoinSpec]()

        while (
            not from_.is_empty()
            and (
                self.is_kw(0, "JOIN")
                or self.is_kw(0, "INNER")
                or self.is_kw(0, "LEFT")
            )
        ):
            var left = false

            if self.eat_kw("LEFT"):
                left = true
            else:
                self.eat_kw("INNER")

            try self.need_kw("JOIN")

            t := try self.tref()
            try self.need_kw("ON")

            on := try self.expr()
            joins.append(JoinSpec(left: left, tref: t, on: on))

        var where_e: Expr? = none

        if self.eat_kw("WHERE"):
            w := try self.expr()
            where_e = w

        var group = List[Expr]()

        if self.eat_kw("GROUP"):
            try self.need_kw("BY")

            while true:
                g := try self.colref()
                group.append(g)
                if not self.eat_op(","): break

        var having: Expr? = none

        if self.eat_kw("HAVING"):
            h := try self.expr()
            having = h

        var order = List[OrdDef]()

        if self.eat_kw("ORDER"):
            try self.need_kw("BY")

            while true:
                e := try self.expr()
                var desc = false

                if self.eat_kw("DESC"):
                    desc = true
                else:
                    self.eat_kw("ASC")

                order.append(OrdDef(e: e, desc: desc))
                if not self.eat_op(","): break

        var limit: Int? = none
        var offset: Int? = none

        if self.eat_kw("LIMIT"):
            l := try self.int_lit()
            limit = l

            if self.eat_kw("OFFSET"):
                o := try self.int_lit()
                offset = o

        return ok(
            Sel(
                distinct: distinct, items: items, from_: from_, joins: joins,
                where_e: where_e, group: group, having: having, order: order,
                limit: limit, offset: offset
            )
        )

    var fn statement() Stmt!String:
        if self.eat_kw("CREATE"):
            try self.need_kw("TABLE")

            name := try self.ident()
            try self.need_op("(")

            var cols = List[ColDef]()

            while true:
                cn := try self.ident()
                if self.kind() != "id": return error("syntax error")

                tw := self.text_at(0).upper()
                if tw != "INT" and tw != "TEXT": return error("syntax error")

                self.pos += 1

                var pk = false
                var nn = false

                while true:
                    if self.eat_kw("PRIMARY"):
                        try self.need_kw("KEY")
                        pk = true
                    else if self.eat_kw("NOT"):
                        try self.need_kw("NULL")
                        nn = true
                    else:
                        break

                cols.append(ColDef(name: cn, typ: tw, pk: pk, nn: nn))
                if not self.eat_op(","): break

            try self.need_op(")")
            return ok(Create(name: name, cols: cols))

        if self.eat_kw("DROP"):
            try self.need_kw("TABLE")

            name := try self.ident()
            return ok(Drop(name: name))

        if self.eat_kw("INSERT"):
            try self.need_kw("INTO")

            name := try self.ident()
            var cols = List[String]()
            var has_cols = false

            if self.eat_op("("):
                has_cols = true

                while true:
                    c := try self.ident()
                    cols.append(c)
                    if not self.eat_op(","): break

                try self.need_op(")")

            try self.need_kw("VALUES")

            var rows = List[List[Expr]]()

            while true:
                try self.need_op("(")

                var vals = List[Expr]()

                while true:
                    v := try self.expr()
                    vals.append(v)
                    if not self.eat_op(","): break

                try self.need_op(")")
                rows.append(vals)
                if not self.eat_op(","): break

            return ok(Insert(name: name, cols: cols, has_cols: has_cols, rows: rows))

        if self.eat_kw("UPDATE"):
            name := try self.ident()
            try self.need_kw("SET")

            var sets = List[AssignDef]()

            while true:
                c := try self.ident()
                try self.need_op("=")

                e := try self.expr()
                sets.append(AssignDef(col: c, e: e))
                if not self.eat_op(","): break

            var w: Expr? = none

            if self.eat_kw("WHERE"):
                we := try self.expr()
                w = we

            return ok(Update(name: name, sets: sets, where_e: w))

        if self.eat_kw("DELETE"):
            try self.need_kw("FROM")

            name := try self.ident()
            var w: Expr? = none

            if self.eat_kw("WHERE"):
                we := try self.expr()
                w = we

            return ok(Delete(name: name, where_e: w))

        if self.is_kw(0, "SELECT"):
            s := try self.select_stmt()
            return ok(Query(s: s))

        return error("syntax error")

fn parse_stmt(toks: List[Tok]) Stmt!String:
    var p = Parser(toks: toks.clone(), pos: 0)
    st := try p.statement()
    if p.kind() != "eof": return error("syntax error")

    return ok(st)

// ---------------------------------------------------------------- tables

type TableDef:
    name: String
    cols: List[String]
    types: List[String]
    notnull: List[Bool]
    pk: Int
    rows: List[List[Value]]

type SCol:
    alias: String
    name: String

fn find_table(tables: List[TableDef], name: String) Int:
    for i in 0..tables.length():
        if tables[i].name == name: return i
    return -1

fn col_index(t: TableDef, name: String) Int:
    for i in 0..t.cols.length():
        if t.cols[i] == name: return i
    return -1

fn table_scope(t: TableDef, alias: String) List[SCol]:
    var sc = List[SCol]()
    for c in t.cols:
        sc.append(SCol(alias: alias.clone(), name: c.clone()))
    return sc

fn concat_scope(a: List[SCol], b: List[SCol]) List[SCol]:
    var out = List[SCol]()
    for x in a:
        out.append(x.clone())
    for x in b:
        out.append(x.clone())
    return out

fn find_col(sc: List[SCol], q: String, name: String) Int!String:
    var found = -1
    var count = 0

    for i in 0..sc.length():
        if sc[i].name == name and (q == "" or sc[i].alias == q):
            found = i
            count += 1

    if count == 0:
        if q == "": return error("no such column: " + name)

        return error("no such column: " + q + "." + name)

    if count > 1: return error("ambiguous column: " + name)

    return ok(found)

// ---------------------------------------------------------------- static checks

type Ck:
    aggq: Bool
    aggok: Bool
    grp: List[Int]

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

fn arity_ok(name: String, n: Int, star: Bool, distinct: Bool) Bool:
    if star: return name == "COUNT" and not distinct
    if distinct and n != 1: return false
    if name == "COUNT" or name == "SUM" or name == "MIN" or name == "MAX": return n == 1
    if name == "SUBSTR": return n == 3
    if name == "COALESCE": return n >= 1

    return n == 1

fn has_agg(e: Expr) Bool:
    match e:
        Call(name, args, _distinct, _star):
            if is_agg(name): return true

            for a in args:
                if has_agg(a): return true
            return false
        Neg(x):
            return has_agg(x)
        Not(x):
            return has_agg(x)
        IsNull(x, _neg):
            return has_agg(x)
        Bin(_op, l, r):
            return has_agg(l) or has_agg(r)
        Like(x, p, _neg):
            return has_agg(x) or has_agg(p)
        InList(x, items, _neg):
            if has_agg(x): return true

            for it in items:
                if has_agg(it): return true
            return false
        Between(x, lo, hi, _neg):
            return has_agg(x) or has_agg(lo) or has_agg(hi)
        _:
            return false

fn item_has_agg(it: SelItem) Bool:
    match it:
        Ex(e, _alias):
            return has_agg(e)
        _:
            return false

fn disp(q: String, name: String) String:
    if q == "": return name.clone()

    return q.clone() + "." + name.clone()

fn check(e: Expr, sc: List[SCol], ck: Ck, inagg: Bool) Unit!String:
    match e:
        Lit(_v):
            return ok(unit)
        Col(q, name):
            i := try find_col(sc, q, name)
            if ck.aggq and not inagg and not ck.grp.contains(i):
                return error("column " + disp(q, name) + " must appear in GROUP BY")

            return ok(unit)
        Neg(x):
            try check(x, sc, ck, inagg)
            return ok(unit)
        Not(x):
            try check(x, sc, ck, inagg)
            return ok(unit)
        IsNull(x, _neg):
            try check(x, sc, ck, inagg)
            return ok(unit)
        Bin(_op, l, r):
            try check(l, sc, ck, inagg)
            try check(r, sc, ck, inagg)
            return ok(unit)
        Like(x, p, _neg):
            try check(x, sc, ck, inagg)
            try check(p, sc, ck, inagg)
            return ok(unit)
        InList(x, items, _neg):
            try check(x, sc, ck, inagg)
            for it in items:
                try check(it, sc, ck, inagg)
            return ok(unit)
        Between(x, lo, hi, _neg):
            try check(x, sc, ck, inagg)
            try check(lo, sc, ck, inagg)
            try check(hi, sc, ck, inagg)
            return ok(unit)
        Call(name, args, distinct, star):
            if not (is_agg(name) or is_scalar(name)):
                return error("no such function: " + name)
            if not arity_ok(name, args.length(), star, distinct):
                return error("wrong number of arguments to " + name)

            if is_agg(name):
                if inagg or not ck.aggok: return error("misuse of aggregate")

                for a in args:
                    try check(a, sc, ck, true)
            else:
                for a in args:
                    try check(a, sc, ck, inagg)

            return ok(unit)

// ---------------------------------------------------------------- evaluation

fn cond_true(v: Value) Bool!String:
    match v:
        VBool(b):
            return ok(b)
        VNull:
            return ok(false)
        _:
            return error("type error")

fn and3(x: Value, y: Value) Value!String:
    kx := vkind(x)
    ky := vkind(y)
    if (kx != 0 and kx != 1) or (ky != 0 and ky != 1): return error("type error")
    if (kx == 1 and not as_bool(x)) or (ky == 1 and not as_bool(y)):
        return ok(VBool(b: false))
    if kx == 1 and ky == 1: return ok(VBool(b: true))

    return ok(VNull)

fn or3(x: Value, y: Value) Value!String:
    kx := vkind(x)
    ky := vkind(y)
    if (kx != 0 and kx != 1) or (ky != 0 and ky != 1): return error("type error")
    if (kx == 1 and as_bool(x)) or (ky == 1 and as_bool(y)): return ok(VBool(b: true))
    if kx == 1 and ky == 1: return ok(VBool(b: false))

    return ok(VNull)

fn not3(x: Value) Value!String:
    kx := vkind(x)
    if kx == 0: return ok(VNull)
    if kx == 1: return ok(VBool(b: not as_bool(x)))

    return error("type error")

fn compare_op(op: String, a: Value, b: Value) Value!String:
    ka := vkind(a)
    kb := vkind(b)
    if ka == 0 or kb == 0: return ok(VNull)
    if ka != kb or ka == 1: return error("type error")

    c := cmp_val(a, b)
    if op == "=": return ok(VBool(b: c == 0))
    if op == "<>": return ok(VBool(b: c != 0))
    if op == "<": return ok(VBool(b: c < 0))
    if op == "<=": return ok(VBool(b: c <= 0))
    if op == ">": return ok(VBool(b: c > 0))

    return ok(VBool(b: c >= 0))

fn arith_op(op: String, a: Value, b: Value) Value!String:
    ka := vkind(a)
    kb := vkind(b)
    if ka == 0 or kb == 0: return ok(VNull)
    if ka != 2 or kb != 2: return error("type error")

    x := as_int(a)
    y := as_int(b)
    if op == "+": return ok(VInt(v: x + y))
    if op == "-": return ok(VInt(v: x - y))
    if op == "*": return ok(VInt(v: x * y))
    if y == 0: return error("division by zero")
    if op == "/": return ok(VInt(v: x / y))

    return ok(VInt(v: x % y))

fn binop(op: String, a: Value, b: Value) Value!String:
    if op == "||":
        ka := vkind(a)
        kb := vkind(b)
        if ka == 0 or kb == 0: return ok(VNull)
        if ka != 3 or kb != 3: return error("type error")

        return ok(VText(s: as_text(a) + as_text(b)))

    if is_cmp_op(op): return compare_op(op, a, b)

    return arith_op(op, a, b)

fn like_match(s: Bytes, p: Bytes) Bool:
    n := s.length()
    m := p.length()
    pc := "%".to_bytes()[0]
    uc := "_".to_bytes()[0]
    var si = 0
    var pi = 0
    var star = -1
    var mark = 0

    while si < n:
        if pi < m and p[pi] == pc:
            star = pi
            mark = si
            pi += 1
        else if pi < m and (p[pi] == uc or p[pi] == s[si]):
            si += 1
            pi += 1
        else if star >= 0:
            pi = star + 1
            mark += 1
            si = mark
        else:
            return false

    while pi < m and p[pi] == pc:
        pi += 1
    return pi == m

fn ascii_map(s: String, up: Bool) String:
    var out = ""

    for c in s.chars():
        if up and c >= "a" and c <= "z":
            out += c.upper()
        else if not up and c >= "A" and c <= "Z":
            out += c.lower()
        else:
            out += c

    return out

fn scalar_call(
    name: String,
    args: List[Expr],
    sc: List[SCol],
    row: List[Value],
    grp: List[List[Value]]
) Value!String:
    var vals = List[Value]()

    for a in args:
        v := try ev(a, sc, row, grp)
        vals.append(v)

    if name == "COALESCE":
        for v in vals:
            if vkind(v) != 0: return ok(v.clone())
        return ok(VNull)

    for v in vals:
        if vkind(v) == 0: return ok(VNull)

    if name == "UPPER" or name == "LOWER":
        if vkind(vals[0]) != 3: return error("type error")

        return ok(VText(s: ascii_map(as_text(vals[0]), name == "UPPER")))

    if name == "LENGTH":
        if vkind(vals[0]) != 3: return error("type error")

        return ok(VInt(v: as_text(vals[0]).byte_length()))

    if name == "ABS":
        if vkind(vals[0]) != 2: return error("type error")

        x := as_int(vals[0])
        if x < 0: return ok(VInt(v: 0 - x))

        return ok(VInt(v: x))

    // SUBSTR(t, start, len)
    if vkind(vals[0]) != 3 or vkind(vals[1]) != 2 or vkind(vals[2]) != 2:
        return error("type error")

    bs := as_text(vals[0]).to_bytes()
    n := bs.length()
    start := as_int(vals[1])
    len := as_int(vals[2])
    if len <= 0: return ok(VText(s: ""))

    var from = start
    if from < 1:
        from = 1

    var to = start + len - 1
    if to > n:
        to = n
    if from > to: return ok(VText(s: ""))

    return ok(VText(s: bs.decode_utf8_range(from - 1, to).get("")))

fn agg_val(
    name: String,
    args: List[Expr],
    distinct: Bool,
    star: Bool,
    sc: List[SCol],
    grp: List[List[Value]]
) Value!String:
    if name == "COUNT" and star: return ok(VInt(v: grp.length()))

    var vals = List[Value]()
    none_grp := List[List[Value]]()

    for r in grp:
        v := try ev(args[0], sc, r, none_grp)
        if vkind(v) != 0:
            vals.append(v)

    if distinct:
        var u = List[Value]()

        for v in vals:
            var dup = false
            for w in u:
                if same_val(v, w):
                    dup = true
            if not dup:
                u.append(v.clone())

        vals = u

    if name == "COUNT": return ok(VInt(v: vals.length()))
    if vals.is_empty(): return ok(VNull)

    if name == "SUM":
        var total = 0

        for v in vals:
            if vkind(v) != 2: return error("type error")

            total += as_int(v)

        return ok(VInt(v: total))

    k0 := vkind(vals[0])
    if k0 == 1: return error("type error")

    var best = vals[0].clone()

    for v in vals:
        if vkind(v) != k0: return error("type error")

        c := cmp_val(v, best)
        if name == "MIN" and c < 0:
            best = v.clone()
        if name == "MAX" and c > 0:
            best = v.clone()

    return ok(best)

fn ev(e: Expr, sc: List[SCol], row: List[Value], grp: List[List[Value]]) Value!String:
    match e:
        Lit(v):
            return ok(v.clone())
        Col(q, name):
            i := try find_col(sc, q, name)
            if i >= row.length(): return ok(VNull)

            return ok(row[i].clone())
        Neg(x):
            v := try ev(x, sc, row, grp)
            if vkind(v) == 0: return ok(VNull)
            if vkind(v) != 2: return error("type error")

            return ok(VInt(v: 0 - as_int(v)))
        Not(x):
            v := try ev(x, sc, row, grp)
            r := try not3(v)
            return ok(r)
        IsNull(x, neg):
            v := try ev(x, sc, row, grp)
            isn := vkind(v) == 0
            return ok(VBool(b: isn != neg))
        Like(x, p, neg):
            xv := try ev(x, sc, row, grp)
            pv := try ev(p, sc, row, grp)
            if vkind(xv) == 0 or vkind(pv) == 0: return ok(VNull)
            if vkind(xv) != 3 or vkind(pv) != 3: return error("type error")

            m := like_match(as_text(xv).to_bytes(), as_text(pv).to_bytes())
            return ok(VBool(b: m != neg))
        InList(x, items, neg):
            xv := try ev(x, sc, row, grp)
            var vals = List[Value]()

            for it in items:
                v := try ev(it, sc, row, grp)
                vals.append(v)

            if vkind(xv) == 0: return ok(VNull)

            var sawnull = false

            for y in vals:
                eqv := try compare_op("=", xv, y)
                if vkind(eqv) == 1 and as_bool(eqv): return ok(VBool(b: not neg))

                if vkind(eqv) == 0:
                    sawnull = true

            if sawnull: return ok(VNull)

            return ok(VBool(b: neg))
        Between(x, lo, hi, neg):
            xv := try ev(x, sc, row, grp)
            lv := try ev(lo, sc, row, grp)
            hv := try ev(hi, sc, row, grp)
            a1 := try compare_op(">=", xv, lv)
            a2 := try compare_op("<=", xv, hv)
            var r = try and3(a1, a2)
            if neg:
                r = try not3(r)
            return ok(r)
        Bin(op, l, r):
            if op == "AND":
                a := try ev(l, sc, row, grp)
                if vkind(a) == 1 and not as_bool(a): return ok(VBool(b: false))

                b := try ev(r, sc, row, grp)
                res := try and3(a, b)
                return ok(res)

            if op == "OR":
                a := try ev(l, sc, row, grp)
                if vkind(a) == 1 and as_bool(a): return ok(VBool(b: true))

                b := try ev(r, sc, row, grp)
                res := try or3(a, b)
                return ok(res)

            a := try ev(l, sc, row, grp)
            b := try ev(r, sc, row, grp)
            res := try binop(op, a, b)
            return ok(res)
        Call(name, args, distinct, star):
            if is_agg(name):
                res := try agg_val(name, args, distinct, star, sc, grp)
                return ok(res)

            res := try scalar_call(name, args, sc, row, grp)
            return ok(res)

fn rep_row(u: List[List[Value]], w: Int) List[Value]:
    if not u.is_empty(): return u[0].clone()

    return nulls(w)

fn cond_of(e: Expr, sc: List[SCol], r: List[Value]) Bool!String:
    none_grp := List[List[Value]]()
    v := try ev(e, sc, r, none_grp)
    b := try cond_true(v)
    return ok(b)

// ---------------------------------------------------------------- SELECT

fn expr_name(e: Expr, alias: String?) String:
    if a := alias: return a.clone()

    match e:
        Col(_q, name):
            return name.clone()
        _:
            return "?column?"

fn lit_int(e: Expr) Int?:
    match e:
        Lit(v):
            if vkind(v) == 2: return as_int(v)

            return none
        _:
            return none

fn bare_name(e: Expr) String?:
    match e:
        Col(q, name):
            if q == "": return name.clone()

            return none
        _:
            return none

fn opt_present(e: Expr?) Bool:
    if _x := e: return true

    return false

fn run_select(tables: List[TableDef], s: Sel) List[String]!String:
    var refs = List[TRef]()
    for r in s.from_:
        refs.append(r.clone())
    for j in s.joins:
        refs.append(j.tref.clone())

    var tix = List[Int]()

    for r in refs:
        ti := find_table(tables, r.name)
        if ti < 0: return error("no such table: " + r.name)

        tix.append(ti)

    for i in 0..refs.length():
        for j in 0..i:
            if refs[j].alias == refs[i].alias:
                return error("duplicate alias: " + refs[i].alias)

    // scopes after each prefix of refs
    var scs = List[List[SCol]]()
    var acc = List[SCol]()

    for k in 0..refs.length():
        acc = concat_scope(acc, table_scope(tables[tix[k]], refs[k].alias.clone()))
        scs.append(acc.clone())

    var sc = List[SCol]()
    if not scs.is_empty():
        sc = scs[scs.length() - 1].clone()

    ck_row := Ck(aggq: false, aggok: false, grp: List[Int]())
    for j in 0..s.joins.length():
        try check(s.joins[j].on, scs[j + 1], ck_row, false)

    for it in s.items:
        match it:
            TStar(t):
                var found = false
                for c in sc:
                    if c.alias == t:
                        found = true
                if not found: return error("no such table: " + t)
            _:
                continue

    var aggq = s.group.length() > 0 or opt_present(s.having)
    for it in s.items:
        if item_has_agg(it):
            aggq = true
    for o in s.order:
        if has_agg(o.e):
            aggq = true

    var gidx = List[Int]()

    for g in s.group:
        match g:
            Col(q, name):
                i := try find_col(sc, q, name)
                gidx.append(i)
            _:
                return error("syntax error")

    if w := s.where_e:
        try check(w, sc, ck_row, false)

    ck_item := Ck(aggq: aggq, aggok: true, grp: gidx.clone())
    var names = List[String]()

    for it in s.items:
        match it:
            Star:
                for i in 0..sc.length():
                    if aggq and not gidx.contains(i):
                        return error(
                            "column " + sc[
                                i
                            ].name + " must appear in GROUP BY"
                        )

                    names.append(sc[i].name.clone())
            TStar(t):
                for i in 0..sc.length():
                    if sc[i].alias == t:
                        if aggq and not gidx.contains(i):
                            return error(
                                "column " + sc[
                                    i
                                ].name + " must appear in GROUP BY"
                            )

                        names.append(sc[i].name.clone())
            Ex(e, alias):
                try check(e, sc, ck_item, false)
                names.append(expr_name(e, alias))

    if h := s.having:
        try check(h, sc, ck_item, false)

    // ORDER BY resolution: kind 0 = expression, 1 = output column index
    var okind = List[Int]()
    var oval = List[Int]()
    var descs = List[Bool]()

    for o in s.order:
        descs.append(o.desc)

        var k = 0
        var ov = 0

        if n := lit_int(o.e):
            if n < 1 or n > names.length(): return error("bad ORDER BY position")

            k = 1
            ov = n - 1
        else if nm := bare_name(o.e):
            if p := names.index_of(nm):
                k = 1
                ov = p

        if k == 0:
            try check(o.e, sc, ck_item, false)
        okind.append(k)
        oval.append(ov)

    // ---- row production
    var rows = List[List[Value]]()

    if refs.is_empty():
        rows.append(List[Value]())
    else:
        for r in tables[tix[0]].rows:
            rows.append(r.clone())

    for j in 0..s.joins.length():
        w := tables[tix[j + 1]].cols.length()
        var nxt = List[List[Value]]()

        for o in rows:
            var matched = false

            for ir in tables[tix[j + 1]].rows:
                comb := concat_row(o, ir)
                okb := try cond_of(s.joins[j].on, scs[j + 1], comb)

                if okb:
                    nxt.append(comb)
                    matched = true

            if not matched and s.joins[j].left:
                nxt.append(concat_row(o, nulls(w)))

        rows = nxt

    if w := s.where_e:
        var kept = List[List[Value]]()

        for r in rows:
            okb := try cond_of(w, sc, r)
            if okb:
                kept.append(r.clone())

        rows = kept

    // ---- grouping
    var units = List[List[List[Value]]]()

    if aggq:
        if gidx.is_empty():
            units.append(rows)
        else:
            var keys = List[List[Value]]()

            for r in rows:
                var key = List[Value]()
                for gi in gidx:
                    key.append(r[gi].clone())

                var found = -1
                for k in 0..keys.length():
                    if found < 0 and same_row(keys[k], key):
                        found = k

                if found < 0:
                    keys.append(key)

                    var one = List[List[Value]]()
                    one.append(r.clone())
                    units.append(one)
                else:
                    units[found].append(r.clone())
    else:
        for r in rows:
            var one = List[List[Value]]()
            one.append(r.clone())
            units.append(one)

    // ---- HAVING and projection
    w_all := sc.length()
    var outs = List[List[Value]]()
    var ukeep = List[List[List[Value]]]()

    for u in units:
        rp := rep_row(u, w_all)

        if h := s.having:
            hv := try ev(h, sc, rp, u)
            hb := try cond_true(hv)
            if not hb: continue

        var row = List[Value]()

        for it in s.items:
            match it:
                Star:
                    for i in 0..sc.length():
                        row.append(rp[i].clone())
                TStar(t):
                    for i in 0..sc.length():
                        if sc[i].alias == t:
                            row.append(rp[i].clone())
                Ex(e, _alias):
                    v := try ev(e, sc, rp, u)
                    row.append(v)

        outs.append(row)
        ukeep.append(u.clone())

    // ---- DISTINCT
    var sel = List[Int]()

    for i in 0..outs.length():
        if s.distinct:
            var dup = false
            for k in sel:
                if same_row(outs[k], outs[i]):
                    dup = true
            if dup: continue

        sel.append(i)

    // ---- ORDER BY
    var srt = List[SortRow]()

    for i in sel:
        var keys = List[Value]()

        if not okind.is_empty():
            rp := rep_row(ukeep[i], w_all)

            for k in 0..okind.length():
                if okind[k] == 1:
                    keys.append(outs[i][oval[k]].clone())
                else:
                    kv := try ev(s.order[k].e, sc, rp, ukeep[i])
                    keys.append(kv)

        srt.append(SortRow(keys: keys, idx: i))

    if not okind.is_empty():
        srt.sort(fn(a: SortRow, b: SortRow) Int: cmp_keys(a.keys, b.keys, descs))

    // ---- OFFSET / LIMIT
    var off = 0
    if o := s.offset:
        off = o

    var lim = srt.length()
    if l := s.limit:
        lim = l

    var lines = List[String]()
    lines.append(names.join("|"))

    var cnt = 0
    var j = off

    while j < srt.length() and cnt < lim:
        row := outs[srt[j].idx]
        var parts = List[String]()
        for v in row:
            parts.append(fmt_val(v))
        lines.append(parts.join("|"))
        cnt += 1
        j += 1

    lines.append("({cnt} rows)")
    return ok(lines)

type SortRow:
    keys: List[Value]
    idx: Int

// ---------------------------------------------------------------- DDL / DML

fn check_val(t: TableDef, i: Int, v: Value) Unit!String:
    if vkind(v) == 0:
        if t.notnull[i]: return error("NOT NULL constraint failed: " + t.cols[i])

        return ok(unit)

    if t.types[i] == "INT" and vkind(v) != 2:
        return error("type mismatch in column " + t.cols[i])
    if t.types[i] == "TEXT" and vkind(v) != 3:
        return error("type mismatch in column " + t.cols[i])


fn pk_check(t: TableDef, rows: List[List[Value]]) Unit!String:
    if t.pk < 0: return ok(unit)

    for i in 0..rows.length():
        for j in 0..i:
            if same_val(rows[j][t.pk], rows[i][t.pk]):
                return error("duplicate primary key: " + fmt_val(rows[i][t.pk]))

fn do_create(var tables: List[TableDef], name: String, cols: List[ColDef]) List[String]!String:
    if find_table(tables, name) >= 0: return error("table " + name + " already exists")

    for i in 0..cols.length():
        for j in 0..i:
            if cols[j].name == cols[i].name:
                return error("duplicate column: " + cols[i].name)

    var npk = 0
    var pkidx = -1

    for i in 0..cols.length():
        if cols[i].pk:
            npk += 1
            pkidx = i

    if npk > 1: return error("multiple primary keys")

    var names = List[String]()
    var types = List[String]()
    var nn = List[Bool]()

    for c in cols:
        names.append(c.name.clone())
        types.append(c.typ.clone())
        nn.append(c.nn or c.pk)

    tables.append(
        TableDef(
            name: name, cols: names, types: types, notnull: nn, pk: pkidx,
            rows: List[List[Value]]()
        )
    )

    var out = List[String]()
    out.append("ok")
    return ok(out)

fn do_drop(var tables: List[TableDef], name: String) List[String]!String:
    ti := find_table(tables, name)
    if ti < 0: return error("no such table: " + name)

    tables.remove(ti)

    var out = List[String]()
    out.append("ok")
    return ok(out)

fn do_insert(
    var tables: List[TableDef], name: String, cols: List[String], has_cols: Bool,
    rows: List[List[Expr]]
) List[String]!String:
    ti := find_table(tables, name)
    if ti < 0: return error("no such table: " + name)

    t := TableDef(
        name: tables[ti].name.clone(), cols: tables[ti].cols.clone(),
        types: tables[ti].types.clone(), notnull: tables[ti].notnull.clone(),
        pk: tables[ti].pk, rows: List[List[Value]]()
    )
    var pos = List[Int]()

    if has_cols:
        for c in cols:
            i := col_index(t, c)
            if i < 0: return error("no such column: " + c)
            if pos.contains(i): return error("duplicate column: " + c)

            pos.append(i)
    else:
        for i in 0..t.cols.length():
            pos.append(i)

    empty_sc := List[SCol]()
    ck0 := Ck(aggq: false, aggok: false, grp: List[Int]())
    var newrows = List[List[Value]]()

    for r in rows:
        if r.length() != pos.length(): return error("wrong number of values")

        for e in r:
            try check(e, empty_sc, ck0, false)

        var full = nulls(t.cols.length())
        var k = 0

        for e in r:
            v := try ev(e, empty_sc, List[Value](), List[List[Value]]())
            full[pos[k]] = v
            k += 1

        for i in 0..t.cols.length():
            try check_val(t, i, full[i])
        newrows.append(full)

    if t.pk >= 0:
        for i in 0..newrows.length():
            v := newrows[i][t.pk]
            for ex in tables[ti].rows:
                if same_val(ex[t.pk], v):
                    return error("duplicate primary key: " + fmt_val(v))
            for j in 0..i:
                if same_val(newrows[j][t.pk], v):
                    return error("duplicate primary key: " + fmt_val(v))

    n := newrows.length()
    for nr in newrows:
        tables[ti].rows.append(nr)

    var out = List[String]()
    out.append("inserted {n}")
    return ok(out)

fn do_update(
    var tables: List[TableDef], name: String, sets: List[AssignDef], where_e: Expr?
) List[String]!String:
    ti := find_table(tables, name)
    if ti < 0: return error("no such table: " + name)

    var t = tables[ti].clone()
    sc := table_scope(t, name)
    var sidx = List[Int]()

    for a in sets:
        i := col_index(t, a.col)
        if i < 0: return error("no such column: " + a.col)

        sidx.append(i)

    ck0 := Ck(aggq: false, aggok: false, grp: List[Int]())
    for a in sets:
        try check(a.e, sc, ck0, false)
    if w := where_e:
        try check(w, sc, ck0, false)

    none_grp := List[List[Value]]()
    var newrows = List[List[Value]]()
    var cnt = 0

    for r in t.rows:
        var hit = true
        if w := where_e:
            hit = try cond_of(w, sc, r)

        if not hit:
            newrows.append(r.clone())
        else:
            cnt += 1

            var vals = List[Value]()

            for a in sets:
                v := try ev(a.e, sc, r, none_grp)
                vals.append(v)

            var nr = r.clone()
            for k in 0..sets.length():
                nr[sidx[k]] = vals[k].clone()
            for i in 0..nr.length():
                try check_val(t, i, nr[i])
            newrows.append(nr)

    try pk_check(t, newrows)
    t.rows = newrows
    tables[ti] = t

    var out = List[String]()
    out.append("updated {cnt}")
    return ok(out)

fn do_delete(var tables: List[TableDef], name: String, where_e: Expr?) List[String]!String:
    ti := find_table(tables, name)
    if ti < 0: return error("no such table: " + name)

    var t = tables[ti].clone()
    sc := table_scope(t, name)
    ck0 := Ck(aggq: false, aggok: false, grp: List[Int]())
    if w := where_e:
        try check(w, sc, ck0, false)

    var kept = List[List[Value]]()
    var cnt = 0

    for r in t.rows:
        var hit = true
        if w := where_e:
            hit = try cond_of(w, sc, r)

        if hit:
            cnt += 1
        else:
            kept.append(r.clone())

    t.rows = kept
    tables[ti] = t

    var out = List[String]()
    out.append("deleted {cnt}")
    return ok(out)

fn run_stmt(var tables: List[TableDef], st: Stmt) List[String]!String:
    match st:
        Create(name, cols):
            return do_create(var tables, name, cols)
        Drop(name):
            return do_drop(var tables, name)
        Insert(name, cols, has_cols, rows):
            return do_insert(var tables, name, cols, has_cols, rows)
        Update(name, sets, w):
            return do_update(var tables, name, sets, w)
        Delete(name, w):
            return do_delete(var tables, name, w)
        Query(s):
            return run_select(tables, s)

// ---------------------------------------------------------------- main

export fn main() Int:
    var text = ""
    rd := read_all(stdin())
    if rd.is_ok():
        text = rd.get().decode_utf8().get("")

    segs := lex_all(text.chars())
    var tables = List[TableDef]()
    var out = List[String]()

    for seg in segs:
        if seg.err:
            out.append("error: syntax error")
        else if not seg.toks.is_empty():
            pr := parse_stmt(seg.toks)

            if pr.is_error():
                out.append("error: " + pr.err())
            else:
                er := run_stmt(var tables, pr.get())

                if er.is_error():
                    out.append("error: " + er.err())
                else:
                    lines := er.get()
                    for l in lines:
                        out.append(l.clone())

    if not out.is_empty():
        stdout().write(out.join("\n") + "\n").get()
    return 0

import Bytes from "@std/bytes.ms"
import stdin, stdout from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

// ---------------------------------------------------------------- types

enum Value:
    VNull
    VInt(i: Int)
    VText(s: String)
    VBool(b: Bool)

enum Expr:
    Lit(v: Value)
    ColRef(tbl: String, name: String)
    Idx(i: Int, shown: String)
    Unary(op: String, e: Expr)
    Bin(op: String, l: Expr, r: Expr)
    IsNull(e: Expr, neg: Bool)
    Like(e: Expr, pat: Expr, neg: Bool)
    InList(e: Expr, items: List[Expr], neg: Bool)
    Between(e: Expr, lo: Expr, hi: Expr, neg: Bool)
    Call(name: String, args: List[Expr], distinct: Bool, star: Bool)

type Tok:
    kind: Int
    text: String
    num: Int

type Parser:
    toks: List[Tok]
    pos: Int

type ColDef:
    name: String
    ty: Int
    pk: Bool
    notnull: Bool

type SetItem:
    name: String
    e: Expr

type CRef:
    tbl: String
    name: String

type TRef:
    name: String
    alias: String

type JoinC:
    is_left: Bool
    tref: TRef
    cond: Expr

type SelItem:
    kind: Int
    e: Expr
    alias: String
    tbl: String

type OrdItem:
    lit: Bool
    n: Int
    e: Expr
    desc: Bool

type Query:
    distinct: Bool
    items: List[SelItem]
    has_from: Bool
    from_t: TRef
    joins: List[JoinC]
    has_where: Bool
    where_e: Expr
    group: List[CRef]
    has_having: Bool
    having_e: Expr
    order: List[OrdItem]
    has_limit: Bool
    limit_n: Int
    offset_n: Int

enum Stmt:
    SCreate(name: String, cols: List[ColDef])
    SDrop(name: String)
    SInsert(name: String, has_cols: Bool, cols: List[String], rows: List[List[Expr]])
    SUpdate(name: String, sets: List[SetItem], has_where: Bool, where_e: Expr)
    SDelete(name: String, has_where: Bool, where_e: Expr)
    SSelect(q: Query)

type Table:
    name: String
    cols: List[ColDef]
    rows: List[List[Value]]

type Src:
    alias: String
    cols: List[String]
    off: Int
    tidx: Int

type Changed:
    rows: List[List[Value]]
    count: Int

type OutRow:
    vals: List[Value]
    keys: List[Value]

// ---------------------------------------------------------------- lexer

fn code_of(c: String) Int:
    return c.scalar_at(0, -1)

fn is_alpha(k: Int) Bool:
    if k >= 65 and k <= 90:
        return true
    if k >= 97 and k <= 122:
        return true

    return k == 95

fn is_alnum(k: Int) Bool:
    if is_alpha(k):
        return true

    return k >= 48 and k <= 57

fn is_keyword(w: String) Bool:
    return [
        "SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET",
        "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE",
        "IN", "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"
    ].contains(w)

fn lex(cs: List[String]) Result[List[Tok], String]:
    var toks: List[Tok] = []
    n := cs.length()
    var i = 0

    while i < n:
        c := cs[i]
        k := code_of(c)

        if k == 32 or k == 9 or k == 10 or k == 13:
            i += 1
        else if k == 45 and i + 1 < n and cs[i + 1] == "-":
            while i < n and cs[i] != "\n":
                i += 1
        else if is_alpha(k):
            var word = ""

            while i < n and is_alnum(code_of(cs[i])):
                word = word + cs[i]
                i += 1

            up := word.upper()

            if is_keyword(up):
                toks.append(Tok(kind: 2, text: up, num: 0))
            else:
                toks.append(Tok(kind: 1, text: word, num: 0))
        else if k >= 48 and k <= 57:
            var v = 0

            while i < n and code_of(cs[i]) >= 48 and code_of(cs[i]) <= 57:
                d := code_of(cs[i]) - 48
                if v > (9223372036854775807 - d) / 10:
                    return error("syntax error")

                v = v * 10 + d
                i += 1

            toks.append(Tok(kind: 3, text: "", num: v))
        else if k == 39:
            var s = ""
            var closed = false
            i += 1

            while i < n:
                if cs[i] == "'":
                    if i + 1 < n and cs[i + 1] == "'":
                        s = s + "'"
                        i += 2
                    else:
                        closed = true
                        i += 1
                        break
                else:
                    s = s + cs[i]
                    i += 1

            if not closed:
                return error("syntax error")

            toks.append(Tok(kind: 4, text: s, num: 0))
        else:
            var two = ""
            if i + 1 < n:
                two = c + cs[i + 1]

            if two == "<>" or two == "<=" or two == ">=" or two == "||":
                toks.append(Tok(kind: 5, text: two, num: 0))
                i += 2
            else if two == "!=":
                toks.append(Tok(kind: 5, text: "<>", num: 0))
                i += 2
            else if "=<>+-*/%(),.".contains(c):
                toks.append(Tok(kind: 5, text: c.clone(), num: 0))
                i += 1
            else:
                return error("syntax error")

    toks.append(Tok(kind: 0, text: "", num: 0))
    return ok(toks)

// Splits the script at ';' outside string literals and comments.
fn split_statements(cs: List[String]) List[List[String]]:
    var out: List[List[String]] = []
    var cur: List[String] = []
    var instr = false
    var incom = false
    n := cs.length()
    var i = 0

    while i < n:
        c := cs[i]
        k := code_of(c)

        if incom:
            if k == 10:
                incom = false
        else if instr:
            if k == 39:
                instr = false
        else if k == 39:
            instr = true
        else if k == 45 and i + 1 < n and cs[i + 1] == "-":
            incom = true
        else if k == 59:
            out.append(cur.clone())
            cur = []
            i += 1
            continue

        cur.append(c.clone())
        i += 1

    out.append(cur.clone())
    return out

// ---------------------------------------------------------------- parser

fn kind_at(p: Parser) Int:
    return p.toks[p.pos].kind

fn kind_off(p: Parser, off: Int) Int:
    j := p.pos + off
    if j >= p.toks.length():
        return 0

    return p.toks[j].kind

fn kw_at(p: Parser, w: String) Bool:
    t := p.toks[p.pos]
    return t.kind == 2 and t.text == w

fn kw_off(p: Parser, off: Int, w: String) Bool:
    j := p.pos + off
    if j >= p.toks.length():
        return false

    t := p.toks[j]
    return t.kind == 2 and t.text == w

fn op_at(p: Parser, s: String) Bool:
    t := p.toks[p.pos]
    return t.kind == 5 and t.text == s

fn op_off(p: Parser, off: Int, s: String) Bool:
    j := p.pos + off
    if j >= p.toks.length():
        return false

    t := p.toks[j]
    return t.kind == 5 and t.text == s

fn adv(var p: Parser) Unit:
    if p.pos < p.toks.length() - 1:
        p.pos += 1

fn take_text(var p: Parser) String:
    s := p.toks[p.pos].text.clone()
    adv(var p)
    return s

fn expect_kw(var p: Parser, w: String) Result[Unit, String]:
    if not kw_at(p, w):
        return error("syntax error")

    adv(var p)
    return ok(unit)

fn expect_op(var p: Parser, s: String) Result[Unit, String]:
    if not op_at(p, s):
        return error("syntax error")

    adv(var p)
    return ok(unit)

fn ident(var p: Parser) Result[String, String]:
    if kind_at(p) != 1:
        return error("syntax error")

    return ok(take_text(var p))

fn parse_expr(var p: Parser) Result[Expr, String]:
    return parse_or(var p)

fn parse_or(var p: Parser) Result[Expr, String]:
    var left = try parse_and(var p)

    while kw_at(p, "OR"):
        adv(var p)

        right := try parse_and(var p)
        left = Bin("OR", left, right)

    return ok(left)

fn parse_and(var p: Parser) Result[Expr, String]:
    var left = try parse_not(var p)

    while kw_at(p, "AND"):
        adv(var p)

        right := try parse_not(var p)
        left = Bin("AND", left, right)

    return ok(left)

fn parse_not(var p: Parser) Result[Expr, String]:
    if kw_at(p, "NOT"):
        adv(var p)

        e := try parse_not(var p)
        return ok(Unary("NOT", e))

    return parse_cmp(var p)

fn is_cmp_op(p: Parser) Bool:
    return (
        op_at(p, "=")
        or op_at(p, "<>")
        or op_at(p, "!=")
        or op_at(p, "<")
        or op_at(p, "<=")
        or op_at(p, ">")
        or op_at(p, ">=")
    )

fn parse_cmp(var p: Parser) Result[Expr, String]:
    a := try parse_add(var p)

    if is_cmp_op(p):
        op0 := take_text(var p)
        var op = op0
        if op == "!=":
            op = "<>"

        b := try parse_add(var p)
        return ok(Bin(op, a, b))

    if kw_at(p, "IS"):
        adv(var p)

        var isneg = false

        if kw_at(p, "NOT"):
            adv(var p)
            isneg = true

        try expect_kw(var p, "NULL")
        return ok(IsNull(a, isneg))

    var neg = false

    if kw_at(p, "NOT"):
        adv(var p)
        neg = true
        if not (kw_at(p, "LIKE") or kw_at(p, "IN") or kw_at(p, "BETWEEN")):
            return error("syntax error")

    if kw_at(p, "LIKE"):
        adv(var p)

        pat := try parse_add(var p)
        return ok(Like(a, pat, neg))

    if kw_at(p, "IN"):
        adv(var p)
        try expect_op(var p, "(")

        var items: List[Expr] = []
        e1 := try parse_expr(var p)
        items.append(e1)

        while op_at(p, ","):
            adv(var p)

            en := try parse_expr(var p)
            items.append(en)

        try expect_op(var p, ")")
        return ok(InList(a, items, neg))

    if kw_at(p, "BETWEEN"):
        adv(var p)

        lo := try parse_add(var p)
        try expect_kw(var p, "AND")

        hi := try parse_add(var p)
        return ok(Between(a, lo, hi, neg))

    if neg:
        return error("syntax error")

    return ok(a)

fn parse_add(var p: Parser) Result[Expr, String]:
    var left = try parse_mul(var p)

    while op_at(p, "+") or op_at(p, "-") or op_at(p, "||"):
        op := take_text(var p)
        right := try parse_mul(var p)
        left = Bin(op, left, right)

    return ok(left)

fn parse_mul(var p: Parser) Result[Expr, String]:
    var left = try parse_unary(var p)

    while op_at(p, "*") or op_at(p, "/") or op_at(p, "%"):
        op := take_text(var p)
        right := try parse_unary(var p)
        left = Bin(op, left, right)

    return ok(left)

fn parse_unary(var p: Parser) Result[Expr, String]:
    if op_at(p, "-"):
        adv(var p)

        e := try parse_unary(var p)
        return ok(Unary("-", e))

    return parse_primary(var p)

fn parse_primary(var p: Parser) Result[Expr, String]:
    k := kind_at(p)

    if k == 3:
        v := p.toks[p.pos].num
        adv(var p)
        return ok(Lit(VInt(v)))

    if k == 4:
        s := take_text(var p)
        return ok(Lit(VText(s)))

    if kw_at(p, "NULL"):
        adv(var p)
        return ok(Lit(VNull))

    if op_at(p, "("):
        adv(var p)

        e := try parse_expr(var p)
        try expect_op(var p, ")")
        return ok(e)

    if k == 1:
        name := take_text(var p)

        if op_at(p, "("):
            adv(var p)
            return parse_call(var p, name)

        if op_at(p, "."):
            adv(var p)

            col := try ident(var p)
            return ok(ColRef(name, col))

        return ok(ColRef("", name))

    return error("syntax error")

fn parse_call(var p: Parser, name: String) Result[Expr, String]:
    var distinct = false
    var star = false
    var args: List[Expr] = []

    if kw_at(p, "DISTINCT"):
        adv(var p)
        distinct = true

    if op_at(p, "*"):
        adv(var p)
        star = true
    else if not op_at(p, ")"):
        a1 := try parse_expr(var p)
        args.append(a1)

        while op_at(p, ","):
            adv(var p)

            an := try parse_expr(var p)
            args.append(an)

    try expect_op(var p, ")")
    return ok(Call(name.upper(), args, distinct, star))

fn parse_colref(var p: Parser) Result[CRef, String]:
    a := try ident(var p)

    if op_at(p, "."):
        adv(var p)

        b := try ident(var p)
        return ok(CRef(tbl: a, name: b))

    return ok(CRef(tbl: "", name: a))

fn parse_tref(var p: Parser) Result[TRef, String]:
    name := try ident(var p)
    var alias = ""

    if kw_at(p, "AS"):
        adv(var p)
        alias = try ident(var p)
    else if kind_at(p) == 1:
        alias = take_text(var p)

    return ok(TRef(name: name, alias: alias))

fn parse_item(var p: Parser) Result[SelItem, String]:
    if op_at(p, "*"):
        adv(var p)
        return ok(SelItem(kind: 1, e: Lit(VNull), alias: "", tbl: ""))

    if kind_at(p) == 1 and op_off(p, 1, ".") and op_off(p, 2, "*"):
        tname := take_text(var p)
        adv(var p)
        adv(var p)
        return ok(SelItem(kind: 2, e: Lit(VNull), alias: "", tbl: tname))

    e := try parse_expr(var p)
    var alias = ""

    if kw_at(p, "AS"):
        adv(var p)
        alias = try ident(var p)

    return ok(SelItem(kind: 0, e: e, alias: alias, tbl: ""))

fn parse_order(var p: Parser) Result[OrdItem, String]:
    var lit = false
    var n = 0
    var e: Expr = Lit(VNull)

    if (
        kind_at(p) == 3
        and (
            kind_off(p, 1) == 0
            or op_off(p, 1, ",")
            or kw_off(p, 1, "ASC")
            or kw_off(p, 1, "DESC")
        )
    ):
        lit = true
        n = p.toks[p.pos].num
        adv(var p)
    else:
        e = try parse_expr(var p)

    var desc = false

    if kw_at(p, "DESC"):
        adv(var p)
        desc = true
    else if kw_at(p, "ASC"):
        adv(var p)

    return ok(OrdItem(lit: lit, n: n, e: e, desc: desc))

fn parse_select(var p: Parser) Result[Query, String]:
    try expect_kw(var p, "SELECT")

    var distinct = false

    if kw_at(p, "DISTINCT"):
        adv(var p)
        distinct = true

    var items: List[SelItem] = []
    it1 := try parse_item(var p)
    items.append(it1)

    while op_at(p, ","):
        adv(var p)

        itn := try parse_item(var p)
        items.append(itn)

    var has_from = false
    var from_t = TRef(name: "", alias: "")
    var joins: List[JoinC] = []

    if kw_at(p, "FROM"):
        adv(var p)
        has_from = true
        from_t = try parse_tref(var p)

        while kw_at(p, "JOIN") or kw_at(p, "INNER") or kw_at(p, "LEFT"):
            var is_left = false

            if kw_at(p, "INNER"):
                adv(var p)
            else if kw_at(p, "LEFT"):
                adv(var p)
                is_left = true

            try expect_kw(var p, "JOIN")

            tr := try parse_tref(var p)
            try expect_kw(var p, "ON")

            cond := try parse_expr(var p)
            joins.append(JoinC(is_left: is_left, tref: tr, cond: cond))

    var has_where = false
    var where_e: Expr = Lit(VNull)

    if kw_at(p, "WHERE"):
        adv(var p)
        has_where = true
        where_e = try parse_expr(var p)

    var group: List[CRef] = []

    if kw_at(p, "GROUP"):
        adv(var p)
        try expect_kw(var p, "BY")

        g1 := try parse_colref(var p)
        group.append(g1)

        while op_at(p, ","):
            adv(var p)

            gn := try parse_colref(var p)
            group.append(gn)

    var has_having = false
    var having_e: Expr = Lit(VNull)

    if kw_at(p, "HAVING"):
        adv(var p)
        has_having = true
        having_e = try parse_expr(var p)

    var order: List[OrdItem] = []

    if kw_at(p, "ORDER"):
        adv(var p)
        try expect_kw(var p, "BY")

        o1 := try parse_order(var p)
        order.append(o1)

        while op_at(p, ","):
            adv(var p)

            on2 := try parse_order(var p)
            order.append(on2)

    var has_limit = false
    var limit_n = 0
    var offset_n = 0

    if kw_at(p, "LIMIT"):
        adv(var p)
        if kind_at(p) != 3:
            return error("syntax error")

        has_limit = true
        limit_n = p.toks[p.pos].num
        adv(var p)

        if kw_at(p, "OFFSET"):
            adv(var p)
            if kind_at(p) != 3:
                return error("syntax error")

            offset_n = p.toks[p.pos].num
            adv(var p)

    return ok(
        Query(
            distinct: distinct, items: items, has_from: has_from, from_t: from_t,
            joins: joins, has_where: has_where, where_e: where_e, group: group,
            has_having: has_having, having_e: having_e, order: order,
            has_limit: has_limit, limit_n: limit_n, offset_n: offset_n
        )
    )

fn parse_coldef(var p: Parser) Result[ColDef, String]:
    name := try ident(var p)
    tyname := try ident(var p)
    up := tyname.upper()
    var ty = 0

    if up == "INT":
        ty = 1
    else if up == "TEXT":
        ty = 2
    else:
        return error("syntax error")

    var pk = false
    var notnull = false

    while true:
        if kw_at(p, "PRIMARY"):
            adv(var p)
            try expect_kw(var p, "KEY")
            pk = true
            notnull = true
        else if kw_at(p, "NOT"):
            adv(var p)
            try expect_kw(var p, "NULL")
            notnull = true
        else:
            break

    return ok(ColDef(name: name, ty: ty, pk: pk, notnull: notnull))

fn parse_create(var p: Parser) Result[Stmt, String]:
    try expect_kw(var p, "CREATE")
    try expect_kw(var p, "TABLE")

    name := try ident(var p)
    try expect_op(var p, "(")

    var cols: List[ColDef] = []
    c1 := try parse_coldef(var p)
    cols.append(c1)

    while op_at(p, ","):
        adv(var p)

        cn := try parse_coldef(var p)
        cols.append(cn)

    try expect_op(var p, ")")
    return ok(SCreate(name: name, cols: cols))

fn parse_drop(var p: Parser) Result[Stmt, String]:
    try expect_kw(var p, "DROP")
    try expect_kw(var p, "TABLE")

    name := try ident(var p)
    return ok(SDrop(name: name))

fn parse_row(var p: Parser) Result[List[Expr], String]:
    try expect_op(var p, "(")

    var vals: List[Expr] = []
    e1 := try parse_expr(var p)
    vals.append(e1)

    while op_at(p, ","):
        adv(var p)

        en := try parse_expr(var p)
        vals.append(en)

    try expect_op(var p, ")")
    return ok(vals)

fn parse_insert(var p: Parser) Result[Stmt, String]:
    try expect_kw(var p, "INSERT")
    try expect_kw(var p, "INTO")

    name := try ident(var p)
    var has_cols = false
    var cols: List[String] = []

    if op_at(p, "("):
        adv(var p)
        has_cols = true

        c1 := try ident(var p)
        cols.append(c1)

        while op_at(p, ","):
            adv(var p)

            cn := try ident(var p)
            cols.append(cn)

        try expect_op(var p, ")")

    try expect_kw(var p, "VALUES")

    var rows: List[List[Expr]] = []
    r1 := try parse_row(var p)
    rows.append(r1)

    while op_at(p, ","):
        adv(var p)

        rn := try parse_row(var p)
        rows.append(rn)

    return ok(SInsert(name: name, has_cols: has_cols, cols: cols, rows: rows))

fn parse_update(var p: Parser) Result[Stmt, String]:
    try expect_kw(var p, "UPDATE")

    name := try ident(var p)
    try expect_kw(var p, "SET")

    var sets: List[SetItem] = []
    var more = true

    while more:
        cn := try ident(var p)
        try expect_op(var p, "=")

        e := try parse_expr(var p)
        sets.append(SetItem(name: cn, e: e))

        if op_at(p, ","):
            adv(var p)
        else:
            more = false

    var has_where = false
    var where_e: Expr = Lit(VNull)

    if kw_at(p, "WHERE"):
        adv(var p)
        has_where = true
        where_e = try parse_expr(var p)

    return ok(SUpdate(name: name, sets: sets, has_where: has_where, where_e: where_e))

fn parse_delete(var p: Parser) Result[Stmt, String]:
    try expect_kw(var p, "DELETE")
    try expect_kw(var p, "FROM")

    name := try ident(var p)
    var has_where = false
    var where_e: Expr = Lit(VNull)

    if kw_at(p, "WHERE"):
        adv(var p)
        has_where = true
        where_e = try parse_expr(var p)

    return ok(SDelete(name: name, has_where: has_where, where_e: where_e))

fn finish_stmt(p: Parser, st: Stmt) Result[Stmt, String]:
    if kind_at(p) != 0:
        return error("syntax error")

    return ok(st.clone())

fn parse_statement(var p: Parser) Result[Stmt, String]:
    if kw_at(p, "SELECT"):
        q := try parse_select(var p)
        return finish_stmt(p, SSelect(q))

    if kw_at(p, "INSERT"):
        st := try parse_insert(var p)
        return finish_stmt(p, st)

    if kw_at(p, "UPDATE"):
        st := try parse_update(var p)
        return finish_stmt(p, st)

    if kw_at(p, "DELETE"):
        st := try parse_delete(var p)
        return finish_stmt(p, st)

    if kw_at(p, "CREATE"):
        st := try parse_create(var p)
        return finish_stmt(p, st)

    if kw_at(p, "DROP"):
        st := try parse_drop(var p)
        return finish_stmt(p, st)

    return error("syntax error")

// ---------------------------------------------------------------- values

fn kind(v: Value) Int:
    match v:
        VNull:
            return 0
        VInt(_i):
            return 1
        VText(_s):
            return 2
        VBool(_b):
            return 3

fn ival(v: Value) Int:
    match v:
        VInt(i):
            return i
        _:
            return 0

fn sval(v: Value) String:
    match v:
        VText(s):
            return s.clone()
        _:
            return ""

// Three-valued truth: 1 true, 0 false, 2 NULL, -1 not a boolean.
fn tri(v: Value) Int:
    match v:
        VNull:
            return 2
        VInt(_i):
            return -1
        VText(_s):
            return -1
        VBool(b):
            if b:
                return 1

            return 0

fn from_tri(t: Int) Value:
    if t == 2:
        return VNull

    return VBool(t == 1)

fn same(a: Value, b: Value) Bool:
    ka := kind(a)
    kb := kind(b)
    if ka != kb:
        return false
    if ka == 0:
        return true
    if ka == 1:
        return ival(a) == ival(b)
    if ka == 2:
        return sval(a) == sval(b)

    return tri(a) == tri(b)

fn same_row(a: List[Value], b: List[Value]) Bool:
    if a.length() != b.length():
        return false

    var i = 0

    while i < a.length():
        if not same(a[i], b[i]):
            return false

        i += 1

    return true

fn vstr(v: Value) String:
    match v:
        VNull:
            return "NULL"
        VInt(i):
            return "{i}"
        VText(s):
            return s.clone()
        VBool(b):
            if b:
                return "true"

            return "false"

fn type_ok(ty: Int, v: Value) Bool:
    if ty == 1:
        return kind(v) == 1

    return kind(v) == 2

// Ordering used by ORDER BY: NULL < BOOL < INT < TEXT.
fn rank(v: Value) Int:
    k := kind(v)
    if k == 3:
        return 1
    if k == 1:
        return 2
    if k == 2:
        return 3

    return 0

fn cmp_sort(a: Value, b: Value) Int:
    ra := rank(a)
    rb := rank(b)

    if ra != rb:
        if ra < rb:
            return -1

        return 1

    if ra == 2:
        x := ival(a)
        y := ival(b)
        if x < y:
            return -1
        if x > y:
            return 1

        return 0

    if ra == 3:
        x := sval(a)
        y := sval(b)
        if x < y:
            return -1
        if x > y:
            return 1

        return 0

    if ra == 1:
        return tri(a) - tri(b)

    return 0

fn cmp_out(x: OutRow, y: OutRow, desc: List[Bool]) Int:
    var i = 0

    while i < desc.length():
        c := cmp_sort(x.keys[i], y.keys[i])

        if c != 0:
            if desc[i]:
                return 0 - c

            return c

        i += 1

    return 0

fn compare_op(op: String, a: Value, b: Value) Result[Value, String]:
    ka := kind(a)
    kb := kind(b)
    if ka == 0 or kb == 0:
        return ok(VNull)
    if ka != kb or ka == 3:
        return error("type error")

    var c = 0

    if ka == 1:
        x := ival(a)
        y := ival(b)

        if x < y:
            c = -1
        else if x > y:
            c = 1
    else:
        x := sval(a)
        y := sval(b)

        if x < y:
            c = -1
        else if x > y:
            c = 1

    if op == "=":
        return ok(VBool(c == 0))
    if op == "<>":
        return ok(VBool(c != 0))
    if op == "<":
        return ok(VBool(c < 0))
    if op == "<=":
        return ok(VBool(c <= 0))
    if op == ">":
        return ok(VBool(c > 0))

    return ok(VBool(c >= 0))

fn arith(op: String, a: Value, b: Value) Result[Value, String]:
    ka := kind(a)
    kb := kind(b)
    if ka == 0 or kb == 0:
        return ok(VNull)
    if ka != 1 or kb != 1:
        return error("type error")

    x := ival(a)
    y := ival(b)
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

fn concat_op(a: Value, b: Value) Result[Value, String]:
    ka := kind(a)
    kb := kind(b)
    if ka == 0 or kb == 0:
        return ok(VNull)
    if ka != 2 or kb != 2:
        return error("type error")

    return ok(VText(sval(a) + sval(b)))

fn like_rec(s: Bytes, si: Int, p: Bytes, pi: Int) Bool:
    if pi == p.length():
        return si == s.length()

    pc := p.get(pi).to_int()

    if pc == 37:
        var k = si

        while k <= s.length():
            if like_rec(s, k, p, pi + 1):
                return true

            k += 1

        return false

    if si >= s.length():
        return false
    if pc == 95 or pc == s.get(si).to_int():
        return like_rec(s, si + 1, p, pi + 1)

    return false

fn logic(
    isand: Bool,
    row: List[Value],
    grp: List[List[Value]],
    l: Expr,
    r: Expr
) Result[Value, String]:
    lv := try ev(row, grp, l)
    lt := tri(lv)
    if isand and lt == 0:
        return ok(VBool(false))
    if not isand and lt == 1:
        return ok(VBool(true))

    rv := try ev(row, grp, r)
    rt := tri(rv)
    if lt == -1 or rt == -1:
        return error("type error")

    if isand:
        if lt == 1:
            return ok(from_tri(rt))
        if rt == 0:
            return ok(VBool(false))

        return ok(VNull)

    if lt == 0:
        return ok(from_tri(rt))
    if rt == 1:
        return ok(VBool(true))

    return ok(VNull)

fn is_agg(name: String) Bool:
    return name == "COUNT" or name == "SUM" or name == "MIN" or name == "MAX"

fn substr_fn(vals: List[Value]) Result[Value, String]:
    s := vals[0]
    st := vals[1]
    ln := vals[2]
    ks := kind(s)
    kst := kind(st)
    kln := kind(ln)
    if (ks != 0 and ks != 2) or (kst != 0 and kst != 1) or (kln != 0 and kln != 1):
        return error("type error")
    if ks == 0 or kst == 0 or kln == 0:
        return ok(VNull)

    bs := sval(s).as_bytes()
    n := bs.length()
    start := ival(st)
    len := ival(ln)
    if len <= 0:
        return ok(VText(""))

    var first = start
    if first < 1:
        first = 1

    skipped := first - start
    var take = len - skipped
    avail := n - first + 1
    if take > avail:
        take = avail
    if take <= 0:
        return ok(VText(""))

    piece := bs.slice(first - 1, first - 1 + take).get()
    if t := piece.decode_utf8():
        return ok(VText(t.clone()))

    return ok(VText(""))

// ASCII-only case mapping.
fn ascii_case(s: String, up: Bool) String:
    var out = ""

    for c in s.split_after(""):
        k := code_of(c)

        if up and k >= 97 and k <= 122:
            out = out + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".get(k - 97)
        else if not up and k >= 65 and k <= 90:
            out = out + "abcdefghijklmnopqrstuvwxyz".get(k - 65)
        else:
            out = out + c

    return out

fn scalar_fn(name: String, vals: List[Value]) Result[Value, String]:
    if name == "COALESCE":
        for v in vals:
            if kind(v) != 0:
                return ok(v.clone())
        return ok(VNull)

    if name == "SUBSTR":
        return substr_fn(vals)

    v := vals[0]
    k := kind(v)

    if name == "ABS":
        if k == 0:
            return ok(VNull)
        if k != 1:
            return error("type error")

        x := ival(v)
        if x < 0:
            return ok(VInt(0 - x))

        return ok(VInt(x))

    if k == 0:
        return ok(VNull)
    if k != 2:
        return error("type error")
    if name == "UPPER":
        return ok(VText(ascii_case(sval(v), true)))
    if name == "LOWER":
        return ok(VText(ascii_case(sval(v), false)))

    return ok(VInt(sval(v).byte_length()))

fn agg_eval(
    name: String,
    distinct: Bool,
    star: Bool,
    args: List[Expr],
    grp: List[List[Value]]
) Result[Value, String]:
    if name == "COUNT" and star:
        return ok(VInt(grp.length()))

    empty: List[List[Value]] = []
    var vals: List[Value] = []

    for r in grp:
        v := try ev(r, empty, args[0])
        if kind(v) != 0:
            vals.append(v)

    var use: List[Value] = []

    for v in vals:
        var dup = false
        if distinct:
            for u in use:
                if same(u, v):
                    dup = true
        if not dup:
            use.append(v.clone())

    if name == "COUNT":
        return ok(VInt(use.length()))

    if name == "SUM":
        var total = 0
        var seen = false

        for v in use:
            if kind(v) != 1:
                return error("type error")

            total += ival(v)
            seen = true

        if not seen:
            return ok(VNull)

        return ok(VInt(total))

    if use.length() == 0:
        return ok(VNull)

    k0 := kind(use[0])
    if k0 != 1 and k0 != 2:
        return error("type error")

    var best = use[0].clone()

    for v in use:
        if kind(v) != k0:
            return error("type error")

        c := cmp_sort(v, best)
        if name == "MIN" and c < 0:
            best = v.clone()
        if name == "MAX" and c > 0:
            best = v.clone()

    return ok(best)

// Evaluates a bound expression. `row` is the current row (or the group's
// representative row); `grp` holds the rows of the current group for aggregates.
fn ev(row: List[Value], grp: List[List[Value]], e: Expr) Result[Value, String]:
    match e:
        Lit(v):
            return ok(v.clone())
        Idx(i, _s):
            return ok(row[i].clone())
        ColRef(_t, _n):
            return ok(VNull)
        Unary(op, x):
            v := try ev(row, grp, x)

            if op == "NOT":
                t := tri(v)
                if t == -1:
                    return error("type error")
                if t == 2:
                    return ok(VNull)

                return ok(VBool(t == 0))

            if kind(v) == 0:
                return ok(VNull)
            if kind(v) != 1:
                return error("type error")

            return ok(VInt(0 - ival(v)))
        Bin(op, l, r):
            if op == "AND":
                return logic(true, row, grp, l, r)
            if op == "OR":
                return logic(false, row, grp, l, r)

            a := try ev(row, grp, l)
            b := try ev(row, grp, r)
            if op == "||":
                return concat_op(a, b)
            if op == "+" or op == "-" or op == "*" or op == "/" or op == "%":
                return arith(op, a, b)

            return compare_op(op, a, b)
        IsNull(x, neg):
            v := try ev(row, grp, x)
            return ok(VBool((kind(v) == 0) != neg))
        Like(x, pat, neg):
            a := try ev(row, grp, x)
            b := try ev(row, grp, pat)
            ka := kind(a)
            kb := kind(b)
            if (ka != 0 and ka != 2) or (kb != 0 and kb != 2):
                return error("type error")
            if ka == 0 or kb == 0:
                return ok(VNull)

            m := like_rec(sval(a).as_bytes(), 0, sval(b).as_bytes(), 0)
            return ok(VBool(m != neg))
        InList(x, items, neg):
            xv := try ev(row, grp, x)
            var found = false
            var sawnull = false

            for it in items:
                v := try ev(row, grp, it)
                kv := kind(v)

                if kind(xv) != 0 and kv != 0:
                    if kv != kind(xv) or kv == 3:
                        return error("type error")

                    if same(xv, v):
                        found = true
                else if kv == 0:
                    sawnull = true

            if kind(xv) == 0:
                return ok(VNull)
            if found:
                return ok(VBool(not neg))
            if sawnull:
                return ok(VNull)

            return ok(VBool(neg))
        Between(x, lo, hi, neg):
            xv := try ev(row, grp, x)
            lv := try ev(row, grp, lo)
            hv := try ev(row, grp, hi)
            ge := try compare_op(">=", xv, lv)
            gt := tri(ge)
            var res = 0

            if gt == 0:
                res = 0
            else:
                le := try compare_op("<=", xv, hv)
                lt := tri(le)

                if gt == 1:
                    res = lt
                else if lt == 0:
                    res = 0
                else:
                    res = 2

            if neg and res != 2:
                res = 1 - res
            return ok(from_tri(res))
        Call(name, args, distinct, star):
            if is_agg(name):
                return agg_eval(name, distinct, star, args, grp)

            var vals: List[Value] = []

            for a in args:
                v := try ev(row, grp, a)
                vals.append(v)

            return scalar_fn(name, vals)

fn has_agg(e: Expr) Bool:
    match e:
        Lit(_v):
            return false
        ColRef(_t, _n):
            return false
        Idx(_i, _s):
            return false
        Unary(_op, x):
            return has_agg(x)
        Bin(_op, l, r):
            return has_agg(l) or has_agg(r)
        IsNull(x, _neg):
            return has_agg(x)
        Like(x, pat, _neg):
            return has_agg(x) or has_agg(pat)
        InList(x, items, _neg):
            if has_agg(x):
                return true

            for it in items:
                if has_agg(it):
                    return true
            return false
        Between(x, lo, hi, _neg):
            return has_agg(x) or has_agg(lo) or has_agg(hi)
        Call(name, args, _d, _s):
            if is_agg(name):
                return true

            for a in args:
                if has_agg(a):
                    return true
            return false

// ---------------------------------------------------------------- binding (name resolution)

fn qual_name(t: String, n: String) String:
    if t == "":
        return n.clone()

    return t + "." + n

fn col_find_names(cols: List[String], n: String) Int:
    var i = 0

    while i < cols.length():
        if cols[i] == n:
            return i

        i += 1

    return -1

fn col_find_defs(cols: List[ColDef], n: String) Int:
    var i = 0

    while i < cols.length():
        if cols[i].name == n:
            return i

        i += 1

    return -1

fn col_names(cols: List[ColDef]) List[String]:
    var out: List[String] = []
    for c in cols:
        out.append(c.name.clone())
    return out

fn resolve(srcs: List[Src], t: String, n: String) Result[Int, String]:
    if t != "":
        for s in srcs:
            if s.alias == t:
                j := col_find_names(s.cols, n)
                if j >= 0:
                    return ok(s.off + j)

                return error("no such column: {qual_name(t, n)}")

        return error("no such column: {qual_name(t, n)}")

    var found = -1
    var count = 0

    for s in srcs:
        j := col_find_names(s.cols, n)

        if j >= 0:
            found = s.off + j
            count += 1

    if count == 0:
        return error("no such column: {n}")
    if count > 1:
        return error("ambiguous column: {n}")

    return ok(found)

fn group_check(
    gidx: List[Int],
    aggq: Bool,
    inagg: Bool,
    i: Int,
    shown: String
) Result[Unit, String]:
    if aggq and not inagg and not gidx.contains(i):
        return error("column {shown} must appear in GROUP BY")

    return ok(unit)

fn bind_call(
    srcs: List[Src],
    gidx: List[Int],
    aggq: Bool,
    allow: Bool,
    inagg: Bool,
    name: String,
    args: List[Expr],
    distinct: Bool,
    star: Bool
) Result[Expr, String]:
    if is_agg(name):
        if not allow or inagg:
            return error("misuse of aggregate")

        if star:
            if name == "COUNT" and not distinct:
                return ok(Call(name.clone(), [], false, true))

            return error("wrong number of arguments to {name}")

        if args.length() != 1:
            return error("wrong number of arguments to {name}")

        b := try bind(srcs, gidx, aggq, false, true, args[0])
        var bl: List[Expr] = []
        bl.append(b)
        return ok(Call(name.clone(), bl, distinct, false))

    var need = 0

    if name == "UPPER" or name == "LOWER" or name == "LENGTH" or name == "ABS":
        need = 1
    else if name == "SUBSTR":
        need = 3
    else if name == "COALESCE":
        need = -1
    else:
        return error("no such function: {name}")

    if star:
        return error("wrong number of arguments to {name}")
    if need >= 0 and args.length() != need:
        return error("wrong number of arguments to {name}")
    if need < 0 and args.length() < 1:
        return error("wrong number of arguments to {name}")

    var bl: List[Expr] = []

    for a in args:
        b := try bind(srcs, gidx, aggq, allow, inagg, a)
        bl.append(b)

    return ok(Call(name.clone(), bl, distinct, false))

// Resolves names, checks functions and aggregate placement, and rewrites
// column references to resolved indexes (Idx).
fn bind(
    srcs: List[Src],
    gidx: List[Int],
    aggq: Bool,
    allow: Bool,
    inagg: Bool,
    e: Expr
) Result[Expr, String]:
    match e:
        Lit(v):
            return ok(Lit(v.clone()))
        ColRef(t, n):
            i := try resolve(srcs, t, n)
            shown := qual_name(t, n)
            try group_check(gidx, aggq, inagg, i, shown)
            return ok(Idx(i, shown))
        Idx(i, shown):
            try group_check(gidx, aggq, inagg, i, shown)
            return ok(Idx(i, shown.clone()))
        Unary(op, x):
            b := try bind(srcs, gidx, aggq, allow, inagg, x)
            return ok(Unary(op.clone(), b))
        Bin(op, l, r):
            bl := try bind(srcs, gidx, aggq, allow, inagg, l)
            br := try bind(srcs, gidx, aggq, allow, inagg, r)
            return ok(Bin(op.clone(), bl, br))
        IsNull(x, neg):
            bx := try bind(srcs, gidx, aggq, allow, inagg, x)
            return ok(IsNull(bx, neg))
        Like(x, pat, neg):
            bx := try bind(srcs, gidx, aggq, allow, inagg, x)
            bp := try bind(srcs, gidx, aggq, allow, inagg, pat)
            return ok(Like(bx, bp, neg))
        InList(x, items, neg):
            bx := try bind(srcs, gidx, aggq, allow, inagg, x)
            var bi: List[Expr] = []

            for it in items:
                b := try bind(srcs, gidx, aggq, allow, inagg, it)
                bi.append(b)

            return ok(InList(bx, bi, neg))
        Between(x, lo, hi, neg):
            bx := try bind(srcs, gidx, aggq, allow, inagg, x)
            bl := try bind(srcs, gidx, aggq, allow, inagg, lo)
            bh := try bind(srcs, gidx, aggq, allow, inagg, hi)
            return ok(Between(bx, bl, bh, neg))
        Call(name, args, distinct, star):
            return bind_call(srcs, gidx, aggq, allow, inagg, name, args, distinct, star)

// ---------------------------------------------------------------- SELECT

fn table_index(db: List[Table], name: String) Int:
    var i = 0

    while i < db.length():
        if db[i].name == name:
            return i

        i += 1

    return -1

fn make_src(db: List[Table], ti: Int, alias: String, off: Int) Src:
    return Src(alias: alias, cols: col_names(db[ti].cols), off: off, tidx: ti)

fn alias_of(tr: TRef) String:
    if tr.alias != "":
        return tr.alias.clone()

    return tr.name.clone()

fn has_alias(srcs: List[Src], a: String) Bool:
    for s in srcs:
        if s.alias == a:
            return true
    return false

fn prefix_srcs(srcs: List[Src], k: Int) List[Src]:
    var out: List[Src] = []
    var i = 0

    while i < k and i < srcs.length():
        out.append(srcs[i].clone())
        i += 1

    return out

fn bare_name(e: Expr) String:
    match e:
        ColRef(t, n):
            if t == "":
                return n.clone()

            return ""
        _:
            return ""

fn colref_name(e: Expr) String:
    match e:
        ColRef(_t, n):
            return n.clone()
        _:
            return ""

fn index_of_name(names: List[String], n: String) Int:
    var i = 0

    while i < names.length():
        if names[i] == n:
            return i

        i += 1

    return -1

fn rep_of(u: List[List[Value]]) List[Value]:
    if u.length() > 0:
        return u[0].clone()

    empty: List[Value] = []
    return empty

fn concat_rows(a: List[Value], b: List[Value]) List[Value]:
    var out: List[Value] = []
    for v in a:
        out.append(v.clone())
    for v in b:
        out.append(v.clone())
    return out

fn exec_select(db: List[Table], q: Query) Result[String, String]:
    // Step 1: tables exist, aliases are unique (FROM first, then joins).
    var srcs: List[Src] = []
    var from_ti = -1
    var join_tis: List[Int] = []
    var off = 0

    if q.has_from:
        from_ti = table_index(db, q.from_t.name)
        if from_ti < 0:
            return error("no such table: {q.from_t.name}")

        srcs.append(make_src(db, from_ti, alias_of(q.from_t), off))
        off += db[from_ti].cols.length()

        for j in q.joins:
            tj := table_index(db, j.tref.name)
            if tj < 0:
                return error("no such table: {j.tref.name}")

            aj := alias_of(j.tref)
            if has_alias(srcs, aj):
                return error("duplicate alias: {aj}")

            srcs.append(make_src(db, tj, aj, off))
            join_tis.append(tj)
            off += db[tj].cols.length()

    no_g: List[Int] = []
    no_rows: List[List[Value]] = []

    // Step 2: JOIN conditions.
    var bons: List[Expr] = []
    var jn = 0

    while jn < q.joins.length():
        pre := prefix_srcs(srcs, jn + 2)
        bc := try bind(pre, no_g, false, false, false, q.joins[jn].cond)
        bons.append(bc)
        jn += 1

    // Step 3: stars expand to resolved column references.
    var outs: List[Expr] = []
    var names: List[String] = []

    for it in q.items:
        if it.kind == 0:
            var nm = "?column?"

            if it.alias != "":
                nm = it.alias.clone()
            else if colref_name(it.e) != "":
                nm = colref_name(it.e)

            names.append(nm)
            outs.append(it.e.clone())
        else if it.kind == 1:
            for s in srcs:
                var j = 0

                while j < s.cols.length():
                    names.append(s.cols[j].clone())
                    outs.append(Idx(s.off + j, s.cols[j].clone()))
                    j += 1
        else:
            var found = -1
            var si = 0

            while si < srcs.length():
                if srcs[si].alias == it.tbl:
                    found = si
                si += 1

            if found < 0:
                return error("no such table: {it.tbl}")

            s := srcs[found]
            var j = 0

            while j < s.cols.length():
                names.append(s.cols[j].clone())
                outs.append(Idx(s.off + j, s.cols[j].clone()))
                j += 1

    // Step 4: GROUP BY columns.
    var gidx: List[Int] = []

    for g in q.group:
        gi := try resolve(srcs, g.tbl, g.name)
        gidx.append(gi)

    // Aggregated query?
    var aggq = q.group.length() > 0 or q.has_having
    for e in outs:
        if has_agg(e):
            aggq = true
    for o in q.order:
        if has_agg(o.e):
            aggq = true

    // Step 5: WHERE.
    var bwhere: Expr = Lit(VNull)
    if q.has_where:
        bwhere = try bind(srcs, no_g, false, false, false, q.where_e)

    // Step 6: select list.
    var bouts: List[Expr] = []

    for e in outs:
        b := try bind(srcs, gidx, aggq, true, false, e)
        bouts.append(b)

    // Step 7: HAVING.
    var bhav: Expr = Lit(VNull)
    if q.has_having:
        bhav = try bind(srcs, gidx, aggq, true, false, q.having_e)

    // Step 8: ORDER BY (position, output name, or expression).
    var ord_pos: List[Int] = []
    var ord_e: List[Expr] = []
    var ord_desc: List[Bool] = []
    nout := bouts.length()

    for o in q.order:
        ord_desc.append(o.desc)

        if o.lit:
            if o.n < 1 or o.n > nout:
                return error("bad ORDER BY position")

            ord_pos.append(o.n - 1)
            ord_e.append(Lit(VNull))
        else if bare_name(o.e) != "" and names.contains(bare_name(o.e)):
            ord_pos.append(index_of_name(names, bare_name(o.e)))
            ord_e.append(Lit(VNull))
        else:
            b := try bind(srcs, gidx, aggq, true, false, o.e)
            ord_pos.append(-1)
            ord_e.append(b)

    // Evaluation: joined rows.
    var rows: List[List[Value]] = []

    if q.has_from:
        for r in db[from_ti].rows:
            rows.append(r.clone())
    else:
        one: List[Value] = []
        rows.append(one)

    jn = 0

    while jn < q.joins.length():
        tj := join_tis[jn]
        width := db[tj].cols.length()
        var next: List[List[Value]] = []

        for r in rows:
            var matched = false

            for ir in db[tj].rows:
                comb := concat_rows(r, ir)
                cv := try ev(comb, no_rows, bons[jn])
                ct := tri(cv)
                if ct == -1:
                    return error("type error")

                if ct == 1:
                    matched = true
                    next.append(comb)

            if q.joins[jn].is_left and not matched:
                var padded = r.clone()
                var k = 0

                while k < width:
                    padded.append(VNull)
                    k += 1

                next.append(padded)

        rows = next
        jn += 1

    // WHERE filter.
    if q.has_where:
        var kept: List[List[Value]] = []

        for r in rows:
            wv := try ev(r, no_rows, bwhere)
            wt := tri(wv)
            if wt == -1:
                return error("type error")

            if wt == 1:
                kept.append(r.clone())

        rows = kept

    // Units: groups for aggregated queries, single rows otherwise.
    var units: List[List[List[Value]]] = []

    if aggq:
        if gidx.length() == 0:
            units.append(rows.clone())
        else:
            var gkeys: List[List[Value]] = []

            for r in rows:
                var key: List[Value] = []
                for gi in gidx:
                    key.append(r[gi].clone())

                var found = -1
                var g = 0

                while g < gkeys.length():
                    if same_row(gkeys[g], key):
                        found = g
                        break

                    g += 1

                if found < 0:
                    gkeys.append(key)

                    var one: List[List[Value]] = []
                    one.append(r.clone())
                    units.append(one)
                else:
                    units[found].append(r.clone())
    else:
        for r in rows:
            var one: List[List[Value]] = []
            one.append(r.clone())
            units.append(one)

    // HAVING filter.
    if q.has_having:
        var kept_u: List[List[List[Value]]] = []

        for u in units:
            hv := try ev(rep_of(u), u, bhav)
            ht := tri(hv)
            if ht == -1:
                return error("type error")

            if ht == 1:
                kept_u.append(u.clone())

        units = kept_u

    // Output values and ORDER BY keys.
    var outrows: List[OutRow] = []

    for u in units:
        rep := rep_of(u)
        var vals: List[Value] = []

        for e in bouts:
            v := try ev(rep, u, e)
            vals.append(v)

        var keys: List[Value] = []
        var oi = 0

        while oi < ord_pos.length():
            if ord_pos[oi] >= 0:
                keys.append(vals[ord_pos[oi]].clone())
            else:
                kv := try ev(rep, u, ord_e[oi])
                keys.append(kv)

            oi += 1

        outrows.append(OutRow(vals: vals, keys: keys))

    // DISTINCT (keeps first occurrence).
    if q.distinct:
        var uniq: List[OutRow] = []

        for o in outrows:
            var dup = false

            for u2 in uniq:
                if same_row(u2.vals, o.vals):
                    dup = true
                    break

            if not dup:
                uniq.append(OutRow(vals: o.vals.clone(), keys: o.keys.clone()))

        outrows = uniq

    // ORDER BY (stable).
    if ord_desc.length() > 0:
        outrows.sort(fn(x: OutRow, y: OutRow) Int: cmp_out(x, y, ord_desc))

    // OFFSET / LIMIT.
    var first = q.offset_n
    if first > outrows.length():
        first = outrows.length()

    var last = outrows.length()
    if q.has_limit:
        if q.limit_n < last - first:
            last = first + q.limit_n

    var out = names.join("|") + "\n"
    var i = first

    while i < last:
        var cells: List[String] = []
        for v in outrows[i].vals:
            cells.append(vstr(v))
        out = out + cells.join("|") + "\n"
        i += 1

    out = out + "({last - first} rows)\n"
    return ok(out)

// ---------------------------------------------------------------- DDL / DML

fn check_coldefs(cols: List[ColDef]) Result[Unit, String]:
    var npk = 0
    var i = 0

    while i < cols.length():
        for j in 0..i:
            if cols[j].name == cols[i].name:
                return error("duplicate column: {cols[i].name}")

        if cols[i].pk:
            npk += 1
            if npk > 1:
                return error("multiple primary keys")

        i += 1

    return ok(unit)

fn pk_index(cols: List[ColDef]) Int:
    var i = 0

    while i < cols.length():
        if cols[i].pk:
            return i

        i += 1

    return -1

// Per-column constraints, checked in declaration order.
fn check_row(cols: List[ColDef], row: List[Value]) Result[Unit, String]:
    var c = 0

    while c < cols.length():
        v := row[c]

        if kind(v) == 0:
            if cols[c].notnull:
                return error("NOT NULL constraint failed: {cols[c].name}")
        else if not type_ok(cols[c].ty, v):
            return error("type mismatch in column {cols[c].name}")

        c += 1

    return ok(unit)

fn first_dup(rows: List[List[Value]], p: Int) Result[Unit, String]:
    var j = 0

    while j < rows.length():
        var i = 0

        while i < j:
            if same(rows[i][p], rows[j][p]):
                return error("duplicate primary key: {vstr(rows[j][p])}")

            i += 1

        j += 1

    return ok(unit)

fn insert_rows(
    tbl: Table,
    has_cols: Bool,
    cols: List[String],
    rows: List[List[Expr]]
) Result[Changed, String]:
    ncols := tbl.cols.length()
    var pos: List[Int] = []

    if has_cols:
        for cn in cols:
            j := col_find_defs(tbl.cols, cn)
            if j < 0:
                return error("no such column: {cn}")
            if pos.contains(j):
                return error("duplicate column: {cn}")

            pos.append(j)
    else:
        var j = 0

        while j < ncols:
            pos.append(j)
            j += 1

    no_srcs: List[Src] = []
    no_g: List[Int] = []
    no_rows: List[List[Value]] = []
    no_row: List[Value] = []
    var all: List[List[Value]] = []
    for r in tbl.rows:
        all.append(r.clone())

    base := all.length()

    for r in rows:
        if r.length() != pos.length():
            return error("wrong number of values")

        var vals: List[Value] = []
        var j = 0

        while j < ncols:
            vals.append(VNull)
            j += 1

        var k = 0

        while k < r.length():
            b := try bind(no_srcs, no_g, false, false, false, r[k])
            v := try ev(no_row, no_rows, b)
            vals[pos[k]] = v
            k += 1

        try check_row(tbl.cols, vals)
        all.append(vals)

    p := pk_index(tbl.cols)
    if p >= 0:
        try first_dup(all, p)

    added := all.length() - base
    return ok(Changed(rows: all, count: added))

fn update_rows(
    tbl: Table,
    sets: List[SetItem],
    has_where: Bool,
    wh: Expr
) Result[Changed, String]:
    srcs: List[Src] = [
        Src(alias: tbl.name.clone(), cols: col_names(tbl.cols), off: 0, tidx: 0)
    ]
    no_g: List[Int] = []
    no_rows: List[List[Value]] = []
    var setpos: List[Int] = []

    for s in sets:
        j := col_find_defs(tbl.cols, s.name)
        if j < 0:
            return error("no such column: {s.name}")

        setpos.append(j)

    var bexprs: List[Expr] = []

    for s in sets:
        b := try bind(srcs, no_g, false, false, false, s.e)
        bexprs.append(b)

    var bwhere: Expr = Lit(VNull)
    if has_where:
        bwhere = try bind(srcs, no_g, false, false, false, wh)

    var out: List[List[Value]] = []
    var count = 0

    for row in tbl.rows:
        var hit = true

        if has_where:
            wv := try ev(row, no_rows, bwhere)
            wt := tri(wv)
            if wt == -1:
                return error("type error")

            hit = wt == 1

        if hit:
            var newrow = row.clone()
            var k = 0

            while k < setpos.length():
                v := try ev(row, no_rows, bexprs[k])
                newrow[setpos[k]] = v
                k += 1

            try check_row(tbl.cols, newrow)
            out.append(newrow)
            count += 1
        else:
            out.append(row.clone())

    p := pk_index(tbl.cols)
    if p >= 0:
        try first_dup(out, p)
    return ok(Changed(rows: out, count: count))

fn delete_rows(tbl: Table, has_where: Bool, wh: Expr) Result[Changed, String]:
    srcs: List[Src] = [
        Src(alias: tbl.name.clone(), cols: col_names(tbl.cols), off: 0, tidx: 0)
    ]
    no_g: List[Int] = []
    no_rows: List[List[Value]] = []
    var bwhere: Expr = Lit(VNull)
    if has_where:
        bwhere = try bind(srcs, no_g, false, false, false, wh)

    var out: List[List[Value]] = []
    var count = 0

    for row in tbl.rows:
        var del = true

        if has_where:
            wv := try ev(row, no_rows, bwhere)
            wt := tri(wv)
            if wt == -1:
                return error("type error")

            del = wt == 1

        if del:
            count += 1
        else:
            out.append(row.clone())

    return ok(Changed(rows: out, count: count))

fn run_stmt(var db: List[Table], st: Stmt) Result[String, String]:
    match st:
        SCreate(name, cols):
            if table_index(db, name) >= 0:
                return error("table {name} already exists")

            try check_coldefs(cols)
            db.append(Table(name: name.clone(), cols: cols.clone(), rows: []))
            return ok("ok\n")
        SDrop(name):
            ti := table_index(db, name)
            if ti < 0:
                return error("no such table: {name}")

            db.remove(ti)
            return ok("ok\n")
        SInsert(name, has_cols, cols, rows):
            ti := table_index(db, name)
            if ti < 0:
                return error("no such table: {name}")

            ch := try insert_rows(db[ti].clone(), has_cols, cols, rows)
            db[ti].rows = ch.rows
            return ok("inserted {ch.count}\n")
        SUpdate(name, sets, has_where, where_e):
            ti := table_index(db, name)
            if ti < 0:
                return error("no such table: {name}")

            ch := try update_rows(db[ti].clone(), sets, has_where, where_e)
            db[ti].rows = ch.rows
            return ok("updated {ch.count}\n")
        SDelete(name, has_where, where_e):
            ti := table_index(db, name)
            if ti < 0:
                return error("no such table: {name}")

            ch := try delete_rows(db[ti].clone(), has_where, where_e)
            db[ti].rows = ch.rows
            return ok("deleted {ch.count}\n")
        SSelect(q):
            return exec_select(db, q)

fn run_piece_r(var db: List[Table], cs: List[String]) Result[String, String]:
    toks := try lex(cs)
    if toks.length() == 1:
        return ok("")

    var p = Parser(toks: toks, pos: 0)
    st := try parse_statement(var p)
    return run_stmt(var db, st)

fn run_piece(var db: List[Table], cs: List[String]) String:
    r := run_piece_r(var db, cs)
    if r.is_error():
        return "error: {r.err()}\n"

    return r.get().clone()

export fn main() Int:
    raw := read_all(stdin()).get()
    var text = ""
    if t := raw.decode_utf8():
        text = t.clone()

    cs := text.split_after("")
    var db: List[Table] = []
    var out = ""
    for piece in split_statements(cs):
        out = out + run_piece(var db, piece)
    stdout().write(out).get()
    return 0

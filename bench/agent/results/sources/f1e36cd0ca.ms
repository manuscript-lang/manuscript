import stdin, stdout, read_all from "@std/io.ms"
import Bytes from "@std/bytes.ms"

# ---------- values and errors ----------

type Val:
    case VNull
    case VInt(v: Int)
    case VText(s: String)
    case VBool(b: Bool)

type Expr:
    case Lit(v: Val)
    case Col(qual: String, name: String)
    case Un(op: String, e: Expr)
    case Bin(op: String, l: Expr, r: Expr)
    case Like(e: Expr, pat: Expr, neg: Bool)
    case IsNull(e: Expr, neg: Bool)
    case InList(e: Expr, items: List[Expr], neg: Bool)
    case Between(e: Expr, lo: Expr, hi: Expr, neg: Bool)
    case Call(name: String, args: List[Expr], distinct: Bool, star: Bool)

type SqlErr:
    msg: String

impl Error for SqlErr:
    fn message() String:
        return self.msg.clone()

# ---------- schema and statements ----------

type Tok:
    kind: Int
    text: String
    num: Int

type PS:
    toks: List[Tok]
    pos: Int

type Span:
    s: Int
    e: Int

type ColDef:
    name: String
    is_int: Bool
    notnull: Bool
    pk: Bool

type Tab:
    name: String
    cols: List[ColDef]
    rows: List[List[Val]]

type Db:
    tables: List[Tab]

type Scol:
    qual: String
    name: String

type TRef:
    name: String
    al: String

type SelItem:
    case Star
    case TStar(al: String)
    case Item(e: Expr, al: String)

type SelQ:
    distinct: Bool
    items: List[SelItem]
    tables: List[TRef]
    lefts: List[Bool]
    ons: List[Expr]
    wh: Expr
    has_wh: Bool
    grp: List[Expr]
    hav: Expr
    has_hav: Bool
    order: List[Expr]
    ordesc: List[Bool]
    has_limit: Bool
    lim: Int
    off: Int

type Stmt:
    case Create(name: String, cols: List[ColDef])
    case Drop(name: String)
    case Insert(name: String, has_cols: Bool, cols: List[String], rows: List[List[Expr]])
    case Update(name: String, set_cols: List[String], set_exprs: List[Expr], wh: Expr, has_wh: Bool)
    case Delete(name: String, wh: Expr, has_wh: Bool)
    case Select(q: SelQ)

# ---------- lexer ----------

fn is_kw(w: String) Bool:
    return ["SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET", "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN", "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"].contains(w)

fn byte_at(src: Bytes, i: Int) Int:
    if i < 0 or i >= src.length():
        return -1
    return src.get(i).to_int()

fn is_alpha(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_digit(c: Int) Bool:
    return c >= 48 and c <= 57

fn is_alnum(c: Int) Bool:
    return is_alpha(c) or is_digit(c)

fn op_tok(t: String) Tok:
    return Tok(kind: 4, text: t, num: 0)

# Splits the script at top-level ';' (outside strings and comments).
fn split_stmts(src: Bytes) List[Span]:
    var spans = List[Span]()
    let n = src.length()
    var start = 0
    var i = 0
    while i < n:
        let c = byte_at(src, i)
        if c == 39:
            i += 1
            while i < n:
                if byte_at(src, i) == 39:
                    if byte_at(src, i + 1) == 39:
                        i += 2
                    else:
                        break
                else:
                    i += 1
            i += 1
        else if c == 45 and byte_at(src, i + 1) == 45:
            while i < n and byte_at(src, i) != 10:
                i += 1
        else if c == 59:
            spans.append(Span(s: start, e: i))
            i += 1
            start = i
        else:
            i += 1
    spans.append(Span(s: start, e: n))
    return spans

fn lex(src: Bytes, s: Int, e: Int) Result[List[Tok], SqlErr]:
    var toks = List[Tok]()
    var i = s
    while i < e:
        let c = byte_at(src, i)
        if c == 32 or c == 9 or c == 13 or c == 10:
            i += 1
        else if c == 45 and byte_at(src, i + 1) == 45:
            while i < e and byte_at(src, i) != 10:
                i += 1
        else if is_alpha(c):
            let st = i
            while i < e and is_alnum(byte_at(src, i)):
                i += 1
            let word0 = src.decode_utf8_range(st, i).get("")
            let word = word0.clone()
            let up = word.upper()
            if is_kw(up):
                toks.append(Tok(kind: 1, text: up, num: 0))
            else:
                toks.append(Tok(kind: 0, text: word, num: 0))
        else if is_digit(c):
            var v = 0
            var bad = false
            while i < e and is_digit(byte_at(src, i)):
                let d = byte_at(src, i) - 48
                if v > 922337203685477580 or (v == 922337203685477580 and d > 7):
                    bad = true
                else:
                    v = v * 10 + d
                i += 1
            if bad:
                return error(SqlErr(msg: "syntax error"))
            toks.append(Tok(kind: 2, text: "", num: v))
        else if c == 39:
            i += 1
            let st = i
            while true:
                if i >= e:
                    return error(SqlErr(msg: "syntax error"))
                if byte_at(src, i) == 39:
                    if i + 1 < e and byte_at(src, i + 1) == 39:
                        i += 2
                    else:
                        break
                else:
                    i += 1
            let raw0 = src.decode_utf8_range(st, i).get("")
            let raw = raw0.clone()
            toks.append(Tok(kind: 3, text: raw.replace("''", "'"), num: 0))
            i += 1
        else:
            let c2 = if i + 1 < e: byte_at(src, i + 1) else: -1
            if (c == 60 and c2 == 62) or (c == 33 and c2 == 61):
                toks.append(op_tok("<>"))
                i += 2
            else if (c == 60 and c2 == 61) or (c == 62 and c2 == 61):
                toks.append(op_tok(src.decode_utf8_range(i, i + 2).get("")))
                i += 2
            else if c == 124 and c2 == 124:
                toks.append(op_tok("||"))
                i += 2
            else:
                let ch = src.decode_utf8_range(i, i + 1).get("")
                if ["=", "<", ">", "+", "-", "*", "/", "%", "(", ")", ",", "."].contains(ch):
                    toks.append(op_tok(ch))
                    i += 1
                else:
                    return error(SqlErr(msg: "syntax error"))
    return ok(toks)

# ---------- parser ----------

fn syn() SqlErr:
    return SqlErr(msg: "syntax error")

fn at_end(p: PS) Bool:
    return p.pos >= p.toks.length()

fn at_kw(p: PS, kw: String) Bool:
    if p.pos >= p.toks.length():
        return false
    return p.toks[p.pos].kind == 1 and p.toks[p.pos].text == kw

fn kw_at(p: PS, off: Int, kw: String) Bool:
    let j = p.pos + off
    if j >= p.toks.length():
        return false
    return p.toks[j].kind == 1 and p.toks[j].text == kw

fn at_op(p: PS, op: String) Bool:
    if p.pos >= p.toks.length():
        return false
    return p.toks[p.pos].kind == 4 and p.toks[p.pos].text == op

fn op_at(p: PS, off: Int, op: String) Bool:
    let j = p.pos + off
    if j >= p.toks.length():
        return false
    return p.toks[j].kind == 4 and p.toks[j].text == op

fn at_ident(p: PS) Bool:
    if p.pos >= p.toks.length():
        return false
    return p.toks[p.pos].kind == 0

fn expect_kw(var p: PS, kw: String) Result[Unit, SqlErr]:
    if not at_kw(p, kw):
        return error(syn())
    p.pos += 1
    return ok(unit)

fn expect_op(var p: PS, op: String) Result[Unit, SqlErr]:
    if not at_op(p, op):
        return error(syn())
    p.pos += 1
    return ok(unit)

fn expect_ident(var p: PS) Result[String, SqlErr]:
    if not at_ident(p):
        return error(syn())
    let t = p.toks[p.pos].text.clone()
    p.pos += 1
    return ok(t)

fn expect_int(var p: PS) Result[Int, SqlErr]:
    if p.pos >= p.toks.length() or p.toks[p.pos].kind != 2:
        return error(syn())
    let n = p.toks[p.pos].num
    p.pos += 1
    return ok(n)

fn parse_expr(var p: PS) Result[Expr, SqlErr]:
    return parse_or(var p)

fn parse_or(var p: PS) Result[Expr, SqlErr]:
    var left = try parse_and(var p)
    while at_kw(p, "OR"):
        p.pos += 1
        let right = try parse_and(var p)
        left = Bin(op: "OR", l: left, r: right)
    return ok(left)

fn parse_and(var p: PS) Result[Expr, SqlErr]:
    var left = try parse_not(var p)
    while at_kw(p, "AND"):
        p.pos += 1
        let right = try parse_not(var p)
        left = Bin(op: "AND", l: left, r: right)
    return ok(left)

fn parse_not(var p: PS) Result[Expr, SqlErr]:
    if at_kw(p, "NOT"):
        p.pos += 1
        let x = try parse_not(var p)
        return ok(Un(op: "NOT", e: x))
    return parse_cmp(var p)

fn parse_cmp(var p: PS) Result[Expr, SqlErr]:
    let left = try parse_add(var p)
    if at_op(p, "=") or at_op(p, "<>") or at_op(p, "<") or at_op(p, "<=") or at_op(p, ">") or at_op(p, ">="):
        let op = p.toks[p.pos].text.clone()
        p.pos += 1
        let right = try parse_add(var p)
        return ok(Bin(op: op, l: left, r: right))
    if at_kw(p, "IS"):
        p.pos += 1
        var neg = false
        if at_kw(p, "NOT"):
            neg = true
            p.pos += 1
        try expect_kw(var p, "NULL")
        return ok(IsNull(e: left, neg: neg))
    var neg2 = false
    if at_kw(p, "NOT") and (kw_at(p, 1, "LIKE") or kw_at(p, 1, "IN") or kw_at(p, 1, "BETWEEN")):
        neg2 = true
        p.pos += 1
    if at_kw(p, "LIKE"):
        p.pos += 1
        let pat = try parse_add(var p)
        return ok(Like(e: left, pat: pat, neg: neg2))
    if at_kw(p, "IN"):
        p.pos += 1
        try expect_op(var p, "(")
        var items = List[Expr]()
        let first = try parse_expr(var p)
        items.append(first)
        while at_op(p, ","):
            p.pos += 1
            let more = try parse_expr(var p)
            items.append(more)
        try expect_op(var p, ")")
        return ok(InList(e: left, items: items, neg: neg2))
    if at_kw(p, "BETWEEN"):
        p.pos += 1
        let lo = try parse_add(var p)
        try expect_kw(var p, "AND")
        let hi = try parse_add(var p)
        return ok(Between(e: left, lo: lo, hi: hi, neg: neg2))
    return ok(left)

fn parse_add(var p: PS) Result[Expr, SqlErr]:
    var left = try parse_mul(var p)
    while at_op(p, "+") or at_op(p, "-") or at_op(p, "||"):
        let op = p.toks[p.pos].text.clone()
        p.pos += 1
        let right = try parse_mul(var p)
        left = Bin(op: op, l: left, r: right)
    return ok(left)

fn parse_mul(var p: PS) Result[Expr, SqlErr]:
    var left = try parse_unary(var p)
    while at_op(p, "*") or at_op(p, "/") or at_op(p, "%"):
        let op = p.toks[p.pos].text.clone()
        p.pos += 1
        let right = try parse_unary(var p)
        left = Bin(op: op, l: left, r: right)
    return ok(left)

fn parse_unary(var p: PS) Result[Expr, SqlErr]:
    if at_op(p, "-"):
        p.pos += 1
        let x = try parse_unary(var p)
        return ok(Un(op: "-", e: x))
    return parse_primary(var p)

fn parse_primary(var p: PS) Result[Expr, SqlErr]:
    if at_end(p):
        return error(syn())
    let k = p.toks[p.pos].kind
    if k == 2:
        let n = p.toks[p.pos].num
        p.pos += 1
        return ok(Lit(v: VInt(v: n)))
    if k == 3:
        let s = p.toks[p.pos].text.clone()
        p.pos += 1
        return ok(Lit(v: VText(s: s)))
    if at_kw(p, "NULL"):
        p.pos += 1
        return ok(Lit(v: VNull))
    if at_op(p, "("):
        p.pos += 1
        let e = try parse_expr(var p)
        try expect_op(var p, ")")
        return ok(e)
    if at_ident(p):
        let name = p.toks[p.pos].text.clone()
        p.pos += 1
        if at_op(p, "("):
            p.pos += 1
            var distinct = false
            var star = false
            var args = List[Expr]()
            if at_op(p, "*"):
                star = true
                p.pos += 1
            else if not at_op(p, ")"):
                if at_kw(p, "DISTINCT"):
                    distinct = true
                    p.pos += 1
                let a0 = try parse_expr(var p)
                args.append(a0)
                while at_op(p, ","):
                    p.pos += 1
                    let an = try parse_expr(var p)
                    args.append(an)
            try expect_op(var p, ")")
            let up = name.upper()
            if star and up != "COUNT":
                return error(syn())
            return ok(Call(name: up, args: args, distinct: distinct, star: star))
        if at_op(p, "."):
            p.pos += 1
            let col = try expect_ident(var p)
            return ok(Col(qual: name, name: col))
        return ok(Col(qual: "", name: name))
    return error(syn())

fn parse_colref(var p: PS) Result[Expr, SqlErr]:
    let name = try expect_ident(var p)
    if at_op(p, "."):
        p.pos += 1
        let col = try expect_ident(var p)
        return ok(Col(qual: name, name: col))
    return ok(Col(qual: "", name: name))

fn parse_tref(var p: PS) Result[TRef, SqlErr]:
    let name = try expect_ident(var p)
    var al = name.clone()
    if at_kw(p, "AS"):
        p.pos += 1
        al = try expect_ident(var p)
    else if at_ident(p):
        al = try expect_ident(var p)
    return ok(TRef(name: name, al: al))

fn parse_item(var p: PS) Result[SelItem, SqlErr]:
    if at_op(p, "*"):
        p.pos += 1
        return ok(Star)
    if at_ident(p) and op_at(p, 1, ".") and op_at(p, 2, "*"):
        let a = p.toks[p.pos].text.clone()
        p.pos += 3
        return ok(TStar(al: a))
    let e = try parse_expr(var p)
    if at_kw(p, "AS"):
        p.pos += 1
        let a2 = try expect_ident(var p)
        return ok(Item(e: e, al: a2))
    return ok(Item(e: e, al: ""))

fn parse_row(var p: PS) Result[List[Expr], SqlErr]:
    try expect_op(var p, "(")
    var vals = List[Expr]()
    let first = try parse_expr(var p)
    vals.append(first)
    while at_op(p, ","):
        p.pos += 1
        let more = try parse_expr(var p)
        vals.append(more)
    try expect_op(var p, ")")
    return ok(vals)

fn parse_select(var p: PS) Result[SelQ, SqlErr]:
    try expect_kw(var p, "SELECT")
    var distinct = false
    if at_kw(p, "DISTINCT"):
        distinct = true
        p.pos += 1
    var items = List[SelItem]()
    let i0 = try parse_item(var p)
    items.append(i0)
    while at_op(p, ","):
        p.pos += 1
        let im = try parse_item(var p)
        items.append(im)
    var tables = List[TRef]()
    var lefts = List[Bool]()
    var ons = List[Expr]()
    if at_kw(p, "FROM"):
        p.pos += 1
        let t0 = try parse_tref(var p)
        tables.append(t0)
        while at_kw(p, "JOIN") or at_kw(p, "INNER") or at_kw(p, "LEFT"):
            var is_left = false
            if at_kw(p, "LEFT"):
                is_left = true
                p.pos += 1
            else if at_kw(p, "INNER"):
                p.pos += 1
            try expect_kw(var p, "JOIN")
            let tj = try parse_tref(var p)
            tables.append(tj)
            try expect_kw(var p, "ON")
            let on = try parse_expr(var p)
            ons.append(on)
            lefts.append(is_left)
    var has_wh = false
    var wh = Lit(v: VNull)
    if at_kw(p, "WHERE"):
        p.pos += 1
        has_wh = true
        wh = try parse_expr(var p)
    var grp = List[Expr]()
    if at_kw(p, "GROUP"):
        p.pos += 1
        try expect_kw(var p, "BY")
        let g0 = try parse_colref(var p)
        grp.append(g0)
        while at_op(p, ","):
            p.pos += 1
            let gn = try parse_colref(var p)
            grp.append(gn)
    var has_hav = false
    var hav = Lit(v: VNull)
    if at_kw(p, "HAVING"):
        p.pos += 1
        has_hav = true
        hav = try parse_expr(var p)
    var order = List[Expr]()
    var ordesc = List[Bool]()
    if at_kw(p, "ORDER"):
        p.pos += 1
        try expect_kw(var p, "BY")
        var more = true
        while more:
            let oe = try parse_expr(var p)
            var d = false
            if at_kw(p, "ASC"):
                p.pos += 1
            else if at_kw(p, "DESC"):
                d = true
                p.pos += 1
            order.append(oe)
            ordesc.append(d)
            if at_op(p, ","):
                p.pos += 1
            else:
                more = false
    var has_limit = false
    var lim = 0
    var off = 0
    if at_kw(p, "LIMIT"):
        p.pos += 1
        lim = try expect_int(var p)
        has_limit = true
        if at_kw(p, "OFFSET"):
            p.pos += 1
            off = try expect_int(var p)
    let q = SelQ(distinct: distinct, items: items, tables: tables, lefts: lefts, ons: ons, wh: wh, has_wh: has_wh, grp: grp, hav: hav, has_hav: has_hav, order: order, ordesc: ordesc, has_limit: has_limit, lim: lim, off: off)
    return ok(q)

fn parse_create(var p: PS) Result[Stmt, SqlErr]:
    try expect_kw(var p, "CREATE")
    try expect_kw(var p, "TABLE")
    let name = try expect_ident(var p)
    try expect_op(var p, "(")
    var cols = List[ColDef]()
    var more = true
    while more:
        let cname = try expect_ident(var p)
        let tword = try expect_ident(var p)
        let tu = tword.upper()
        var is_int = false
        if tu == "INT":
            is_int = true
        else if tu != "TEXT":
            return error(syn())
        var notnull = false
        var pk = false
        var going = true
        while going:
            if at_kw(p, "PRIMARY"):
                p.pos += 1
                try expect_kw(var p, "KEY")
                pk = true
                notnull = true
            else if at_kw(p, "NOT"):
                p.pos += 1
                try expect_kw(var p, "NULL")
                notnull = true
            else:
                going = false
        cols.append(ColDef(name: cname, is_int: is_int, notnull: notnull, pk: pk))
        if at_op(p, ","):
            p.pos += 1
        else:
            more = false
    try expect_op(var p, ")")
    return ok(Create(name: name, cols: cols))

fn parse_insert(var p: PS) Result[Stmt, SqlErr]:
    try expect_kw(var p, "INSERT")
    try expect_kw(var p, "INTO")
    let name = try expect_ident(var p)
    var has_cols = false
    var cols = List[String]()
    if at_op(p, "("):
        p.pos += 1
        has_cols = true
        let c0 = try expect_ident(var p)
        cols.append(c0)
        while at_op(p, ","):
            p.pos += 1
            let cn = try expect_ident(var p)
            cols.append(cn)
        try expect_op(var p, ")")
    try expect_kw(var p, "VALUES")
    var rows = List[List[Expr]]()
    let r0 = try parse_row(var p)
    rows.append(r0)
    while at_op(p, ","):
        p.pos += 1
        let rn = try parse_row(var p)
        rows.append(rn)
    return ok(Insert(name: name, has_cols: has_cols, cols: cols, rows: rows))

fn parse_update(var p: PS) Result[Stmt, SqlErr]:
    try expect_kw(var p, "UPDATE")
    let name = try expect_ident(var p)
    try expect_kw(var p, "SET")
    var set_cols = List[String]()
    var set_exprs = List[Expr]()
    var more = true
    while more:
        let c = try expect_ident(var p)
        try expect_op(var p, "=")
        let e = try parse_expr(var p)
        set_cols.append(c)
        set_exprs.append(e)
        if at_op(p, ","):
            p.pos += 1
        else:
            more = false
    var has_wh = false
    var wh = Lit(v: VNull)
    if at_kw(p, "WHERE"):
        p.pos += 1
        has_wh = true
        wh = try parse_expr(var p)
    return ok(Update(name: name, set_cols: set_cols, set_exprs: set_exprs, wh: wh, has_wh: has_wh))

fn parse_delete(var p: PS) Result[Stmt, SqlErr]:
    try expect_kw(var p, "DELETE")
    try expect_kw(var p, "FROM")
    let name = try expect_ident(var p)
    var has_wh = false
    var wh = Lit(v: VNull)
    if at_kw(p, "WHERE"):
        p.pos += 1
        has_wh = true
        wh = try parse_expr(var p)
    return ok(Delete(name: name, wh: wh, has_wh: has_wh))

fn parse_drop(var p: PS) Result[Stmt, SqlErr]:
    try expect_kw(var p, "DROP")
    try expect_kw(var p, "TABLE")
    let name = try expect_ident(var p)
    return ok(Drop(name: name))

fn parse_stmt(var p: PS) Result[Stmt, SqlErr]:
    if at_kw(p, "CREATE"):
        return parse_create(var p)
    if at_kw(p, "DROP"):
        return parse_drop(var p)
    if at_kw(p, "INSERT"):
        return parse_insert(var p)
    if at_kw(p, "UPDATE"):
        return parse_update(var p)
    if at_kw(p, "DELETE"):
        return parse_delete(var p)
    if at_kw(p, "SELECT"):
        let q = try parse_select(var p)
        return ok(Select(q: q))
    return error(syn())

# ---------- value helpers ----------

fn val_clone(v: Val) Val:
    match v:
        VNull:
            return VNull
        VInt(n):
            return VInt(v: n)
        VText(s):
            let c = s.clone()
            return VText(s: c)
        VBool(b):
            return VBool(b: b)

fn kind_of(v: Val) Int:
    match v:
        VNull:
            return 0
        VBool(_b):
            return 1
        VInt(_n):
            return 2
        VText(_s):
            return 3

fn as_int(v: Val) Int:
    match v:
        VInt(n):
            return n
        _:
            return 0

fn as_bool(v: Val) Bool:
    match v:
        VBool(b):
            return b
        _:
            return false

fn as_text(v: Val) String:
    match v:
        VText(s):
            let c = s.clone()
            return c
        _:
            return ""

fn val_text(v: Val) String:
    match v:
        VNull:
            return "NULL"
        VInt(n):
            return "{n}"
        VText(s):
            let c = s.clone()
            return c
        VBool(b):
            if b:
                return "true"
            return "false"

fn val_enc(v: Val) String:
    match v:
        VNull:
            return "N;"
        VInt(n):
            return "I{n};"
        VText(s):
            return "T{s.byte_length()};{s}"
        VBool(b):
            if b:
                return "B1;"
            return "B0;"

fn cmp_int(x: Int, y: Int) Int:
    if x < y:
        return -1
    if x > y:
        return 1
    return 0

fn bool_int(b: Bool) Int:
    if b:
        return 1
    return 0

# Total order used for sorting: NULL < BOOL < INT < TEXT.
fn val_cmp(a: Val, b: Val) Int:
    let ka = kind_of(a)
    let kb = kind_of(b)
    if ka != kb:
        if ka < kb:
            return -1
        return 1
    if ka == 2:
        return cmp_int(as_int(a), as_int(b))
    if ka == 3:
        let sa = as_text(a)
        let sb = as_text(b)
        if sa < sb:
            return -1
        if sa > sb:
            return 1
        return 0
    if ka == 1:
        return cmp_int(bool_int(as_bool(a)), bool_int(as_bool(b)))
    return 0

# SQL comparison of two non-NULL values: only INT/INT and TEXT/TEXT are allowed.
fn sql_cmp(a: Val, b: Val) Result[Int, SqlErr]:
    let ka = kind_of(a)
    let kb = kind_of(b)
    if ka == kb and (ka == 2 or ka == 3):
        return ok(val_cmp(a, b))
    return error(SqlErr(msg: "type error"))

# 0 = false, 1 = true, 2 = NULL, -1 = not a boolean.
fn tri(v: Val) Int:
    let k = kind_of(v)
    if k == 0:
        return 2
    if k == 1:
        return bool_int(as_bool(v))
    return -1

fn tri_val(t: Int) Val:
    if t == 1:
        return VBool(b: true)
    if t == 0:
        return VBool(b: false)
    return VNull

fn tri_not(t: Int) Int:
    if t == 2:
        return 2
    return 1 - t

fn truthy(v: Val) Result[Bool, SqlErr]:
    let t = tri(v)
    if t == -1:
        return error(SqlErr(msg: "type error"))
    return ok(t == 1)

fn clone_row(r: List[Val]) List[Val]:
    var out = List[Val]()
    for i in 0..r.length():
        out.append(val_clone(r[i]))
    return out

fn concat_rows(a: List[Val], b: List[Val]) List[Val]:
    var out = List[Val]()
    for i in 0..a.length():
        out.append(val_clone(a[i]))
    for i in 0..b.length():
        out.append(val_clone(b[i]))
    return out

fn null_row(n: Int) List[Val]:
    var out = List[Val]()
    for i in 0..n:
        out.append(VNull)
    return out

# ---------- scalar functions ----------

fn to_bytes_list(s: String) List[Int]:
    var out = List[Int]()
    let bs = s.to_bytes()
    for i in 0..bs.length():
        out.append(bs.get(i).to_int())
    return out

fn like_match(s: List[Int], si: Int, p: List[Int], pj: Int) Bool:
    if pj == p.length():
        return si == s.length()
    if p[pj] == 37:
        var k = si
        while k <= s.length():
            if like_match(s, k, p, pj + 1):
                return true
            k += 1
        return false
    if si >= s.length():
        return false
    if p[pj] == 95 or p[pj] == s[si]:
        return like_match(s, si + 1, p, pj + 1)
    return false

fn substr(t: String, start: Int, len: Int) String:
    if len <= 0:
        return ""
    let bs = t.to_bytes()
    let n = bs.length()
    let from = start - 1
    var lo = from
    if lo < 0:
        lo = 0
    var hi = from + len
    if hi > n:
        hi = n
    if lo >= hi:
        return ""
    return bs.decode_utf8_range(lo, hi).get("")

fn ascii_case(t: String, up: Bool) String:
    var out = List[String]()
    for ch in t.chars():
        let code = ch.scalar_at(0)
        if up and code >= 97 and code <= 122:
            out.append(ch.upper())
        else if (not up) and code >= 65 and code <= 90:
            out.append(ch.lower())
        else:
            out.append(ch.clone())
    return out.join("")

fn is_scalar_name(n: String) Bool:
    return n == "UPPER" or n == "LOWER" or n == "LENGTH" or n == "ABS" or n == "SUBSTR" or n == "COALESCE"

fn is_agg_name(n: String) Bool:
    return n == "COUNT" or n == "SUM" or n == "MIN" or n == "MAX"

fn eval_scalar(name: String, vals: List[Val]) Result[Val, SqlErr]:
    if name == "COALESCE":
        for k in 0..vals.length():
            if kind_of(vals[k]) != 0:
                return ok(val_clone(vals[k]))
        return ok(VNull)
    if name == "SUBSTR":
        let t = kind_of(vals[0])
        let s = kind_of(vals[1])
        let l = kind_of(vals[2])
        if (t != 0 and t != 3) or (s != 0 and s != 2) or (l != 0 and l != 2):
            return error(SqlErr(msg: "type error"))
        if t == 0 or s == 0 or l == 0:
            return ok(VNull)
        return ok(VText(s: substr(as_text(vals[0]), as_int(vals[1]), as_int(vals[2]))))
    let k = kind_of(vals[0])
    if k == 0:
        return ok(VNull)
    if name == "ABS":
        if k != 2:
            return error(SqlErr(msg: "type error"))
        let n = as_int(vals[0])
        if n < 0:
            return ok(VInt(v: 0 - n))
        return ok(VInt(v: n))
    if k != 3:
        return error(SqlErr(msg: "type error"))
    if name == "LENGTH":
        return ok(VInt(v: as_text(vals[0]).byte_length()))
    if name == "UPPER":
        return ok(VText(s: ascii_case(as_text(vals[0]), true)))
    return ok(VText(s: ascii_case(as_text(vals[0]), false)))

# ---------- expression evaluation ----------

fn find_col(sc: List[Scol], qual: String, name: String) Int:
    for i in 0..sc.length():
        if sc[i].name == name and (qual == "" or sc[i].qual == qual):
            return i
    return -1

fn count_col(sc: List[Scol], qual: String, name: String) Int:
    var n = 0
    for i in 0..sc.length():
        if sc[i].name == name and (qual == "" or sc[i].qual == qual):
            n += 1
    return n

fn disp(qual: String, name: String) String:
    if qual == "":
        return name
    return "{qual}.{name}"

fn resolve_col(sc: List[Scol], qual: String, name: String) Result[Int, SqlErr]:
    let n = count_col(sc, qual, name)
    if n == 0:
        return error(SqlErr(msg: "no such column: {disp(qual, name)}"))
    if n > 1:
        return error(SqlErr(msg: "ambiguous column: {name}"))
    return ok(find_col(sc, qual, name))

fn eval_agg(name: String, args: List[Expr], distinct: Bool, star: Bool, sc: List[Scol], rows: List[List[Val]], grp: List[Int]) Result[Val, SqlErr]:
    if star:
        return ok(VInt(v: grp.length()))
    var vals = List[Val]()
    var seen = Set[String]()
    for k in 0..grp.length():
        let v = try eval(args[0], sc, rows[grp[k]], rows, List[Int]())
        if kind_of(v) == 0:
            continue
        if distinct:
            let key = val_enc(v)
            if seen.contains(key):
                continue
            seen.add(key)
        vals.append(v)
    if name == "COUNT":
        return ok(VInt(v: vals.length()))
    if name == "SUM":
        if vals.length() == 0:
            return ok(VNull)
        var total = 0
        for k in 0..vals.length():
            if kind_of(vals[k]) != 2:
                return error(SqlErr(msg: "type error"))
            total += as_int(vals[k])
        return ok(VInt(v: total))
    if vals.length() == 0:
        return ok(VNull)
    let k0 = kind_of(vals[0])
    if k0 != 2 and k0 != 3:
        return error(SqlErr(msg: "type error"))
    var best = 0
    for k in 0..vals.length():
        if kind_of(vals[k]) != k0:
            return error(SqlErr(msg: "type error"))
        let c = val_cmp(vals[k], vals[best])
        if name == "MIN" and c < 0:
            best = k
        if name == "MAX" and c > 0:
            best = k
    return ok(val_clone(vals[best]))

fn eval(e: Expr, sc: List[Scol], row: List[Val], rows: List[List[Val]], grp: List[Int]) Result[Val, SqlErr]:
    match e:
        Lit(v):
            return ok(val_clone(v))
        Col(qual, name):
            let idx = find_col(sc, qual, name)
            if idx < 0 or idx >= row.length():
                return ok(VNull)
            return ok(val_clone(row[idx]))
        Un(op, x):
            let v = try eval(x, sc, row, rows, grp)
            if op == "NOT":
                let t = tri(v)
                if t == -1:
                    return error(SqlErr(msg: "type error"))
                return ok(tri_val(tri_not(t)))
            if kind_of(v) == 0:
                return ok(VNull)
            if kind_of(v) != 2:
                return error(SqlErr(msg: "type error"))
            return ok(VInt(v: 0 - as_int(v)))
        Like(x, pat, neg):
            let a = try eval(x, sc, row, rows, grp)
            let b = try eval(pat, sc, row, rows, grp)
            if kind_of(a) == 0 or kind_of(b) == 0:
                return ok(VNull)
            if kind_of(a) != 3 or kind_of(b) != 3:
                return error(SqlErr(msg: "type error"))
            let m = like_match(to_bytes_list(as_text(a)), 0, to_bytes_list(as_text(b)), 0)
            if neg:
                return ok(VBool(b: not m))
            return ok(VBool(b: m))
        IsNull(x, neg):
            let v = try eval(x, sc, row, rows, grp)
            let isnull = kind_of(v) == 0
            if neg:
                return ok(VBool(b: not isnull))
            return ok(VBool(b: isnull))
        InList(x, items, neg):
            let v = try eval(x, sc, row, rows, grp)
            var vals = List[Val]()
            for k in 0..items.length():
                let w = try eval(items[k], sc, row, rows, grp)
                vals.append(w)
            if kind_of(v) == 0:
                return ok(VNull)
            var sawnull = false
            var found = false
            for k in 0..vals.length():
                if kind_of(vals[k]) == 0:
                    sawnull = true
                else:
                    let c = try sql_cmp(v, vals[k])
                    if c == 0:
                        found = true
                        break
            var res = 2
            if found:
                res = 1
            else if not sawnull:
                res = 0
            if neg:
                res = tri_not(res)
            return ok(tri_val(res))
        Between(x, lo, hi, neg):
            let v = try eval(x, sc, row, rows, grp)
            let a = try eval(lo, sc, row, rows, grp)
            let b = try eval(hi, sc, row, rows, grp)
            var g = 2
            if kind_of(v) != 0 and kind_of(a) != 0:
                let c1 = try sql_cmp(v, a)
                g = 0
                if c1 >= 0:
                    g = 1
            var res = g
            if g != 0:
                var h = 2
                if kind_of(v) != 0 and kind_of(b) != 0:
                    let c2 = try sql_cmp(v, b)
                    h = 0
                    if c2 <= 0:
                        h = 1
                if h == 0:
                    res = 0
                else if g == 2 or h == 2:
                    res = 2
                else:
                    res = 1
            if neg:
                res = tri_not(res)
            return ok(tri_val(res))
        Bin(op, l, r):
            if op == "AND":
                let a = try eval(l, sc, row, rows, grp)
                let ta = tri(a)
                if ta == -1:
                    return error(SqlErr(msg: "type error"))
                if ta == 0:
                    return ok(VBool(b: false))
                let b = try eval(r, sc, row, rows, grp)
                let tb = tri(b)
                if tb == -1:
                    return error(SqlErr(msg: "type error"))
                if ta == 1:
                    return ok(tri_val(tb))
                if tb == 0:
                    return ok(VBool(b: false))
                return ok(VNull)
            if op == "OR":
                let a = try eval(l, sc, row, rows, grp)
                let ta = tri(a)
                if ta == -1:
                    return error(SqlErr(msg: "type error"))
                if ta == 1:
                    return ok(VBool(b: true))
                let b = try eval(r, sc, row, rows, grp)
                let tb = tri(b)
                if tb == -1:
                    return error(SqlErr(msg: "type error"))
                if ta == 0:
                    return ok(tri_val(tb))
                if tb == 1:
                    return ok(VBool(b: true))
                return ok(VNull)
            let a = try eval(l, sc, row, rows, grp)
            let b = try eval(r, sc, row, rows, grp)
            if op == "||":
                if kind_of(a) == 0 or kind_of(b) == 0:
                    return ok(VNull)
                if kind_of(a) != 3 or kind_of(b) != 3:
                    return error(SqlErr(msg: "type error"))
                return ok(VText(s: as_text(a) + as_text(b)))
            if op == "+" or op == "-" or op == "*" or op == "/" or op == "%":
                if kind_of(a) == 0 or kind_of(b) == 0:
                    return ok(VNull)
                if kind_of(a) != 2 or kind_of(b) != 2:
                    return error(SqlErr(msg: "type error"))
                let x = as_int(a)
                let y = as_int(b)
                if op == "+":
                    return ok(VInt(v: x + y))
                if op == "-":
                    return ok(VInt(v: x - y))
                if op == "*":
                    return ok(VInt(v: x * y))
                if y == 0:
                    return error(SqlErr(msg: "division by zero"))
                if op == "/":
                    return ok(VInt(v: x / y))
                return ok(VInt(v: x % y))
            if kind_of(a) == 0 or kind_of(b) == 0:
                return ok(VNull)
            let c = try sql_cmp(a, b)
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
            return ok(VBool(b: res))
        Call(name, args, distinct, star):
            if is_agg_name(name):
                return eval_agg(name, args, distinct, star, sc, rows, grp)
            var vals = List[Val]()
            for k in 0..args.length():
                let v = try eval(args[k], sc, row, rows, grp)
                vals.append(v)
            return eval_scalar(name, vals)

# Evaluates in the context of a group (or a single row when the group is a one-row list).
fn eval_g(e: Expr, sc: List[Scol], cur: List[List[Val]], grp: List[Int]) Result[Val, SqlErr]:
    if grp.length() > 0:
        return eval(e, sc, cur[grp[0]], cur, grp)
    return eval(e, sc, List[Val](), cur, grp)

# ---------- static name resolution ----------

fn has_agg(e: Expr) Bool:
    match e:
        Lit(_v):
            return false
        Col(_q, _n):
            return false
        Un(_op, x):
            return has_agg(x)
        Bin(_op, l, r):
            return has_agg(l) or has_agg(r)
        Like(x, pat, _neg):
            return has_agg(x) or has_agg(pat)
        IsNull(x, _neg):
            return has_agg(x)
        InList(x, items, _neg):
            if has_agg(x):
                return true
            for k in 0..items.length():
                if has_agg(items[k]):
                    return true
            return false
        Between(x, lo, hi, _neg):
            return has_agg(x) or has_agg(lo) or has_agg(hi)
        Call(name, args, _d, _s):
            if is_agg_name(name):
                return true
            for k in 0..args.length():
                if has_agg(args[k]):
                    return true
            return false

fn item_has_agg(it: SelItem) Bool:
    match it:
        Star:
            return false
        TStar(_al):
            return false
        Item(e, _al):
            return has_agg(e)

fn resolve(e: Expr, sc: List[Scol], allow_agg: Bool, need_group: Bool, gidx: List[Int], inside: Bool) Result[Unit, SqlErr]:
    match e:
        Lit(_v):
            return ok(unit)
        Col(qual, name):
            let idx = try resolve_col(sc, qual.clone(), name.clone())
            if need_group and not inside:
                if not gidx.contains(idx):
                    return error(SqlErr(msg: "column {disp(qual, name)} must appear in GROUP BY"))
            return ok(unit)
        Un(_op, x):
            try resolve(x, sc, allow_agg, need_group, gidx, inside)
            return ok(unit)
        Bin(_op, l, r):
            try resolve(l, sc, allow_agg, need_group, gidx, inside)
            try resolve(r, sc, allow_agg, need_group, gidx, inside)
            return ok(unit)
        Like(x, pat, _neg):
            try resolve(x, sc, allow_agg, need_group, gidx, inside)
            try resolve(pat, sc, allow_agg, need_group, gidx, inside)
            return ok(unit)
        IsNull(x, _neg):
            try resolve(x, sc, allow_agg, need_group, gidx, inside)
            return ok(unit)
        InList(x, items, _neg):
            try resolve(x, sc, allow_agg, need_group, gidx, inside)
            for k in 0..items.length():
                try resolve(items[k].clone(), sc, allow_agg, need_group, gidx, inside)
            return ok(unit)
        Between(x, lo, hi, _neg):
            try resolve(x, sc, allow_agg, need_group, gidx, inside)
            try resolve(lo, sc, allow_agg, need_group, gidx, inside)
            try resolve(hi, sc, allow_agg, need_group, gidx, inside)
            return ok(unit)
        Call(name, args, distinct, star):
            if is_agg_name(name):
                if (not allow_agg) or inside:
                    return error(SqlErr(msg: "misuse of aggregate"))
                if star:
                    if distinct:
                        return error(SqlErr(msg: "wrong number of arguments to {name}"))
                    return ok(unit)
                if args.length() != 1:
                    return error(SqlErr(msg: "wrong number of arguments to {name}"))
                try resolve(args[0].clone(), sc, allow_agg, need_group, gidx, true)
                return ok(unit)
            if not is_scalar_name(name):
                return error(SqlErr(msg: "no such function: {name}"))
            let n = args.length()
            var arity_ok = n == 1
            if name == "SUBSTR":
                arity_ok = n == 3
            if name == "COALESCE":
                arity_ok = n >= 1
            if not arity_ok:
                return error(SqlErr(msg: "wrong number of arguments to {name}"))
            for k in 0..n:
                try resolve(args[k].clone(), sc, allow_agg, need_group, gidx, inside)
            return ok(unit)

# ---------- schema helpers ----------

fn find_table(db: Db, name: String) Int:
    for i in 0..db.tables.length():
        if db.tables[i].name == name:
            return i
    return -1

fn find_coldef(cols: List[ColDef], name: String) Int:
    for i in 0..cols.length():
        if cols[i].name == name:
            return i
    return -1

fn tab_scope(cols: List[ColDef], qual: String) List[Scol]:
    var sc = List[Scol]()
    for j in 0..cols.length():
        sc.append(Scol(qual: qual.clone(), name: cols[j].name.clone()))
    return sc

# Scope of the first `upto` FROM/JOIN tables.
fn scope_of(db: Db, q: SelQ, upto: Int) List[Scol]:
    var sc = List[Scol]()
    for k in 0..upto:
        let ti = find_table(db, q.tables[k].name)
        for j in 0..db.tables[ti].cols.length():
            sc.append(Scol(qual: q.tables[k].al.clone(), name: db.tables[ti].cols[j].name.clone()))
    return sc

fn check_row(cols: List[ColDef], row: List[Val]) Result[Unit, SqlErr]:
    for j in 0..cols.length():
        let k = kind_of(row[j])
        if k == 0:
            if cols[j].notnull:
                return error(SqlErr(msg: "NOT NULL constraint failed: {cols[j].name}"))
        else if cols[j].is_int:
            if k != 2:
                return error(SqlErr(msg: "type mismatch in column {cols[j].name}"))
        else:
            if k != 3:
                return error(SqlErr(msg: "type mismatch in column {cols[j].name}"))
    return ok(unit)

fn check_pk(cols: List[ColDef], rows: List[List[Val]]) Result[Unit, SqlErr]:
    var pk = -1
    for j in 0..cols.length():
        if cols[j].pk:
            pk = j
    if pk < 0:
        return ok(unit)
    var seen = Set[String]()
    for r in 0..rows.length():
        let key = val_enc(rows[r][pk])
        if seen.contains(key):
            return error(SqlErr(msg: "duplicate primary key: {val_text(rows[r][pk])}"))
        seen.add(key)
    return ok(unit)

# ---------- statements ----------

fn exec_create(var db: Db, name: String, cols: List[ColDef]) Result[String, SqlErr]:
    if find_table(db, name) >= 0:
        return error(SqlErr(msg: "table {name} already exists"))
    var npk = 0
    for j in 0..cols.length():
        for i in 0..j:
            if cols[i].name == cols[j].name:
                return error(SqlErr(msg: "duplicate column: {cols[j].name}"))
        if cols[j].pk:
            npk += 1
    if npk > 1:
        return error(SqlErr(msg: "multiple primary keys"))
    var copy = List[ColDef]()
    for j in 0..cols.length():
        let nn = cols[j].notnull or cols[j].pk
        copy.append(ColDef(name: cols[j].name.clone(), is_int: cols[j].is_int, notnull: nn, pk: cols[j].pk))
    db.tables.append(Tab(name: name.clone(), cols: copy, rows: List[List[Val]]()))
    return ok("ok\n")

fn exec_drop(var db: Db, name: String) Result[String, SqlErr]:
    let ti = find_table(db, name)
    if ti < 0:
        return error(SqlErr(msg: "no such table: {name}"))
    db.tables.remove(ti)
    return ok("ok\n")

fn exec_insert(var db: Db, name: String, has_cols: Bool, cols: List[String], rows: List[List[Expr]]) Result[String, SqlErr]:
    let ti = find_table(db, name)
    if ti < 0:
        return error(SqlErr(msg: "no such table: {name}"))
    let nt = db.tables[ti].cols.length()
    var colmap = List[Int]()
    for j in 0..nt:
        colmap.append(-1)
    var want = nt
    if has_cols:
        want = cols.length()
        for k in 0..cols.length():
            let c = find_coldef(db.tables[ti].cols, cols[k])
            if c < 0:
                return error(SqlErr(msg: "no such column: {cols[k]}"))
            if colmap[c] >= 0:
                return error(SqlErr(msg: "duplicate column: {cols[k]}"))
            colmap[c] = k
    else:
        for j in 0..nt:
            colmap[j] = j
    var combined = List[List[Val]]()
    for r in 0..db.tables[ti].rows.length():
        combined.append(clone_row(db.tables[ti].rows[r]))
    var added = 0
    for r in 0..rows.length():
        if rows[r].length() != want:
            return error(SqlErr(msg: "wrong number of values"))
        var vals = List[Val]()
        for k in 0..rows[r].length():
            try resolve(rows[r][k].clone(), List[Scol](), false, false, List[Int](), false)
            let v = try eval(rows[r][k].clone(), List[Scol](), List[Val](), List[List[Val]](), List[Int]())
            vals.append(v)
        var full = List[Val]()
        for j in 0..nt:
            if colmap[j] < 0:
                full.append(VNull)
            else:
                full.append(val_clone(vals[colmap[j]]))
        try check_row(db.tables[ti].cols, full)
        combined.append(full)
        added += 1
    try check_pk(db.tables[ti].cols, combined)
    db.tables[ti].rows = combined
    return ok("inserted {added}\n")

fn exec_update(var db: Db, name: String, set_cols: List[String], set_exprs: List[Expr], wh: Expr, has_wh: Bool) Result[String, SqlErr]:
    let ti = find_table(db, name)
    if ti < 0:
        return error(SqlErr(msg: "no such table: {name}"))
    let sc = tab_scope(db.tables[ti].cols, name)
    var setidx = List[Int]()
    for k in 0..set_cols.length():
        let c = find_col(sc, "", set_cols[k])
        if c < 0:
            return error(SqlErr(msg: "no such column: {set_cols[k]}"))
        setidx.append(c)
    for k in 0..set_exprs.length():
        try resolve(set_exprs[k].clone(), sc, false, false, List[Int](), false)
    if has_wh:
        try resolve(wh.clone(), sc, false, false, List[Int](), false)
    var newrows = List[List[Val]]()
    var count = 0
    let nrows = db.tables[ti].rows.length()
    for r in 0..nrows:
        var matched = true
        if has_wh:
            let t = try eval(wh.clone(), sc, db.tables[ti].rows[r], db.tables[ti].rows, List[Int]())
            matched = try truthy(t)
        if matched:
            var vals = List[Val]()
            for k in 0..set_exprs.length():
                let v = try eval(set_exprs[k].clone(), sc, db.tables[ti].rows[r], db.tables[ti].rows, List[Int]())
                vals.append(v)
            var nr = clone_row(db.tables[ti].rows[r])
            for k in 0..setidx.length():
                nr[setidx[k]] = val_clone(vals[k])
            try check_row(db.tables[ti].cols, nr)
            newrows.append(nr)
            count += 1
        else:
            newrows.append(clone_row(db.tables[ti].rows[r]))
    try check_pk(db.tables[ti].cols, newrows)
    db.tables[ti].rows = newrows
    return ok("updated {count}\n")

fn exec_delete(var db: Db, name: String, wh: Expr, has_wh: Bool) Result[String, SqlErr]:
    let ti = find_table(db, name)
    if ti < 0:
        return error(SqlErr(msg: "no such table: {name}"))
    let sc = tab_scope(db.tables[ti].cols, name)
    if has_wh:
        try resolve(wh.clone(), sc, false, false, List[Int](), false)
    var newrows = List[List[Val]]()
    var count = 0
    let nrows = db.tables[ti].rows.length()
    for r in 0..nrows:
        var matched = true
        if has_wh:
            let t = try eval(wh.clone(), sc, db.tables[ti].rows[r], db.tables[ti].rows, List[Int]())
            matched = try truthy(t)
        if matched:
            count += 1
        else:
            newrows.append(clone_row(db.tables[ti].rows[r]))
    db.tables[ti].rows = newrows
    return ok("deleted {count}\n")

fn name_pos(names: List[String], nm: String) Int:
    for i in 0..names.length():
        if names[i] == nm:
            return i
    return -1

fn colname_of(e: Expr) String:
    match e:
        Col(_q, n):
            return n.clone()
        _:
            return "?column?"

fn cmp_keys(a: List[Val], b: List[Val], desc: List[Bool]) Int:
    for k in 0..a.length():
        var c = val_cmp(a[k], b[k])
        if desc[k]:
            c = 0 - c
        if c != 0:
            return c
    return 0

fn colidx(e: Expr, sc: List[Scol]) Result[Int, SqlErr]:
    match e:
        Col(qual, name):
            return resolve_col(sc, qual, name)
        _:
            return error(syn())

fn join_step(cur: List[List[Val]], trows: List[List[Val]], psc: List[Scol], on: Expr, is_left: Bool, ncols: Int) Result[List[List[Val]], SqlErr]:
    var nxt = List[List[Val]]()
    for a in 0..cur.length():
        var matched = false
        for b in 0..trows.length():
            let tv = try eval(on.clone(), psc, concat_rows(cur[a], trows[b]), List[List[Val]](), List[Int]())
            let keep_it = try truthy(tv)
            if keep_it:
                nxt.append(concat_rows(cur[a], trows[b]))
                matched = true
        if (not matched) and is_left:
            nxt.append(concat_rows(cur[a], null_row(ncols)))
    return ok(nxt)

fn exec_select(db: Db, q: SelQ) Result[String, SqlErr]:
    let nt = q.tables.length()
    # 1. tables exist and aliases are unique
    for k in 0..nt:
        if find_table(db, q.tables[k].name) < 0:
            return error(SqlErr(msg: "no such table: {q.tables[k].name}"))
        for j in 0..k:
            if q.tables[j].al == q.tables[k].al:
                return error(SqlErr(msg: "duplicate alias: {q.tables[k].al}"))
    # 2. join conditions, stars, GROUP BY, WHERE, items, HAVING, ORDER BY
    for k in 1..nt:
        let psc = scope_of(db, q, k + 1)
        try resolve(q.ons[k - 1].clone(), psc, false, false, List[Int](), false)
    for k in 0..q.items.length():
        match q.items[k]:
            Star:
                continue
            TStar(al):
                var found = false
                for j in 0..nt:
                    if q.tables[j].al == al:
                        found = true
                if not found:
                    return error(SqlErr(msg: "no such table: {al}"))
            Item(_e, _al):
                continue
    let sc = scope_of(db, q, nt)
    var agg_any = false
    for k in 0..q.items.length():
        if item_has_agg(q.items[k]):
            agg_any = true
    var ord_agg = false
    for k in 0..q.order.length():
        if has_agg(q.order[k]):
            ord_agg = true
    let is_agg = q.grp.length() > 0 or q.has_hav or agg_any or ord_agg
    var gidx = List[Int]()
    for k in 0..q.grp.length():
        let gi = try colidx(q.grp[k].clone(), sc)
        gidx.append(gi)
    if q.has_wh:
        try resolve(q.wh.clone(), sc, false, false, List[Int](), false)
    for k in 0..q.items.length():
        match q.items[k]:
            Star:
                for c in 0..sc.length():
                    if is_agg and not gidx.contains(c):
                        return error(SqlErr(msg: "column {sc[c].name} must appear in GROUP BY"))
            TStar(al):
                for c in 0..sc.length():
                    if sc[c].qual == al and is_agg and not gidx.contains(c):
                        return error(SqlErr(msg: "column {sc[c].name} must appear in GROUP BY"))
            Item(e, _al):
                try resolve(e.clone(), sc, true, is_agg, gidx, false)
    if q.has_hav:
        try resolve(q.hav.clone(), sc, true, is_agg, gidx, false)
    var names = List[String]()
    for k in 0..q.items.length():
        match q.items[k]:
            Star:
                for c in 0..sc.length():
                    names.append(sc[c].name.clone())
            TStar(al):
                for c in 0..sc.length():
                    if sc[c].qual == al:
                        names.append(sc[c].name.clone())
            Item(e, al):
                if al != "":
                    names.append(al.clone())
                else:
                    names.append(colname_of(e))
    var ord_out = List[Int]()
    for k in 0..q.order.length():
        match q.order[k]:
            Lit(v):
                if kind_of(v) == 2:
                    let pos = as_int(v)
                    if pos < 1 or pos > names.length():
                        return error(SqlErr(msg: "bad ORDER BY position"))
                    ord_out.append(pos - 1)
                else:
                    try resolve(q.order[k].clone(), sc, true, is_agg, gidx, false)
                    ord_out.append(-1)
            Col(qu, nm):
                let ni = name_pos(names, nm)
                if qu == "" and ni >= 0:
                    ord_out.append(ni)
                else:
                    try resolve(q.order[k].clone(), sc, true, is_agg, gidx, false)
                    ord_out.append(-1)
            _:
                try resolve(q.order[k].clone(), sc, true, is_agg, gidx, false)
                ord_out.append(-1)

    # 3. build rows: FROM and JOINs
    var cur = List[List[Val]]()
    if nt == 0:
        cur.append(List[Val]())
    else:
        let ti0 = find_table(db, q.tables[0].name)
        for r in 0..db.tables[ti0].rows.length():
            cur.append(clone_row(db.tables[ti0].rows[r]))
    for k in 1..nt:
        let ti = find_table(db, q.tables[k].name)
        let psc = scope_of(db, q, k + 1)
        let ncols = db.tables[ti].cols.length()
        let stepped = join_step(cur, db.tables[ti].rows, psc, q.ons[k - 1].clone(), q.lefts[k - 1], ncols)
        if stepped.is_error():
            return error(stepped.err())
        cur = stepped.get()

    # 4. WHERE
    var keep = List[Int]()
    for r in 0..cur.length():
        if q.has_wh:
            let wv = try eval(q.wh.clone(), sc, cur[r], cur, List[Int]())
            let pass_it = try truthy(wv)
            if pass_it:
                keep.append(r)
        else:
            keep.append(r)

    # 5. groups
    var groups = List[List[Int]]()
    if is_agg:
        if q.grp.length() > 0:
            var gmap = Map[String, Int]()
            for kk in 0..keep.length():
                let r = keep[kk]
                var key = ""
                for c in 0..gidx.length():
                    key = key + val_enc(cur[r][gidx[c]])
                let g = gmap.get_or(key, -1)
                if g >= 0:
                    groups[g].append(r)
                else:
                    gmap.add(key, groups.length())
                    var ng = List[Int]()
                    ng.append(r)
                    groups.append(ng)
        else:
            var g0 = List[Int]()
            for kk in 0..keep.length():
                g0.append(keep[kk])
            groups.append(g0)
    else:
        for kk in 0..keep.length():
            var ng = List[Int]()
            ng.append(keep[kk])
            groups.append(ng)

    var gsel = List[Int]()
    for g in 0..groups.length():
        var pass_g = true
        if q.has_hav:
            let hv = try eval_g(q.hav.clone(), sc, cur, groups[g])
            pass_g = try truthy(hv)
        if pass_g:
            gsel.append(g)

    # 6. select list
    var outs = List[List[Val]]()
    var outg = List[Int]()
    for gi in 0..gsel.length():
        let g = gsel[gi]
        var rv = List[Val]()
        for k in 0..q.items.length():
            match q.items[k]:
                Star:
                    for c in 0..sc.length():
                        rv.append(val_clone(cur[groups[g][0]][c]))
                TStar(al):
                    for c in 0..sc.length():
                        if sc[c].qual == al:
                            rv.append(val_clone(cur[groups[g][0]][c]))
                Item(e, _al):
                    let v = try eval_g(e, sc, cur, groups[g])
                    rv.append(v)
        outs.append(rv)
        outg.append(g)

    # 7. DISTINCT, then ORDER BY keys
    var dist_outs = List[List[Val]]()
    var dist_g = List[Int]()
    var seen_rows = Set[String]()
    for o in 0..outs.length():
        var keep_o = true
        if q.distinct:
            var key = ""
            for c in 0..outs[o].length():
                key = key + val_enc(outs[o][c])
            if seen_rows.contains(key):
                keep_o = false
            else:
                seen_rows.add(key)
        if keep_o:
            dist_outs.append(clone_row(outs[o]))
            dist_g.append(outg[o])
    let nord = q.order.length()
    var keys = List[List[Val]]()
    for o in 0..dist_outs.length():
        var kr = List[Val]()
        for k in 0..nord:
            if ord_out[k] >= 0:
                kr.append(val_clone(dist_outs[o][ord_out[k]]))
            else:
                let kv = try eval_g(q.order[k].clone(), sc, cur, groups[dist_g[o]])
                kr.append(kv)
        keys.append(kr)

    var idx = List[Int]()
    for o in 0..dist_outs.length():
        idx.append(o)
    if nord > 0:
        idx.sort(fn(a: Int, b: Int) Int: cmp_keys(keys[a], keys[b], q.ordesc))

    # 8. OFFSET and LIMIT
    let total = idx.length()
    let off0 = q.off
    var start = off0
    if start > total:
        start = total
    var stop = total
    if q.has_limit:
        if start + q.lim < total:
            stop = start + q.lim
    var out = names.join("|") + "\n"
    for i in start..stop:
        let o = idx[i]
        var cells = List[String]()
        for c in 0..dist_outs[o].length():
            cells.append(val_text(dist_outs[o][c]))
        out = out + cells.join("|") + "\n"
    out = out + "({stop - start} rows)\n"
    return ok(out)

fn exec(var db: Db, st: Stmt) Result[String, SqlErr]:
    match st:
        Create(name, cols):
            return exec_create(var db, name, cols)
        Drop(name):
            return exec_drop(var db, name)
        Insert(name, has_cols, cols, rows):
            return exec_insert(var db, name, has_cols, cols, rows)
        Update(name, set_cols, set_exprs, wh, has_wh):
            return exec_update(var db, name, set_cols, set_exprs, wh, has_wh)
        Delete(name, wh, has_wh):
            return exec_delete(var db, name, wh, has_wh)
        Select(q):
            return exec_select(db, q)

fn run_stmt(var db: Db, src: Bytes, s: Int, e: Int) Result[String, SqlErr]:
    let toks = try lex(src, s, e)
    if toks.length() == 0:
        return ok("")
    var p = PS(toks: toks, pos: 0)
    let st = try parse_stmt(var p)
    if not at_end(p):
        return error(syn())
    return exec(var db, st)

export fn main() Int:
    let src = read_all(stdin()).get()
    let spans = split_stmts(src)
    var db = Db(tables: List[Tab]())
    for k in 0..spans.length():
        let r = run_stmt(var db, src, spans[k].s, spans[k].e)
        if r.is_error():
            stdout().write("error: {r.err().msg}\n").get()
        else:
            stdout().write(r.get()).get()
    return 0

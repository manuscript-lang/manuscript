import stdout, stdin, read_all from "@std/io.ms"
import from_scalars from "@std/string.ms"

# ---------- values and errors ----------

type Value:
    case VNull
    case VInt(v: Int)
    case VText(s: String)
    case VBool(b: Bool)

type SqlError:
    msg: String

impl Error for SqlError:
    fn message() String: self.msg.clone()

fn sql_error(msg: String) SqlError:
    return SqlError(msg: msg)

fn syntax_error() SqlError:
    return SqlError(msg: "syntax error")

fn type_error() SqlError:
    return SqlError(msg: "type error")

# 0 NULL, 1 INT, 2 BOOL, 3 TEXT
fn rank(v: Value) Int:
    match v:
        VNull:
            return 0
        VInt(_n):
            return 1
        VBool(_b):
            return 2
        VText(_s):
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

fn text_of(v: Value) String:
    match v:
        VText(s):
            return s.clone()
        _:
            return ""

fn show(v: Value) String:
    match v:
        VNull:
            return "NULL"
        VInt(n):
            return n.to_string()
        VText(s):
            return s.clone()
        VBool(b):
            if b:
                return "true"

            return "false"

fn key_of(v: Value) String:
    match v:
        VNull:
            return "N"
        VInt(n):
            return "I{n};"
        VText(s):
            return "T{s.byte_length()}:{s}"
        VBool(b):
            if b:
                return "B1"

            return "B0"

fn row_key(vals: List[Value]) String:
    var k = ""
    for v in vals:
        k = k + key_of(v)
    return k

fn cmp_int(x: Int, y: Int) Int:
    if x < y:
        return -1
    if x > y:
        return 1

    return 0

fn cmp_text(x: String, y: String) Int:
    if x < y:
        return -1
    if x > y:
        return 1

    return 0

fn bool_int(v: Value) Int:
    if bool_of(v):
        return 1

    return 0

# Total order used by comparisons (after NULL checks) and by ORDER BY.
fn order_cmp(a: Value, b: Value) Int:
    let ra = rank(a)
    let rb = rank(b)
    if ra != rb:
        return cmp_int(ra, rb)
    if ra == 1:
        return cmp_int(int_of(a), int_of(b))
    if ra == 2:
        return cmp_int(bool_int(a), bool_int(b))
    if ra == 3:
        return cmp_text(text_of(a), text_of(b))

    return 0

# Three-valued logic codes: 0 false, 1 true, 2 unknown (NULL).
fn tri_of(v: Value) Result[Int, SqlError]:
    match v:
        VNull:
            return ok(2)
        VBool(b):
            if b:
                return ok(1)

            return ok(0)
        _:
            return error(type_error())

fn tri_value(t: Int) Value:
    if t == 2:
        return Value.VNull

    return Value.VBool(b: t == 1)

fn tri_and(a: Int, b: Int) Int:
    if a == 0 or b == 0:
        return 0
    if a == 2 or b == 2:
        return 2

    return 1

fn tri_or(a: Int, b: Int) Int:
    if a == 1 or b == 1:
        return 1
    if a == 2 or b == 2:
        return 2

    return 0

fn tri_not(a: Int) Int:
    if a == 2:
        return 2

    return 1 - a

# WHERE, HAVING and ON keep a row only when the condition is true.
fn truth(v: Value) Result[Bool, SqlError]:
    let t = try tri_of(v)
    return ok(t == 1)

fn compare_op(op: String, x: Value, y: Value) Result[Value, SqlError]:
    if rank(x) == 0 or rank(y) == 0:
        return ok(Value.VNull)
    if rank(x) != rank(y) or rank(x) == 2:
        return error(type_error())

    let c = order_cmp(x, y)
    if op == "=":
        return ok(Value.VBool(b: c == 0))
    if op == "<>":
        return ok(Value.VBool(b: c != 0))
    if op == "<":
        return ok(Value.VBool(b: c < 0))
    if op == "<=":
        return ok(Value.VBool(b: c <= 0))
    if op == ">":
        return ok(Value.VBool(b: c > 0))

    return ok(Value.VBool(b: c >= 0))

fn arith(op: String, x: Value, y: Value) Result[Value, SqlError]:
    if rank(x) == 0 or rank(y) == 0:
        return ok(Value.VNull)

    if op == "||":
        if rank(x) != 3 or rank(y) != 3:
            return error(type_error())

        return ok(Value.VText(s: text_of(x) + text_of(y)))

    if rank(x) != 1 or rank(y) != 1:
        return error(type_error())

    let a = int_of(x)
    let b = int_of(y)
    if op == "+":
        return ok(Value.VInt(v: a + b))
    if op == "-":
        return ok(Value.VInt(v: a - b))
    if op == "*":
        return ok(Value.VInt(v: a * b))
    if b == 0:
        return error(sql_error("division by zero"))
    if op == "/":
        return ok(Value.VInt(v: a / b))

    return ok(Value.VInt(v: a % b))

fn negate(x: Value) Result[Value, SqlError]:
    if rank(x) == 0:
        return ok(Value.VNull)
    if rank(x) != 1:
        return error(type_error())

    return ok(Value.VInt(v: 0 - int_of(x)))

fn dedupe(vals: List[Value]) List[Value]:
    var seen = Set[String]()
    var out = List[Value]()

    for v in vals:
        let k = key_of(v)

        if not seen.contains(k):
            seen.add(k)
            out.append(v.clone())

    return out

# ---------- LIKE, string and math functions ----------

fn byte_list(s: String) List[Int]:
    let raw = s.to_bytes()
    var out = List[Int]()
    for k in 0..raw.length():
        out.append(raw.get(k).to_int())
    return out

# '%' is 37, '_' is 95.
fn like_at(text: List[Int], ti: Int, pat: List[Int], pi: Int) Bool:
    if pi == pat.length():
        return ti == text.length()

    if pat[pi] == 37:
        var k = ti

        while k <= text.length():
            if like_at(text, k, pat, pi + 1):
                return true

            k += 1

        return false

    if ti == text.length():
        return false
    if pat[pi] == 95 or pat[pi] == text[ti]:
        return like_at(text, ti + 1, pat, pi + 1)

    return false

fn like_match(s: String, pat: String) Bool:
    return like_at(byte_list(s), 0, byte_list(pat), 0)

fn ascii_case(s: String, upper: Bool) String:
    var codes = List[Int]()

    for ch in s.chars():
        var code = ch.scalar_at(0)
        if upper and code >= 97 and code <= 122:
            code = code - 32
        if not upper and code >= 65 and code <= 90:
            code = code + 32
        codes.append(code)

    return from_scalars(codes).get()

# 1-based start; positions are bytes and clipped to the string.
fn substr(t: String, start: Int, count: Int) String:
    if count <= 0:
        return ""

    let size = t.byte_length()
    var begin = start
    if begin < 1:
        begin = 1

    var finish = start + count - 1
    if finish > size:
        finish = size
    if begin > finish:
        return ""

    let piece = t.to_bytes().slice(begin - 1, finish).get()
    return piece.decode_utf8().get("")

fn is_aggregate(name: String) Bool:
    return name == "COUNT" or name == "SUM" or name == "MIN" or name == "MAX"

# -1 unknown function, -2 variadic (one or more), otherwise the exact count.
fn scalar_arity(name: String) Int:
    if name == "UPPER" or name == "LOWER" or name == "LENGTH" or name == "ABS":
        return 1
    if name == "SUBSTR":
        return 3
    if name == "COALESCE":
        return -2

    return -1

# ---------- expressions and statements ----------

type Expr:
    case ELit(v: Value)
    case ERef(qual: String, name: String)
    case ESlot(index: Int)
    case ENeg(arg: Expr)
    case ENot(arg: Expr)
    case EArith(op: String, left: Expr, right: Expr)
    case ECmp(op: String, left: Expr, right: Expr)
    case EAnd(left: Expr, right: Expr)
    case EOr(left: Expr, right: Expr)
    case EIsNull(arg: Expr, negated: Bool)
    case ELike(arg: Expr, pattern: Expr, negated: Bool)
    case EIn(arg: Expr, items: List[Expr], negated: Bool)
    case EBetween(arg: Expr, low: Expr, high: Expr, negated: Bool)
    case ECall(name: String, args: List[Expr], distinct: Bool, star: Bool)

type ColDef:
    name: String
    is_int: Bool
    not_null: Bool
    primary: Bool

type Table:
    cols: List[ColDef]
    rows: List[List[Value]]

type Assign:
    col: String
    expr: Expr

type TableRef:
    name: String
    alias: String

type JoinSpec:
    left_outer: Bool
    table: TableRef
    on: Expr

type RawItem:
    case RStar
    case RTableStar(tname: String)
    case RExpr(expr: Expr, alias: String)

type OrderSpec:
    expr: Expr
    desc: Bool

type Query:
    distinct: Bool
    items: List[RawItem]
    from_ref: Optional[TableRef]
    joins: List[JoinSpec]
    where_cond: Optional[Expr]
    groups: List[Expr]
    having_cond: Optional[Expr]
    orders: List[OrderSpec]
    limit: Optional[Int]
    offset: Int

type Stmt:
    case SCreate(name: String, cols: List[ColDef])
    case SDrop(name: String)
    case SInsert(name: String, cols: List[String], rows: List[List[Expr]])
    case SUpdate(name: String, sets: List[Assign], cond: Optional[Expr])
    case SDelete(name: String, cond: Optional[Expr])
    case SSelect(q: Query)

# ---------- lexer ----------

type Tok:
    case TId(name: String)
    case TKw(word: String)
    case TNum(n: Int)
    case TStr(s: String)
    case TSym(text: String)
    case TBad
    case TEof

fn is_letter(c: String) Bool:
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"

fn is_digit(c: String) Bool:
    return c >= "0" and c <= "9"

fn join_span(cs: List[String], begin: Int, finish: Int) String:
    var parts = List[String]()
    for k in begin..finish:
        parts.append(cs[k].clone())
    return parts.join("")

fn lex(cs: List[String]) List[Tok]:
    let kws = Set(
        [
            "SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT",
            "OFFSET", "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL",
            "IS", "LIKE", "IN", "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
            "DELETE", "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC",
            "DESC"
        ]
    )
    let ops = ["=", "<", ">", "+", "-", "*", "/", "%", "(", ")", ",", ".", ";"]
    let size = cs.length()
    var toks = List[Tok]()
    var i = 0

    while i < size:
        let c = cs[i].clone()

        if c == " " or c == "\t" or c == "\r" or c == "\n":
            i += 1
        else if c == "-" and i + 1 < size and cs[i + 1] == "-":
            while i < size and cs[i] != "\n":
                i += 1
        else if is_letter(c):
            var j = i + 1
            while j < size and (is_letter(cs[j]) or is_digit(cs[j])):
                j += 1

            let word = join_span(cs, i, j)
            let up = word.upper()

            if kws.contains(up):
                toks.append(Tok.TKw(word: up))
            else:
                toks.append(Tok.TId(name: word))

            i = j
        else if is_digit(c):
            var j = i
            var v = 0
            var big = false

            while j < size and is_digit(cs[j]):
                let d = cs[j].scalar_at(0) - 48

                if v > (9223372036854775807 - d) / 10:
                    big = true
                else:
                    v = v * 10 + d

                j += 1

            if big:
                toks.append(Tok.TBad)
            else:
                toks.append(Tok.TNum(n: v))

            i = j
        else if c == "'":
            var j = i + 1
            var parts = List[String]()
            var closed = false

            while j < size and not closed:
                if cs[j] == "'":
                    if j + 1 < size and cs[j + 1] == "'":
                        parts.append("'")
                        j += 2
                    else:
                        closed = true
                        j += 1
                else:
                    parts.append(cs[j].clone())
                    j += 1

            if closed:
                toks.append(Tok.TStr(s: parts.join("")))
            else:
                toks.append(Tok.TBad)

            i = j
        else:
            var pair = ""
            if i + 1 < size:
                pair = c + cs[i + 1]

            if pair == "<>" or pair == "<=" or pair == ">=" or pair == "||":
                toks.append(Tok.TSym(text: pair))
                i += 2
            else if pair == "!=":
                toks.append(Tok.TSym(text: "<>"))
                i += 2
            else if ops.contains(c):
                toks.append(Tok.TSym(text: c))
                i += 1
            else:
                toks.append(Tok.TBad)
                i += 1

    return toks

# Statements are separated by ';' tokens; empty statements are dropped.
fn split_statements(toks: List[Tok]) List[List[Tok]]:
    var stmts = List[List[Tok]]()
    var cur = List[Tok]()

    for t in toks:
        if tok_is_sym(t, ";"):
            if cur.length() > 0:
                stmts.append(cur)
            cur = List[Tok]()
        else:
            cur.append(t.clone())

    if cur.length() > 0:
        stmts.append(cur)
    return stmts

fn tok_is_sym(t: Tok, s: String) Bool:
    match t:
        TSym(text):
            return text == s
        _:
            return false

fn tok_is_kw(t: Tok, w: String) Bool:
    match t:
        TKw(word):
            return word == w
        _:
            return false

fn id_name(t: Tok) String:
    match t:
        TId(name):
            return name.clone()
        _:
            return ""

fn sym_op(t: Tok) String:
    match t:
        TSym(text):
            return text.clone()
        _:
            return ""

# ---------- parser ----------

type Cur:
    toks: List[Tok]
    pos: List[Int]

fn peek(p: Cur, k: Int) Tok:
    let idx = p.pos[0] + k
    if idx < p.toks.length():
        return p.toks[idx].clone()

    return Tok.TEof

fn advance(var p: Cur) Unit:
    p.pos[0] += 1

fn at_sym(p: Cur, s: String) Bool:
    return tok_is_sym(peek(p, 0), s)

fn at_kw(p: Cur, w: String) Bool:
    return tok_is_kw(peek(p, 0), w)

fn at_join(p: Cur) Bool:
    return at_kw(p, "JOIN") or at_kw(p, "INNER") or at_kw(p, "LEFT")

fn accept_sym(var p: Cur, s: String) Bool:
    if at_sym(p, s):
        advance(var p)
        return true

    return false

fn accept_kw(var p: Cur, w: String) Bool:
    if at_kw(p, w):
        advance(var p)
        return true

    return false

fn expect_kw(var p: Cur, w: String) Result[Unit, SqlError]:
    if accept_kw(var p, w):
        return ok(unit)

    return error(syntax_error())

fn expect_sym(var p: Cur, s: String) Result[Unit, SqlError]:
    if accept_sym(var p, s):
        return ok(unit)

    return error(syntax_error())

fn expect_ident(var p: Cur) Result[String, SqlError]:
    let name = id_name(peek(p, 0))
    if name == "":
        return error(syntax_error())

    advance(var p)
    return ok(name)

fn expect_number(var p: Cur) Result[Int, SqlError]:
    match peek(p, 0):
        TNum(n):
            advance(var p)
            return ok(n)
        _:
            return error(syntax_error())

fn parse_expr(var p: Cur) Result[Expr, SqlError]:
    return parse_or(var p)

fn parse_or(var p: Cur) Result[Expr, SqlError]:
    var left = try parse_and(var p)

    while accept_kw(var p, "OR"):
        let right = try parse_and(var p)
        left = Expr.EOr(left: left, right: right)

    return ok(left)

fn parse_and(var p: Cur) Result[Expr, SqlError]:
    var left = try parse_not(var p)

    while accept_kw(var p, "AND"):
        let right = try parse_not(var p)
        left = Expr.EAnd(left: left, right: right)

    return ok(left)

fn parse_not(var p: Cur) Result[Expr, SqlError]:
    if accept_kw(var p, "NOT"):
        let arg = try parse_not(var p)
        return ok(Expr.ENot(arg: arg))

    return parse_cmp(var p)

fn parse_cmp(var p: Cur) Result[Expr, SqlError]:
    let left = try parse_add(var p)
    let op = sym_op(peek(p, 0))

    if op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">=":
        advance(var p)

        let right = try parse_add(var p)
        return ok(Expr.ECmp(op: op, left: left, right: right))

    if accept_kw(var p, "IS"):
        let negated = accept_kw(var p, "NOT")
        try expect_kw(var p, "NULL")
        return ok(Expr.EIsNull(arg: left, negated: negated))

    var negated = false

    if at_kw(p, "NOT"):
        let nxt = peek(p, 1)

        if tok_is_kw(nxt, "LIKE") or tok_is_kw(nxt, "IN") or tok_is_kw(nxt, "BETWEEN"):
            advance(var p)
            negated = true

    if accept_kw(var p, "LIKE"):
        let pattern = try parse_add(var p)
        return ok(Expr.ELike(arg: left, pattern: pattern, negated: negated))

    if accept_kw(var p, "IN"):
        try expect_sym(var p, "(")

        var items = List[Expr]()
        let first = try parse_expr(var p)
        items.append(first)

        while accept_sym(var p, ","):
            let more = try parse_expr(var p)
            items.append(more)

        try expect_sym(var p, ")")
        return ok(Expr.EIn(arg: left, items: items, negated: negated))

    if accept_kw(var p, "BETWEEN"):
        let low = try parse_add(var p)
        try expect_kw(var p, "AND")

        let high = try parse_add(var p)
        return ok(Expr.EBetween(arg: left, low: low, high: high, negated: negated))

    return ok(left)

fn parse_add(var p: Cur) Result[Expr, SqlError]:
    var left = try parse_mul(var p)
    var going = true

    while going:
        let op = sym_op(peek(p, 0))

        if op == "+" or op == "-" or op == "||":
            advance(var p)

            let right = try parse_mul(var p)
            left = Expr.EArith(op: op, left: left, right: right)
        else:
            going = false

    return ok(left)

fn parse_mul(var p: Cur) Result[Expr, SqlError]:
    var left = try parse_unary(var p)
    var going = true

    while going:
        let op = sym_op(peek(p, 0))

        if op == "*" or op == "/" or op == "%":
            advance(var p)

            let right = try parse_unary(var p)
            left = Expr.EArith(op: op, left: left, right: right)
        else:
            going = false

    return ok(left)

fn parse_unary(var p: Cur) Result[Expr, SqlError]:
    if accept_sym(var p, "-"):
        let arg = try parse_unary(var p)
        return ok(Expr.ENeg(arg: arg))

    return parse_primary(var p)

fn parse_call(var p: Cur, name: String) Result[Expr, SqlError]:
    let distinct = accept_kw(var p, "DISTINCT")

    if accept_sym(var p, "*"):
        try expect_sym(var p, ")")
        return ok(
            Expr.ECall(
                name: name.upper(), args: List[Expr](), distinct: distinct, star: true
            )
        )

    var args = List[Expr]()
    if accept_sym(var p, ")"):
        return ok(
            Expr.ECall(
                name: name.upper(), args: args, distinct: distinct, star: false
            )
        )

    let first = try parse_expr(var p)
    args.append(first)

    while accept_sym(var p, ","):
        let more = try parse_expr(var p)
        args.append(more)

    try expect_sym(var p, ")")
    return ok(
        Expr.ECall(
            name: name.upper(), args: args, distinct: distinct, star: false
        )
    )

fn parse_primary(var p: Cur) Result[Expr, SqlError]:
    let t = peek(p, 0)

    match t:
        TNum(n):
            advance(var p)
            return ok(Expr.ELit(v: Value.VInt(v: n)))
        TStr(s):
            advance(var p)
            return ok(Expr.ELit(v: Value.VText(s: s)))
        TKw(word):
            if word == "NULL":
                advance(var p)
                return ok(Expr.ELit(v: Value.VNull))

            return error(syntax_error())
        TSym(text):
            if text == "(":
                advance(var p)

                let inner = try parse_expr(var p)
                try expect_sym(var p, ")")
                return ok(inner)

            return error(syntax_error())
        TId(name):
            advance(var p)
            if accept_sym(var p, "("):
                return parse_call(var p, name)

            if accept_sym(var p, "."):
                let col = try expect_ident(var p)
                return ok(Expr.ERef(qual: name, name: col))

            return ok(Expr.ERef(qual: "", name: name))
        _:
            return error(syntax_error())

fn parse_colref(var p: Cur) Result[Expr, SqlError]:
    let first = try expect_ident(var p)

    if accept_sym(var p, "."):
        let second = try expect_ident(var p)
        return ok(Expr.ERef(qual: first, name: second))

    return ok(Expr.ERef(qual: "", name: first))

fn parse_tref(var p: Cur) Result[TableRef, SqlError]:
    let name = try expect_ident(var p)
    var alias = name.clone()

    if accept_kw(var p, "AS"):
        alias = try expect_ident(var p)
    else if id_name(peek(p, 0)) != "":
        alias = try expect_ident(var p)

    return ok(TableRef(name: name, alias: alias))

fn parse_join(var p: Cur) Result[JoinSpec, SqlError]:
    var outer = false

    if accept_kw(var p, "LEFT"):
        outer = true
        try expect_kw(var p, "JOIN")
    else if accept_kw(var p, "INNER"):
        try expect_kw(var p, "JOIN")
    else:
        try expect_kw(var p, "JOIN")

    let table = try parse_tref(var p)
    try expect_kw(var p, "ON")

    let on = try parse_expr(var p)
    return ok(JoinSpec(left_outer: outer, table: table, on: on))

fn parse_item(var p: Cur) Result[RawItem, SqlError]:
    if accept_sym(var p, "*"):
        return ok(RawItem.RStar)

    let name = id_name(peek(p, 0))

    if name != "" and tok_is_sym(peek(p, 1), ".") and tok_is_sym(peek(p, 2), "*"):
        advance(var p)
        advance(var p)
        advance(var p)
        return ok(RawItem.RTableStar(tname: name))

    let e = try parse_expr(var p)
    var alias = ""
    if accept_kw(var p, "AS"):
        alias = try expect_ident(var p)
    return ok(RawItem.RExpr(expr: e, alias: alias))

fn parse_select(var p: Cur) Result[Query, SqlError]:
    let distinct = accept_kw(var p, "DISTINCT")
    var items = List[RawItem]()
    let first = try parse_item(var p)
    items.append(first)

    while accept_sym(var p, ","):
        let more = try parse_item(var p)
        items.append(more)

    var from_ref: Optional[TableRef] = none
    var joins = List[JoinSpec]()

    if accept_kw(var p, "FROM"):
        let base = try parse_tref(var p)
        from_ref = base

        while at_join(p):
            let join = try parse_join(var p)
            joins.append(join)

    var where_cond: Optional[Expr] = none

    if accept_kw(var p, "WHERE"):
        let w = try parse_expr(var p)
        where_cond = w

    var groups = List[Expr]()

    if accept_kw(var p, "GROUP"):
        try expect_kw(var p, "BY")

        let g0 = try parse_colref(var p)
        groups.append(g0)

        while accept_sym(var p, ","):
            let g = try parse_colref(var p)
            groups.append(g)

    var having_cond: Optional[Expr] = none

    if accept_kw(var p, "HAVING"):
        let h = try parse_expr(var p)
        having_cond = h

    var orders = List[OrderSpec]()

    if accept_kw(var p, "ORDER"):
        try expect_kw(var p, "BY")

        var going = true

        while going:
            let e = try parse_expr(var p)
            var desc = accept_kw(var p, "DESC")
            if not desc:
                let _asc = accept_kw(var p, "ASC")
            orders.append(OrderSpec(expr: e, desc: desc))
            going = accept_sym(var p, ",")

    var limit: Optional[Int] = none
    var offset = 0

    if accept_kw(var p, "LIMIT"):
        let n = try expect_number(var p)
        limit = n

        if accept_kw(var p, "OFFSET"):
            let skip = try expect_number(var p)
            offset = skip

    return ok(
        Query(
            distinct: distinct, items: items, from_ref: from_ref, joins: joins,
            where_cond: where_cond, groups: groups, having_cond: having_cond,
            orders: orders, limit: limit, offset: offset
        )
    )

fn parse_coldef(var p: Cur) Result[ColDef, SqlError]:
    let name = try expect_ident(var p)
    let type_name = try expect_ident(var p)
    let up = type_name.upper()
    if up != "INT" and up != "TEXT":
        return error(syntax_error())

    var pk = false
    var nn = false
    var going = true

    while going:
        if accept_kw(var p, "PRIMARY"):
            try expect_kw(var p, "KEY")
            pk = true
        else if accept_kw(var p, "NOT"):
            try expect_kw(var p, "NULL")
            nn = true
        else:
            going = false

    return ok(ColDef(name: name, is_int: up == "INT", not_null: nn or pk, primary: pk))

fn parse_row(var p: Cur) Result[List[Expr], SqlError]:
    try expect_sym(var p, "(")

    var vals = List[Expr]()
    let first = try parse_expr(var p)
    vals.append(first)

    while accept_sym(var p, ","):
        let more = try parse_expr(var p)
        vals.append(more)

    try expect_sym(var p, ")")
    return ok(vals)

fn parse_assign(var p: Cur) Result[Assign, SqlError]:
    let col = try expect_ident(var p)
    try expect_sym(var p, "=")

    let e = try parse_expr(var p)
    return ok(Assign(col: col, expr: e))

fn parse_where_opt(var p: Cur) Result[Optional[Expr], SqlError]:
    if accept_kw(var p, "WHERE"):
        let e = try parse_expr(var p)
        return ok(e)

    return ok(none)

fn parse_statement(var p: Cur) Result[Stmt, SqlError]:
    if accept_kw(var p, "CREATE"):
        try expect_kw(var p, "TABLE")

        let name = try expect_ident(var p)
        try expect_sym(var p, "(")

        var cols = List[ColDef]()
        let first = try parse_coldef(var p)
        cols.append(first)

        while accept_sym(var p, ","):
            let more = try parse_coldef(var p)
            cols.append(more)

        try expect_sym(var p, ")")
        return ok(Stmt.SCreate(name: name, cols: cols))

    if accept_kw(var p, "DROP"):
        try expect_kw(var p, "TABLE")

        let name = try expect_ident(var p)
        return ok(Stmt.SDrop(name: name))

    if accept_kw(var p, "INSERT"):
        try expect_kw(var p, "INTO")

        let name = try expect_ident(var p)
        var cols = List[String]()

        if accept_sym(var p, "("):
            let c0 = try expect_ident(var p)
            cols.append(c0)

            while accept_sym(var p, ","):
                let more = try expect_ident(var p)
                cols.append(more)

            try expect_sym(var p, ")")

        try expect_kw(var p, "VALUES")

        var rows = List[List[Expr]]()
        let r0 = try parse_row(var p)
        rows.append(r0)

        while accept_sym(var p, ","):
            let more = try parse_row(var p)
            rows.append(more)

        return ok(Stmt.SInsert(name: name, cols: cols, rows: rows))

    if accept_kw(var p, "UPDATE"):
        let name = try expect_ident(var p)
        try expect_kw(var p, "SET")

        var sets = List[Assign]()
        let first = try parse_assign(var p)
        sets.append(first)

        while accept_sym(var p, ","):
            let more = try parse_assign(var p)
            sets.append(more)

        let cond = try parse_where_opt(var p)
        return ok(Stmt.SUpdate(name: name, sets: sets, cond: cond))

    if accept_kw(var p, "DELETE"):
        try expect_kw(var p, "FROM")

        let name = try expect_ident(var p)
        let cond = try parse_where_opt(var p)
        return ok(Stmt.SDelete(name: name, cond: cond))

    if accept_kw(var p, "SELECT"):
        let q = try parse_select(var p)
        return ok(Stmt.SSelect(q: q))

    return error(syntax_error())

# ---------- name resolution ----------

type Source:
    alias: String
    cols: List[String]
    offset: Int

type Scope:
    sources: List[Source]
    visible: Int
    aggs_ok: Bool
    grouped: Bool
    group_slots: List[Int]

fn plain_scope(sources: List[Source], visible: Int) Scope:
    return Scope(
        sources: sources, visible: visible, aggs_ok: false, grouped: false,
        group_slots: List[Int]()
    )

fn qualified(qual: String, name: String) String:
    if qual == "":
        return name.clone()

    return qual + "." + name

fn find_slot(sc: Scope, qual: String, name: String) Result[Int, SqlError]:
    var found = -1
    var count = 0

    for k in 0..sc.visible:
        if qual == "" or sc.sources[k].alias == qual:
            for j in 0..sc.sources[k].cols.length():
                if sc.sources[k].cols[j] == name:
                    found = sc.sources[k].offset + j
                    count += 1

    if count == 1:
        return ok(found)
    if count > 1:
        return error(sql_error("ambiguous column: {name}"))

    return error(sql_error("no such column: {qualified(qual, name)}"))

fn slot_of(e: Expr) Int:
    match e:
        ESlot(index):
            return index
        _:
            return -1

fn resolve(e: Expr, sc: Scope, in_agg: Bool) Result[Expr, SqlError]:
    match e:
        ELit(v):
            return ok(Expr.ELit(v: v.clone()))
        ERef(qual, name):
            let slot = try find_slot(sc, qual, name)
            if sc.grouped and not in_agg and not sc.group_slots.contains(slot):
                return error(
                    sql_error(
                        "column {qualified(qual, name)} must appear in GROUP BY"
                    )
                )

            return ok(Expr.ESlot(index: slot))
        ESlot(index):
            return ok(Expr.ESlot(index: index))
        ENeg(arg):
            let a = try resolve(arg, sc, in_agg)
            return ok(Expr.ENeg(arg: a))
        ENot(arg):
            let a = try resolve(arg, sc, in_agg)
            return ok(Expr.ENot(arg: a))
        EArith(op, left, right):
            let l = try resolve(left, sc, in_agg)
            let r = try resolve(right, sc, in_agg)
            return ok(Expr.EArith(op: op.clone(), left: l, right: r))
        ECmp(op, left, right):
            let l = try resolve(left, sc, in_agg)
            let r = try resolve(right, sc, in_agg)
            return ok(Expr.ECmp(op: op.clone(), left: l, right: r))
        EAnd(left, right):
            let l = try resolve(left, sc, in_agg)
            let r = try resolve(right, sc, in_agg)
            return ok(Expr.EAnd(left: l, right: r))
        EOr(left, right):
            let l = try resolve(left, sc, in_agg)
            let r = try resolve(right, sc, in_agg)
            return ok(Expr.EOr(left: l, right: r))
        EIsNull(arg, negated):
            let a = try resolve(arg, sc, in_agg)
            return ok(Expr.EIsNull(arg: a, negated: negated))
        ELike(arg, pattern, negated):
            let a = try resolve(arg, sc, in_agg)
            let p = try resolve(pattern, sc, in_agg)
            return ok(Expr.ELike(arg: a, pattern: p, negated: negated))
        EIn(arg, items, negated):
            let a = try resolve(arg, sc, in_agg)
            var rs = List[Expr]()

            for it in items:
                let r = try resolve(it, sc, in_agg)
                rs.append(r)

            return ok(Expr.EIn(arg: a, items: rs, negated: negated))
        EBetween(arg, low, high, negated):
            let a = try resolve(arg, sc, in_agg)
            let lo = try resolve(low, sc, in_agg)
            let hi = try resolve(high, sc, in_agg)
            return ok(Expr.EBetween(arg: a, low: lo, high: hi, negated: negated))
        ECall(name, args, distinct, star):
            if is_aggregate(name):
                if not sc.aggs_ok or in_agg:
                    return error(sql_error("misuse of aggregate"))

                if star:
                    if name != "COUNT" or distinct:
                        return error(sql_error("wrong number of arguments to {name}"))

                    return ok(
                        Expr.ECall(
                            name: name.clone(), args: List[Expr](), distinct: false,
                            star: true
                        )
                    )

                if args.length() != 1:
                    return error(sql_error("wrong number of arguments to {name}"))

                let a = try resolve(args[0], sc, true)
                var one = List[Expr]()
                one.append(a)
                return ok(
                    Expr.ECall(
                        name: name.clone(), args: one, distinct: distinct, star: false
                    )
                )

            let want = scalar_arity(name)
            if want == -1:
                return error(sql_error("no such function: {name}"))
            if (
                star
                or (want == -2 and args.length() == 0)
                or (want >= 0 and args.length() != want)
            ):
                return error(sql_error("wrong number of arguments to {name}"))

            var rs = List[Expr]()

            for a in args:
                let r = try resolve(a, sc, in_agg)
                rs.append(r)

            return ok(
                Expr.ECall(
                    name: name.clone(), args: rs, distinct: false, star: false
                )
            )

fn has_agg(e: Expr) Bool:
    match e:
        ECall(name, args, _d, _s):
            if is_aggregate(name):
                return true

            for a in args:
                if has_agg(a):
                    return true
            return false
        ENeg(arg):
            return has_agg(arg)
        ENot(arg):
            return has_agg(arg)
        EArith(_op, left, right):
            return has_agg(left) or has_agg(right)
        ECmp(_op, left, right):
            return has_agg(left) or has_agg(right)
        EAnd(left, right):
            return has_agg(left) or has_agg(right)
        EOr(left, right):
            return has_agg(left) or has_agg(right)
        EIsNull(arg, _n):
            return has_agg(arg)
        ELike(arg, pattern, _n):
            return has_agg(arg) or has_agg(pattern)
        EIn(arg, items, _n):
            if has_agg(arg):
                return true

            for it in items:
                if has_agg(it):
                    return true
            return false
        EBetween(arg, low, high, _n):
            return has_agg(arg) or has_agg(low) or has_agg(high)
        _:
            return false

# The literal N of `ORDER BY N`, or -1 when the expression is not an integer literal.
fn int_literal(e: Expr) Int:
    match e:
        ELit(v):
            if rank(v) == 1:
                return int_of(v)

            return -1
        _:
            return -1

fn plain_name(e: Expr) String:
    match e:
        ERef(qual, name):
            if qual == "":
                return name.clone()

            return ""
        _:
            return ""

# The output name of a select item: the alias, else the column name (qualifier dropped).
fn item_name(alias: String, e: Expr) String:
    if alias != "":
        return alias.clone()

    match e:
        ERef(_qual, name):
            return name.clone()
        _:
            return "?column?"

# ---------- evaluation ----------

fn eval_scalar(
    name: String,
    args: List[Expr],
    row: List[Value],
    group: List[List[Value]]
) Result[Value, SqlError]:
    var vals = List[Value]()

    for a in args:
        let v = try eval(a, row, group)
        vals.append(v)

    if name == "COALESCE":
        for v in vals:
            if rank(v) != 0:
                return ok(v.clone())
        return ok(Value.VNull)

    for v in vals:
        if rank(v) == 0:
            return ok(Value.VNull)

    if name == "UPPER" or name == "LOWER":
        if rank(vals[0]) != 3:
            return error(type_error())

        return ok(Value.VText(s: ascii_case(text_of(vals[0]), name == "UPPER")))

    if name == "LENGTH":
        if rank(vals[0]) != 3:
            return error(type_error())

        return ok(Value.VInt(v: text_of(vals[0]).byte_length()))

    if name == "ABS":
        if rank(vals[0]) != 1:
            return error(type_error())

        let n = int_of(vals[0])
        if n < 0:
            return ok(Value.VInt(v: 0 - n))

        return ok(Value.VInt(v: n))

    # SUBSTR(text, start, count)
    if rank(vals[0]) != 3 or rank(vals[1]) != 1 or rank(vals[2]) != 1:
        return error(type_error())

    return ok(
        Value.VText(
            s: substr(text_of(vals[0]), int_of(vals[1]), int_of(vals[2]))
        )
    )

fn aggregate(
    name: String,
    args: List[Expr],
    distinct: Bool,
    star: Bool,
    group: List[List[Value]]
) Result[Value, SqlError]:
    if star:
        return ok(Value.VInt(v: group.length()))

    let none_group = List[List[Value]]()
    var vals = List[Value]()

    for r in group:
        let v = try eval(args[0], r, none_group)
        if rank(v) != 0:
            vals.append(v)

    var use = vals.clone()
    if distinct:
        use = dedupe(vals)
    if name == "COUNT":
        return ok(Value.VInt(v: use.length()))
    if use.length() == 0:
        return ok(Value.VNull)

    if name == "SUM":
        var total = 0

        for v in use:
            if rank(v) != 1:
                return error(type_error())

            total += int_of(v)

        return ok(Value.VInt(v: total))

    let kind = rank(use[0])
    if kind != 1 and kind != 3:
        return error(type_error())

    var best = use[0].clone()

    for v in use:
        if rank(v) != kind:
            return error(type_error())

        let c = order_cmp(v, best)
        if (name == "MIN" and c < 0) or (name == "MAX" and c > 0):
            best = v.clone()

    return ok(best)

fn eval(e: Expr, row: List[Value], group: List[List[Value]]) Result[Value, SqlError]:
    match e:
        ELit(v):
            return ok(v.clone())
        ESlot(index):
            return ok(row[index].clone())
        ENeg(arg):
            let x = try eval(arg, row, group)
            return negate(x)
        ENot(arg):
            let x = try eval(arg, row, group)
            let t = try tri_of(x)
            return ok(tri_value(tri_not(t)))
        EArith(op, left, right):
            let x = try eval(left, row, group)
            let y = try eval(right, row, group)
            return arith(op, x, y)
        ECmp(op, left, right):
            let x = try eval(left, row, group)
            let y = try eval(right, row, group)
            return compare_op(op, x, y)
        EAnd(left, right):
            let x = try eval(left, row, group)
            let tx = try tri_of(x)
            if tx == 0:
                return ok(Value.VBool(b: false))

            let y = try eval(right, row, group)
            let ty = try tri_of(y)
            return ok(tri_value(tri_and(tx, ty)))
        EOr(left, right):
            let x = try eval(left, row, group)
            let tx = try tri_of(x)
            if tx == 1:
                return ok(Value.VBool(b: true))

            let y = try eval(right, row, group)
            let ty = try tri_of(y)
            return ok(tri_value(tri_or(tx, ty)))
        EIsNull(arg, negated):
            let x = try eval(arg, row, group)
            let isnull = rank(x) == 0
            return ok(Value.VBool(b: isnull != negated))
        ELike(arg, pattern, negated):
            let x = try eval(arg, row, group)
            let p = try eval(pattern, row, group)
            if rank(x) == 0 or rank(p) == 0:
                return ok(Value.VNull)
            if rank(x) != 3 or rank(p) != 3:
                return error(type_error())

            let m = like_match(text_of(x), text_of(p))
            return ok(Value.VBool(b: m != negated))
        EIn(arg, items, negated):
            let x = try eval(arg, row, group)
            var vals = List[Value]()

            for it in items:
                let v = try eval(it, row, group)
                vals.append(v)

            if rank(x) == 0:
                return ok(Value.VNull)

            var found = false
            var unknown = false

            for v in vals:
                if not found:
                    if rank(v) == 0:
                        unknown = true
                    else if rank(v) != rank(x) or rank(x) == 2:
                        return error(type_error())
                    else if order_cmp(x, v) == 0:
                        found = true

            if found:
                return ok(Value.VBool(b: not negated))
            if unknown:
                return ok(Value.VNull)

            return ok(Value.VBool(b: negated))
        EBetween(arg, low, high, negated):
            let x = try eval(arg, row, group)
            let lo = try eval(low, row, group)
            let hi = try eval(high, row, group)
            let c1 = try compare_op(">=", x, lo)
            let c2 = try compare_op("<=", x, hi)
            let t1 = try tri_of(c1)
            let t2 = try tri_of(c2)
            var t = tri_and(t1, t2)
            if negated:
                t = tri_not(t)
            return ok(tri_value(t))
        ECall(name, args, distinct, star):
            if is_aggregate(name):
                return aggregate(name, args, distinct, star, group)

            return eval_scalar(name, args, row, group)
        _:
            return ok(Value.VNull)

fn eval_all(
    exprs: List[Expr],
    row: List[Value],
    group: List[List[Value]]
) Result[List[Value], SqlError]:
    var out = List[Value]()

    for e in exprs:
        let v = try eval(e, row, group)
        out.append(v)

    return ok(out)

# ---------- SELECT ----------

type Pending:
    expr: Expr
    name: String

type OutRow:
    vals: List[Value]
    keys: List[Value]

# position >= 0 reads that output column; otherwise expr is evaluated.
type OrderKey:
    position: Int
    expr: Expr
    desc: Bool

fn fetch(db: Map[String, Table], name: String) Result[Table, SqlError]:
    if let t = db.get(name):
        return ok(t.clone())

    return error(sql_error("no such table: {name}"))

fn group_rows(rows: List[List[Value]], slots: List[Int]) List[List[List[Value]]]:
    var groups = List[List[List[Value]]]()

    if slots.length() == 0:
        groups.append(rows.clone())
        return groups

    var index = Map[String, Int]()

    for r in rows:
        var k = ""
        for s in slots:
            k = k + key_of(r[s])

        if index.contains(k):
            let gi = index.get_or(k, 0)
            groups[gi].append(r.clone())
        else:
            index.add(k, groups.length())

            var g = List[List[Value]]()
            g.append(r.clone())
            groups.append(g)

    return groups

fn eval_keys(
    keys: List[OrderKey],
    vals: List[Value],
    row: List[Value],
    group: List[List[Value]]
) Result[List[Value], SqlError]:
    var out = List[Value]()

    for k in keys:
        if k.position >= 0:
            out.append(vals[k.position].clone())
        else:
            let v = try eval(k.expr, row, group)
            out.append(v)

    return ok(out)

fn cmp_out(a: OutRow, b: OutRow, descs: List[Bool]) Int:
    for k in 0..descs.length():
        var c = order_cmp(a.keys[k], b.keys[k])
        if descs[k]:
            c = 0 - c
        if c != 0:
            return c

    return 0

fn run_select(db: Map[String, Table], q: Query) Result[String, SqlError]:
    var refs = List[TableRef]()
    if let base = q.from_ref:
        refs.append(base.clone())
    for j in q.joins:
        refs.append(j.table.clone())
    for r in refs:
        if not db.contains(r.name):
            return error(sql_error("no such table: {r.name}"))

    var aliases = Set[String]()

    for r in refs:
        if aliases.contains(r.alias):
            return error(sql_error("duplicate alias: {r.alias}"))

        aliases.add(r.alias.clone())

    var sources = List[Source]()
    var tables = List[List[List[Value]]]()
    var offset = 0

    for r in refs:
        let t = try fetch(db, r.name)
        var names = List[String]()
        for c in t.cols:
            names.append(c.name.clone())
        sources.append(
            Source(
                alias: r.alias.clone(), cols: names.clone(), offset: offset
            )
        )
        offset += names.length()
        tables.append(t.rows.clone())

    # ON conditions see only the tables joined so far.
    var on_exprs = List[Expr]()

    for k in 0..q.joins.length():
        let on_scope = plain_scope(sources.clone(), k + 2)
        let on_r = try resolve(q.joins[k].on, on_scope, false)
        on_exprs.append(on_r)

    # Stars expand before GROUP BY, WHERE and the select list are resolved.
    var pend = List[Pending]()

    for it in q.items:
        match it:
            RStar:
                for s in sources:
                    for c in s.cols:
                        pend.append(
                            Pending(
                                expr: Expr.ERef(
                                    qual: s.alias.clone(), name: c.clone()
                                ),
                                name: c.clone()
                            )
                        )
            RTableStar(tname):
                var idx = -1
                for k in 0..sources.length():
                    if sources[k].alias == tname:
                        idx = k
                if idx < 0:
                    return error(sql_error("no such table: {tname}"))

                for c in sources[idx].cols:
                    pend.append(
                        Pending(
                            expr: Expr.ERef(
                                qual: tname.clone(), name: c.clone()
                            ),
                            name: c.clone()
                        )
                    )
            RExpr(e, alias):
                pend.append(Pending(expr: e.clone(), name: item_name(alias, e)))

    let full = plain_scope(sources.clone(), sources.length())
    var group_slots = List[Int]()

    for g in q.groups:
        let rg = try resolve(g, full, false)
        group_slots.append(slot_of(rg))

    var where_r: Optional[Expr] = none

    if let w = q.where_cond:
        let wr = try resolve(w, full, false)
        where_r = wr

    var is_agg = q.groups.length() > 0
    if let _h = q.having_cond:
        is_agg = true
    for p in pend:
        if has_agg(p.expr):
            is_agg = true
    for o in q.orders:
        if has_agg(o.expr):
            is_agg = true

    let agg_scope = Scope(
        sources: sources.clone(), visible: sources.length(), aggs_ok: true,
        grouped: is_agg, group_slots: group_slots.clone()
    )
    var items_r = List[Expr]()
    var names = List[String]()

    for p in pend:
        let ir = try resolve(p.expr, agg_scope, false)
        items_r.append(ir)
        names.append(p.name.clone())

    var having_r: Optional[Expr] = none

    if let h = q.having_cond:
        let hr = try resolve(h, agg_scope, false)
        having_r = hr

    var keys = List[OrderKey]()

    for o in q.orders:
        let lit = int_literal(o.expr)
        let plain = plain_name(o.expr)
        var position = -1

        if lit != -1:
            if lit < 1 or lit > items_r.length():
                return error(sql_error("bad ORDER BY position"))

            position = lit - 1
        else if plain != "":
            for i in 0..names.length():
                if position == -1 and names[i] == plain:
                    position = i

        if position >= 0:
            keys.append(
                OrderKey(
                    position: position, expr: Expr.ELit(v: Value.VNull), desc: o.desc
                )
            )
        else:
            let orr = try resolve(o.expr, agg_scope, false)
            keys.append(OrderKey(position: -1, expr: orr, desc: o.desc))

    # FROM and JOIN: nested loops in order.
    let empty = List[List[Value]]()
    var rows = List[List[Value]]()

    if sources.length() == 0:
        rows.append(List[Value]())
    else:
        rows = tables[0].clone()

    for k in 0..q.joins.length():
        var nxt = List[List[Value]]()
        let width = sources[k + 1].cols.length()

        for outer in rows:
            var matched = false

            for inner in tables[k + 1]:
                var combined = outer.clone()
                for v in inner:
                    combined.append(v.clone())

                let cond = try eval(on_exprs[k], combined, empty)
                let keep = try truth(cond)

                if keep:
                    matched = true
                    nxt.append(combined)

            if q.joins[k].left_outer and not matched:
                var padded = outer.clone()
                for _w in 0..width:
                    padded.append(Value.VNull)
                nxt.append(padded)

        rows = nxt

    if let w = where_r:
        var kept = List[List[Value]]()

        for r in rows:
            let cond = try eval(w, r, empty)
            let keep = try truth(cond)
            if keep:
                kept.append(r.clone())

        rows = kept

    var outs = List[OutRow]()

    if not is_agg:
        for r in rows:
            let vals = try eval_all(items_r, r, empty)
            let ks = try eval_keys(keys, vals, r, empty)
            outs.append(OutRow(vals: vals, keys: ks))
    else:
        let groups = group_rows(rows, group_slots)

        for g in groups:
            var rep = List[Value]()
            if g.length() > 0:
                rep = g[0].clone()

            var keep = true

            if let h = having_r:
                let hv = try eval(h, rep, g)
                keep = try truth(hv)

            if keep:
                let vals = try eval_all(items_r, rep, g)
                let ks = try eval_keys(keys, vals, rep, g)
                outs.append(OutRow(vals: vals, keys: ks))

    if q.distinct:
        var seen = Set[String]()
        var kept = List[OutRow]()

        for o in outs:
            let k = row_key(o.vals)

            if not seen.contains(k):
                seen.add(k)
                kept.append(o.clone())

        outs = kept

    if keys.length() > 0:
        var descs = List[Bool]()
        for k in keys:
            descs.append(k.desc)
        outs = outs.sorted(fn a, b: cmp_out(a, b, descs))

    let skip = q.offset
    var begin = skip
    if begin > outs.length():
        begin = outs.length()

    var finish = outs.length()
    if let lim = q.limit:
        if begin + lim < finish:
            finish = begin + lim

    var lines = List[String]()
    lines.append(names.join("|"))
    for i in begin..finish:
        lines.append(outs[i].vals.map(fn v: show(v)).join("|"))
    lines.append("({finish - begin} rows)")
    return ok(lines.join("\n") + "\n")

# ---------- DDL and DML ----------

fn table_scope(name: String, cols: List[ColDef]) List[Source]:
    var names = List[String]()
    for c in cols:
        names.append(c.name.clone())

    var sources = List[Source]()
    sources.append(Source(alias: name.clone(), cols: names, offset: 0))
    return sources

fn col_index(cols: List[ColDef], name: String) Int:
    for j in 0..cols.length():
        if cols[j].name == name:
            return j
    return -1

fn check_row(cols: List[ColDef], vals: List[Value]) Result[Unit, SqlError]:
    for j in 0..cols.length():
        if rank(vals[j]) == 0:
            if cols[j].not_null:
                return error(sql_error("NOT NULL constraint failed: {cols[j].name}"))
        else if cols[j].is_int and rank(vals[j]) != 1:
            return error(sql_error("type mismatch in column {cols[j].name}"))
        else if not cols[j].is_int and rank(vals[j]) != 3:
            return error(sql_error("type mismatch in column {cols[j].name}"))

    return ok(unit)

# Checks the primary key of `added` rows against `existing` rows, in order.
fn check_primary(
    cols: List[ColDef],
    existing: List[List[Value]],
    added: List[List[Value]]
) Result[Unit, SqlError]:
    var pk = -1
    for j in 0..cols.length():
        if cols[j].primary:
            pk = j
    if pk < 0:
        return ok(unit)

    var seen = Set[String]()
    for r in existing:
        seen.add(key_of(r[pk]))

    for r in added:
        let k = key_of(r[pk])
        if seen.contains(k):
            return error(sql_error("duplicate primary key: {show(r[pk])}"))

        seen.add(k)

    return ok(unit)

fn create_table(var db: Map[String, Table], name: String, cols: List[ColDef]) Result[
    String, SqlError
]:
    if db.contains(name):
        return error(sql_error("table {name} already exists"))

    var seen = Set[String]()
    var pk_count = 0

    for c in cols:
        if seen.contains(c.name):
            return error(sql_error("duplicate column: {c.name}"))

        seen.add(c.name.clone())
        if c.primary:
            pk_count += 1

    if pk_count > 1:
        return error(sql_error("multiple primary keys"))

    db.add(name.clone(), Table(cols: cols, rows: List[List[Value]]()))
    return ok("ok\n")

fn drop_table(var db: Map[String, Table], name: String) Result[String, SqlError]:
    if not db.contains(name):
        return error(sql_error("no such table: {name}"))

    db.remove(name)
    return ok("ok\n")

fn insert_rows(
    var db: Map[String, Table], name: String, cols: List[String], rows: List[List[Expr]]
) Result[String, SqlError]:
    let tbl = try fetch(db, name)
    var positions = List[Int]()

    if cols.length() == 0:
        for j in 0..tbl.cols.length():
            positions.append(j)
    else:
        var seen = Set[String]()

        for c in cols:
            let j = col_index(tbl.cols, c)
            if j < 0:
                return error(sql_error("no such column: {c}"))
            if seen.contains(c):
                return error(sql_error("duplicate column: {c}"))

            seen.add(c.clone())
            positions.append(j)

    let no_scope = plain_scope(List[Source](), 0)
    let no_row = List[Value]()
    let empty = List[List[Value]]()
    var added = List[List[Value]]()

    for exprs in rows:
        if exprs.length() != positions.length():
            return error(sql_error("wrong number of values"))

        var vals = List[Value]()
        for _j in 0..tbl.cols.length():
            vals.append(Value.VNull)

        for k in 0..exprs.length():
            let re = try resolve(exprs[k], no_scope, false)
            let v = try eval(re, no_row, empty)
            vals[positions[k]] = v

        try check_row(tbl.cols, vals)
        added.append(vals)

    try check_primary(tbl.cols, tbl.rows, added)

    let count = added.length()
    var updated = tbl
    for r in added:
        updated.rows.append(r.clone())
    db.add(name.clone(), updated)
    return ok("inserted {count}\n")

fn update_rows(
    var db: Map[String, Table], name: String, sets: List[Assign], cond: Optional[Expr]
) Result[String, SqlError]:
    let tbl = try fetch(db, name)
    var idxs = List[Int]()

    for a in sets:
        let j = col_index(tbl.cols, a.col)
        if j < 0:
            return error(sql_error("no such column: {a.col}"))

        idxs.append(j)

    let sc = plain_scope(table_scope(name, tbl.cols), 1)
    var exprs = List[Expr]()

    for a in sets:
        let re = try resolve(a.expr, sc, false)
        exprs.append(re)

    var cond_r: Optional[Expr] = none

    if let c = cond:
        let cr = try resolve(c, sc, false)
        cond_r = cr

    let empty = List[List[Value]]()
    var out = List[List[Value]]()
    var updated = 0

    for row in tbl.rows:
        var hit = true

        if let c = cond_r:
            let cv = try eval(c, row, empty)
            hit = try truth(cv)

        var newrow = row.clone()

        if hit:
            updated += 1

            var vals = List[Value]()

            for k in 0..exprs.length():
                let v = try eval(exprs[k], row, empty)
                vals.append(v)

            for k in 0..exprs.length():
                newrow[idxs[k]] = vals[k].clone()
            try check_row(tbl.cols, newrow)

        out.append(newrow)

    try check_primary(tbl.cols, List[List[Value]](), out)
    db.add(name.clone(), Table(cols: tbl.cols.clone(), rows: out))
    return ok("updated {updated}\n")

fn delete_rows(var db: Map[String, Table], name: String, cond: Optional[Expr]) Result[
    String, SqlError
]:
    let tbl = try fetch(db, name)
    let sc = plain_scope(table_scope(name, tbl.cols), 1)
    var cond_r: Optional[Expr] = none

    if let c = cond:
        let cr = try resolve(c, sc, false)
        cond_r = cr

    let empty = List[List[Value]]()
    var kept = List[List[Value]]()
    var deleted = 0

    for row in tbl.rows:
        var hit = true

        if let c = cond_r:
            let cv = try eval(c, row, empty)
            hit = try truth(cv)

        if hit:
            deleted += 1
        else:
            kept.append(row.clone())

    db.add(name.clone(), Table(cols: tbl.cols.clone(), rows: kept))
    return ok("deleted {deleted}\n")

fn execute(var db: Map[String, Table], st: Stmt) Result[String, SqlError]:
    match st:
        SCreate(name, cols):
            return create_table(var db, name.clone(), cols.clone())
        SDrop(name):
            return drop_table(var db, name.clone())
        SInsert(name, cols, rows):
            return insert_rows(var db, name.clone(), cols.clone(), rows.clone())
        SUpdate(name, sets, cond):
            return update_rows(var db, name.clone(), sets.clone(), cond.clone())
        SDelete(name, cond):
            return delete_rows(var db, name.clone(), cond.clone())
        SSelect(q):
            return run_select(db, q)

fn run_statement(var db: Map[String, Table], toks: List[Tok]) Result[String, SqlError]:
    var p = Cur(toks: toks.clone(), pos: [0])
    let st = try parse_statement(var p)
    if p.pos[0] != p.toks.length():
        return error(syntax_error())

    return execute(var db, st)

export fn main() Int:
    let raw = read_all(stdin()).get()
    let text = raw.decode_utf8().get("")
    let stmts = split_statements(lex(text.chars()))
    var db = Map[String, Table]()
    var out = List[String]()

    for toks in stmts:
        let r = run_statement(var db, toks)

        if r.is_error():
            out.append("error: {r.err().message()}\n")
        else:
            out.append(r.get().clone())

    stdout().write(out.join("")).get()
    return 0

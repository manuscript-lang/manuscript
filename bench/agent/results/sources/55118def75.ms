from "@std/io.ms" import stdin, stdout, read_all
from "@std/bytes.ms" import Bytes, BytesBuilder
from "@std/collections.ms" import range

# ---------------------------------------------------------------- errors
type SqlError:
    msg: String

impl Error for SqlError:
    def message() -> String:
        return self.msg

def sql_error(msg: String) -> SqlError:
    return SqlError(msg: msg)

def syntax_error() -> SqlError:
    return SqlError(msg: "syntax error")

def type_error() -> SqlError:
    return SqlError(msg: "type error")

def wrong_args(name: String) -> SqlError:
    return SqlError(msg: f"wrong number of arguments to {name}")

# ---------------------------------------------------------------- values
type Value:
    case VNull
    case VInt(n: Int)
    case VBool(truth: Bool)
    case VText(s: String)

def is_null(v: Value) -> Bool:
    match v:
        case VNull:
            return True
        case _:
            return False

def is_true(v: Value) -> Bool:
    match v:
        case VBool(truth):
            return truth
        case _:
            return False

def is_false(v: Value) -> Bool:
    match v:
        case VBool(truth):
            return not truth
        case _:
            return False

def is_bool_or_null(v: Value) -> Bool:
    match v:
        case VBool(truth):
            return True
        case VNull:
            return True
        case _:
            return False

def int_of(v: Value) -> Optional[Int]:
    match v:
        case VInt(n):
            return some(n)
        case _:
            return none

def text_of(v: Value) -> Optional[String]:
    match v:
        case VText(s):
            return some(s)
        case _:
            return none

def int_arg(v: Value) -> Result[Int, SqlError]:
    if let n = int_of(v):
        return ok(n)

    return error(type_error())

def text_arg(v: Value) -> Result[String, SqlError]:
    if let s = text_of(v):
        return ok(s)

    return error(type_error())

def value_rank(v: Value) -> Int:
    match v:
        case VNull:
            return 0
        case VBool(truth):
            return 1
        case VInt(n):
            return 2
        case VText(_):
            return 3

def int_key(v: Value) -> Int:
    match v:
        case VBool(truth):
            if truth:
                return 1

            return 0
        case VInt(n):
            return n
        case _:
            return 0

def min_int(a: Int, b: Int) -> Int:
    if a < b:
        return a

    return b

# Total order used for sorting, DISTINCT and key equality: NULL < BOOL < INT < TEXT.
def value_order(a: Value, b: Value) -> Int:
    let ra = value_rank(a)
    let rb = value_rank(b)
    if ra != rb:
        return ra.compare(rb)
    if ra == 3:
        return text_of(a).get().compare(text_of(b).get())

    return int_key(a).compare(int_key(b))

def value_equal(a: Value, b: Value) -> Bool:
    return value_order(a, b) == 0

def rows_equal(a: List[Value], b: List[Value]) -> Bool:
    if a.length() != b.length():
        return False

    for k in range(0, a.length()):
        if not value_equal(a[k], b[k]):
            return False
    return True

def contains_value(vals: List[Value], v: Value) -> Bool:
    for i in range(0, vals.length()):
        if value_equal(vals[i], v):
            return True
    return False

def nulls(n: Int) -> List[Value]:
    var out: List[Value] = []
    for i in range(0, n):
        out.append(VNull)
    return out

def value_text(v: Value) -> String:
    match v:
        case VNull:
            return "NULL"
        case VBool(truth):
            if truth:
                return "true"

            return "false"
        case VInt(n):
            return n.to_string_radix(10)
        case VText(s):
            return s

# Text is kept as UTF-8 strings; byte-level operations go through Bytes and fall back to '?' on invalid UTF-8.
def bytes_to_string(b: Bytes) -> String:
    if let s = b.decode_utf8():
        return s

    return "?"

# ---------------------------------------------------------------- operators on values
def negate(v: Value) -> Result[Value, SqlError]:
    if is_null(v):
        return ok(VNull)

    let n = try int_arg(v)
    return ok(VInt(n: 0 - n))

def logical_not(v: Value) -> Result[Value, SqlError]:
    if is_null(v):
        return ok(VNull)

    match v:
        case VBool(truth):
            return ok(VBool(truth: not truth))
        case _:
            return error(type_error())

def and_values(a: Value, b: Value) -> Result[Value, SqlError]:
    if not is_bool_or_null(a) or not is_bool_or_null(b):
        return error(type_error())
    if is_false(a) or is_false(b):
        return ok(VBool(truth: False))
    if is_null(a) or is_null(b):
        return ok(VNull)

    return ok(VBool(truth: True))

def or_values(a: Value, b: Value) -> Result[Value, SqlError]:
    if not is_bool_or_null(a) or not is_bool_or_null(b):
        return error(type_error())
    if is_true(a) or is_true(b):
        return ok(VBool(truth: True))
    if is_null(a) or is_null(b):
        return ok(VNull)

    return ok(VBool(truth: False))

def arith(op: String, a: Value, b: Value) -> Result[Value, SqlError]:
    if is_null(a) or is_null(b):
        return ok(VNull)

    if op == "||":
        if let x = text_of(a):
            if let y = text_of(b):
                return ok(VText(s: x.concat(y)))
        return error(type_error())

    if let x = int_of(a):
        if let y = int_of(b):
            if op == "+":
                return ok(VInt(n: x + y))
            if op == "-":
                return ok(VInt(n: x - y))
            if op == "*":
                return ok(VInt(n: x * y))
            if y == 0:
                return error(sql_error("division by zero"))
            if op == "/":
                return ok(VInt(n: x / y))

            return ok(VInt(n: x % y))

    return error(type_error())

# Ordering for SQL comparisons: only INT with INT and TEXT with TEXT.
def ordering(a: Value, b: Value) -> Result[Int, SqlError]:
    if let x = int_of(a):
        if let y = int_of(b):
            return ok(x.compare(y))
    if let x = text_of(a):
        if let y = text_of(b):
            return ok(x.compare(y))
    return error(type_error())

def compare_op(op: String, a: Value, b: Value) -> Result[Value, SqlError]:
    if is_null(a) or is_null(b):
        return ok(VNull)

    let c = try ordering(a, b)
    if op == "=":
        return ok(VBool(truth: c == 0))
    if op == "<>":
        return ok(VBool(truth: c != 0))
    if op == "<":
        return ok(VBool(truth: c < 0))
    if op == "<=":
        return ok(VBool(truth: c <= 0))
    if op == ">":
        return ok(VBool(truth: c > 0))

    return ok(VBool(truth: c >= 0))

def like_at(s: String, i: Int, p: String, j: Int) -> Bool:
    if j == p.byte_length():
        return i == s.byte_length()

    let pc = p.to_bytes().get(j)

    if pc == 37:
        for k in range(i, s.byte_length() + 1):
            if like_at(s, k, p, j + 1):
                return True
        return False

    if i >= s.byte_length():
        return False
    if pc == 95 or pc == s.to_bytes().get(i):
        return like_at(s, i + 1, p, j + 1)

    return False

def like_values(a: Value, b: Value, neg: Bool) -> Result[Value, SqlError]:
    if is_null(a) or is_null(b):
        return ok(VNull)

    if let s = text_of(a):
        if let p = text_of(b):
            return ok(VBool(truth: like_at(s, 0, p, 0) != neg))
    return error(type_error())

def ascii_case(s: String, to_upper: Bool) -> String:
    let src = s.to_bytes()
    var out = BytesBuilder()

    for i in range(0, src.length()):
        var c = src.get(i)
        if to_upper and c >= 97 and c <= 122:
            c = c - 32
        if not to_upper and c >= 65 and c <= 90:
            c = c + 32
        out.append(c)

    return bytes_to_string(out.build())

def substring(s: String, start: Int, len: Int) -> String:
    let src = s.to_bytes()
    var out = BytesBuilder()
    if len <= 0:
        return bytes_to_string(out.build())

    var first = start
    if first < 1:
        first = 1

    var last = start + len - 1
    if last > src.length():
        last = src.length()
    for k in range(first, last + 1):
        out.append(src.get(k - 1))
    return bytes_to_string(out.build())

# ---------------------------------------------------------------- functions
def is_aggregate(name: String) -> Bool:
    return name == "COUNT" or name == "SUM" or name == "MIN" or name == "MAX"

def is_scalar(name: String) -> Bool:
    return (
        name == "UPPER"
        or name == "LOWER"
        or name == "LENGTH"
        or name == "ABS"
        or name == "SUBSTR"
        or name == "COALESCE"
    )

# -1 means variadic (at least one argument).
def scalar_arity(name: String) -> Int:
    if name == "SUBSTR":
        return 3
    if name == "COALESCE":
        return -1

    return 1

def scalar_call(name: String, vals: List[Value]) -> Result[Value, SqlError]:
    if name == "COALESCE":
        for i in range(0, vals.length()):
            if not is_null(vals[i]):
                return ok(vals[i])
        return ok(VNull)

    for i in range(0, vals.length()):
        if is_null(vals[i]):
            return ok(VNull)

    if name == "UPPER" or name == "LOWER":
        let s = try text_arg(vals[0])
        return ok(VText(s: ascii_case(s, name == "UPPER")))

    if name == "LENGTH":
        let s = try text_arg(vals[0])
        return ok(VInt(n: s.byte_length()))

    if name == "ABS":
        let n = try int_arg(vals[0])
        if n < 0:
            return ok(VInt(n: 0 - n))

        return ok(VInt(n: n))

    let s = try text_arg(vals[0])
    let start = try int_arg(vals[1])
    let len = try int_arg(vals[2])
    return ok(VText(s: substring(s, start, len)))

def distinct_values(vals: List[Value]) -> List[Value]:
    var out: List[Value] = []
    for i in range(0, vals.length()):
        if not contains_value(out, vals[i]):
            out.append(vals[i])
    return out

# ---------------------------------------------------------------- names
def display_name(qual: String, name: String) -> String:
    if qual == "":
        return name

    return f"{qual}.{name}"

def resolve_col(
    scope: List[ScopeCol],
    qual: String,
    name: String
) -> Result[Int, SqlError]:
    var found = -1
    var hits = 0

    for i in range(0, scope.length()):
        if scope[i].name == name and (qual == "" or scope[i].alias == qual):
            if found < 0:
                found = i
            hits = hits + 1

    if hits == 0:
        return error(sql_error(f"no such column: {display_name(qual, name)}"))
    if hits > 1 and qual == "":
        return error(sql_error(f"ambiguous column: {name}"))

    return ok(found)

# ---------------------------------------------------------------- expressions
type Expr:
    case Lit(v: Value)
    case Col(qual: String, name: String)
    case Neg(e: Expr)
    case Not(e: Expr)
    case Arith(op: String, l: Expr, r: Expr)
    case Cmp(op: String, l: Expr, r: Expr)
    case And(l: Expr, r: Expr)
    case Or(l: Expr, r: Expr)
    case IsNull(e: Expr, neg: Bool)
    case Like(e: Expr, pattern: Expr, neg: Bool)
    case InList(e: Expr, items: List[Expr], neg: Bool)
    case Between(e: Expr, lo: Expr, hi: Expr, neg: Bool)
    case Call(name: String, args: List[Expr], distinct: Bool, star: Bool)

# What an expression is evaluated against: the scope names, the current joined row,
# and the rows of the current aggregation group (empty outside aggregation).
type Ctx:
    scope: List[ScopeCol]
    row: List[Value]
    group: List[List[Value]]

def aggregate(
    name: String,
    args: List[Expr],
    distinct: Bool,
    star: Bool,
    c: Ctx
) -> Result[Value, SqlError]:
    if star:
        return ok(VInt(n: c.group.length()))

    var vals: List[Value] = []

    for i in range(0, c.group.length()):
        let inner = Ctx(scope: c.scope.clone(), row: c.group[i].clone(), group: [])
        let v = try eval(args[0].clone(), inner)
        if not is_null(v):
            vals.append(v)

    if distinct:
        vals = distinct_values(vals)
    if name == "COUNT":
        return ok(VInt(n: vals.length()))
    if vals.is_empty():
        return ok(VNull)

    if name == "SUM":
        var total = 0

        for i in range(0, vals.length()):
            let n = try int_arg(vals[i])
            total = total + n

        return ok(VInt(n: total))

    for i in range(0, vals.length()):
        if not int_of(vals[i]).is_some() and not text_of(vals[i]).is_some():
            return error(type_error())

    var best = vals[0]

    for k in range(1, vals.length()):
        let order = try ordering(vals[k], best)
        if name == "MIN" and order < 0:
            best = vals[k]
        if name == "MAX" and order > 0:
            best = vals[k]

    return ok(best)

def eval(e: Expr, c: Ctx) -> Result[Value, SqlError]:
    match e:
        case Lit(v):
            return ok(v)
        case Col(qual, name):
            let idx = try resolve_col(c.scope, qual, name)
            return ok(c.row[idx])
        case Neg(x):
            let v = try eval(x, c)
            return negate(v)
        case Not(x):
            let v = try eval(x, c)
            return logical_not(v)
        case Arith(op, l, r):
            let a = try eval(l, c)
            let b = try eval(r, c)
            return arith(op, a, b)
        case Cmp(op, l, r):
            let a = try eval(l, c)
            let b = try eval(r, c)
            return compare_op(op, a, b)
        case And(l, r):
            let a = try eval(l, c)
            if is_false(a):
                return ok(VBool(truth: False))

            let b = try eval(r, c)
            return and_values(a, b)
        case Or(l, r):
            let a = try eval(l, c)
            if is_true(a):
                return ok(VBool(truth: True))

            let b = try eval(r, c)
            return or_values(a, b)
        case IsNull(x, neg):
            let v = try eval(x, c)
            return ok(VBool(truth: is_null(v) != neg))
        case Like(x, pattern, neg):
            let a = try eval(x, c)
            let b = try eval(pattern, c)
            return like_values(a, b, neg)
        case InList(x, items, neg):
            let a = try eval(x, c)
            var found = False
            var sawnull = False

            for i in range(0, items.length()):
                let v = try eval(items[i].clone(), c)

                if is_null(v):
                    sawnull = True
                elif not is_null(a):
                    let order = try ordering(a, v)
                    if order == 0:
                        found = True

            if is_null(a):
                return ok(VNull)

            var result = VBool(truth: False)

            if found:
                result = VBool(truth: True)
            elif sawnull:
                result = VNull

            if neg:
                return logical_not(result)

            return ok(result)
        case Between(x, lo, hi, neg):
            let a = try eval(x, c)
            let low = try eval(lo, c)
            let high = try eval(hi, c)
            let ge = try compare_op(">=", a, low)
            let le = try compare_op("<=", a, high)
            let both = try and_values(ge, le)
            if neg:
                return logical_not(both)

            return ok(both)
        case Call(name, args, distinct, star):
            if is_aggregate(name):
                return aggregate(name, args, distinct, star, c)

            var vals: List[Value] = []

            for i in range(0, args.length()):
                let v = try eval(args[i].clone(), c)
                vals.append(v)

            return scalar_call(name, vals)

def contains_agg(e: Expr) -> Bool:
    match e:
        case Neg(x):
            return contains_agg(x)
        case Not(x):
            return contains_agg(x)
        case IsNull(x, neg):
            return contains_agg(x)
        case Arith(op, l, r):
            return contains_agg(l) or contains_agg(r)
        case Cmp(op, l, r):
            return contains_agg(l) or contains_agg(r)
        case And(l, r):
            return contains_agg(l) or contains_agg(r)
        case Or(l, r):
            return contains_agg(l) or contains_agg(r)
        case Like(x, pattern, neg):
            return contains_agg(x) or contains_agg(pattern)
        case InList(x, items, neg):
            if contains_agg(x):
                return True

            for i in range(0, items.length()):
                if contains_agg(items[i].clone()):
                    return True
            return False
        case Between(x, lo, hi, neg):
            return contains_agg(x) or contains_agg(lo) or contains_agg(hi)
        case Call(name, args, distinct, star):
            if is_aggregate(name):
                return True

            for i in range(0, args.length()):
                if contains_agg(args[i].clone()):
                    return True
            return False
        case _:
            return False

# Static checks, in the order the spec names them. `in_agg` is true inside an aggregate's arguments.
type Check:
    scope: List[ScopeCol]
    allow_agg: Bool
    aggregated: Bool
    group_idx: List[Int]

def check_expr(e: Expr, c: Check, in_agg: Bool) -> Result[Unit, SqlError]:
    match e:
        case Col(qual, name):
            let idx = try resolve_col(c.scope, qual, name)
            if c.aggregated and not in_agg and not c.group_idx.contains(idx):
                return error(
                    sql_error(
                        f"column {display_name(qual, name)} must appear in GROUP BY"
                    )
                )

            return ok(unit_value())
        case Neg(x):
            return check_expr(x, c, in_agg)
        case Not(x):
            return check_expr(x, c, in_agg)
        case IsNull(x, neg):
            return check_expr(x, c, in_agg)
        case Arith(op, l, r):
            try check_expr(l, c, in_agg)
            return check_expr(r, c, in_agg)
        case Cmp(op, l, r):
            try check_expr(l, c, in_agg)
            return check_expr(r, c, in_agg)
        case And(l, r):
            try check_expr(l, c, in_agg)
            return check_expr(r, c, in_agg)
        case Or(l, r):
            try check_expr(l, c, in_agg)
            return check_expr(r, c, in_agg)
        case Like(x, pattern, neg):
            try check_expr(x, c, in_agg)
            return check_expr(pattern, c, in_agg)
        case InList(x, items, neg):
            try check_expr(x, c, in_agg)
            for i in range(0, items.length()):
                try check_expr(items[i].clone(), c, in_agg)
            return ok(unit_value())
        case Between(x, lo, hi, neg):
            try check_expr(x, c, in_agg)
            try check_expr(lo, c, in_agg)
            return check_expr(hi, c, in_agg)
        case Call(name, args, distinct, star):
            if is_aggregate(name):
                if not c.allow_agg or in_agg:
                    return error(sql_error("misuse of aggregate"))

                if star:
                    if name != "COUNT" or distinct:
                        return error(wrong_args(name))
                elif args.length() != 1:
                    return error(wrong_args(name))

                for i in range(0, args.length()):
                    try check_expr(args[i].clone(), c, True)
                return ok(unit_value())

            if not is_scalar(name):
                return error(sql_error(f"no such function: {name}"))
            if star:
                return error(wrong_args(name))

            let want = scalar_arity(name)
            if want >= 0 and args.length() != want:
                return error(wrong_args(name))
            if want < 0 and args.length() == 0:
                return error(wrong_args(name))

            for i in range(0, args.length()):
                try check_expr(args[i].clone(), c, in_agg)
            return ok(unit_value())
        case _:
            return ok(unit_value())

def column_index(cols: List[ColDef], name: String) -> Int:
    for k in range(0, cols.length()):
        if cols[k].name == name:
            return k
    return -1

def primary_index(cols: List[ColDef]) -> Int:
    for k in range(0, cols.length()):
        if cols[k].primary:
            return k
    return -1

def table_scope(alias: String, cols: List[ColDef]) -> List[ScopeCol]:
    var out: List[ScopeCol] = []
    for k in range(0, cols.length()):
        out.append(ScopeCol(alias: alias, name: cols[k].name))
    return out

def alias_used(scope: List[ScopeCol], alias: String) -> Bool:
    for k in range(0, scope.length()):
        if scope[k].alias == alias:
            return True
    return False

# ---------------------------------------------------------------- statements: data model
type ScopeCol:
    alias: String
    name: String

type ColDef:
    name: String
    kind: String
    primary: Bool
    notnull: Bool

type Table:
    name: String
    cols: List[ColDef]
    rows: List[List[Value]]

type TableRef:
    name: String
    alias: String

type Join:
    left: Bool
    tref: TableRef
    on: Expr

type SelItem:
    case ItemStar
    case ItemTableStar(table: String)
    case ItemExpr(e: Expr, alias: String)

type OrderItem:
    e: Expr
    desc: Bool

type OutCol:
    e: Expr
    name: String

type Select:
    distinct: Bool
    items: List[SelItem]
    from_ref: Optional[TableRef]
    joins: List[Join]
    where_cond: Optional[Expr]
    group_by: List[Expr]
    having_cond: Optional[Expr]
    order_by: List[OrderItem]
    limit_n: Optional[Int]
    offset_n: Int

type Stmt:
    case Create(name: String, cols: List[ColDef])
    case Drop(name: String)
    case Insert(table: String, names: Optional[List[String]], rows: List[List[Expr]])
    case Update(
        table: String,
        names: List[String],
        exprs: List[Expr],
        cond: Optional[Expr]
    )
    case Delete(table: String, cond: Optional[Expr])
    case Query(sel: Select)

# ---------------------------------------------------------------- lexer
type Token:
    kind: String
    text: String
    num: Int
    data: String

type Span:
    start: Int
    stop: Int

# A Unit value for Result[Unit, SqlError] successes.
def unit_value() -> Unit:
    var scratch: List[Int] = []
    return scratch.append(0)

def is_digit(c: Int) -> Bool:
    return c >= 48 and c <= 57

def is_alpha(c: Int) -> Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

def is_alnum(c: Int) -> Bool:
    return is_alpha(c) or is_digit(c)

def is_space(c: Int) -> Bool:
    return c == 32 or c == 9 or c == 13 or c == 10

def is_keyword(word: String) -> Bool:
    return [
        "SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET",
        "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE",
        "IN", "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"
    ].contains(word)

# Splits the script at semicolons that are outside string literals and comments.
def split_statements(src: List[Int]) -> List[Span]:
    var spans: List[Span] = []
    let n = src.length()
    var start = 0
    var i = 0

    while i < n:
        let c = src[i]

        if c == 39:
            i += 1

            var closed = False

            while not closed and i < n:
                if src[i] == 39:
                    if i + 1 < n and src[i + 1] == 39:
                        i += 2
                    else:
                        closed = True
                else:
                    i += 1

            if closed:
                i += 1
        elif c == 45 and i + 1 < n and src[i + 1] == 45:
            while i < n and src[i] != 10:
                i += 1
        elif c == 59:
            spans.append(Span(start: start, stop: i))
            i += 1
            start = i
        else:
            i += 1

    spans.append(Span(start: start, stop: n))
    return spans

def operator_at(src: List[Int], i: Int, stop: Int) -> String:
    let c = src[i]
    var next = -1
    if i + 1 < stop:
        next = src[i + 1]
    if c == 60 and next == 61:
        return "<="
    if c == 60 and next == 62:
        return "<>"
    if c == 62 and next == 61:
        return ">="
    if c == 33 and next == 61:
        return "<>"
    if c == 124 and next == 124:
        return "||"
    if c == 61:
        return "="
    if c == 60:
        return "<"
    if c == 62:
        return ">"
    if c == 43:
        return "+"
    if c == 45:
        return "-"
    if c == 42:
        return "*"
    if c == 47:
        return "/"
    if c == 37:
        return "%"
    if c == 40:
        return "("
    if c == 41:
        return ")"
    if c == 44:
        return ","
    if c == 46:
        return "."

    return ""

def lex(src: List[Int], start: Int, stop: Int) -> Result[List[Token], SqlError]:
    var toks: List[Token] = []
    var i = start

    while i < stop:
        let c = src[i]

        if is_space(c):
            i += 1
        elif c == 45 and i + 1 < stop and src[i + 1] == 45:
            while i < stop and src[i] != 10:
                i += 1
        elif is_alpha(c):
            var word = BytesBuilder()

            while i < stop and is_alnum(src[i]):
                word.append(src[i])
                i += 1

            let text = bytes_to_string(word.build())
            let upper = text.upper()

            if is_keyword(upper):
                toks.append(Token(kind: "kw", text: upper, num: 0, data: ""))
            else:
                toks.append(Token(kind: "ident", text: text, num: 0, data: ""))
        elif is_digit(c):
            var value = 0

            while i < stop and is_digit(src[i]):
                let d = src[i] - 48
                if value > (9223372036854775807 - d) / 10:
                    return error(syntax_error())

                value = value * 10 + d
                i += 1

            toks.append(Token(kind: "int", text: "", num: value, data: ""))
        elif c == 39:
            var text = BytesBuilder()
            i += 1

            var closed = False

            while not closed:
                if i >= stop:
                    return error(syntax_error())

                if src[i] == 39:
                    if i + 1 < stop and src[i + 1] == 39:
                        text.append(39)
                        i += 2
                    else:
                        closed = True
                        i += 1
                else:
                    text.append(src[i])
                    i += 1

            toks.append(
                Token(
                    kind: "str", text: "", num: 0, data: bytes_to_string(text.build())
                )
            )
        else:
            let op = operator_at(src, i, stop)
            if op == "":
                return error(syntax_error())

            toks.append(Token(kind: "op", text: op, num: 0, data: ""))
            i += op.byte_length()

    return ok(toks)

# ---------------------------------------------------------------- parser
type Parser:
    toks: List[Token]
    pos: Int

def tok_is(p: Parser, ahead: Int, kind: String, text: String) -> Bool:
    let k = p.pos + ahead
    if k >= p.toks.length():
        return False

    return p.toks[k].kind == kind and p.toks[k].text == text

def at_kind(p: Parser, ahead: Int, kind: String) -> Bool:
    let k = p.pos + ahead
    if k >= p.toks.length():
        return False

    return p.toks[k].kind == kind

def at_kw(p: Parser, word: String) -> Bool:
    return tok_is(p, 0, "kw", word)

def at_op(p: Parser, op: String) -> Bool:
    return tok_is(p, 0, "op", op)

def expect_kw(var p: Parser, word: String) -> Result[Unit, SqlError]:
    if not at_kw(p, word):
        return error(syntax_error())

    p.pos = p.pos + 1
    return ok(unit_value())

def expect_op(var p: Parser, op: String) -> Result[Unit, SqlError]:
    if not at_op(p, op):
        return error(syntax_error())

    p.pos = p.pos + 1
    return ok(unit_value())

def expect_ident(var p: Parser) -> Result[String, SqlError]:
    if not at_kind(p, 0, "ident"):
        return error(syntax_error())

    let name = p.toks[p.pos].text
    p.pos = p.pos + 1
    return ok(name)

def expect_int(var p: Parser) -> Result[Int, SqlError]:
    if not at_kind(p, 0, "int"):
        return error(syntax_error())

    let n = p.toks[p.pos].num
    p.pos = p.pos + 1
    return ok(n)

def parse_colref(var p: Parser) -> Result[Expr, SqlError]:
    let first = try expect_ident(var p)

    if at_op(p, "."):
        p.pos = p.pos + 1

        let second = try expect_ident(var p)
        return ok(Col(qual: first, name: second))

    return ok(Col(qual: "", name: first))

def parse_call(var p: Parser, name: String) -> Result[Expr, SqlError]:
    var distinct = False
    var star = False
    var args: List[Expr] = []

    if at_kw(p, "DISTINCT"):
        distinct = True
        p.pos = p.pos + 1

    if at_op(p, "*"):
        star = True
        p.pos = p.pos + 1
    elif not at_op(p, ")"):
        let first = try parse_expr(var p)
        args.append(first)

        while at_op(p, ","):
            p.pos = p.pos + 1

            let more = try parse_expr(var p)
            args.append(more)

    if distinct and args.is_empty() and not star:
        return error(syntax_error())

    try expect_op(var p, ")")
    return ok(Call(name: name, args: args, distinct: distinct, star: star))

def parse_primary(var p: Parser) -> Result[Expr, SqlError]:
    if p.pos >= p.toks.length():
        return error(syntax_error())

    let t = p.toks[p.pos]

    if t.kind == "int":
        p.pos = p.pos + 1
        return ok(Lit(v: VInt(n: t.num)))

    if t.kind == "str":
        p.pos = p.pos + 1
        return ok(Lit(v: VText(s: t.data)))

    if t.kind == "kw" and t.text == "NULL":
        p.pos = p.pos + 1
        return ok(Lit(v: VNull))

    if t.kind == "op" and t.text == "(":
        p.pos = p.pos + 1

        let e = try parse_expr(var p)
        try expect_op(var p, ")")
        return ok(e)

    if t.kind == "ident":
        if tok_is(p, 1, "op", "("):
            p.pos = p.pos + 2
            return parse_call(var p, t.text.upper())

        return parse_colref(var p)

    return error(syntax_error())

def parse_unary(var p: Parser) -> Result[Expr, SqlError]:
    if at_op(p, "-"):
        p.pos = p.pos + 1

        let e = try parse_unary(var p)
        return ok(Neg(e: e))

    return parse_primary(var p)

def parse_mul(var p: Parser) -> Result[Expr, SqlError]:
    var left = try parse_unary(var p)

    while at_op(p, "*") or at_op(p, "/") or at_op(p, "%"):
        let op = p.toks[p.pos].text
        p.pos = p.pos + 1

        let right = try parse_unary(var p)
        left = Arith(op: op, l: left, r: right)

    return ok(left)

def parse_add(var p: Parser) -> Result[Expr, SqlError]:
    var left = try parse_mul(var p)

    while at_op(p, "+") or at_op(p, "-") or at_op(p, "||"):
        let op = p.toks[p.pos].text
        p.pos = p.pos + 1

        let right = try parse_mul(var p)
        left = Arith(op: op, l: left, r: right)

    return ok(left)

def parse_cmp(var p: Parser) -> Result[Expr, SqlError]:
    let left = try parse_add(var p)
    var op = ""
    for candidate in ["=", "<>", "<", "<=", ">", ">="]:
        if at_op(p, candidate):
            op = candidate

    if op != "":
        p.pos = p.pos + 1

        let right = try parse_add(var p)
        return ok(Cmp(op: op, l: left, r: right))

    if at_kw(p, "IS"):
        p.pos = p.pos + 1

        var neg = False

        if at_kw(p, "NOT"):
            neg = True
            p.pos = p.pos + 1

        try expect_kw(var p, "NULL")
        return ok(IsNull(e: left, neg: neg))

    var neg = False

    if at_kw(p, "NOT"):
        neg = True
        p.pos = p.pos + 1
        if not (at_kw(p, "LIKE") or at_kw(p, "IN") or at_kw(p, "BETWEEN")):
            return error(syntax_error())

    if at_kw(p, "LIKE"):
        p.pos = p.pos + 1

        let pattern = try parse_add(var p)
        return ok(Like(e: left, pattern: pattern, neg: neg))

    if at_kw(p, "IN"):
        p.pos = p.pos + 1
        try expect_op(var p, "(")

        var items: List[Expr] = []
        let first = try parse_expr(var p)
        items.append(first)

        while at_op(p, ","):
            p.pos = p.pos + 1

            let more = try parse_expr(var p)
            items.append(more)

        try expect_op(var p, ")")
        return ok(InList(e: left, items: items, neg: neg))

    if at_kw(p, "BETWEEN"):
        p.pos = p.pos + 1

        let lo = try parse_add(var p)
        try expect_kw(var p, "AND")

        let hi = try parse_add(var p)
        return ok(Between(e: left, lo: lo, hi: hi, neg: neg))

    return ok(left)

def parse_not(var p: Parser) -> Result[Expr, SqlError]:
    if at_kw(p, "NOT"):
        p.pos = p.pos + 1

        let e = try parse_not(var p)
        return ok(Not(e: e))

    return parse_cmp(var p)

def parse_and(var p: Parser) -> Result[Expr, SqlError]:
    var left = try parse_not(var p)

    while at_kw(p, "AND"):
        p.pos = p.pos + 1

        let right = try parse_not(var p)
        left = And(l: left, r: right)

    return ok(left)

def parse_expr(var p: Parser) -> Result[Expr, SqlError]:
    var left = try parse_and(var p)

    while at_kw(p, "OR"):
        p.pos = p.pos + 1

        let right = try parse_and(var p)
        left = Or(l: left, r: right)

    return ok(left)

def parse_row(var p: Parser) -> Result[List[Expr], SqlError]:
    try expect_op(var p, "(")

    var exprs: List[Expr] = []
    let first = try parse_expr(var p)
    exprs.append(first)

    while at_op(p, ","):
        p.pos = p.pos + 1

        let more = try parse_expr(var p)
        exprs.append(more)

    try expect_op(var p, ")")
    return ok(exprs)

def parse_coldef(var p: Parser) -> Result[ColDef, SqlError]:
    let name = try expect_ident(var p)
    let kind = try expect_ident(var p)
    let upper = kind.upper()
    if upper != "INT" and upper != "TEXT":
        return error(syntax_error())

    var primary = False
    var notnull = False
    var more = True

    while more:
        if at_kw(p, "PRIMARY"):
            p.pos = p.pos + 1
            try expect_kw(var p, "KEY")
            primary = True
            notnull = True
        elif at_kw(p, "NOT"):
            p.pos = p.pos + 1
            try expect_kw(var p, "NULL")
            notnull = True
        else:
            more = False

    return ok(ColDef(name: name, kind: upper, primary: primary, notnull: notnull))

def parse_create(var p: Parser) -> Result[Stmt, SqlError]:
    try expect_kw(var p, "CREATE")
    try expect_kw(var p, "TABLE")

    let name = try expect_ident(var p)
    try expect_op(var p, "(")

    var cols: List[ColDef] = []
    let first = try parse_coldef(var p)
    cols.append(first)

    while at_op(p, ","):
        p.pos = p.pos + 1

        let more = try parse_coldef(var p)
        cols.append(more)

    try expect_op(var p, ")")
    return ok(Create(name: name, cols: cols))

def parse_drop(var p: Parser) -> Result[Stmt, SqlError]:
    try expect_kw(var p, "DROP")
    try expect_kw(var p, "TABLE")

    let name = try expect_ident(var p)
    return ok(Drop(name: name))

def parse_insert(var p: Parser) -> Result[Stmt, SqlError]:
    try expect_kw(var p, "INSERT")
    try expect_kw(var p, "INTO")

    let name = try expect_ident(var p)
    var names: Optional[List[String]] = none

    if at_op(p, "("):
        p.pos = p.pos + 1

        var list: List[String] = []
        let first = try expect_ident(var p)
        list.append(first)

        while at_op(p, ","):
            p.pos = p.pos + 1

            let more = try expect_ident(var p)
            list.append(more)

        try expect_op(var p, ")")
        names = some(list)

    try expect_kw(var p, "VALUES")

    var rows: List[List[Expr]] = []
    let first_row = try parse_row(var p)
    rows.append(first_row)

    while at_op(p, ","):
        p.pos = p.pos + 1

        let more = try parse_row(var p)
        rows.append(more)

    return ok(Insert(table: name, names: names, rows: rows))

def parse_update(var p: Parser) -> Result[Stmt, SqlError]:
    try expect_kw(var p, "UPDATE")

    let name = try expect_ident(var p)
    try expect_kw(var p, "SET")

    var names: List[String] = []
    var exprs: List[Expr] = []
    var more = True

    while more:
        let col = try expect_ident(var p)
        try expect_op(var p, "=")

        let e = try parse_expr(var p)
        names.append(col)
        exprs.append(e)

        if at_op(p, ","):
            p.pos = p.pos + 1
        else:
            more = False

    var cond: Optional[Expr] = none

    if at_kw(p, "WHERE"):
        p.pos = p.pos + 1

        let w = try parse_expr(var p)
        cond = some(w)

    return ok(Update(table: name, names: names, exprs: exprs, cond: cond))

def parse_delete(var p: Parser) -> Result[Stmt, SqlError]:
    try expect_kw(var p, "DELETE")
    try expect_kw(var p, "FROM")

    let name = try expect_ident(var p)
    var cond: Optional[Expr] = none

    if at_kw(p, "WHERE"):
        p.pos = p.pos + 1

        let w = try parse_expr(var p)
        cond = some(w)

    return ok(Delete(table: name, cond: cond))

def parse_tref(var p: Parser) -> Result[TableRef, SqlError]:
    let name = try expect_ident(var p)
    var alias = name

    if at_kw(p, "AS"):
        p.pos = p.pos + 1
        alias = try expect_ident(var p)
    elif at_kind(p, 0, "ident"):
        alias = try expect_ident(var p)

    return ok(TableRef(name: name, alias: alias))

def parse_join(var p: Parser) -> Result[Join, SqlError]:
    var left = False

    if at_kw(p, "LEFT"):
        left = True
        p.pos = p.pos + 1
    elif at_kw(p, "INNER"):
        p.pos = p.pos + 1

    try expect_kw(var p, "JOIN")

    let tref = try parse_tref(var p)
    try expect_kw(var p, "ON")

    let on = try parse_expr(var p)
    return ok(Join(left: left, tref: tref, on: on))

def parse_item(var p: Parser) -> Result[SelItem, SqlError]:
    if at_op(p, "*"):
        p.pos = p.pos + 1
        return ok(ItemStar)

    if at_kind(p, 0, "ident") and tok_is(p, 1, "op", ".") and tok_is(p, 2, "op", "*"):
        let table = p.toks[p.pos].text
        p.pos = p.pos + 3
        return ok(ItemTableStar(table: table))

    let e = try parse_expr(var p)
    var alias = ""

    if at_kw(p, "AS"):
        p.pos = p.pos + 1
        alias = try expect_ident(var p)

    return ok(ItemExpr(e: e, alias: alias))

def parse_order_item(var p: Parser) -> Result[OrderItem, SqlError]:
    let e = try parse_expr(var p)
    var desc = False

    if at_kw(p, "DESC"):
        desc = True
        p.pos = p.pos + 1
    elif at_kw(p, "ASC"):
        p.pos = p.pos + 1

    return ok(OrderItem(e: e, desc: desc))

def parse_select(var p: Parser) -> Result[Select, SqlError]:
    try expect_kw(var p, "SELECT")

    var distinct = False

    if at_kw(p, "DISTINCT"):
        distinct = True
        p.pos = p.pos + 1

    var items: List[SelItem] = []
    let first = try parse_item(var p)
    items.append(first)

    while at_op(p, ","):
        p.pos = p.pos + 1

        let more = try parse_item(var p)
        items.append(more)

    var from_ref: Optional[TableRef] = none
    var joins: List[Join] = []

    if at_kw(p, "FROM"):
        p.pos = p.pos + 1

        let base = try parse_tref(var p)
        from_ref = some(base)

        while at_kw(p, "JOIN") or at_kw(p, "INNER") or at_kw(p, "LEFT"):
            let join = try parse_join(var p)
            joins.append(join)

    var where_cond: Optional[Expr] = none

    if at_kw(p, "WHERE"):
        p.pos = p.pos + 1

        let w = try parse_expr(var p)
        where_cond = some(w)

    var group_by: List[Expr] = []

    if at_kw(p, "GROUP"):
        p.pos = p.pos + 1
        try expect_kw(var p, "BY")

        let g0 = try parse_colref(var p)
        group_by.append(g0)

        while at_op(p, ","):
            p.pos = p.pos + 1

            let g = try parse_colref(var p)
            group_by.append(g)

    var having_cond: Optional[Expr] = none

    if at_kw(p, "HAVING"):
        p.pos = p.pos + 1

        let h = try parse_expr(var p)
        having_cond = some(h)

    var order_by: List[OrderItem] = []

    if at_kw(p, "ORDER"):
        p.pos = p.pos + 1
        try expect_kw(var p, "BY")

        let o0 = try parse_order_item(var p)
        order_by.append(o0)

        while at_op(p, ","):
            p.pos = p.pos + 1

            let o = try parse_order_item(var p)
            order_by.append(o)

    var limit_n: Optional[Int] = none
    var offset_n = 0

    if at_kw(p, "LIMIT"):
        p.pos = p.pos + 1

        let n = try expect_int(var p)
        limit_n = some(n)

        if at_kw(p, "OFFSET"):
            p.pos = p.pos + 1
            offset_n = try expect_int(var p)

    return ok(
        Select(
            distinct: distinct, items: items, from_ref: from_ref, joins: joins,
            where_cond: where_cond, group_by: group_by, having_cond: having_cond,
            order_by: order_by, limit_n: limit_n, offset_n: offset_n
        )
    )

def parse_statement(var p: Parser) -> Result[Stmt, SqlError]:
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
        let sel = try parse_select(var p)
        return ok(Query(sel: sel))

    return error(syntax_error())

# ---------------------------------------------------------------- SELECT execution
type Group:
    key: List[Value]
    rows: List[List[Value]]

def out_name(e: Expr, alias: String) -> String:
    if alias != "":
        return alias

    match e:
        case Col(qual, name):
            return name
        case _:
            return "?column?"

def star_columns(scope: List[ScopeCol], table: String) -> List[OutCol]:
    var out: List[OutCol] = []
    for k in range(0, scope.length()):
        if table == "" or scope[k].alias == table:
            out.append(
                OutCol(
                    e: Col(
                        qual: scope[k].alias, name: scope[k].name
                    ),
                    name: scope[k].name
                )
            )
    return out

def lit_int(e: Expr) -> Optional[Int]:
    match e:
        case Lit(v):
            return int_of(v)
        case _:
            return none

def plain_name(e: Expr) -> Optional[String]:
    match e:
        case Col(qual, name):
            if qual == "":
                return some(name)

            return none
        case _:
            return none

# Returns the output column an ORDER BY item names, or -1 when it is an expression.
def order_target(outs: List[OutCol], e: Expr) -> Result[Int, SqlError]:
    if let pos = lit_int(e.clone()):
        if pos < 1 or pos > outs.length():
            return error(sql_error("bad ORDER BY position"))

        return ok(pos - 1)

    if let name = plain_name(e.clone()):
        for i in range(0, outs.length()):
            if outs[i].name == name:
                return ok(i)
    return ok(-1)

def find_table(tables: List[Table], name: String) -> Int:
    for i in range(0, tables.length()):
        if tables[i].name == name:
            return i
    return -1

def join_rows(
    left_rows: List[List[Value]],
    right_rows: List[List[Value]],
    on: Expr,
    scope: List[ScopeCol],
    outer: Bool,
    width: Int
) -> Result[List[List[Value]], SqlError]:
    var next: List[List[Value]] = []

    for i in range(0, left_rows.length()):
        var matched = False

        for j in range(0, right_rows.length()):
            let combined = left_rows[i].concat(right_rows[j])
            let cctx = Ctx(scope: scope.clone(), row: combined.clone(), group: [])
            let cond = try eval(on.clone(), cctx)

            if is_true(cond):
                matched = True
                next.append(combined)

        if outer and not matched:
            next.append(left_rows[i].concat(nulls(width)))

    return ok(next)

def group_key(row: List[Value], idx: List[Int]) -> List[Value]:
    var key: List[Value] = []
    for i in range(0, idx.length()):
        key.append(row[idx[i]])
    return key

def find_group(groups: List[Group], key: List[Value]) -> Int:
    for g in range(0, groups.length()):
        if rows_equal(groups[g].key.clone(), key.clone()):
            return g
    return -1

def compare_ids(a: Int, b: Int, keys: List[List[Value]], descs: List[Bool]) -> Int:
    for k in range(0, descs.length()):
        var c = value_order(keys[a][k], keys[b][k])
        if descs[k]:
            c = 0 - c
        if c != 0:
            return c

    return a.compare(b)

# Stable merge sort of row ids by their ORDER BY keys.
def sort_ids(ids: List[Int], keys: List[List[Value]], descs: List[Bool]) -> List[Int]:
    if ids.length() < 2:
        return ids

    let mid = ids.length() / 2
    let left = sort_ids(ids.take(mid), keys.clone(), descs.clone())
    let right = sort_ids(ids.drop(mid), keys.clone(), descs.clone())
    var merged: List[Int] = []
    var i = 0
    var j = 0

    while i < left.length() and j < right.length():
        if compare_ids(left[i], right[j], keys.clone(), descs.clone()) <= 0:
            merged.append(left[i])
            i = i + 1
        else:
            merged.append(right[j])
            j = j + 1

    while i < left.length():
        merged.append(left[i])
        i = i + 1

    while j < right.length():
        merged.append(right[j])
        j = j + 1

    return merged

def write_row(var out: BytesBuilder, vals: List[Value]) -> Unit:
    for k in range(0, vals.length()):
        if k > 0:
            out.append(124)
        out.concat(value_text(vals[k]).to_bytes())

    out.append(10)

def emit(var out: BytesBuilder, line: String) -> Unit:
    out.concat(line.to_bytes())
    out.append(10)

def run_select(
    s: Select,
    tables: List[Table],
    var out: BytesBuilder
) -> Result[Int, SqlError]:
    var refs: List[TableRef] = []
    if s.from_ref.is_some():
        refs.append(s.from_ref.get().clone())
    for j in range(0, s.joins.length()):
        refs.append(s.joins[j].tref.clone())

    # Tables and scope, in FROM/JOIN order.
    var scope: List[ScopeCol] = []
    var ref_tables: List[Int] = []
    var prefixes: List[List[ScopeCol]] = []

    for r in range(0, refs.length()):
        let ti = find_table(tables, refs[r].name)
        if ti < 0:
            return error(sql_error(f"no such table: {refs[r].name}"))
        if alias_used(scope, refs[r].alias):
            return error(sql_error(f"duplicate alias: {refs[r].alias}"))

        scope = scope.concat(table_scope(refs[r].alias, tables[ti].cols.clone()))
        ref_tables.append(ti)
        prefixes.append(scope.clone())

    # JOIN conditions see the tables joined up to them.
    for j in range(0, s.joins.length()):
        let jc = Check(
            scope: prefixes[j + 1].clone(), allow_agg: False, aggregated: False,
            group_idx: []
        )
        try check_expr(s.joins[j].on.clone(), jc, False)

    # Stars, then GROUP BY, WHERE, select items, HAVING, ORDER BY.
    var outs: List[OutCol] = []

    for i in range(0, s.items.length()):
        match s.items[i].clone():
            case ItemStar:
                outs = outs.concat(star_columns(scope.clone(), ""))
            case ItemTableStar(table):
                if not alias_used(scope, table):
                    return error(sql_error(f"no such table: {table}"))

                outs = outs.concat(star_columns(scope.clone(), table))
            case ItemExpr(e, alias):
                outs.append(OutCol(e: e.clone(), name: out_name(e.clone(), alias)))

    var group_idx: List[Int] = []

    for g in range(0, s.group_by.length()):
        match s.group_by[g].clone():
            case Col(qual, name):
                let idx = try resolve_col(scope.clone(), qual, name)
                group_idx.append(idx)
            case _:
                return error(syntax_error())

    if s.where_cond.is_some():
        let wc = Check(
            scope: scope.clone(), allow_agg: False, aggregated: False, group_idx: []
        )
        try check_expr(s.where_cond.get().clone(), wc, False)

    let has_group = s.group_by.length() > 0
    var aggregated = has_group or s.having_cond.is_some()
    for i in range(0, outs.length()):
        if contains_agg(outs[i].e.clone()):
            aggregated = True
    for i in range(0, s.order_by.length()):
        if contains_agg(s.order_by[i].e.clone()):
            aggregated = True

    for i in range(0, outs.length()):
        let oc = Check(
            scope: scope.clone(), allow_agg: True, aggregated: aggregated,
            group_idx: group_idx.clone()
        )
        try check_expr(outs[i].e.clone(), oc, False)

    if s.having_cond.is_some():
        let hc = Check(
            scope: scope.clone(), allow_agg: True, aggregated: aggregated,
            group_idx: group_idx.clone()
        )
        try check_expr(s.having_cond.get().clone(), hc, False)

    var order_out: List[Int] = []

    for i in range(0, s.order_by.length()):
        let target = try order_target(outs.clone(), s.order_by[i].e.clone())

        if target < 0:
            let rc = Check(
                scope: scope.clone(), allow_agg: True, aggregated: aggregated,
                group_idx: group_idx.clone()
            )
            try check_expr(s.order_by[i].e.clone(), rc, False)

        order_out.append(target)

    # Rows: FROM, then each JOIN.
    var rows: List[List[Value]] = []

    if refs.length() == 0:
        rows.append([])
    else:
        rows = tables[ref_tables[0]].rows.clone()

    for j in range(0, s.joins.length()):
        let jt = ref_tables[j + 1]
        rows = try join_rows(
            rows, tables[jt].rows.clone(), s.joins[j].on.clone(),
            prefixes[j + 1].clone(), s.joins[j].left, tables[jt].cols.length()
        )

    var kept: List[List[Value]] = []

    for i in range(0, rows.length()):
        var keep = True

        if s.where_cond.is_some():
            let wctx = Ctx(scope: scope.clone(), row: rows[i].clone(), group: [])
            let cond = try eval(s.where_cond.get().clone(), wctx)
            keep = is_true(cond)

        if keep:
            kept.append(rows[i].clone())

    # Groups: one per GROUP BY key, one for the whole input, or one per row.
    var groups: List[Group] = []

    if not aggregated:
        for i in range(0, kept.length()):
            groups.append(Group(key: [], rows: [kept[i].clone()]))
    elif not has_group:
        groups.append(Group(key: [], rows: kept.clone()))
    else:
        for i in range(0, kept.length()):
            let key = group_key(kept[i].clone(), group_idx.clone())
            let g = find_group(groups, key.clone())

            if g < 0:
                groups.append(Group(key: key, rows: [kept[i].clone()]))
            else:
                groups[g].rows.append(kept[i].clone())

    var vals_list: List[List[Value]] = []
    var keys_list: List[List[Value]] = []

    for gi in range(0, groups.length()):
        var first: List[Value] = []
        if groups[gi].rows.length() > 0:
            first = groups[gi].rows[0].clone()

        let gctx = Ctx(
            scope: scope.clone(), row: first.clone(), group: groups[gi].rows.clone()
        )
        var keep = True

        if s.having_cond.is_some():
            let h = try eval(s.having_cond.get().clone(), gctx.clone())
            keep = is_true(h)

        if keep:
            var vals: List[Value] = []

            for o in range(0, outs.length()):
                let v = try eval(outs[o].e.clone(), gctx.clone())
                vals.append(v)

            var keys: List[Value] = []

            for k in range(0, order_out.length()):
                if order_out[k] >= 0:
                    keys.append(vals[order_out[k]])
                else:
                    let kv = try eval(s.order_by[k].e.clone(), gctx.clone())
                    keys.append(kv)

            vals_list.append(vals)
            keys_list.append(keys)

    var ids: List[Int] = []
    for i in range(0, vals_list.length()):
        ids.append(i)

    if s.distinct:
        var unique: List[Int] = []

        for i in range(0, ids.length()):
            var dup = False
            for u in range(0, unique.length()):
                if rows_equal(vals_list[ids[i]].clone(), vals_list[unique[u]].clone()):
                    dup = True
            if not dup:
                unique.append(ids[i])

        ids = unique

    if s.order_by.length() > 0:
        var descs: List[Bool] = []
        for i in range(0, s.order_by.length()):
            descs.append(s.order_by[i].desc)
        ids = sort_ids(ids.clone(), keys_list.clone(), descs.clone())

    var first_id = s.offset_n
    if first_id > ids.length():
        first_id = ids.length()

    var end_id = ids.length()

    if s.limit_n.is_some():
        let lim = s.limit_n.get()
        if first_id + lim < end_id:
            end_id = first_id + lim

    var names: List[String] = []
    for i in range(0, outs.length()):
        names.append(outs[i].name)
    emit(var out, names.join("|"))
    for k in range(first_id, end_id):
        write_row(var out, vals_list[ids[k]].clone())
    emit(var out, f"({end_id - first_id} rows)")
    return ok(end_id - first_id)

# ---------------------------------------------------------------- DDL and DML
def exec_create(
    name: String,
    cols: List[ColDef],
    var tables: List[Table]
) -> Result[Unit, SqlError]:
    if find_table(tables, name) >= 0:
        return error(sql_error(f"table {name} already exists"))

    var primaries = 0

    for k in range(0, cols.length()):
        if column_index(cols.clone(), cols[k].name) != k:
            return error(sql_error(f"duplicate column: {cols[k].name}"))

        if cols[k].primary:
            primaries = primaries + 1

    if primaries > 1:
        return error(sql_error("multiple primary keys"))

    tables.append(Table(name: name, cols: cols.clone(), rows: []))
    return ok(unit_value())

def exec_drop(name: String, var tables: List[Table]) -> Result[Unit, SqlError]:
    let ti = find_table(tables, name)
    if ti < 0:
        return error(sql_error(f"no such table: {name}"))

    tables.remove(ti)
    return ok(unit_value())

def check_row(row: List[Value], cols: List[ColDef]) -> Result[Unit, SqlError]:
    for k in range(0, cols.length()):
        let v = row[k]
        if (cols[k].notnull or cols[k].primary) and is_null(v):
            return error(sql_error(f"NOT NULL constraint failed: {cols[k].name}"))

        if not is_null(v):
            var fits = text_of(v).is_some()
            if cols[k].kind == "INT":
                fits = int_of(v).is_some()
            if not fits:
                return error(sql_error(f"type mismatch in column {cols[k].name}"))

    return ok(unit_value())

# Duplicate primary keys among rows, reported in row order.
def check_primary(rows: List[List[Value]], pk: Int) -> Result[Unit, SqlError]:
    if pk < 0:
        return ok(unit_value())

    var seen: List[Value] = []

    for r in range(0, rows.length()):
        if contains_value(seen, rows[r][pk]):
            return error(sql_error(f"duplicate primary key: {value_text(rows[r][pk])}"))

        seen.append(rows[r][pk])

    return ok(unit_value())

def exec_insert(
    table: String,
    names: Optional[List[String]],
    rows: List[List[Expr]],
    var tables: List[Table]
) -> Result[Int, SqlError]:
    let ti = find_table(tables, table)
    if ti < 0:
        return error(sql_error(f"no such table: {table}"))

    let cols = tables[ti].cols.clone()
    var targets: List[Int] = []

    if names.is_some():
        let given = names.get().clone()

        for i in range(0, given.length()):
            let idx = column_index(cols.clone(), given[i])
            if idx < 0:
                return error(sql_error(f"no such column: {given[i]}"))
            if targets.contains(idx):
                return error(sql_error(f"duplicate column: {given[i]}"))

            targets.append(idx)
    else:
        for k in range(0, cols.length()):
            targets.append(k)

    var fresh: List[List[Value]] = []

    for r in range(0, rows.length()):
        if rows[r].length() != targets.length():
            return error(sql_error("wrong number of values"))

        var row = nulls(cols.length())

        for k in range(0, targets.length()):
            let rc = Check(
                scope: [], allow_agg: False, aggregated: False, group_idx: []
            )
            try check_expr(rows[r][k].clone(), rc, False)

            let v = try eval(rows[r][k].clone(), Ctx(scope: [], row: [], group: []))
            row.set(targets[k], v)

        try check_row(row.clone(), cols.clone())
        fresh.append(row)

    let pk = primary_index(cols.clone())

    if pk >= 0:
        var existing = tables[ti].rows.clone()
        for r in range(0, fresh.length()):
            existing.append(fresh[r].clone())
        try check_primary(existing, pk)

    let count = fresh.length()
    for r in range(0, fresh.length()):
        tables[ti].rows.append(fresh[r].clone())
    return ok(count)

def exec_update(
    table: String,
    names: List[String],
    exprs: List[Expr],
    cond: Optional[Expr],
    var tables: List[Table]
) -> Result[Int, SqlError]:
    let ti = find_table(tables, table)
    if ti < 0:
        return error(sql_error(f"no such table: {table}"))

    let cols = tables[ti].cols.clone()
    let scope = table_scope(table, cols.clone())
    var targets: List[Int] = []

    for n in range(0, names.length()):
        let idx = column_index(cols.clone(), names[n])
        if idx < 0:
            return error(sql_error(f"no such column: {names[n]}"))

        targets.append(idx)

    for i in range(0, exprs.length()):
        let plain = Check(
            scope: scope.clone(), allow_agg: False, aggregated: False, group_idx: []
        )
        try check_expr(exprs[i].clone(), plain, False)

    if cond.is_some():
        let plain = Check(
            scope: scope.clone(), allow_agg: False, aggregated: False, group_idx: []
        )
        try check_expr(cond.get().clone(), plain, False)

    var fresh: List[List[Value]] = []
    var count = 0
    let old = tables[ti].rows.clone()

    for r in range(0, old.length()):
        let row = old[r].clone()
        var hit = True

        if cond.is_some():
            let cctx = Ctx(scope: scope.clone(), row: row.clone(), group: [])
            let c = try eval(cond.get().clone(), cctx)
            hit = is_true(c)

        if hit:
            count = count + 1

            var newvals: List[Value] = []

            for i in range(0, exprs.length()):
                let ectx = Ctx(scope: scope.clone(), row: row.clone(), group: [])
                let v = try eval(exprs[i].clone(), ectx)
                newvals.append(v)

            var newrow = row.clone()
            for k in range(0, targets.length()):
                newrow.set(targets[k], newvals[k])
            try check_row(newrow.clone(), cols.clone())
            fresh.append(newrow)
        else:
            fresh.append(row)

    try check_primary(fresh.clone(), primary_index(cols.clone()))
    tables[ti].rows.splice(0, tables[ti].rows.length(), fresh)
    return ok(count)

def exec_delete(
    table: String,
    cond: Optional[Expr],
    var tables: List[Table]
) -> Result[Int, SqlError]:
    let ti = find_table(tables, table)
    if ti < 0:
        return error(sql_error(f"no such table: {table}"))

    let scope = table_scope(table, tables[ti].cols.clone())

    if cond.is_some():
        let plain = Check(
            scope: scope.clone(), allow_agg: False, aggregated: False, group_idx: []
        )
        try check_expr(cond.get().clone(), plain, False)

    var fresh: List[List[Value]] = []
    var count = 0
    let old = tables[ti].rows.clone()

    for r in range(0, old.length()):
        let row = old[r].clone()
        var hit = True

        if cond.is_some():
            let cctx = Ctx(scope: scope.clone(), row: row.clone(), group: [])
            let c = try eval(cond.get().clone(), cctx)
            hit = is_true(c)

        if hit:
            count = count + 1
        else:
            fresh.append(row)

    tables[ti].rows.splice(0, tables[ti].rows.length(), fresh)
    return ok(count)

def execute(
    stmt: Stmt,
    var tables: List[Table],
    var out: BytesBuilder
) -> Result[Int, SqlError]:
    match stmt:
        case Create(name, cols):
            try exec_create(name, cols.clone(), var tables)
            emit(var out, "ok")
            return ok(0)
        case Drop(name):
            try exec_drop(name, var tables)
            emit(var out, "ok")
            return ok(0)
        case Insert(table, names, rows):
            let n = try exec_insert(table, names.clone(), rows.clone(), var tables)
            emit(var out, f"inserted {n}")
            return ok(0)
        case Update(table, names, exprs, cond):
            let n = try exec_update(
                table, names.clone(), exprs.clone(), cond.clone(), var tables
            )
            emit(var out, f"updated {n}")
            return ok(0)
        case Delete(table, cond):
            let n = try exec_delete(table, cond.clone(), var tables)
            emit(var out, f"deleted {n}")
            return ok(0)
        case Query(sel):
            return run_select(sel.clone(), tables.clone(), var out)

# ---------------------------------------------------------------- driver
def run_span(
    src: List[Int],
    span: Span,
    var tables: List[Table],
    var out: BytesBuilder
) -> Result[Int, SqlError]:
    let toks = try lex(src, span.start, span.stop)
    if toks.length() == 0:
        return ok(0)

    var p = Parser(toks: toks, pos: 0)
    let stmt = try parse_statement(var p)
    if p.pos != p.toks.length():
        return error(syntax_error())

    return execute(stmt, var tables, var out)

def run_script(data: Bytes) -> Bytes:
    let src = data.values()
    let spans = split_statements(src)
    var tables: List[Table] = []
    var out = BytesBuilder()

    for i in range(0, spans.length()):
        let r = run_span(src.clone(), spans[i].clone(), var tables, var out)
        if r.is_error():
            emit(var out, f"error: {r.err().message()}")

    return out.build()

export def main() -> Int:
    if let data = read_all(stdin()):
        stdout().write_bytes(run_script(data))
    return 0

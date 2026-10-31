import stdout, stdin, read_all from "@std/io.ms"
import BytesBuilder from "@std/bytes.ms"

let MAX_INT = 9223372036854775807
let KEYWORDS = [
    "SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET",
    "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN",
    "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE",
    "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"
]
let OPS2 = ["<=", ">=", "<>", "!=", "||"]
let OPS1 = ["=", "<", ">", "+", "-", "*", "/", "%", "(", ")", ",", ".", ";"]
let FUNCS = [
    "UPPER", "LOWER", "LENGTH", "ABS", "SUBSTR", "COALESCE", "COUNT", "SUM", "MIN",
    "MAX"
]

# ---------- values ----------

type Value:
    case VNull
    case VInt(n: Int)
    case VText(s: String)
    case VBool(b: Bool)

type Fail:
    msg: String

impl Error for Fail:
    fn message() String: self.msg.clone()

fn is_null(v: Value) Bool:
    match v:
        VNull:
            return true
        _:
            return false

# Type rank used for NULL < BOOL < INT < TEXT ordering and type checks.
fn rank(v: Value) Int:
    match v:
        VNull:
            return 0
        VBool(_):
            return 1
        VInt(_):
            return 2
        VText(_):
            return 3

fn int_of(v: Value) Int:
    match v:
        VInt(n):
            return n
        _:
            return 0

fn text_of(v: Value) String:
    match v:
        VText(s):
            return s.clone()
        _:
            return ""

fn as_int(v: Value) Result[Int, Fail]:
    match v:
        VInt(n):
            return ok(n)
        _:
            return error(Fail("type error"))

fn as_text(v: Value) Result[String, Fail]:
    match v:
        VText(s):
            return ok(s.clone())
        _:
            return error(Fail("type error"))

fn show(v: Value) String:
    match v:
        VNull:
            return "NULL"
        VInt(n):
            return "{n}"
        VText(s):
            return s.clone()
        VBool(b):
            if b:
                return "true"

            return "false"

# Injective encoding of a value, used as a hash key where NULLs compare equal.
fn enc(v: Value) String:
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

fn enc_row(vals: List[Value]) String:
    var acc = ""
    for v in vals:
        acc = acc + enc(v)
    return acc

# Three-valued logic: 0 false, 1 true, 2 NULL. Non-boolean operands are type errors.
fn tri(v: Value) Result[Int, Fail]:
    match v:
        VNull:
            return ok(2)
        VBool(b):
            if b:
                return ok(1)

            return ok(0)
        _:
            return error(Fail("type error"))

fn tri_value(t: Int) Value:
    if t == 2:
        return VNull

    return VBool(t == 1)

fn tri_not(t: Int) Int:
    if t == 2:
        return 2

    return 1 - t

fn tri_and(a: Int, b: Int) Int:
    if a == 0 or b == 0:
        return 0
    if a == 1 and b == 1:
        return 1

    return 2

fn tri_or(a: Int, b: Int) Int:
    if a == 1 or b == 1:
        return 1
    if a == 0 and b == 0:
        return 0

    return 2

# Ordering used by ORDER BY: NULL < BOOL < INT < TEXT.
fn order_of(a: Value, b: Value) Int:
    let ra = rank(a)
    let rb = rank(b)
    if ra != rb:
        return ra.compare(rb)
    if ra == 2:
        return int_of(a).compare(int_of(b))
    if ra == 3:
        return text_of(a).compare(text_of(b))
    if ra == 1:
        return enc(a).compare(enc(b))

    return 0

# Comparison of two non-NULL values of the same INT or TEXT type.
fn compare_values(a: Value, b: Value) Result[Int, Fail]:
    let ra = rank(a)
    if ra != rank(b) or ra < 2:
        return error(Fail("type error"))
    if ra == 2:
        return ok(int_of(a).compare(int_of(b)))

    return ok(text_of(a).compare(text_of(b)))

fn compare_op(op: String, a: Value, b: Value) Result[Value, Fail]:
    if is_null(a) or is_null(b):
        return ok(VNull)

    let c = try compare_values(a, b)
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

fn binary_op(op: String, a: Value, b: Value) Result[Value, Fail]:
    if op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">=":
        return compare_op(op, a, b)
    if is_null(a) or is_null(b):
        return ok(VNull)

    if op == "||":
        let x = try as_text(a)
        let y = try as_text(b)
        return ok(VText(x + y))

    let x = try as_int(a)
    let y = try as_int(b)
    if op == "+":
        return ok(VInt(x + y))
    if op == "-":
        return ok(VInt(x - y))
    if op == "*":
        return ok(VInt(x * y))
    if y == 0:
        return error(Fail("division by zero"))
    if op == "/":
        return ok(VInt(x / y))

    return ok(VInt(x % y))

fn distinct_values(vals: List[Value]) List[Value]:
    var seen = Set[String]()
    var out = List[Value]()

    for v in vals:
        let k = enc(v)

        if not seen.contains(k):
            seen.add(k)
            out.append(v.clone())

    return out

# ---------- byte-level text helpers ----------

fn bytes_of(s: String) List[Int]:
    var out = List[Int]()
    for b in s.to_bytes().values():
        out.append(b.to_int())
    return out

fn text_of_bytes(bs: List[Int]) String:
    var builder = BytesBuilder()
    for b in bs:
        if let u = b.to_uint8():
            builder.append(u)
    return builder.build().decode_utf8().get("")

# LIKE: '%' matches any run of bytes, '_' exactly one byte, everything else literally.
fn like_match(s: List[Int], p: List[Int]) Bool:
    let n = s.length()
    let m = p.length()
    var i = 0
    var j = 0
    var star = -1
    var mark = 0

    while i < n:
        if j < m and p[j] == 37:
            star = j
            mark = i
            j += 1
        else if j < m and (p[j] == 95 or p[j] == s[i]):
            i += 1
            j += 1
        else if star >= 0:
            j = star + 1
            mark += 1
            i = mark
        else:
            return false

    while j < m and p[j] == 37:
        j += 1
    return j == m

# ---------- syntax tree ----------

type Expr:
    case Lit(v: Value)
    case Col(table: String, name: String)
    case Unary(op: String, x: Expr)
    case Binary(op: String, l: Expr, r: Expr)
    case IsNull(x: Expr, negate: Bool)
    case Like(x: Expr, pat: Expr, negate: Bool)
    case InList(x: Expr, items: List[Expr], negate: Bool)
    case Between(x: Expr, lo: Expr, hi: Expr, negate: Bool)
    case Call(name: String, args: List[Expr], distinct: Bool, star: Bool)

type TRef:
    table: String
    alias: String

type Join:
    left: Bool
    tref: TRef
    on: Expr

type OrderItem:
    e: Expr
    desc: Bool

type SelItem:
    case AllCols(table: String)
    case ExprItem(e: Expr, alias: String)

type Select:
    distinct: Bool
    items: List[SelItem]
    source: List[TRef]
    joins: List[Join]
    cond: Expr
    groups: List[Expr]
    has_having: Bool
    having: Expr
    order: List[OrderItem]
    limit: Int
    offset: Int

type ColDef:
    name: String
    ty: String
    pk: Bool
    notnull: Bool

type Assign:
    col: String
    e: Expr

type Stmt:
    case CreateTable(name: String, defs: List[ColDef])
    case DropTable(name: String)
    case InsertRows(
        name: String,
        cols: List[String],
        has_cols: Bool,
        rows: List[List[Expr]]
    )
    case UpdateRows(name: String, sets: List[Assign], cond: Expr)
    case DeleteRows(name: String, cond: Expr)
    case Query(sel: Select)

# ---------- lexer ----------

type Tok:
    kind: String
    text: String
    num: Int

fn is_alpha(c: String) Bool:
    if c == "_":
        return true
    if c >= "a" and c <= "z":
        return true

    return c >= "A" and c <= "Z"

fn is_digit(c: String) Bool:
    return c >= "0" and c <= "9"

fn digit_value(c: String) Int:
    return c.scalar_values() [0] - 48

# Lexes the whole script. Bad characters and unterminated strings become "err" tokens so that
# only the statement containing them fails.
fn lex(text: String) List[Tok]:
    let cs = text.chars()
    let n = cs.length()
    var toks = List[Tok]()
    var i = 0

    while i < n:
        let c = cs[i].clone()

        if c == " " or c == "\t" or c == "\r" or c == "\n":
            i += 1
        else if c == "-" and i + 1 < n and cs[i + 1] == "-":
            while i < n and cs[i] != "\n":
                i += 1
        else if is_alpha(c):
            var word = ""

            while i < n and (is_alpha(cs[i]) or is_digit(cs[i])):
                word = word + cs[i]
                i += 1

            let up = word.upper()

            if KEYWORDS.contains(up):
                toks.append(Tok("kw", up, 0))
            else:
                toks.append(Tok("id", word, 0))
        else if is_digit(c):
            var v = 0
            var bad = false

            while i < n and is_digit(cs[i]):
                let d = digit_value(cs[i])

                if v > (MAX_INT - d) / 10:
                    bad = true
                else:
                    v = v * 10 + d

                i += 1

            if bad:
                toks.append(Tok("err", "", 0))
            else:
                toks.append(Tok("int", "", v))
        else if c == "'":
            i += 1

            var s = ""
            var closed = false

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

            if closed:
                toks.append(Tok("str", s, 0))
            else:
                toks.append(Tok("err", "", 0))
        else if i + 1 < n and OPS2.contains(c + cs[i + 1]):
            toks.append(Tok("op", c + cs[i + 1], 0))
            i += 2
        else if OPS1.contains(c):
            toks.append(Tok("op", c, 0))
            i += 1
        else:
            toks.append(Tok("err", "", 0))
            i += 1

    return toks

# Splits tokens at ';' operators. Empty statements are returned as empty lists.
fn statements(toks: List[Tok]) List[List[Tok]]:
    var out = List[List[Tok]]()
    var cur = List[Tok]()

    for t in toks:
        if t.kind == "op" and t.text == ";":
            out.append(cur)
            cur = List[Tok]()
        else:
            cur.append(t.clone())

    out.append(cur)
    return out

# ---------- parser ----------

type Parser:
    toks: List[Tok]
    pos: Int

impl Parser:
    fn tok(i: Int) Tok:
        if i >= self.toks.length():
            return Tok("end", "", 0)

        return self.toks[i].clone()

    fn kw_at(i: Int, word: String) Bool:
        let t = self.tok(i)
        return t.kind == "kw" and t.text == word

    fn op_at(i: Int, op: String) Bool:
        let t = self.tok(i)
        return t.kind == "op" and t.text == op

    fn is_kw(word: String) Bool:
        return self.kw_at(self.pos, word)

    fn is_op(op: String) Bool:
        return self.op_at(self.pos, op)

    var fn expect_kw(word: String) Result[Unit, Fail]:
        if not self.is_kw(word):
            return error(Fail("syntax error"))

        self.pos += 1
        return ok(unit)

    var fn expect_op(op: String) Result[Unit, Fail]:
        if not self.is_op(op):
            return error(Fail("syntax error"))

        self.pos += 1
        return ok(unit)

    var fn ident() Result[String, Fail]:
        let t = self.tok(self.pos)
        if t.kind != "id":
            return error(Fail("syntax error"))

        self.pos += 1
        return ok(t.text.clone())

    var fn statement() Result[Stmt, Fail]:
        let t = self.tok(self.pos)
        if t.kind != "kw":
            return error(Fail("syntax error"))
        if t.text == "CREATE":
            return self.create_stmt()
        if t.text == "DROP":
            return self.drop_stmt()
        if t.text == "INSERT":
            return self.insert_stmt()
        if t.text == "UPDATE":
            return self.update_stmt()
        if t.text == "DELETE":
            return self.delete_stmt()

        if t.text == "SELECT":
            let sel = try self.select_stmt()
            return ok(Query(sel))

        return error(Fail("syntax error"))

    var fn create_stmt() Result[Stmt, Fail]:
        try self.expect_kw("CREATE")
        try self.expect_kw("TABLE")

        let name = try self.ident()
        try self.expect_op("(")

        var defs = List[ColDef]()
        defs.append(try self.coldef())

        while self.is_op(","):
            self.pos += 1
            defs.append(try self.coldef())

        try self.expect_op(")")
        return ok(CreateTable(name, defs))

    var fn coldef() Result[ColDef, Fail]:
        let name = try self.ident()
        let ty = try self.ident()
        let up = ty.upper()
        if up != "INT" and up != "TEXT":
            return error(Fail("syntax error"))

        var pk = false
        var notnull = false

        while self.is_kw("PRIMARY") or self.is_kw("NOT"):
            if self.is_kw("PRIMARY"):
                self.pos += 1
                try self.expect_kw("KEY")
                pk = true
                notnull = true
            else:
                self.pos += 1
                try self.expect_kw("NULL")
                notnull = true

        return ok(ColDef(name, up, pk, notnull))

    var fn drop_stmt() Result[Stmt, Fail]:
        try self.expect_kw("DROP")
        try self.expect_kw("TABLE")

        let name = try self.ident()
        return ok(DropTable(name))

    var fn insert_stmt() Result[Stmt, Fail]:
        try self.expect_kw("INSERT")
        try self.expect_kw("INTO")

        let name = try self.ident()
        var cols = List[String]()
        var has_cols = false

        if self.is_op("("):
            self.pos += 1
            has_cols = true
            cols.append(try self.ident())

            while self.is_op(","):
                self.pos += 1
                cols.append(try self.ident())

            try self.expect_op(")")

        try self.expect_kw("VALUES")

        var rows = List[List[Expr]]()
        rows.append(try self.value_row())

        while self.is_op(","):
            self.pos += 1
            rows.append(try self.value_row())

        return ok(InsertRows(name, cols, has_cols, rows))

    var fn value_row() Result[List[Expr], Fail]:
        try self.expect_op("(")

        var vals = List[Expr]()
        vals.append(try self.expr())

        while self.is_op(","):
            self.pos += 1
            vals.append(try self.expr())

        try self.expect_op(")")
        return ok(vals)

    var fn update_stmt() Result[Stmt, Fail]:
        try self.expect_kw("UPDATE")

        let name = try self.ident()
        try self.expect_kw("SET")

        var sets = List[Assign]()
        sets.append(try self.assignment())

        while self.is_op(","):
            self.pos += 1
            sets.append(try self.assignment())

        var cond: Expr = Lit(VBool(true))

        if self.is_kw("WHERE"):
            self.pos += 1
            cond = try self.expr()

        return ok(UpdateRows(name, sets, cond))

    var fn assignment() Result[Assign, Fail]:
        let col = try self.ident()
        try self.expect_op("=")

        let e = try self.expr()
        return ok(Assign(col, e))

    var fn delete_stmt() Result[Stmt, Fail]:
        try self.expect_kw("DELETE")
        try self.expect_kw("FROM")

        let name = try self.ident()
        var cond: Expr = Lit(VBool(true))

        if self.is_kw("WHERE"):
            self.pos += 1
            cond = try self.expr()

        return ok(DeleteRows(name, cond))

    var fn select_stmt() Result[Select, Fail]:
        try self.expect_kw("SELECT")

        var distinct = false

        if self.is_kw("DISTINCT"):
            self.pos += 1
            distinct = true

        var items = List[SelItem]()
        items.append(try self.select_item())

        while self.is_op(","):
            self.pos += 1
            items.append(try self.select_item())

        var source = List[TRef]()
        var joins = List[Join]()

        if self.is_kw("FROM"):
            self.pos += 1
            source.append(try self.tref())

            while self.is_kw("JOIN") or self.is_kw("INNER") or self.is_kw("LEFT"):
                var left = false

                if self.is_kw("INNER"):
                    self.pos += 1
                else if self.is_kw("LEFT"):
                    self.pos += 1
                    left = true

                try self.expect_kw("JOIN")

                let tr = try self.tref()
                try self.expect_kw("ON")

                let on = try self.expr()
                joins.append(Join(left, tr, on))

        var cond: Expr = Lit(VBool(true))

        if self.is_kw("WHERE"):
            self.pos += 1
            cond = try self.expr()

        var groups = List[Expr]()

        if self.is_kw("GROUP"):
            self.pos += 1
            try self.expect_kw("BY")
            groups.append(try self.colref())

            while self.is_op(","):
                self.pos += 1
                groups.append(try self.colref())

        var has_having = false
        var having: Expr = Lit(VBool(true))

        if self.is_kw("HAVING"):
            self.pos += 1
            has_having = true
            having = try self.expr()

        var order = List[OrderItem]()

        if self.is_kw("ORDER"):
            self.pos += 1
            try self.expect_kw("BY")
            order.append(try self.order_item())

            while self.is_op(","):
                self.pos += 1
                order.append(try self.order_item())

        var limit = -1
        var offset = 0

        if self.is_kw("LIMIT"):
            self.pos += 1
            limit = try self.int_lit()

            if self.is_kw("OFFSET"):
                self.pos += 1
                offset = try self.int_lit()

        return ok(
            Select(
                distinct, items, source, joins, cond, groups, has_having, having, order,
                limit, offset
            )
        )

    var fn select_item() Result[SelItem, Fail]:
        if self.is_op("*"):
            self.pos += 1
            return ok(AllCols(""))

        let t = self.tok(self.pos)

        if (
            t.kind == "id"
            and self.op_at(self.pos + 1, ".")
            and self.op_at(self.pos + 2, "*")
        ):
            self.pos += 3
            return ok(AllCols(t.text.clone()))

        let e = try self.expr()
        var alias = ""

        if self.is_kw("AS"):
            self.pos += 1
            alias = try self.ident()

        return ok(ExprItem(e, alias))

    var fn tref() Result[TRef, Fail]:
        let name = try self.ident()
        var alias = name.clone()

        if self.is_kw("AS"):
            self.pos += 1
            alias = try self.ident()
        else if self.tok(self.pos).kind == "id":
            alias = try self.ident()

        return ok(TRef(name, alias))

    var fn colref() Result[Expr, Fail]:
        let first = try self.ident()

        if self.is_op("."):
            self.pos += 1

            let second = try self.ident()
            return ok(Col(first, second))

        return ok(Col("", first))

    var fn order_item() Result[OrderItem, Fail]:
        let e = try self.expr()
        var desc = false

        if self.is_kw("ASC"):
            self.pos += 1
        else if self.is_kw("DESC"):
            self.pos += 1
            desc = true

        return ok(OrderItem(e, desc))

    var fn int_lit() Result[Int, Fail]:
        let t = self.tok(self.pos)
        if t.kind != "int":
            return error(Fail("syntax error"))

        self.pos += 1
        return ok(t.num)

    var fn expr() Result[Expr, Fail]:
        var left = try self.and_expr()

        while self.is_kw("OR"):
            self.pos += 1

            let right = try self.and_expr()
            left = Binary("OR", left, right)

        return ok(left)

    var fn and_expr() Result[Expr, Fail]:
        var left = try self.not_expr()

        while self.is_kw("AND"):
            self.pos += 1

            let right = try self.not_expr()
            left = Binary("AND", left, right)

        return ok(left)

    var fn not_expr() Result[Expr, Fail]:
        if self.is_kw("NOT"):
            self.pos += 1

            let x = try self.not_expr()
            return ok(Unary("NOT", x))

        return self.cmp_expr()

    var fn cmp_expr() Result[Expr, Fail]:
        let left = try self.add_expr()
        let t = self.tok(self.pos)

        if (
            t.kind == "op"
            and (
                t.text == "="
                or t.text == "<>"
                or t.text == "!="
                or t.text == "<"
                or t.text == "<="
                or t.text == ">"
                or t.text == ">="
            )
        ):
            self.pos += 1

            let right = try self.add_expr()
            if t.text == "!=":
                return ok(Binary("<>", left, right))

            return ok(Binary(t.text.clone(), left, right))

        if self.is_kw("IS"):
            self.pos += 1

            var neg = false

            if self.is_kw("NOT"):
                self.pos += 1
                neg = true

            try self.expect_kw("NULL")
            return ok(IsNull(left, neg))

        var neg = false

        if (
            self.is_kw("NOT")
            and (
                self.kw_at(self.pos + 1, "LIKE")
                or self.kw_at(self.pos + 1, "IN")
                or self.kw_at(self.pos + 1, "BETWEEN")
            )
        ):
            self.pos += 1
            neg = true

        if self.is_kw("LIKE"):
            self.pos += 1

            let pat = try self.add_expr()
            return ok(Like(left, pat, neg))

        if self.is_kw("IN"):
            self.pos += 1
            try self.expect_op("(")

            var items = List[Expr]()
            items.append(try self.expr())

            while self.is_op(","):
                self.pos += 1
                items.append(try self.expr())

            try self.expect_op(")")
            return ok(InList(left, items, neg))

        if self.is_kw("BETWEEN"):
            self.pos += 1

            let lo = try self.add_expr()
            try self.expect_kw("AND")

            let hi = try self.add_expr()
            return ok(Between(left, lo, hi, neg))

        return ok(left)

    var fn add_expr() Result[Expr, Fail]:
        var left = try self.mul_expr()

        while self.is_op("+") or self.is_op("-") or self.is_op("||"):
            let op = self.tok(self.pos).text.clone()
            self.pos += 1

            let right = try self.mul_expr()
            left = Binary(op, left, right)

        return ok(left)

    var fn mul_expr() Result[Expr, Fail]:
        var left = try self.unary_expr()

        while self.is_op("*") or self.is_op("/") or self.is_op("%"):
            let op = self.tok(self.pos).text.clone()
            self.pos += 1

            let right = try self.unary_expr()
            left = Binary(op, left, right)

        return ok(left)

    var fn unary_expr() Result[Expr, Fail]:
        if self.is_op("-"):
            self.pos += 1

            let x = try self.unary_expr()
            return ok(Unary("-", x))

        return self.primary()

    var fn primary() Result[Expr, Fail]:
        let t = self.tok(self.pos)

        if t.kind == "int":
            self.pos += 1
            return ok(Lit(VInt(t.num)))

        if t.kind == "str":
            self.pos += 1
            return ok(Lit(VText(t.text.clone())))

        if t.kind == "kw" and t.text == "NULL":
            self.pos += 1
            return ok(Lit(VNull))

        if t.kind == "op" and t.text == "(":
            self.pos += 1

            let x = try self.expr()
            try self.expect_op(")")
            return ok(x)

        if t.kind == "id":
            self.pos += 1
            if self.is_op("("):
                return self.call_rest(t.text.clone())

            if self.is_op("."):
                self.pos += 1

                let col = try self.ident()
                return ok(Col(t.text.clone(), col))

            return ok(Col("", t.text.clone()))

        return error(Fail("syntax error"))

    # The current token is "(" after a function name.
    var fn call_rest(name: String) Result[Expr, Fail]:
        self.pos += 1

        var distinct = false
        var star = false
        var args = List[Expr]()

        if self.is_kw("DISTINCT"):
            self.pos += 1
            distinct = true

        if self.is_op("*"):
            self.pos += 1
            star = true
        else if not self.is_op(")"):
            args.append(try self.expr())

            while self.is_op(","):
                self.pos += 1
                args.append(try self.expr())

        try self.expect_op(")")
        return ok(Call(name.upper(), args, distinct, star))

# ---------- static checks (name resolution, aggregate placement) ----------

type Slot:
    alias: String
    col: String

type Check:
    agg_ok: Bool
    grouped: Bool
    groups: List[Int]

fn plain_check() Check:
    return Check(false, false, List[Int]())

fn written(table: String, name: String) String:
    if table == "":
        return name.clone()

    return "{table}.{name}"

fn find_col(slots: List[Slot], table: String, name: String) Result[Int, Fail]:
    var found = -1
    var count = 0

    for i in 0..slots.length():
        if slots[i].col == name and (table == "" or slots[i].alias == table):
            if found < 0:
                found = i
            count += 1

    if count == 0:
        return error(Fail("no such column: {written(table, name)}"))
    if table == "" and count > 1:
        return error(Fail("ambiguous column: {name}"))

    return ok(found)

fn find_table(db: List[Table], name: String) Int:
    for i in 0..db.length():
        if db[i].name == name:
            return i
    return -1

fn column_index(cols: List[ColDef], name: String) Int:
    for i in 0..cols.length():
        if cols[i].name == name:
            return i
    return -1

fn is_agg(name: String) Bool:
    return name == "COUNT" or name == "SUM" or name == "MIN" or name == "MAX"

fn contains_agg(e: Expr) Bool:
    match e:
        Lit(_):
            return false
        Col(_, _):
            return false
        Unary(_, x):
            return contains_agg(x)
        Binary(_, l, r):
            return contains_agg(l) or contains_agg(r)
        IsNull(x, _):
            return contains_agg(x)
        Like(x, p, _):
            return contains_agg(x) or contains_agg(p)
        InList(x, items, _):
            if contains_agg(x):
                return true

            for it in items:
                if contains_agg(it):
                    return true
            return false
        Between(x, lo, hi, _):
            return contains_agg(x) or contains_agg(lo) or contains_agg(hi)
        Call(name, args, _, _):
            if is_agg(name):
                return true

            for a in args:
                if contains_agg(a):
                    return true
            return false

fn check_call_shape(
    name: String,
    count: Int,
    distinct: Bool,
    star: Bool
) Result[Unit, Fail]:
    if not FUNCS.contains(name):
        return error(Fail("no such function: {name}"))

    let wrong = Fail("wrong number of arguments to {name}")

    if star:
        if name != "COUNT" or distinct:
            return error(wrong)

        return ok(unit)

    if distinct and count != 1:
        return error(wrong)

    if name == "SUBSTR":
        if count != 3:
            return error(wrong)
    else if name == "COALESCE":
        if count < 1:
            return error(wrong)
    else if count != 1:
        return error(wrong)

    return ok(unit)

fn check_expr(e: Expr, slots: List[Slot], cx: Check, in_agg: Bool) Result[Unit, Fail]:
    match e:
        Lit(_):
            return ok(unit)
        Col(t, n):
            let i = try find_col(slots, t, n)
            if cx.grouped and not in_agg and not cx.groups.contains(i):
                return error(Fail("column {written(t, n)} must appear in GROUP BY"))

            return ok(unit)
        Unary(_, x):
            return check_expr(x, slots, cx, in_agg)
        Binary(_, l, r):
            try check_expr(l, slots, cx, in_agg)
            try check_expr(r, slots, cx, in_agg)
            return ok(unit)
        IsNull(x, _):
            return check_expr(x, slots, cx, in_agg)
        Like(x, p, _):
            try check_expr(x, slots, cx, in_agg)
            try check_expr(p, slots, cx, in_agg)
            return ok(unit)
        InList(x, items, _):
            try check_expr(x, slots, cx, in_agg)
            for it in items:
                try check_expr(it, slots, cx, in_agg)
            return ok(unit)
        Between(x, lo, hi, _):
            try check_expr(x, slots, cx, in_agg)
            try check_expr(lo, slots, cx, in_agg)
            try check_expr(hi, slots, cx, in_agg)
            return ok(unit)
        Call(name, args, distinct, star):
            try check_call_shape(name, args.length(), distinct, star)

            let agg = is_agg(name)
            if agg and (in_agg or not cx.agg_ok):
                return error(Fail("misuse of aggregate"))

            for a in args:
                try check_expr(a, slots, cx, in_agg or agg)
            return ok(unit)

# ---------- evaluation ----------

fn like_bytes(v: Value, p: Value) Result[Bool, Fail]:
    let s = try as_text(v)
    let q = try as_text(p)
    return ok(like_match(bytes_of(s), bytes_of(q)))

fn eval(
    e: Expr,
    slots: List[Slot],
    row: List[Value],
    group: List[List[Value]]
) Result[Value, Fail]:
    match e:
        Lit(v):
            return ok(v.clone())
        Col(t, n):
            let i = try find_col(slots, t, n)
            return ok(row[i].clone())
        Unary(op, x):
            let v = try eval(x, slots, row, group)

            if op == "NOT":
                let t = try tri(v)
                return ok(tri_value(tri_not(t)))

            if is_null(v):
                return ok(VNull)

            let n = try as_int(v)
            return ok(VInt(-n))
        IsNull(x, negate):
            let v = try eval(x, slots, row, group)
            return ok(VBool(is_null(v) != negate))
        Like(x, p, negate):
            let v = try eval(x, slots, row, group)
            let q = try eval(p, slots, row, group)
            if is_null(v) or is_null(q):
                return ok(VNull)

            let m = try like_bytes(v, q)
            return ok(VBool(m != negate))
        InList(x, items, negate):
            let v = try eval(x, slots, row, group)
            var vals = List[Value]()

            for it in items:
                let iv = try eval(it, slots, row, group)
                vals.append(iv)

            if is_null(v):
                return ok(VNull)

            var sawnull = false
            var found = false

            for iv in vals:
                if is_null(iv):
                    sawnull = true
                else:
                    let c = try compare_values(v, iv)

                    if c == 0:
                        found = true
                        break

            var t = 0

            if found:
                t = 1
            else if sawnull:
                t = 2

            if negate:
                t = tri_not(t)
            return ok(tri_value(t))
        Between(x, lo, hi, negate):
            let v = try eval(x, slots, row, group)
            let a = try eval(lo, slots, row, group)
            let b = try eval(hi, slots, row, group)
            let t1 = try compare_op(">=", v, a)
            let t2 = try compare_op("<=", v, b)
            var t = tri_and(try tri(t1), try tri(t2))
            if negate:
                t = tri_not(t)
            return ok(tri_value(t))
        Binary(op, l, r):
            if op == "AND":
                let a = try tri(try eval(l, slots, row, group))
                if a == 0:
                    return ok(VBool(false))

                let b = try tri(try eval(r, slots, row, group))
                return ok(tri_value(tri_and(a, b)))

            if op == "OR":
                let a = try tri(try eval(l, slots, row, group))
                if a == 1:
                    return ok(VBool(true))

                let b = try tri(try eval(r, slots, row, group))
                return ok(tri_value(tri_or(a, b)))

            let a = try eval(l, slots, row, group)
            let b = try eval(r, slots, row, group)
            return binary_op(op, a, b)
        Call(name, args, distinct, star):
            if is_agg(name):
                return aggregate(name, args, distinct, star, slots, group)

            var vals = List[Value]()

            for a in args:
                let v = try eval(a, slots, row, group)
                vals.append(v)

            if name == "COALESCE":
                for v in vals:
                    if not is_null(v):
                        return ok(v.clone())
                return ok(VNull)

            for v in vals:
                if is_null(v):
                    return ok(VNull)
            return scalar_call(name, vals)

fn aggregate(
    name: String,
    args: List[Expr],
    distinct: Bool,
    star: Bool,
    slots: List[Slot],
    group: List[List[Value]]
) Result[Value, Fail]:
    if star:
        return ok(VInt(group.length()))

    let none_group = List[List[Value]]()
    var vals = List[Value]()

    for grow in group:
        let v = try eval(args[0], slots, grow, none_group)
        if not is_null(v):
            vals.append(v)

    if distinct:
        vals = distinct_values(vals)
    if name == "COUNT":
        return ok(VInt(vals.length()))
    if vals.length() == 0:
        return ok(VNull)

    if name == "SUM":
        var total = 0

        for v in vals:
            let x = try as_int(v)
            total += x

        return ok(VInt(total))

    var best = vals[0].clone()

    for v in vals:
        if rank(v) < 2:
            return error(Fail("type error"))

        let c = try compare_values(v, best)
        if (name == "MIN" and c < 0) or (name == "MAX" and c > 0):
            best = v.clone()

    return ok(best)

fn scalar_call(name: String, vals: List[Value]) Result[Value, Fail]:
    if name == "UPPER" or name == "LOWER":
        let s = try as_text(vals[0])
        var out = List[Int]()

        for b in bytes_of(s):
            if name == "UPPER" and b >= 97 and b <= 122:
                out.append(b - 32)
            else if name == "LOWER" and b >= 65 and b <= 90:
                out.append(b + 32)
            else:
                out.append(b)

        return ok(VText(text_of_bytes(out)))

    if name == "LENGTH":
        let s = try as_text(vals[0])
        return ok(VInt(s.byte_length()))

    if name == "ABS":
        let k = try as_int(vals[0])
        return ok(VInt(k.abs()))

    let s = try as_text(vals[0])
    let start = try as_int(vals[1])
    let len = try as_int(vals[2])
    let bs = bytes_of(s)
    let blen = bs.length()
    var out = List[Int]()

    if len > 0 and start <= blen:
        var hi = blen

        if start < 1:
            hi = (start + len - 1).min(blen)
        else if len - 1 < blen - start:
            hi = start + len - 1

        var i = 1
        if start > 1:
            i = start

        while i <= hi:
            out.append(bs[i - 1])
            i += 1

    return ok(VText(text_of_bytes(out)))

# ---------- SELECT ----------

type Group:
    row: List[Value]
    rows: List[List[Value]]

type SortKey:
    mode: Int
    index: Int
    e: Expr
    desc: Bool

type SortRec:
    outs: List[Value]
    keys: List[Value]

fn column_name(e: Expr) String:
    match e:
        Col(_, n):
            return n.clone()
        _:
            return "?column?"

fn prefix_slots(slots: List[Slot], n: Int) List[Slot]:
    var out = List[Slot]()
    for i in 0..n:
        out.append(Slot(slots[i].alias.clone(), slots[i].col.clone()))
    return out

fn names_index(names: List[String], name: String) Int:
    for i in 0..names.length():
        if names[i] == name:
            return i
    return -1

fn plan_order(
    o: OrderItem,
    names: List[String],
    slots: List[Slot],
    cx: Check
) Result[SortKey, Fail]:
    match o.e:
        Lit(v):
            if rank(v) == 2:
                let pos = int_of(v)
                if pos < 1 or pos > names.length():
                    return error(Fail("bad ORDER BY position"))

                return ok(SortKey(1, pos - 1, o.e.clone(), o.desc))
        Col(t, n):
            if t == "":
                let k = names_index(names, n)
                if k >= 0:
                    return ok(SortKey(1, k, o.e.clone(), o.desc))
        _:
            unit

    try check_expr(o.e, slots, cx, false)
    return ok(SortKey(0, 0, o.e.clone(), o.desc))

fn render_row(vals: List[Value]) String:
    var parts = List[String]()
    for v in vals:
        parts.append(show(v))
    return parts.join("|")

fn compare_recs(a: SortRec, b: SortRec, descs: List[Bool]) Int:
    for i in 0..a.keys.length():
        var c = order_of(a.keys[i], b.keys[i])
        if descs[i]:
            c = -c
        if c != 0:
            return c

    return 0

fn run_select(db: List[Table], sel: Select) Result[String, Fail]:
    var refs = List[TRef]()
    for r in sel.source:
        refs.append(r.clone())
    for j in sel.joins:
        refs.append(j.tref.clone())

    let nsrc = sel.source.length()

    # Step 1: tables exist, aliases are unique.
    var tabs = List[Int]()

    for r in refs:
        let ti = find_table(db, r.table)
        if ti < 0:
            return error(Fail("no such table: {r.table}"))

        tabs.append(ti)

    var slots = List[Slot]()
    var ends = List[Int]()
    var aliases = List[String]()

    for k in 0..refs.length():
        let alias = refs[k].alias.clone()
        if aliases.contains(alias):
            return error(Fail("duplicate alias: {alias}"))

        aliases.append(alias.clone())
        for c in db[tabs[k]].cols:
            slots.append(Slot(alias.clone(), c.name.clone()))
        ends.append(slots.length())

    # Step 2: name resolution, in the specified order.
    for j in 0..sel.joins.length():
        let pre = prefix_slots(slots, ends[nsrc + j])
        try check_expr(sel.joins[j].on, pre, plain_check(), false)

    for it in sel.items:
        match it:
            AllCols(t):
                if t != "" and not aliases.contains(t):
                    return error(Fail("no such table: {t}"))
            ExprItem(_, _):
                unit

    var group_idx = List[Int]()

    for g in sel.groups:
        match g:
            Col(t, n):
                let gi = try find_col(slots, t, n)
                group_idx.append(gi)
            _:
                unit

    try check_expr(sel.cond, slots, plain_check(), false)

    var aggregated = sel.groups.length() > 0 or sel.has_having

    for it in sel.items:
        match it:
            ExprItem(e, _):
                if contains_agg(e):
                    aggregated = true
            AllCols(_):
                unit

    for o in sel.order:
        if contains_agg(o.e):
            aggregated = true

    let cx = Check(true, aggregated, group_idx.clone())
    var names = List[String]()
    var exprs = List[Expr]()

    for it in sel.items:
        match it:
            AllCols(t):
                for si in 0..slots.length():
                    if t == "" or slots[si].alias == t:
                        let e = Col(slots[si].alias.clone(), slots[si].col.clone())
                        try check_expr(e, slots, cx, false)
                        names.append(slots[si].col.clone())
                        exprs.append(e)
            ExprItem(e, alias):
                try check_expr(e, slots, cx, false)

                var nm = column_name(e)
                if alias != "":
                    nm = alias.clone()
                names.append(nm)
                exprs.append(e.clone())

    if sel.has_having:
        try check_expr(sel.having, slots, cx, false)

    var keys = List[SortKey]()

    for o in sel.order:
        let k = try plan_order(o, names, slots, cx)
        keys.append(k)

    # Step 3: FROM and JOIN rows.
    var rows = List[List[Value]]()

    if refs.length() == 0:
        rows.append(List[Value]())
    else:
        for r in db[tabs[0]].rows:
            rows.append(r.clone())

    let none_group = List[List[Value]]()

    for j in 0..sel.joins.length():
        let tj = tabs[nsrc + j]
        let pre = prefix_slots(slots, ends[nsrc + j])
        var nxt = List[List[Value]]()

        for outer in rows:
            var matched = false

            for inner in db[tj].rows:
                var combined = outer.clone()
                for v in inner:
                    combined.append(v.clone())

                let cv = try eval(sel.joins[j].on, pre, combined, none_group)
                let t = try tri(cv)

                if t == 1:
                    matched = true
                    nxt.append(combined)

            if not matched and sel.joins[j].left:
                var padded = outer.clone()
                for i in 0..db[tj].cols.length():
                    padded.append(VNull)
                nxt.append(padded)

        rows = nxt

    # Step 4: WHERE.
    var filtered = List[List[Value]]()

    for r in rows:
        let v = try eval(sel.cond, slots, r, none_group)
        let t = try tri(v)
        if t == 1:
            filtered.append(r.clone())

    # Step 5: grouping.
    var units = List[Group]()

    if aggregated and sel.groups.length() > 0:
        var index = Map[String, Int]()
        var members = List[List[List[Value]]]()

        for r in filtered:
            var k = ""
            for gi in group_idx:
                k = k + enc(r[gi])

            if let slot = index.get(k):
                members[slot].append(r.clone())
            else:
                var fresh = List[List[Value]]()
                fresh.append(r.clone())
                index.add(k, members.length())
                members.append(fresh)

        for g in 0..members.length():
            units.append(Group(members[g][0].clone(), members[g].clone()))
    else if aggregated:
        var rep = List[Value]()

        if filtered.length() > 0:
            rep = filtered[0].clone()
        else:
            for i in 0..slots.length():
                rep.append(VNull)

        units.append(Group(rep, filtered.clone()))
    else:
        for r in filtered:
            units.append(Group(r.clone(), List[List[Value]]()))

    # Step 6: HAVING per group.
    var kept = List[Group]()

    for u in units:
        let hv = try eval(sel.having, slots, u.row, u.rows)
        let ht = try tri(hv)
        if ht == 1:
            kept.append(u.clone())

    # Step 7: select list per row.
    var outs = List[List[Value]]()

    for u in kept:
        var out = List[Value]()

        for e in exprs:
            let v = try eval(e, slots, u.row, u.rows)
            out.append(v)

        outs.append(out)

    # Step 8: ORDER BY keys per row.
    var recs = List[SortRec]()

    for i in 0..kept.length():
        var ks = List[Value]()

        for k in keys:
            if k.mode == 1:
                ks.append(outs[i][k.index].clone())
            else:
                let kv = try eval(k.e, slots, kept[i].row, kept[i].rows)
                ks.append(kv)

        recs.append(SortRec(outs[i].clone(), ks))

    # Step 9: DISTINCT, ORDER BY, OFFSET, LIMIT.
    var uniq = List[SortRec]()
    var seen = Set[String]()

    for rec in recs:
        if sel.distinct:
            let k = enc_row(rec.outs)
            if seen.contains(k):
                continue

            seen.add(k)

        uniq.append(rec.clone())

    if keys.length() > 0:
        var descs = List[Bool]()
        for k in keys:
            descs.append(k.desc)
        uniq = uniq.sorted(fn a, b: compare_recs(a, b, descs))

    var lines = List[String]()
    lines.append(names.join("|"))

    var emitted = 0

    for i in 0..uniq.length():
        if i < sel.offset:
            continue
        if sel.limit >= 0 and emitted >= sel.limit:
            break

        lines.append(render_row(uniq[i].outs))
        emitted += 1

    lines.append("({emitted} rows)")
    return ok(lines.join("\n") + "\n")

# ---------- DDL and DML ----------

type Table:
    name: String
    cols: List[ColDef]
    rows: List[List[Value]]

# Column-level constraints for one full row, in declaration order.
fn check_row(cols: List[ColDef], row: List[Value]) Result[Unit, Fail]:
    for i in 0..cols.length():
        let c = cols[i]
        let v = row[i]

        if is_null(v):
            if c.notnull:
                return error(Fail("NOT NULL constraint failed: {c.name}"))
        else if c.ty == "INT" and rank(v) != 2:
            return error(Fail("type mismatch in column {c.name}"))
        else if c.ty == "TEXT" and rank(v) != 3:
            return error(Fail("type mismatch in column {c.name}"))

    return ok(unit)

# Duplicate primary key check over existing rows followed by added rows.
fn check_pk(
    cols: List[ColDef],
    existing: List[List[Value]],
    added: List[List[Value]]
) Result[Unit, Fail]:
    var pk = -1
    for i in 0..cols.length():
        if cols[i].pk:
            pk = i
    if pk < 0:
        return ok(unit)

    var seen = Set[String]()
    for r in existing:
        seen.add(show(r[pk]))

    for r in added:
        let k = show(r[pk])
        if seen.contains(k):
            return error(Fail("duplicate primary key: {k}"))

        seen.add(k)

    return ok(unit)

fn create_table(var db: List[Table], name: String, defs: List[ColDef]) Result[
    String, Fail
]:
    if find_table(db, name) >= 0:
        return error(Fail("table {name} already exists"))

    var cols = List[ColDef]()
    var has_pk = false

    for c in defs:
        if column_index(cols, c.name) >= 0:
            return error(Fail("duplicate column: {c.name}"))

        if c.pk:
            if has_pk:
                return error(Fail("multiple primary keys"))

            has_pk = true

        cols.append(c.clone())

    db.append(Table(name.clone(), cols, List[List[Value]]()))
    return ok("ok\n")

fn drop_table(var db: List[Table], name: String) Result[String, Fail]:
    let ti = find_table(db, name)
    if ti < 0:
        return error(Fail("no such table: {name}"))

    db.remove(ti)
    return ok("ok\n")

fn insert_rows(
    var db: List[Table], name: String, cols: List[String], has_cols: Bool,
    rows: List[List[Expr]]
) Result[String, Fail]:
    let ti = find_table(db, name)
    if ti < 0:
        return error(Fail("no such table: {name}"))

    var targets = List[Int]()

    if has_cols:
        for c in cols:
            let idx = column_index(db[ti].cols, c)
            if idx < 0:
                return error(Fail("no such column: {c}"))
            if targets.contains(idx):
                return error(Fail("duplicate column: {c}"))

            targets.append(idx)
    else:
        for i in 0..db[ti].cols.length():
            targets.append(i)

    let no_slots = List[Slot]()
    let no_row = List[Value]()
    let none_group = List[List[Value]]()
    var new_rows = List[List[Value]]()

    for r in rows:
        if r.length() != targets.length():
            return error(Fail("wrong number of values"))

        for e in r:
            try check_expr(e, no_slots, plain_check(), false)

        var vals = List[Value]()

        for e in r:
            let v = try eval(e, no_slots, no_row, none_group)
            vals.append(v)

        var full = List[Value]()
        for i in 0..db[ti].cols.length():
            full.append(VNull)
        for k in 0..targets.length():
            full[targets[k]] = vals[k].clone()
        try check_row(db[ti].cols, full)
        new_rows.append(full)

    try check_pk(db[ti].cols, db[ti].rows, new_rows)

    let count = new_rows.length()
    for r in new_rows:
        db[ti].rows.append(r.clone())
    return ok("inserted {count}\n")

fn update_rows(var db: List[Table], name: String, sets: List[Assign], cond: Expr) Result[
    String, Fail
]:
    let ti = find_table(db, name)
    if ti < 0:
        return error(Fail("no such table: {name}"))

    let slots = prefix_slots(table_slots(db[ti], name), db[ti].cols.length())
    var idxs = List[Int]()

    for a in sets:
        let idx = column_index(db[ti].cols, a.col)
        if idx < 0:
            return error(Fail("no such column: {a.col}"))

        idxs.append(idx)

    for a in sets:
        try check_expr(a.e, slots, plain_check(), false)
    try check_expr(cond, slots, plain_check(), false)

    let none_group = List[List[Value]]()
    var new_rows = List[List[Value]]()
    var count = 0

    for r in db[ti].rows:
        let t = try tri(try eval(cond, slots, r, none_group))

        if t == 1:
            var nr = r.clone()

            for k in 0..sets.length():
                let v = try eval(sets[k].e, slots, r, none_group)
                nr[idxs[k]] = v

            try check_row(db[ti].cols, nr)
            count += 1
            new_rows.append(nr)
        else:
            new_rows.append(r.clone())

    try check_pk(db[ti].cols, List[List[Value]](), new_rows)
    db[ti].rows = new_rows
    return ok("updated {count}\n")

fn table_slots(t: Table, alias: String) List[Slot]:
    var out = List[Slot]()
    for c in t.cols:
        out.append(Slot(alias.clone(), c.name.clone()))
    return out

fn delete_rows(var db: List[Table], name: String, cond: Expr) Result[String, Fail]:
    let ti = find_table(db, name)
    if ti < 0:
        return error(Fail("no such table: {name}"))

    let slots = table_slots(db[ti], name)
    try check_expr(cond, slots, plain_check(), false)

    let none_group = List[List[Value]]()
    var kept = List[List[Value]]()
    var count = 0

    for r in db[ti].rows:
        let t = try tri(try eval(cond, slots, r, none_group))

        if t == 1:
            count += 1
        else:
            kept.append(r.clone())

    db[ti].rows = kept
    return ok("deleted {count}\n")

fn execute(var db: List[Table], st: Stmt) Result[String, Fail]:
    match st:
        CreateTable(name, defs):
            return create_table(var db, name, defs)
        DropTable(name):
            return drop_table(var db, name)
        InsertRows(name, cols, has_cols, rows):
            return insert_rows(var db, name, cols, has_cols, rows)
        UpdateRows(name, sets, cond):
            return update_rows(var db, name, sets, cond)
        DeleteRows(name, cond):
            return delete_rows(var db, name, cond)
        Query(sel):
            return run_select(db, sel)

fn exec_tokens(var db: List[Table], toks: List[Tok]) Result[String, Fail]:
    var p = Parser(toks.clone(), 0)
    let st = try p.statement()
    if p.pos != toks.length():
        return error(Fail("syntax error"))

    return execute(var db, st)

fn run_statement(var db: List[Table], toks: List[Tok]) String:
    let r = exec_tokens(var db, toks)
    if r.is_error():
        return "error: " + r.err().message() + "\n"

    return r.get().clone()

export fn main() Int:
    let text = read_all(stdin()).get().decode_utf8().get("")
    var db = List[Table]()
    var out = List[String]()
    for toks in statements(lex(text)):
        if toks.length() > 0:
            out.append(run_statement(var db, toks))
    stdout().write(out.join("")).get()
    return 0

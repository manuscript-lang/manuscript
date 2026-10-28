import {stdin, stdout, read_all} from "@std/io.ms"
import {Bytes, BytesBuilder} from "@std/bytes.ms"

let KEYWORDS = ["SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET", "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN", "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"]
let SYMBOL_CODES = [61, 60, 62, 43, 45, 42, 47, 37, 40, 41, 44, 46]
let HEX_DIGITS = "0123456789abcdef"
let MAX_INT = 9223372036854775807

# ---------------------------------------------------------------- errors and values

type SqlErr:
    msg: String

impl Error for SqlErr:
    fn message() String:
        return self.msg.clone()

fn sql_error(msg: String) SqlErr:
    return SqlErr(msg: msg)

fn syntax_error() SqlErr:
    return SqlErr(msg: "syntax error")

fn type_error() SqlErr:
    return SqlErr(msg: "type error")

type Value:
    case VNull
    case VInt(i: Int)
    case VBool(b: Bool)
    case VText(t: Bytes)

fn is_null(v: Value) Bool:
    match v:
        VNull:
            return true
        _:
            return false

fn as_int(v: Value) Optional[Int]:
    match v:
        VInt(i):
            return some(i)
        _:
            return none

fn as_bool(v: Value) Optional[Bool]:
    match v:
        VBool(b):
            return some(b)
        _:
            return none

fn as_text(v: Value) Optional[Bytes]:
    match v:
        VText(t):
            return some(t.clone())
        _:
            return none

fn value_text(v: Value) Bytes:
    match v:
        VNull:
            return "NULL".to_bytes()
        VInt(i):
            return "{i}".to_bytes()
        VBool(b):
            if b:
                return "true".to_bytes()
            return "false".to_bytes()
        VText(t):
            return t.clone()

fn value_string(v: Value) String:
    match v:
        VInt(i):
            return "{i}"
        VText(t):
            if let s = t.decode_utf8():
                return s
            return "?"
        _:
            return "?"

fn hex_of(t: Bytes) String:
    var out = ""
    for k in 0..t.length():
        let c = byte_at(t, k)
        out = out + HEX_DIGITS.get(c / 16) + HEX_DIGITS.get(c % 16)
    return out

# A key that is equal for two values exactly when they are equal (NULLs equal each other).
fn value_key(v: Value) String:
    match v:
        VNull:
            return "N;"
        VInt(i):
            return "I{i};"
        VBool(b):
            if b:
                return "B1;"
            return "B0;"
        VText(t):
            return "T" + hex_of(t) + ";"

fn row_key(vals: List[Value]) String:
    var out = ""
    for v in vals:
        out = out + value_key(v)
    return out

fn group_key(row: List[Value], idxs: List[Int]) String:
    var out = ""
    for k in idxs:
        out = out + value_key(row[k])
    return out

# ---------------------------------------------------------------- bytes helpers

fn byte_at(src: Bytes, i: Int) Int:
    if i < 0 or i >= src.length():
        return -1
    return src.get(i).to_int()

fn empty_bytes() Bytes:
    return "".to_bytes()

fn byte_value(c: Int) UInt8:
    return c.to_uint8().get()

fn bytes_cmp(a: Bytes, b: Bytes) Int:
    let na = a.length()
    let nb = b.length()
    var k = 0
    while k < na and k < nb:
        let x = byte_at(a, k)
        let y = byte_at(b, k)
        if x != y:
            if x < y:
                return -1
            return 1
        k += 1
    if na < nb:
        return -1
    if na > nb:
        return 1
    return 0

fn ascii_case(t: Bytes, upper: Bool) Bytes:
    var sb = BytesBuilder()
    for k in 0..t.length():
        var c = byte_at(t, k)
        if upper and c >= 97 and c <= 122:
            c = c - 32
        if not upper and c >= 65 and c <= 90:
            c = c + 32
        sb.append(byte_value(c))
    return sb.build()

fn substr(t: Bytes, start: Int, len: Int) Bytes:
    let n = t.length()
    if len <= 0:
        return empty_bytes()
    var lo = start
    if lo < 1:
        lo = 1
    if lo > n:
        return empty_bytes()
    var hi = start + len - 1
    if hi > n:
        hi = n
    if hi < lo:
        return empty_bytes()
    return t.slice(lo - 1, hi).get()

# LIKE with `%` (any run), `_` (one byte), other bytes literal.
fn like_match(s: Bytes, p: Bytes) Bool:
    var si = 0
    var pi = 0
    var star_p = -1
    var star_s = 0
    let np = p.length()
    while si < s.length():
        if pi < np and byte_at(p, pi) == 37:
            star_p = pi
            star_s = si
            pi += 1
        else if pi < np and (byte_at(p, pi) == 95 or byte_at(p, pi) == byte_at(s, si)):
            si += 1
            pi += 1
        else if star_p >= 0:
            pi = star_p + 1
            star_s += 1
            si = star_s
        else:
            return false
    while pi < np and byte_at(p, pi) == 37:
        pi += 1
    return pi == np

# ---------------------------------------------------------------- comparison

# Comparison of two non-NULL values of the same type.
fn typed_cmp(a: Value, b: Value) Result[Int, SqlErr]:
    if let x = as_int(a):
        if let y = as_int(b):
            return ok(x.compare(y))
    if let x = as_text(a):
        if let y = as_text(b):
            return ok(bytes_cmp(x, y))
    return error(type_error())

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

# Total order used by ORDER BY: NULL < BOOL < INT < TEXT.
fn order_cmp(a: Value, b: Value) Int:
    let ra = rank(a)
    let rb = rank(b)
    if ra != rb:
        return ra.compare(rb)
    if let x = as_int(a):
        if let y = as_int(b):
            return x.compare(y)
    if let x = as_text(a):
        if let y = as_text(b):
            return bytes_cmp(x, y)
    if let x = as_bool(a):
        if let y = as_bool(b):
            if x == y:
                return 0
            if y:
                return -1
            return 1
    return 0

# Three-valued truth: 1 true, 0 false, -1 NULL. Only BOOL and NULL are allowed.
fn tri_of(v: Value) Result[Int, SqlErr]:
    match v:
        VNull:
            return ok(-1)
        VBool(b):
            if b:
                return ok(1)
            return ok(0)
        _:
            return error(type_error())

fn tri_value(t: Int) Value:
    if t == 1:
        return VBool(true)
    if t == 0:
        return VBool(false)
    return VNull

fn and3(a: Int, b: Int) Int:
    if a == 0 or b == 0:
        return 0
    if a == 1 and b == 1:
        return 1
    return -1

fn or3(a: Int, b: Int) Int:
    if a == 1 or b == 1:
        return 1
    if a == 0 and b == 0:
        return 0
    return -1

fn not3(a: Int) Int:
    if a < 0:
        return -1
    return 1 - a

# ---------------------------------------------------------------- AST

type ColDef:
    name: String
    is_int: Bool
    primary: Bool
    not_null: Bool

type Expr:
    case Lit(v: Value)
    case Col(table: String, name: String, idx: Int)
    case Neg(e: Expr)
    case Not(e: Expr)
    case Bin(op: String, l: Expr, r: Expr)
    case IsNull(e: Expr, neg: Bool)
    case Like(e: Expr, pat: Expr, neg: Bool)
    case InList(e: Expr, items: List[Expr], neg: Bool)
    case Between(e: Expr, lo: Expr, hi: Expr, neg: Bool)
    case Call(name: String, args: List[Expr], distinct: Bool, star: Bool)

type SelItem:
    case StarItem
    case TStarItem(t: String)
    case ExprItem(e: Expr, alias: String)

type TableRef:
    name: String
    alias: String

type Join:
    is_left: Bool
    table: TableRef
    on: Expr

type OrderItem:
    e: Expr
    desc: Bool

type Select:
    distinct_rows: Bool
    items: List[SelItem]
    from_ref: Optional[TableRef]
    joins: List[Join]
    where_expr: Optional[Expr]
    group_by: List[Expr]
    having_expr: Optional[Expr]
    order_by: List[OrderItem]
    limit: Int
    offset: Int

type Stmt:
    case CreateStmt(name: String, cols: List[ColDef])
    case DropStmt(name: String)
    case InsertStmt(name: String, cols: List[String], rows: List[List[Expr]])
    case UpdateStmt(name: String, names: List[String], vals: List[Expr], where_expr: Optional[Expr])
    case DeleteStmt(name: String, where_expr: Optional[Expr])
    case SelectStmt(sel: Select)

type Token:
    kind: String
    text: String
    num: Int
    str: Bytes

fn sym_token(text: String) Token:
    return Token(kind: "sym", text: text, num: 0, str: empty_bytes())

# ---------------------------------------------------------------- lexer and splitter

fn is_letter(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_digit(c: Int) Bool:
    return c >= 48 and c <= 57

fn lex(src: Bytes) Result[List[Token], SqlErr]:
    var toks = List[Token]()
    let n = src.length()
    var i = 0
    while i < n:
        let c = byte_at(src, i)
        if c == 32 or c == 9 or c == 10 or c == 13:
            i += 1
        else if c == 45 and byte_at(src, i + 1) == 45:
            while i < n and byte_at(src, i) != 10:
                i += 1
        else if is_letter(c):
            let start = i
            while is_letter(byte_at(src, i)) or is_digit(byte_at(src, i)):
                i += 1
            let word = src.decode_utf8_range(start, i).get()
            let upper = word.upper()
            if KEYWORDS.contains(upper):
                toks.append(Token(kind: "kw", text: upper, num: 0, str: empty_bytes()))
            else:
                toks.append(Token(kind: "id", text: word, num: 0, str: empty_bytes()))
        else if is_digit(c):
            var v = 0
            while is_digit(byte_at(src, i)):
                let d = byte_at(src, i) - 48
                if v > (MAX_INT - d) / 10:
                    return error(syntax_error())
                v = v * 10 + d
                i += 1
            toks.append(Token(kind: "int", text: "", num: v, str: empty_bytes()))
        else if c == 39:
            var sb = BytesBuilder()
            var seg = i + 1
            i += 1
            var closed = false
            while i < n and not closed:
                if byte_at(src, i) == 39:
                    if byte_at(src, i + 1) == 39:
                        sb.append_bytes(src.slice(seg, i + 1).get())
                        i += 2
                        seg = i
                    else:
                        closed = true
                else:
                    i += 1
            if not closed:
                return error(syntax_error())
            sb.append_bytes(src.slice(seg, i).get())
            i += 1
            toks.append(Token(kind: "str", text: "", num: 0, str: sb.build()))
        else if c == 60 and byte_at(src, i + 1) == 62:
            toks.append(sym_token("<>"))
            i += 2
        else if c == 60 and byte_at(src, i + 1) == 61:
            toks.append(sym_token("<="))
            i += 2
        else if c == 62 and byte_at(src, i + 1) == 61:
            toks.append(sym_token(">="))
            i += 2
        else if c == 33 and byte_at(src, i + 1) == 61:
            toks.append(sym_token("!="))
            i += 2
        else if c == 124 and byte_at(src, i + 1) == 124:
            toks.append(sym_token("||"))
            i += 2
        else if SYMBOL_CODES.contains(c):
            toks.append(sym_token(src.decode_utf8_range(i, i + 1).get()))
            i += 1
        else:
            return error(syntax_error())
    toks.append(Token(kind: "eof", text: "", num: 0, str: empty_bytes()))
    return ok(toks)

# Splits the script at `;` outside string literals and comments.
fn split_statements(src: Bytes) List[Bytes]:
    var parts = List[Bytes]()
    let n = src.length()
    var start = 0
    var i = 0
    while i < n:
        let c = byte_at(src, i)
        if c == 39:
            i += 1
            var closed = false
            while i < n and not closed:
                if byte_at(src, i) == 39:
                    if byte_at(src, i + 1) == 39:
                        i += 2
                    else:
                        closed = true
                        i += 1
                else:
                    i += 1
        else if c == 45 and byte_at(src, i + 1) == 45:
            while i < n and byte_at(src, i) != 10:
                i += 1
        else if c == 59:
            parts.append(src.slice(start, i).get())
            i += 1
            start = i
        else:
            i += 1
    parts.append(src.slice(start, n).get())
    return parts

# ---------------------------------------------------------------- parser

type Parser:
    toks: List[Token]
    pos: Int

impl Parser:
    fn at_kind(kind: String) Bool:
        return self.toks[self.pos].kind == kind

    fn at_kw(word: String) Bool:
        let t = self.toks[self.pos]
        return t.kind == "kw" and t.text == word

    fn at_sym(sym: String) Bool:
        let t = self.toks[self.pos]
        return t.kind == "sym" and t.text == sym

    fn sym_at(k: Int, sym: String) Bool:
        if self.pos + k >= self.toks.length():
            return false
        let t = self.toks[self.pos + k]
        return t.kind == "sym" and t.text == sym

    var fn accept_kw(word: String) Bool:
        if self.at_kw(word):
            self.pos += 1
            return true
        return false

    var fn accept_sym(sym: String) Bool:
        if self.at_sym(sym):
            self.pos += 1
            return true
        return false

    var fn expect_kw(word: String) Result[Unit, SqlErr]:
        if not self.accept_kw(word):
            return error(syntax_error())
        return ok(unit)

    var fn expect_sym(sym: String) Result[Unit, SqlErr]:
        if not self.accept_sym(sym):
            return error(syntax_error())
        return ok(unit)

    var fn expect_id() Result[String, SqlErr]:
        if self.at_kind("id"):
            let name = self.toks[self.pos].text.clone()
            self.pos += 1
            return ok(name)
        return error(syntax_error())

    var fn expect_int() Result[Int, SqlErr]:
        if self.at_kind("int"):
            let v = self.toks[self.pos].num
            self.pos += 1
            return ok(v)
        return error(syntax_error())

    var fn parse_statement() Result[Stmt, SqlErr]:
        if self.accept_kw("CREATE"):
            try self.expect_kw("TABLE")
            let name = try self.expect_id()
            try self.expect_sym("(")
            var cols = List[ColDef]()
            let first = try self.parse_coldef()
            cols.append(first)
            while self.accept_sym(","):
                let c = try self.parse_coldef()
                cols.append(c)
            try self.expect_sym(")")
            return ok(CreateStmt(name: name, cols: cols))
        if self.accept_kw("DROP"):
            try self.expect_kw("TABLE")
            let name = try self.expect_id()
            return ok(DropStmt(name: name))
        if self.accept_kw("INSERT"):
            try self.expect_kw("INTO")
            let name = try self.expect_id()
            var names = List[String]()
            if self.accept_sym("("):
                let first = try self.expect_id()
                names.append(first)
                while self.accept_sym(","):
                    let more = try self.expect_id()
                    names.append(more)
                try self.expect_sym(")")
            try self.expect_kw("VALUES")
            var rows = List[List[Expr]]()
            let row1 = try self.parse_row()
            rows.append(row1)
            while self.accept_sym(","):
                let rown = try self.parse_row()
                rows.append(rown)
            return ok(InsertStmt(name: name, cols: names, rows: rows))
        if self.accept_kw("UPDATE"):
            let name = try self.expect_id()
            try self.expect_kw("SET")
            var names = List[String]()
            var vals = List[Expr]()
            let cn1 = try self.expect_id()
            try self.expect_sym("=")
            let v1 = try self.parse_expr()
            names.append(cn1)
            vals.append(v1)
            while self.accept_sym(","):
                let cn = try self.expect_id()
                try self.expect_sym("=")
                let v = try self.parse_expr()
                names.append(cn)
                vals.append(v)
            let where_expr = try self.parse_optional_where()
            return ok(UpdateStmt(name: name, names: names, vals: vals, where_expr: where_expr))
        if self.accept_kw("DELETE"):
            try self.expect_kw("FROM")
            let name = try self.expect_id()
            let where_expr = try self.parse_optional_where()
            return ok(DeleteStmt(name: name, where_expr: where_expr))
        if self.accept_kw("SELECT"):
            let sel = try self.parse_select()
            return ok(SelectStmt(sel: sel))
        return error(syntax_error())

    var fn parse_optional_where() Result[Optional[Expr], SqlErr]:
        if self.accept_kw("WHERE"):
            let cond = try self.parse_expr()
            return ok(some(cond))
        return ok(none)

    var fn parse_coldef() Result[ColDef, SqlErr]:
        let name = try self.expect_id()
        let type_name = try self.expect_id()
        let upper = type_name.upper()
        if upper != "INT" and upper != "TEXT":
            return error(syntax_error())
        var primary = false
        var not_null = false
        while true:
            if self.accept_kw("PRIMARY"):
                try self.expect_kw("KEY")
                primary = true
            else if self.accept_kw("NOT"):
                try self.expect_kw("NULL")
                not_null = true
            else:
                break
        return ok(ColDef(name: name, is_int: upper == "INT", primary: primary, not_null: not_null))

    var fn parse_row() Result[List[Expr], SqlErr]:
        try self.expect_sym("(")
        let vals = try self.parse_expr_list()
        try self.expect_sym(")")
        return ok(vals)

    var fn parse_select() Result[Select, SqlErr]:
        var sel = Select(distinct_rows: false, items: List[SelItem](), from_ref: none, joins: List[Join](), where_expr: none, group_by: List[Expr](), having_expr: none, order_by: List[OrderItem](), limit: -1, offset: 0)
        sel.distinct_rows = self.accept_kw("DISTINCT")
        let first = try self.parse_item()
        sel.items.append(first)
        while self.accept_sym(","):
            let item = try self.parse_item()
            sel.items.append(item)
        if self.accept_kw("FROM"):
            let base = try self.parse_tref()
            sel.from_ref = some(base)
            while self.at_kw("JOIN") or self.at_kw("INNER") or self.at_kw("LEFT"):
                var is_left = false
                if self.accept_kw("LEFT"):
                    is_left = true
                else:
                    self.accept_kw("INNER")
                try self.expect_kw("JOIN")
                let jt = try self.parse_tref()
                try self.expect_kw("ON")
                let on = try self.parse_expr()
                sel.joins.append(Join(is_left: is_left, table: jt, on: on))
        if self.accept_kw("WHERE"):
            let cond = try self.parse_expr()
            sel.where_expr = some(cond)
        if self.accept_kw("GROUP"):
            try self.expect_kw("BY")
            let g1 = try self.parse_colref()
            sel.group_by.append(g1)
            while self.accept_sym(","):
                let g = try self.parse_colref()
                sel.group_by.append(g)
        if self.accept_kw("HAVING"):
            let cond = try self.parse_expr()
            sel.having_expr = some(cond)
        if self.accept_kw("ORDER"):
            try self.expect_kw("BY")
            let o1 = try self.parse_order_item()
            sel.order_by.append(o1)
            while self.accept_sym(","):
                let o = try self.parse_order_item()
                sel.order_by.append(o)
        if self.accept_kw("LIMIT"):
            sel.limit = try self.expect_int()
            if self.accept_kw("OFFSET"):
                sel.offset = try self.expect_int()
        return ok(sel)

    var fn parse_item() Result[SelItem, SqlErr]:
        if self.accept_sym("*"):
            return ok(StarItem)
        if self.at_kind("id") and self.sym_at(1, ".") and self.sym_at(2, "*"):
            let t = self.toks[self.pos].text.clone()
            self.pos += 3
            return ok(TStarItem(t: t))
        let e = try self.parse_expr()
        var alias = ""
        if self.accept_kw("AS"):
            alias = try self.expect_id()
        return ok(ExprItem(e: e, alias: alias))

    var fn parse_tref() Result[TableRef, SqlErr]:
        let name = try self.expect_id()
        var alias = name.clone()
        if self.accept_kw("AS"):
            alias = try self.expect_id()
        else if self.at_kind("id"):
            alias = try self.expect_id()
        return ok(TableRef(name: name, alias: alias))

    var fn parse_colref() Result[Expr, SqlErr]:
        let first = try self.expect_id()
        if self.accept_sym("."):
            let second = try self.expect_id()
            return ok(Col(table: first, name: second, idx: -1))
        return ok(Col(table: "", name: first, idx: -1))

    var fn parse_order_item() Result[OrderItem, SqlErr]:
        let e = try self.parse_expr()
        var desc = false
        if self.accept_kw("DESC"):
            desc = true
        else:
            self.accept_kw("ASC")
        return ok(OrderItem(e: e, desc: desc))

    var fn parse_expr() Result[Expr, SqlErr]:
        var left = try self.parse_and()
        while self.accept_kw("OR"):
            let right = try self.parse_and()
            left = Bin(op: "OR", l: left, r: right)
        return ok(left)

    var fn parse_and() Result[Expr, SqlErr]:
        var left = try self.parse_not()
        while self.accept_kw("AND"):
            let right = try self.parse_not()
            left = Bin(op: "AND", l: left, r: right)
        return ok(left)

    var fn parse_not() Result[Expr, SqlErr]:
        if self.accept_kw("NOT"):
            let inner = try self.parse_not()
            return ok(Not(e: inner))
        return self.parse_cmp()

    var fn accept_cmp_op() String:
        for op in ["=", "<>", "<", "<=", ">", ">="]:
            if self.accept_sym(op):
                return op
        if self.accept_sym("!="):
            return "<>"
        return ""

    var fn parse_cmp() Result[Expr, SqlErr]:
        let left = try self.parse_add()
        let op = self.accept_cmp_op()
        if op != "":
            let right = try self.parse_add()
            return ok(Bin(op: op, l: left, r: right))
        if self.accept_kw("IS"):
            let neg = self.accept_kw("NOT")
            try self.expect_kw("NULL")
            return ok(IsNull(e: left, neg: neg))
        let neg = self.accept_kw("NOT")
        if self.accept_kw("LIKE"):
            let pat = try self.parse_add()
            return ok(Like(e: left, pat: pat, neg: neg))
        if self.accept_kw("IN"):
            try self.expect_sym("(")
            let items = try self.parse_expr_list()
            try self.expect_sym(")")
            return ok(InList(e: left, items: items, neg: neg))
        if self.accept_kw("BETWEEN"):
            let lo = try self.parse_add()
            try self.expect_kw("AND")
            let hi = try self.parse_add()
            return ok(Between(e: left, lo: lo, hi: hi, neg: neg))
        if neg:
            return error(syntax_error())
        return ok(left)

    var fn parse_add() Result[Expr, SqlErr]:
        var left = try self.parse_mul()
        while self.at_sym("+") or self.at_sym("-") or self.at_sym("||"):
            let op = self.toks[self.pos].text.clone()
            self.pos += 1
            let right = try self.parse_mul()
            left = Bin(op: op, l: left, r: right)
        return ok(left)

    var fn parse_mul() Result[Expr, SqlErr]:
        var left = try self.parse_unary()
        while self.at_sym("*") or self.at_sym("/") or self.at_sym("%"):
            let op = self.toks[self.pos].text.clone()
            self.pos += 1
            let right = try self.parse_unary()
            left = Bin(op: op, l: left, r: right)
        return ok(left)

    var fn parse_unary() Result[Expr, SqlErr]:
        if self.accept_sym("-"):
            let inner = try self.parse_unary()
            return ok(Neg(e: inner))
        return self.parse_primary()

    var fn parse_expr_list() Result[List[Expr], SqlErr]:
        var items = List[Expr]()
        let first = try self.parse_expr()
        items.append(first)
        while self.accept_sym(","):
            let e = try self.parse_expr()
            items.append(e)
        return ok(items)

    var fn parse_primary() Result[Expr, SqlErr]:
        let t = self.toks[self.pos].clone()
        if t.kind == "int":
            self.pos += 1
            return ok(Lit(v: VInt(t.num)))
        if t.kind == "str":
            self.pos += 1
            return ok(Lit(v: VText(t.str.clone())))
        if t.kind == "kw" and t.text == "NULL":
            self.pos += 1
            return ok(Lit(v: VNull))
        if self.accept_sym("("):
            let inner = try self.parse_expr()
            try self.expect_sym(")")
            return ok(inner)
        if t.kind == "id":
            self.pos += 1
            if self.accept_sym("("):
                return self.parse_call(t.text.upper())
            if self.accept_sym("."):
                let col = try self.expect_id()
                return ok(Col(table: t.text.clone(), name: col, idx: -1))
            return ok(Col(table: "", name: t.text.clone(), idx: -1))
        return error(syntax_error())

    var fn parse_call(name: String) Result[Expr, SqlErr]:
        let distinct = self.accept_kw("DISTINCT")
        if self.accept_sym("*"):
            try self.expect_sym(")")
            return ok(Call(name: name, args: List[Expr](), distinct: distinct, star: true))
        if self.accept_sym(")"):
            return ok(Call(name: name, args: List[Expr](), distinct: distinct, star: false))
        let args = try self.parse_expr_list()
        try self.expect_sym(")")
        return ok(Call(name: name, args: args, distinct: distinct, star: false))

fn parse_statement_text(text: Bytes) Result[Stmt, SqlErr]:
    let toks = try lex(text)
    var p = Parser(toks: toks, pos: 0)
    let stmt = try p.parse_statement()
    if not p.at_kind("eof"):
        return error(syntax_error())
    return ok(stmt)

# ---------------------------------------------------------------- tables

type Table:
    name: String
    cols: List[ColDef]
    rows: List[List[Value]]

type ScopeCol:
    alias: String
    name: String
    idx: Int

fn find_table(tables: List[Table], name: String) Optional[Int]:
    for k in 0..tables.length():
        if tables[k].name == name:
            return some(k)
    return none

fn table_index(tables: List[Table], name: String) Result[Int, SqlErr]:
    if let k = find_table(tables, name):
        return ok(k)
    return error(sql_error("no such table: {name}"))

fn column_index(t: Table, name: String) Optional[Int]:
    for k in 0..t.cols.length():
        if t.cols[k].name == name:
            return some(k)
    return none

fn pk_index(t: Table) Int:
    for k in 0..t.cols.length():
        if t.cols[k].primary:
            return k
    return -1

fn table_scope(t: Table, alias: String, offset: Int) List[ScopeCol]:
    var out = List[ScopeCol]()
    for k in 0..t.cols.length():
        out.append(ScopeCol(alias: alias.clone(), name: t.cols[k].name.clone(), idx: offset + k))
    return out

fn is_int_value(v: Value) Bool:
    match v:
        VInt(_):
            return true
        _:
            return false

fn is_text_value(v: Value) Bool:
    match v:
        VText(_):
            return true
        _:
            return false

# Checks NOT NULL and type constraints of one full row, in column order.
fn check_row(t: Table, row: List[Value]) Result[Unit, SqlErr]:
    for c in 0..t.cols.length():
        let col = t.cols[c]
        let v = row[c]
        if is_null(v):
            if col.not_null:
                return error(sql_error("NOT NULL constraint failed: {col.name}"))
        else:
            var good = false
            if col.is_int:
                good = is_int_value(v)
            else:
                good = is_text_value(v)
            if not good:
                return error(sql_error("type mismatch in column {col.name}"))
    return ok(unit)

fn check_pk(t: Table, rows: List[List[Value]]) Result[Unit, SqlErr]:
    let pk = pk_index(t)
    if pk < 0:
        return ok(unit)
    var seen = Map[String, Bool]()
    for row in rows:
        let k = value_key(row[pk])
        if seen.contains(k):
            return error(sql_error("duplicate primary key: {value_string(row[pk])}"))
        seen.add(k, true)
    return ok(unit)

# ---------------------------------------------------------------- name resolution

fn qualified(t: String, n: String) String:
    if t == "":
        return n.clone()
    return "{t}.{n}"

fn lookup(scope: List[ScopeCol], t: String, n: String) Result[Int, SqlErr]:
    var found = -1
    var count = 0
    for sc in scope:
        if sc.name == n and (t == "" or sc.alias == t):
            found = sc.idx
            count += 1
    if count == 0:
        return error(sql_error("no such column: {qualified(t, n)}"))
    if count > 1:
        return error(sql_error("ambiguous column: {n}"))
    return ok(found)

fn is_aggregate(name: String) Bool:
    return name == "COUNT" or name == "SUM" or name == "MIN" or name == "MAX"

# -1 unknown function, -2 any number of arguments (at least one), otherwise the exact count.
fn scalar_arity(name: String) Int:
    if name == "UPPER" or name == "LOWER" or name == "LENGTH" or name == "ABS":
        return 1
    if name == "SUBSTR":
        return 3
    if name == "COALESCE":
        return -2
    return -1

fn wrong_args(name: String) SqlErr:
    return sql_error("wrong number of arguments to {name}")

# mode 0: row context, no aggregates. mode 1: grouped context, aggregates allowed and
# bare columns must be GROUP BY columns. mode 2: inside an aggregate argument.
fn resolve(e: Expr, scope: List[ScopeCol], mode: Int, group: List[Int]) Result[Expr, SqlErr]:
    match e:
        Lit(v):
            return ok(Lit(v: v.clone()))
        Col(t, n, idx):
            var at = idx
            if idx < 0:
                at = try lookup(scope, t, n)
            if mode == 1 and not group.contains(at):
                return error(sql_error("column {qualified(t, n)} must appear in GROUP BY"))
            return ok(Col(table: t.clone(), name: n.clone(), idx: at))
        Neg(x):
            let a = try resolve(x, scope, mode, group)
            return ok(Neg(e: a))
        Not(x):
            let a = try resolve(x, scope, mode, group)
            return ok(Not(e: a))
        Bin(op, l, r):
            let a = try resolve(l, scope, mode, group)
            let b = try resolve(r, scope, mode, group)
            return ok(Bin(op: op.clone(), l: a, r: b))
        IsNull(x, neg):
            let a = try resolve(x, scope, mode, group)
            return ok(IsNull(e: a, neg: neg))
        Like(x, p, neg):
            let a = try resolve(x, scope, mode, group)
            let b = try resolve(p, scope, mode, group)
            return ok(Like(e: a, pat: b, neg: neg))
        InList(x, items, neg):
            let a = try resolve(x, scope, mode, group)
            var rs = List[Expr]()
            for it in items:
                let b = try resolve(it, scope, mode, group)
                rs.append(b)
            return ok(InList(e: a, items: rs, neg: neg))
        Between(x, lo, hi, neg):
            let a = try resolve(x, scope, mode, group)
            let b = try resolve(lo, scope, mode, group)
            let c = try resolve(hi, scope, mode, group)
            return ok(Between(e: a, lo: b, hi: c, neg: neg))
        Call(name, args, distinct, star):
            return resolve_call(name, args, distinct, star, scope, mode, group)

fn resolve_call(name: String, args: List[Expr], distinct: Bool, star: Bool, scope: List[ScopeCol], mode: Int, group: List[Int]) Result[Expr, SqlErr]:
    if is_aggregate(name):
        if mode != 1:
            return error(sql_error("misuse of aggregate"))
        if star:
            if name != "COUNT" or distinct:
                return error(wrong_args(name))
            return ok(Call(name: name, args: List[Expr](), distinct: false, star: true))
        if args.length() != 1:
            return error(wrong_args(name))
        let a = try resolve(args[0].clone(), scope, 2, group)
        var single = List[Expr]()
        single.append(a)
        return ok(Call(name: name, args: single, distinct: distinct, star: false))
    let arity = scalar_arity(name)
    if arity == -1:
        return error(sql_error("no such function: {name}"))
    if star or (distinct and args.length() != 1):
        return error(wrong_args(name))
    if arity == -2:
        if args.length() < 1:
            return error(wrong_args(name))
    else if args.length() != arity:
        return error(wrong_args(name))
    var rs = List[Expr]()
    for a in args:
        let r = try resolve(a, scope, mode, group)
        rs.append(r)
    return ok(Call(name: name, args: rs, distinct: distinct, star: false))

fn has_agg(e: Expr) Bool:
    match e:
        Neg(x):
            return has_agg(x)
        Not(x):
            return has_agg(x)
        Bin(_, l, r):
            return has_agg(l) or has_agg(r)
        IsNull(x, _):
            return has_agg(x)
        Like(x, p, _):
            return has_agg(x) or has_agg(p)
        InList(x, items, _):
            if has_agg(x):
                return true
            for it in items:
                if has_agg(it):
                    return true
            return false
        Between(x, lo, hi, _):
            return has_agg(x) or has_agg(lo) or has_agg(hi)
        Call(name, args, _, _):
            if is_aggregate(name):
                return true
            for a in args:
                if has_agg(a):
                    return true
            return false
        _:
            return false

fn col_idx(e: Expr) Int:
    match e:
        Col(_, _, i):
            return i
        _:
            return -1

fn literal_int(e: Expr) Optional[Int]:
    match e:
        Lit(v):
            return as_int(v)
        _:
            return none

fn name_position(e: Expr, names: List[String]) Optional[Int]:
    match e:
        Col(t, n, _):
            if t == "":
                return names.index_of(n)
            return none
        _:
            return none

fn default_name(e: Expr) String:
    match e:
        Col(_, n, _):
            return n.clone()
        _:
            return "?column?"

# ---------------------------------------------------------------- evaluation

fn no_group() List[List[Value]]:
    return List[List[Value]]()

fn no_row() List[Value]:
    return List[Value]()

fn eval(e: Expr, row: List[Value], group: List[List[Value]]) Result[Value, SqlErr]:
    match e:
        Lit(v):
            return ok(v.clone())
        Col(_, _, idx):
            return ok(row[idx].clone())
        Neg(x):
            let v = try eval(x, row, group)
            if is_null(v):
                return ok(VNull)
            if let i = as_int(v):
                return ok(VInt(0 - i))
            return error(type_error())
        Not(x):
            let v = try eval(x, row, group)
            let t = try tri_of(v)
            return ok(tri_value(not3(t)))
        Bin(op, l, r):
            return eval_bin(op, l, r, row, group)
        IsNull(x, neg):
            let v = try eval(x, row, group)
            return ok(VBool(is_null(v) != neg))
        Like(x, p, neg):
            let a = try eval(x, row, group)
            let b = try eval(p, row, group)
            if is_null(a) or is_null(b):
                return ok(VNull)
            if let s = as_text(a):
                if let pat = as_text(b):
                    return ok(VBool(like_match(s, pat) != neg))
            return error(type_error())
        InList(x, items, neg):
            let v = try eval(x, row, group)
            var found = false
            var saw_null = false
            for it in items:
                let w = try eval(it, row, group)
                if is_null(v):
                    continue
                if is_null(w):
                    saw_null = true
                else:
                    let c = try typed_cmp(v, w)
                    if c == 0:
                        found = true
            var res = -1
            if is_null(v):
                res = -1
            else if found:
                res = 1
            else if saw_null:
                res = -1
            else:
                res = 0
            if neg:
                res = not3(res)
            return ok(tri_value(res))
        Between(x, lo, hi, neg):
            let v = try eval(x, row, group)
            let a = try eval(lo, row, group)
            let b = try eval(hi, row, group)
            let c1 = try compare_values(">=", v, a)
            var res = tri_raw(c1)
            if res != 0:
                let c2 = try compare_values("<=", v, b)
                res = and3(res, tri_raw(c2))
            if neg:
                res = not3(res)
            return ok(tri_value(res))
        Call(name, args, _, _):
            if is_aggregate(name):
                return eval_aggregate(name, args, e, group)
            return eval_scalar(name, args, row, group)

fn tri_raw(v: Value) Int:
    match v:
        VBool(b):
            if b:
                return 1
            return 0
        _:
            return -1

fn eval_bin(op: String, l: Expr, r: Expr, row: List[Value], group: List[List[Value]]) Result[Value, SqlErr]:
    if op == "AND":
        let lt = try tri_of(try eval(l, row, group))
        if lt == 0:
            return ok(VBool(false))
        let rt = try tri_of(try eval(r, row, group))
        return ok(tri_value(and3(lt, rt)))
    if op == "OR":
        let lt = try tri_of(try eval(l, row, group))
        if lt == 1:
            return ok(VBool(true))
        let rt = try tri_of(try eval(r, row, group))
        return ok(tri_value(or3(lt, rt)))
    let a = try eval(l, row, group)
    let b = try eval(r, row, group)
    if op == "||":
        if is_null(a) or is_null(b):
            return ok(VNull)
        if let x = as_text(a):
            if let y = as_text(b):
                return ok(VText(x.concat(y)))
        return error(type_error())
    if op == "+" or op == "-" or op == "*" or op == "/" or op == "%":
        return arith(op, a, b)
    return compare_values(op, a, b)

fn arith(op: String, a: Value, b: Value) Result[Value, SqlErr]:
    if is_null(a) or is_null(b):
        return ok(VNull)
    if let x = as_int(a):
        if let y = as_int(b):
            if op == "+":
                return ok(VInt(x + y))
            if op == "-":
                return ok(VInt(x - y))
            if op == "*":
                return ok(VInt(x * y))
            if y == 0:
                return error(sql_error("division by zero"))
            if op == "/":
                return ok(VInt(x / y))
            return ok(VInt(x % y))
    return error(type_error())

fn compare_values(op: String, a: Value, b: Value) Result[Value, SqlErr]:
    if is_null(a) or is_null(b):
        return ok(VNull)
    let c = try typed_cmp(a, b)
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

fn eval_scalar(name: String, args: List[Expr], row: List[Value], group: List[List[Value]]) Result[Value, SqlErr]:
    var vals = List[Value]()
    for a in args:
        let v = try eval(a, row, group)
        vals.append(v)
    if name == "COALESCE":
        for v in vals:
            if not is_null(v):
                return ok(v.clone())
        return ok(VNull)
    for v in vals:
        if is_null(v):
            return ok(VNull)
    if name == "UPPER" or name == "LOWER":
        if let t = as_text(vals[0]):
            return ok(VText(ascii_case(t, name == "UPPER")))
        return error(type_error())
    if name == "LENGTH":
        if let t = as_text(vals[0]):
            return ok(VInt(t.length()))
        return error(type_error())
    if name == "ABS":
        if let i = as_int(vals[0]):
            return ok(VInt(i.abs()))
        return error(type_error())
    # SUBSTR(text, start, len)
    if let t = as_text(vals[0]):
        if let start = as_int(vals[1]):
            if let len = as_int(vals[2]):
                return ok(VText(substr(t, start, len)))
    return error(type_error())

fn eval_aggregate(name: String, args: List[Expr], e: Expr, group: List[List[Value]]) Result[Value, SqlErr]:
    match e:
        Call(_, _, distinct, star):
            if star:
                return ok(VInt(group.length()))
            var vals = List[Value]()
            var seen = Map[String, Bool]()
            for r in group:
                let v = try eval(args[0], r, no_group())
                if is_null(v):
                    continue
                if distinct:
                    let k = value_key(v)
                    if seen.contains(k):
                        continue
                    seen.add(k, true)
                vals.append(v)
            if name == "COUNT":
                return ok(VInt(vals.length()))
            if vals.length() == 0:
                return ok(VNull)
            if name == "SUM":
                var total = 0
                for v in vals:
                    if let i = as_int(v):
                        total += i
                    else:
                        return error(type_error())
                return ok(VInt(total))
            var best = vals[0].clone()
            for v in vals:
                if not is_int_value(v) and not is_text_value(v):
                    return error(type_error())
                let c = try typed_cmp(v, best)
                if name == "MIN" and c < 0:
                    best = v.clone()
                if name == "MAX" and c > 0:
                    best = v.clone()
            return ok(best)
        _:
            return error(type_error())

# ---------------------------------------------------------------- SELECT execution

type OutItem:
    e: Expr
    name: String

type OrderKey:
    pos: Int
    e: Expr
    desc: Bool

type OutRow:
    out: List[Value]
    keys: List[Value]
    descs: List[Bool]

fn project(exprs: List[Expr], row: List[Value], group: List[List[Value]]) Result[List[Value], SqlErr]:
    var vals = List[Value]()
    for e in exprs:
        let v = try eval(e, row, group)
        vals.append(v)
    return ok(vals)

fn order_values(keys: List[OrderKey], out: List[Value], row: List[Value], group: List[List[Value]]) Result[List[Value], SqlErr]:
    var vals = List[Value]()
    for k in keys:
        if k.pos >= 0:
            vals.append(out[k.pos].clone())
        else:
            let v = try eval(k.e, row, group)
            vals.append(v)
    return ok(vals)

fn order_descs(keys: List[OrderKey]) List[Bool]:
    var out = List[Bool]()
    for k in keys:
        out.append(k.desc)
    return out

fn compare_rows(a: OutRow, b: OutRow) Int:
    for k in 0..a.keys.length():
        var c = order_cmp(a.keys[k], b.keys[k])
        if a.descs[k]:
            c = 0 - c
        if c != 0:
            return c
    return 0

# True when the optional condition is absent or evaluates to TRUE.
fn passes(cond: Optional[Expr], row: List[Value]) Result[Bool, SqlErr]:
    if let c = cond:
        let v = try eval(c, row, no_group())
        let t = try tri_of(v)
        return ok(t == 1)
    return ok(true)

# Source rows of FROM and JOINs, in the order described by the spec.
fn build_rows(tables: List[Table], tids: List[Int], joins: List[Join], ons: List[Expr]) Result[List[List[Value]], SqlErr]:
    var rows = List[List[Value]]()
    if tids.length() == 0:
        rows.append(no_row())
        return ok(rows)
    for r in tables[tids[0]].rows:
        rows.append(r.clone())
    for k in 0..joins.length():
        let t = tables[tids[k + 1]]
        var next = List[List[Value]]()
        for o in rows:
            var matched = false
            for inner in t.rows:
                let combined = o.concat(inner)
                let c = try eval(ons[k], combined, no_group())
                let ct = try tri_of(c)
                if ct == 1:
                    matched = true
                    next.append(combined)
            if not matched and joins[k].is_left:
                var padded = o.clone()
                for w in 0..t.cols.length():
                    padded.append(VNull)
                next.append(padded)
        rows = next
    return ok(rows)

fn exec_select(tables: List[Table], sel: Select) Result[Bytes, SqlErr]:
    # Tables of FROM and JOINs: existence and aliases, left to right.
    var all = List[TableRef]()
    if let base = sel.from_ref:
        all.append(base.clone())
    for j in sel.joins:
        all.append(j.table.clone())
    var tids = List[Int]()
    var aliases = List[String]()
    for tr in all:
        let ti = try table_index(tables, tr.name)
        if aliases.contains(tr.alias):
            return error(sql_error("duplicate alias: {tr.alias}"))
        aliases.append(tr.alias.clone())
        tids.append(ti)

    # JOIN conditions, each against the tables joined so far.
    var scope = List[ScopeCol]()
    var ons = List[Expr]()
    var offset = 0
    for k in 0..tids.length():
        let t = tables[tids[k]]
        for sc in table_scope(t, all[k].alias, offset):
            scope.append(sc.clone())
        offset += t.cols.length()
        if k > 0:
            let on = try resolve(sel.joins[k - 1].on.clone(), scope, 0, List[Int]())
            ons.append(on)

    # Stars, expanded in FROM order.
    var items = List[OutItem]()
    for it in sel.items:
        match it:
            StarItem:
                for sc in scope:
                    items.append(OutItem(e: Col(table: "", name: sc.name.clone(), idx: sc.idx), name: sc.name.clone()))
            TStarItem(t):
                var found = false
                for sc in scope:
                    if sc.alias == t:
                        found = true
                        items.append(OutItem(e: Col(table: "", name: sc.name.clone(), idx: sc.idx), name: sc.name.clone()))
                if not found:
                    return error(sql_error("no such table: {t}"))
            ExprItem(e, alias):
                var nm = default_name(e)
                if alias != "":
                    nm = alias.clone()
                items.append(OutItem(e: e.clone(), name: nm))

    # GROUP BY columns.
    var group_idx = List[Int]()
    for g in sel.group_by:
        let r = try resolve(g.clone(), scope, 0, List[Int]())
        group_idx.append(col_idx(r))

    # WHERE.
    var where_r: Optional[Expr] = none
    if let w = sel.where_expr:
        let r = try resolve(w.clone(), scope, 0, List[Int]())
        where_r = some(r)

    var aggregated = sel.group_by.length() > 0 or not sel.having_expr.is_none()
    for it in items:
        if has_agg(it.e):
            aggregated = true
    for o in sel.order_by:
        if has_agg(o.e):
            aggregated = true
    var mode = 0
    if aggregated:
        mode = 1

    # Select list.
    var rexprs = List[Expr]()
    var onames = List[String]()
    for it in items:
        let r = try resolve(it.e.clone(), scope, mode, group_idx)
        rexprs.append(r)
        onames.append(it.name.clone())

    # HAVING.
    var having_r: Optional[Expr] = none
    if let h = sel.having_expr:
        let r = try resolve(h.clone(), scope, 1, group_idx)
        having_r = some(r)

    # ORDER BY.
    var okeys = List[OrderKey]()
    for o in sel.order_by:
        if let n = literal_int(o.e):
            if n < 1 or n > onames.length():
                return error(sql_error("bad ORDER BY position"))
            okeys.append(OrderKey(pos: n - 1, e: Lit(v: VNull), desc: o.desc))
        else if let p = name_position(o.e, onames):
            okeys.append(OrderKey(pos: p, e: Lit(v: VNull), desc: o.desc))
        else:
            let r = try resolve(o.e.clone(), scope, mode, group_idx)
            okeys.append(OrderKey(pos: -1, e: r, desc: o.desc))
    let descs = order_descs(okeys)

    # Rows and filtering.
    let source = try build_rows(tables, tids, sel.joins, ons)
    var kept = List[List[Value]]()
    for row in source:
        let keep = try passes(where_r, row)
        if keep:
            kept.append(row.clone())

    var units = List[OutRow]()
    if not aggregated:
        for row in kept:
            let out = try project(rexprs, row, no_group())
            let keys = try order_values(okeys, out, row, no_group())
            units.append(OutRow(out: out, keys: keys, descs: descs.clone()))
    else:
        var groups = List[List[List[Value]]]()
        if group_idx.length() == 0:
            groups.append(kept.clone())
        else:
            var index = Map[String, Int]()
            for row in kept:
                let key = group_key(row, group_idx)
                if let gi = index.get(key):
                    groups[gi].append(row.clone())
                else:
                    index.add(key, groups.length())
                    var g = List[List[Value]]()
                    g.append(row.clone())
                    groups.append(g)
        for g in groups:
            var rep = no_row()
            if g.length() > 0:
                rep = g[0].clone()
            if let hv = having_r:
                let hval = try eval(hv, rep, g)
                let ht = try tri_of(hval)
                if ht != 1:
                    continue
            let out = try project(rexprs, rep, g)
            let keys = try order_values(okeys, out, rep, g)
            units.append(OutRow(out: out, keys: keys, descs: descs.clone()))

    if sel.distinct_rows:
        var seen = Map[String, Bool]()
        var uniq = List[OutRow]()
        for u in units:
            let k = row_key(u.out)
            if not seen.contains(k):
                seen.add(k, true)
                uniq.append(u.clone())
        units = uniq

    if okeys.length() > 0:
        units.sort(fn(a: OutRow, b: OutRow) Int: compare_rows(a, b))

    # OFFSET and LIMIT.
    let total = units.length()
    let offset_start = sel.offset
    var first = offset_start
    if first > total:
        first = total
    var last = total
    if sel.limit >= 0 and first + sel.limit < total:
        last = first + sel.limit

    var sb = BytesBuilder()
    for c in 0..onames.length():
        if c > 0:
            sb.append_bytes("|".to_bytes())
        sb.append_bytes(onames[c].to_bytes())
    sb.append_bytes("\n".to_bytes())
    var i = first
    while i < last:
        let u = units[i].clone()
        for c in 0..u.out.length():
            if c > 0:
                sb.append_bytes("|".to_bytes())
            sb.append_bytes(value_text(u.out[c]))
        sb.append_bytes("\n".to_bytes())
        i += 1
    sb.append_bytes("({last - first} rows)\n".to_bytes())
    return ok(sb.build())

# ---------------------------------------------------------------- other statements

fn exec_create(var tables: List[Table], name: String, cols: List[ColDef]) Result[Bytes, SqlErr]:
    if not find_table(tables, name).is_none():
        return error(sql_error("table {name} already exists"))
    var primaries = 0
    for c in 0..cols.length():
        for p in 0..c:
            if cols[p].name == cols[c].name:
                return error(sql_error("duplicate column: {cols[c].name}"))
        if cols[c].primary:
            primaries += 1
    if primaries > 1:
        return error(sql_error("multiple primary keys"))
    var stored = List[ColDef]()
    for c in cols:
        stored.append(ColDef(name: c.name.clone(), is_int: c.is_int, primary: c.primary, not_null: c.not_null or c.primary))
    tables.append(Table(name: name.clone(), cols: stored, rows: List[List[Value]]()))
    return ok("ok\n".to_bytes())

fn exec_drop(var tables: List[Table], name: String) Result[Bytes, SqlErr]:
    let ti = try table_index(tables, name)
    tables.remove(ti)
    return ok("ok\n".to_bytes())

fn exec_insert(var tables: List[Table], name: String, cols: List[String], rows: List[List[Expr]]) Result[Bytes, SqlErr]:
    let ti = try table_index(tables, name)
    let t = tables[ti].clone()
    let ncols = t.cols.length()
    var targets = List[Int]()
    if cols.length() == 0:
        for c in 0..ncols:
            targets.append(c)
    else:
        for cn in cols:
            if let k = column_index(t, cn):
                if targets.contains(k):
                    return error(sql_error("duplicate column: {cn}"))
                targets.append(k)
            else:
                return error(sql_error("no such column: {cn}"))
    var added = List[List[Value]]()
    for vals in rows:
        if vals.length() != targets.length():
            return error(sql_error("wrong number of values"))
        var full = List[Value]()
        for c in 0..ncols:
            full.append(VNull)
        for k in 0..vals.length():
            let r = try resolve(vals[k].clone(), List[ScopeCol](), 0, List[Int]())
            let v = try eval(r, no_row(), no_group())
            full[targets[k]] = v
        try check_row(t, full)
        added.append(full)
    var combined = t.rows.clone()
    for r in added:
        combined.append(r.clone())
    try check_pk(t, combined)
    tables[ti].rows = combined
    return ok("inserted {added.length()}\n".to_bytes())

fn exec_update(var tables: List[Table], name: String, names: List[String], vals: List[Expr], where_expr: Optional[Expr]) Result[Bytes, SqlErr]:
    let ti = try table_index(tables, name)
    let t = tables[ti].clone()
    let scope = table_scope(t, name, 0)
    var setidx = List[Int]()
    for cn in names:
        if let k = column_index(t, cn):
            setidx.append(k)
        else:
            return error(sql_error("no such column: {cn}"))
    var setexprs = List[Expr]()
    for e in vals:
        let r = try resolve(e, scope, 0, List[Int]())
        setexprs.append(r)
    var where_r: Optional[Expr] = none
    if let w = where_expr:
        let r = try resolve(w, scope, 0, List[Int]())
        where_r = some(r)
    var updated = 0
    var newrows = List[List[Value]]()
    for row in t.rows:
        let hit = try passes(where_r, row)
        if hit:
            updated += 1
            var newvals = List[Value]()
            for se in setexprs:
                let v = try eval(se, row, no_group())
                newvals.append(v)
            var nr = row.clone()
            for k in 0..setidx.length():
                nr[setidx[k]] = newvals[k].clone()
            try check_row(t, nr)
            newrows.append(nr)
        else:
            newrows.append(row.clone())
    try check_pk(t, newrows)
    tables[ti].rows = newrows
    return ok("updated {updated}\n".to_bytes())

fn exec_delete(var tables: List[Table], name: String, where_expr: Optional[Expr]) Result[Bytes, SqlErr]:
    let ti = try table_index(tables, name)
    let t = tables[ti].clone()
    let scope = table_scope(t, name, 0)
    var where_r: Optional[Expr] = none
    if let w = where_expr:
        let r = try resolve(w, scope, 0, List[Int]())
        where_r = some(r)
    var deleted = 0
    var kept = List[List[Value]]()
    for row in t.rows:
        let hit = try passes(where_r, row)
        if hit:
            deleted += 1
        else:
            kept.append(row.clone())
    tables[ti].rows = kept
    return ok("deleted {deleted}\n".to_bytes())

fn run_statement(var tables: List[Table], text: Bytes) Result[Bytes, SqlErr]:
    let toks = try lex(text)
    if toks.length() == 1:
        return ok(empty_bytes())
    let stmt = try parse_statement_text(text)
    match stmt:
        CreateStmt(name, cols):
            return exec_create(var tables, name.clone(), cols.clone())
        DropStmt(name):
            return exec_drop(var tables, name.clone())
        InsertStmt(name, cols, rows):
            return exec_insert(var tables, name.clone(), cols.clone(), rows.clone())
        UpdateStmt(name, names, vals, where_expr):
            return exec_update(var tables, name.clone(), names.clone(), vals.clone(), where_expr.clone())
        DeleteStmt(name, where_expr):
            return exec_delete(var tables, name.clone(), where_expr.clone())
        SelectStmt(sel):
            return exec_select(tables, sel.clone())

export fn main() Int:
    let data = read_all(stdin()).get()
    var tables = List[Table]()
    var out = BytesBuilder()
    for seg in split_statements(data):
        let r = run_statement(var tables, seg)
        if r.is_error():
            let e = r.err()
            out.append_bytes("error: {e.msg}\n".to_bytes())
        else:
            out.append_bytes(r.get())
    stdout().write_bytes(out.build()).get()
    return 0

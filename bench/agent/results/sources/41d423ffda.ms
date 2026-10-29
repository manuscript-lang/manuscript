# In-memory SQL engine. Reads a script on stdin, runs each statement in order against one
# database, and prints each statement's result, or `error: MESSAGE`, on stdout.

import {stdin, stdout} from "@std/io.ms"
import {read_lines} from "@std/streams.ms"
import {from_scalars} from "@std/string.ms"

# ---------------------------------------------------------------- constants

let MAX_INT = 9223372036854775807
let T_IDENT = 0
let T_KEYWORD = 1
let T_INT = 2
let T_STRING = 3
let T_SYMBOL = 4
let T_ERROR = 5
let T_EOF = 6
let V_NULL = 0
let V_INT = 1
let V_TEXT = 2
let V_BOOL = 3
let E_INT = 1
let E_TEXT = 2
let E_NULL = 3
let E_COL = 4
let E_CALL = 5
let E_NEG = 6
let E_NOT = 7
let E_BIN = 8
let E_AND = 9
let E_OR = 10
let E_ISNULL = 11
let E_LIKE = 12
let E_IN = 13
let E_BETWEEN = 14
let I_STAR = 0
let I_TABLE = 1
let I_EXPR = 2
let KEYWORDS = [
    "SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET",
    "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN",
    "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE",
    "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"
]
let TWO_SYMBOLS = ["<>", "<=", ">=", "||"]
let COMPARE_OPS = ["=", "<>", "<", "<=", ">", ">="]
let AGGREGATES = ["COUNT", "SUM", "MIN", "MAX"]

# ---------------------------------------------------------------- errors and values

type SqlError:
    msg: String = ""

impl Error for SqlError:
    fn message() String:
        return self.msg.clone()

type Value:
    kind: Int = 0
    num: Int = 0
    text: String = ""
    flag: Bool = false

fn null_value() Value:
    return Value(kind: V_NULL)

fn int_value(n: Int) Value:
    return Value(kind: V_INT, num: n)

fn text_value(s: String) Value:
    return Value(kind: V_TEXT, text: s)

fn bool_value(b: Bool) Value:
    return Value(kind: V_BOOL, flag: b)

fn null_row(width: Int) List[Value]:
    var row: List[Value] = []
    for k in 0..width:
        row.append(null_value())
    return row

# Text form of a value, as printed in SELECT output.
fn show(v: Value) String:
    if v.kind == V_NULL:
        return "NULL"
    if v.kind == V_INT:
        return "{v.num}"

    if v.kind == V_BOOL:
        if v.flag:
            return "true"

        return "false"

    return v.text.clone()

# Equality used by DISTINCT, GROUP BY and primary keys: NULL equals NULL.
fn same_value(a: Value, b: Value) Bool:
    if a.kind != b.kind:
        return false
    if a.kind == V_INT:
        return a.num == b.num
    if a.kind == V_TEXT:
        return a.text == b.text
    if a.kind == V_BOOL:
        return a.flag == b.flag

    return true

fn same_row(a: List[Value], b: List[Value]) Bool:
    if a.length() != b.length():
        return false

    for k in 0..a.length():
        if not same_value(a[k], b[k]):
            return false
    return true

fn order_rank(v: Value) Int:
    if v.kind == V_NULL:
        return 0
    if v.kind == V_BOOL:
        return 1
    if v.kind == V_INT:
        return 2

    return 3

# Total order for ORDER BY: NULL < BOOL < INT < TEXT.
fn order_cmp(a: Value, b: Value) Int:
    let ra = order_rank(a)
    let rb = order_rank(b)
    if ra < rb:
        return -1
    if ra > rb:
        return 1

    if a.kind == V_INT:
        if a.num < b.num:
            return -1
        if a.num > b.num:
            return 1

        return 0

    if a.kind == V_TEXT:
        return a.text.compare(b.text)

    if a.kind == V_BOOL:
        if a.flag == b.flag:
            return 0
        if not a.flag:
            return -1

        return 1

    return 0

fn compare_keys(a: List[Value], b: List[Value], descs: List[Bool]) Int:
    for k in 0..descs.length():
        var c = order_cmp(a[k], b[k])
        if descs[k]:
            c = 0 - c
        if c != 0:
            return c

    return 0

# ---------------------------------------------------------------- lexer

fn is_alpha(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_digit(c: Int) Bool:
    return c >= 48 and c <= 57

fn is_alnum(c: Int) Bool:
    return is_alpha(c) or is_digit(c)

fn is_single_symbol(c: Int) Bool:
    return [61, 60, 62, 43, 45, 42, 47, 37, 40, 41, 44, 46, 59].contains(c)

type Token:
    kind: Int = 0
    text: String = ""
    num: Int = 0

# Splits the whole script into tokens. `;` becomes a symbol token. Bad characters, bad literals
# and unterminated strings become error tokens, which make only their own statement a syntax error.
fn lex(text: String) List[Token]:
    let data = text.to_bytes()
    let n = data.length()
    var toks: List[Token] = []
    var i = 0

    while i < n:
        let c = data.get(i).to_int()

        let nxt = if i + 1 < n: data.get(i + 1).to_int() else: 0

        if c == 32 or c == 9 or c == 13 or c == 10:
            i += 1
        else if c == 45 and nxt == 45:
            while i < n and data.get(i).to_int() != 10:
                i += 1
        else if is_alpha(c):
            var j = i + 1
            while j < n and is_alnum(data.get(j).to_int()):
                j += 1

            let word = data.decode_utf8_range(i, j).get("")
            let up = word.upper()

            if KEYWORDS.contains(up):
                toks.append(Token(kind: T_KEYWORD, text: up))
            else:
                toks.append(Token(kind: T_IDENT, text: word))

            i = j
        else if is_digit(c):
            var j = i
            var v = 0
            var overflow = false

            while j < n and is_digit(data.get(j).to_int()):
                let d = data.get(j).to_int() - 48

                if v > (MAX_INT - d) / 10:
                    overflow = true
                else:
                    v = v * 10 + d

                j += 1

            if overflow:
                toks.append(Token(kind: T_ERROR))
            else:
                toks.append(Token(kind: T_INT, num: v))

            i = j
        else if c == 39:
            var s = ""
            var seg = i + 1
            var j = i + 1
            var closed = false

            while j < n and not closed:
                if data.get(j).to_int() == 39:
                    s = s + data.decode_utf8_range(seg, j).get("")

                    if j + 1 < n and data.get(j + 1).to_int() == 39:
                        s = s + "'"
                        j += 2
                        seg = j
                    else:
                        closed = true
                        j += 1
                else:
                    j += 1

            if closed:
                toks.append(Token(kind: T_STRING, text: s))
            else:
                toks.append(Token(kind: T_ERROR))

            i = j
        else if (
            i + 1 < n
            and TWO_SYMBOLS.contains(
                data.decode_utf8_range(i, i + 2).get("")
            )
        ):
            toks.append(
                Token(
                    kind: T_SYMBOL, text: data.decode_utf8_range(i, i + 2).get("")
                )
            )
            i += 2
        else if c == 33 and nxt == 61:
            toks.append(Token(kind: T_SYMBOL, text: "<>"))
            i += 2
        else if is_single_symbol(c):
            toks.append(
                Token(
                    kind: T_SYMBOL, text: data.decode_utf8_range(i, i + 1).get("")
                )
            )
            i += 1
        else:
            toks.append(Token(kind: T_ERROR))
            i += 1

    return toks

# Splits tokens at `;`. Each statement gets a trailing EOF token; statements with no tokens are dropped.
fn split_statements(toks: List[Token]) List[List[Token]]:
    var stmts: List[List[Token]] = []
    var cur: List[Token] = []

    for t in toks:
        if t.kind == T_SYMBOL and t.text == ";":
            if cur.length() > 0:
                cur.append(Token(kind: T_EOF))
                stmts.append(cur)
                cur = []
        else:
            cur.append(t.clone())

    if cur.length() > 0:
        cur.append(Token(kind: T_EOF))
        stmts.append(cur)

    return stmts

# ---------------------------------------------------------------- AST

type Expr:
    kind: Int = 0
    op: String = ""
    table: String = ""
    num: Int = 0
    text: String = ""
    negated: Bool = false
    distinct: Bool = false
    star: Bool = false
    args: List[Expr] = []

type TableRef:
    name: String = ""
    alias: String = ""

type Join:
    tref: TableRef = TableRef()
    on: Expr = Expr()
    left: Bool = false

type Item:
    kind: Int = 0
    table: String = ""
    alias: String = ""
    has_alias: Bool = false
    expr: Expr = Expr()

type OrderItem:
    expr: Expr = Expr()
    desc: Bool = false

type Select:
    distinct: Bool = false
    items: List[Item] = []
    has_from: Bool = false
    from_ref: TableRef = TableRef()
    joins: List[Join] = []
    has_where: Bool = false
    where_expr: Expr = Expr()
    group: List[Expr] = []
    has_having: Bool = false
    having_expr: Expr = Expr()
    order: List[OrderItem] = []
    has_limit: Bool = false
    limit: Int = 0
    offset: Int = 0

type ColDef:
    name: String = ""
    kind: Int = 0
    notnull: Bool = false
    primary: Bool = false

type CreateStmt:
    name: String = ""
    cols: List[ColDef] = []

type InsertStmt:
    name: String = ""
    names: List[String] = []
    rows: List[List[Expr]] = []

type UpdateStmt:
    name: String = ""
    names: List[String] = []
    exprs: List[Expr] = []
    has_where: Bool = false
    where_expr: Expr = Expr()

type DeleteStmt:
    name: String = ""
    has_where: Bool = false
    where_expr: Expr = Expr()

# ---------------------------------------------------------------- parser

type Parser:
    toks: List[Token] = []
    pos: Int = 0

fn at_kw(p: Parser, word: String) Bool:
    let t = p.toks[p.pos]
    return t.kind == T_KEYWORD and t.text == word

fn at_sym(p: Parser, sym: String) Bool:
    let t = p.toks[p.pos]
    return t.kind == T_SYMBOL and t.text == sym

# NOT followed by LIKE, IN or BETWEEN.
fn at_negated_predicate(p: Parser) Bool:
    if not at_kw(p, "NOT"):
        return false

    let nt = p.toks[p.pos + 1]
    return (
        nt.kind == T_KEYWORD
        and (nt.text == "LIKE" or nt.text == "IN" or nt.text == "BETWEEN")
    )

fn eat_kw(var p: Parser, word: String) Bool:
    if at_kw(p, word):
        p.pos += 1
        return true

    return false

fn eat_sym(var p: Parser, sym: String) Bool:
    if at_sym(p, sym):
        p.pos += 1
        return true

    return false

fn expect_kw(var p: Parser, word: String) Result[Unit, SqlError]:
    if eat_kw(var p, word):
        return ok(unit)

    return error(SqlError(msg: "syntax error"))

fn expect_sym(var p: Parser, sym: String) Result[Unit, SqlError]:
    if eat_sym(var p, sym):
        return ok(unit)

    return error(SqlError(msg: "syntax error"))

fn expect_ident(var p: Parser) Result[String, SqlError]:
    let t = p.toks[p.pos]
    if t.kind != T_IDENT:
        return error(SqlError(msg: "syntax error"))

    let text = t.text.clone()
    p.pos += 1
    return ok(text)

fn expect_int(var p: Parser) Result[Int, SqlError]:
    let t = p.toks[p.pos]
    if t.kind != T_INT:
        return error(SqlError(msg: "syntax error"))

    let v = t.num
    p.pos += 1
    return ok(v)

fn parse_expr(var p: Parser) Result[Expr, SqlError]:
    return parse_or(var p)

fn parse_or(var p: Parser) Result[Expr, SqlError]:
    var left = try parse_and(var p)

    while eat_kw(var p, "OR"):
        let right = try parse_and(var p)
        left = Expr(kind: E_OR, args: [left, right])

    return ok(left)

fn parse_and(var p: Parser) Result[Expr, SqlError]:
    var left = try parse_not(var p)

    while eat_kw(var p, "AND"):
        let right = try parse_not(var p)
        left = Expr(kind: E_AND, args: [left, right])

    return ok(left)

fn parse_not(var p: Parser) Result[Expr, SqlError]:
    if eat_kw(var p, "NOT"):
        let inner = try parse_not(var p)
        return ok(Expr(kind: E_NOT, args: [inner]))

    return parse_cmp(var p)

# At most one comparison per cmp: a second one is left unparsed and fails at the statement end.
fn parse_cmp(var p: Parser) Result[Expr, SqlError]:
    let left = try parse_add(var p)
    let t = p.toks[p.pos].clone()

    if t.kind == T_SYMBOL and COMPARE_OPS.contains(t.text):
        p.pos += 1

        let right = try parse_add(var p)
        return ok(Expr(kind: E_BIN, op: t.text.clone(), args: [left, right]))

    if eat_kw(var p, "IS"):
        let neg = eat_kw(var p, "NOT")
        try expect_kw(var p, "NULL")
        return ok(Expr(kind: E_ISNULL, negated: neg, args: [left]))

    var neg = false

    if at_negated_predicate(p):
        p.pos += 1
        neg = true

    if eat_kw(var p, "LIKE"):
        let pattern = try parse_add(var p)
        return ok(Expr(kind: E_LIKE, negated: neg, args: [left, pattern]))

    if eat_kw(var p, "IN"):
        try expect_sym(var p, "(")

        var args: List[Expr] = [left]
        args.append(try parse_expr(var p))
        while eat_sym(var p, ","):
            args.append(try parse_expr(var p))
        try expect_sym(var p, ")")
        return ok(Expr(kind: E_IN, negated: neg, args: args))

    if eat_kw(var p, "BETWEEN"):
        let lo = try parse_add(var p)
        try expect_kw(var p, "AND")

        let hi = try parse_add(var p)
        return ok(Expr(kind: E_BETWEEN, negated: neg, args: [left, lo, hi]))

    return ok(left)

fn parse_add(var p: Parser) Result[Expr, SqlError]:
    var left = try parse_mul(var p)

    while at_sym(p, "+") or at_sym(p, "-") or at_sym(p, "||"):
        let op = p.toks[p.pos].text.clone()
        p.pos += 1

        let right = try parse_mul(var p)
        left = Expr(kind: E_BIN, op: op, args: [left, right])

    return ok(left)

fn parse_mul(var p: Parser) Result[Expr, SqlError]:
    var left = try parse_unary(var p)

    while at_sym(p, "*") or at_sym(p, "/") or at_sym(p, "%"):
        let op = p.toks[p.pos].text.clone()
        p.pos += 1

        let right = try parse_unary(var p)
        left = Expr(kind: E_BIN, op: op, args: [left, right])

    return ok(left)

fn parse_unary(var p: Parser) Result[Expr, SqlError]:
    if eat_sym(var p, "-"):
        let inner = try parse_unary(var p)
        return ok(Expr(kind: E_NEG, args: [inner]))

    return parse_primary(var p)

fn parse_primary(var p: Parser) Result[Expr, SqlError]:
    let t = p.toks[p.pos].clone()

    if t.kind == T_INT:
        p.pos += 1
        return ok(Expr(kind: E_INT, num: t.num))

    if t.kind == T_STRING:
        p.pos += 1
        return ok(Expr(kind: E_TEXT, text: t.text.clone()))

    if at_kw(p, "NULL"):
        p.pos += 1
        return ok(Expr(kind: E_NULL))

    if at_sym(p, "("):
        p.pos += 1

        let inner = try parse_expr(var p)
        try expect_sym(var p, ")")
        return ok(inner)

    if t.kind == T_IDENT:
        p.pos += 1
        if at_sym(p, "("):
            return parse_call(var p, t.text.clone())

        if eat_sym(var p, "."):
            let column = try expect_ident(var p)
            return ok(Expr(kind: E_COL, table: t.text.clone(), op: column))

        return ok(Expr(kind: E_COL, op: t.text.clone()))

    return error(SqlError(msg: "syntax error"))

# Called with the function name consumed and the next token being `(`.
fn parse_call(var p: Parser, name: String) Result[Expr, SqlError]:
    p.pos += 1

    let distinct = eat_kw(var p, "DISTINCT")
    var star = false
    var args: List[Expr] = []

    if eat_sym(var p, "*"):
        star = true
    else if not at_sym(p, ")"):
        args.append(try parse_expr(var p))
        while eat_sym(var p, ","):
            args.append(try parse_expr(var p))

    try expect_sym(var p, ")")
    return ok(Expr(kind: E_CALL, op: name, distinct: distinct, star: star, args: args))

fn parse_colref(var p: Parser) Result[Expr, SqlError]:
    let first = try expect_ident(var p)

    if eat_sym(var p, "."):
        let second = try expect_ident(var p)
        return ok(Expr(kind: E_COL, table: first, op: second))

    return ok(Expr(kind: E_COL, op: first))

fn parse_item(var p: Parser) Result[Item, SqlError]:
    if eat_sym(var p, "*"):
        return ok(Item(kind: I_STAR))

    let t = p.toks[p.pos].clone()

    if (
        t.kind == T_IDENT
        and p.toks[p.pos + 1].kind == T_SYMBOL
        and p.toks[p.pos + 1].text == "."
        and p.toks[p.pos + 2].kind == T_SYMBOL
        and p.toks[p.pos + 2].text == "*"
    ):
        p.pos += 3
        return ok(Item(kind: I_TABLE, table: t.text.clone()))

    let e = try parse_expr(var p)

    if eat_kw(var p, "AS"):
        let alias = try expect_ident(var p)
        return ok(Item(kind: I_EXPR, alias: alias, has_alias: true, expr: e))

    return ok(Item(kind: I_EXPR, expr: e))

fn parse_tref(var p: Parser) Result[TableRef, SqlError]:
    let name = try expect_ident(var p)

    if eat_kw(var p, "AS"):
        let alias = try expect_ident(var p)
        return ok(TableRef(name: name, alias: alias))

    if p.toks[p.pos].kind == T_IDENT:
        let alias = p.toks[p.pos].text.clone()
        p.pos += 1
        return ok(TableRef(name: name, alias: alias))

    return ok(TableRef(name: name.clone(), alias: name))

fn parse_join(var p: Parser) Result[Join, SqlError]:
    var left = false

    if eat_kw(var p, "LEFT"):
        left = true
    else:
        eat_kw(var p, "INNER")

    try expect_kw(var p, "JOIN")

    let tref = try parse_tref(var p)
    try expect_kw(var p, "ON")

    let on = try parse_expr(var p)
    return ok(Join(tref: tref, on: on, left: left))

fn parse_order_item(var p: Parser) Result[OrderItem, SqlError]:
    let e = try parse_expr(var p)
    var desc = false

    if eat_kw(var p, "DESC"):
        desc = true
    else:
        eat_kw(var p, "ASC")

    return ok(OrderItem(expr: e, desc: desc))

fn parse_select(var p: Parser) Result[Select, SqlError]:
    try expect_kw(var p, "SELECT")

    let distinct = eat_kw(var p, "DISTINCT")
    var items: List[Item] = []
    items.append(try parse_item(var p))
    while eat_sym(var p, ","):
        items.append(try parse_item(var p))

    var has_from = false
    var from_ref = TableRef()
    var joins: List[Join] = []

    if eat_kw(var p, "FROM"):
        has_from = true
        from_ref = try parse_tref(var p)
        while at_kw(p, "JOIN") or at_kw(p, "INNER") or at_kw(p, "LEFT"):
            joins.append(try parse_join(var p))

    var has_where = false
    var where_expr = Expr()

    if eat_kw(var p, "WHERE"):
        has_where = true
        where_expr = try parse_expr(var p)

    var group: List[Expr] = []

    if eat_kw(var p, "GROUP"):
        try expect_kw(var p, "BY")
        group.append(try parse_colref(var p))
        while eat_sym(var p, ","):
            group.append(try parse_colref(var p))

    var has_having = false
    var having_expr = Expr()

    if eat_kw(var p, "HAVING"):
        has_having = true
        having_expr = try parse_expr(var p)

    var order: List[OrderItem] = []

    if eat_kw(var p, "ORDER"):
        try expect_kw(var p, "BY")
        order.append(try parse_order_item(var p))
        while eat_sym(var p, ","):
            order.append(try parse_order_item(var p))

    var has_limit = false
    var limit = 0
    var offset = 0

    if eat_kw(var p, "LIMIT"):
        has_limit = true
        limit = try expect_int(var p)
        if eat_kw(var p, "OFFSET"):
            offset = try expect_int(var p)

    return ok(
        Select(
            distinct: distinct, items: items, has_from: has_from, from_ref: from_ref,
            joins: joins, has_where: has_where, where_expr: where_expr, group: group,
            has_having: has_having, having_expr: having_expr, order: order,
            has_limit: has_limit, limit: limit, offset: offset
        )
    )

fn parse_create(var p: Parser) Result[CreateStmt, SqlError]:
    try expect_kw(var p, "CREATE")
    try expect_kw(var p, "TABLE")

    let name = try expect_ident(var p)
    try expect_sym(var p, "(")

    var cols: List[ColDef] = []
    var more = true

    while more:
        let col_name = try expect_ident(var p)
        let type_word = try expect_ident(var p)
        var kind = 0

        if type_word.upper() == "INT":
            kind = V_INT
        else if type_word.upper() == "TEXT":
            kind = V_TEXT
        else:
            return error(SqlError(msg: "syntax error"))

        var primary = false
        var notnull = false
        var constraints = true

        while constraints:
            if eat_kw(var p, "PRIMARY"):
                try expect_kw(var p, "KEY")
                primary = true
            else if eat_kw(var p, "NOT"):
                try expect_kw(var p, "NULL")
                notnull = true
            else:
                constraints = false

        cols.append(
            ColDef(
                name: col_name, kind: kind, notnull: notnull or primary,
                primary: primary
            )
        )
        more = eat_sym(var p, ",")

    try expect_sym(var p, ")")
    return ok(CreateStmt(name: name, cols: cols))

fn parse_row(var p: Parser) Result[List[Expr], SqlError]:
    try expect_sym(var p, "(")

    var exprs: List[Expr] = []
    exprs.append(try parse_expr(var p))
    while eat_sym(var p, ","):
        exprs.append(try parse_expr(var p))
    try expect_sym(var p, ")")
    return ok(exprs)

fn parse_insert(var p: Parser) Result[InsertStmt, SqlError]:
    try expect_kw(var p, "INSERT")
    try expect_kw(var p, "INTO")

    let name = try expect_ident(var p)
    var names: List[String] = []

    if eat_sym(var p, "("):
        names.append(try expect_ident(var p))
        while eat_sym(var p, ","):
            names.append(try expect_ident(var p))
        try expect_sym(var p, ")")

    try expect_kw(var p, "VALUES")

    var rows: List[List[Expr]] = []
    rows.append(try parse_row(var p))
    while eat_sym(var p, ","):
        rows.append(try parse_row(var p))
    return ok(InsertStmt(name: name, names: names, rows: rows))

fn parse_update(var p: Parser) Result[UpdateStmt, SqlError]:
    try expect_kw(var p, "UPDATE")

    let name = try expect_ident(var p)
    try expect_kw(var p, "SET")

    var names: List[String] = []
    var exprs: List[Expr] = []
    var more = true

    while more:
        names.append(try expect_ident(var p))
        try expect_sym(var p, "=")
        exprs.append(try parse_expr(var p))
        more = eat_sym(var p, ",")

    var has_where = false
    var where_expr = Expr()

    if eat_kw(var p, "WHERE"):
        has_where = true
        where_expr = try parse_expr(var p)

    return ok(
        UpdateStmt(
            name: name, names: names, exprs: exprs, has_where: has_where,
            where_expr: where_expr
        )
    )

fn parse_delete(var p: Parser) Result[DeleteStmt, SqlError]:
    try expect_kw(var p, "DELETE")
    try expect_kw(var p, "FROM")

    let name = try expect_ident(var p)
    var has_where = false
    var where_expr = Expr()

    if eat_kw(var p, "WHERE"):
        has_where = true
        where_expr = try parse_expr(var p)

    return ok(DeleteStmt(name: name, has_where: has_where, where_expr: where_expr))

fn parse_drop(var p: Parser) Result[String, SqlError]:
    try expect_kw(var p, "DROP")
    try expect_kw(var p, "TABLE")
    return expect_ident(var p)

# The statement must end after its last clause.
fn finish(p: Parser) Result[Unit, SqlError]:
    if p.toks[p.pos].kind != T_EOF:
        return error(SqlError(msg: "syntax error"))

    return ok(unit)

# ---------------------------------------------------------------- tables and scopes

type ScopeCol:
    table: String = ""
    name: String = ""
    index: Int = 0

type Ctx:
    scope: List[ScopeCol] = []
    grouped: Bool = false
    keys: List[Int] = []

type Table:
    name: String = ""
    cols: List[ColDef] = []
    rows: List[List[Value]] = []

type OutCol:
    expr: Expr = Expr()
    name: String = ""

type Group:
    key: List[Value] = []
    rep: List[Value] = []
    rows: List[List[Value]] = []

fn table_index(db: List[Table], name: String) Optional[Int]:
    for i in 0..db.length():
        if db[i].name == name:
            return some(i)
    return none

fn resolve_table(db: List[Table], name: String) Result[Int, SqlError]:
    if let i = table_index(db, name):
        return ok(i)

    return error(SqlError(msg: "no such table: " + name))

fn col_index(cols: List[ColDef], name: String) Int:
    for c in 0..cols.length():
        if cols[c].name == name:
            return c
    return -1

fn pk_index(cols: List[ColDef]) Int:
    for c in 0..cols.length():
        if cols[c].primary:
            return c
    return -1

fn append_scope(var scope: List[ScopeCol], alias: String, cols: List[ColDef]) Unit:
    for c in cols:
        scope.append(
            ScopeCol(
                table: alias.clone(), name: c.name.clone(), index: scope.length()
            )
        )

fn qualified(table: String, name: String) String:
    if table == "":
        return name.clone()

    return "{table}.{name}"

fn lookup(scope: List[ScopeCol], table: String, name: String) Result[Int, SqlError]:
    var found = -1
    var count = 0

    for c in scope:
        if c.name == name and (table == "" or c.table == table):
            found = c.index
            count += 1

    if count == 0:
        return error(SqlError(msg: "no such column: " + qualified(table, name)))
    if count > 1:
        return error(SqlError(msg: "ambiguous column: " + name))

    return ok(found)

fn has_aggregate(e: Expr) Bool:
    if e.kind == E_CALL and AGGREGATES.contains(e.op.upper()):
        return true

    for a in e.args:
        if has_aggregate(a):
            return true
    return false

# ---------------------------------------------------------------- name resolution

fn scalar_arity(name: String) Int:
    if name == "UPPER" or name == "LOWER" or name == "LENGTH" or name == "ABS":
        return 1
    if name == "SUBSTR":
        return 3
    if name == "COALESCE":
        return 0

    return -1

# Name resolution for one expression, in the order the spec gives: unknown columns, unknown
# functions, wrong argument counts, aggregate placement and GROUP BY membership.
fn check(e: Expr, ctx: Ctx, allow_agg: Bool, in_agg: Bool) Result[Unit, SqlError]:
    if e.kind == E_COL:
        let idx = try lookup(ctx.scope, e.table, e.op)
        if ctx.grouped and not in_agg and not ctx.keys.contains(idx):
            return error(
                SqlError(
                    msg: "column " + qualified(
                        e.table, e.op
                    ) + " must appear in GROUP BY"
                )
            )

        return ok(unit)

    if e.kind == E_CALL:
        return check_call(e, ctx, allow_agg, in_agg)

    for a in e.args:
        try check(a, ctx, allow_agg, in_agg)
    return ok(unit)

fn check_call(e: Expr, ctx: Ctx, allow_agg: Bool, in_agg: Bool) Result[Unit, SqlError]:
    let name = e.op.upper()

    if AGGREGATES.contains(name):
        if not allow_agg:
            return error(SqlError(msg: "misuse of aggregate"))

        var arity_ok = e.args.length() == 1 and not e.star
        if name == "COUNT" and e.star:
            arity_ok = not e.distinct
        if not arity_ok:
            return error(SqlError(msg: "wrong number of arguments to " + name))

        for a in e.args:
            try check(a, ctx, false, true)
        return ok(unit)

    let arity = scalar_arity(name)
    if arity < 0:
        return error(SqlError(msg: "no such function: " + name))
    if e.star or (e.distinct and e.args.length() != 1):
        return error(SqlError(msg: "wrong number of arguments to " + name))
    if arity > 0 and e.args.length() != arity:
        return error(SqlError(msg: "wrong number of arguments to " + name))
    if arity == 0 and e.args.length() == 0:
        return error(SqlError(msg: "wrong number of arguments to " + name))

    for a in e.args:
        try check(a, ctx, allow_agg, in_agg)
    return ok(unit)

# ---------------------------------------------------------------- expression evaluation

fn type_error() SqlError:
    return SqlError(msg: "type error")

fn truth(v: Value) Result[Bool, SqlError]:
    if v.kind == V_NULL:
        return ok(false)
    if v.kind == V_BOOL:
        return ok(v.flag)

    return error(type_error())

# NOT for values already known to be boolean or NULL.
fn not3(v: Value) Value:
    if v.kind == V_BOOL:
        return bool_value(not v.flag)

    return null_value()

fn and3(a: Value, b: Value) Value:
    if (a.kind == V_BOOL and not a.flag) or (b.kind == V_BOOL and not b.flag):
        return bool_value(false)
    if a.kind == V_NULL or b.kind == V_NULL:
        return null_value()

    return bool_value(true)

fn cmp_holds(op: String, c: Int) Bool:
    if op == "=":
        return c == 0
    if op == "<>":
        return c != 0
    if op == "<":
        return c < 0
    if op == "<=":
        return c <= 0
    if op == ">":
        return c > 0

    return c >= 0

fn compare_values(op: String, l: Value, r: Value) Result[Value, SqlError]:
    if l.kind == V_NULL or r.kind == V_NULL:
        return ok(null_value())
    if l.kind != r.kind or (l.kind != V_INT and l.kind != V_TEXT):
        return error(type_error())

    var c = 0

    if l.kind == V_INT:
        if l.num < r.num:
            c = -1
        else if l.num > r.num:
            c = 1
    else:
        c = l.text.compare(r.text)

    return ok(bool_value(cmp_holds(op, c)))

fn arith(op: String, l: Value, r: Value) Result[Value, SqlError]:
    if l.kind == V_NULL or r.kind == V_NULL:
        return ok(null_value())
    if l.kind != V_INT or r.kind != V_INT:
        return error(type_error())
    if op == "+":
        return ok(int_value(l.num + r.num))
    if op == "-":
        return ok(int_value(l.num - r.num))
    if op == "*":
        return ok(int_value(l.num * r.num))
    if r.num == 0:
        return error(SqlError(msg: "division by zero"))
    if op == "/":
        return ok(int_value(l.num / r.num))

    return ok(int_value(l.num % r.num))

fn concat_values(l: Value, r: Value) Result[Value, SqlError]:
    if l.kind == V_NULL or r.kind == V_NULL:
        return ok(null_value())
    if l.kind != V_TEXT or r.kind != V_TEXT:
        return error(type_error())

    return ok(text_value(l.text + r.text))

fn binary(op: String, l: Value, r: Value) Result[Value, SqlError]:
    if op == "||":
        return concat_values(l, r)
    if op == "+" or op == "-" or op == "*" or op == "/" or op == "%":
        return arith(op, l, r)

    return compare_values(op, l, r)

fn byte_codes(s: String) List[Int]:
    var out: List[Int] = []
    for b in s.to_bytes().values():
        out.append(b.to_int())
    return out

# Whole-string LIKE: `%` matches any run of bytes, `_` exactly one byte.
fn like_match(t: List[Int], p: List[Int]) Bool:
    var i = 0
    var j = 0
    var star = -1
    var mark = 0

    while i < t.length():
        if j < p.length() and p[j] == 37:
            star = j
            mark = i
            j += 1
        else if j < p.length() and (p[j] == 95 or p[j] == t[i]):
            i += 1
            j += 1
        else if star >= 0:
            j = star + 1
            mark += 1
            i = mark
        else:
            return false

    while j < p.length() and p[j] == 37:
        j += 1
    return j == p.length()

fn like_value(x: Value, pattern: Value) Result[Value, SqlError]:
    if x.kind == V_NULL or pattern.kind == V_NULL:
        return ok(null_value())
    if x.kind != V_TEXT or pattern.kind != V_TEXT:
        return error(type_error())

    return ok(bool_value(like_match(byte_codes(x.text), byte_codes(pattern.text))))

fn negate(x: Value) Result[Value, SqlError]:
    if x.kind == V_NULL:
        return ok(null_value())
    if x.kind != V_INT:
        return error(type_error())

    return ok(int_value(0 - x.num))

fn logical_not(x: Value) Result[Value, SqlError]:
    if x.kind == V_NULL or x.kind == V_BOOL:
        return ok(not3(x))

    return error(type_error())

fn eval_and(
    e: Expr,
    ctx: Ctx,
    row: List[Value],
    group: List[List[Value]]
) Result[Value, SqlError]:
    let l = try eval(e.args[0], ctx, row, group)
    if l.kind != V_NULL and l.kind != V_BOOL:
        return error(type_error())
    if l.kind == V_BOOL and not l.flag:
        return ok(bool_value(false))

    let r = try eval(e.args[1], ctx, row, group)
    if r.kind != V_NULL and r.kind != V_BOOL:
        return error(type_error())
    if r.kind == V_BOOL and not r.flag:
        return ok(bool_value(false))
    if l.kind == V_NULL or r.kind == V_NULL:
        return ok(null_value())

    return ok(bool_value(true))

fn eval_or(
    e: Expr,
    ctx: Ctx,
    row: List[Value],
    group: List[List[Value]]
) Result[Value, SqlError]:
    let l = try eval(e.args[0], ctx, row, group)
    if l.kind != V_NULL and l.kind != V_BOOL:
        return error(type_error())
    if l.kind == V_BOOL and l.flag:
        return ok(bool_value(true))

    let r = try eval(e.args[1], ctx, row, group)
    if r.kind != V_NULL and r.kind != V_BOOL:
        return error(type_error())
    if r.kind == V_BOOL and r.flag:
        return ok(bool_value(true))
    if l.kind == V_NULL or r.kind == V_NULL:
        return ok(null_value())

    return ok(bool_value(false))

fn eval_in(
    e: Expr,
    x: Value,
    ctx: Ctx,
    row: List[Value],
    group: List[List[Value]]
) Result[Value, SqlError]:
    var found = false
    var saw_null = false

    for k in 1..e.args.length():
        let v = try eval(e.args[k], ctx, row, group)
        if x.kind == V_NULL:
            continue

        if v.kind == V_NULL:
            saw_null = true
            continue

        if v.kind != x.kind or (x.kind != V_INT and x.kind != V_TEXT):
            return error(type_error())

        if same_value(x, v):
            found = true

    var result = null_value()

    if x.kind == V_NULL:
        result = null_value()
    else if found:
        result = bool_value(true)
    else if saw_null:
        result = null_value()
    else:
        result = bool_value(false)

    if e.negated:
        result = not3(result)
    return ok(result)

# Scalar functions: every argument is evaluated, a NULL argument gives NULL, then types are checked.
fn scalar_call(name: String, vals: List[Value]) Result[Value, SqlError]:
    if name == "COALESCE":
        for v in vals:
            if v.kind != V_NULL:
                return ok(v.clone())
        return ok(null_value())

    for v in vals:
        if v.kind == V_NULL:
            return ok(null_value())

    if name == "UPPER" or name == "LOWER":
        if vals[0].kind != V_TEXT:
            return error(type_error())

        return ok(text_value(change_case(vals[0].text, name == "UPPER")))

    if name == "LENGTH":
        if vals[0].kind != V_TEXT:
            return error(type_error())

        return ok(int_value(vals[0].text.byte_length()))

    if name == "ABS":
        if vals[0].kind != V_INT:
            return error(type_error())
        if vals[0].num < 0:
            return ok(int_value(0 - vals[0].num))

        return ok(vals[0].clone())

    if vals[0].kind != V_TEXT or vals[1].kind != V_INT or vals[2].kind != V_INT:
        return error(type_error())

    return ok(text_value(substring(vals[0].text, vals[1].num, vals[2].num)))

# ASCII-only case mapping.
fn change_case(s: String, to_upper: Bool) String:
    var out: List[Int] = []

    for c in s.scalar_values():
        var m = c

        if to_upper and c >= 97 and c <= 122:
            m = c - 32
        else if not to_upper and c >= 65 and c <= 90:
            m = c + 32

        out.append(m)

    return from_scalars(out).get()

# SUBSTR on bytes, 1-based; the result is the bytes at start .. start+len-1 clipped to the string.
fn substring(s: String, start: Int, len: Int) String:
    if len <= 0:
        return ""

    let data = s.to_bytes()
    let n = data.length()
    var first = 1
    var last = 0

    if start >= 1:
        if start > n:
            return ""

        first = start

        if len > n:
            last = n
        else:
            last = (start + len - 1).min(n)
    else:
        last = start + len - 1
        last = last.min(n)

    if last < first:
        return ""

    return data.decode_utf8_range(first - 1, last).get("")

fn distinct_values(vals: List[Value]) List[Value]:
    var out: List[Value] = []

    for v in vals:
        var seen = false

        for w in out:
            if same_value(v, w):
                seen = true
                break

        if not seen:
            out.append(v.clone())

    return out

fn eval_aggregate(
    e: Expr,
    name: String,
    ctx: Ctx,
    group: List[List[Value]]
) Result[Value, SqlError]:
    if name == "COUNT" and e.star:
        return ok(int_value(group.length()))

    var vals: List[Value] = []

    for row in group:
        let v = try eval(e.args[0], ctx, row, [])
        if v.kind != V_NULL:
            vals.append(v)

    if e.distinct:
        vals = distinct_values(vals)
    if name == "COUNT":
        return ok(int_value(vals.length()))
    if vals.length() == 0:
        return ok(null_value())

    if name == "SUM":
        var total = 0

        for v in vals:
            if v.kind != V_INT:
                return error(type_error())

            total += v.num

        return ok(int_value(total))

    if vals[0].kind != V_INT and vals[0].kind != V_TEXT:
        return error(type_error())

    var best = vals[0].clone()

    for k in 1..vals.length():
        let v = vals[k]
        if v.kind != best.kind:
            return error(type_error())

        let c = order_cmp(v, best)
        if name == "MIN" and c < 0:
            best = v.clone()
        if name == "MAX" and c > 0:
            best = v.clone()

    return ok(best)

fn eval_call(
    e: Expr,
    ctx: Ctx,
    row: List[Value],
    group: List[List[Value]]
) Result[Value, SqlError]:
    let name = e.op.upper()
    if AGGREGATES.contains(name):
        return eval_aggregate(e, name, ctx, group)

    var vals: List[Value] = []
    for a in e.args:
        vals.append(try eval(a, ctx, row, group))
    return scalar_call(name, vals)

fn eval(
    e: Expr,
    ctx: Ctx,
    row: List[Value],
    group: List[List[Value]]
) Result[Value, SqlError]:
    if e.kind == E_INT:
        return ok(int_value(e.num))
    if e.kind == E_TEXT:
        return ok(text_value(e.text.clone()))
    if e.kind == E_NULL:
        return ok(null_value())

    if e.kind == E_COL:
        let idx = try lookup(ctx.scope, e.table, e.op)
        return ok(row[idx].clone())

    if e.kind == E_CALL:
        return eval_call(e, ctx, row, group)
    if e.kind == E_AND:
        return eval_and(e, ctx, row, group)
    if e.kind == E_OR:
        return eval_or(e, ctx, row, group)

    if e.kind == E_BIN:
        let l = try eval(e.args[0], ctx, row, group)
        let r = try eval(e.args[1], ctx, row, group)
        return binary(e.op, l, r)

    let x = try eval(e.args[0], ctx, row, group)
    if e.kind == E_NEG:
        return negate(x)
    if e.kind == E_NOT:
        return logical_not(x)
    if e.kind == E_ISNULL:
        return ok(bool_value((x.kind == V_NULL) != e.negated))
    if e.kind == E_IN:
        return eval_in(e, x, ctx, row, group)

    if e.kind == E_LIKE:
        let pattern = try eval(e.args[1], ctx, row, group)
        var result = try like_value(x, pattern)
        if e.negated:
            result = not3(result)
        return ok(result)

    let lo = try eval(e.args[1], ctx, row, group)
    let hi = try eval(e.args[2], ctx, row, group)
    let ge = try compare_values(">=", x, lo)
    let le = try compare_values("<=", x, hi)
    var result = and3(ge, le)
    if e.negated:
        result = not3(result)
    return ok(result)

# ---------------------------------------------------------------- constraints

fn check_row(cols: List[ColDef], row: List[Value]) Result[Unit, SqlError]:
    for c in 0..cols.length():
        let v = row[c]

        if v.kind == V_NULL:
            if cols[c].notnull:
                return error(
                    SqlError(
                        msg: "NOT NULL constraint failed: " + cols[
                            c
                        ].name
                    )
                )
        else if v.kind != cols[c].kind:
            return error(SqlError(msg: "type mismatch in column " + cols[c].name))

    return ok(unit)

# Primary keys must be unique across `existing` and `fresh`.
fn check_unique(
    existing: List[List[Value]],
    fresh: List[List[Value]],
    pk: Int
) Result[Unit, SqlError]:
    if pk < 0:
        return ok(unit)

    var seen: List[Value] = []
    for r in existing:
        seen.append(r[pk].clone())

    for r in fresh:
        for s in seen:
            if same_value(s, r[pk]):
                return error(SqlError(msg: "duplicate primary key: " + show(r[pk])))
        seen.append(r[pk].clone())

    return ok(unit)

# ---------------------------------------------------------------- SELECT

fn output_name(it: Item) String:
    if it.has_alias:
        return it.alias.clone()
    if it.expr.kind == E_COL:
        return it.expr.op.clone()

    return "?column?"

fn output_index(outs: List[OutCol], name: String) Int:
    for k in 0..outs.length():
        if outs[k].name == name:
            return k
    return -1

fn run_select(db: List[Table], sel: Select) Result[String, SqlError]:
    # Sources: FROM first, then each JOIN. Existence and alias checks come first.
    var sources: List[TableRef] = []

    if sel.has_from:
        sources.append(sel.from_ref.clone())
        for j in sel.joins:
            sources.append(j.tref.clone())

    var scope: List[ScopeCol] = []
    var aliases: List[String] = []
    var tables: List[Int] = []
    var prefixes: List[Ctx] = []

    for tr in sources:
        let ti = try resolve_table(db, tr.name)
        if aliases.contains(tr.alias):
            return error(SqlError(msg: "duplicate alias: " + tr.alias))

        aliases.append(tr.alias.clone())
        tables.append(ti)
        append_scope(var scope, tr.alias, db[ti].cols)
        prefixes.append(Ctx(scope: scope.clone()))

    # JOIN conditions.
    for j in 0..sel.joins.length():
        try check(sel.joins[j].on, prefixes[j + 1], false, false)

    # Select list, with stars expanded into column references.
    var outs: List[OutCol] = []

    for it in sel.items:
        if it.kind == I_STAR:
            for c in scope:
                outs.append(
                    OutCol(
                        expr: Expr(
                            kind: E_COL, table: c.table.clone(), op: c.name.clone()
                        ),
                        name: c.name.clone()
                    )
                )
        else if it.kind == I_TABLE:
            var found = false

            for c in scope:
                if c.table == it.table:
                    found = true
                    outs.append(
                        OutCol(
                            expr: Expr(
                                kind: E_COL, table: c.table.clone(), op: c.name.clone()
                            ),
                            name: c.name.clone()
                        )
                    )

            if not found:
                return error(SqlError(msg: "no such table: " + it.table))
        else:
            outs.append(OutCol(expr: it.expr.clone(), name: output_name(it)))

    # GROUP BY columns.
    var keys: List[Int] = []
    for g in sel.group:
        keys.append(try lookup(scope, g.table, g.op))

    var grouped = sel.group.length() > 0 or sel.has_having
    for o in outs:
        if has_aggregate(o.expr):
            grouped = true
    for ob in sel.order:
        if has_aggregate(ob.expr):
            grouped = true

    let ctx = Ctx(scope: scope.clone(), grouped: grouped, keys: keys.clone())

    if sel.has_where:
        let plain = Ctx(scope: scope.clone())
        try check(sel.where_expr, plain, false, false)

    for o in outs:
        try check(o.expr, ctx, true, false)
    if sel.has_having:
        try check(sel.having_expr, ctx, true, false)

    # ORDER BY: an output position, an output column name, or an expression (-1).
    var order_col: List[Int] = []
    var descs: List[Bool] = []

    for ob in sel.order:
        descs.append(ob.desc)

        if ob.expr.kind == E_INT:
            if ob.expr.num < 1 or ob.expr.num > outs.length():
                return error(SqlError(msg: "bad ORDER BY position"))

            order_col.append(ob.expr.num - 1)
        else if (
            ob.expr.kind == E_COL
            and ob.expr.table == ""
            and output_index(outs, ob.expr.op) >= 0
        ):
            order_col.append(output_index(outs, ob.expr.op))
        else:
            try check(ob.expr, ctx, true, false)
            order_col.append(-1)

    # Joins, in order.
    var rows: List[List[Value]] = []

    if sel.has_from:
        for r in db[tables[0]].rows:
            rows.append(r.clone())
    else:
        let no_columns: List[Value] = []
        rows.append(no_columns)

    for j in 0..sel.joins.length():
        let s = j + 1
        let right = db[tables[s]].rows
        let width = db[tables[s]].cols.length()
        var next: List[List[Value]] = []

        for l in rows:
            var matched = false

            for r in right:
                var combo = l.clone()
                for v in r:
                    combo.append(v.clone())

                let cond = try eval(sel.joins[j].on, prefixes[s], combo, [])
                let keep = try truth(cond)

                if keep:
                    matched = true
                    next.append(combo)

            if not matched and sel.joins[j].left:
                var padded = l.clone()
                for k in 0..width:
                    padded.append(null_value())
                next.append(padded)

        rows = next

    # WHERE.
    if sel.has_where:
        var kept: List[List[Value]] = []

        for r in rows:
            let cond = try eval(sel.where_expr, ctx, r, [])
            let keep = try truth(cond)
            if keep:
                kept.append(r.clone())

        rows = kept

    # Units to project: one per row, or one per group (after HAVING).
    var reps: List[List[Value]] = []
    var mems: List[List[List[Value]]] = []

    if grouped:
        var groups: List[Group] = []

        for r in rows:
            var key: List[Value] = []
            for k in keys:
                key.append(r[k].clone())

            var gi = -1

            for g in 0..groups.length():
                if same_row(groups[g].key, key):
                    gi = g
                    break

            if gi < 0:
                groups.append(Group(key: key, rep: r.clone(), rows: []))
                gi = groups.length() - 1

            groups[gi].rows.append(r.clone())

        if groups.length() == 0 and keys.length() == 0:
            groups.append(Group(key: [], rep: null_row(scope.length()), rows: []))

        for g in groups:
            if sel.has_having:
                let cond = try eval(sel.having_expr, ctx, g.rep, g.rows)
                let keep = try truth(cond)
                if not keep:
                    continue

            reps.append(g.rep.clone())
            mems.append(g.rows.clone())
    else:
        for r in rows:
            reps.append(r.clone())

            let no_members: List[List[Value]] = []
            mems.append(no_members)

    # Select values.
    var outvals: List[List[Value]] = []

    for u in 0..reps.length():
        var vals: List[Value] = []
        for o in outs:
            vals.append(try eval(o.expr, ctx, reps[u], mems[u]))
        outvals.append(vals)

    # ORDER BY keys.
    var sortkeys: List[List[Value]] = []

    for u in 0..reps.length():
        var ks: List[Value] = []

        for k in 0..order_col.length():
            if order_col[k] >= 0:
                ks.append(outvals[u][order_col[k]].clone())
            else:
                ks.append(try eval(sel.order[k].expr, ctx, reps[u], mems[u]))

        sortkeys.append(ks)

    # DISTINCT keeps the first of each duplicate output row.
    var idx: List[Int] = []

    for u in 0..reps.length():
        var dup = false

        if sel.distinct:
            for v in idx:
                if same_row(outvals[v], outvals[u]):
                    dup = true
                    break

        if not dup:
            idx.append(u)

    if order_col.length() > 0:
        idx = idx.sorted(
            fn(a: Int, b: Int) Int: compare_keys(
                sortkeys[a], sortkeys[b], descs
            )
        )

    # OFFSET and LIMIT.
    var start = 0
    if sel.has_limit:
        start = sel.offset
    if start > idx.length():
        start = idx.length()

    var count = idx.length() - start
    if sel.has_limit and sel.limit < count:
        count = sel.limit

    var names: List[String] = []
    for o in outs:
        names.append(o.name.clone())

    var lines: List[String] = []
    lines.append(names.join("|"))

    for k in start..start + count:
        var cells: List[String] = []
        for v in outvals[idx[k]]:
            cells.append(show(v))
        lines.append(cells.join("|"))

    lines.append("({count} rows)")
    return ok(lines.join("\n"))

# ---------------------------------------------------------------- other statements

fn exec_create(var db: List[Table], st: CreateStmt) Result[String, SqlError]:
    if table_index(db, st.name).is_some():
        return error(SqlError(msg: "table " + st.name + " already exists"))

    var pks = 0

    for c in 0..st.cols.length():
        for d in 0..c:
            if st.cols[d].name == st.cols[c].name:
                return error(SqlError(msg: "duplicate column: " + st.cols[c].name))
        if st.cols[c].primary:
            pks += 1

    if pks > 1:
        return error(SqlError(msg: "multiple primary keys"))

    db.append(Table(name: st.name.clone(), cols: st.cols.clone(), rows: []))
    return ok("ok")

fn exec_drop(var db: List[Table], name: String) Result[String, SqlError]:
    let ti = try resolve_table(db, name)
    db.splice(ti, 1, [])
    return ok("ok")

fn exec_insert(var db: List[Table], st: InsertStmt) Result[String, SqlError]:
    let ti = try resolve_table(db, st.name)
    let cols = db[ti].cols.clone()
    var targets: List[Int] = []

    if st.names.length() == 0:
        for c in 0..cols.length():
            targets.append(c)
    else:
        for name in st.names:
            let idx = col_index(cols, name)
            if idx < 0:
                return error(SqlError(msg: "no such column: " + name))
            if targets.contains(idx):
                return error(SqlError(msg: "duplicate column: " + name))

            targets.append(idx)

    let ctx = Ctx()
    var fresh: List[List[Value]] = []

    for exprs in st.rows:
        if exprs.length() != targets.length():
            return error(SqlError(msg: "wrong number of values"))

        var row = null_row(cols.length())
        let no_row: List[Value] = []
        let no_group: List[List[Value]] = []

        for k in 0..exprs.length():
            try check(exprs[k], ctx, false, false)
            row[targets[k]] = try eval(exprs[k], ctx, no_row, no_group)

        try check_row(cols, row)
        fresh.append(row)

    try check_unique(db[ti].rows, fresh, pk_index(cols))
    for r in fresh:
        db[ti].rows.append(r.clone())
    return ok("inserted {fresh.length()}")

fn exec_update(var db: List[Table], st: UpdateStmt) Result[String, SqlError]:
    let ti = try resolve_table(db, st.name)
    let cols = db[ti].cols.clone()
    var scope: List[ScopeCol] = []
    append_scope(var scope, st.name, cols)

    let ctx = Ctx(scope: scope)
    var targets: List[Int] = []

    for name in st.names:
        let idx = col_index(cols, name)
        if idx < 0:
            return error(SqlError(msg: "no such column: " + name))

        targets.append(idx)

    for e in st.exprs:
        try check(e, ctx, false, false)
    if st.has_where:
        try check(st.where_expr, ctx, false, false)

    let no_group: List[List[Value]] = []
    var newrows: List[List[Value]] = []
    var count = 0

    for r in db[ti].rows:
        var hit = true

        if st.has_where:
            let cond = try eval(st.where_expr, ctx, r, no_group)
            hit = try truth(cond)

        if hit:
            var vals: List[Value] = []
            for e in st.exprs:
                vals.append(try eval(e, ctx, r, no_group))

            var nr = r.clone()
            for k in 0..targets.length():
                nr[targets[k]] = vals[k].clone()
            try check_row(cols, nr)
            newrows.append(nr)
            count += 1
        else:
            newrows.append(r.clone())

    let no_existing: List[List[Value]] = []
    try check_unique(no_existing, newrows, pk_index(cols))
    db[ti].rows = newrows
    return ok("updated {count}")

fn exec_delete(var db: List[Table], st: DeleteStmt) Result[String, SqlError]:
    let ti = try resolve_table(db, st.name)
    let cols = db[ti].cols.clone()
    var scope: List[ScopeCol] = []
    append_scope(var scope, st.name, cols)

    let ctx = Ctx(scope: scope)
    if st.has_where:
        try check(st.where_expr, ctx, false, false)

    let no_group: List[List[Value]] = []
    var kept: List[List[Value]] = []
    var count = 0

    for r in db[ti].rows:
        var hit = true

        if st.has_where:
            let cond = try eval(st.where_expr, ctx, r, no_group)
            hit = try truth(cond)

        if hit:
            count += 1
        else:
            kept.append(r.clone())

    db[ti].rows = kept
    return ok("deleted {count}")

# Runs one statement. Parsing (including the whole syntax check) happens before anything executes.
fn execute(var db: List[Table], toks: List[Token]) Result[String, SqlError]:
    var p = Parser(toks: toks.clone(), pos: 0)

    if at_kw(p, "SELECT"):
        let sel = try parse_select(var p)
        try finish(p)
        return run_select(db, sel)

    if at_kw(p, "CREATE"):
        let st = try parse_create(var p)
        try finish(p)
        return exec_create(var db, st)

    if at_kw(p, "DROP"):
        let name = try parse_drop(var p)
        try finish(p)
        return exec_drop(var db, name)

    if at_kw(p, "INSERT"):
        let st = try parse_insert(var p)
        try finish(p)
        return exec_insert(var db, st)

    if at_kw(p, "UPDATE"):
        let st = try parse_update(var p)
        try finish(p)
        return exec_update(var db, st)

    if at_kw(p, "DELETE"):
        let st = try parse_delete(var p)
        try finish(p)
        return exec_delete(var db, st)

    return error(SqlError(msg: "syntax error"))

fn run_statement(var db: List[Table], toks: List[Token]) String:
    let r = execute(var db, toks)
    if r.is_error():
        return "error: " + r.err().message()

    return r.get().clone()

export fn main() Int:
    let text = read_lines(stdin()).get().join("\n")
    var db: List[Table] = []
    for stmt in split_statements(lex(text)):
        stdout().write(run_statement(var db, stmt) + "\n").get()
    return 0

import Data from "@std/core.ms"
import StringBuilder from "@std/string.ms"
import JsonValue, parse, stringify from "@std/data/json.ms"
import escape from "@std/data/html.ms"

# Text templates, written and run in Manuscript: compile once, render with `JsonValue` data.
#
#     import compile, render, to_data from "@std/text/template.ms"
#     let page = compile("Hello {{ name | title }}! {{ for t in tags }}#{{ t }} {{ end }}").get()
#     page.render(to_data(user).get()).get()
#
# Actions sit between `{{` and `}}`:
#
# - `{{ user.name }}` prints a value; a path walks object members and list positions (`items.0`).
#   Names resolve to loop variables first, then to members of the root object. A missing path is an
#   error unless `strict: false`, or the value goes through `default`.
# - `{{ name | upper | default("anonymous") }}` pipes a value through filters. Filters bind tighter than
#   operators: `{{ if name | length > 3 }}`. Filters: `upper lower trim title length join(sep) json
#   default(value) escape raw first last reverse keys contains(x) replace(old, new) truncate(n)`.
# - `{{ if cond }}…{{ else if cond }}…{{ else }}…{{ end }}` with `== != < <= > >= and or not` and
#   parentheses. Empty text, zero, null, false, and empty lists and objects are false; a missing path
#   in a condition is false.
# - `{{ for item in items }}…{{ else }}…{{ end }}` loops a list (the `else` branch runs when it is empty).
#   `for i, item in items` adds the position; for an object, `for key, value in object`; a single name over
#   an object binds `{key, value}`. Inside a loop `loop.index`, `loop.first`, `loop.last` and `loop.length` exist.
# - `{{ include "name" }}` renders a partial from the `partials` map passed to `render`, in the current scope.
# - `{{# comment }}` prints nothing. `{{-` and `-}}` trim adjacent white space. `{{ "{{" }}` prints braces.
#
# `compile(source, html: true)` escapes every printed value for HTML text and quoted attributes; end an
# action with `| raw` to print trusted markup unchanged. Values come from data only: templates cannot
# call functions or run code, and `max_output` bounds the result.

# Errors from compiling or rendering a template.
export type TemplateError:
    # The template text is malformed; `line` counts from 1.
    case Syntax(
        # Line of the action that failed.
        line: Int,
        # What was wrong, without echoing template text.
        reason: String
    )
    # A printed path has no value and rendering is strict.
    case MissingValue(
        # The dotted path that was not found.
        path: String
    )
    # A filter was called with the wrong kind of value or arguments.
    case InvalidFilter(
        # The filter that failed, such as `join` or `truncate`.
        name: String,
        # A short reason such as a missing argument, never echoing values.
        reason: String
    )
    # `include` named a partial that was not supplied, or partials nest too deeply.
    case UnknownPartial(
        # The partial name that was requested but not found in the supplied map.
        name: String
    )
    # Output exceeded `max_output`.
    case LimitExceeded
    # The data could not be converted to JSON.
    case InvalidData

# A parsed template expression: a literal, a path, a filter call or an operator. Internal to the engine; hidden from callers.
export opaque type TemplateExpr:
    # A literal string, number, boolean or null written in the template.
    case Literal(
        # The literal as a JSON value.
        value: JsonValue
    )
    # A dotted path whose first name is a loop variable or a root member.
    case Path(
        # The names between the dots, in order.
        parts: List[String]
    )
    # A filter applied to its first argument; later arguments are the filter's own.
    case Call(
        # The filter name, one of the documented filters.
        name: String,
        # The filtered value followed by the filter arguments.
        args: List[TemplateExpr]
    )
    # A comparison or logical operator over one or two operands.
    case Op(
        # One of `and or not == != < <= > >=`.
        op: String,
        # The operands, in source order.
        args: List[TemplateExpr]
    )

# One `if` or `else if` arm of a conditional node. Internal to the engine.
export opaque type TemplateBranch:
    # Condition that selects this arm when true.
    cond: TemplateExpr
    # Nodes rendered when the condition holds.
    body: List[TemplateNode]

# A parsed template node: text, a printed value, a conditional, a loop or an include. Internal to the engine.
export opaque type TemplateNode:
    # Literal text copied to the output.
    case Text(
        # The text between actions, after trim markers.
        text: String
    )
    # A value printed to the output.
    case Emit(
        # The expression whose value is printed.
        expr: TemplateExpr,
        # True when the printed text is HTML-escaped.
        escape: Bool
    )
    # A conditional with its arms and optional final branch.
    case If(
        # Arms tried in order; the first true condition renders.
        branches: List[TemplateBranch],
        # Nodes rendered when no arm holds.
        otherwise: List[TemplateNode]
    )
    # A loop over a list or object.
    case Each(
        # First loop name: the item, or the position or key when `second` is set.
        first: String,
        # Second loop name, or empty text for a single-name loop.
        second: String,
        # Expression that yields the list or object being walked.
        source: TemplateExpr,
        # Nodes rendered once per element.
        body: List[TemplateNode],
        # Nodes rendered when the collection is empty.
        otherwise: List[TemplateNode]
    )
    # Renders a named partial in the current scope.
    case Include(
        # Expression that yields the partial's name.
        name: TemplateExpr
    )

# A compiled template; render it any number of times.
export opaque type Template:
    # The parsed nodes in source order.
    nodes: List[TemplateNode]
    # True when printed values are HTML-escaped by default.
    html: Bool

type Token:
    action: Bool
    body: String
    line: Int

type Tok:
    kind: String
    text: String

let FILTERS = [
    "upper", "lower", "trim", "title", "length", "join", "json", "default", "escape",
    "raw", "first", "last", "reverse", "keys", "contains", "replace", "truncate"
]
let MAX_DEPTH = 64

# Compiles template source. With `html: true`, printed values are HTML-escaped unless they end in `| raw`.
export fn compile(source: String, html: Bool = false) Template!TemplateError:
    let tokens = try tokenize(source)
    var builder = Builder(tokens: tokens, at: 0, html: html)
    let done = try builder.block(0)
    if done.end != "": return error(
        TemplateError.Syntax(line: done.line, reason: "unexpected {done.end}")
    )

    return ok(Template(nodes: done.nodes, html: html))

# Compiles and renders in one call; use `compile` when rendering more than once.
export fn render(
    source: String,
    data: JsonValue,
    html: Bool = false
) String!TemplateError:
    let template = try compile(source, html: html)
    return template.render(data)

# Converts any `Data` value (records, lists, scalars) to the `JsonValue` a template reads.
export fn to_data[T: Data](value: T) JsonValue!TemplateError:
    let text = stringify(value: value)
    if text.is_error(): return error(TemplateError.InvalidData)

    let parsed = parse(text.get())
    if parsed.is_error(): return error(TemplateError.InvalidData)

    return ok(parsed.get())

impl Template:
    # Renders with `data` (an object supplies the root names). `partials` feeds `include`. A strict render
    # fails on a missing printed path; `max_output` bounds the text length (default 16 MiB).
    fn render(
        data: JsonValue,
        partials: Map[String, Template] = Map[String, Template](),
        strict: Bool = true,
        max_output: Int = 16777216
    ) String!TemplateError:
        var frames = List[Map[String, JsonValue]]()
        frames.append(root_names(data))

        var run = Run(
            out: StringBuilder(), written: 0, frames: frames,
            partials: partials.clone(), strict: strict, limit: max_output,
            html: self.html
        )
        try run.nodes(self.nodes.clone(), 0)
        return ok(run.out.build())

fn root_names(data: JsonValue) Map[String, JsonValue]:
    if let members = data.as_map(): return members

    return Map[String, JsonValue]()

# ---- lexing -------------------------------------------------------------------------------

fn count_lines(text: String) Int:
    return text.count("\n")

fn tokenize(source: String) List[Token]!TemplateError:
    var tokens = List[Token]()
    var rest = source.clone()
    var line = 1
    var trim_next = false

    while true:
        let open = rest.index_of("\{\{")

        if not open.is_some():
            tokens.append(
                Token(
                    action: false,
                    body: if trim_next: rest.trim_start() else: rest.clone(), line: line
                )
            )
            break

        var text = rest.take(open.get(0))
        if trim_next: text = text.trim_start()

        let after = rest.drop(open.get(0) + 2)
        let close = after.index_of("\}\}")
        if not close.is_some(): return error(
            TemplateError.Syntax(
                line: line + count_lines(text), reason: "unterminated action"
            )
        )

        var body = after.take(close.get(0))
        let action_line = line + count_lines(rest.take(open.get(0)))
        trim_next = false

        if body.starts_with("-") and (body.length() == 1 or is_blank(body.get(1))):
            text = text.trim_end()
            body = body.drop(1)

        if (
            body.ends_with("-")
            and (
                body.length() == 1
                or is_blank(body.get(body.length() - 2))
            )
        ):
            trim_next = true
            body = body.take(body.length() - 1)

        if not text.is_empty(): tokens.append(
            Token(action: false, body: text, line: line)
        )
        if not body.trim().starts_with("#"):
            tokens.append(Token(action: true, body: body.trim(), line: action_line))
        line = action_line + count_lines(after.take(close.get(0)))
        rest = after.drop(close.get(0) + 2)

    return ok(tokens)

fn is_blank(c: String) Bool:
    return c == " " or c == "\t" or c == "\n" or c == "\r"

fn is_word_start(c: String) Bool:
    return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")

fn is_digit(c: String) Bool:
    return c >= "0" and c <= "9"

fn lex(text: String, line: Int) List[Tok]!TemplateError:
    var toks = List[Tok]()
    let chars = text.chars()
    var i = 0

    while i < chars.length():
        let c = chars[i]
        let two = if i + 1 < chars.length(): "{c}{chars[i + 1]}" else: c.clone()

        if is_blank(c):
            i += 1
        else if two == "==" or two == "!=" or two == "<=" or two == ">=":
            toks.append(Tok(kind: "sym", text: two))
            i += 2
        else if c == "(" or c == ")" or c == "," or c == "|" or c == "<" or c == ">":
            toks.append(Tok(kind: "sym", text: c.clone()))
            i += 1
        else if c == "\"":
            var out = StringBuilder()
            i += 1

            var closed = false

            while i < chars.length():
                if chars[i] == "\"":
                    closed = true
                    i += 1
                    break

                if chars[i] == "\\" and i + 1 < chars.length():
                    let e = chars[i + 1]
                    out.append(if e == "n": "\n" else if e == "t": "\t" else: e.clone())
                    i += 2
                else:
                    out.append(chars[i])
                    i += 1

            if not closed: return error(
                TemplateError.Syntax(
                    line: line, reason: "unterminated string"
                )
            )

            toks.append(Tok(kind: "str", text: out.build()))
        else if (
            is_digit(c)
            or (
                c == "-"
                and i + 1 < chars.length()
                and is_digit(chars[i + 1])
            )
        ):
            var out = c.clone()
            i += 1

            while i < chars.length() and (is_digit(chars[i]) or chars[i] == "."):
                out = "{out}{chars[i]}"
                i += 1

            toks.append(Tok(kind: "num", text: out))
        else if is_word_start(c):
            var out = c.clone()
            i += 1

            while (
                i < chars.length()
                and (
                    is_word_start(chars[i])
                    or is_digit(chars[i])
                    or chars[i] == "."
                )
            ):
                out = "{out}{chars[i]}"
                i += 1

            toks.append(Tok(kind: "word", text: out))
        else:
            return error(
                TemplateError.Syntax(
                    line: line, reason: "unexpected character"
                )
            )

    return ok(toks)

# ---- expression parsing --------------------------------------------------------------------

type ExprParser:
    toks: List[Tok]
    at: Int
    line: Int

impl ExprParser:
    fn peek() Tok:
        return self.toks.get(self.at, Tok(kind: "end", text: ""))

    fn is_sym(text: String) Bool:
        let t = self.peek()
        return t.kind == "sym" and t.text == text

    fn is_word(text: String) Bool:
        let t = self.peek()
        return t.kind == "word" and t.text == text

    fn fail(reason: String) TemplateError:
        return TemplateError.Syntax(line: self.line, reason: reason)

    var fn or_expr() TemplateExpr!TemplateError:
        var left = try self.and_expr()

        while self.is_word("or"):
            self.at += 1

            let right = try self.and_expr()
            left = Op("or", [left, right])

        return ok(left)

    var fn and_expr() TemplateExpr!TemplateError:
        var left = try self.not_expr()

        while self.is_word("and"):
            self.at += 1

            let right = try self.not_expr()
            left = Op("and", [left, right])

        return ok(left)

    var fn not_expr() TemplateExpr!TemplateError:
        if self.is_word("not"):
            self.at += 1

            let inner = try self.not_expr()
            return ok(Op("not", [inner]))

        return self.compare()

    var fn compare() TemplateExpr!TemplateError:
        let left = try self.filtered()
        let t = self.peek()
        let is_cmp = (
            t.kind == "sym"
            and ["==", "!=", "<", "<=", ">", ">="].contains(t.text)
        )
        if not is_cmp: return ok(left)

        self.at += 1

        let right = try self.filtered()
        return ok(Op(t.text.clone(), [left, right]))

    var fn filtered() TemplateExpr!TemplateError:
        var value = try self.primary()

        while self.is_sym("|"):
            self.at += 1

            let name = self.peek()
            if name.kind != "word" or not FILTERS.contains(name.text): return error(
                self.fail("unknown filter")
            )

            self.at += 1

            var args = [value]

            if self.is_sym("("):
                self.at += 1

                while not self.is_sym(")"):
                    args.append(try self.or_expr())

                    if self.is_sym(","): self.at += 1
                    else if not self.is_sym(")"): return error(
                        self.fail("expected , or )")
                    )

                self.at += 1

            value = Call(name.text.clone(), args)

        return ok(value)

    var fn primary() TemplateExpr!TemplateError:
        let t = self.peek()
        self.at += 1
        if t.kind == "str": return ok(Literal(JsonValue.StringValue(t.text.clone())))
        if t.kind == "num": return ok(Literal(JsonValue.NumberValue(t.text.clone())))

        if t.kind == "sym" and t.text == "(":
            let inner = try self.or_expr()
            if not self.is_sym(")"): return error(self.fail("expected )"))

            self.at += 1
            return ok(inner)

        if t.kind == "word":
            if t.text == "true": return ok(Literal(JsonValue.BoolValue(true)))
            if t.text == "false": return ok(Literal(JsonValue.BoolValue(false)))
            if t.text == "null": return ok(Literal(JsonValue.Null))
            if t.text == "and" or t.text == "or" or t.text == "not": return error(
                self.fail("unexpected operator")
            )

            return ok(Path(t.text.split(".")))

        return error(self.fail("expected a value"))

fn parse_expr(text: String, line: Int) TemplateExpr!TemplateError:
    let toks = try lex(text, line)
    var parser = ExprParser(toks: toks, at: 0, line: line)
    if parser.toks.is_empty(): return error(
        TemplateError.Syntax(line: line, reason: "empty action")
    )

    let expr = try parser.or_expr()
    if parser.at < parser.toks.length(): return error(
        TemplateError.Syntax(
            line: line, reason: "unexpected text after expression"
        )
    )

    return ok(expr)

# ---- block parsing -------------------------------------------------------------------------

type BlockEnd:
    nodes: List[TemplateNode]
    # "" at end of input, otherwise "end", "else" or "else if".
    end: String
    cond: String
    line: Int

type Builder:
    tokens: List[Token]
    at: Int
    html: Bool

fn first_word(body: String) String:
    return body.split(" ")[0].trim()

fn after_word(body: String) String:
    return body.drop(first_word(body).length()).trim()

impl Builder:
    var fn block(depth: Int) BlockEnd!TemplateError:
        var nodes = List[TemplateNode]()
        if depth > MAX_DEPTH: return error(
            TemplateError.Syntax(line: 0, reason: "nested too deeply")
        )

        while self.at < self.tokens.length():
            let token = self.tokens[self.at].clone()
            self.at += 1

            if not token.action:
                nodes.append(Text(token.body.clone()))
                continue

            let word = first_word(token.body)
            let rest = after_word(token.body)
            if word == "end":
                return ok(
                    BlockEnd(
                        nodes: nodes, end: "end", cond: "", line: token.line
                    )
                )

            if word == "else":
                if first_word(rest) == "if":
                    return ok(
                        BlockEnd(
                            nodes: nodes, end: "else if", cond: after_word(rest),
                            line: token.line
                        )
                    )

                return ok(
                    BlockEnd(
                        nodes: nodes, end: "else", cond: "", line: token.line
                    )
                )

            if word == "if":
                nodes.append(try self.conditional(rest, token.line, depth))
            else if word == "for":
                nodes.append(try self.for_block(rest, token.line, depth))
            else if word == "include":
                nodes.append(Include(try parse_expr(rest, token.line)))
            else:
                nodes.append(try self.emit(token.body, token.line))

        return ok(BlockEnd(nodes: nodes, end: "", cond: "", line: 0))

    fn emit(body: String, line: Int) TemplateNode!TemplateError:
        var expr = try parse_expr(body, line)
        var escape_output = self.html
        let last = trailing_filter(expr)

        if last == "raw":
            escape_output = false
            expr = strip_filter(expr)
        else if last == "escape" and self.html:
            expr = strip_filter(expr)

        return ok(Emit(expr, escape_output))

    var fn conditional(cond: String, line: Int, depth: Int) TemplateNode!TemplateError:
        var branches = List[TemplateBranch]()
        var otherwise = List[TemplateNode]()
        var guard = try parse_expr(cond, line)

        while true:
            let done = try self.block(depth + 1)
            branches.append(TemplateBranch(cond: guard, body: done.nodes))
            if done.end == "end": break

            if done.end == "else if":
                guard = try parse_expr(done.cond, done.line)
                continue

            if done.end == "else":
                let tail = try self.block(depth + 1)
                if tail.end != "end": return error(
                    TemplateError.Syntax(
                        line: done.line, reason: "if needs end"
                    )
                )

                otherwise = tail.nodes
                break

            return error(TemplateError.Syntax(line: line, reason: "if needs end"))

        return ok(If(branches, otherwise))

    var fn for_block(header: String, line: Int, depth: Int) TemplateNode!TemplateError:
        let at = header.index_of(" in ")
        if not at.is_some(): return error(
            TemplateError.Syntax(
                line: line, reason: "for needs `name in value`"
            )
        )

        let names = header.take(at.get(0)).split(",")
        if names.length() > 2: return error(
            TemplateError.Syntax(
                line: line, reason: "for takes one or two names"
            )
        )

        let first = names[0].trim()
        let second = if names.length() == 2: names[1].trim() else: ""
        if first.is_empty() or not is_word_start(first.take(1)) or first.contains("."):
            return error(TemplateError.Syntax(line: line, reason: "bad loop name"))
        if (
            names.length() == 2
            and (
                second.is_empty()
                or second.contains(".")
                or not is_word_start(second.take(1))
            )
        ):
            return error(TemplateError.Syntax(line: line, reason: "bad loop name"))

        let source = try parse_expr(header.drop(at.get(0) + 4), line)
        let body = try self.block(depth + 1)
        var otherwise = List[TemplateNode]()

        if body.end == "else":
            let tail = try self.block(depth + 1)
            if tail.end != "end": return error(
                TemplateError.Syntax(
                    line: line, reason: "for needs end"
                )
            )

            otherwise = tail.nodes
        else if body.end != "end":
            return error(TemplateError.Syntax(line: line, reason: "for needs end"))

        return ok(Each(first, second, source, body.nodes, otherwise))

fn trailing_filter(expr: TemplateExpr) String:
    match expr:
        Call(name, _): return name.clone()
        _: return ""

fn strip_filter(expr: TemplateExpr) TemplateExpr:
    match expr:
        Call(_, args): return args[0].clone()
        _: return expr.clone()

# ---- rendering -----------------------------------------------------------------------------

type Run:
    out: StringBuilder
    written: Int
    frames: List[Map[String, JsonValue]]
    partials: Map[String, Template]
    strict: Bool
    limit: Int
    html: Bool

impl Run:
    var fn write(text: String) Unit!TemplateError:
        self.written += text.length()
        if self.written > self.limit: return error(TemplateError.LimitExceeded)

        self.out.append(text)
        return ok(unit)

    fn lookup(parts: List[String]) JsonValue?:
        var current: JsonValue? = none
        var i = self.frames.length() - 1

        while i >= 0:
            if let found = self.frames[i].get(parts[0]):
                current = found.clone()
                break

            i -= 1

        if not current.is_some(): return none

        var value = current.get(JsonValue.Null)

        for k in 1..parts.length():
            let next = member(value, parts[k])
            if not next.is_some(): return none

            value = next.get(JsonValue.Null)

        return value

    fn eval(expr: TemplateExpr, strict: Bool) JsonValue!TemplateError:
        match expr:
            Literal(value): return ok(value.clone())
            Path(parts): return self.path_value(parts, strict)
            Call(name, args): return self.call(name, args, strict)
            Op(op, args): return self.operator(op, args)

    fn path_value(parts: List[String], strict: Bool) JsonValue!TemplateError:
        if let found = self.lookup(parts): return ok(found)
        if strict: return error(TemplateError.MissingValue(path: parts.join(".")))

        return ok(JsonValue.Null)

    fn operator(op: String, args: List[TemplateExpr]) JsonValue!TemplateError:
        let left = try self.eval(args[0].clone(), false)
        if op == "not": return ok(JsonValue.BoolValue(not truthy(left)))
        if op == "and" and not truthy(left): return ok(JsonValue.BoolValue(false))
        if op == "or" and truthy(left): return ok(JsonValue.BoolValue(true))

        let right = try self.eval(args[1].clone(), false)
        if op == "and" or op == "or": return ok(JsonValue.BoolValue(truthy(right)))
        if op == "==": return ok(JsonValue.BoolValue(equal(left, right)))
        if op == "!=": return ok(JsonValue.BoolValue(not equal(left, right)))

        let order = compare_values(left, right)
        if op == "<": return ok(JsonValue.BoolValue(order < 0))
        if op == "<=": return ok(JsonValue.BoolValue(order <= 0))
        if op == ">": return ok(JsonValue.BoolValue(order > 0 and order != 2))

        return ok(JsonValue.BoolValue(order >= 0 and order != 2))

    fn call(
        name: String,
        args: List[TemplateExpr],
        strict: Bool
    ) JsonValue!TemplateError:
        if name == "default":
            let input = try self.eval(args[0].clone(), false)
            if truthy(input): return ok(input)
            if args.length() != 2: return error(
                TemplateError.InvalidFilter(
                    name: name, reason: "needs one argument"
                )
            )

            return self.eval(args[1].clone(), strict)

        let input = try self.eval(args[0].clone(), strict)
        var values = List[JsonValue]()
        for i in 1..args.length():
            values.append(try self.eval(args[i].clone(), strict))
        return apply_filter(name, input, values)

    var fn nodes(items: List[TemplateNode], depth: Int) Unit!TemplateError:
        for node in items:
            try self.node(node, depth)
        return ok(unit)

    var fn node(node: TemplateNode, depth: Int) Unit!TemplateError:
        match node:
            Text(text): return self.write(text)
            Emit(expr, escape_output): return self.emit(expr, escape_output)
            If(branches, otherwise): return self.branch(branches, otherwise, depth)
            Each(first, second, source, body, otherwise): return self.each(
                first, second, source, body, otherwise, depth
            )
            Include(name): return self.include(name, depth)

    var fn emit(expr: TemplateExpr, escape_output: Bool) Unit!TemplateError:
        let value = try self.eval(expr, self.strict)
        let text = to_text(value)
        return self.write(if escape_output: escape(text) else: text)

    var fn branch(
        branches: List[TemplateBranch],
        otherwise: List[TemplateNode],
        depth: Int
    ) Unit!TemplateError:
        for branch in branches:
            let verdict = try self.eval(branch.cond.clone(), false)
            if truthy(verdict): return self.nodes(branch.body.clone(), depth + 1)

        return self.nodes(otherwise, depth + 1)

    var fn each(
        first: String,
        second: String,
        source: TemplateExpr,
        body: List[TemplateNode],
        otherwise: List[TemplateNode],
        depth: Int
    ) Unit!TemplateError:
        let collection = try self.eval(source, false)
        let rows = rows_of(collection, first, second)
        if rows.is_empty(): return self.nodes(otherwise, depth + 1)

        for i in 0..rows.length():
            var frame = rows[i].clone()
            frame.add("loop", loop_info(i, rows.length()))
            self.frames.append(frame)

            let result = self.nodes(body.clone(), depth + 1)
            let _frame = self.frames.remove(self.frames.length() - 1)
            if result.is_error(): return result

        return ok(unit)

    var fn include(name: TemplateExpr, depth: Int) Unit!TemplateError:
        let key = to_text(try self.eval(name, true))
        if depth > MAX_DEPTH: return error(TemplateError.UnknownPartial(name: key))

        let partial = self.partials.get(key).clone()
        if not partial.is_some(): return error(TemplateError.UnknownPartial(name: key))

        return self.nodes(
            partial.get(
                Template(nodes: List[TemplateNode](), html: false)
            ).nodes.clone(),
            depth + 1
        )

# ---- values --------------------------------------------------------------------------------

fn member(value: JsonValue, key: String) JsonValue?:
    if let found = value.get(key): return found
    if let index = key.parse_int():
        return value.at(index)

    return none

fn loop_info(index: Int, length: Int) JsonValue:
    var fields = Map[String, JsonValue]()
    fields.add("index", JsonValue.NumberValue("{index}"))
    fields.add("first", JsonValue.BoolValue(index == 0))
    fields.add("last", JsonValue.BoolValue(index == length - 1))
    fields.add("length", JsonValue.NumberValue("{length}"))
    return JsonValue.ObjectValue(fields)

# One variable frame per iteration: the list item, or an object's key and value.
fn rows_of(
    collection: JsonValue,
    first: String,
    second: String
) List[Map[String, JsonValue]]:
    var rows = List[Map[String, JsonValue]]()

    if let items = collection.as_list():
        for i in 0..items.length():
            var frame = Map[String, JsonValue]()

            if second.is_empty():
                frame.add(first.clone(), items[i].clone())
            else:
                frame.add(first.clone(), JsonValue.NumberValue("{i}"))
                frame.add(second.clone(), items[i].clone())

            rows.append(frame)
    else if let members = collection.as_map():
        for entry in members.entries():
            var frame = Map[String, JsonValue]()

            if second.is_empty():
                var pair = Map[String, JsonValue]()
                pair.add("key", JsonValue.StringValue(entry.key.clone()))
                pair.add("value", entry.value.clone())
                frame.add(first.clone(), JsonValue.ObjectValue(pair))
            else:
                frame.add(first.clone(), JsonValue.StringValue(entry.key.clone()))
                frame.add(second.clone(), entry.value.clone())

            rows.append(frame)

    return rows

fn truthy(value: JsonValue) Bool:
    if value.is_null(): return false
    if let flag = value.as_bool(): return flag
    if let list = value.as_list(): return not list.is_empty()
    if let members = value.as_map(): return not members.is_empty()
    if let text = value.as_string(): return not text.is_empty()
    if let number = value.as_float(): return number != 0.0

    return true

fn to_text(value: JsonValue) String:
    if value.is_null(): return ""
    if let text = value.as_string(): return text
    if let flag = value.as_bool(): return if flag: "true" else: "false"
    if let found = number_text(value): return found

    return stringify(value: value).get("")

fn number_text(value: JsonValue) String?:
    match value:
        NumberValue(text): return text.clone()
        _: return none

fn equal(left: JsonValue, right: JsonValue) Bool:
    if let a = left.as_float():
        if let b = right.as_float(): return a == b

        return false

    return to_text(left) == to_text(right) and left.is_null() == right.is_null()

# -1, 0, 1 for numbers or strings of the same kind; 2 when the values cannot be ordered.
fn compare_values(left: JsonValue, right: JsonValue) Int:
    if let a = left.as_float():
        if let b = right.as_float(): return if a < b: -1 else if a > b: 1 else: 0

        return 2

    if let a = left.as_string():
        if let b = right.as_string(): return a.compare(b)
    return 2

fn text_value(text: String) JsonValue:
    return JsonValue.StringValue(text)

fn invalid(name: String, reason: String) TemplateError:
    return TemplateError.InvalidFilter(name: name, reason: reason)

fn arg_text(name: String, args: List[JsonValue], at: Int) String!TemplateError:
    if at >= args.length(): return error(invalid(name.clone(), "missing argument"))

    return ok(to_text(args[at]))

fn apply_filter(
    name: String,
    input: JsonValue,
    args: List[JsonValue]
) JsonValue!TemplateError:
    let text = to_text(input)
    if name == "upper": return ok(text_value(text.upper()))
    if name == "lower": return ok(text_value(text.lower()))
    if name == "trim": return ok(text_value(text.trim()))
    if name == "title": return ok(text_value(text.title()))
    if name == "escape": return ok(text_value(escape(text)))
    if name == "json": return ok(text_value(stringify(value: input).get("")))
    if name == "length": return ok(JsonValue.NumberValue("{length_of(input)}"))
    if name == "reverse": return reverse_value(input)
    if name == "first" or name == "last": return ok(end_of(input, name == "first"))
    if name == "keys": return ok(keys_of(input))

    if name == "join":
        let sep = try arg_text(name.clone(), args, 0)
        return ok(text_value(join_values(input, sep)))

    if name == "contains":
        if args.is_empty(): return error(invalid(name.clone(), "missing argument"))

        return ok(JsonValue.BoolValue(contains_value(input, args[0])))

    if name == "replace":
        let old = try arg_text(name.clone(), args, 0)
        let new = try arg_text(name.clone(), args, 1)
        return ok(text_value(if old.is_empty(): text else: text.replace(old, new)))

    if name == "truncate":
        let count = try arg_text(name.clone(), args, 0)
        let limit = count.parse_int()
        if not limit.is_some() or limit.get(0) < 0: return error(
            invalid(name.clone(), "needs a count")
        )

        let n = limit.get(0)
        return ok(text_value(if text.length() > n: "{text.take(n)}..." else: text))

    # `raw` and any other registered name pass through; unknown names fail at compile time.
    return ok(input.clone())

fn length_of(value: JsonValue) Int:
    if let list = value.as_list(): return list.length()
    if let members = value.as_map(): return members.length()

    return to_text(value).length()

fn reverse_value(value: JsonValue) JsonValue!TemplateError:
    if let list = value.as_list(): return ok(JsonValue.ArrayValue(list.reversed()))

    return ok(text_value(to_text(value).reverse()))

fn end_of(value: JsonValue, first: Bool) JsonValue:
    if let list = value.as_list():
        if list.is_empty(): return JsonValue.Null

        return list[if first: 0 else: list.length() - 1].clone()

    return JsonValue.Null

fn keys_of(value: JsonValue) JsonValue:
    var keys = List[JsonValue]()
    if let members = value.as_map():
        for key in members.keys():
            keys.append(JsonValue.StringValue(key.clone()))
    return JsonValue.ArrayValue(keys)

fn join_values(value: JsonValue, sep: String) String:
    var parts = List[String]()

    if let list = value.as_list():
        for item in list:
            parts.append(to_text(item))
        return parts.join(sep)

    return to_text(value)

fn contains_value(haystack: JsonValue, needle: JsonValue) Bool:
    if let list = haystack.as_list():
        for item in list:
            if equal(item, needle): return true
        return false

    if let members = haystack.as_map(): return members.contains(to_text(needle))

    return to_text(haystack).contains(to_text(needle))

impl Error for TemplateError:
    # Returns a template-prefixed diagnostic; it names the line, path or filter but never echoes values.
    fn message() String:
        match self:
            Syntax(line, reason): return "template: line {line}: {reason}"
            MissingValue(path): return "template: no value for {path}"
            InvalidFilter(name, reason): return "template: filter {name}: {reason}"
            UnknownPartial(name): return "template: unknown partial {name}"
            LimitExceeded: return "template: output limit exceeded"
            InvalidData: return "template: data is not JSON"

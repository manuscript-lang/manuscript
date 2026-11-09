import Data from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import StringBuilder from "@std/string.ms"
import WriteStream from "@std/io/io.ms"
import JsonValue, parse, stringify from "@std/data/json.ms"
import escape from "@std/data/html.ms"

/*
Text templates, written and run in Manuscript: compile once, render with `JsonValue` data.

    import compile, to_data from "@std/text/template.ms"
    let page = try compile("Hello \{\{ name | title \}\}!")
    let rendered = try page.render(try to_data(user))

Actions sit between `{{` and `}}`:

- `{{ user.name }}` prints a value; a path walks object members and list positions (`items.0`).
  Names resolve to loop variables first, then to members of the root object. A missing path is an
  error unless `strict: false`, or the value goes through `default`.
- `{{ name | upper | default("anonymous") }}` pipes a value through filters. Filters bind tighter than
  operators: `{{ if name | length > 3 }}`. Filters: `upper lower trim title length join(sep) json
  default(value) escape raw first last reverse keys contains(x) replace(old, new) truncate(n)`.
- `{{ if cond }}…{{ else if cond }}…{{ else }}…{{ end }}` with `== != < <= > >= and or not` and
  parentheses. Empty text, zero, null, false, and empty lists and objects are false; a missing path
  in a condition is false. Numbers compare by their exact JSON decimal value, without Float rounding.
- `{{ for item in items }}…{{ else }}…{{ end }}` loops a list (the `else` branch runs when it is empty).
  `for i, item in items` adds the position; for an object, `for key, value in object`; a single name over
  an object binds `{key, value}`. Inside a loop `loop.index`, `loop.first`, `loop.last` and `loop.length` exist.
- `{{ include "name" }}` renders a partial from the `partials` map passed to `render`, in the current scope.
- `{{# comment }}` prints nothing. `{{-` and `-}}` trim adjacent white space. `{{ "{{" }}` prints braces.

`compile(source, html: true)` escapes every printed value for HTML text and quoted attributes; end an
action with `| raw` to print trusted markup unchanged. Values come from data only: templates cannot
call functions or run code, and `max_output` bounds the result.
*/

// A parsed template expression: a literal, a path, a filter call or an operator. Internal to the engine; hidden from callers.
export opaque enum TemplateExpr:
    // A literal string, number, boolean or null written in the template.
    Literal(
        // The literal as a JSON value.
        value: JsonValue
    )
    // A dotted path whose first name is a loop variable or a root member.
    Path(
        // The names between the dots, in order.
        parts: List[String]
    )
    // A filter applied to its first argument; later arguments are the filter's own.
    Call(
        // The filter name, one of the documented filters.
        name: String,
        // The filtered value followed by the filter arguments.
        args: List[TemplateExpr]
    )
    // A comparison or logical operator over one or two operands.
    Op(
        // One of `and or not == != < <= > >=`.
        op: String,
        // The operands, in source order.
        args: List[TemplateExpr]
    )

// One `if` or `else if` arm of a conditional node. Internal to the engine.
export opaque type TemplateBranch:
    // Condition that selects this arm when true.
    cond: TemplateExpr
    // Nodes rendered when the condition holds.
    body: List[TemplateNode]

// A parsed template node: text, a printed value, a conditional, a loop or an include. Internal to the engine.
export opaque enum TemplateNode:
    // Literal text copied to the output.
    Text(
        // The text between actions, after trim markers.
        text: String
    )
    // A value printed to the output.
    Emit(
        // The expression whose value is printed.
        expr: TemplateExpr,
        // True when the printed text is HTML-escaped.
        escape: Bool
    )
    // A conditional with its arms and optional final branch.
    If(
        // Arms tried in order; the first true condition renders.
        branches: List[TemplateBranch],
        // Nodes rendered when no arm holds.
        otherwise: List[TemplateNode]
    )
    // A loop over a list or object.
    Each(
        // First loop name: the item, or the position or key when `second` is set.
        first: String,
        // Second loop name, or empty text for a single-name loop.
        second: String,
        // Expression that yields the list or object being walked.
        source: TemplateExpr,
        // Nodes rendered once per element.
        body: List[TemplateNode],
        // Nodes rendered when the collection is empty.
        otherwise: List[TemplateNode]
    )
    // Renders a named partial in the current scope.
    Include(
        // Expression that yields the partial's name.
        name: TemplateExpr
    )

// A compiled template; render it any number of times.
export opaque type Template:
    // The parsed nodes in source order.
    nodes: List[TemplateNode]
    // True when printed values are HTML-escaped by default.
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

// Builds a template error. Each message names the line, path, filter or partial but never echoes values.
fn syntax_error(line: Int, reason: String) Error:
    return Error(
        "template: line {line}: {reason}", kind: "EBADMSG", details: {"line": "{line}"}
    )

fn missing_value_error(path: String) Error:
    return Error(
        "template: no value for {path}", kind: "ENOENT", details: {"path": path}
    )

fn invalid_filter_error(name: String, reason: String) Error:
    return Error(
        "template: filter {name}: {reason}", kind: "EINVAL", details: {"filter": name}
    )

fn unknown_partial_error(name: String) Error:
    return Error(
        "template: unknown partial {name}", kind: "ENOENT", details: {"partial": name}
    )

// Compiles template source. With `html: true`, printed values are HTML-escaped unless they end in `| raw`.
export fn compile(source: String, html: Bool = false) Template!Error:
    let tokens = try tokenize(source)
    var builder = Builder(tokens: tokens, at: 0, html: html)
    let done = try builder.block(0)
    if done.end != "": return error(
        syntax_error(line: done.line, reason: "unexpected {done.end}")
    )

    return ok(Template(nodes: done.nodes, html: html))

// Compiles and renders in one call; use `compile` when rendering more than once.
export fn render(source: String, data: JsonValue, html: Bool = false) String!Error:
    let template = try compile(source, html: html)
    return template.render(data)

// Converts any `Data` value (records, lists, scalars) to the `JsonValue` a template reads.
export fn to_data[T: Data](value: T) JsonValue!Error:
    let text = stringify(value: value)
    if text.is_error(): return error(
        Error("template: data is not JSON", kind: "EBADMSG")
    )

    let parsed = parse(text.get())
    if parsed.is_error(): return error(
        Error("template: data is not JSON", kind: "EBADMSG")
    )

    return ok(parsed.get())

// Settings for `render` and `render_to`.
export type RenderOptions:
    // Templates that `include` can name.
    partials: Map[String, Template] = Map[String, Template]()
    // True fails a render on a missing printed path; false prints it as empty.
    strict: Bool = true
    // Maximum text length in bytes (default 16 MiB).
    max_output: Int = 16777216

impl Template:
    // Renders with `data` (an object supplies the root names) and the settings in `options`.
    fn render(data: JsonValue, options: RenderOptions = RenderOptions()) String!Error:
        var frames = List[Map[String, JsonValue]]()
        frames.append(root_names(data))

        var run = Run(
            out: StringBuilder(), written: 0, frames: frames,
            partials: options.partials.clone(), strict: options.strict,
            limit: options.max_output, html: self.html
        )
        try run.nodes(self.nodes.clone(), 0)
        return ok(run.out.build())

// Renders `template` as its `render` method does and writes the text to `output`, which the caller keeps and closes.
// A failed render writes nothing; a failed write returns the stream's error.
export fn render_to(
    template: Template,
    data: JsonValue,
    var output: WriteStream[String],
    options: RenderOptions = RenderOptions()
) Unit!Error:
    let text = try template.render(data, options)
    return output.write(text)

fn root_names(data: JsonValue) Map[String, JsonValue]:
    if let members = data.as_map(): return members

    return Map[String, JsonValue]()

// ---- lexing -------------------------------------------------------------------------------

fn count_lines(text: String) Int:
    return text.count("\n")

fn tokenize(source: String) List[Token]!Error:
    var tokens = List[Token]()

    // Splitting once keeps lexing linear: each piece starts right after an opening delimiter.
    let pieces = source.split("\{\{")
    var literal = pieces[0].clone()
    var index = 1
    var line = 1
    var trim_next = false

    while index < pieces.length():
        var text = literal.clone()
        if trim_next: text = text.trim_start()

        // An action ends at the first closing delimiter, even when its body holds a literal opener.
        var chunks = List[String]()
        var tail = ""
        var closed = false

        while index < pieces.length():
            let piece = pieces[index]
            index += 1

            let close = piece.index_of("\}\}")

            if close.is_some():
                chunks.append(piece.take(close.get(0)))
                tail = piece.drop(close.get(0) + 2)
                closed = true
                break

            chunks.append(piece.clone())

        if not closed: return error(
            syntax_error(
                line: line + count_lines(text), reason: "unterminated action"
            )
        )

        let raw = chunks.join("\{\{")
        var body = raw.clone()
        let action_line = line + count_lines(literal)
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
        line = action_line + count_lines(raw)
        literal = tail

    tokens.append(
        Token(
            action: false,
            body: if trim_next: literal.trim_start() else: literal.clone(), line: line
        )
    )
    return ok(tokens)

fn is_blank(c: String) Bool:
    return c == " " or c == "\t" or c == "\n" or c == "\r"

fn is_word_start(c: String) Bool:
    return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")

fn is_digit(c: String) Bool:
    return c >= "0" and c <= "9"

fn lex(text: String, line: Int) List[Tok]!Error:
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
                syntax_error(line: line, reason: "unterminated string")
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
            return error(syntax_error(line: line, reason: "unexpected character"))

    return ok(toks)

// ---- expression parsing --------------------------------------------------------------------

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

    fn fail(reason: String) Error:
        return syntax_error(line: self.line, reason: reason)

    var fn or_expr() TemplateExpr!Error:
        var left = try self.and_expr()

        while self.is_word("or"):
            self.at += 1

            let right = try self.and_expr()
            left = Op("or", [left, right])

        return ok(left)

    var fn and_expr() TemplateExpr!Error:
        var left = try self.not_expr()

        while self.is_word("and"):
            self.at += 1

            let right = try self.not_expr()
            left = Op("and", [left, right])

        return ok(left)

    var fn not_expr() TemplateExpr!Error:
        if self.is_word("not"):
            self.at += 1

            let inner = try self.not_expr()
            return ok(Op("not", [inner]))

        return self.compare()

    var fn compare() TemplateExpr!Error:
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

    var fn filtered() TemplateExpr!Error:
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

    var fn primary() TemplateExpr!Error:
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

fn parse_expr(text: String, line: Int) TemplateExpr!Error:
    let toks = try lex(text, line)
    var parser = ExprParser(toks: toks, at: 0, line: line)
    if parser.toks.is_empty(): return error(
        syntax_error(line: line, reason: "empty action")
    )

    let expr = try parser.or_expr()
    if parser.at < parser.toks.length(): return error(
        syntax_error(line: line, reason: "unexpected text after expression")
    )

    return ok(expr)

// ---- block parsing -------------------------------------------------------------------------

type BlockEnd:
    nodes: List[TemplateNode]
    // "" at end of input, otherwise "end", "else" or "else if".
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
    var fn block(depth: Int) BlockEnd!Error:
        var nodes = List[TemplateNode]()
        if depth > MAX_DEPTH: return error(
            syntax_error(line: 0, reason: "nested too deeply")
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

    fn emit(body: String, line: Int) TemplateNode!Error:
        var expr = try parse_expr(body, line)
        var escape_output = self.html
        let last = trailing_filter(expr)

        if last == "raw":
            escape_output = false
            expr = strip_filter(expr)
        else if last == "escape" and self.html:
            expr = strip_filter(expr)

        return ok(Emit(expr, escape_output))

    var fn conditional(cond: String, line: Int, depth: Int) TemplateNode!Error:
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
                    syntax_error(
                        line: done.line, reason: "if needs end"
                    )
                )

                otherwise = tail.nodes
                break

            return error(syntax_error(line: line, reason: "if needs end"))

        return ok(If(branches, otherwise))

    var fn for_block(header: String, line: Int, depth: Int) TemplateNode!Error:
        let at = header.index_of(" in ")
        if at.is_none(): return error(
            syntax_error(line: line, reason: "for needs `name in value`")
        )

        let names = header.take(at.get(0)).split(",")
        if names.length() > 2: return error(
            syntax_error(line: line, reason: "for takes one or two names")
        )

        let first = names[0].trim()
        let second = if names.length() == 2: names[1].trim() else: ""
        if first.is_empty() or not is_word_start(first.take(1)) or first.contains("."):
            return error(syntax_error(line: line, reason: "bad loop name"))
        if (
            names.length() == 2
            and (
                second.is_empty()
                or second.contains(".")
                or not is_word_start(second.take(1))
            )
        ):
            return error(syntax_error(line: line, reason: "bad loop name"))

        let source = try parse_expr(header.drop(at.get(0) + 4), line)
        let body = try self.block(depth + 1)
        var otherwise = List[TemplateNode]()

        if body.end == "else":
            let tail = try self.block(depth + 1)
            if tail.end != "end": return error(
                syntax_error(line: line, reason: "for needs end")
            )

            otherwise = tail.nodes
        else if body.end != "end":
            return error(syntax_error(line: line, reason: "for needs end"))

        return ok(Each(first, second, source, body.nodes, otherwise))

fn trailing_filter(expr: TemplateExpr) String:
    match expr:
        Call(name, _): return name.clone()
        _: return ""

fn strip_filter(expr: TemplateExpr) TemplateExpr:
    match expr:
        Call(_, args): return args[0].clone()
        _: return expr.clone()

// ---- rendering -----------------------------------------------------------------------------

type Run:
    out: StringBuilder
    written: Int
    frames: List[Map[String, JsonValue]]
    partials: Map[String, Template]
    strict: Bool
    limit: Int
    html: Bool

impl Run:
    var fn write(text: String) Unit!Error:
        self.written += text.byte_length()
        if self.written > self.limit: return error(
            Error("template: output limit exceeded", kind: "EOVERFLOW")
        )

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

        if current.is_none(): return none

        var value = current.get(JsonValue.Null)

        for k in 1..parts.length():
            let next = member(value, parts[k])
            if next.is_none(): return none

            value = next.get(JsonValue.Null)

        return value

    fn eval(expr: TemplateExpr, strict: Bool) JsonValue!Error:
        match expr:
            Literal(value): return ok(value.clone())
            Path(parts): return self.path_value(parts, strict)
            Call(name, args): return self.call(name, args, strict)
            Op(op, args): return self.operator(op, args)

    fn path_value(parts: List[String], strict: Bool) JsonValue!Error:
        if let found = self.lookup(parts): return ok(found)
        if strict: return error(missing_value_error(path: parts.join(".")))

        return ok(JsonValue.Null)

    fn operator(op: String, args: List[TemplateExpr]) JsonValue!Error:
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

    fn call(name: String, args: List[TemplateExpr], strict: Bool) JsonValue!Error:
        if name == "default":
            let input = try self.eval(args[0].clone(), false)
            if truthy(input): return ok(input)
            if args.length() != 2: return error(
                invalid_filter_error(
                    name: name, reason: "needs one argument"
                )
            )

            return self.eval(args[1].clone(), strict)

        let input = try self.eval(args[0].clone(), strict)
        var values = List[JsonValue]()
        for i in 1..args.length():
            values.append(try self.eval(args[i].clone(), strict))
        return apply_filter(name, input, values)

    var fn nodes(items: List[TemplateNode], depth: Int) Unit!Error:
        for node in items:
            try self.node(node, depth)
        return ok(unit)

    var fn node(node: TemplateNode, depth: Int) Unit!Error:
        match node:
            Text(text): return self.write(text)
            Emit(expr, escape_output): return self.emit(expr, escape_output)
            If(branches, otherwise): return self.branch(branches, otherwise, depth)
            Each(first, second, source, body, otherwise): return self.each(
                first, second, source, body, otherwise, depth
            )
            Include(name): return self.include(name, depth)

    var fn emit(expr: TemplateExpr, escape_output: Bool) Unit!Error:
        let value = try self.eval(expr, self.strict)
        let text = to_text(value)
        if escape_output: return self.write(escape(text))

        return self.write(text)

    var fn branch(
        branches: List[TemplateBranch],
        otherwise: List[TemplateNode],
        depth: Int
    ) Unit!Error:
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
    ) Unit!Error:
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

    var fn include(name: TemplateExpr, depth: Int) Unit!Error:
        let key = to_text(try self.eval(name, true))
        if depth > MAX_DEPTH: return error(unknown_partial_error(name: key))

        let partial = self.partials.get(key).clone()
        if partial.is_none(): return error(unknown_partial_error(name: key))

        return self.nodes(
            partial.get(
                Template(nodes: List[TemplateNode](), html: false)
            ).nodes.clone(),
            depth + 1
        )

// ---- values --------------------------------------------------------------------------------

fn member(value: JsonValue, key: String) JsonValue?:
    if let found = value.get(key): return found
    if let index = key.parse_int():
        return value.at(index).clone()

    return none

fn loop_info(index: Int, length: Int) JsonValue:
    var fields = Map[String, JsonValue]()
    fields.add("index", JsonValue.NumberValue("{index}"))
    fields.add("first", JsonValue.BoolValue(index == 0))
    fields.add("last", JsonValue.BoolValue(index == length - 1))
    fields.add("length", JsonValue.NumberValue("{length}"))
    return JsonValue.ObjectValue(fields)

// One variable frame per iteration: the list item, or an object's key and value.
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

// Keep validated coefficient bytes and a small decimal-order offset. Only
// exponent-bearing comparisons need arbitrary signed decimal-order arithmetic.
type ExactNumber:
    negative: Bool
    coefficient: Bytes
    first: Int
    end: Int
    offset: Int
    exponent: String

fn unsigned_digits(text: String) String:
    let chars = text.chars()
    var first = 0
    while first < chars.length() and chars[first] == "0": first += 1
    return if first == chars.length(): "0" else: text.drop(first)

fn magnitude_compare(a: String, b: String) Int:
    if a.length() != b.length(): return if a.length() < b.length(): -1 else: 1

    return a.compare(b)

// Add or subtract unsigned decimal magnitudes. Subtraction requires a >= b.
fn magnitude_sum(a: String, b: String, subtract: Bool) String:
    let left = a.chars()
    let right = b.chars()
    var i = left.length() - 1
    var j = right.length() - 1
    var carry = 0
    var out = StringBuilder()

    while i >= 0 or j >= 0:
        let x = if i >= 0: left[i].parse_int().get(0) else: 0
        let y = if j >= 0: right[j].parse_int().get(0) else: 0
        var digit = x + (if subtract: -y else: y) + carry
        carry = 0

        if digit < 0:
            digit += 10
            carry = -1
        else if digit >= 10:
            digit -= 10
            carry = 1

        out.append("{digit}")
        i -= 1
        j -= 1

    if carry > 0: out.append("1")
    return unsigned_digits(out.build().reverse())

fn decimal_order(exponent: String, offset: Int) String:
    if exponent == "0": return "{offset}"

    let negative = exponent.starts_with("-")
    let magnitude = unsigned_digits(
        if negative or exponent.starts_with("+"): exponent.drop(
            1
        ) else: exponent.clone()
    )
    let delta_text = "{offset}"
    let delta = if offset < 0: delta_text.drop(1) else: delta_text.clone()
    var result = ""
    var result_negative = negative

    if negative == (offset < 0):
        result = magnitude_sum(magnitude, delta, false)
    else if magnitude_compare(magnitude, delta) >= 0:
        result = magnitude_sum(magnitude, delta, true)
    else:
        result = magnitude_sum(delta, magnitude, true)
        result_negative = offset < 0

    return if result_negative and result != "0": "-{result}" else: result

fn order_compare(a: String, b: String) Int:
    let an = a.starts_with("-")
    let bn = b.starts_with("-")
    if an != bn: return if an: -1 else: 1

    let comparison = magnitude_compare(
        if an: a.drop(1) else: a.clone(), if bn: b.drop(1) else: b.clone()
    )
    return if an: -comparison else: comparison

fn number_digit(byte: UInt8) Bool:
    return byte >= 48 and byte <= 57

fn exact_number(text: String) ExactNumber?:
    // Validate a JSON number while locating its coefficient and exponent. Raw
    // NumberValue constructors need not have passed through the JSON parser.
    let chars = text.to_bytes()
    if chars.is_empty(): return none

    let negative = chars.get(0) == 45
    var at = if negative: 1 else: 0
    if at == chars.length(): return none

    let start = at

    if chars.get(at) == 48:
        at += 1
    else:
        if chars.get(at) < 49 or chars.get(at) > 57: return none

        while at < chars.length() and number_digit(chars.get(at)): at += 1

    let before_point = at - start

    if at < chars.length() and chars.get(at) == 46:
        at += 1

        let fraction_start = at
        while at < chars.length() and number_digit(chars.get(at)): at += 1
        if at == fraction_start: return none

    let coefficient_end = at
    var exponent = "0"

    if at < chars.length():
        if chars.get(at) != 101 and chars.get(at) != 69: return none

        at += 1

        let exponent_start = at
        if at < chars.length() and (chars.get(at) == 43 or chars.get(at) == 45): at += 1

        let digits_start = at
        while at < chars.length() and number_digit(chars.get(at)): at += 1
        if at == digits_start or at != chars.length(): return none

        exponent = text.drop(exponent_start)

    var first = start
    var leading_zeros = 0

    while first < coefficient_end:
        let byte = chars.get(first)
        if byte != 48 and byte != 46: break

        if byte == 48: leading_zeros += 1
        first += 1

    return ExactNumber(
        negative: negative and first != coefficient_end, coefficient: chars,
        first: first, end: coefficient_end, offset: before_point - leading_zeros,
        exponent: exponent
    )

fn number_compare(a: ExactNumber, b: ExactNumber) Int:
    if a.negative != b.negative: return if a.negative: -1 else: 1

    let az = a.first == a.end
    let bz = b.first == b.end
    if az or bz:
        return if az == bz: 0 else if az: -1 else: 1

    var order = 0

    if a.exponent == "0" and b.exponent == "0":
        order = if a.offset < b.offset: -1 else if a.offset > b.offset: 1 else: 0
    else:
        order = order_compare(
            decimal_order(a.exponent, a.offset), decimal_order(b.exponent, b.offset)
        )

    if order == 0: order = coefficient_compare(a, b)
    return if a.negative: -order else: order

// Most unequal coefficients differ immediately. For a shared prefix, use the
// native string comparison instead of inspecting every byte in Manuscript.
fn coefficient_compare(a: ExactNumber, b: ExactNumber) Int:
    let x = a.coefficient.get(a.first)
    let y = b.coefficient.get(b.first)
    if x != y: return if x < y: -1 else: 1

    return coefficient_text(a).compare(coefficient_text(b))

fn coefficient_text(number: ExactNumber) String:
    var end = number.end

    while end > number.first + 1:
        let last = number.coefficient.get(end - 1)
        if last != 48 and last != 46: break

        end -= 1

    // The lexical scan already validated ASCII; these byte ranges are UTF-8.
    return number.coefficient.decode_utf8_range(number.first, end).get("").replace(
        ".", ""
    )

// Common integer tokens compare directly without losing precision. Noncanonical
// or out-of-range text continues through the general exact-number path.
fn exact_integer(text: String) Int?:
    if let integer = text.parse_int():
        if text == "{integer}" or text == "-0": return integer
    return none

fn truthy(value: JsonValue) Bool:
    if value.is_null(): return false
    if let flag = value.as_bool(): return flag
    if let list = value.as_list(): return not list.is_empty()
    if let members = value.as_map(): return not members.is_empty()
    if let text = value.as_string(): return not text.is_empty()

    if let text = number_text(value):
        if let integer = exact_integer(text): return integer != 0
        if let number = exact_number(text): return number.first != number.end

    return true

fn to_text(value: JsonValue) String:
    if value.is_null(): return ""
    if let text = value.as_string(): return text
    if let flag = value.as_bool(): return if flag: "true" else: "false"
    if let found = number_text(value): return found.clone()

    return stringify(value: value).get("")

fn number_text(value: JsonValue) String?:
    match value:
        NumberValue(text): return text
        _: return none

// 0 null, 1 bool, 2 number, 3 string, 4 list, 5 object: values of different kinds are never equal.
fn kind_of(value: JsonValue) Int:
    if value.is_null(): return 0
    if value.as_bool().is_some(): return 1
    if number_text(value).is_some(): return 2
    if value.as_string().is_some(): return 3
    if value.as_list().is_some(): return 4

    return 5

fn equal(left: JsonValue, right: JsonValue) Bool:
    if kind_of(left) != kind_of(right): return false
    if number_text(left).is_some(): return compare_values(left, right) == 0

    return to_text(left) == to_text(right) and left.is_null() == right.is_null()

// -1, 0, 1 for numbers or strings of the same kind; 2 when the values cannot be ordered.
fn compare_values(left: JsonValue, right: JsonValue) Int:
    if let text = number_text(left):
        let other = number_text(right)
        if other.is_none(): return 2

        let right_text = other.get("")
        if let integer = exact_integer(text):
            if let other_integer = exact_integer(right_text):
                return if integer < other_integer: -1 else if integer > other_integer: 1 else: 0

        let a = exact_number(text)
        if a.is_none(): return 2

        let b = exact_number(right_text)
        if b.is_none(): return 2

        return number_compare(a.get(), b.get())

    if let a = left.as_string():
        if let b = right.as_string(): return a.compare(b)
    return 2

fn text_value(text: String) JsonValue:
    return JsonValue.StringValue(text)

fn invalid(name: String, reason: String) Error:
    return invalid_filter_error(name: name, reason: reason)

fn arg_text(name: String, args: List[JsonValue], at: Int) String!Error:
    if at >= args.length(): return error(invalid(name.clone(), "missing argument"))

    return ok(to_text(args[at]))

fn apply_filter(name: String, input: JsonValue, args: List[JsonValue]) JsonValue!Error:
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
        if limit.is_none() or limit.get(0) < 0: return error(
            invalid(name.clone(), "needs a count")
        )

        let n = limit.get(0)
        return ok(text_value(if text.length() > n: "{text.take(n)}..." else: text))

    // `raw` and any other registered name pass through; unknown names fail at compile time.
    return ok(input.clone())

fn length_of(value: JsonValue) Int:
    if let list = value.as_list(): return list.length()
    if let members = value.as_map(): return members.length()

    return to_text(value).length()

fn reverse_value(value: JsonValue) JsonValue!Error:
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

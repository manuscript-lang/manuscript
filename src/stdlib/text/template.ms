import (
	Bytes from "@std/bytes.ms",
	Data from "@std/core.ms",
	escape from "@std/data/html.ms",
	JsonValue, parse, stringify from "@std/data/json.ms",
	WriteStream from "@std/io/io.ms",
)

/*
Text templates: compile a template once, then render it with `JsonValue` data.

<!-- manuscript-example: {"mode":"fragment","given":["user JsonValue"]} -->
```manuscript
import JsonValue from "@std/data/json.ms"
import compile, to_data from "@std/text/template.ms"

page := compile("Hello {{ name | title }}!")?
rendered := page.render(to_data(user)?)?
print(rendered)
```

Actions sit between `{{` and `}}`:

- `{{ user.name }}` prints a value. A path walks object members and list positions (`items.0`).
  Names resolve to loop variables first, then to members of the root object. A missing path is an
  error, unless `RenderOptions(strict: false)` is set or the value goes through `default`.
- `{{ name | upper | default("anonymous") }}` pipes a value through filters. Filters bind tighter than
  operators, as in `{{ if name | length > 3 }}`. The filters are `upper`, `lower`, `trim`, `title`,
  `length`, `join(sep)`, `json`, `default(value)`, `escape`, `raw`, `first`, `last`, `reverse`, `keys`,
  `contains(x)`, `replace(old, new)` and `truncate(n)`.
  `length` counts list items, object members or the UTF-8 bytes of text.
  `truncate(n)` keeps at most `n` bytes without splitting a character, adds `...` when it cuts, and rejects a negative `n`.
- `{{ if cond }}…{{ else if cond }}…{{ else }}…{{ end }}` accepts `== != < <= > >= and or not` and
  parentheses. Empty text, zero, null, false, and empty lists and objects are false. A missing path
  in a condition is false. Numbers compare by their exact JSON decimal value, without Float rounding.
- `{{ for item in items }}…{{ else }}…{{ end }}` loops over a list; the `else` branch runs when it is empty.
  `for i, item in items` adds the position. For an object, write `for key, value in object`; a single name over
  an object binds `{key, value}`. Inside a loop, `loop.index`, `loop.first`, `loop.last` and `loop.length` are available.
- `{{ include "name" }}` renders a partial from the `partials` map in `RenderOptions`, in the current scope.
  Partials may nest 64 deep; a partial that includes itself fails with `EOVERFLOW`.
- `{{# comment }}` prints nothing. `{{-` and `-}}` trim adjacent white space. `{{ "{{" }}` prints braces.

`compile(source, html: true)` escapes every printed value for HTML text and quoted attributes. End an
action with `| raw` to print trusted markup unchanged. Values come from data only: templates cannot
call functions or run code. `max_output` bounds the size of the result.
*/

// A parsed template expression: a literal, a path, a filter call or an operator.
// Internal to the engine; hidden from callers.
export opaque enum TemplateExpr:
	// A literal string, number, boolean or null written in the template.
	Literal(
		// The literal as a JSON value.
		value JsonValue
	)
	// A dotted path whose first name is a loop variable or a root member.
	Path(
		// The names between the dots, in order.
		parts List[String]
	)
	// A filter applied to its first argument; later arguments are the filter's own.
	Call(
		// The filter name, one of the documented filters.
		name String,
		// The filtered value followed by the filter arguments.
		args List[TemplateExpr]
	)
	// A comparison or logical operator over one or two operands.
	Op(
		// One of `and or not == != < <= > >=`.
		op String,
		// The operands, in source order.
		args List[TemplateExpr]
	)

// One `if` or `else if` arm of a conditional node. Internal to the engine.
export opaque type TemplateBranch:
	// Condition that selects this arm when true.
	cond TemplateExpr
	// Nodes rendered when the condition holds.
	body List[TemplateNode]

// A parsed template node: text, a printed value, a conditional, a loop or an include.
// Internal to the engine.
export opaque enum TemplateNode:
	// Literal text copied to the output.
	Text(
		// The text between actions, after trim markers.
		text String
	)
	// A value printed to the output.
	Emit(
		// The expression whose value is printed.
		expr TemplateExpr,
		// True when the printed text is HTML-escaped.
		escape Bool
	)
	// A conditional with its arms and optional final branch.
	If(
		// Arms tried in order; the first true condition renders.
		branches List[TemplateBranch],
		// Nodes rendered when no arm holds.
		otherwise List[TemplateNode]
	)
	// A loop over a list or object.
	Each(
		// First loop name: the item, or the position or key when `second` is set.
		first String,
		// Second loop name, or empty text for a single-name loop.
		second String,
		// Expression that yields the list or object being walked.
		source TemplateExpr,
		// Nodes rendered once per element.
		body List[TemplateNode],
		// Nodes rendered when the collection is empty.
		otherwise List[TemplateNode]
	)
	// Renders a named partial in the current scope.
	Include(
		// Expression that yields the partial's name.
		name TemplateExpr
	)

// A compiled template; render it any number of times.
export opaque type Template:
	// The parsed nodes in source order.
	nodes List[TemplateNode]
	// True when printed values are HTML-escaped by default.
	html Bool

// Renders the template with `data` and the settings in `options`. When `data` is an
// object, its members supply the root names.
fn Template.render(data JsonValue, options RenderOptions = RenderOptions()) String!Error:
	var frames = List[Map[String, JsonValue]]()
	frames.append(root_names(data))

	var run = Run(
		out: "",
		written: 0,
		frames: frames,
		partials: options.partials.clone(),
		strict: options.strict,
		limit: options.max_output,
		html: self.html,
	)
	run.nodes(self.nodes, 0)?
	return ok(run.out)

type Token:
	action Bool
	body String
	line Int

type Tok:
	kind String
	text String

FILTERS := [
	"upper", "lower", "trim", "title", "length", "join", "json", "default", "escape",
	"raw", "first", "last", "reverse", "keys", "contains", "replace", "truncate"
]
MAX_DEPTH := 64

// Compiles template source. With `html: true`, printed values are HTML-escaped unless
// the action ends in `| raw`.
export fn compile(source String, html Bool = false) Template!Error:
	tokens := tokenize(source)?
	var builder = Builder(tokens: tokens, at: 0, html: html)
	done := builder.block(0)?
	if done.end != "": return error(
		syntax_error(line: done.line, reason: f"unexpected {done.end}")
	)

	return ok(Template(nodes: done.nodes, html: html))

// Compiles and renders in one call, with default `RenderOptions`. Use `compile` when
// rendering more than once.
export fn render(source String, data JsonValue, html Bool = false) String!Error:
	template := compile(source, html: html)?
	return template.render(data)

// Converts any `Data` value (records, lists, scalars) to the `JsonValue` that a
// template reads.
export fn to_data[T Data](value T) JsonValue!Error:
	text := stringify(value: value)
	if text.is_error(): return error(
		Error("template: data is not JSON", kind: "EBADMSG")
	)

	parsed := parse(text.get())
	if parsed.is_error(): return error(
		Error("template: data is not JSON", kind: "EBADMSG")
	)

	return ok(parsed.get())

// Settings for `Template.render` and `render_to`.
export type RenderOptions:
	// Templates that `include` can name.
	partials Map[String, Template] = Map[String, Template]()
	// When true, a missing printed path fails the render; when false, it prints as
	// empty.
	strict Bool = true
	// Maximum text length in bytes (default 16 MiB).
	max_output Int = 16777216

// Renders `template` as its `render` method does and writes the text to `output`. The
// caller keeps `output` and closes it. A failed render writes nothing; a failed write
// returns the stream's error.
export fn render_to(
	template Template,
	data JsonValue,
	var output WriteStream[String],
	options RenderOptions = RenderOptions(),
) Void!Error:
	text := template.render(data, options)?
	return output.write(text)

fn root_names(data JsonValue) Map[String, JsonValue]:
	members := data.as_map()
	if members != null: return members

	return Map[String, JsonValue]()

// ---- lexing -------------------------------------------------------------------------------

fn count_lines(text String) Int:
	return text.count("\n")

fn tokenize(source String) List[Token]!Error:
	var tokens = List[Token]()

	// Splitting once keeps lexing linear: each piece starts right after an opening
	// delimiter.
	pieces := source.split("{{")
	var literal = pieces[0].clone()
	var index = 1
	var line = 1
	var trim_next = false

	while index < pieces.length():
		var text = literal.clone()
		if trim_next: text = text.trim_start()

		// An action ends at the first closing delimiter, even when its body holds a
		// literal opener.
		var chunks = List[String]()
		var tail = ""
		var closed = false

		while index < pieces.length():
			piece := pieces[index]
			index += 1

			close := piece.index_of("}}")

			if close != null:
				chunks.append(piece.view(0, close).clone())
				tail = piece.view((close) + 2, piece.length()).clone()
				closed = true
				break

			chunks.append(piece.clone())

		if not closed: return error(
			syntax_error(
				line: line + count_lines(text),
				reason: "unterminated action",
			)
		)

		raw := chunks.join("{{")
		var body = raw.clone()
		action_line := line + count_lines(literal)
		trim_next = false

		if body.starts_with("-") and (body.length() == 1 or is_blank_at(body, 1)):
			text = text.trim_end()
			body = body.view(1, body.length()).clone()

		if (
			body.ends_with("-")
			and (body.length() == 1 or is_blank_at(body, body.length() - 2))
		):
			trim_next = true
			body = body.view(0, body.length() - 1).clone()

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
			body: if trim_next: literal.trim_start() else: literal.clone(),
			line: line,
		)
	)
	return ok(tokens)

// Whether the scalar that starts at byte `at` is a space, tab or line break.
fn is_blank_at(text String, at Int) Bool:
	code := text.scalar_at(at, -1)
	return code == 32 or code == 9 or code == 10 or code == 13

fn is_blank(c String) Bool:
	return c == " " or c == "\t" or c == "\n" or c == "\r"

fn is_word_start(c String) Bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")

fn is_digit(c String) Bool:
	return c >= "0" and c <= "9"

fn lex(text String, line Int) List[Tok]!Error:
	var toks = List[Tok]()
	chars := text.chars()
	var i = 0

	while i < chars.length():
		c := chars[i]
		two := if i + 1 < chars.length(): f"{c}{chars[i + 1]}" else: c.clone()

		if is_blank(c):
			i += 1
		else if two == "==" or two == "!=" or two == "<=" or two == ">=":
			toks.append(Tok(kind: "sym", text: two))
			i += 2
		else if c == "(" or c == ")" or c == "," or c == "|" or c == "<" or c == ">":
			toks.append(Tok(kind: "sym", text: c.clone()))
			i += 1
		else if c == "\"":
			var out = ""
			i += 1

			var closed = false

			while i < chars.length():
				if chars[i] == "\"":
					closed = true
					i += 1
					break

				if chars[i] == "\\" and i + 1 < chars.length():
					e := chars[i + 1]
					out += if e == "n": "\n" else if e == "t": "\t" else: e.clone()
					i += 2
				else:
					out += chars[i]
					i += 1

			if not closed: return error(
				syntax_error(line: line, reason: "unterminated string")
			)

			toks.append(Tok(kind: "str", text: out))
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
				out = f"{out}{chars[i]}"
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
				out = f"{out}{chars[i]}"
				i += 1

			toks.append(Tok(kind: "word", text: out))
		else:
			return error(syntax_error(line: line, reason: "unexpected character"))

	return ok(toks)

// ---- expression parsing --------------------------------------------------------------------

type ExprParser:
	toks List[Tok]
	at Int
	line Int

fn ExprParser.peek() Tok:
	return self.toks.get_or(self.at, Tok(kind: "end", text: ""))

fn ExprParser.is_sym(text String) Bool:
	t := self.peek()
	return t.kind == "sym" and t.text == text

fn ExprParser.is_word(text String) Bool:
	t := self.peek()
	return t.kind == "word" and t.text == text

fn ExprParser.fail(reason String) Error:
	return syntax_error(line: self.line, reason: reason)

fn var ExprParser.or_expr() TemplateExpr!Error:
	var left = self.and_expr()?

	while self.is_word("or"):
		self.at += 1

		right := self.and_expr()?
		left = Op("or", [left, right])

	return ok(left)

fn var ExprParser.and_expr() TemplateExpr!Error:
	var left = self.not_expr()?

	while self.is_word("and"):
		self.at += 1

		right := self.not_expr()?
		left = Op("and", [left, right])

	return ok(left)

fn var ExprParser.not_expr() TemplateExpr!Error:
	if self.is_word("not"):
		self.at += 1

		inner := self.not_expr()?
		return ok(Op("not", [inner]))

	return self.compare()

fn var ExprParser.compare() TemplateExpr!Error:
	left := self.filtered()?
	t := self.peek().clone()
	is_cmp := (t.kind == "sym" and ["==", "!=", "<", "<=", ">", ">="].contains(t.text))
	if not is_cmp: return ok(left)

	self.at += 1

	right := self.filtered()?
	return ok(Op(t.text.clone(), [left, right]))

fn var ExprParser.filtered() TemplateExpr!Error:
	var value = self.primary()?

	while self.is_sym("|"):
		self.at += 1

		name := self.peek().clone()
		if name.kind != "word" or not FILTERS.contains(name.text): return error(
			self.fail("unknown filter")
		)

		self.at += 1

		var args = [value]

		if self.is_sym("("):
			self.at += 1

			while not self.is_sym(")"):
				args.append(self.or_expr()?)

				if self.is_sym(","): self.at += 1
				else if not self.is_sym(")"): return error(self.fail("expected , or )"))

			self.at += 1

		value = Call(name.text.clone(), args)

	return ok(value)

fn var ExprParser.primary() TemplateExpr!Error:
	t := self.peek().clone()
	self.at += 1
	if t.kind == "str": return ok(Literal(JsonValue.StringValue(t.text.clone())))
	if t.kind == "num": return ok(Literal(JsonValue.NumberValue(t.text.clone())))

	if t.kind == "sym" and t.text == "(":
		inner := self.or_expr()?
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

		return ok(Path(t.text.split(".").clone()))

	return error(self.fail("expected a value"))

fn parse_expr(text String, line Int) TemplateExpr!Error:
	toks := lex(text, line)?
	var parser = ExprParser(toks: toks, at: 0, line: line)
	if parser.toks.is_empty(): return error(
		syntax_error(line: line, reason: "empty action")
	)

	expr := parser.or_expr()?
	if parser.at < parser.toks.length(): return error(
		syntax_error(line: line, reason: "unexpected text after expression")
	)

	return ok(expr)

// ---- block parsing -------------------------------------------------------------------------

type BlockEnd:
	nodes List[TemplateNode]
	// "" at end of input, otherwise "end", "else" or "else if".
	end String
	cond String
	line Int

type Builder:
	tokens List[Token]
	at Int
	html Bool

fn var Builder.block(depth Int) BlockEnd!Error:
	var nodes = List[TemplateNode]()
	if depth > MAX_DEPTH: return error(
		syntax_error(line: 0, reason: "nested too deeply")
	)

	while self.at < self.tokens.length():
		token := self.tokens[self.at].clone()
		self.at += 1

		if not token.action:
			nodes.append(Text(token.body.clone()))
			continue

		word := first_word(token.body)
		rest := after_word(token.body)
		if word == "end":
			return ok(BlockEnd(nodes: nodes, end: "end", cond: "", line: token.line))

		if word == "else":
			if first_word(rest) == "if":
				return ok(
					BlockEnd(
						nodes: nodes,
						end: "else if",
						cond: after_word(rest),
						line: token.line,
					)
				)
			return ok(BlockEnd(nodes: nodes, end: "else", cond: "", line: token.line))

		if word == "if":
			nodes.append(self.conditional(rest, token.line, depth)?)
		else if word == "for":
			nodes.append(self.for_block(rest, token.line, depth)?)
		else if word == "include":
			nodes.append(Include(parse_expr(rest, token.line)?))
		else:
			nodes.append(self.emit(token.body, token.line)?)

	return ok(BlockEnd(nodes: nodes, end: "", cond: "", line: 0))

fn Builder.emit(body String, line Int) TemplateNode!Error:
	var expr = parse_expr(body, line)?
	var escape_output = self.html
	last := trailing_filter(expr)

	if last == "raw":
		escape_output = false
		expr = strip_filter(expr)
	else if last == "escape" and self.html:
		expr = strip_filter(expr)

	return ok(Emit(expr, escape_output))

fn var Builder.conditional(cond String, line Int, depth Int) TemplateNode!Error:
	var branches = List[TemplateBranch]()
	var otherwise = List[TemplateNode]()
	var guard = parse_expr(cond, line)?

	while true:
		done := self.block(depth + 1)?
		branches.append(TemplateBranch(cond: guard, body: done.nodes.clone()))
		if done.end == "end": break

		if done.end == "else if":
			guard = parse_expr(done.cond, done.line)?
			continue

		if done.end == "else":
			tail := self.block(depth + 1)?
			if tail.end != "end": return error(
				syntax_error(line: done.line, reason: "if needs end")
			)

			otherwise = tail.nodes
			break

		return error(syntax_error(line: line, reason: "if needs end"))

	return ok(If(branches, otherwise))

fn var Builder.for_block(header String, line Int, depth Int) TemplateNode!Error:
	at := header.index_of(" in ")
	if at == null: return error(
		syntax_error(line: line, reason: "for needs `name in value`")
	)

	names := header.view(0, at).split(",")
	if names.length() > 2: return error(
		syntax_error(line: line, reason: "for takes one or two names")
	)

	first := names[0].trim()
	second := if names.length() == 2: names[1].trim() else: ""
	if first.is_empty() or not is_word_start(first.chars()[0]) or first.contains("."):
		return error(syntax_error(line: line, reason: "bad loop name"))
	if (
		names.length() == 2
		and (
			second.is_empty()
			or second.contains(".")
			or not is_word_start(second.view(0, 1))
		)
	):
		return error(syntax_error(line: line, reason: "bad loop name"))

	source := parse_expr(header.view((at) + 4, header.length()), line)?
	body := self.block(depth + 1)?
	var otherwise = List[TemplateNode]()

	if body.end == "else":
		tail := self.block(depth + 1)?
		if tail.end != "end": return error(
			syntax_error(line: line, reason: "for needs end")
		)

		otherwise = tail.nodes
	else if body.end != "end":
		return error(syntax_error(line: line, reason: "for needs end"))

	return ok(Each(first, second, source, body.nodes, otherwise))

fn first_word(body String) String:
	return body.split(" ")[0].trim()

fn after_word(body String) String:
	return body.view(first_word(body).length(), body.length()).trim().clone()

fn trailing_filter(expr TemplateExpr) String:
	match expr:
		Call(name, _): return name.clone()
		_: return ""

fn strip_filter(expr TemplateExpr) TemplateExpr:
	match expr:
		Call(_, args): return args[0].clone()
		_: return expr.clone()

// ---- rendering -----------------------------------------------------------------------------

type Run:
	out String
	written Int
	frames List[Map[String, JsonValue]]
	partials Map[String, Template]
	strict Bool
	limit Int
	html Bool

fn var Run.write(text String) Void!Error:
	self.written += text.length()
	if self.written > self.limit: return error(
		Error("template: output limit exceeded", kind: "EOVERFLOW")
	)

	self.out += text

fn Run.lookup(parts List[String]) JsonValue?:
	var i = self.frames.length() - 1

	while i >= 0:
		found := self.frames[i].get(parts[0])

		if found != null:
			if parts.length() == 1: return found.clone()
			return descend(found, parts)

		i -= 1

	return null

fn Run.eval(expr TemplateExpr, strict Bool) JsonValue!Error:
	match expr:
		Literal(value): return ok(value.clone())
		Path(parts): return self.path_value(parts, strict)
		Call(name, args): return self.call(name, args, strict)
		Op(op, args): return self.operator(op, args)

fn Run.path_value(parts List[String], strict Bool) JsonValue!Error:
	found := self.lookup(parts)
	if found != null: return ok(found)
	if strict: return error(missing_value_error(path: parts.join(".")))

	return ok(JsonValue.Null)

fn Run.operator(op String, args List[TemplateExpr]) JsonValue!Error:
	left := self.eval(args[0], false)?
	if op == "not": return ok(JsonValue.BoolValue(not truthy(left)))
	if op == "and" and not truthy(left): return ok(JsonValue.BoolValue(false))
	if op == "or" and truthy(left): return ok(JsonValue.BoolValue(true))

	right := self.eval(args[1], false)?
	if op == "and" or op == "or": return ok(JsonValue.BoolValue(truthy(right)))
	if op == "==": return ok(JsonValue.BoolValue(equal(left, right)))
	if op == "!=": return ok(JsonValue.BoolValue(not equal(left, right)))

	order := compare_values(left, right)
	if op == "<": return ok(JsonValue.BoolValue(order < 0))
	if op == "<=": return ok(JsonValue.BoolValue(order <= 0))
	if op == ">": return ok(JsonValue.BoolValue(order > 0 and order != 2))

	return ok(JsonValue.BoolValue(order >= 0 and order != 2))

fn Run.call(name String, args List[TemplateExpr], strict Bool) JsonValue!Error:
	if name == "default":
		input := self.eval(args[0], false)?
		if truthy(input): return ok(input)
		if args.length() != 2: return error(
			invalid_filter_error(
				name: name.clone(),
				reason: "needs one argument",
			)
		)

		return self.eval(args[1], strict)

	input := self.eval(args[0], strict)?
	var values = List[JsonValue]()
	for i in 1..args.length():
		values.append(self.eval(args[i], strict)?)
	return apply_filter(name.clone(), input, values)

fn var Run.nodes(items List[TemplateNode], depth Int) Void!Error:
	for node in items:
		self.node(node, depth)?

fn var Run.node(node TemplateNode, depth Int) Void!Error:
	match node:
		Text(text): return self.write(text)
		Emit(expr, escape_output): return self.emit(expr, escape_output)
		If(branches, otherwise): return self.branch(branches, otherwise, depth)
		Each(first, second, source, body, otherwise): return self.each(
			first,
			second,
			source,
			body,
			otherwise,
			depth,
		)
		Include(name): return self.include(name, depth)

fn var Run.emit(expr TemplateExpr, escape_output Bool) Void!Error:
	value := self.eval(expr, self.strict)?
	text := to_text(value)
	if escape_output: return self.write(escape(text))

	return self.write(text)

fn var Run.branch(
	branches List[TemplateBranch],
	otherwise List[TemplateNode],
	depth Int,
) Void!Error:
	for branch in branches:
		verdict := self.eval(branch.cond, false)?
		if truthy(verdict): return self.nodes(branch.body, depth + 1)

	return self.nodes(otherwise, depth + 1)

fn var Run.each(
	first String,
	second String,
	source TemplateExpr,
	body List[TemplateNode],
	otherwise List[TemplateNode],
	depth Int,
) Void!Error:
	collection := self.eval(source, false)?
	var keys List[String] = []
	var items = collection_items(collection, keys)
	count := items.length() + keys.length()
	if count == 0: return self.nodes(otherwise, depth + 1)

	for i in 0..count:
		var frame = Map[String, JsonValue]()
		bind_row(frame, collection, items, first, second, keys, i)
		frame.add("loop", loop_info(i, count))
		self.frames.append(frame)

		result := self.nodes(body, depth + 1)
		_frame := self.frames.remove(self.frames.length() - 1)
		if result.is_error(): return result

	return ok()

fn var Run.include(name TemplateExpr, depth Int) Void!Error:
	key := to_text(self.eval(name, true)?)
	if depth > MAX_DEPTH: return error(partial_depth_error(name: key))

	partial := self.partials.get(key).clone()
	if partial == null: return error(unknown_partial_error(name: key))

	return self.nodes((partial).nodes.clone(), depth + 1)

// ---- values --------------------------------------------------------------------------------

// Walks `parts[1..]` below `root`, copying only the member each step reaches, never the
// unused siblings.
fn descend(root JsonValue, parts List[String]) JsonValue?:
	first := member(root, parts[1])
	if first == null: return null

	var value = first

	for k in 2..parts.length():
		next := member(value, parts[k]).clone()
		if next == null: return null

		value = next

	return value

fn member(value JsonValue, key String) JsonValue?:
	found := value.get(key)
	if found != null: return found

	index := key.parse_int()
	if index != null: return value.get_index(index).clone()

	return null

fn loop_info(index Int, length Int) JsonValue:
	var fields = Map[String, JsonValue]()
	fields.add("index", JsonValue.NumberValue(f"{index}"))
	fields.add("first", JsonValue.BoolValue(index == 0))
	fields.add("last", JsonValue.BoolValue(index == length - 1))
	fields.add("length", JsonValue.NumberValue(f"{length}"))
	return JsonValue.ObjectValue(fields)

// The items of a list loop, last first so each can be moved out with `pop` instead of
// copied; for an object loop `keys` receives its keys in order and the result is empty.
fn collection_items(collection JsonValue, var keys List[String]) List[JsonValue]:
	found := collection.as_list()

	if found != null:
		var items = found
		items.reverse()
		return items

	members := collection.as_map()
	if members != null:
		for entry in members.entries(): keys.append(entry.key.clone())
	return List[JsonValue]()

// Binds the variables of iteration `i` into `frame`: the list item (moved out of
// `items`), or an object's key and value.
fn bind_row(
	var frame Map[String, JsonValue],
	collection JsonValue,
	var items List[JsonValue],
	first String,
	second String,
	keys List[String],
	i Int,
) Void:
	if keys.is_empty():
		item := items.pop() or JsonValue.Null

		if second.is_empty():
			frame.add(first.clone(), item)
		else:
			frame.add(first.clone(), JsonValue.NumberValue(f"{i}"))
			frame.add(second.clone(), item)
	else:
		value := (collection.get(keys[i]).clone() or JsonValue.Null).clone()

		if second.is_empty():
			var pair = Map[String, JsonValue]()
			pair.add("key", JsonValue.StringValue(keys[i].clone()))
			pair.add("value", value)
			frame.add(first.clone(), JsonValue.ObjectValue(pair))
		else:
			frame.add(first.clone(), JsonValue.StringValue(keys[i].clone()))
			frame.add(second.clone(), value)

// Keep validated coefficient bytes and a small decimal-order offset. Only
// exponent-bearing comparisons need arbitrary signed decimal-order arithmetic.
type ExactNumber:
	negative Bool
	coefficient Bytes
	first Int
	end Int
	offset Int
	exponent String

fn unsigned_digits(text String) String:
	chars := text.chars()
	var first = 0
	while first < chars.length() and chars[first] == "0": first += 1
	return if first == chars.length(): "0" else: text.view(first, text.length()).clone()

fn magnitude_compare(a String, b String) Int:
	if a.length() != b.length(): return if a.length() < b.length(): -1 else: 1
	return a.compare(b)

// Add or subtract unsigned decimal magnitudes. Subtraction requires a >= b.
fn magnitude_sum(a String, b String, subtract Bool) String:
	left := a.chars()
	right := b.chars()
	var i = left.length() - 1
	var j = right.length() - 1
	var carry = 0
	var out = ""

	while i >= 0 or j >= 0:
		x := if i >= 0: (left[i].parse_int() or 0) else: 0
		y := if j >= 0: (right[j].parse_int() or 0) else: 0
		var digit = x + (if subtract: -y else: y) + carry
		carry = 0

		if digit < 0:
			digit += 10
			carry = -1
		else if digit >= 10:
			digit -= 10
			carry = 1

		out += f"{digit}"
		i -= 1
		j -= 1

	if carry > 0: out += "1"
	return unsigned_digits(out.reverse())

fn decimal_order(exponent String, offset Int) String:
	if exponent == "0": return f"{offset}"

	negative := exponent.starts_with("-")
	magnitude := unsigned_digits(
		if negative or exponent.starts_with("+"): exponent.view(
			1,
			exponent.length(),
		).clone() else: exponent.clone()
	)
	delta_text := f"{offset}"
	delta := if offset < 0: delta_text.view(1, delta_text.length()).clone() else: delta_text.clone()
	var result = ""
	var result_negative = negative

	if negative == (offset < 0):
		result = magnitude_sum(magnitude, delta, false)
	else if magnitude_compare(magnitude, delta) >= 0:
		result = magnitude_sum(magnitude, delta, true)
	else:
		result = magnitude_sum(delta, magnitude, true)
		result_negative = offset < 0

	return if result_negative and result != "0": f"-{result}" else: result

fn order_compare(a String, b String) Int:
	an := a.starts_with("-")
	bn := b.starts_with("-")
	if an != bn: return if an: -1 else: 1

	comparison := magnitude_compare(
		if an: a.view(1, a.length()).clone() else: a.clone(),
		if bn: b.view(1, b.length()).clone() else: b.clone(),
	)
	return if an: -comparison else: comparison

fn number_digit(byte UInt8) Bool:
	return byte >= 48 and byte <= 57

fn exact_number(text String) ExactNumber?:
	// Validate a JSON number while locating its coefficient and exponent. Raw
	// NumberValue constructors need not have passed through the JSON parser.
	chars := text.to_bytes()
	if chars.is_empty(): return null

	negative := chars.get(0) == 45
	var at = if negative: 1 else: 0
	if at == chars.length(): return null

	start := at

	if chars.get(at) == 48:
		at += 1
	else:
		if chars.get(at) < 49 or chars.get(at) > 57: return null

		while at < chars.length() and number_digit(chars.get(at)): at += 1

	before_point := at - start

	if at < chars.length() and chars.get(at) == 46:
		at += 1

		fraction_start := at
		while at < chars.length() and number_digit(chars.get(at)): at += 1
		if at == fraction_start: return null

	coefficient_end := at
	var exponent = "0"

	if at < chars.length():
		if chars.get(at) != 101 and chars.get(at) != 69: return null

		at += 1

		exponent_start := at
		if at < chars.length() and (chars.get(at) == 43 or chars.get(at) == 45): at += 1

		digits_start := at
		while at < chars.length() and number_digit(chars.get(at)): at += 1
		if at == digits_start or at != chars.length(): return null

		exponent = text.view(exponent_start, text.length()).clone()

	var first = start
	var leading_zeros = 0

	while first < coefficient_end:
		byte := chars.get(first)
		if byte != 48 and byte != 46: break

		if byte == 48: leading_zeros += 1
		first += 1

	return ExactNumber(
		negative: negative and first != coefficient_end,
		coefficient: chars,
		first: first,
		end: coefficient_end,
		offset: before_point - leading_zeros,
		exponent: exponent,
	)

fn number_compare(a ExactNumber, b ExactNumber) Int:
	if a.negative != b.negative: return if a.negative: -1 else: 1

	az := a.first == a.end
	bz := b.first == b.end
	if az or bz: return if az == bz: 0 else if az: -1 else: 1

	var order = 0

	if a.exponent == "0" and b.exponent == "0":
		order = if a.offset < b.offset: -1 else if a.offset > b.offset: 1 else: 0
	else:
		order = order_compare(
			decimal_order(a.exponent, a.offset),
			decimal_order(b.exponent, b.offset),
		)

	if order == 0: order = coefficient_compare(a, b)
	return if a.negative: -order else: order

// Most unequal coefficients differ immediately. For a shared prefix, use the
// native string comparison instead of inspecting every byte in Manuscript.
fn coefficient_compare(a ExactNumber, b ExactNumber) Int:
	x := a.coefficient.get(a.first)
	y := b.coefficient.get(b.first)
	if x != y: return if x < y: -1 else: 1

	return coefficient_text(a).compare(coefficient_text(b))

fn coefficient_text(number ExactNumber) String:
	var end = number.end

	while end > number.first + 1:
		last := number.coefficient.get(end - 1)
		if last != 48 and last != 46: break

		end -= 1

	// The lexical scan already validated ASCII; these byte ranges are UTF-8.
	return (number.coefficient.decode_utf8_range(number.first, end) or "").replace(
		".",
		"",
	)

// Common integer tokens compare directly without losing precision. Noncanonical
// or out-of-range text continues through the general exact-number path.
fn exact_integer(text String) Int?:
	integer := text.parse_int()
	if integer != null:
		if text == f"{integer}" or text == "-0": return integer
	return null

fn truthy(value JsonValue) Bool:
	if value.is_null(): return false

	flag := value.as_bool()
	if flag != null: return flag

	list := value.as_list()
	if list != null: return not list.is_empty()

	members := value.as_map()
	if members != null: return not members.is_empty()

	text := value.as_string()
	if text != null: return not text.is_empty()

	text := number_text(value)

	if text != null:
		integer := exact_integer(text)
		if integer != null: return integer != 0

		number := exact_number(text)
		if number != null: return number.first != number.end

	return true

fn to_text(value JsonValue) String:
	if value.is_null(): return ""

	text := value.as_string()
	if text != null: return text

	flag := value.as_bool()
	if flag != null: return if flag: "true" else: "false"

	found := number_text(value)
	if found != null: return found.clone()

	return stringify(value: value).get_or("")

fn number_text(value JsonValue) String?:
	match value:
		NumberValue(text): return text
		_: return null

// 0 null, 1 bool, 2 number, 3 string, 4 list, 5 object: values of different kinds are
// never equal.
fn kind_of(value JsonValue) Int:
	if value.is_null(): return 0
	if value.as_bool() != null: return 1
	if number_text(value) != null: return 2
	if value.as_string() != null: return 3
	if value.as_list() != null: return 4

	return 5

fn equal(left JsonValue, right JsonValue) Bool:
	if kind_of(left) != kind_of(right): return false
	if number_text(left) != null: return compare_values(left, right) == 0

	return to_text(left) == to_text(right) and left.is_null() == right.is_null()

// -1, 0, 1 for numbers or strings of the same kind; 2 when the values cannot be ordered.
fn compare_values(left JsonValue, right JsonValue) Int:
	text := number_text(left)

	if text != null:
		other := number_text(right)
		if other == null: return 2

		right_text := other
		integer := exact_integer(text)

		if integer != null:
			other_integer := exact_integer(right_text)
			if other_integer != null:
				return if integer < other_integer: -1 else if integer > other_integer: 1 else: 0

		a := exact_number(text)
		b := exact_number(right_text)
		x := a

		if x != null:
			y := b
			if y != null: return number_compare(x, y)

		return 2

	a := left.as_string()

	if a != null:
		b := right.as_string()
		if b != null: return a.compare(b)

	return 2

fn text_value(text String) JsonValue:
	return JsonValue.StringValue(text.clone())

fn invalid(name String, reason String) Error:
	return invalid_filter_error(name: name, reason: reason)

fn arg_text(name String, args List[JsonValue], at Int) String!Error:
	if at >= args.length(): return error(invalid(name.clone(), "missing argument"))
	return ok(to_text(args[at]))

fn apply_filter(name String, input JsonValue, args List[JsonValue]) JsonValue!Error:
	text := to_text(input)
	if name == "upper": return ok(text_value(text.upper()))
	if name == "lower": return ok(text_value(text.lower()))
	if name == "trim": return ok(text_value(text.trim()))
	if name == "title": return ok(text_value(text.title()))
	if name == "escape": return ok(text_value(escape(text)))
	if name == "json": return ok(text_value(stringify(value: input).get_or("")))
	if name == "length": return ok(JsonValue.NumberValue(f"{length_of(input)}"))
	if name == "reverse": return reverse_value(input)
	if name == "first" or name == "last": return ok(end_of(input, name == "first"))
	if name == "keys": return ok(keys_of(input))

	if name == "join":
		sep := arg_text(name.clone(), args, 0)?
		return ok(text_value(join_values(input, sep)))

	if name == "contains":
		if args.is_empty(): return error(invalid(name.clone(), "missing argument"))
		return ok(JsonValue.BoolValue(contains_value(input, args[0])))

	if name == "replace":
		old := arg_text(name.clone(), args, 0)?
		new := arg_text(name.clone(), args, 1)?
		return ok(text_value(if old.is_empty(): text else: text.replace(old, new)))

	if name == "truncate":
		count := arg_text(name.clone(), args, 0)?
		limit := count.parse_int()
		if (limit == null) or (limit) < 0: return error(
			invalid(name.clone(), "needs a count")
		)

		return ok(text_value(truncated(text, limit)))

	// `raw` and any other registered name pass through; unknown names fail at compile time.
	return ok(input.clone())

// Keeps at most `limit` bytes of `text` and adds `...` when it cut anything. The cut
// backs up to the start of a scalar, so a multi-byte character is dropped whole.
fn truncated(text String, limit Int) String:
	if text.length() <= limit: return text.clone()

	raw := text.as_bytes()
	var end = limit
	while end > 0 and raw.get(end).to_int() >= 128 and raw.get(end).to_int() < 192:
		end -= 1
	return f"{text.view(0, end)}..."

fn length_of(value JsonValue) Int:
	list := value.as_list()
	if list != null: return list.length()

	members := value.as_map()
	if members != null: return members.length()

	return to_text(value).length()

fn reverse_value(value JsonValue) JsonValue!Error:
	list := value.as_list()
	if list != null: return ok(JsonValue.ArrayValue(list.reversed().clone()))

	return ok(text_value(to_text(value).reverse()))

fn end_of(value JsonValue, first Bool) JsonValue:
	list := value.as_list()

	if list != null:
		if list.is_empty(): return JsonValue.Null
		return list[if first: 0 else: list.length() - 1].clone()

	return JsonValue.Null

fn keys_of(value JsonValue) JsonValue:
	var keys = List[JsonValue]()
	members := value.as_map()
	if members != null:
		for key in members.keys():
			keys.append(JsonValue.StringValue(key.clone()))
	return JsonValue.ArrayValue(keys)

fn join_values(value JsonValue, sep String) String:
	var parts = List[String]()
	list := value.as_list()

	if list != null:
		for item in list:
			parts.append(to_text(item))
		return parts.join(sep)

	return to_text(value)

fn contains_value(haystack JsonValue, needle JsonValue) Bool:
	list := haystack.as_list()

	if list != null:
		for item in list:
			if equal(item, needle): return true
		return false

	members := haystack.as_map()
	if members != null: return members.contains(to_text(needle))

	return to_text(haystack).contains(to_text(needle))

// Builds a template error. Each message names the line, path, filter or partial but
// never echoes values.
fn syntax_error(line Int, reason String) Error:
	return Error(
		f"template: line {line}: {reason}",
		kind: "EBADMSG",
		details: {"line": f"{line}"},
	)

fn missing_value_error(path String) Error:
	return Error(
		f"template: no value for {path}",
		kind: "ENOENT",
		details: {"path": path.clone()},
	)

fn invalid_filter_error(name String, reason String) Error:
	return Error(
		f"template: filter {name}: {reason}",
		kind: "EINVAL",
		details: {"filter": name.clone()},
	)

fn partial_depth_error(name String) Error:
	return Error(
		f"template: partial {name} is nested more than {MAX_DEPTH} deep; a partial may include itself",
		kind: "EOVERFLOW",
		details: {"partial": name.clone()},
	)

fn unknown_partial_error(name String) Error:
	return Error(
		f"template: unknown partial {name}",
		kind: "ENOENT",
		details: {"partial": name.clone()},
	)

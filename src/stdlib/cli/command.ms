// ms: allow_effect std.console.write
import panic from "@std/core.ms"
/*
Command-line parsing for programs with nested subcommands, typed flags, positional arguments and generated help.

A `Command` holds a schema (`flags`, `args`), `children`, and a handler. `command[T]` builds a leaf whose handler
receives your own options record `T`: every flag and argument is stored under its name (dashes become underscores),
and the record is decoded from those values like `json.parse[T]`, so each field needs a flag or argument with its name
and a matching type. Flags and arguments without a field, such as inherited persistent flags, are ignored.
Parsing reads only the `List[String]` you give it; pass `arguments()` from `@std/os/env.ms` in `main`.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import Arg, Command, Flag, FlagKind, command from "@std/cli/command.ms"
import arguments from "@std/os/env.ms"

type Greeting:
    name String
    shout Bool

fn greet(options Greeting) Int!:
    return ok(0)

fn main() Int:
    greeting := command[Greeting](
        name: "greet",
        about: "Print a greeting",
        flags: [Flag("shout", FlagKind.Bool, "s", help: "Uppercase the greeting")],
        args: [Arg("name", help: "Who to greet")],
        run: fn options: greet(options)
    )
    return Command(name: "tool", children: [greeting]).execute(arguments())
```
*/
import (
	Align, Table from "@std/cli/table.ms",
	Data from "@std/core.ms",
	parse, stringify from "@std/data/json.ms",
	stderr, stdout from "@std/io/io.ms",
)

// What a flag accepts. Each case fills the record field of the same language type.
export enum FlagKind {
	// `Bool` field. Present or absent; `--name`, `--name=false` and `--no-name` are accepted.
	Bool
	// `String` field. Any text. The value may begin with a dash (`--name=-x` or `--name -x`).
	String
	// `Int` field. A whole number that fits in Int; other text returns an Error with kind `"EINVAL"`.
	Int
	// `Float` field. A finite decimal number that parses as Float; other text, including NaN
	// and infinities, returns an Error with kind `"EINVAL"`.
	Float
	// `List[String]` field. The flag may repeat; every occurrence is kept in order.
	List
}

// A named option such as `--port 8080` or `-p 8080`.
export type Flag {
	// The long name without dashes; also the key `Matches` reads it by.
	name String
	// What the flag accepts, and so the type of the record field; defaults to String.
	kind FlagKind = FlagKind.String
	// One-letter alias used as `-p`; empty for null. A value follows as `-p 8080` or
	// `-p=8080`; short flags do not combine (`-vd`) or attach a value (`-p8080`).
	short String = ""
	// Text used when the flag is absent; null for no default. A Bool defaults to false.
	default String?
	// One line shown in help.
	help String = ""
	// Absence is an error when there is no default. A Bool or List flag is never absent
	// (false or empty), so `required` has no effect on it.
	required Bool = false
	// Also accepted by every subcommand below the command that declares it.
	persistent Bool = false
	// When not empty, every value must be one of these texts; use with String and List
	// flags.
	choices List[String] = []
}

// A positional argument, bound in declaration order.
export type Arg {
	// The key `Matches` reads it by.
	name String
	// One line shown in help.
	help String = ""
	// Absence is an error. A required argument may not follow an optional one.
	required Bool = true
	// Takes every remaining word as a list; only the last argument may be rest.
	rest Bool = false
	// What the argument accepts: `String` (the default), `Int` or `Float`. An `Int` or
	// `Float` argument fills a record field of that type and fails the run when the word
	// does not parse. `Bool` and `List` are not positional kinds, and a `rest` argument
	// is always `List[String]`.
	kind FlagKind = FlagKind.String
}

/*
The values one invocation produced.

Reading a name the schema does not declare, or reading it as the wrong kind, is a programmer error and faults.
A flag with a default or `required`, and a required argument, always has a value.
*/
export type Matches {
	// Text values by flag or argument name; a List flag or rest argument holds several.
	values Map[String, List[String]] = Map[String, List[String]]()
	// The command names walked from the root, root included.
	path List[String] = []
	// The JSON literal for each supplied value by field name (dashes in names become
	// underscores); decoded by `command`.
	fields Map[String, String] = Map[String, String]()
}

// Returns the text of a flag or argument.
fn Matches.string(name String) String {
	return (self.values.get(name) or panic("called Optional.get() on null"))[0].clone()
}

// Returns an Int flag or argument value.
fn Matches.int(name String) Int {
	return self.string(name).parse_int() or panic("called Optional.get() on null")
}

// Returns a Float flag or argument value.
fn Matches.float(name String) Float {
	return self.string(name).parse_float() or panic("called Optional.get() on null")
}

// Returns a Bool flag value; absent is false.
fn Matches.bool(name String) Bool {
	return self.string(name) == "true"
}

// Returns every value of a List flag or rest argument, in order; empty when absent.
fn Matches.list(name String) List[String] {
	return self.values.get_or(name, []).clone()
}

// Returns the text, or null for an optional argument or flag that was not supplied.
fn Matches.string_or_none(name String) String? {
	items := self.values.get(name)
	if items != null {
		if not items.is_empty() { return items[0].clone() }
	}
	return null
}

// Returns an Int value, or null when absent.
fn Matches.int_or_none(name String) Int? {
	text := self.string_or_none(name)
	if text != null { return text.parse_int() }

	return null
}

// Returns a Float value, or null when absent.
fn Matches.float_or_none(name String) Float? {
	text := self.string_or_none(name)
	if text != null { return text.parse_float() }

	return null
}

/*
A command or command group: its schema, subcommands and handler.

A group is a Command with `children`. Build a leaf with `command[T]`, then call `execute(arguments())` from `main`. Start with the [complete CLI recipe](../../../cookbook/command-line.md#parse-subcommands-and-flags); use `exec` directly when you need `Matches`.
*/
export type Command {
	// The word that selects this node; the program name for the root.
	name String
	// One line shown in help.
	about String = ""
	// Flags declared here; persistent ones also apply below.
	flags List[Flag] = []
	// Positional arguments in order.
	args List[Arg] = []
	// Subcommands in help order; their names must be unique, nonempty and not `help`.
	children List[Command] = []
	// Runs after a successful parse; the returned Int is the exit status.
	exec fn(Matches) Int! = m => ok(0)
}

// Checks the command tree, resolves the subcommand chain, and validates flags and
// arguments. Returns `Help` for `-h`, `--help`, a leading `help` word, or a group
// invoked without a subcommand; an invalid schema or usage error returns `EINVAL`.
fn Command.parse(argv List[String]) Parsed! {
	check_schema(self, [], [self.name.clone()])?
	return walk(self, argv)
}

// Parses `argv`, writes help to stdout or the error plus a usage hint to stderr,
// and runs the handler. Returns the handler's status, 0 after help, 1 when the
// handler fails and 2 for a usage error.
fn Command.execute(argv List[String]) Int {
	parsed := self.parse(argv)

	if parsed.is_error() {
		stderr().write(
			parsed.err().message + f"\nRun '{self.name} --help' for usage.\n"
		).get()
		return 2
	}

	match parsed.get() {
		Help(text) => {
			stdout().write(text).get()
			return 0
		}
		Run(matches) => {
			result := self.run(matches)

			if result.is_error() {
				stderr().write(result.err().message + "\n").get()
				return 1
			}

			return result.get()
		}
	}
}

// Runs the handler of the command `matches.path` names, as `parse` resolved it, and
// returns its exit status. The path starts at this node's name; an unknown path is
// an `EINVAL` error.
fn Command.run(matches Matches) Int! {
	if matches.path.length() > 0 and matches.path[0] == self.name {
		node := node_at(self, matches.path, 1)
		if node != null {
			return node.exec(matches)
		}
	}

	return error(cli_unknown_command(matches.path.join(" "), self.name.clone()))
}

// Returns the help text for the command reached by following `path` from this node,
// or null for an unknown path.
fn Command.help(path List[String] = []) String? {
	rendered := help_at(self, path, 0, [self.name.clone()], [])
	if rendered.is_error() { return null }

	return rendered.get()
}

// Returns the child named `word`, or null; the result reads the child in place.
fn Command.child(word String) Command? {
	for candidate in self.children {
		if candidate.name == word { return candidate }
	}
	return null
}

// The outcome of parsing: help text to show, or a node ready to run.
export enum Parsed {
	// `-h`, `--help`, a leading `help` word, or a group invoked without a subcommand.
	Help(
		// The rendered help ending in a newline, ready to write to stdout.
		text String
	)
	// A leaf to run: `Command.run` passes the values to the handler at `matches.path`.
	Run(
		// The values to pass the handler; `path` names the command reached from the
		// root.
		matches Matches
	)
}

// The command reached by following `path` from `from` on, or null for an unknown word.
fn node_at(node Command, path List[String], from Int) Command? {
	if from >= path.length() { return node }

	next := node.child(path[from])
	if next != null { return node_at(next, path, from + 1) }

	return null
}

// The help of the command reached by following `words` from `from` on, under `names`
// and the persistent flags `inherited` so far; an unknown word is an error naming the
// path reached.
fn help_at(
	node Command,
	words List[String],
	from Int,
	names List[String],
	inherited List[Flag],
) String! {
	if from >= words.length() { return ok(render_help(node, names, inherited)) }

	next := node.child(words[from])
	if next != null {
		return help_at(
			next,
			words,
			from + 1,
			names.concat([words[from].clone()]),
			inherited.concat(persistent_flags(node.flags)),
		)
	}

	return error(cli_unknown_command(words[from].clone(), names.join(" ")))
}

/*
Builds a leaf command whose handler receives the options record `T`.

Each field of `T` is filled from the flag or argument with its name, dashes written as underscores, and has the
type its kind names:

| declared | field type |
| --- | --- |
| `FlagKind.Bool` | `Bool` (absent is false) |
| `FlagKind.String` | `String` |
| `FlagKind.Int` | `Int` |
| `FlagKind.Float` | `Float` |
| `FlagKind.List`, and a `rest` argument | `List[String]` (absent is empty) |
| `Arg` with `kind` `Int` or `Float` | `Int` or `Float` |
| any other `Arg` | `String` |

A flag with neither a default nor `required`, and an optional `Arg`, needs an `...?` field, which is `null`
when absent. A field with no matching value, or of the wrong type, fails the run with an `Error` with kind `"EINVAL"`. The
handler returns the exit status.
*/
export fn command[T Data](
	move name String,
	move run fn(T) Int!,
	move about String = "",
	move flags List[Flag] = [],
	move args List[Arg] = []
) Command {
	return Command(
		name: name,
		about: about,
		flags: flags,
		args: args,
		exec: matches => run(decode[T](matches)?),
	)
}

// Builds `T` from the JSON literals of the supplied values.
fn decode[T Data](matches Matches) T! {
	var members = matches.fields.entries().map(
		entry => (stringify(entry.key.clone()).get() + ":" + entry.value)
	)
	parsed := parse[T]("{" + members.join(",") + "}")
	return parsed.map_error(
		cause => cli_invalid_schema(
			f"options record does not match the declared flags and arguments: {cause.message}"
		)
	)
}

// Renders one supplied value as the JSON literal for its kind.
fn literal(kind FlagKind, text String) String {
	match kind {
		Bool => return text.clone()
		Int => return f"{(text.parse_int() or 0)}"
		Float => return f"{(text.parse_float() or 0.0)}"
		_ => return stringify(text.clone()).get_or("\"\"")
	}
}

// Collects the JSON literal of every supplied flag and argument for `command`.
fn collect_fields(
	values Map[String, List[String]],
	flags List[Flag],
	args List[Arg],
) Map[String, String] {
	var fields = Map[String, String]()

	for flag in flags {
		items := values.get_or(flag.name, [])

		if is_list(flag.kind) {
			fields[field_name(flag.name)] = stringify(items.clone()).get()
		} else if not items.is_empty() {
			fields[field_name(flag.name)] = literal(flag.kind, items[0].clone())
		}
	}

	for arg in args {
		items := values.get_or(arg.name, [])

		if arg.rest {
			fields[field_name(arg.name)] = stringify(items.clone()).get()
		} else if not items.is_empty() {
			fields[field_name(arg.name)] = literal(arg.kind, items[0].clone())
		}
	}

	return fields
}

// Maps a flag or argument name to its record field name.
fn field_name(name String) String {
	return name.replace("-", "_")
}

// Keeps the flags that descendants also accept.
fn persistent_flags(flags List[Flag]) List[Flag] {
	return flags.filter(flag => flag.persistent)
}

// Describes what a flag accepts, for errors.
fn expected_text(kind FlagKind, choices List[String]) String {
	if not choices.is_empty() { return "one of " + choices.join(", ") }

	match kind {
		Bool => return "true or false"
		Int => return "an integer"
		Float => return "a number"
		_ => return "text"
	}
}

// Names the value a flag takes in help, such as `int` or `dev|prod`.
fn value_hint(flag Flag) String {
	if not flag.choices.is_empty() { return flag.choices.join("|") }

	match flag.kind {
		Int => return "int"
		Float => return "float"
		_ => return "text"
	}
}

// Returns whether the kind is Bool.
fn is_bool(kind FlagKind) Bool {
	match kind {
		Bool => return true
		_ => return false
	}
}

// Returns whether the kind is List.
fn is_list(kind FlagKind) Bool {
	match kind {
		List => return true
		_ => return false
	}
}

// Returns whether `value` fits the flag's kind and choices.
fn fits(kind FlagKind, choices List[String], value String) Bool {
	if not choices.is_empty() and not choices.contains(
		value
	) { return false }

	match kind {
		Bool => return value == "true" or value == "false"
		Int => return value.parse_int() != null
		Float => {
			number := value.parse_float()
			if number != null { return number.is_finite() }

			return false
		}
		_ => return true
	}
}

// Checks one flag name or short against names already seen.
fn claim(var seen List[String], key String, label String) Void! {
	if seen.contains(
		key
	) { return error(cli_invalid_schema(f"duplicate {label}")) }

	seen.append(key.clone())
}

// Validates a node and everything below it; `inherited` holds ancestors' persistent
// flags.
fn check_schema(node Command, inherited List[Flag], path List[String]) Void! {
	where := path.join(" ")
	var names List[String] = []
	var shorts List[String] = []
	all := inherited.concat(node.flags)

	for flag in all {
		if flag.name.is_empty() {
			return error(cli_invalid_schema(f"empty flag name in {where}"))
		}
		if flag.name == "help" {
			return error(cli_invalid_schema(f"flag help is reserved in {where}"))
		}

		claim(names, flag.name.clone(), f"flag {flag.name} in {where}")?
		if flag.short.is_empty() { continue }
		if flag.short.length() != 1 or flag.short == "h" or flag.short == "-" {
			return error(
				cli_invalid_schema(
					f"bad short {flag.short} for {flag.name} in {where}"
				)
			)
		}

		claim(shorts, flag.short.clone(), f"short -{flag.short} in {where}")?
	}

	for flag in node.flags {
		text := flag.default
		if text != null {
			if not fits(flag.kind, flag.choices, text) {
				return error(
					cli_invalid_schema(
						f"default {text} does not fit flag {flag.name}"
					)
				)
			}
		}
	}

	var optional_seen = false
	var index = 0

	for arg in node.args {
		if arg.name.is_empty() or names.contains(arg.name) {
			return error(cli_invalid_schema(f"argument {arg.name} clashes in {where}"))
		}

		names.append(arg.name.clone())
		if arg.rest and index != node.args.length() - 1 {
			return error(
				cli_invalid_schema(
					f"rest argument {arg.name} must be last in {where}"
				)
			)
		}
		if arg.required and optional_seen {
			return error(
				cli_invalid_schema(
					f"required argument {arg.name} follows an optional one in {where}"
				)
			)
		}
		if is_bool(arg.kind) or is_list(arg.kind) {
			return error(
				cli_invalid_schema(
					f"argument {arg.name} in {where} must be String, Int or Float"
				)
			)
		}

		if not arg.required { optional_seen = true }
		index += 1
	}

	var words List[String] = []

	for child in node.children {
		if child.name == "help" or child.name.is_empty() {
			return error(
				cli_invalid_schema(
					f"bad command name {child.name} in {where}"
				)
			)
		}

		claim(words, child.name.clone(), f"command {child.name} in {where}")?
	}

	below := inherited.concat(persistent_flags(node.flags))
	for child in node.children {
		check_schema(child, below, path.concat([child.name.clone()]))?
	}
}

// Finds a flag by long name or one-letter alias.
fn find_flag(flags List[Flag], key String, long Bool) Flag? {
	for flag in flags {
		if long and flag.name == key { return flag.clone() }
		if not long and not flag.short.is_empty() and flag.short == key { return flag.clone() }
	}

	return null
}

// Stores one flag occurrence after checking it against the kind.
fn store(var values Map[String, List[String]], flag Flag, value String) Result[
	Void,
	Error,
] {
	if not fits(flag.kind, flag.choices, value) {
		return error(
			cli_invalid_value(
				"flag",
				flag.name.clone(),
				value,
				expected_text(flag.kind, flag.choices),
			)
		)
	}

	if is_list(flag.kind) {
		var items = values.get_or(flag.name, [])
		items.append(value.clone())
		values[flag.name.clone()] = items
		return ok()
	}

	values[flag.name.clone()] = [value.clone()]
	return ok()
}

// Resolves subcommands, flags and positionals from `argv`.
fn walk(root Command, argv List[String]) Parsed! {
	return walk_from(
		root,
		argv,
		0,
		[root.name.clone()],
		[],
		Map[String, List[String]](),
	)
}

// Resolves `argv` from `start` on at `node`, reached by `path`, with the persistent
// flags
// `inherited` and the flag values `given` so far. A subcommand word continues at the
// child.
fn walk_from(
	node Command,
	argv List[String],
	start Int,
	path List[String],
	inherited List[Flag],
	given Map[String, List[String]],
) Parsed! {
	var values = given.clone()
	var words List[String] = []
	var literal = false
	var index = start

	while index < argv.length() {
		token := argv[index].clone()
		index += 1

		if literal {
			words.append(token)
			continue
		}

		if token == "--" {
			literal = true
			continue
		}

		if token == "-h" or token == "--help" {
			return ok(Parsed.Help(render_help(node, path, inherited)))
		}

		if token.starts_with("-") and token.length() > 1 {
			flags := inherited.concat(node.flags)
			long := token.starts_with("--")
			body := token.view(if long { 2 } else { 1 }, token.length())
			cut := body.index_of("=")
			key := body.view(0, cut or body.length())
			var flag = find_flag(flags, key, long)
			var negated = false

			if long and (flag == null) and key.starts_with("no-") {
				positive := find_flag(flags, key.view(3, key.length()), true)
				found := positive

				if found != null {
					if is_bool(found.kind) {
						flag = positive
						negated = true
					}
				}
			}

			chosen := ok_or(flag, cli_unknown_flag(token))?

			if is_bool(chosen.kind) {
				if negated {
					values[chosen.name.clone()] = ["false"]
				} else {
					var supplied = "true"
					at := cut
					if at != null {
						supplied = body.view(at + 1, body.length()).clone()
					}
					store(values, chosen, supplied)?
				}

				continue
			}

			at := cut

			if at != null {
				store(values, chosen, body.view(at + 1, body.length()).clone())?
				continue
			}

			if index >= argv.length() { return error(cli_missing_value(token)) }

			store(values, chosen, argv[index].clone())?
			index += 1
			continue
		}

		if words.is_empty() {
			next := node.child(token)
			if next != null {
				return walk_from(
					next,
					argv,
					index,
					path.concat([token.clone()]),
					inherited.concat(persistent_flags(node.flags)),
					values,
				)
			}
			if token == "help" and not node.children.is_empty() {
				return ok(Parsed.Help(help_at(node, argv, index, path, inherited)?))
			}
		}

		words.append(token)
	}

	if not node.children.is_empty() and words.is_empty() {
		return ok(Parsed.Help(render_help(node, path, inherited)))
	}

	bind(node, words, values, path)?
	for flag in inherited.concat(node.flags) {
		fill(values, flag)?
	}

	fields := collect_fields(values, inherited.concat(node.flags), node.args)
	return ok(Parsed.Run(Matches(values, path.clone(), fields)))
}

// Assigns positional words to the node's arguments.
fn bind(
	node Command,
	words List[String],
	var values Map[String, List[String]],
	path List[String],
) Void! {
	var next = 0

	for arg in node.args {
		if arg.rest {
			remaining := words.drop(next)
			if arg.required and remaining.is_empty() {
				return error(cli_missing_required(arg.name.clone()))
			}

			values[arg.name.clone()] = remaining
			next = words.length()
			continue
		}

		if next >= words.length() {
			if arg.required { return error(cli_missing_required(arg.name.clone())) }

			continue
		}

		if not fits(arg.kind, [], words[next]) {
			return error(
				cli_invalid_value(
					"argument",
					arg.name.clone(),
					words[next].clone(),
					expected_text(arg.kind, []),
				)
			)
		}

		values[arg.name.clone()] = [words[next].clone()]
		next += 1
	}

	if next < words.length() {
		if node.args.is_empty() and not node.children.is_empty() {
			return error(cli_unknown_command(words[next].clone(), path.join(" ")))
		}
		return error(cli_too_many_arguments(words[next].clone()))
	}

	return ok()
}

// Applies the default of an absent flag or reports a missing required one.
fn fill(var values Map[String, List[String]], flag Flag) Void! {
	if values.contains(flag.name) { return ok() }

	text := flag.default

	if text != null {
		values[flag.name.clone()] = [text.clone()]
		return ok()
	}

	if is_bool(flag.kind) {
		values[flag.name.clone()] = ["false"]
		return ok()
	}

	if is_list(flag.kind) {
		values[flag.name.clone()] = []
		return ok()
	}

	if flag.required { return error(cli_missing_required(f"--{flag.name}")) }
}

// Renders usage, commands, arguments and flags for one node.
fn render_help(node Command, path List[String], inherited List[Flag]) String {
	var out = ""
	if not node.about.is_empty() { out += f"{node.about}\n\n" }

	var usage = "  " + path.join(" ")
	if not node.children.is_empty() { usage += " <command>" }
	if not node.flags.is_empty() or not inherited.is_empty() { usage += " [flags]" }

	for arg in node.args {
		label := arg.name + (if arg.rest { "..." } else { "" })
		usage += if arg.required { f" <{label}>" } else { f" [{label}]" }
	}

	out += f"Usage:\n{usage}\n"

	if not node.children.is_empty() {
		var commands = Table(columns: [Align.Left, Align.Left], indent: 2)
		for child in node.children {
			help_row(commands, [child.name.clone(), child.about.clone()])
		}
		out += f"\nCommands:\n{commands.render()}\n"
	}

	if not node.args.is_empty() {
		var arguments = Table(columns: [Align.Left, Align.Left], indent: 2)
		for arg in node.args { help_row(arguments, [arg.name.clone(), arg.help.clone()]) }
		out += f"\nArguments:\n{arguments.render()}\n"
	}

	out += flag_section("Flags", node.flags.concat([help_flag()]))
	out += flag_section("Global Flags", inherited)
	return out
}

// The built-in help flag, shown but handled by the parser.
fn help_flag() Flag {
	return Flag(name: "help", kind: FlagKind.Bool, short: "h", help: "Show help")
}

// Renders a titled flag list, aligned; empty for no flags.
fn flag_section(title String, flags List[Flag]) String {
	if flags.is_empty() { return "" }

	var table = Table(columns: [Align.Left, Align.Left], indent: 2)

	for flag in flags {
		var label = if not flag.short.is_empty() { f"-{flag.short}, " } else { "    " }
		label += f"--{flag.name}"
		if not is_bool(flag.kind) { label += f" <{value_hint(flag)}>" }

		var help = flag.help.clone()
		text := flag.default
		if text != null { help += f" (default {text})" }
		if flag.required { help += " (required)" }
		help_row(table, [label, help])
	}

	return f"\n{title}:\n{table.render()}\n"
}

// Adds a help row. Help text is single-line: tabs and line breaks become spaces; a row
// with other controls is omitted.
fn help_row(var table Table, row List[String]) Void {
	var cells = row.map(cell => cell.replace_each({"\n": " ", "\t": " ", "\r": " "}))
	if table.add(cells).is_error() { return }
}

fn cli_unknown_flag(name String) Error {
	return Error(f"cli: unknown flag {name}", kind: "EINVAL")
}

fn cli_unknown_command(name String, path String) Error {
	return Error(f"cli: unknown command {name} for {path}", kind: "EINVAL")
}

fn cli_missing_value(name String) Error {
	return Error(f"cli: flag {name} needs a value", kind: "EINVAL")
}

fn cli_invalid_value(what String, name String, value String, expected String) Error {
	return Error(f"cli: {what} {name}: {value} is not {expected}", kind: "EINVAL")
}

fn cli_missing_required(name String) Error {
	return Error(f"cli: missing required {name}", kind: "EINVAL")
}

fn cli_too_many_arguments(value String) Error {
	return Error(f"cli: unexpected argument {value}", kind: "EINVAL")
}

fn cli_invalid_schema(reason String) Error {
	return Error(f"cli: invalid command schema: {reason}", kind: "EINVAL")
}

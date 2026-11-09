/*
Command-line parsing for programs with nested subcommands, typed flags, positional arguments and generated help.

A `Command` holds a schema (`flags`, `args`), `children`, and a handler. `command[T]` builds a leaf whose handler
receives your own options record `T`: every flag and argument is stored under its name (dashes become underscores),
and the record is decoded from those values like `json.parse[T]`, so each field needs a flag or argument with its name
and a matching type; flags and arguments without a field, such as inherited persistent flags, are ignored. Parsing reads only the `List[String]` you give it; pass
`process.arguments()` from `main`.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import Arg, Command, Flag, FlagKind, command from "@std/cli/command.ms"
import arguments from "@std/os/env.ms"

type Greeting:
    name: String
    shout: Bool

fn greet(options: Greeting) Int!:
    return ok(0)

export fn main() Int:
    let greeting = command[Greeting](
        name: "greet",
        about: "Print a greeting",
        flags: [Flag("shout", FlagKind.Bool, "s", help: "Uppercase the greeting")],
        args: [Arg("name", help: "Who to greet")],
        run: fn options: greet(options)
    )
    return Command(name: "tool", children: [greeting]).execute(arguments())
```
*/
import Align, Table from "@std/cli/table.ms"
import Data from "@std/core.ms"
import stderr, stdout from "@std/io/io.ms"
import parse, stringify from "@std/data/json.ms"

fn cli_unknown_flag(name: String) Error:
    return Error("cli: unknown flag {name}", kind: "EINVAL")

fn cli_unknown_command(name: String, path: String) Error:
    return Error("cli: unknown command {name} for {path}", kind: "EINVAL")

fn cli_missing_value(name: String) Error:
    return Error("cli: flag {name} needs a value", kind: "EINVAL")

fn cli_invalid_value(name: String, value: String, expected: String) Error:
    return Error("cli: flag {name}: {value} is not {expected}", kind: "EINVAL")

fn cli_missing_required(name: String) Error:
    return Error("cli: missing required {name}", kind: "EINVAL")

fn cli_too_many_arguments(value: String) Error:
    return Error("cli: unexpected argument {value}", kind: "EINVAL")

fn cli_invalid_schema(reason: String) Error:
    return Error("cli: invalid command schema: {reason}", kind: "EINVAL")

// What a flag accepts. Each case fills the record field of the same language type.
export enum FlagKind:
    // `Bool` field. Present or absent; `--name`, `--name=false` and `--no-name` are accepted.
    Bool
    // `String` field. Any text, including text that begins with a dash when given as `--name=value`.
    String
    // `Int` field. A whole number that fits in Int; other text returns an Error with kind `"EINVAL"`.
    Int
    // `Float` field. A finite decimal number that parses as Float; other text, including NaN and infinities, returns an Error with kind `"EINVAL"`.
    Float
    // `List[String]` field. The flag may repeat; every occurrence is kept in order.
    List

// A named option such as `--port 8080` or `-p 8080`.
export type Flag:
    // The long name without dashes; also the key `Matches` reads it by.
    name: String
    // What the flag accepts, and so the type of the record field; defaults to String.
    kind: FlagKind = FlagKind.String
    // One-letter alias used as `-p`; empty for none.
    short: String = ""
    // Text used when the flag is absent; none for no default. A Bool defaults to false.
    default: String?
    // One line shown in help.
    help: String = ""
    // Absence is an error when there is no default.
    required: Bool = false
    // Also accepted by every subcommand below the command that declares it.
    persistent: Bool = false
    // When not empty, every value must be one of these texts; use with String and List flags.
    choices: List[String] = []

// A positional argument, bound in declaration order.
export type Arg:
    // The key `Matches` reads it by.
    name: String
    // One line shown in help.
    help: String = ""
    // Absence is an error. A required argument may not follow an optional one.
    required: Bool = true
    // Takes every remaining word as a list; only the last argument may be rest.
    rest: Bool = false

/*
The values one invocation produced.

Reading a name the schema does not declare, or reading it as the wrong kind, is a programmer error and faults.
A flag with a default or `required`, and a required argument, always has a value.
*/
export type Matches:
    // Text values by flag or argument name; a List flag or rest argument holds several.
    values: Map[String, List[String]] = Map[String, List[String]]()
    // The command names walked from the root, root included.
    path: List[String] = []
    // The JSON literal for each supplied value by field name (dashes in names become underscores); decoded by `command`.
    fields: Map[String, String] = Map[String, String]()

impl Matches:
    // Returns the text of a flag or argument.
    fn string(name: String) String:
        return self.values.get(name).get()[0].clone()

    // Returns an Int flag or argument value.
    fn int(name: String) Int:
        return self.string(name).parse_int().get()

    // Returns a Float flag or argument value.
    fn float(name: String) Float:
        return self.string(name).parse_float().get()

    // Returns a Bool flag value; absent is false.
    fn bool(name: String) Bool:
        return self.string(name) == "true"

    // Returns every value of a List flag or rest argument, in order; empty when absent.
    fn list(name: String) List[String]:
        return self.values.get_or(name, []).clone()

    // Returns the text, or none for an optional argument or flag that was not supplied.
    fn string_or_none(name: String) String?:
        if let items = self.values.get(name):
            if not items.is_empty(): return items[0].clone()
        return none

    // Returns an Int value, or none when absent.
    fn int_or_none(name: String) Int?:
        if let text = self.string_or_none(name): return text.parse_int()

        return none

    // Returns a Float value, or none when absent.
    fn float_or_none(name: String) Float?:
        if let text = self.string_or_none(name): return text.parse_float()

        return none

/*
A command or command group: its schema, subcommands and handler.

A group is a Command with `children`. Build a leaf with `command[T]`, then call `execute(arguments())` from `main`. Start with the [complete CLI recipe](../../../cookbook/command-line.md#parse-subcommands-and-flags); use `exec` directly when you need `Matches`.
*/
export type Command:
    // The word that selects this node; the program name for the root.
    name: String
    // One line shown in help.
    about: String = ""
    // Flags declared here; persistent ones also apply below.
    flags: List[Flag] = []
    // Positional arguments in order.
    args: List[Arg] = []
    // Subcommands in help order; their names must be unique, nonempty and not `help`.
    children: List[Command] = []
    // Runs after a successful parse; the returned Int is the exit status.
    exec: fn(Matches) Int! = fn m: ok(0)

// The outcome of parsing: help text to show, or a node ready to run.
export enum Parsed:
    // `-h`, `--help`, `help` or a group without a handler.
    Help(
        // The rendered help ending in a newline, ready to write to stdout.
        text: String
    )
    // A leaf to run: `Command.run` passes the values to the handler at `matches.path`.
    Run(
        // The values to pass the handler; `path` names the command reached from the root.
        matches: Matches
    )

impl Command:
    // Checks the tree, resolves the subcommand chain, and validates flags and arguments.
    // Returns `Help` for `-h`, `--help`, a leading `help` word, or a group invoked without a subcommand.
    fn parse(argv: List[String]) Parsed!:
        try check_schema(self, [], [self.name.clone()])
        return walk(self, argv)

    // Parses `argv`, writes help to stdout or the error plus a usage hint to stderr, and runs the handler.
    // Returns the handler's status, 0 after help, 1 when the handler fails and 2 for a usage error.
    fn execute(argv: List[String]) Int:
        let parsed = self.parse(argv)

        if parsed.is_error():
            stderr().write(
                parsed.err().message + "\nRun '{self.name} --help' for usage.\n"
            ).get()
            return 2

        match parsed.get():
            Help(text):
                stdout().write(text).get()
                return 0
            Run(matches):
                let result = self.run(matches)

                if result.is_error():
                    stderr().write(result.err().message + "\n").get()
                    return 1

                return result.get()

    // Runs the handler of the command `matches.path` names, as `parse` resolved it, and returns its exit status.
    // The path starts at this node's name; an unknown path is an `EINVAL` error.
    fn run(matches: Matches) Int!:
        if let node = node_at(self, matches.path, 1): return node.exec(matches)

        return error(cli_unknown_command(matches.path.join(" "), self.name.clone()))

    // Returns the help text for the command reached by following `path` from this node, or none for an unknown path.
    fn help(path: List[String] = []) String?:
        let rendered = help_at(self, path, 0, [self.name.clone()], [])
        if rendered.is_error(): return none

        return rendered.get()

    // Returns the child named `word`, or none; the result reads the child in place.
    fn child(word: String) Command?:
        for candidate in self.children:
            if candidate.name == word: return candidate
        return none

// The command reached by following `path` from `from` on, or none for an unknown word.
fn node_at(node: Command, path: List[String], from: Int) Command?:
    if from >= path.length(): return node
    if let next = node.child(path[from]): return node_at(next, path, from + 1)

    return none

// The help of the command reached by following `words` from `from` on, under `names` and the
// persistent flags `inherited` so far; an unknown word is an error naming the path reached.
fn help_at(
    node: Command,
    words: List[String],
    from: Int,
    names: List[String],
    inherited: List[Flag]
) String!:
    if from >= words.length(): return ok(render_help(node, names, inherited))
    if let next = node.child(words[from]):
        return help_at(
            next, words, from + 1, names.concat([words[from].clone()]),
            inherited.concat(persistent_flags(node.flags))
        )

    return error(cli_unknown_command(words[from].clone(), names.join(" ")))

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
| any other `Arg` | `String` |

A flag with neither a default nor `required`, and an optional `Arg`, needs an `...?` field, which is `none`
when absent. A field with no matching value, or of the wrong type, fails the run with an `Error` with kind `"EINVAL"`. The
handler returns the exit status.
*/
export fn command[T: Data](
    name: String,
    run: fn(T) Int!,
    about: String = "",
    flags: List[Flag] = [],
    args: List[Arg] = []
) Command:
    return Command(
        name: name, about: about, flags: flags, args: args,
        exec: fn matches: run(try decode[T](matches))
    )

// Builds `T` from the JSON literals of the supplied values.
fn decode[T: Data](matches: Matches) T!:
    var members = matches.fields.entries().map(
        fn entry: (stringify(entry.key.clone()).get() + ":" + entry.value)
    )
    let parsed = parse[T]("\{" + members.join(",") + "\}")
    return parsed.map_error(
        fn cause: cli_invalid_schema(
            "options record does not match the declared flags and arguments: {cause.message}"
        )
    )

// Renders one supplied value as the JSON literal for its kind.
fn literal(kind: FlagKind, text: String) String:
    match kind:
        Bool: return text.clone()
        Int: return "{text.parse_int().get()}"
        Float: return "{text.parse_float().get()}"
        _: return stringify(text.clone()).get()

// Collects the JSON literal of every supplied flag and argument for `command`.
fn collect_fields(
    values: Map[String, List[String]],
    flags: List[Flag],
    args: List[Arg]
) Map[String, String]:
    var fields = Map[String, String]()

    for flag in flags:
        let items = values.get_or(flag.name, [])

        if is_list(flag.kind):
            fields[field_name(flag.name)] = stringify(items.clone()).get()
        else if not items.is_empty():
            fields[field_name(flag.name)] = literal(flag.kind, items[0].clone())

    for arg in args:
        let items = values.get_or(arg.name, [])

        if arg.rest:
            fields[field_name(arg.name)] = stringify(items.clone()).get()
        else if not items.is_empty():
            fields[field_name(arg.name)] = stringify(items[0].clone()).get()

    return fields

// Maps a flag or argument name to its record field name.
fn field_name(name: String) String:
    return name.replace("-", "_")

// Keeps the flags that descendants also accept.
fn persistent_flags(flags: List[Flag]) List[Flag]:
    return flags.filter(fn flag: flag.persistent)

// Describes what a flag accepts, for errors.
fn expected_text(flag: Flag) String:
    if not flag.choices.is_empty(): return "one of " + flag.choices.join(", ")

    match flag.kind:
        Bool: return "true or false"
        Int: return "an integer"
        Float: return "a number"
        _: return "text"

// Names the value a flag takes in help, such as `int` or `dev|prod`.
fn value_hint(flag: Flag) String:
    if not flag.choices.is_empty(): return flag.choices.join("|")

    match flag.kind:
        Int: return "int"
        Float: return "float"
        _: return "text"

// Returns whether the kind is Bool.
fn is_bool(kind: FlagKind) Bool:
    match kind:
        Bool: return true
        _: return false

// Returns whether the kind is List.
fn is_list(kind: FlagKind) Bool:
    match kind:
        List: return true
        _: return false

// Returns whether `value` fits the flag's kind and choices.
fn fits(flag: Flag, value: String) Bool:
    if not flag.choices.is_empty() and not flag.choices.contains(value): return false

    match flag.kind:
        Bool: return value == "true" or value == "false"
        Int: return value.parse_int().is_some()
        Float:
            if let number = value.parse_float(): return number.is_finite()

            return false
        _: return true

// Checks one flag name or short against names already seen.
fn claim(var seen: List[String], key: String, label: String) Unit!:
    if seen.contains(key): return error(cli_invalid_schema("duplicate {label}"))

    seen.append(key)
    return ok(unit)

// Validates a node and everything below it; `inherited` holds ancestors' persistent flags.
fn check_schema(node: Command, inherited: List[Flag], path: List[String]) Unit!:
    let where = path.join(" ")
    var names: List[String] = []
    var shorts: List[String] = []
    let all = inherited.concat(node.flags)

    for flag in all:
        if flag.name.is_empty(): return error(
            cli_invalid_schema("empty flag name in {where}")
        )
        if flag.name == "help": return error(
            cli_invalid_schema("flag help is reserved in {where}")
        )

        try claim(var names, flag.name.clone(), "flag {flag.name} in {where}")
        if flag.short.is_empty(): continue
        if flag.short.length() != 1 or flag.short == "h" or flag.short == "-":
            return error(
                cli_invalid_schema(
                    "bad short {flag.short} for {flag.name} in {where}"
                )
            )

        try claim(var shorts, flag.short.clone(), "short -{flag.short} in {where}")

    for flag in node.flags:
        if let text = flag.default:
            if not fits(flag, text):
                return error(
                    cli_invalid_schema(
                        "default {text} does not fit flag {flag.name}"
                    )
                )

    var optional_seen = false
    var index = 0

    for arg in node.args:
        if arg.name.is_empty() or names.contains(arg.name):
            return error(cli_invalid_schema("argument {arg.name} clashes in {where}"))

        names.append(arg.name.clone())
        if arg.rest and index != node.args.length() - 1:
            return error(
                cli_invalid_schema(
                    "rest argument {arg.name} must be last in {where}"
                )
            )
        if arg.required and optional_seen:
            return error(
                cli_invalid_schema(
                    "required argument {arg.name} follows an optional one in {where}"
                )
            )

        if not arg.required: optional_seen = true
        index += 1

    var words: List[String] = []

    for child in node.children:
        if child.name == "help" or child.name.is_empty():
            return error(cli_invalid_schema("bad command name {child.name} in {where}"))

        try claim(var words, child.name.clone(), "command {child.name} in {where}")

    let below = inherited.concat(persistent_flags(node.flags))
    for child in node.children:
        try check_schema(child, below, path.concat([child.name.clone()]))
    return ok(unit)

// Finds a flag by long name or one-letter alias.
fn find_flag(flags: List[Flag], key: String, long: Bool) Flag?:
    for flag in flags:
        if long and flag.name == key: return flag.clone()
        if not long and not flag.short.is_empty() and flag.short == key: return flag.clone()

    return none

// Stores one flag occurrence after checking it against the kind.
fn store(var values: Map[String, List[String]], flag: Flag, value: String) Result[
    Unit, Error
]:
    if not fits(flag, value):
        return error(cli_invalid_value(flag.name.clone(), value, expected_text(flag)))

    if is_list(flag.kind):
        var items = values.get_or(flag.name, [])
        items.append(value)
        values[flag.name.clone()] = items
        return ok(unit)

    values[flag.name.clone()] = [value]
    return ok(unit)

// Resolves subcommands, flags and positionals from `argv`.
fn walk(root: Command, argv: List[String]) Parsed!:
    return walk_from(
        root, argv, 0, [root.name.clone()], [], Map[String, List[String]]()
    )

// Resolves `argv` from `start` on at `node`, reached by `path` with the persistent flags
// `inherited` and the flag values `given` so far; a subcommand word continues at the child.
fn walk_from(
    node: Command,
    argv: List[String],
    start: Int,
    path: List[String],
    inherited: List[Flag],
    given: Map[String, List[String]]
) Parsed!:
    var values = given
    var words: List[String] = []
    var literal = false
    var index = start

    while index < argv.length():
        let token = argv[index].clone()
        index += 1

        if literal:
            words.append(token)
            continue

        if token == "--":
            literal = true
            continue

        if token == "-h" or token == "--help":
            return ok(Parsed.Help(render_help(node, path, inherited)))

        if token.starts_with("-") and token.length() > 1:
            let flags = inherited.concat(node.flags)
            let long = token.starts_with("--")
            let body = token.drop(if long: 2 else: 1)
            let cut = body.index_of("=")
            let key = body.take(cut.get(body.length()))
            var flag = find_flag(flags, key, long)
            var negated = false

            if long and flag.is_none() and key.starts_with("no-"):
                let positive = find_flag(flags, key.drop(3), true)

                if positive.is_some() and is_bool(positive.get().kind):
                    flag = positive
                    negated = true

            if flag.is_none(): return error(cli_unknown_flag(token))

            let chosen = flag.get()

            if is_bool(chosen.kind):
                if negated: values[chosen.name.clone()] = ["false"]
                else:
                    try store(
                        var values,
                        chosen,
                        if cut.is_some(): body.drop(
                            cut.get() + 1
                        ) else: "true"
                    )

                continue

            if cut.is_some():
                try store(var values, chosen, body.drop(cut.get() + 1))
                continue

            if index >= argv.length(): return error(cli_missing_value(token))

            try store(var values, chosen, argv[index].clone())
            index += 1
            continue

        if words.is_empty():
            if let next = node.child(token):
                return walk_from(
                    next, argv, index, path.concat([token.clone()]),
                    inherited.concat(persistent_flags(node.flags)), values
                )
            if token == "help" and not node.children.is_empty():
                return ok(Parsed.Help(try help_at(node, argv, index, path, inherited)))

        words.append(token)

    if not node.children.is_empty() and words.is_empty():
        return ok(Parsed.Help(render_help(node, path, inherited)))

    try bind(node, words, var values, path)
    for flag in inherited.concat(node.flags):
        try fill(var values, flag)

    let fields = collect_fields(values, inherited.concat(node.flags), node.args)
    return ok(Parsed.Run(Matches(values, path, fields)))

// Assigns positional words to the node's arguments.
fn bind(
    node: Command,
    words: List[String],
    var values: Map[String, List[String]],
    path: List[String]
) Unit!:
    var next = 0

    for arg in node.args:
        if arg.rest:
            let remaining = words.drop(next)
            if arg.required and remaining.is_empty(): return error(
                cli_missing_required(arg.name.clone())
            )

            values[arg.name.clone()] = remaining
            next = words.length()
            continue

        if next >= words.length():
            if arg.required: return error(cli_missing_required(arg.name.clone()))

            continue

        values[arg.name.clone()] = [words[next].clone()]
        next += 1

    if next < words.length():
        if node.args.is_empty() and not node.children.is_empty():
            return error(cli_unknown_command(words[next].clone(), path.join(" ")))

        return error(cli_too_many_arguments(words[next].clone()))

    return ok(unit)

// Applies the default of an absent flag or reports a missing required one.
fn fill(var values: Map[String, List[String]], flag: Flag) Unit!:
    if values.contains(flag.name): return ok(unit)

    if let text = flag.default:
        values[flag.name.clone()] = [text.clone()]
        return ok(unit)

    if is_bool(flag.kind):
        values[flag.name.clone()] = ["false"]
        return ok(unit)

    if is_list(flag.kind):
        values[flag.name.clone()] = []
        return ok(unit)

    if flag.required: return error(cli_missing_required("--{flag.name}"))

    return ok(unit)

// Renders usage, commands, arguments and flags for one node.
fn render_help(node: Command, path: List[String], inherited: List[Flag]) String:
    var out = ""
    if not node.about.is_empty(): out += node.about + "\n\n"

    var usage = "  " + path.join(" ")
    if not node.children.is_empty(): usage += " <command>"
    if not node.flags.is_empty() or not inherited.is_empty(): usage += " [flags]"

    for arg in node.args:
        let label = arg.name + (if arg.rest: "..." else: "")
        usage += if arg.required: " <{label}>" else: " [{label}]"

    out += "Usage:\n" + usage + "\n"

    if not node.children.is_empty():
        var commands = Table(columns: [Align.Left, Align.Left], indent: 2)
        for child in node.children: help_row(
            var commands, [child.name.clone(), child.about.clone()]
        )
        out += "\nCommands:\n" + commands.render() + "\n"

    if not node.args.is_empty():
        var arguments = Table(columns: [Align.Left, Align.Left], indent: 2)
        for arg in node.args: help_row(
            var arguments, [arg.name.clone(), arg.help.clone()]
        )
        out += "\nArguments:\n" + arguments.render() + "\n"

    out += flag_section("Flags", node.flags.concat([help_flag()]))
    out += flag_section("Global Flags", inherited)
    return out

// The built-in help flag, shown but handled by the parser.
fn help_flag() Flag:
    return Flag(name: "help", kind: FlagKind.Bool, short: "h", help: "Show help")

// Renders a titled flag list, aligned; empty for no flags.
fn flag_section(title: String, flags: List[Flag]) String:
    if flags.is_empty(): return ""

    var table = Table(columns: [Align.Left, Align.Left], indent: 2)

    for flag in flags:
        var label = if not flag.short.is_empty(): "-{flag.short}, " else: "    "
        label += "--{flag.name}"
        if not is_bool(flag.kind): label += " <{value_hint(flag)}>"

        var help = flag.help.clone()
        if let text = flag.default: help += " (default {text})"
        if flag.required: help += " (required)"
        help_row(var table, [label, help])

    return "\n{title}:\n" + table.render() + "\n"

// Adds a help row. Help text is single-line: tabs and line breaks become spaces; a row with other controls is omitted.
fn help_row(var table: Table, row: List[String]) Unit:
    var cells = row.map(fn cell: cell.replace_each({"\n": " ", "\t": " ", "\r": " "}))
    if table.add(cells).is_error(): return

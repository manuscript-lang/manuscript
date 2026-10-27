# Command-line parsing for programs with nested subcommands, typed flags, positional arguments and generated help.
#
# A `Command` holds a schema (`flags`, `args`), `children`, and a handler. `command[T]` builds a leaf whose handler
# receives your own options record `T`: every flag and argument is stored under its name (dashes become underscores),
# and the record is decoded from those values like `json.parse[T]`, so each field needs a flag or argument with its name
# and a matching type; flags and arguments without a field, such as inherited persistent flags, are ignored. Parsing reads only the `List[String]` you give it; pass
# `process.arguments()` from `main`.
#
# ```
# from "@std/cli.ms" import Arg, Command, Flag, FlagKind, command
# from "@std/process.ms" import arguments
#
# type Greeting:
#     name: String
#     shout: Bool
#
# def greet(options: Greeting) -> Result[Int, Error]:
#     return ok(0)
#
# def main() -> Int:
#     let greeting = command[Greeting](
#         name: "greet",
#         about: "Print a greeting",
#         flags: [Flag("shout", FlagKind.Bool, "s", help: "Uppercase the greeting")],
#         args: [Arg("name", help: "Who to greet")],
#         run: lambda options: greet(options)
#     )
#     return Command(name: "tool", children: [greeting]).execute(arguments())
# ```
from "@std/io.ms" import stderr, stdout
from "@std/json.ms" import parse, stringify

# Errors returned while checking a command schema or parsing arguments.
export type CliError:
    # A flag that no reachable command declares.
    case UnknownFlag(
        # The flag as written, including its dashes.
        name: String
    )
    # A word that is neither a subcommand nor accepted as a positional argument.
    case UnknownCommand(
        # The unrecognized word exactly as it appeared in the arguments.
        name: String,
        # The command chain that was searched, such as `tool remote`.
        path: String
    )
    # A flag that needs a value was last on the line.
    case MissingValue(
        # The flag as written.
        name: String
    )
    # A value that does not fit the flag's kind or choices.
    case InvalidValue(
        # The flag name without dashes.
        name: String,
        # The rejected text exactly as the user wrote it, without the flag name or dashes.
        value: String,
        # What was expected, such as `an integer` or `one of dev, prod`.
        expected: String
    )
    # A required flag or argument was not supplied.
    case MissingRequired(
        # The flag or argument name.
        name: String
    )
    # More positional words than the command declares arguments for.
    case TooManyArguments(
        # The first extra word.
        value: String
    )
    # The command tree itself is inconsistent; fix the program.
    case InvalidSchema(
        # What is wrong, such as `duplicate flag verbose`.
        reason: String
    )

impl Error for CliError:
    # Returns a `cli: ...` line naming the offending flag, word or schema entry.
    def message() -> String:
        match self:
            case UnknownFlag(name): return f"cli: unknown flag {name}"
            case UnknownCommand(name, path): return f"cli: unknown command {name} for {path}"
            case MissingValue(name): return f"cli: flag {name} needs a value"
            case InvalidValue(name, value, expected): return f"cli: flag {name}: {value} is not {expected}"
            case MissingRequired(name): return f"cli: missing required {name}"
            case TooManyArguments(value): return f"cli: unexpected argument {value}"
            case InvalidSchema(reason): return f"cli: invalid command schema: {reason}"

# What a flag accepts. Each case fills the record field of the same language type.
export type FlagKind:
    # `Bool` field. Present or absent; `--name`, `--name=false` and `--no-name` are accepted.
    case Bool
    # `String` field. Any text, including text that begins with a dash when given as `--name=value`.
    case String
    # `Int` field. A whole number that fits in Int; other text is an InvalidValue error.
    case Int
    # `Float` field. A finite decimal number that parses as Float; other text, including NaN and infinities, is an InvalidValue error.
    case Float
    # `List[String]` field. The flag may repeat; every occurrence is kept in order.
    case List

# A named option such as `--port 8080` or `-p 8080`.
export type Flag:
    # The long name without dashes; also the key `Matches` reads it by.
    name: String
    # What the flag accepts, and so the type of the record field; defaults to String.
    kind: FlagKind = FlagKind.String
    # One-letter alias used as `-p`; empty for none.
    short: String = ""
    # Text used when the flag is absent; none for no default. A Bool defaults to false.
    default: Optional[String] = none
    # One line shown in help.
    help: String = ""
    # Absence is an error when there is no default.
    required: Bool = False
    # Also accepted by every subcommand below the command that declares it.
    persistent: Bool = False
    # When not empty, every value must be one of these texts; use with String and List flags.
    choices: List[String] = []

# A positional argument, bound in declaration order.
export type Arg:
    # The key `Matches` reads it by.
    name: String
    # One line shown in help.
    help: String = ""
    # Absence is an error. A required argument may not follow an optional one.
    required: Bool = True
    # Takes every remaining word as a list; only the last argument may be rest.
    rest: Bool = False

# The values one invocation produced.
#
# Reading a name the schema does not declare, or reading it as the wrong kind, is a programmer error and faults.
# A flag with a default or `required`, and a required argument, always has a value.
export type Matches:
    # Text values by flag or argument name; a List flag or rest argument holds several.
    values: Map[String, List[String]] = Map[String, List[String]]()
    # The command names walked from the root, root included.
    path: List[String] = []
    # The JSON literal for each supplied value by field name (dashes in names become underscores); decoded by `command`.
    fields: Map[String, String] = Map[String, String]()

impl Matches:
    # Returns the text of a flag or argument.
    def string(name: String) -> String:
        return self.values.get(name).get() [0].clone()

    # Returns an Int flag or argument value.
    def int(name: String) -> Int:
        return self.string(name).parse_int().get()

    # Returns a Float flag or argument value.
    def float(name: String) -> Float:
        return self.string(name).parse_float().get()

    # Returns a Bool flag value; absent is false.
    def bool(name: String) -> Bool:
        return self.string(name) == "true"

    # Returns every value of a List flag or rest argument, in order; empty when absent.
    def list(name: String) -> List[String]:
        return self.values.get(name).get([]).clone()

    # Returns the text, or none for an optional argument or flag that was not supplied.
    def string_or_none(name: String) -> Optional[String]:
        if let items = self.values.get(name):
            if not items.is_empty(): return items[0].clone()
        return none

    # Returns an Int value, or none when absent.
    def int_or_none(name: String) -> Optional[Int]:
        if let text = self.string_or_none(name): return text.parse_int()

        return none

    # Returns a Float value, or none when absent.
    def float_or_none(name: String) -> Optional[Float]:
        if let text = self.string_or_none(name): return text.parse_float()

        return none

# A command or command group: its schema, subcommands and handler.
#
# A group is a Command with `children`. Build a leaf with `command[T]`, or set `exec` directly to read `Matches` yourself.
export type Command:
    # The word that selects this node; the program name for the root.
    name: String
    # One line shown in help.
    about: String = ""
    # Flags declared here; persistent ones also apply below.
    flags: List[Flag] = []
    # Positional arguments in order.
    args: List[Arg] = []
    # Subcommands in help order; their names must be unique, nonempty and not `help`.
    children: List[Command] = []
    # Runs after a successful parse; the returned Int is the exit status.
    exec: Callable[[Matches], Result[Int, Error]] = lambda m: ok(0)

# The outcome of parsing: help text to show, or a node ready to run.
export type Parsed:
    # `-h`, `--help`, `help` or a group without a handler.
    case Help(
        # The rendered help ending in a newline, ready to write to stdout.
        text: String
    )
    # A leaf to run.
    case Run(
        # The command reached by following the subcommand words; its `exec` is the handler.
        node: Command,
        # The values to pass its handler.
        matches: Matches
    )

impl Command:
    # Checks the tree, resolves the subcommand chain, and validates flags and arguments.
    # Returns `Help` for `-h`, `--help`, a leading `help` word, or a group invoked without a subcommand.
    def parse(argv: List[String]) -> Result[Parsed, CliError]:
        try check_schema(self, [], [self.name.clone()])
        return walk(self, argv)

    # Parses `argv`, writes help to stdout or the error plus a usage hint to stderr, and runs the handler.
    # Returns the handler's status, 0 after help, 1 when the handler fails and 2 for a usage error.
    def execute(argv: List[String]) -> Int:
        let parsed = self.parse(argv)

        if parsed.is_error():
            stderr().write(
                parsed.err().message() + f"\nRun '{self.name} --help' for usage.\n"
            ).get()
            return 2

        match parsed.get():
            case Help(text):
                stdout().write(text).get()
                return 0
            case Run(node, matches):
                let result = node.exec(matches)

                if result.is_error():
                    stderr().write(result.err().message() + "\n").get()
                    return 1

                return result.get()

    # Returns the help text for the command reached by following `path` from this node, or none for an unknown path.
    def help(path: List[String] = []) -> Optional[String]:
        var node = self.clone()
        var names = [self.name.clone()]
        var inherited: List[Flag] = []

        for word in path:
            let next = node.child(word)
            if next.is_none(): return none

            inherited = inherited.concat(persistent_flags(node.flags))
            node = next.get().clone()
            names.append(word.clone())

        return render_help(node, names, inherited)

    # Returns the child named `word`, or none.
    def child(word: String) -> Optional[Command]:
        for candidate in self.children:
            if candidate.name == word: return candidate.clone()
        return none

# Builds a leaf command whose handler receives the options record `T`.
#
# Each field of `T` is filled from the flag or argument with its name, dashes written as underscores, and has the
# type its kind names:
#
# | declared | field type |
# | --- | --- |
# | `FlagKind.Bool` | `Bool` (absent is false) |
# | `FlagKind.String` | `String` |
# | `FlagKind.Int` | `Int` |
# | `FlagKind.Float` | `Float` |
# | `FlagKind.List`, and a `rest` argument | `List[String]` (absent is empty) |
# | any other `Arg` | `String` |
#
# A flag with neither a default nor `required`, and an optional `Arg`, needs an `Optional[...]` field, which is `none`
# when absent. A field with no matching value, or of the wrong type, fails the run with an `InvalidSchema` error. The
# handler returns the exit status.
export def command[T](
    name: String,
    run: Callable[[T], Result[Int, Error]],
    about: String = "",
    flags: List[Flag] = [],
    args: List[Arg] = []
) -> Command:
    return Command(
        name: name, about: about, flags: flags, args: args,
        exec: lambda matches: run(try decode[T](matches))
    )

# Builds `T` from the JSON literals of the supplied values.
def decode[T](matches: Matches) -> Result[T, CliError]:
    var members: List[String] = []
    for entry in matches.fields.entries():
        members.append(stringify(entry.key.clone()).get() + ":" + entry.value)

    let parsed = parse[T]("{" + members.join(",") + "}")
    return parsed.map_error(
        lambda cause: CliError.InvalidSchema(
            f"options record does not match the declared flags and arguments: {cause.message()}"
        )
    )

# Renders one supplied value as the JSON literal for its kind.
def literal(kind: FlagKind, text: String) -> String:
    match kind:
        case Bool: return text
        case Int: return f"{text.parse_int().get()}"
        case Float: return f"{text.parse_float().get()}"
        case _: return stringify(text.clone()).get()

# Collects the JSON literal of every supplied flag and argument for `command`.
def collect_fields(
    values: Map[String, List[String]],
    flags: List[Flag],
    args: List[Arg]
) -> Map[String, String]:
    var fields = Map[String, String]()

    for flag in flags:
        let items = values.get(flag.name).get([])

        if is_list(flag.kind):
            fields[field_name(flag.name)] = stringify(items.clone()).get()
        elif not items.is_empty():
            fields[field_name(flag.name)] = literal(flag.kind, items[0].clone())

    for arg in args:
        let items = values.get(arg.name).get([])

        if arg.rest:
            fields[field_name(arg.name)] = stringify(items.clone()).get()
        elif not items.is_empty():
            fields[field_name(arg.name)] = stringify(items[0].clone()).get()

    return fields

# Maps a flag or argument name to its record field name.
def field_name(name: String) -> String:
    return name.replace("-", "_")

# Keeps the flags that descendants also accept.
def persistent_flags(flags: List[Flag]) -> List[Flag]:
    return flags.filter(lambda flag: flag.persistent)

# Describes what a flag accepts, for errors.
def expected_text(flag: Flag) -> String:
    if not flag.choices.is_empty(): return "one of " + flag.choices.join(", ")

    match flag.kind:
        case Bool: return "true or false"
        case Int: return "an integer"
        case Float: return "a number"
        case _: return "text"

# Names the value a flag takes in help, such as `int` or `dev|prod`.
def value_hint(flag: Flag) -> String:
    if not flag.choices.is_empty(): return flag.choices.join("|")

    match flag.kind:
        case Int: return "int"
        case Float: return "float"
        case _: return "text"

# Returns whether the kind is Bool.
def is_bool(kind: FlagKind) -> Bool:
    match kind:
        case Bool: return True
        case _: return False

# Returns whether the kind is List.
def is_list(kind: FlagKind) -> Bool:
    match kind:
        case List: return True
        case _: return False

# Returns whether `value` fits the flag's kind and choices.
def fits(flag: Flag, value: String) -> Bool:
    if not flag.choices.is_empty() and not flag.choices.contains(value): return False

    match flag.kind:
        case Bool: return value == "true" or value == "false"
        case Int: return value.parse_int().is_some()
        case Float:
            if let number = value.parse_float(): return number.is_finite()

            return False
        case _: return True

# Checks one flag name or short against names already seen.
def claim(var seen: List[String], key: String, label: String) -> Result[Unit, CliError]:
    if seen.contains(key): return error(CliError.InvalidSchema(f"duplicate {label}"))

    seen.append(key)
    return ok(())

# Validates a node and everything below it; `inherited` holds ancestors' persistent flags.
def check_schema(
    node: Command,
    inherited: List[Flag],
    path: List[String]
) -> Result[Unit, CliError]:
    let where = path.join(" ")
    var names: List[String] = []
    var shorts: List[String] = []
    let all = inherited.concat(node.flags)

    for flag in all:
        if flag.name.is_empty(): return error(
            CliError.InvalidSchema(f"empty flag name in {where}")
        )
        if flag.name == "help": return error(
            CliError.InvalidSchema(f"flag help is reserved in {where}")
        )

        try claim(var names, flag.name.clone(), f"flag {flag.name} in {where}")
        if flag.short.is_empty(): continue
        if flag.short.length() != 1 or flag.short == "h" or flag.short == "-":
            return error(
                CliError.InvalidSchema(
                    f"bad short {flag.short} for {flag.name} in {where}"
                )
            )

        try claim(var shorts, flag.short.clone(), f"short -{flag.short} in {where}")

    for flag in node.flags:
        if let text = flag.default:
            if not fits(flag, text):
                return error(
                    CliError.InvalidSchema(
                        f"default {text} does not fit flag {flag.name}"
                    )
                )

    var optional_seen = False
    var index = 0

    for arg in node.args:
        if arg.name.is_empty() or names.contains(arg.name):
            return error(
                CliError.InvalidSchema(
                    f"argument {arg.name} clashes in {where}"
                )
            )

        names.append(arg.name.clone())
        if arg.rest and index != node.args.length() - 1:
            return error(
                CliError.InvalidSchema(
                    f"rest argument {arg.name} must be last in {where}"
                )
            )
        if arg.required and optional_seen:
            return error(
                CliError.InvalidSchema(
                    f"required argument {arg.name} follows an optional one in {where}"
                )
            )

        if not arg.required: optional_seen = True
        index += 1

    var words: List[String] = []

    for child in node.children:
        if child.name == "help" or child.name.is_empty():
            return error(
                CliError.InvalidSchema(
                    f"bad command name {child.name} in {where}"
                )
            )

        try claim(var words, child.name.clone(), f"command {child.name} in {where}")

    let below = inherited.concat(persistent_flags(node.flags))
    for child in node.children:
        try check_schema(child, below, path.concat([child.name.clone()]))
    return ok(())

# Finds a flag by long name or one-letter alias.
def find_flag(flags: List[Flag], key: String, long: Bool) -> Optional[Flag]:
    for flag in flags:
        if long and flag.name == key: return flag.clone()
        if not long and not flag.short.is_empty() and flag.short == key: return flag.clone()

    return none

# Stores one flag occurrence after checking it against the kind.
def store(var values: Map[String, List[String]], flag: Flag, value: String) -> Result[
    Unit, CliError
]:
    if not fits(flag, value):
        return error(
            CliError.InvalidValue(
                flag.name.clone(), value, expected_text(flag)
            )
        )

    if is_list(flag.kind):
        var items = values.get(flag.name).get([])
        items.append(value)
        values[flag.name.clone()] = items
        return ok(())

    values[flag.name.clone()] = [value]
    return ok(())

# Resolves subcommands, flags and positionals from `argv`.
def walk(root: Command, argv: List[String]) -> Result[Parsed, CliError]:
    var node = root.clone()
    var path = [root.name.clone()]
    var inherited: List[Flag] = []
    var values = Map[String, List[String]]()
    var words: List[String] = []
    var literal = False
    var index = 0

    while index < argv.length():
        let token = argv[index].clone()
        index += 1

        if literal:
            words.append(token)
            continue

        if token == "--":
            literal = True
            continue

        if token == "-h" or token == "--help":
            return ok(Parsed.Help(render_help(node, path, inherited)))

        if token.starts_with("-") and token.length() > 1:
            let flags = inherited.concat(node.flags)
            let long = token.starts_with("--")
            let body = token.drop(2 if long else 1)
            let cut = body.index_of("=")
            let key = body.take(cut.get(body.length()))
            var flag = find_flag(flags, key, long)
            var negated = False

            if long and flag.is_none() and key.starts_with("no-"):
                let positive = find_flag(flags, key.drop(3), True)

                if positive.is_some() and is_bool(positive.get().kind):
                    flag = positive
                    negated = True

            if flag.is_none(): return error(CliError.UnknownFlag(token))

            let chosen = flag.get()

            if is_bool(chosen.kind):
                if negated: values[chosen.name.clone()] = ["false"]
                else:
                    try store(
                        var values,
                        chosen,
                        body.drop(
                            cut.get() + 1
                        ) if cut.is_some() else "true"
                    )

                continue

            if cut.is_some():
                try store(var values, chosen, body.drop(cut.get() + 1))
                continue

            if index >= argv.length(): return error(CliError.MissingValue(token))

            try store(var values, chosen, argv[index].clone())
            index += 1
            continue

        if words.is_empty():
            if let next = node.child(token):
                inherited = inherited.concat(persistent_flags(node.flags))
                node = next
                path.append(token)
                continue

            if token == "help" and not node.children.is_empty():
                var target = node.clone()
                var names = path.clone()
                var chain = inherited.clone()

                while index < argv.length():
                    let step = target.child(argv[index])
                    if step.is_none(): return error(
                        CliError.UnknownCommand(
                            argv[index].clone(), names.join(" ")
                        )
                    )

                    chain = chain.concat(persistent_flags(target.flags))
                    target = step.get().clone()
                    names.append(argv[index].clone())
                    index += 1

                return ok(Parsed.Help(render_help(target, names, chain)))

        words.append(token)

    if not node.children.is_empty() and words.is_empty():
        return ok(Parsed.Help(render_help(node, path, inherited)))

    try bind(node, words, var values, path)
    for flag in inherited.concat(node.flags):
        try fill(var values, flag)

    let fields = collect_fields(values, inherited.concat(node.flags), node.args)
    return ok(Parsed.Run(node, Matches(values, path, fields)))

# Assigns positional words to the node's arguments.
def bind(
    node: Command,
    words: List[String],
    var values: Map[String, List[String]],
    path: List[String]
) -> Result[Unit, CliError]:
    var next = 0

    for arg in node.args:
        if arg.rest:
            let remaining = words.drop(next)
            if arg.required and remaining.is_empty(): return error(
                CliError.MissingRequired(arg.name.clone())
            )

            values[arg.name.clone()] = remaining
            next = words.length()
            continue

        if next >= words.length():
            if arg.required: return error(CliError.MissingRequired(arg.name.clone()))

            continue

        values[arg.name.clone()] = [words[next].clone()]
        next += 1

    if next < words.length():
        if node.args.is_empty() and not node.children.is_empty():
            return error(CliError.UnknownCommand(words[next].clone(), path.join(" ")))

        return error(CliError.TooManyArguments(words[next].clone()))

    return ok(())

# Applies the default of an absent flag or reports a missing required one.
def fill(var values: Map[String, List[String]], flag: Flag) -> Result[Unit, CliError]:
    if values.contains(flag.name): return ok(())

    if let text = flag.default:
        values[flag.name.clone()] = [text.clone()]
        return ok(())

    if is_bool(flag.kind):
        values[flag.name.clone()] = ["false"]
        return ok(())

    if is_list(flag.kind):
        values[flag.name.clone()] = []
        return ok(())

    if flag.required: return error(CliError.MissingRequired(f"--{flag.name}"))

    return ok(())

# Renders usage, commands, arguments and flags for one node.
def render_help(node: Command, path: List[String], inherited: List[Flag]) -> String:
    var out = ""
    if not node.about.is_empty(): out += node.about + "\n\n"

    var usage = "  " + path.join(" ")
    if not node.children.is_empty(): usage += " <command>"
    if not node.flags.is_empty() or not inherited.is_empty(): usage += " [flags]"

    for arg in node.args:
        let label = arg.name + ("..." if arg.rest else "")
        usage += f" <{label}>" if arg.required else f" [{label}]"

    out += "Usage:\n" + usage + "\n"

    if not node.children.is_empty():
        out += "\nCommands:\n"

        var width = 0
        for child in node.children: width = max_int(width, child.name.length())
        for child in node.children: out += (
            "  "
            + child.name.pad_end(width, " ")
            + "  "
            + child.about
            + "\n"
        )

    if not node.args.is_empty():
        out += "\nArguments:\n"

        var width = 0
        for arg in node.args: width = max_int(width, arg.name.length())
        for arg in node.args: out += (
            "  "
            + arg.name.pad_end(width, " ")
            + "  "
            + arg.help
            + "\n"
        )

    out += flag_section("Flags", node.flags.concat([help_flag()]))
    out += flag_section("Global Flags", inherited)
    return out

# The built-in help flag, shown but handled by the parser.
def help_flag() -> Flag:
    return Flag(name: "help", kind: FlagKind.Bool, short: "h", help: "Show help")

# Renders a titled flag list, aligned; empty for no flags.
def flag_section(title: String, flags: List[Flag]) -> String:
    if flags.is_empty(): return ""

    var labels: List[String] = []
    var width = 0

    for flag in flags:
        var label = f"-{flag.short}, " if not flag.short.is_empty() else "    "

        label += f"--{flag.name}"
        if not is_bool(flag.kind): label += f" <{value_hint(flag)}>"
        labels.append(label.clone())
        width = max_int(width, label.length())

    var out = f"\n{title}:\n"
    var index = 0

    for flag in flags:
        var line = "  " + labels[index].pad_end(width, " ") + "  " + flag.help
        if let text = flag.default: line += f" (default {text})"
        if flag.required: line += " (required)"
        out += line.trim_end() + "\n"
        index += 1

    return out

def max_int(left: Int, right: Int) -> Int:
    return left if left > right else right

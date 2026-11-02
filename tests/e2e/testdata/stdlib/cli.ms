import Arg, CliError, Command, Flag, FlagKind, Matches, command from "@std/cli.ms"
import (
    expect_contains,
    expect_equal,
    expect_error,
    expect_ok,
    expect_some,
    fail
) from "@std/test/test.ms"

type ServeOptions:
    port: Int
    mode: String
    root: String
    verbose: Bool
    tags: List[String]

fn serve(options: ServeOptions) Int!:
    return ok(options.port)

fn common_flags() List[Flag]:
    return [
        Flag(
            name: "verbose", kind: FlagKind.Bool, short: "v", persistent: true,
            help: "Print more"
        )
    ]

fn serve_command() Command:
    return command[ServeOptions](
        name: "serve",
        about: "Run the server",
        flags: [
            Flag("port", FlagKind.Int, "p", "8080", "Listen port"),
            Flag(
                "mode", FlagKind.String, default: "dev", choices: ["dev", "prod"]
            ),
            Flag("tags", FlagKind.List)
        ],
        args: [Arg("root", "Directory to serve")],
        run: fn options: serve(options)
    )

type AddOptions:
    name: String
    url: String?
    extra: List[String]
    dry_run: Bool

fn remote_group() Command:
    let add = command[AddOptions](
        name: "add",
        flags: [Flag("dry-run", FlagKind.Bool)],
        args: [
            Arg("name"), Arg("url", required: false),
            Arg("extra", required: false, rest: true)
        ],
        run: fn options: ok(
            options.extra.length() + (if options.dry_run: 100 else: 0) + (
                if options
                .url
                .is_some(): 10 else: 0
            )
        )
    )
    return Command(name: "remote", about: "Manage remotes", children: [add])

fn app() Command:
    return Command(
        name: "tool", about: "Manage projects", flags: common_flags(),
        children: [serve_command(), remote_group()]
    )

fn run(argv: List[String]) Matches!CliError:
    let parsed = app().parse(argv)
    if parsed.is_error(): return error(parsed.err().clone())

    match parsed.get():
        Run(_, matches): return ok(matches.clone())
        Help(text): return ok(Matches(path: [text.clone()]))

fn failure(argv: List[String]) String!:
    let result = app().parse(argv)
    if result.is_ok(): return error(CliError.InvalidSchema("accepted"))

    return ok(result.err().message())

test "nested command resolves path and typed options":
    let matches = (run(["serve", "site"]) | try expect_ok)
    matches.path | try expect_equal(["tool", "serve"])
    matches.int("port") | try expect_equal(8080)
    matches.string("mode") | try expect_equal("dev")
    matches.string("root") | try expect_equal("site")
    matches.bool("verbose") | try expect_equal(false)

test "flags take values in every spelling and persistent flags work on both sides":
    let matches = (
        run(
            [
                "-v", "serve", "--port=9090", "-p", "7", "--mode", "prod", "--tags",
                "a", "--tags=b", "--", "-x"
            ]
        ) | try expect_ok
    )
    matches.int("port") | try expect_equal(7)
    matches.string("mode") | try expect_equal("prod")
    matches.list("tags") | try expect_equal(["a", "b"])
    matches.string("root") | try expect_equal("-x")
    matches.bool("verbose") | try expect_equal(true)

    let after = (run(["serve", "site", "--verbose", "--no-verbose"]) | try expect_ok)
    after.bool("verbose") | try expect_equal(false)

test "optional and rest arguments":
    let matches = (run(["remote", "add", "origin"]) | try expect_ok)
    matches.string("name") | try expect_equal("origin")
    matches.string_or_none("url") | try expect_equal(none)

    let full = (run(["remote", "add", "origin", "u", "x", "y"]) | try expect_ok)
    full.list("extra") | try expect_equal(["x", "y"])
    full.string_or_none("url") | try expect_equal("u")

test "usage errors name the problem":
    (try failure(["serve"])) | try expect_equal("cli: missing required root")
    (try failure(["serve", "a", "b"])) | try expect_equal("cli: unexpected argument b")
    (try failure(["serve", "a", "--port", "x"])) | try expect_equal(
        "cli: flag port: x is not an integer"
    )
    (try failure(["serve", "a", "--port", "1.5"])) | try expect_equal(
        "cli: flag port: 1.5 is not an integer"
    )
    (try failure(["serve", "a", "--mode", "x"])) | try expect_equal(
        "cli: flag mode: x is not one of dev, prod"
    )
    (try failure(["serve", "a", "--port"])) | try expect_equal(
        "cli: flag --port needs a value"
    )
    (try failure(["serve", "a", "--nope"])) | try expect_equal(
        "cli: unknown flag --nope"
    )
    (try failure(["bogus"])) | try expect_equal("cli: unknown command bogus for tool")
    (try failure(["remote", "bogus"])) | try expect_equal(
        "cli: unknown command bogus for tool remote"
    )

test "help is generated for groups, leaves and the help word":
    let root = app().help() | try expect_some
    root | try expect_contains("Usage:\n  tool <command> [flags]")
    root | try expect_contains("  serve   Run the server")
    root | try expect_contains("-v, --verbose  Print more")

    let leaf = app().help(["serve"]) | try expect_some
    leaf | try expect_contains("Usage:\n  tool serve [flags] <root>")
    leaf | try expect_contains("-p, --port <int>       Listen port (default 8080)")
    leaf | try expect_contains("Global Flags:")
    app().help(["nope"]) | try expect_equal(none)

    let via_word = (run(["help", "serve"]) | try expect_ok)
    via_word.path[0] | try expect_contains("tool serve")

    let group = (run(["remote"]) | try expect_ok)
    group.path[0] | try expect_contains("Manage remotes")

    let flag = (run(["serve", "--help"]) | try expect_ok)
    flag.path[0] | try expect_contains("Run the server")

test "float flags reject NaN and infinities":
    let ratio = Command(name: "x", flags: [Flag(name: "ratio", kind: FlagKind.Float)])
    for text in ["NaN", "Infinity", "-Infinity"]:
        (ratio.parse(["--ratio", text.clone()]) | try expect_error).message() | try expect_equal(
            "cli: flag ratio: {text} is not a number"
        )

    let _ = try expect_ok(ratio.parse(["--ratio", "1e5"]))
    let bad_default = Command(
        name: "x", flags: [Flag(name: "ratio", kind: FlagKind.Float, default: "NaN")]
    )
    (bad_default.parse([]) | try expect_error).message() | try expect_contains(
        "default NaN does not fit"
    )

test "schema mistakes are reported before parsing":
    let duplicate = Command(
        name: "x",
        flags: [
            Flag(name: "a", kind: FlagKind.Bool), Flag(name: "a", kind: FlagKind.String)
        ]
    )
    (duplicate.parse([]) | try expect_error).message() | try expect_contains(
        "duplicate flag a"
    )

    let bad_default = Command(
        name: "x", flags: [Flag(name: "n", kind: FlagKind.Int, default: "z")]
    )
    (bad_default.parse([]) | try expect_error).message() | try expect_contains(
        "default z does not fit"
    )

    let rest_first = Command(
        name: "x", args: [Arg(name: "a", rest: true), Arg(name: "b")]
    )
    (rest_first.parse([]) | try expect_error).message() | try expect_contains(
        "must be last"
    )

    let order = Command(
        name: "x", args: [Arg(name: "a", required: false), Arg(name: "b")]
    )
    (order.parse([]) | try expect_error).message() | try expect_contains(
        "follows an optional"
    )

    let reserved = Command(name: "x", children: [Command(name: "help")])
    (reserved.parse([]) | try expect_error).message() | try expect_contains(
        "bad command name help"
    )

fn handled(argv: List[String]) Int!:
    let parsed = app().parse(argv)
    if parsed.is_error(): return error(parsed.err().clone())

    match parsed.get():
        Run(node, matches): return node.exec(matches)
        Help(_): return ok(-1)

test "handlers receive the decoded options record":
    (handled(["serve", "site", "-p", "9090"]) | try expect_ok) | try expect_equal(9090)
    (handled(["serve", "site"]) | try expect_ok) | try expect_equal(8080)
    (handled(["-v", "serve", "site"]) | try expect_ok) | try expect_equal(8080)

test "optional, rest and dashed names decode into record fields":
    (handled(["remote", "add", "o"]) | try expect_ok) | try expect_equal(0)
    (handled(["remote", "add", "o", "u", "x", "y", "--dry-run"]) | try expect_ok) | try expect_equal(
        112
    )

test "a record that does not match the schema is reported when the handler runs":
    let mismatched = command[ServeOptions](name: "bad", run: fn options: ok(0))
    let result = Command(name: "tool", children: [mismatched]).parse(["bad"])
    let parsed = (result | try expect_ok)

    match parsed:
        Run(node, matches):
            (node.exec(matches) | try expect_error).message() | try expect_contains(
                "does not match"
            )
        Help(_): return fail("help")

test "help rows without text carry no trailing spaces":
    let quiet = Command(
        name: "t",
        args: [Arg("file")],
        children: [
            Command(name: "sub"), Command(name: "other-long", about: "Other")
        ]
    )
    let text = quiet.help() | try expect_some
    text | try expect_contains("  sub        \n".trim_end() + "\n")
    text | try expect_contains("  file\n")
    for line in text.split("\n"):
        line | try expect_equal(line.trim_end())

import (
	Arg, Command, Flag, FlagKind, Matches, command from "@std/cli/command.ms",
	expect_contains,
	expect_equal,
	expect_error,
	expect_ok,
	expect_some,
	fail from "@std/test/test.ms",
)

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
			name: "verbose",
			kind: FlagKind.Bool,
			short: "v",
			persistent: true,
			help: "Print more",
		)
	]

fn serve_command() Command:
	return command[ServeOptions](
		name: "serve",
		about: "Run the server",
		flags: [
			Flag("port", FlagKind.Int, "p", "8080", "Listen port"),
			Flag(
				"mode",
				FlagKind.String,
				default: "dev",
				choices: ["dev", "prod"],
			),
			Flag("tags", FlagKind.List),
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
	add := command[AddOptions](
		name: "add",
		flags: [Flag("dry-run", FlagKind.Bool)],
		args: [
			Arg("name"),
			Arg("url", required: false),
			Arg("extra", required: false, rest: true),
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
		name: "tool",
		about: "Manage projects",
		flags: common_flags(),
		children: [serve_command(), remote_group()],
	)

fn run(argv: List[String]) Matches!:
	parsed := app().parse(argv)
	if parsed.is_error(): return error(parsed.err().clone())

	match parsed.get():
		Run(matches): return ok(matches.clone())
		Help(text): return ok(Matches(path: [text.clone()]))

fn failure(argv: List[String]) String!:
	result := app().parse(argv)
	if result.is_ok(): return error(Error("accepted", kind: "EIO"))

	return ok(result.err().message)

test "nested command resolves path and typed options":
	matches := (run(["serve", "site"]) | expect_ok?)
	matches.path | expect_equal(["tool", "serve"])?
	matches.int("port") | expect_equal(8080)?
	matches.string("mode") | expect_equal("dev")?
	matches.string("root") | expect_equal("site")?
	matches.bool("verbose") | expect_equal(false)?

test "run rejects paths outside this command root":
	leaf := Command(name: "build", exec: fn matches: ok(29))
	tool := Command(name: "tool", exec: fn matches: ok(17), children: [leaf])
	expect_equal(tool.run(Matches(path: [])).is_error(), true)?
	expect_equal(tool.run(Matches(path: ["other"])).is_error(), true)?
	expect_equal(tool.run(Matches(path: ["other", "build"])).is_error(), true)?
	expect_equal(tool.run(Matches(path: ["build"])).is_error(), true)?
	expect_equal(tool.run(Matches(path: ["tool", "missing"])).is_error(), true)?
	expect_equal(tool.run(Matches(path: ["tool"])).get(), 17)?
	expect_equal(tool.run(Matches(path: ["tool", "build"])).get(), 29)?

test "flags take values in every spelling and persistent flags work on both sides":
	matches := (
		run(
			[
				"-v", "serve", "--port=9090", "-p", "7", "--mode", "prod", "--tags",
				"a", "--tags=b", "--", "-x"
			]
		) | expect_ok?
	)
	matches.int("port") | expect_equal(7)?
	matches.string("mode") | expect_equal("prod")?
	matches.list("tags") | expect_equal(["a", "b"])?
	matches.string("root") | expect_equal("-x")?
	matches.bool("verbose") | expect_equal(true)?

	after := (run(["serve", "site", "--verbose", "--no-verbose"]) | expect_ok?)
	after.bool("verbose") | expect_equal(false)?

test "optional and rest arguments":
	matches := (run(["remote", "add", "origin"]) | expect_ok?)
	matches.string("name") | expect_equal("origin")?
	matches.string_or_none("url") | expect_equal(none)?

	full := (run(["remote", "add", "origin", "u", "x", "y"]) | expect_ok?)
	full.list("extra") | expect_equal(["x", "y"])?
	full.string_or_none("url") | expect_equal("u")?

test "usage errors name the problem":
	(failure(["serve"])?) | expect_equal("cli: missing required root")?
	(failure(["serve", "a", "b"])?) | expect_equal("cli: unexpected argument b")?
	(
		(failure(["serve", "a", "--port", "x"])?)
		| expect_equal("cli: flag port: x is not an integer")?
	)
	(
		(failure(["serve", "a", "--port", "1.5"])?) | expect_equal(
			"cli: flag port: 1.5 is not an integer"
		)?
	)
	(
		(failure(["serve", "a", "--mode", "x"])?) | expect_equal(
			"cli: flag mode: x is not one of dev, prod"
		)?
	)
	(
		(failure(["serve", "a", "--port"])?) | expect_equal(
			"cli: flag --port needs a value"
		)?
	)
	(failure(["serve", "a", "--nope"])?) | expect_equal("cli: unknown flag --nope")?
	(failure(["bogus"])?) | expect_equal("cli: unknown command bogus for tool")?
	(
		(failure(["remote", "bogus"])?)
		| expect_equal("cli: unknown command bogus for tool remote")?
	)

test "help is generated for groups, leaves and the help word":
	root := app().help() | expect_some?
	root | expect_contains("Usage:\n  tool <command> [flags]")?
	root | expect_contains("  serve   Run the server")?
	root | expect_contains("-v, --verbose  Print more")?

	leaf := app().help(["serve"]) | expect_some?
	leaf | expect_contains("Usage:\n  tool serve [flags] <root>")?
	leaf | expect_contains("-p, --port <int>       Listen port (default 8080)")?
	leaf | expect_contains("Global Flags:")?
	app().help(["nope"]) | expect_equal(none)?

	via_word := (run(["help", "serve"]) | expect_ok?)
	via_word.path[0] | expect_contains("tool serve")?

	group := (run(["remote"]) | expect_ok?)
	group.path[0] | expect_contains("Manage remotes")?

	flag := (run(["serve", "--help"]) | expect_ok?)
	flag.path[0] | expect_contains("Run the server")?

test "float flags reject NaN and infinities":
	ratio := Command(name: "x", flags: [Flag(name: "ratio", kind: FlagKind.Float)])
	for text in ["NaN", "Infinity", "-Infinity"]:
		(
			(ratio.parse(["--ratio", text.clone()]) | expect_error?).message
			| expect_equal("cli: flag ratio: {text} is not a number")?
		)

	_ := expect_ok(ratio.parse(["--ratio", "1e5"]))?
	bad_default := Command(
		name: "x",
		flags: [Flag(name: "ratio", kind: FlagKind.Float, default: "NaN")],
	)
	(
		(bad_default.parse([]) | expect_error?).message | expect_contains(
			"default NaN does not fit"
		)?
	)

test "schema mistakes are reported before parsing":
	duplicate := Command(
		name: "x",
		flags: [
			Flag(name: "a", kind: FlagKind.Bool),
			Flag(name: "a", kind: FlagKind.String),
		],
	)
	(duplicate.parse([]) | expect_error?).message | expect_contains("duplicate flag a")?

	bad_default := Command(
		name: "x",
		flags: [Flag(name: "n", kind: FlagKind.Int, default: "z")],
	)
	(
		(bad_default.parse([]) | expect_error?).message | expect_contains(
			"default z does not fit"
		)?
	)

	rest_first := Command(name: "x", args: [Arg(name: "a", rest: true), Arg(name: "b")])
	(rest_first.parse([]) | expect_error?).message | expect_contains("must be last")?

	order := Command(name: "x", args: [Arg(name: "a", required: false), Arg(name: "b")])
	(order.parse([]) | expect_error?).message | expect_contains("follows an optional")?

	reserved := Command(name: "x", children: [Command(name: "help")])
	(
		(reserved.parse([]) | expect_error?).message | expect_contains(
			"bad command name help"
		)?
	)

fn handled(argv: List[String]) Int!:
	tool := app()
	parsed := tool.parse(argv)
	if parsed.is_error(): return error(parsed.err().clone())

	match parsed.get():
		Run(matches): return tool.run(matches)
		Help(_): return ok(-1)

test "handlers receive the decoded options record":
	(handled(["serve", "site", "-p", "9090"]) | expect_ok?) | expect_equal(9090)?
	(handled(["serve", "site"]) | expect_ok?) | expect_equal(8080)?
	(handled(["-v", "serve", "site"]) | expect_ok?) | expect_equal(8080)?

test "optional, rest and dashed names decode into record fields":
	(handled(["remote", "add", "o"]) | expect_ok?) | expect_equal(0)?
	(
		(
			handled(
				["remote", "add", "o", "u", "x", "y", "--dry-run"]
			) | expect_ok?
		)
		| expect_equal(112)?
	)

test "a record that does not match the schema is reported when the handler runs":
	mismatched := command[ServeOptions](name: "bad", run: fn options: ok(0))
	tool := Command(name: "tool", children: [mismatched])
	parsed := (tool.parse(["bad"]) | expect_ok?)

	match parsed:
		Run(matches):
			(tool.run(matches) | expect_error?).message | expect_contains(
				"does not match"
			)?
		Help(_): return fail("help")

test "help rows without text carry no trailing spaces":
	quiet := Command(
		name: "t",
		args: [Arg("file")],
		children: [
			Command(name: "sub"),
			Command(name: "other-long", about: "Other"),
		],
	)
	text := quiet.help() | expect_some?
	text | expect_contains("  sub        \n".trim_end() + "\n")?
	text | expect_contains("  file\n")?
	for line in text.split("\n"):
		line | expect_equal(line.trim_end())?

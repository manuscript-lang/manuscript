// The `ms` command tree: every command, its flags and arguments, and the text that
// `ms help` and `--help` generate from them (@std/cli/command.ms). `main.ms` parses the
// command line with it and dispatches on the command it selects.
import (
	Arg, Command, Flag, FlagKind from "@std/cli/command.ms",
	expect_contains,
	expect_equal,
	expect_false,
	expect_ok,
	expect_some,
	expect_true,
	fail from "@std/test/test.ms",
)

fn flag(
	name: String,
	help: String,
	kind: FlagKind = FlagKind.String,
	short: String = "",
) Flag:
	return Flag(name: name, kind: kind, short: short, help: help)

fn switch(name: String, help: String) Flag:
	return Flag(name: name, kind: FlagKind.Bool, help: help)

fn json_flag(help: String) Flag:
	return switch("json", help)

fn output_flag(help: String) Flag:
	return flag("output", help, short: "o")

fn build_flags(build_help: String) List[Flag]:
	return [
		flag("build-type", build_help),
		flag(
			"link",
			"Link an object or static library that defines `extern fn` symbols (repeatable)",
			kind: FlagKind.List,
		),
		switch(
			"static",
			"Linux: link a static musl executable instead of the system glibc",
		),
	]

fn file_arg() Arg:
	return Arg("file", help: "A .ms file, or a project directory or ms.toml")

fn targets_arg() Arg:
	return Arg(
		"targets",
		help: "Files, directories or ms.toml; each keeps its own import root",
		rest: true,
	)

fn selection_flags(noun: String, timeout_help: String) List[Flag]:
	return [
		flag("filter", f"Run only {noun}s whose module::name contains text"),
		flag("timeout", timeout_help),
		flag(
			"test",
			f"Select exact module::name (repeatable)",
			kind: FlagKind.List,
		),
		flag("match", "Include names matching a regular expression"),
		flag("exclude", "Exclude names matching a regular expression"),
		switch("list", f"List selected {noun}s without running them"),
		switch("fail-fast", f"Stop after the first failed {noun}"),
		flag(
			"repeat",
			f"Run the selected {noun}s count times",
			kind: FlagKind.Int,
		),
	]

fn check_command() Command:
	return Command(
		name: "check",
		about: "Parse and type-check without executing",
		description: r"""
			Parse, resolve imports, and type-check independent inputs without executing source.
			A project directory selects ms.toml and checks all source modules, discovered tests, and its entry signature.
			Standalone directories discover .ms files recursively, skipping hidden/vendor/node_modules directories, directory symlinks, and nested projects.
			Each input retains its own import root; pass nested projects explicitly. Use -- before flag-like filenames.
			""",
		args: [targets_arg()],
		flags: [
			json_flag(
				"Emit versioned JSON diagnostics instead of terminal messages"
			),
			switch(
				"with-text",
				"With --json, also carry the terminal output as text.stdout and text.stderr",
			),
			switch(
				"each",
				"With --json --with-text, report every input as its own result from one standard-library load",
			),
			switch(
				"watch",
				"Recheck after each saved change to an input or loaded module (no --json)",
			),
			switch(
				"fix",
				"Apply machine-applicable fixes in place, then report what remains (no --watch)",
			),
		],
		examples: [
			"ms check main.ms --watch", "ms check main.ms", "ms check ms.toml --json",
			"ms check src utilities.ms --json"
		],
	)

fn lint_command() Command:
	return Command(
		name: "lint",
		about: "Check source hygiene and semantic lint rules",
		description: r"""
			Check source hygiene and semantic lint rules in independent inputs and their imports.
			A project directory selects ms.toml; standalone directories discover .ms files recursively. A project lints all its source modules and test files, imported or not.
			Discovery skips hidden/vendor/node_modules directories, directory symlinks, and nested projects.
			Each rule is a warning or an error (`severity` in --json; `ms explain MSL110` shows it). Warnings are reported
			without failing; exit status is 1 when any input fails checking or has an error finding, or any finding with --deny-warnings.
			""",
		args: [targets_arg()],
		flags: [
			json_flag(
				"Emit versioned JSON findings with stable rule codes"
			),
			switch(
				"watch",
				"Recheck after each saved change to an input or loaded module (no --json)",
			),
			switch("deny-warnings", "Treat warnings as errors (for CI)"),
			switch(
				"fix",
				"Apply machine-applicable fixes in place, then report what remains (no --watch)",
			),
		],
		examples: [
			"ms lint ms.toml", "ms lint main.ms --json",
			"ms lint src utilities.ms --json"
		],
	)

fn build_command() Command:
	return Command(
		name: "build",
		about: "Build a native executable",
		description: r"""
			Build an application exporting main() Int as a native executable.
			Builds link with the linker bundled in ms on every platform; no C compiler or SDK is needed.
			""",
		args: [file_arg()],
		flags: [
			output_flag(
				"Executable path (default: ./program; ./program.exe on Windows)"
			),
			json_flag(
				"Emit one versioned build result and artifact inventory"
			),
		].concat(
			build_flags(
				"Debug, Release, or MinSizeRel (case-insensitive; default Release)"
			)
		),
		examples: [
			"ms build ms.toml -o hello", "ms build main.ms --build-type MinSizeRel"
		],
	)

fn emit_command() Command:
	return Command(
		name: "emit",
		about: "Emit the lowered intermediate code as text",
		description: "Emit the lowered intermediate code of the program as text.",
		args: [file_arg()],
		flags: [
			output_flag("Write output to a file (default: stdout)"),
			json_flag(
				"On failure, emit versioned JSON diagnostics instead of terminal messages"
			),
		],
		examples: ["ms emit main.ms", "ms emit ms.toml -o main.mir"],
	)

fn run_command() Command:
	return Command(
		name: "run",
		about: "Build and run an application",
		description: r"""
			Build a temporary executable and run its exported main() Int.
			Arguments after -- are passed unchanged to the application; its exit status is returned.
			Builds link with the linker bundled in ms on every platform; no C compiler or SDK is needed.
			""",
		passthrough: true,
		args: [file_arg()],
		flags: [
			json_flag(
				"Capture output and emit one versioned result; a runtime fault is reported as data (no --watch)"
			),
			switch(
				"watch",
				"Rebuild and restart after each saved source change",
			),
		].concat(
			build_flags(
				"Debug, Release, or MinSizeRel (case-insensitive; default Debug, Cranelift, fast to build; Release uses LLVM)"
			)
		),
		examples: ["ms run ms.toml -- first second", "ms run main.ms --watch"],
	)

fn test_command() Command:
	return Command(
		name: "test",
		about: "Execute test blocks, including imported modules",
		description: r"""
			Build and execute test blocks in the module and its imported modules.
			More .ms files after the first build into the same executable and run in one invocation. Files run at once, each in its own promise; a file's tests run in order, and a fault ends its file.
			Tests run with the project directory (or the test file's directory) as the working directory, so relative fixture paths resolve there.
			Each test prints RUN before it starts and PASS or FAIL after; a test that exceeds the timeout fails by name.
			Arguments after -- are passed to the test executable; its exit status is returned.
			Builds link with the linker bundled in ms on every platform; no C compiler or SDK is needed.
			""",
		passthrough: true,
		args: [targets_arg()],
		flags: [
			json_flag(
				"Emit one versioned result; stdout is captured, stderr stays live (no --watch)"
			)
		]
		.concat(
			selection_flags(
				"test",
				"Fail a test that runs longer (default 60s; 0 disables)",
			)
		)
		.concat(
			[
				flag(
					"shuffle",
					"Shuffle with a reproducible integer seed",
					kind: FlagKind.Int,
				),
				flag(
					"runs",
					"Cases per property test from @std/test/property.ms (default 100)",
					kind: FlagKind.Int,
				),
				flag(
					"seed",
					"Start property tests at this integer seed to replay a failure",
					kind: FlagKind.Int,
				),
				flag(
					"fuzz",
					"Run each property for this long, with fresh seeds, instead of a fixed case count; disables the default --timeout",
				),
				switch(
					"watch",
					"Rebuild and rerun after each saved source change",
				),
			]
		)
		.concat(
			build_flags(
				"Debug, Release, or MinSizeRel (case-insensitive; default Debug, Cranelift, fast to build; Release uses LLVM)"
			)
		),
		examples: [
			"ms test test.ms", "ms test ms.toml --fuzz 30s",
			"ms test ms.toml --seed 1234 --filter \"sorting\"",
			"ms test ms.toml --build-type Release",
			"ms test ms.toml --filter \"nick collisions\" --timeout 10s"
		],
	)

fn bench_command() Command:
	return Command(
		name: "bench",
		about: "Run and time bench blocks, including imported modules",
		description: r"""
			Build and run bench blocks in the module and its imported modules. A project also loads bench.ms and *_bench.ms files.
			A bench body is one iteration: the @std/test/bench.ms driver repeats it until a sample takes --time (this calibration is the warmup),
			then times --samples samples and reports per-iteration min, median, mean, max, and standard deviation. One more counted run
			reports the runtime's work per operation: allocations, bytes allocated, list copies and string clones. These counts do not depend
			on machine load, so they can gate a build where times cannot.
			Each bench runs in its own process with the project directory (or the file's directory) as the working directory. A bench that
			fails (an error, a fault, or the timeout) fails by name. Standard output written by a bench is discarded.
			Arguments after -- are passed to the bench executable; its exit status is 1 when any bench failed.
			""",
		passthrough: true,
		args: [file_arg()],
		flags: [
			json_flag(
				"Emit one versioned result with each bench's statistics under stats (nanoseconds per iteration)"
			),
			flag(
				"time",
				"Target duration of one sample (default 100ms; at least 1ms)",
			),
			flag(
				"samples",
				"Timed samples per bench (default 10)",
				kind: FlagKind.Int,
			),
			flag(
				"iterations",
				"Fixed iterations per sample; skips calibration",
				kind: FlagKind.Int,
			),
			switch(
				"ops",
				"Build with a counter of the MIR operations the program executes and run each bench once; times of an --ops run are not meaningful",
			),
			flag(
				"baseline",
				"An earlier `--json` result; the run fails when a work count rose more than --fail-over (times are never compared)",
			),
			flag(
				"fail-over",
				"Rise over the baseline a work count may have, in percent (default 3)",
			),
			flag(
				"bench",
				"Select exact module::name (repeatable); --test is the same option",
				kind: FlagKind.List,
			),
		]
		.concat(
			selection_flags(
				"bench",
				"Fail a bench that runs longer (default 10m; 0 disables)",
			)
		)
		.concat(
			build_flags(
				"Debug, Release, or MinSizeRel (case-insensitive; default Release, which benchmarks should use)"
			)
		),
		examples: [
			"ms bench bench.ms", "ms bench ms.toml --filter \"parse\" --time 500ms",
			"ms bench ms.toml --json --samples 20 > bench.json",
			"ms bench ms.toml --baseline bench.json --fail-over 3"
		],
	)

fn fmt_command() Command:
	return Command(
		name: "fmt",
		about: "Format source files or a project",
		description: r"""
			Format selected source files in place, preserving their file permissions.
			Directories are recursive; projects include all source modules and test files.
			Discovery skips hidden, vendor, and node_modules directories.
			""",
		args: [targets_arg()],
		flags: [
			switch(
				"check",
				"Leave files unchanged; report every unformatted file and exit 1",
			),
			json_flag(
				"Emit versioned file statuses and diagnostics; requires --check"
			),
			switch(
				"drop-labels",
				"Also remove redundant argument labels such as key: key; needs source that checks",
			),
		],
		examples: [
			"ms fmt main.ms", "ms fmt ms.toml --check", "ms fmt src test.ms",
			"ms fmt src/*.ms --check"
		],
	)

fn verify_command() Command:
	return Command(
		name: "verify",
		about: "Run check, fmt --check, lint, and test; one result",
		description: r"""
			Run check, fmt --check, lint, and test on one target and report every step together.
			The target defaults to ms.toml. Lint and test are skipped when check fails; fmt always runs.
			With --json the document holds one entry per step with its status, exit code, and that command's own --json result.
			Exit status is 1 when any step fails.
			""",
		args: [
			Arg(
				"target",
				help: "A .ms file, directory or ms.toml (default ms.toml)",
				required: false,
			)
		],
		flags: [
			json_flag("Emit one versioned result with every step"),
			switch(
				"no-test",
				"Skip the test step (it builds a native executable)",
			),
			switch(
				"deny-warnings",
				"Fail the lint step on warnings, not only errors",
			),
		],
		examples: [
			"ms verify", "ms verify ms.toml --json", "ms verify src/main.ms --no-test"
		],
	)

fn inspect_command() Command:
	return Command(
		name: "inspect",
		about: "Emit checked source metadata as JSON",
		description: "Emit checked symbols, source hashes, call sites, and statement spans as JSON.",
		args: [file_arg()],
		flags: [
			output_flag("Write output to a file (default: stdout)"),
			json_flag(
				"On failure, emit versioned JSON diagnostics instead of terminal messages"
			),
		],
		examples: [
			"ms inspect main.ms", "ms inspect ms.toml -o inspection.json"
		],
	)

fn diagram_command() Command:
	return Command(
		name: "diagram",
		about: "Emit a static call graph as ascii or Mermaid",
		description: r"""
			Emit the checked static call graph of project declarations; standard calls are boundary leaves.
			The default ascii outline is plain text with a fixed order; mermaid is a flowchart for rendering.
			--view or --entity switch to one question's tree:
			overview (modules, their effects and cross-module calls), calls (who is called), effects (where effects enter), errors (error types and try sites),
			modules (imports), flow (one function's ordered steps), scope (its cleanup scopes and exits),
			tasks (its task groups and the work each spawn starts),
			types (alias: class; fields and cases that hold other types), ownership (alias: mutability; checked copy, borrow, move and var parameters; owned or borrowed results).
			flow, scope and tasks need --entity. --entity roots the tree at one declaration (name, file::name, or full entity ID file#kind#name; a module
			path for modules) and --depth bounds expansion (default 3, at most 200 nodes).
			An exact entity ID takes precedence over declaration names and qualified names.
			""",
		args: [file_arg()],
		flags: [
			flag(
				"view",
				"overview, calls, effects, errors, modules, flow, scope, tasks, types, or ownership (default calls with --entity)",
			),
			flag("entity", "Root the view at one declaration or module"),
			flag(
				"depth",
				"Expansion depth for a view (default 3)",
				kind: FlagKind.Int,
			),
			flag(
				"diff",
				"Mark what a unified diff changed, from a path or - for stdin (in a view, or in the html page; the tree is the after state)",
			),
			flag(
				"format",
				"ascii (default), mermaid, or html (one interactive page for the whole program)",
			),
			output_flag("Write output to a file (default: stdout)"),
			json_flag(
				"Emit a versioned diagram tree with source IDs and locations (default: calls view)"
			),
		],
		examples: [
			"ms diagram main.ms", "ms diagram ms.toml --format mermaid -o calls.mmd",
			"ms diagram ms.toml --view effects --entity save",
			"ms diagram ms.toml --view errors",
			"ms diagram ms.toml --format html -o map.html",
			"ms diagram ms.toml --view overview", "ms diagram ms.toml --view types",
			"ms diagram ms.toml --view ownership --entity save",
			"ms diagram ms.toml --view flow --entity main --depth 2",
			"ms diagram ms.toml --view flow --entity save --diff change.patch",
			"ms diagram ms.toml --view flow --entity save --json"
		],
	)

fn review_command() Command:
	return Command(
		name: "review",
		about: "Report where to look: project map, or the semantic effect of a diff",
		description: r"""
			Print a fixed-template report of where to look. Without --diff it maps the project:
			public surface, entry points with effects, error types, resources, imports.
			With a unified diff it compares the checked program before and after the change and
			ranks entities by contract, effect, error-flow, and resource changes and their reach.
			ms never runs git: pipe the diff in. The tree must be the diff's after state; the
			before state is rebuilt from the diff and verified. Output is deterministic, with no
			timestamps, absolute paths, or generated prose, and ends with a digest.
			""",
		args: [file_arg()],
		flags: [
			flag("diff", "Unified diff to review (- reads standard input)"),
			flag("format", "ascii (default) or markdown"),
			json_flag(
				"Emit the complete report or explanation as versioned JSON (not with --format)"
			),
			flag(
				"explain",
				"Show one finding in full by number or id: score terms, evidence, callers (needs --diff)",
			),
			flag(
				"effect",
				"Keep findings that reach or permit this effect name or pattern, e.g. std.net.* (needs --diff)",
			),
			switch(
				"all",
				"Show every row instead of the first five per section",
			),
			output_flag("Write output to a file (default: stdout)"),
		],
		examples: [
			"ms review ms.toml",
			"git diff --no-renames main... | ms review ms.toml --diff -",
			"ms review ms.toml --diff change.patch --format markdown",
			"ms review ms.toml --diff change.patch --explain 1",
			"ms review ms.toml --diff change.patch --explain 1 --json"
		],
	)

fn profile_command() Command:
	return Command(
		name: "profile",
		about: "Run with sampling profile capture: folded stacks, pprof, top report",
		description: r"""
			Build an application, run it with the sampling profiler enabled, and write a profile bundle.
			The runtime samples the program (MS_PROFILE is set to the folded-stack output path) and ms converts
			what it wrote: folded stacks, a pprof protobuf, and a text report of the busiest functions.
			The bundle contains program, profile.folded, profile.pb, top.txt, and manifest.json.
			The directory must be new. Native builds keep frame pointers, DWARF line tables and a perf map,
			so perf record works on any ms build output; ms profile prints the command for this program.
			Profiling adds overhead. Measure normal execution separately.
			Arguments after -- go to the application; its exit status is returned.
			Builds link with the linker bundled in ms on every platform; no C compiler or SDK is needed.
			""",
		passthrough: true,
		args: [file_arg()],
		flags: [
			flag("out-dir", "Bundle directory (default: ./profile)"),
			flag(
				"top",
				"Rows in the text report (default 20)",
				kind: FlagKind.Int,
			),
			switch(
				"allocs",
				"Also sample allocations: which functions allocate, in count and bytes",
			),
			json_flag(
				"Emit one versioned result; capture stdout, keep stderr live"
			),
			flag(
				"build-type",
				"Debug, Release, or MinSizeRel (case-insensitive; default Release)",
			),
		],
		examples: [
			"ms profile ms.toml",
			"ms profile main.ms --out-dir capture --top 10 -- first second"
		],
	)

fn init_command() Command:
	return Command(
		name: "init",
		about: "Create a new project with a manifest, entry, test, .gitignore, and .gitattributes",
		description: r"""
			Create a runnable project in the directory (default: the current directory).
			Writes ms.toml, src/main.ms (a hello program), test.ms, a .gitignore that excludes the
			.ms-cache/ build cache, and a .gitattributes that keeps source, manifests and the lock LF
			on Windows checkouts. An existing .gitignore or .gitattributes gets the lines appended.
			An existing file is never overwritten; the command fails before writing anything when
			ms.toml, src/main.ms, or test.ms exist.

			--lib creates a library, which a package must be: its ms.toml has no entry, and
			src/lib.ms holds a function and a test in place of main.

			--workspace creates a workspace: a root ms.toml listing the members, an app that
			imports a greeter library through a path dependency, and one shared ms.lock location
			at the root. Run `ms test` at the root to test every member.

			Keep .ms-cache/ out of version control.
			""",
		args: [
			Arg(
				"directory",
				help: "Where to create the project (default: the current directory)",
				required: false,
			)
		],
		flags: [
			switch(
				"lib",
				"Create a library with no entry, for sharing as a package",
			),
			switch(
				"workspace",
				"Create a workspace with an app member and a library member",
			),
		],
		examples: [
			"ms init", "ms init --lib greeter", "ms init --workspace team",
			"ms init hello", "cd hello && ms run ms.toml -- first second"
		],
	)

fn install_command() Command:
	return Command(
		name: "install",
		about: "Download the packages under [dependencies] and pin them in ms.lock",
		description: r"""
			Download the packages under [dependencies] with git and pin them in ms.lock.
			A version requirement picks the highest tag that satisfies every requirement of that
			repository in the whole graph, one copy for each compatible range (a new major is a
			separate copy). A lock entry that still satisfies them is kept, and it is downloaded
			at exactly its commit and fails if the content hash differs. Packages are cached read-only outside the project
			(MS_PACKAGE_CACHE overrides the location). Every other command works offline from
			the lock and the cache.
			""",
		args: [
			Arg(
				"manifest",
				help: "The project's ms.toml (default ms.toml)",
				required: false,
			)
		],
		flags: [
			flag(
				"update",
				"Pick the dependency @name's version again and rewrite its lock entry (repeatable)",
				kind: FlagKind.List,
			)
		],
	)

fn add_command() Command:
	return Command(
		name: "add",
		about: "Add a git dependency to ms.toml and install it",
		description: r"""
			Add a git dependency to ms.toml and install it. The package name defaults to the
			repository name without a leading ms- (https://github.com/acme/ms-pg.git is @pg).
			The package declares the effects it may use; ms prints them, and --allow writes
			them under [effects] so the project accepts them.
			""",
		args: [Arg("url", help: "The git repository")],
		flags: [
			flag(
				"version",
				"A semver requirement on the repository's tags: 1.2 means ^1.2, and ~1.2.3 and =1.2.3 are also allowed",
			),
			flag("tag", "Exactly this tag"),
			flag("sha", "Exactly this full 40-digit commit"),
			flag("as", "The name imports use (@name/file.ms)"),
			switch("allow", "Allow the effects the package declares"),
		],
	)

fn remove_command() Command:
	return Command(
		name: "remove",
		about: "Remove a dependency from ms.toml and ms.lock",
		description: r"""
			Remove a dependency from [dependencies] and [effects] in ms.toml and from ms.lock.
			The cached copy stays in the package cache.
			""",
		args: [Arg("name", help: "The dependency, written @name")],
	)

fn lsp_command() Command:
	return Command(
		name: "lsp",
		about: "Serve the language server on stdin/stdout",
		description: r"""
			Serve the language server over stdin/stdout until the client disconnects.
			Configure an LSP-capable editor to launch ms lsp. No file argument is needed.
			""",
		examples: ["ms lsp"],
	)

fn search_symbol_command() Command:
	return Command(
		name: "search_symbol",
		about: "Find a project or standard-library symbol: definition, type, uses",
		description: r"""
			Find a symbol, in the project or the standard library. Matching ignores case
			and tolerates partial names, small typos, missing underscores, and plain words
			(read file lines). Exact names rank first.
			  A project match prints its definition, type, description, and uses.
			  A standard-library match prints its signature and a path for details.
			  A lone module or declaration path shows its page, in bounded size:
			    ms search_symbol                 Standard modules, each with a few names
			    ms search_symbol json            One module: a line per declaration
			    ms search_symbol prelude.List    A declaration with its members
			    ms search_symbol prelude.List.sorted
			                                     One member's signature and doc
			Run it from the project directory, or any folder under its ms.toml.
			""",
		args: [
			Arg(
				"query",
				help: "A name, words, or a module or declaration path",
				required: false,
				rest: true,
			)
		],
		flags: [
			flag(
				"limit",
				"Maximum matches (default 5, at most 10)",
				kind: FlagKind.Int,
			),
			json_flag("Always search, and emit versioned JSON"),
		],
		examples: [
			"ms search_symbol parse_config", "ms search_symbol read file lines",
			"ms search_symbol json.parse"
		],
	)

fn explain_command() Command:
	return Command(
		name: "explain",
		about: "Explain diagnostic codes and their usual repairs",
		description: r"""
			For diagnostic codes from ms check --json or ms lint --json (MS and MSL),
			print each code's rule family and usual repair. Apply the diagnostic's own
			fix field first when it has one.
			""",
		args: [
			Arg(
				"code",
				help: "A diagnostic code such as MS3060 or MSL110",
				rest: true,
			)
		],
		flags: [json_flag("Emit versioned JSON")],
		examples: ["ms explain MS3060", "ms explain MS2001 MS3050 --json"],
	)

fn version_command() Command:
	return Command(
		name: "version",
		about: "Print the compiler version",
		description: "Print the compiler version. Equivalent to ms --version. Takes no arguments.",
		examples: ["ms version", "ms --version"],
	)

// The whole `ms` command line.
export fn spec() Command:
	return Command(
		name: "ms",
		about: "Manuscript checks, builds, and runs .ms source and ms.toml projects.",
		description: r"""
			Start with:
			  ms init hello
			  ms check ms.toml
			  ms run ms.toml -- first second

			Inside a project directory, commands that take a target default to ./ms.toml:
			  ms run -- first second

			Bare ms prints this help and exits successfully.
			Long options that take values also accept --flag=value.
			Run 'ms help <command>' or 'ms <command> --help' for usage and examples.
			Builds link with the linker bundled in ms on every platform; no C compiler or SDK is needed.
			MANUSCRIPT_CACHE_DIR selects the user cache for standalone run/test/profile artifacts.
			""",
		flags: [switch("version", "Print the compiler version")],
		children: [
			check_command(),
			lint_command(),
			build_command(),
			emit_command(),
			run_command(),
			test_command(),
			bench_command(),
			fmt_command(),
			verify_command(),
			inspect_command(),
			diagram_command(),
			review_command(),
			profile_command(),
			init_command(),
			install_command(),
			add_command(),
			remove_command(),
			lsp_command(),
			search_symbol_command(),
			explain_command(),
			version_command(),
		],
	)

// Whether the option `token` of `command` (`--name` or a one-letter `-o`) takes a
// value in the next argument, for scanning a command line before it is parsed.
export fn takes_value(root: Command, command: String, token: String) Bool:
	if token.contains("=") or not token.starts_with("-"): return false

	child := root.child(command)
	if child.is_none(): return false

	long := token.starts_with("--")
	key := token.view(if long: 2 else: 1, token.length())

	for flag in child.get().flags:
		if long and flag.name != key: continue
		if not long and flag.short != key: continue

		return flag.kind != FlagKind.Bool

	return false

test "the command tree is a valid schema and every command has help":
	root := spec()
	parsed := root.parse([]) | expect_ok?

	match parsed:
		Help(_): void
		Run(_): return fail("run")

	for child in root.children:
		text := root.help([child.name.clone()]) | expect_some?
		text | expect_contains("Usage:\n  ms " + child.name)?

test "takes_value reads the flag kinds of a command":
	root := spec()
	expect_true(takes_value(root, "build", "-o"))?
	expect_true(takes_value(root, "build", "--build-type"))?
	expect_false(takes_value(root, "build", "--json"))?
	expect_false(takes_value(root, "build", "--build-type=Debug"))?
	expect_false(takes_value(root, "check", "--link"))?
	expect_false(takes_value(root, "nope", "-o"))?

test "run keeps the words after dashes for the program":
	parsed := spec().parse(["run", "a.ms", "--json", "--", "x", "--y"]) | expect_ok?

	match parsed:
		Run(matches):
			matches.string("file") | expect_equal("a.ms")?
			matches.passthrough | expect_equal(["x", "--y"])?
		Help(_): return fail("help")

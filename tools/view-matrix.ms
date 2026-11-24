// View matrix (`make view-matrix`): generates one program for each combination of a
// view-producing operation (`trim`, `slice`, `split`, ...), a way of holding the short
// text it views (inline text lives in its own 16-byte value, so a view points into the
// slot that holds the value), and a set of later statements that make temporaries and
// so reuse the stack slots of earlier ones. Each program prints the view after those
// statements. The oracle is the expected text the table below carries, so a view that
// reads a reused or filled slot prints something else. Run it with MS_POISON_SLOTS=1
// (the tool sets it) in Debug (Cranelift) and Release (LLVM): poison turns a read of a
// dead slot into a wrong print on every build, not only on the build that happened to
// reuse it. A combination the checker rejects is fine; anything it accepts must print
// the expected text. A new view-returning operation belongs in OPERATIONS. MS names the
// ms that runs the programs (default .artifacts/build/ci/src/cli/ms). Usage: ms run
// tools/view-matrix.ms [-- name-filter]
import (
	stdout from "@std/io/io.ms",
	arguments, set_environment, working_directory from "@std/os/env.ms",
	temporary, write_file from "@std/os/fs.ms",
	run from "@std/os/process.ms",

	tool_ms from "./lib.ms",
)

HEADER := """
import print from "@std/core.ms"

fn mk(a: String, b: String) String:
    return a + b

fn show(v: String) Void:
    print(v)

"""

// One view operation on the text `s` (always " ab cd "): the statements that bind the
// view, the expression that prints it later and the text it must print.
type Operation:
	name String
	binds String
	shown String
	expected String

fn op(
	move name String,
	move binds String,
	move shown String,
	move expected String,
) Operation:
	return Operation(name, binds, shown, expected)

fn operations() List[Operation]:
	return [
		op("trim", "v := s.trim()", "v", "ab cd"),
		op("trim_start", "v := s.trim_start()", "v", "ab cd "),
		op("trim_end", "v := s.trim_end()", "v", " ab cd"),
		op("slice", "v := s.slice(1, 4)", "v", "ab "),
		op("split", "v := s.split(\" \")", "v.join(\"|\")", "|ab|cd|"),
		op(
			"trim_then_split",
			"t := s.trim()\n    v := t.split(\" \")",
			"v.join(\"|\")",
			"ab|cd",
		),
		op("trim_twice", "t := s.trim()\n    v := t.trim_start()", "v", "ab cd"),
	]

// A way to hold the text: statements that define `s`, and the function it runs in.
type Source:
	name String
	setup String
	params String
	caller String

fn sources() List[Source]:
	return [
		Source("concat_local", "s := \" ab\" + \" cd \"", "", "run()"),
		Source("call_local", "s := mk(\" ab\", \" cd \")", "", "run()"),
		Source("literal_local", "s := \" ab cd \"", "", "run()"),
		Source("parameter", "", "s: String", "run(mk(\" ab\", \" cd \"))"),
		// No variable holds the text: the call result is passed by value, so the
		// backend spills it into a slot of its own for the call.
		Source("temporary", "", "", "run()"),
	]

// Statements after the view that make short temporaries, each printed so none is
// dropped, and the text they print.
type Stomp:
	name String
	lines String
	expected List[String]

fn stomps() List[Stomp]:
	return [
		Stomp("none", "", []),
		Stomp(
			"concat",
			"t1 := \"x\".repeat(3) + \"y\"\n    t2 := t1 + \"z\"\n    print(t1)\n    print(t2)",
			["xxxy", "xxxyz"],
		),
		Stomp(
			"calls",
			"t1 := mk(\"p\", \"q\")\n    t2 := mk(t1, \"rs\")\n    t3 := mk(t2, t1)\n    print(t3)",
			["pqrspq"],
		),
		Stomp(
			"numbers",
			"t1 := f\"{41 + 1}\" + \"!\"\n    t2 := \"k\".repeat(2) + t1\n    print(t2)",
			["kk42!"],
		),
		// Temporaries in other blocks are the ones whose slots may share storage with
		// the view's own.
		Stomp(
			"branch",
			"n := mk(\"\", \"\").length() + 1\n    if n > 0:\n        t1 := mk(\"p\", \"q\") + \"rs\"\n        print(t1)\n    else:\n        t2 := \"x\".repeat(3) + \"y\"\n        print(t2)",
			["pqrs"],
		),
		Stomp(
			"loop",
			"for i in [1, 2]:\n        t1 := mk(\"a\", \"b\") + f\"{i}\"\n        print(t1)",
			["ab1", "ab2"],
		),
	]

fn program(o Operation, source Source, stomp Stomp) String:
	var body = ""
	if source.setup != "": body = f"    {source.setup}\n"

	var binds = o.binds.clone()
	if source.name == "temporary":
		binds = o.binds.replace("s.", "mk(\" ab\", \" cd \").")
	body = f"{body}    {binds}\n"
	if stomp.lines != "": body = f"{body}    {stomp.lines}\n"
	body = f"{body}    print({o.shown})\n"
	if source.name != "temporary": body = f"{body}    show(s)\n"
	return (
		f"{HEADER}fn run({source.params}) Void:\n{body}\nfn main() Void:\n    {source.caller}\n"
	)

fn expected(o Operation, source Source, stomp Stomp) String:
	var lines = List[String]()
	for line in stomp.expected: lines.append(line.clone())
	lines.append(o.expected.clone())
	if source.name != "temporary": lines.append(" ab cd ")
	return f"{lines.join("\n")}\n"

fn main() Int:
	root := working_directory().get()
	ms := tool_ms(root)
	scratch := temporary("ms-view-matrix-").get()
	set_environment("MS_POISON_SLOTS", "1").get()

	var filter = ""
	for a in arguments(): filter = a.clone()

	var checked = 0
	var rejected = 0
	var failures = 0

	for o in operations():
		for source in sources():
			for stomp in stomps():
				name := f"{o.name}_{source.name}_{stomp.name}"
				if filter != "" and not name.contains(filter): continue

				file := f"{scratch.path()}/{name}.ms"
				write_file(file, program(o, source, stomp)).wait().get()

				verdict := run(ms.clone(), ["check", file.clone()]).wait()

				if verdict.is_error() or verdict.get().exit_code != 0:
					rejected += 1

					why := verdict.get().stderr.decode_utf8() or ""

					// Only a checker rule may reject a combination; a program that does
					// not parse is this tool's bug.
					if why.contains(": parse:"):
						failures += 1
						(
							stdout()
							.write(
								f"generated: {name} does not parse: {why}\n"
							)
							.get()
						)
					else if filter != "":
						print(f"rejected {name}: {why}")

					continue

				want := expected(o, source, stomp)

				for build in ["debug", "release"]:
					checked += 1

					ran := run(
						ms.clone(),
						[
							"run",
							file.clone(),
							"--build-type",
							build.clone(),
						],
					).wait()

					if ran.is_error():
						failures += 1
						(
							stdout()
							.write(
								f"run: {name} ({build}) could not run {ms}\n"
							)
							.get()
						)
						continue

					child := ran.get()
					have := child.stdout.decode_utf8() or ""

					if child.exit_code != 0 or have != want:
						failures += 1

						why := child.stderr.decode_utf8() or ""
						(
							stdout()
							.write(
								f"view: {name} ({build}) printed {have.length()} bytes, wanted {want.length()}: a view read a reused or dead slot ({file})\n{why}\n"
							)
							.get()
						)

	(
		stdout()
		.write(
			f"matrix: {checked} runs, {rejected} combinations rejected by the checker, {failures} failing\n"
		)
		.get()
	)

	if checked == 0:
		print("no combination ran")
		return 1

	if failures > 0: return 1

	return 0

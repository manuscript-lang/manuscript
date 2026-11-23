// Close-once matrix (`make close-matrix`): generates one program for each combination
// of a resource shape (a bare resource, an Optional, a List, a record or a Result
// holding one) and a language construct that ends or moves its life (scope end, early
// return, `try` error, loop exits, reassignment, by-value argument, generic
// pass-through, returned owner, closure capture, escaping closure, promise capture,
// explicit close). A combination the checker rejects is fine; anything `ms check`
// accepts must run and close every resource it made exactly once, in Debug and Release.
// The oracle needs no expected output per case: `mk` prints `made-N`, the idempotent
// `close` prints `closed-N` the first time only, and every made id must close as often
// as it was made. A new construct that moves, drops or closes a value belongs in
// constructs() below. MS names the ms that runs the programs (default
// .artifacts/build/ci/src/cli/ms). Usage: ms run tools/close-matrix.ms [-- name-filter]
import (
	map_concurrent from "@std/concurrency/resilience.ms",
	stdout from "@std/io/io.ms",
	arguments, working_directory from "@std/os/env.ms",
	temporary, write_file from "@std/os/fs.ms",
	run from "@std/os/process.ms",
	system_info from "@std/os/system.ms",

	tool_ms from "./lib.ms",
)

HEADER := """
import Closeable, print from "@std/core.ms"
import promise from "@std/concurrency/promise.ms"
import sleep, milliseconds from "@std/time.ms"

type Marker:
    id: Int
    open: Bool

fn move Marker.close() Void!:
    if self.open:
        self.open = false
        print(f"closed-{self.id}")

type Holder:
    m: Marker

enum Slot:
    Full(m: Marker)
    Empty

fn mk_nested(id: Int) List[Marker?]:
    one: Marker? := mk(id)
    return [one]

fn mk_map(id: Int) Map[Int, Marker]:
    var m = Map[Int, Marker]()
    m.add(0, mk(id))
    return m

fn mk(id: Int) Marker:
    print(f"made-{id}")
    return Marker(id, true)

fn flag() Bool: return true

fn fail() Void!: return error(Error("x"))

fn ident[X](x: X) X: return x

fn pass[X](x: X) Void: return
"""

type Shape:
	name: String
	ty: String
	make: String

type Construct:
	name: String
	defs: String
	body: String
	only: String

fn shapes() List[Shape]:
	return [
		Shape("bare", "Marker", "mk(@ID@)"),
		Shape("optional", "Marker?", "mk(@ID@)"),
		Shape("list", "List[Marker]", "[mk(@ID@)]"),
		Shape("record", "Holder", "Holder(mk(@ID@))"),
		Shape("result", "Marker!Error", "ok(mk(@ID@))"),
		Shape("map", "Map[Int, Marker]", "mk_map(@ID@)"),
		Shape("enum", "Slot", "Full(mk(@ID@))"),
		Shape("nested", "List[Marker?]", "mk_nested(@ID@)"),
	]

fn c(move name: String, move defs: String, move body: String) Construct:
	return Construct(name, defs, body, "")

fn only(
	move name: String,
	move shape: String,
	move defs: String,
	move body: String,
) Construct:
	return Construct(name, defs, body, shape)

fn constructs() List[Construct]:
	return [
		c("scope_end", "", "x: @TY@ := @M1@\n    see(x)"),
		c(
			"early_return",
			"",
			"x: @TY@ := @M1@\n    if flag():\n        return ok()\n    see(x)",
		),
		c("try_error", "", "x: @TY@ := @M1@\n    fail()?\n    see(x)"),
		c(
			"loop_break",
			"",
			"for i in 0..3:\n        x: @TY@ := @M1@\n        if i == 1:\n            break\n        see(x)",
		),
		c(
			"loop_continue",
			"",
			"for i in 0..3:\n        x: @TY@ := @M1@\n        if i == 1:\n            continue\n        see(x)",
		),
		c(
			"while_loop",
			"",
			"var i = 0\n    while i < 2:\n        x: @TY@ := @M1@\n        see(x)\n        i += 1",
		),
		c(
			"loop_try_error",
			"",
			"for i in 0..3:\n        x: @TY@ := @M1@\n        fail()?\n        see(x)",
		),
		c(
			"nested_scope",
			"",
			"if flag():\n        x: @TY@ := @M1@\n        see(x)",
		),
		c(
			"loop_condition_try",
			"",
			"x: @TY@ := @M1@\n    var i = 0\n    while i < (fail_int()?):\n        see(x)\n        i += 1",
		),
		c(
			"break_nested_arms",
			"",
			"for i in 0..3:\n        x: @TY@ := @M1@\n        if i == 0:\n            if flag():\n                break\n            continue\n        see(x)",
		),
		c(
			"continue_nested_arms",
			"",
			"for i in 0..3:\n        x: @TY@ := @M1@\n        if i == 0:\n            if flag():\n                continue\n            break\n        see(x)",
		),
		c(
			"moved_in_one_branch_back_edge",
			"",
			"var x: @TY@ = @M1@\n    for i in 0..2:\n        if i == 0:\n            pass(x)\n            x = @M2@\n    see(x)",
		),
		c(
			"moved_in_one_branch_exit",
			"",
			"x: @TY@ := @M1@\n    for i in 0..2:\n        if i == 1:\n            pass(x)\n            return ok()\n    see(x)",
		),
		c(
			"loop_return",
			"",
			"for i in 0..2:\n        x: @TY@ := @M1@\n        if flag():\n            return ok()\n        see(x)",
		),
		c(
			"two_locals_try",
			"",
			"x: @TY@ := @M1@\n    y: @TY@ := @M2@\n    fail()?\n    see(x)\n    see(y)",
		),
		c(
			"boxed",
			"type Box:\n    v: @TY@",
			"b := Box(@M1@)\n    fail()?\n    see(b.v)",
		),
		c(
			"boxed_overwrite",
			"type Box:\n    v: @TY@",
			"var b = Box(@M1@)\n    b.v = @M2@\n    see(b.v)",
		),
		c(
			"in_list",
			"",
			"xs: List[@TY@] := [@M1@, @M2@]\n    fail()?\n    see_all(xs)",
		),
		c(
			"cancel_borrowed",
			"fn hold(x: @TY@) Void!:\n    sleep(milliseconds(60000)).wait()?\n    return ok()",
			"x: @TY@ := @M1@\n    p := promise(fn: hold(x))\n    p.cancel()\n    void p.wait()",
		),
		c(
			"cancel_owned",
			"fn hold(x: @TY@) Void!:\n    sleep(milliseconds(60000)).wait()?\n    return ok()",
			"p := promise(fn: hold(@M1@))\n    p.cancel()\n    void p.wait()",
		),
		c(
			"cancel_local",
			"fn hold() Void!:\n    x: @TY@ := @M1@\n    sleep(milliseconds(60000)).wait()?\n    see(x)\n    return ok()",
			"p := promise(fn: hold())\n    p.cancel()\n    void p.wait()",
		),
		c(
			"cancel_dropped",
			"fn hold() Void!:\n    x: @TY@ := @M1@\n    sleep(milliseconds(60000)).wait()?\n    see(x)\n    return ok()",
			"void promise(fn: hold())",
		),
		c("fn_value_temporary", "", "f := see\n    f(@M1@)"),
		c("fn_value_lambda", "", "f := fn (v: @TY@): see(v)\n    f(@M1@)"),
		c("fn_value_named", "", "f := see\n    x: @TY@ := @M1@\n    f(x)"),
		c(
			"method_temporary",
			"type Sink:\n    n: Int\n\nfn Sink.take(v: @TY@) Void: return\n\nfn Sink.take_later(v: @TY@, n: Int) Void: return",
			"Sink(0).take(@M1@)",
		),
		c(
			"method_later_try",
			"type Sink:\n    n: Int\n\nfn Sink.take(v: @TY@) Void: return\n\nfn Sink.take_later(v: @TY@, n: Int) Void: return",
			"Sink(0).take_later(@M1@, fail_int()?)",
		),
		c(
			"method_bound_later_try",
			"type Sink:\n    n: Int\n\nfn Sink.take_later(v: @TY@, n: Int) Void: return",
			"s := Sink(0)\n    f := s.take_later\n    f(@M1@, fail_int()?)",
		),
		c(
			"two_resources_try",
			"fn both(a: @TY@, b: @TY@, n: Int) Void: return",
			"both(@M1@, @M2@, fail_int()?)",
		),
		c(
			"generic_later_try",
			"fn gboth[X](a: X, n: Int) Void: return",
			"gboth[@TY@](@M1@, fail_int()?)",
		),
		c(
			"generic_to_optional",
			"fn opt_of[X](x: X) X?: return x",
			"r := opt_of[@TY@](@M1@)\n    if r.is_some():\n        return ok()",
		),
		c(
			"generic_to_optional_named",
			"fn opt_of[X](x: X) X?: return x",
			"x: @TY@ := @M1@\n    r := opt_of[@TY@](x)\n    if r.is_some():\n        return ok()",
		),
		c(
			"generic_to_list",
			"fn list_of[X](x: X) List[X]: return [x]",
			"r := list_of[@TY@](@M1@)\n    fail()?\n    see_all(r)",
		),
		c(
			"generic_to_result",
			"fn res_of[X](x: X) X!Error: return ok(x)",
			"r := res_of[@TY@](@M1@)\n    fail()?\n    if r.is_ok():\n        return ok()",
		),
		only(
			"interface_param",
			"bare",
			"fn via(c: Closeable) Void: return",
			"via(@M1@)",
		),
		only(
			"interface_param_later_try",
			"bare",
			"fn via(c: Closeable, n: Int) Void: return",
			"via(@M1@, fail_int()?)",
		),
		only(
			"bounded_generic",
			"bare",
			"fn gen[X: Closeable](x: X) Void: return",
			"gen(@M1@)",
		),
		only(
			"destructure",
			"record",
			"",
			"{m} := @M1@\n    fail()?\n    see_marker(m)",
		),
		only(
			"match_enum_return",
			"enum",
			"",
			"x: @TY@ := @M1@\n    match x:\n        Full(m): return ok()\n        Empty: return ok()",
		),
		only(
			"match_enum_temporary",
			"enum",
			"",
			"match @M1@:\n        Full(m): see_marker(m)\n        Empty: return ok()",
		),
		c("reassign", "", "var x: @TY@ = @M1@\n    x = @M2@\n    see(x)"),
		c(
			"reassign_branch",
			"",
			"var x: @TY@ = @M1@\n    if flag():\n        x = @M2@\n    see(x)",
		),
		c("argument_temporary", "", "see(@M1@)"),
		c("argument_named", "", "x: @TY@ := @M1@\n    see(x)\n    see(x)"),
		c(
			"two_arguments_try",
			"fn two(a: @TY@, n: Int) Void: return",
			"two(@M1@, fail_int()?)",
		),
		c(
			"returned_whole",
			"fn give() @TY@:\n    x: @TY@ := @M1@\n    return x",
			"y := give()\n    see(y)",
		),
		c(
			"returned_conditional",
			"fn give(f: Bool) @TY@:\n    x: @TY@ := @M1@\n    z: @TY@ := @M2@\n    if f:\n        return x\n    return z",
			"y := give(flag())\n    see(y)",
		),
		c(
			"returned_temporary",
			"fn give() @TY@:\n    return @M1@",
			"y := give()\n    see(y)",
		),
		c("generic_pass_temporary", "", "pass[@TY@](@M1@)"),
		c("generic_pass_named", "", "x: @TY@ := @M1@\n    pass(x)"),
		c("generic_ident_temporary", "", "y: @TY@ := ident(@M1@)\n    see(y)"),
		c(
			"generic_ident_named",
			"",
			"x: @TY@ := @M1@\n    y := ident(x)\n    see(y)",
		),
		c("discard_underscore", "", "_: @TY@ := @M1@"),
		c(
			"closure_borrow",
			"",
			"x: @TY@ := @M1@\n    f := fn: see(x)\n    f()",
		),
		c(
			"closure_escape",
			"fn make() fn() Void:\n    x: @TY@ := @M1@\n    return fn: see(x)",
			"f := make()\n    f()",
		),
		c(
			"closure_escape_unused",
			"fn make() fn() Void:\n    x: @TY@ := @M1@\n    return fn: see(x)",
			"f := make()\n    f()",
		),
		c(
			"promise_capture",
			"",
			"x: @TY@ := @M1@\n    p := promise(fn: seeok(x))\n    p.wait()?",
		),
		c(
			"promise_result",
			"fn produce() @TY@!: return ok(@M1@)",
			"p := promise(fn: produce())\n    y := p.wait()?\n    see(y)",
		),
		c(
			"promise_result_dropped",
			"fn produce() @TY@!: return ok(@M1@)",
			"p := promise(fn: produce())\n    void p.wait()",
		),
		only("explicit_close", "bare", "", "var x = @M1@\n    x.close()?"),
		only(
			"explicit_close_reassign",
			"bare",
			"",
			"var x = @M1@\n    x.close()?\n    x = @M2@\n    see(x)",
		),
		only(
			"interface_view",
			"bare",
			"",
			"var x: Closeable = @M1@\n    x.close()?",
		),
		only(
			"if_let",
			"optional",
			"",
			"x: @TY@ := @M1@\n    if m := x:\n        see_marker(m)",
		),
		only(
			"match_optional",
			"optional",
			"",
			"x: @TY@ := @M1@\n    match x:\n        m: see_marker(m)\n        none: return ok()",
		),
		only("field_move", "record", "", "h := @M1@\n    see_marker(h.m)"),
		only(
			"field_overwrite",
			"record",
			"",
			"var h = @M1@\n    h.m = mk(2)\n    see(h)",
		),
		only(
			"list_for",
			"list",
			"",
			"xs := @M1@\n    for m in xs:\n        see_marker(m)",
		),
		only(
			"list_for_break",
			"list",
			"",
			"xs := @M1@\n    for m in xs:\n        break",
		),
		only(
			"result_match",
			"result",
			"",
			"r: @TY@ := @M1@\n    match r:\n        ok(m): see_marker(m)\n        error(e): return ok()",
		),
	]

// The program for `construct` applied to `shape`.
fn program(shape: Shape, construct: Construct) String:
	see := "fn see(x: @TY@) Void: return\n\nfn see_all(xs: List[@TY@]) Void: return\n\nfn seeok(x: @TY@) Void!: return ok()\n\nfn see_marker(m: Marker) Void: return\n\nfn fail_int() Int!: return error(Error(\"x\"))\n"
	m1 := shape.make.replace("@ID@", "1")
	m2 := shape.make.replace("@ID@", "2")
	var text = f"{HEADER}\n{see}\n{construct.defs}\n\nfn body() Void!:\n    {construct.body}\n    return ok()\n\nfn run() Void:\n    void body()\n\nexport fn main() Int:\n    run()\n    return 0\n"
	text = text.replace("@TY@", shape.ty).replace("@M1@", m1).replace("@M2@", m2)
	return text

// How many times `prefix` + `id` appears as a line.
fn count(lines: List[String], prefix: String) Map[String, Int]:
	var counts = Map[String, Int]()

	for line in lines:
		if not line.starts_with(prefix): continue

		key := line.trim()
		counts.add(key.clone(), counts.get_or(key.clone(), 0) + 1)

	return counts

// One combination to try and what happened when it ran: counts, and the lines to print
// in order.
type Cell:
	shape: Shape
	construct: Construct
	name: String

type Tally:
	checked: Int
	rejected: Int
	failures: Int
	lines: List[String]

// Runs one combination: `ms check`, then the program in Debug and Release. Independent
// of every other combination, so the matrix runs them concurrently.
fn verify(ms: String, scratch: String, cell: Cell, show: Bool, filter: String) Tally:
	var tally = Tally(0, 0, 0, [])
	name := cell.name.clone()
	file := f"{scratch}/{name}.ms"
	write_file(file, program(cell.shape.clone(), cell.construct.clone())).wait().get()

	verdict := run(ms.clone(), ["check", file.clone()]).wait()

	if verdict.is_error() or verdict.get().exit_code != 0:
		tally.rejected += 1

		why := verdict.get().stderr.decode_utf8().get_or("")

		if why.contains(": parse:"):
			tally.failures += 1
			tally.lines.append(f"generated: {name} does not parse: {why}\n")
		else if show or filter != "":
			tally.lines.append(f"rejected {name}: {why.split("\n")[0]}\n")

		return tally

	for build in ["debug", "release"]:
		tally.checked += 1

		ran := run(ms.clone(), ["run", file.clone(), "--build-type", build.clone()]).wait()

		if ran.is_error():
			tally.failures += 1
			tally.lines.append(f"run: {name} ({build}) could not run {ms}\n")
			continue

		child := ran.get()
		lines := child.stdout.decode_utf8().get_or("").split("\n")

		if child.exit_code != 0:
			tally.failures += 1

			why := child.stderr.decode_utf8().get_or("")
			(
				tally.lines.append(
					f"exit: {name} ({build}) passed `ms check` but failed: {why}\n"
				)
			)
			continue

		made := count(lines, "made-")
		closed := count(lines, "closed-")
		var wrong = false

		for key in made.keys():
			id := key.slice(5, key.length())
			if made.get_or(key.clone(), 0) != closed.get_or(f"closed-{id}", 0): wrong = true

		if closed.length() != made.length(): wrong = true

		if wrong:
			tally.failures += 1
			(
				tally
				.lines
				.append(
					f"ownership: {name} ({build}) made {made.length()} ids and closed {closed.length()}; each resource must close once ({file})\n"
				)
			)

	return tally

fn main() Int:
	root := working_directory().get()
	ms := tool_ms(root)
	scratch := temporary("ms-close-matrix-").get()
	var filter = ""
	var show = false

	for a in arguments():
		if a == "rejects": show = true
		else: filter = a.clone()

	var cells: List[Cell] = []

	for shape in shapes():
		for construct in constructs():
			if construct.only != "" and construct.only != shape.name: continue

			name := f"{construct.name}_{shape.name}"
			if filter != "" and not name.contains(filter): continue

			cells.append(Cell(shape.clone(), construct.clone(), name))

	// Each combination compiles and links two programs, so the matrix is bound by the
	// build, not by this
	// loop: run as many at a time as there are cores.
	scratch_path := scratch.path()
	tallies := map_concurrent(
		cells,
		system_info().cpu_count,
		fn cell: verify(
			ms.clone(),
			scratch_path.clone(),
			cell,
			show,
			filter.clone(),
		)
	).get()
	var checked = 0
	var rejected = 0
	var failures = 0

	for tally in tallies:
		checked += tally.checked
		rejected += tally.rejected
		failures += tally.failures
		for line in tally.lines:
			stdout().write(line.clone()).get()

	(
		stdout()
		.write(
			f"close-matrix: {checked} runs, {rejected} combinations rejected by the checker, {failures} failing\n"
		)
		.get()
	)

	if checked == 0:
		print("no combination ran")
		return 1

	if failures > 0: return 1

	return 0

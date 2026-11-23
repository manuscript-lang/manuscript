// Ownership fuzz (`make ownership-fuzz`): writes random programs that mix moves,
// borrows, closures, returned parts and temporaries over strings, lists and nested
// records, then runs every program the checker accepts in Debug (Cranelift) and Release
// (LLVM) and fails on a crash, a wrong printed line, output that differs between the
// builds, or (with the counting runtime that tools/leak-check.ms also builds) a block
// left live at exit. Every value is a long text of the form
// `<prefix><number>-<letters>`, so any printed line that does not match that shape, or
// a bare number, is a borrow that read freed or reused storage. The checker rejects
// most programs (use after move, a borrow held over a change); only the rest run.
// Arguments: seed (default 1) and count (default 200). MS names the ms that runs the
// programs (default .artifacts/build/ci/src/cli/ms). Usage: ms run
// tools/ownership-fuzz.ms [-- seed count]
import (
	arguments, working_directory from "@std/os/env.ms",
	temporary, write_file from "@std/os/fs.ms",
	run from "@std/os/process.ms",
	SeededRandom, seeded from "@std/random.ms",

	tool_ms, use_stats_runtime from "./lib.ms",
)

HEADER := """
type P:
	name: String
	tags: List[String]

type W:
	p: P
	o: String?

fn eat(move s: String) Int:
	return s.length()

fn peek(s: String) Int:
	return s.length()

fn pick(a: String, b: String) String:
	return a

fn part(p: P) String:
	return p.name

fn tag0(p: P) String:
	return p.tags[0]

fn first_of(xs: List[String]) String?:
	return xs.first()

fn grow(var xs: List[String], move s: String) Void:
	xs.append(s)

fn rename(var p: P, move s: String) Void:
	p.name = s

fn mkp(move s: String) P:
	t := s.clone()
	return P(s, [t])

fn wrap(move p: P) W:
	return W(p, none)

fn upd(var w: W, move s: String) Void:
	w.o = s

fn mkw(n: Int) W:
	return W(P(f"wn{n}-ffffffffffffffffffffffffffffff", [f"wt{n}-gggggggggggggggggggggggggg"]), f"wo{n}-hhhhhhhhhhhhhhhhhhhhhhhhhhhh")

fn mkl(n: Int) List[String]:
	return [f"e{n}-cccccccccccccccccccccccccccccc", f"e{n}-cccccccccccccccccccccccccccccd"]

fn ret_cl(s: String) fn() Int:
	return fn(): s.length()

"""
// Expressions that read a part of a temporary; `K` stands for a fresh number.
TEMPORARIES := [
	"mkw(K).p.name", "mkw(K).p.tags[0]", "mkw(K).o.get()",
	"part(mkp(f\"q{K}-jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj\"))", "mkl(K)[0]",
	"mkl(K).first().get()", "part(mkw(K).p)", "pick(mkl(K)[0], mkl(K)[1])",
	"wrap(mkp(f\"q{K}-jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj\")).p.name",
	"mkp(f\"q{K}-jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj\").tags.first().get()"
]

// The names in scope, by kind, and the owned ones already moved away.
type Gen:
	rng: SeededRandom
	lines: List[String]
	strings: List[String]
	lists: List[String]
	records: List[String]
	wrappers: List[String]
	optionals: List[String]
	dead: List[String]
	serial: Int

// Adds one statement.
fn var Gen.emit(move line: String) Void:
	self.lines.append(line)

fn var Gen.fresh(prefix: String) String:
	self.serial += 1
	return f"{prefix}{self.serial}"

// The names of one kind: 0 strings, 1 lists, 2 records, 3 wrappers, 4 optionals.
fn Gen.names(kind: Int) List[String]:
	if kind == 0: return self.strings.clone()
	if kind == 1: return self.lists.clone()
	if kind == 2: return self.records.clone()
	if kind == 3: return self.wrappers.clone()

	return self.optionals.clone()

// A random name of a kind, or "" when there is none. A moved name is skipped.
fn var Gen.any(kind: Int) String:
	var live = List[String]()
	for n in self.names(kind):
		if not self.dead.contains(n): live.append(n.clone())
	if live.length() == 0: return ""

	return live[self.rng.int(0, live.length())].clone()

// A string to move: an owned name that dies here, else a copy of a borrowed one.
fn var Gen.moved() String:
	var owned = List[String]()
	for n in self.strings:
		if not self.dead.contains(n) and not n.starts_with("b"): owned.append(n.clone())

	if owned.length() == 0:
		borrowed := self.any(0)
		if borrowed == "": return self.text("str", "a")

		return f"{borrowed}.clone()"

	name := owned[self.rng.int(0, owned.length())].clone()
	self.dead.append(name.clone())
	return name

fn var Gen.text(prefix: String, letters: String) String:
	self.serial += 1
	return f"f\"{prefix}\{{self.serial}\}-{letters.repeat(30)}\""

fn var Gen.step() Void:
	pick := self.rng.int(0, 38)
	s := self.any(0)
	l := self.any(1)
	p := self.any(2)
	w := self.any(3)
	o := self.any(4)

	if pick < 3:
		v := self.fresh("s")
		h1 := self.text("str", "a")
		self.emit(f"{v} := {h1}")
		self.strings.append(v)
	else if pick < 5:
		v := self.fresh("sv")
		h1 := self.text("str", "b")
		self.emit(f"var {v} = {h1}")
		self.strings.append(v)
	else if pick < 7:
		v := self.fresh("l")
		h1 := self.text("e", "c")
		self.emit(f"var {v}: List[String] = [{h1}]")
		self.lists.append(v)
	else if pick < 9:
		v := self.fresh("p")
		h1 := self.text("n", "d")
		h2 := self.text("t", "e")
		self.emit(f"var {v} = P({h1}, [{h2}])")
		self.records.append(v)
	else if pick < 10:
		v := self.fresh("w")
		self.emit(f"var {v} = mkw({self.serial})")
		self.wrappers.append(v)
	else if pick < 12 and s != "":
		v := self.fresh("b")
		self.emit(f"{v} := {s}")
		self.strings.append(v)
	else if pick < 14 and p != "":
		v := self.fresh("b")
		self.emit(f"{v} := {p}.{["name", "tags[0]"][self.rng.int(0, 2)]}")
		self.strings.append(v)
	else if pick < 15 and l != "":
		v := self.fresh("b")
		self.emit(f"{v} := {l}[0]")
		self.strings.append(v)
	else if pick < 16 and w != "":
		v := self.fresh("b")
		self.emit(f"{v} := {w}.p.name")
		self.strings.append(v)
	else if pick < 18 and l != "":
		h1 := self.moved()
		self.emit(f"{l}.append({h1})")
	else if pick < 19 and l != "" and s != "":
		self.emit(f"{l}.append({s}.clone())")
	else if pick < 20:
		h1 := self.moved()
		self.emit(f"print(f\"\{eat({h1})\}\")")
	else if pick < 21 and s != "":
		self.emit(f"print(f\"\{peek({s})\}\")")
	else if pick < 22 and s != "":
		v := self.fresh("b")
		h1 := self.any(0)
		self.emit(f"{v} := pick({s}, {h1})")
		self.strings.append(v)
	else if pick < 23 and p != "":
		v := self.fresh("b")
		self.emit(f"{v} := {["part", "tag0"][self.rng.int(0, 2)]}({p})")
		self.strings.append(v)
	else if pick < 24 and l != "":
		v := self.fresh("o")
		self.emit(f"{v} := first_of({l})")
		self.optionals.append(v)
	else if pick < 25 and o != "":
		self.emit(f"if q := {o}:\n\t\tprint(q)")
	else if pick < 26 and l != "":
		h1 := self.moved()
		self.emit(f"grow(var {l}, {h1})")
	else if pick < 27 and p != "":
		h1 := self.moved()
		self.emit(f"rename(var {p}, {h1})")
	else if pick < 28 and p != "":
		v := self.fresh("w")
		self.emit(f"var {v} = wrap({p})")
		self.wrappers.append(v)
	else if pick < 29 and w != "":
		h1 := self.moved()
		self.emit(f"upd(var {w}, {h1})")
	else if pick < 30 and s != "":
		v := self.fresh("c")
		self.emit(f"{v} := fn(): {s}.length()\n\tprint(f\"\{{v}()\}\")")
	else if pick < 31:
		v := self.fresh("c")
		h1 := self.moved()
		self.emit(f"{v} := ret_cl({h1})\n\tprint(f\"\{{v}()\}\")")
	else if pick < 32 and l != "":
		self.emit(f"for x in {l}:\n\t\tprint(x)")
	else if pick < 33 and l != "":
		h1 := self.text("z", "i")
		self.emit(f"{l} = [{h1}]")
	else if pick < 34 and p != "":
		h1 := self.moved()
		self.emit(f"{p}.tags.append({h1})")
	else if pick < 35 and w != "":
		self.emit(f"if q := {w}.o:\n\t\tprint(q)")
	else if pick < 37:
		body := TEMPORARIES[self.rng.int(0, TEMPORARIES.length())].replace(
			"K",
			f"{self.serial + 1}",
		)
		self.serial += 1
		self.temporary(body)
	else if s != "":
		self.emit(f"print({s})")

// One use of the temporary expression `body`: printed, bound, cloned, listed or passed.
fn var Gen.temporary(body: String) Void:
	use := self.rng.int(0, 5)
	l := self.any(1)

	if use == 0:
		self.emit(f"print({body})")
	else if use == 1:
		v := self.fresh("b")
		self.emit(f"{v} := {body}")
		self.strings.append(v)
	else if use == 2:
		v := self.fresh("b")
		self.emit(f"{v} := {body}.clone()")
		self.strings.append(v)
	else if use == 3 and l != "":
		self.emit(f"{l}.append({body}.clone())")
	else:
		self.emit(f"print(f\"\{peek({body})\}\")")

// Reads every binding that is still whole, so none is reported as unused.
fn var Gen.finish() Void:
	for s in self.strings:
		if not self.dead.contains(s): self.lines.append(f"print({s})")
	for l in self.lists: self.lines.append(f"print(f\"\{{l}.length()\}\")")
	for p in self.records: self.lines.append(f"print({p}.name)")
	for w in self.wrappers: self.lines.append(f"print({w}.p.name)")
	for o in self.optionals: self.lines.append(f"if q := {o}:\n\t\tprint(q)")

fn program(seed: Int) String:
	var g = Gen(seeded(seed), [], [], [], [], [], [], [], 0)
	for i in 0..g.rng.int(8, 18): g.step()
	g.finish()

	body := g.lines.map(fn line: f"\t{line}").join("\n")
	return f"{HEADER}fn main() Void:\n{body}\n"

// Whether `line` has the shape every value prints with.
fn well_formed(line: String) Bool:
	if line == "": return true
	if line.parse_int() != null: return true

	dash := line.index_of("-")
	if dash == null: return false

	for c in line.slice(dash.get() + 1, line.length()).chars():
		if c < "a" or c > "j": return false
	return true

fn main() Int:
	code := use_stats_runtime()
	if code != 0: return code

	root := working_directory().get()
	ms := tool_ms(root)
	scratch := temporary("ms-ownership-fuzz-").get()
	var seed = 1
	var count = 200
	args := arguments()
	if args.length() > 0: seed = args[0].parse_int() or 1
	if args.length() > 1: count = args[1].parse_int() or 200

	var ran = 0
	var rejected = 0
	var failures = 0

	for i in 0..count:
		name := f"p{seed}_{i}"
		file := f"{scratch.path()}/{name}.ms"
		write_file(file, program(seed * 100000 + i)).wait().get()

		verdict := run(ms.clone(), ["check", file.clone()]).wait()

		if verdict.is_error() or verdict.get().exit_code != 0:
			rejected += 1

			why := verdict.get().stderr.decode_utf8() or ""

			if why.contains(": parse:") or why.contains("internal"):
				failures += 1
				print(f"{name}: generated program is broken: {why}")

			continue

		var outputs = List[String]()

		for build in ["debug", "release"]:
			ran += 1

			child := run(
				ms.clone(),
				["run", file.clone(), "--build-type", build.clone()],
			).wait().get()
			text := child.stdout.decode_utf8() or ""
			err := child.stderr.decode_utf8() or ""
			var problem = ""
			if child.exit_code != 0: problem = f"exit {child.exit_code}"
			for line in text.split("\n"):
				if not well_formed(line): problem = f"printed {line}"
			for line in err.split("\n"):
				if (
					line.starts_with("ms-rt live blocks at exit: ")
					and not line.ends_with(": 0")
				):
					problem = line.clone()

			if problem != "":
				failures += 1
				print(f"{name} ({build}): {problem}\n{file}")

			outputs.append(text)

		if outputs[0] != outputs[1]:
			failures += 1
			print(f"{name}: Debug and Release print different output ({file})")

	print(
		f"ownership-fuzz: {ran} runs, {rejected} programs rejected by the checker, {failures} failing"
	)
	if ran == 0: return 1
	if failures > 0: return 1

	return 0

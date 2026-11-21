// `ms review`: classifies what changed between a base and a head program and ranks it.
// Port of crates/ms-tooling/src/review.rs and review/reach.rs; the Rust code is the
// oracle (`ms-tooling-dev review BASE HEAD ...`, same arguments).
//
// Until the C checker builds the facts, they are read from the JSON files
// `ms-tooling-dev facts FILE` prints.
//   ms run src/ms/review.ms -- BASE.json HEAD.json [--no-base] [--added FILE]... [--touch FILE:LINE]...
import (
	Arg, Command, Flag, FlagKind, Matches from "@std/cli/command.ms",
	parse from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	read_file from "@std/os/fs.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	run_tool from "./cli.ms",
	json_string from "./docgen.ms",
	Fact, Facts from "./views.ms",
)

// Tiers, highest attention first. The weights are the whole ranking policy.
export TIERS := ["CONTRACT", "EFFECT+", "ERROR", "RESOURCE", "INTERNAL"]

export fn tier_rank(tier: String) Int:
	for i in 0..TIERS.length():
		if TIERS[i] == tier: return i
	return 0

// One changed entity with every reason it needs attention.
export type Finding:
	id: String
	entity: String
	location: String
	tier: String = ""
	changes: List[String] = []
	reach: Int = 0
	score: Int = 0
	terms: List[String] = []
	evidence: List[String] = []

// The changed-file information a diff review needs. `touched` maps a file to its
// changed head lines.
export type DiffInput:
	added: Set[String]
	touched: Map[String, List[Int]]
	base_checked: Bool

type Scorer:
	finding: Finding
	tiers: List[String] = []
	weights: List[Int] = []

fn var Scorer.add(tier: String, change: String, term: String, weight: Int) Void:
	self.finding.changes.append(change)
	self.finding.terms.append(f"{term} +{weight}")
	self.tiers.append(tier.clone())
	self.weights.append(weight)
	self.finding.score += weight

// The highest tier with more than one point of weight, else INTERNAL.
fn Scorer.tier() String:
	var best = "INTERNAL"
	for i in 0..self.tiers.length():
		if self.weights[i] > 1 and tier_rank(self.tiers[i]) < tier_rank(best): best = (
			self
			.tiers[i]
			.clone()
		)
	return best

PAD := "    "

fn visibility(exported: Bool) String: if exported: "exported" else: "private"

fn or_none(text: String) String: if text.is_empty(): "none" else: text.clone()

// Entries of `head` that `base` lacks.
fn added_of(head: List[String], base: List[String]) List[String]:
	var out = List[String]()
	for e in head:
		if not base.contains(e): out.append(e.clone())
	return out

fn joined(items: List[String]) String: items.join(", ")

fn has_any(have: List[String], want: List[String]) Bool:
	for w in want:
		if have.contains(w): return true
	return false

type Index:
	facts: Facts
	by_key: Map[String, Int]

fn index_of(facts: Facts) Index:
	var by_key = Map[String, Int]()
	for i in 0..facts.entities.length(): by_key.add(facts.entities[i].key.clone(), i)
	return Index(facts: facts, by_key: by_key)

fn Index.get(key: String) Fact?:
	if i := self.by_key.get(key): return self.facts.entities[i].clone()
	return none

// The first callee of `current` not yet seen that carries a gained effect.
fn gained_callee(
	current: Fact,
	seen: Set[String],
	gained: List[String],
	head: Index,
) Fact?:
	for key in current.calls:
		if seen.contains(key): continue

		callee := head.get(key).get_or(empty())
		if not callee.key.is_empty() and has_any(callee.reach, gained): return callee

	return none

// Follows callees that carry a gained effect down to the native operation or boundary
// where it enters, choosing the first name at each step.
fn effect_path(start: Fact, gained: List[String], head: Index) String:
	var path = [start.name.clone()]
	var seen = Set[String]()
	seen.add(start.key.clone())

	var current = start.clone()

	while true:
		next := gained_callee(current, seen, gained, head)
		if next.is_none(): break

		found := next.get_or(empty())
		seen.add(found.key.clone())
		path.append(found.name.clone())
		current = found

	if not current.external.is_empty(): path.append(current.external[0].clone())
	return f"path: {path.join(" -> ")}"

fn compare(h: Fact, b: Fact, var s: Scorer) Void:
	if h.exported != b.exported: s.add(
		"CONTRACT",
		f"visibility: {visibility(b.exported)} -> {visibility(h.exported)}",
		"contract",
		8,
	)

	if h.ty != b.ty:
		if h.exported: s.add("CONTRACT", f"type: {b.ty} -> {h.ty}", "contract", 8)
		else: s.add("INTERNAL", f"private type: {b.ty} -> {h.ty}", "signature", 1)

	permits := added_of(h.permits, b.permits)
	if not permits.is_empty(): s.add(
		"EFFECT+",
		f"permits: + {joined(permits)}",
		"effect_permit",
		7,
	)

	reach := added_of(h.reach, b.reach)
	if not reach.is_empty(): s.add(
		"EFFECT+",
		f"reaches: + {joined(reach)}",
		"effect_reach",
		6,
	)
	if h.error != b.error: s.add(
		"ERROR",
		f"error type: {or_none(b.error)} -> {or_none(h.error)}",
		"error_flow",
		5,
	)
	if h.tries != b.tries: s.add(
		"ERROR",
		f"try sites: {b.tries} -> {h.tries}",
		"error_flow",
		5,
	)
	if h.scopes != b.scopes: s.add(
		"RESOURCE",
		f"resource scopes: {b.scopes} -> {h.scopes}",
		"resource",
		4,
	)

// The finding for one key and whether it is scored (a change worth a reach count).
type Classified:
	finding: Finding
	scored: Bool

fn classify(key: String, base_checked: Bool, head: Index, h: Fact?, b: Fact?) Classified:
	var subject = empty()
	if bs := b: subject = bs.clone()
	if hs := h: subject = hs.clone()

	var s = Scorer(
		finding: Finding(
			id: key.clone(),
			entity: subject.name.clone(),
			location: f"{subject.file}:{subject.line}",
		)
	)

	if hf := h:
		if bf := b: compare(hf, bf, s)
		else if base_checked:
			s.add("INTERNAL", "added", "added", 1)
			if not hf.permits.is_empty(): s.add(
				"EFFECT+",
				f"permits: + {joined(hf.permits)}",
				"effect_permit",
				7,
			)
			if not hf.reach.is_empty(): s.add(
				"EFFECT+",
				f"reaches: + {joined(hf.reach)}",
				"effect_reach",
				6,
			)
			if hf.exported: s.add(
				"CONTRACT",
				f"added exported {hf.kind}",
				"contract",
				8,
			)
	else if bf := b:
		s.add("INTERNAL", "removed", "removed", 1)
		if bf.exported: s.add("CONTRACT", f"removed exported {bf.kind}", "contract", 8)

	if h.is_none():
		s.finding.tier = s.tier()
		return Classified(finding: s.finding.clone(), scored: false)

	hv := h.get_or(empty())

	if bv := b:
		reach := added_of(hv.reach, bv.reach)
		if not reach.is_empty(): s.finding.evidence.append(effect_path(hv, reach, head))

	scored := not s.finding.changes.is_empty() and s.finding.score > 1
	s.finding.tier = s.tier()
	return Classified(finding: s.finding.clone(), scored: scored)

// The number of distinct project entities that transitively call this entity.
fn reach_count(key: String, callers: Map[String, List[String]]) Int:
	var seen = Set[String]()
	seen.add(key.clone())

	var queue = [key.clone()]
	var next = 0

	while next < queue.length():
		current := queue[next].clone()
		next += 1

		if list := callers.get(current):
			for caller in list:
				if seen.contains(caller): continue

				seen.add(caller.clone())
				queue.append(caller.clone())

	return queue.length() - 1

// Maps changed head lines to the most specific entity containing them: the shortest
// range, then the smallest key.
fn touched_keys(head: Facts, touched: Map[String, List[Int]]) Set[String]:
	var result = Set[String]()

	for file in touched.keys():
		lines := touched.get(file).get_or([])
		var inside = List[Fact]()
		for f in head.entities:
			if f.first > 0 and f.file == file: inside.append(f.clone())

		for line in lines:
			var best: Fact? = none

			for f in inside:
				if f.first > line or f.last < line: continue

				if current := best:
					span := f.last - f.first
					best_span := current.last - current.first
					if span < best_span or span == best_span and f.key < current.key: best = f.clone()
				else: best = f.clone()

			if found := best: result.add(found.key.clone())

	return result

// Classifies what changed between base and head, ranked: score, then tier, then id.
export fn compare_facts(base: Facts, head: Facts, input: DiffInput) List[Finding]:
	head_index := index_of(head.clone())
	base_index := index_of(base.clone())
	var callers = Map[String, List[String]]()

	for f in head.entities:
		for callee in f.calls:
			if list := callers.get(callee):
				var more = list.clone()
				more.append(f.key.clone())
				callers.add(callee.clone(), more)
			else: callers.add(callee.clone(), [f.key.clone()])

	var keys = Set[String]()
	for f in head.entities: keys.add(f.key.clone())
	for f in base.entities: keys.add(f.key.clone())

	touched := touched_keys(head, input.touched)
	var findings = List[Finding]()
	var deferred = List[String]()

	for key in keys.values():
		h := head_index.get(key)
		var b = base_index.get(key)
		if base_fact := b:
			if input.added.contains(base_fact.file): b = none

		c := classify(key, input.base_checked, head_index, h, b)
		var f = c.finding.clone()
		var exported = false
		if hf := h: exported = hf.exported

		if c.scored and callers.contains(key): deferred.append(key.clone())
		else if c.scored and exported:
			// A target without incoming edges has exact reach zero.
			f.terms.append("exported +3")
			f.score += 3

		if f.changes.is_empty() and touched.contains(key): f.changes = ["body changed"]
		if f.changes.is_empty(): continue

		findings.append(f)

	for i in 0..findings.length():
		if not deferred.contains(findings[i].id): continue

		r := reach_count(findings[i].id, callers)
		findings[i].reach = r

		if r > 0:
			var bits = 0
			var rest = r

			while rest > 0:
				bits += 1
				rest /= 2

			findings[i].terms.append(f"reach({r}) +{2 * bits}")
			findings[i].score += 2 * bits

		if head_index.get(findings[i].id).get_or(empty()).exported:
			findings[i].terms.append("exported +3")
			findings[i].score += 3

	findings.sort(
		fn a,
		b:
			if a.score != b.score: return if a.score > b.score: -1 else: 1

			ra := tier_rank(a.tier)
			rb := tier_rank(b.tier)
			if ra != rb: return if ra < rb: -1 else: 1

			return a.id.compare(b.id)
	)

	return findings

fn empty() Fact:
	return Fact(
		key: "",
		file: "",
		kind: "",
		name: "",
		line: 0,
		effects: [],
		error: "",
		tries: 0,
		scopes: 0,
		calls: [],
		external: [],
		slots: [],
		result_ownership: "",
		result_borrow: false,
		receiver: "",
		result: none,
	)

// ---- Output: the JSON `ms review` prints, pretty-printed as the Rust tool does ----

fn string_array(items: List[String], pad: String) String:
	if items.is_empty(): return "null"

	var out = "[\n"

	for i in 0..items.length():
		out = out.concat(f"{pad}  {json_string(items[i])}")
		if i + 1 < items.length(): out = out.concat(",")
		out = out.concat("\n")

	return out.concat(f"{pad}]")

export fn findings_json(findings: List[Finding]) String:
	if findings.is_empty(): return "[]\n"

	var out = "[\n"

	for i in 0..findings.length():
		f := findings[i]
		out = out.concat("  {\n")
		out = out.concat(f"    \"id\": {json_string(f.id)},\n")
		out = out.concat(f"    \"tier\": {json_string(f.tier)},\n")
		out = out.concat(f"    \"entity\": {json_string(f.entity)},\n")
		out = out.concat(f"    \"where\": {json_string(f.location)},\n")
		out = out.concat(f"    \"changes\": {string_array(f.changes, PAD)},\n")
		out = out.concat(f"    \"reach\": {f.reach},\n")
		out = out.concat(f"    \"score\": {f.score},\n")

		if f.evidence.is_empty(): out = out.concat(
			f"    \"terms\": {string_array(f.terms, PAD)}\n"
		)
		else:
			out = out.concat(f"    \"terms\": {string_array(f.terms, PAD)},\n")
			out = out.concat(f"    \"evidence\": {string_array(f.evidence, PAD)}\n")

		out = out.concat("  }")
		if i + 1 < findings.length(): out = out.concat(",")
		out = out.concat("\n")

	return out.concat("]\n")

// ---- Entry ----

fn load(path: String) Facts!:
	return ok(parse[Facts](read_file(path).wait()?.decode_utf8().get_or(""))?)

fn review_tool() Command:
	return Command(
		name: "review.ms",
		about: "Rank what a change affects, from the facts of the base and head",
		args: [
			Arg("base", help: "The base facts JSON"),
			Arg("head", help: "The head facts JSON"),
		],
		flags: [
			Flag(
				"no-base",
				FlagKind.Bool,
				help: "The base was not rebuilt from the diff",
			),
			Flag("added", FlagKind.List, help: "A source the change adds"),
			Flag("touch", FlagKind.List, help: "FILE:LINE a change touches"),
		],
	)

// The changed-source inputs of `--no-base`, `--added` and `--touch FILE:LINE`.
export fn diff_input(m: Matches) DiffInput!:
	var input = DiffInput(
		added: m.list("added").to_set(),
		touched: Map[String, List[Int]](),
		base_checked: not m.bool("no-base"),
	)

	for value in m.list("touch"):
		cut := value.last_index_of(":").get_or(-1)
		if cut < 0: return error(Error(f"--touch needs FILE:LINE, not {value}"))

		file := value.slice(0, cut)
		line := value.slice(cut + 1, value.length()).parse_int().get_or(0)
		var lines = input.touched.get(file).get_or([])
		lines.append(line)
		input.touched.add(file, lines)

	return ok(input)

// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
// ms: allow_effect std.console.write
fn show(m: Matches) Void!:
	base := load(m.string("base"))?
	head := load(m.string("head"))?
	input := diff_input(m)?
	var out = stdout()
	out.write(findings_json(compare_facts(base, head, input)))?
	out.flush()?
	return ok()

fn main() Int:
	return run_tool(review_tool(), show)

// ---- Tests: the behavior crates/ms-tooling/tests/review.rs pinned ----

fn fact(file: String, kind: String, name: String, line: Int) Fact:
	return Fact(
		key: f"{file}#{kind}#{name}",
		file: file,
		kind: kind,
		name: name,
		line: line,
		effects: [],
		error: "",
		tries: 0,
		scopes: 0,
		calls: [],
		external: [],
		slots: [],
		result_ownership: "",
		result_borrow: false,
		receiver: "",
		result: none,
		ty: "fn() Int",
		first: line,
		last: line + 1,
	)

fn facts_of(list: List[Fact]) Facts:
	return Facts(
		entities: list.sorted_by_key(fn f: f.key.clone()),
		imports: [],
		flows: [],
	)

fn input_at(lines: List[Int]) DiffInput:
	return DiffInput(added: Set[String](), touched: {"r.ms": lines}, base_checked: true)

fn program(add_effect: Bool) Facts:
	var say = fact("r.ms", "fn", "say", 3)
	say.effects = ["io"]
	say.reach = ["io"]
	say.external = ["@std/io/io.ms#stdout"]

	var add = fact("r.ms", "fn", "add", 7)
	var run = fact("r.ms", "fn", "run", 10)
	run.exported = true
	run.calls = [add.key.clone()]

	if add_effect:
		add.effects = ["io"]
		add.reach = ["io"]
		add.calls = [say.key.clone()]
		run.effects = ["io"]
		run.reach = ["io"]

	return facts_of([say, add, run])

test "an effect gain ranks through callers":
	findings := compare_facts(program(false), program(true), input_at([8]))
	expect_equal(findings[0].tier, "EFFECT+")?
	expect_equal(findings.length(), 2)?
	expect_true(findings[0].changes.contains("reaches: + io"))?

	add := findings.find(fn f: f.entity == "add").get()
	expect_equal(add.evidence, ["path: add -> say -> @std/io/io.ms#stdout"])?

fn declared_program(permit: Bool, reach: Bool) Facts:
	var connect = fact("r.ms", "fn", "connect", 3)
	var save = fact("r.ms", "fn", "save", 7)
	save.calls = [connect.key.clone()]

	if reach:
		connect.reach = ["std.net.connect"]
		save.reach = ["std.net.connect"]

	if permit: save.permits = ["std.net.*"]
	return facts_of([connect, save])

test "a new permission and a new reach are effect findings, the permission first":
	findings := compare_facts(
		declared_program(false, false),
		declared_program(true, true),
		input_at([8]),
	)
	save := findings.find(fn f: f.entity == "save").get()
	expect_equal(save.tier, "EFFECT+")?
	expect_equal(save.changes[0], "permits: + std.net.*")?
	expect_true(save.changes.contains("reaches: + std.net.connect"))?
	expect_equal(save.evidence, ["path: save -> connect"])?

test "reach counts distinct callers across cycles":
	var entry = fact("r.ms", "fn", "entry", 1)
	var left = fact("r.ms", "fn", "left", 3)
	var right = fact("r.ms", "fn", "right", 5)
	var target = fact("r.ms", "fn", "target", 7)
	unrelated := fact("r.ms", "fn", "unrelated", 9)
	entry.calls = [left.key.clone(), right.key.clone()]
	left.calls = [target.key.clone(), target.key.clone()]
	right.calls = [target.key.clone()]
	target.calls = [left.key.clone(), target.key.clone()]
	target.exported = true

	base := facts_of([entry, left, right, target, unrelated])
	var head = base.clone()

	for i in 0..head.entities.length():
		if head.entities[i].name == "target": head.entities[i].ty = "fn() String"
		if head.entities[i].name == "left": head.entities[i].scopes = 1

	// The right branch has one caller, but a body-only edit gets no reach bonus.
	findings := compare_facts(base, head, input_at([6]))
	expect_equal(findings.length(), 3)?
	expect_equal(findings[0].entity, "target")?
	expect_equal(findings[0].tier, "CONTRACT")?
	expect_equal(findings[0].reach, 3)?
	expect_equal(findings[0].score, 15)?
	expect_equal(findings[0].terms, ["contract +8", "reach(3) +4", "exported +3"])?
	expect_equal(findings[1].entity, "left")?
	expect_equal(findings[1].tier, "RESOURCE")?
	expect_equal(findings[1].reach, 3)?
	expect_equal(findings[1].score, 8)?
	expect_equal(findings[1].terms, ["resource +4", "reach(3) +4"])?
	expect_equal(findings[2].entity, "right")?
	expect_equal(findings[2].tier, "INTERNAL")?
	expect_equal(findings[2].reach, 0)?
	expect_equal(findings[2].score, 0)?
	expect_true(findings[2].terms.is_empty())?

type Range:
	name: String
	first: Int
	last: Int

type Expected:
	line: Int
	key: String

test "touched lines map to the most specific entity, ties to the smallest key":
	var facts = List[Fact]()

	for spec in [
		Range(name: "outer", first: 1, last: 10),
		Range(name: "b", first: 3, last: 5),
		Range(name: "a", first: 3, last: 5),
		Range(name: "ignored", first: 0, last: 20),
		Range(name: "invalid", first: 8, last: 7),
	]:
		var f = fact("a.ms", "fn", spec.name.clone(), 0)
		f.key = spec.name.clone()
		f.first = spec.first
		f.last = spec.last
		facts.append(f)

	head := facts_of(facts)
	cases := [
		Expected(line: -1, key: ""),
		Expected(line: 0, key: ""),
		Expected(line: 1, key: "outer"),
		Expected(line: 3, key: "a"),
		Expected(line: 5, key: "a"),
		Expected(line: 6, key: "outer"),
		Expected(line: 10, key: "outer"),
		Expected(line: 11, key: ""),
	]

	for c in cases:
		keys := touched_keys(head, {"a.ms": [c.line, c.line], "absent.ms": [1]})
		expect_equal(keys.length(), if c.key.is_empty(): 0 else: 1)?
		expect_true(c.key.is_empty() or keys.contains(c.key))?

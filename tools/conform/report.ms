// Summaries of a run: the tally printed at the end, the JSON report and the markdown
// report.
import (
	JsonValue from "@std/data/json.ms",

	PHASES, Phase, phase_index, phase_name from "./fixture.ms",
	list_of, number, object, strings_of, text, with from "./json_util.ms",
	Case, Outcome, outcome_name from "./runner.ms",
)

export type Tally:
	total: Int = 0
	pass: Int = 0
	fail: Int = 0
	expected_fail: Int = 0
	unexpected_pass: Int = 0
	unrecorded: Int = 0

fn var Tally.add(outcome: Outcome) Void:
	self.total += 1
	if outcome == Outcome.Pass: self.pass += 1
	if outcome == Outcome.Fail: self.fail += 1
	if outcome == Outcome.ExpectedFail: self.expected_fail += 1
	if outcome == Outcome.UnexpectedPass: self.unexpected_pass += 1
	if outcome == Outcome.Unrecorded: self.unrecorded += 1

fn Tally.passing() Int: self.pass + self.unexpected_pass

fn Tally.rate() Float:
	if self.total == 0: return 100.0
	return 100.0 * self.passing().to_float() / self.total.to_float()

// A float with `places` decimals.
fn fixed(value: Float, places: Int) String:
	return value.to_fixed(places)

fn Tally.to_json() JsonValue:
	var o = with(object(), "total", number(self.total))
	o = with(o, "pass", number(self.passing()))
	o = with(o, "fail", number(self.fail))
	o = with(o, "expected_fail", number(self.expected_fail))
	o = with(o, "unexpected_pass", number(self.unexpected_pass))
	o = with(o, "unrecorded", number(self.unrecorded))
	return with(o, "pass_rate", JsonValue.NumberValue(fixed(self.rate(), 2)))

export type Summary:
	all: Tally = Tally()
	phases: List[Phase] = []
	by_phase: List[Tally] = []
	tags: List[String] = []
	by_tag: List[Tally] = []

fn var Summary.phase_tally(phase: Phase) Int:
	for at in 0..self.phases.length():
		if self.phases[at] == phase: return at
	self.phases.append(phase)
	self.by_phase.append(Tally())
	return self.phases.length() - 1

fn var Summary.tag_tally(tag: String) Int:
	for at in 0..self.tags.length():
		if self.tags[at] == tag: return at
	self.tags.append(tag.clone())
	self.by_tag.append(Tally())
	return self.tags.length() - 1

export fn summarize(cases: List[Case]) Summary:
	var s = Summary()

	for item in cases:
		s.all.add(item.outcome)

		at := s.phase_tally(item.phase)
		s.by_phase[at].add(item.outcome)

		for tag in item.tags:
			place := s.tag_tally(tag)
			s.by_tag[place].add(item.outcome)

	return s

fn is_regression(item: Case) Bool:
	return item.outcome == Outcome.Fail or item.outcome == Outcome.Unrecorded

export fn has_regressions(cases: List[Case]) Bool:
	return cases.any(is_regression)

export fn has_unexpected_pass(cases: List[Case]) Bool:
	return cases.any(fn c: c.outcome == Outcome.UnexpectedPass)

// Phases present in `s`, in phase order.
fn phase_order(s: Summary) List[Int]:
	return s.phases.keys().sorted_by_key(fn at: phase_index(s.phases[at]))

fn tag_order(s: Summary) List[Int]:
	return s.tags.keys().sorted_by_key(fn at: s.tags[at].clone())

export fn to_json(ms: String, cases: List[Case]) JsonValue:
	s := summarize(cases)
	var o = with(object(), "ms", text(ms))
	o = with(o, "summary", s.all.to_json())

	var phases = object()
	for at in phase_order(s):
		phases = with(phases, phase_name(s.phases[at]), s.by_phase[at].to_json())
	o = with(o, "by_phase", phases)

	var tags = object()
	for at in tag_order(s):
		tags = with(tags, s.tags[at].clone(), s.by_tag[at].to_json())
	o = with(o, "by_tag", tags)

	var failures = List[JsonValue]()

	for item in cases:
		if item.outcome == Outcome.Pass or item.outcome == Outcome.UnexpectedPass: continue

		var f = with(object(), "id", text(item.id))
		f = with(f, "phase", text(phase_name(item.phase)))
		f = with(f, "outcome", text(outcome_name(item.outcome)))
		f = with(f, "tags", strings_of(item.tags))
		failures.append(with(f, "diff", text(item.diff)))

	o = with(o, "failures", list_of(failures))

	var timings = List[JsonValue]()

	for item in cases:
		var t = with(object(), "id", text(item.id))
		t = with(t, "phase", text(phase_name(item.phase)))
		timings.append(with(t, "millis", number(item.millis)))

	o = with(o, "timings", list_of(timings))

	var unexpected = List[String]()
	for item in cases:
		if item.outcome == Outcome.UnexpectedPass: unexpected.append(item.id.clone())
	return with(o, "unexpected_passes", strings_of(unexpected))

fn row(name: String, t: Tally) String:
	return f"| {name} | {t.total} | {t.passing()} | {t.fail} | {t.expected_fail} | {t.unrecorded} | {fixed(t.rate(), 1)}% |\n"

HEADER := "| | total | pass | fail | expected fail | unrecorded | rate |\n|---|---:|---:|---:|---:|---:|---:|\n"

fn failing_section(failing: List[Case], max_failures: Int) String:
	var out = f"\n## Failing fixtures ({failing.length()})\n\n"
	for at in 0..min_of(failing.length(), max_failures):
		out += failing_entry(failing[at])
	if failing.length() > max_failures:
		out += f"... {failing.length() - max_failures} more not shown\n\n"
	return out

fn failing_entry(item: Case) String:
	return f"### `{item.id}` ({phase_name(item.phase)}, {item.tags.join(", ")})\n\n```diff\n{item.diff}```\n\n"

fn unexpected_section(unexpected: List[Case]) String:
	if unexpected.is_empty(): return ""

	var out = f"## Unexpected passes ({unexpected.length()})\n\n"
	out += "Remove these from the expect-fail file:\n\n"
	for item in unexpected:
		out += f"- `{item.id}`\n"
	return out

fn phase_rows(s: Summary) String:
	var out = ""
	for at in phase_order(s):
		out += row(phase_name(s.phases[at]), s.by_phase[at])
	return out

fn tag_rows(s: Summary) String:
	var out = ""
	for at in tag_order(s):
		out += row(s.tags[at], s.by_tag[at])
	return out

export fn to_markdown(ms: String, cases: List[Case], max_failures: Int) String:
	s := summarize(cases)
	var out = f"# Conformance report\n\nBinary: `{ms}`\n\n"
	out += f"## Overall\n\n{HEADER}\n" + row("all", s.all)
	out += f"\n## By phase\n\n{HEADER}\n" + phase_rows(s)
	out += f"\n## By tag\n\n{HEADER}\n" + tag_rows(s)
	out += failing_section(cases.filter(is_regression), max_failures)
	out += unexpected_section(cases.filter(fn c: c.outcome == Outcome.UnexpectedPass))
	return out

fn indent(content: String) String:
	var out = ""
	for line in content.lines():
		out += f"    {line}\n"
	return out

// The end-of-run summary, as lines to print.
export fn summary_lines(cases: List[Case]) List[String]:
	s := summarize(cases)
	var out = List[String]()
	out.append(
		f"{s.all.total} fixtures: {s.all.pass} pass, {s.all.fail} fail, {s.all.expected_fail} expected fail, {s.all.unexpected_pass} unexpected pass, {s.all.unrecorded} unrecorded ({fixed(s.all.rate(), 1)}%)"
	)

	for at in phase_order(s):
		phase := s.phases[at]
		t := s.by_phase[at]
		var millis = 0
		for item in cases:
			if item.phase == phase: millis += item.millis

		name := phase_name(phase).pad_end(6, " ")
		passing := f"{t.passing()}".pad_start(5, " ")
		total := f"{t.total}".pad_end(5, " ")
		out.append(
			f"  {name} {passing}/{total} {fixed(t.rate(), 1)}%  {fixed(millis.to_float() / 1000.0, 0)} s fixture time"
		)

	// CI reads this to find the fixtures that dominate a corpus run.
	slowest := cases.sorted_by_key(fn c: 0 - c.millis)
	out.append("slowest fixtures:")

	for at in 0..min_of(slowest.length(), 15):
		item := slowest[at]
		seconds := fixed(item.millis.to_float() / 1000.0, 2).pad_start(7, " ")
		out.append(f"  {seconds} s  {phase_name(item.phase).pad_end(5, " ")} {item.id}")

	for item in cases:
		if item.outcome == Outcome.UnexpectedPass:
			out.append(f"UNEXPECTED PASS {item.id}: remove from the expect-fail file")

	failing := cases.filter(is_regression)
	for at in 0..min_of(failing.length(), 30):
		out.append(f"FAIL {failing[at].id}\n{indent(failing[at].diff)}")
	if failing.length() > 30:
		out.append(
			f"... {failing.length() - 30} more failures (see --markdown / --json)"
		)
	return out

fn min_of(a: Int, b: Int) Int:
	if a < b: return a
	return b

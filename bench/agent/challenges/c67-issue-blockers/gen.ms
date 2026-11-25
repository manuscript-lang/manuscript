// Generator for c67-issue-blockers. The expected outputs come from the Go oracle in
// oracle/*.ref (built with the local Go toolchain). The hidden cases are the inputs of
// c60-issue-tracker (the behavior that must survive the edit) plus scenarios for
// blocking relations. Deterministic; run: ms run bench/agent/gen.ms -- c67
import (
	JsonValue, parse from "@std/data/json.ms",

	root from "../../core/model.ms",
	Cases, build_oracle, write_cases from "../../lib/gen.ms",
	read_text from "../../lib/text.ms",
)

fn add(var cs Cases, name, script String) Void {
	cs.push(name, script)
}

// The entries of c60-issue-tracker's hidden cases.
fn c60_inputs() List[JsonValue] {
	doc := parse(read_text(f"{root()}/challenges/c60-issue-tracker/hidden/cases.json")).get_or(
		JsonValue.Null
	)
	return doc.as_list() or []
}

WF := "workflow\ninitial: todo\ntodo -> doing, done, wontfix\ndoing -> review requires assignee, todo\nreview -> done requires labels, doing\nfinal: done, wontfix\nend\ncreate A\ncreate B\ncreate C\ncreate D\n"

export fn gen_c67() Void {
	var cs = Cases(build_oracle("c67-issue-blockers"))

	for entry in c60_inputs() {
		name := (entry.get("name") or JsonValue.Null).as_string() or ""
		stdin := (entry.get("stdin") or JsonValue.Null).as_string() or ""
		add(cs, f"kept-{name}", stdin)
	}

	add(cs, "block-basic", WF + "block 1 2\nblock #1 #3\nshow 1\nshow 2\nlog\n")
	add(
		cs,
		"block-clock-and-updated",
		WF + "block 1 2\nshow 1\nblock 1 2\nshow 1\nedit 3 title=\"C2\"\nshow 3\n",
	)
	add(
		cs,
		"block-usage",
		WF + "block\nblock 1\nblock 1 2 3\nunblock\nunblock 1\nunblock 1 2 3\n",
	)
	add(
		cs,
		"block-id-errors",
		WF
		+ "block x 2\nblock 1 y\nblock 9 2\nblock 1 9\nblock 0 1\nblock 1 0\nblock x y\nblock 9 8\nunblock 9 1\nunblock 1 9\nunblock 0 1\n",
	)
	add(cs, "block-self", WF + "block 1 1\nblock #2 2\nunblock 1 1\n")
	add(cs, "block-already", WF + "block 1 2\nblock 1 2\nblock 1 3\nlog\n")
	add(
		cs,
		"block-cycle",
		WF
		+ "block 1 2\nblock 2 3\nblock 3 1\nblock 2 1\nblock 3 2\nblock 4 1\nblock 1 4\nshow 3\n",
	)
	add(
		cs,
		"block-cycle-through-final",
		WF + "block 1 2\nmove 2 wontfix\nblock 2 1\nblock 1 3\nblock 3 1\n",
	)
	add(
		cs,
		"block-final-blocked",
		WF + "move 1 done\nblock 1 2\nunblock 1 2\nblock 2 1\nshow 2\n",
	)
	add(
		cs,
		"block-error-order",
		WF + "move 1 done\nblock 1 1\nblock 1 2\nblock 1 1\nblock x 1\n",
	)
	add(
		cs,
		"unblock-basic",
		WF
		+ "block 1 2\nblock 1 3\nunblock 1 2\nshow 1\nunblock 1 2\nunblock 1 3\nshow 1\nlog\n",
	)
	add(
		cs,
		"unblock-final-allowed",
		WF + "block 1 2\nmove 2 done\nmove 1 done\nunblock 1 2\nblock 1 3\nshow 1\n",
	)
	add(
		cs,
		"move-blocked",
		WF + "block 1 2\nblock 1 3\nmove 1 done\nmove 1 wontfix\nmove 1 doing\nshow 1\n",
	)
	add(
		cs,
		"move-blocked-partial",
		WF
		+ "block 1 2\nblock 1 3\nblock 1 4\nmove 3 done\nmove 1 done\nmove 4 wontfix\nmove 2 done\nmove 1 done\nshow 1\n",
	)
	add(
		cs,
		"move-guard-before-blockers",
		WF
		+ "block 1 2\nmove 1 doing\nmove 1 review\nmove 1 done\nassign 1 bob\nmove 1 review\nmove 1 done\nlabel 1 +x\nmove 1 done\n",
	)
	add(
		cs,
		"move-nonfinal-unaffected",
		WF
		+ "block 1 2\nmove 1 doing\nmove 1 todo\nmove 1 doing comment started\nshow 1\n",
	)
	add(
		cs,
		"move-transition-before-blockers",
		WF + "block 3 1\nmove 3 nowhere\nmove 3 todo\nmove 3 review\nmove 3 done\n",
	)
	add(
		cs,
		"blocker-deleted",
		WF
		+ "block 1 2\nblock 1 3\ndelete 2\nshow 1\nmove 1 done\ndelete 3\nshow 1\nmove 1 done\nlog\n",
	)
	add(
		cs,
		"blocked-deleted",
		WF + "block 1 2\ndelete 1\nshow 2\nunblock 1 2\nblock 1 2\n",
	)
	add(
		cs,
		"blocker-closed-then-reopened-ids",
		WF + "block 1 2\ndelete 2\ncreate E\nshow 1\nblock 1 5\nshow 1\n",
	)
	add(
		cs,
		"bulk-move-blocked",
		WF
		+ "block 1 4\nblock 2 4\nbulk move done where state:todo\nshow 1\nshow 3\nshow 4\n",
	)
	add(
		cs,
		"bulk-move-after-unblock",
		WF + "block 1 4\nmove 4 done\nbulk move done where state:todo\nlist\n",
	)
	add(
		cs,
		"show-blocked-by-order",
		WF + "block 1 4\nblock 1 2\nblock 1 3\nshow 1\nunblock 1 2\nshow 1\n",
	)
	add(
		cs,
		"block-with-comments-and-log",
		WF + "comment 1 hi\nblock 1 2\ncomment 1 again\nshow 1\nlog\n",
	)
	add(
		cs,
		"block-actor-in-log",
		WF + "actor ann\nblock 1 2\nactor bob\nunblock 1 2\nlog\n",
	)
	add(
		cs,
		"block-query-unaffected",
		WF + "block 1 2\nlist is:open\nlist state:todo sort id\nreport\n",
	)
	add(cs, "block-whitespace-words", WF + "block   #1\t 2\nblock 1   3  \nshow 1\n")
	add(cs, "block-no-workflow", "block 1 2\nunblock 1 2\nshow 1\n")

	examples := [
		cs.make(
			"ex-blocked-move",
			WF + "block 1 2\nshow 1\nmove 1 done\nmove 2 done\nmove 1 done\nshow 1\n",
		),
		cs.make(
			"ex-block-errors",
			WF
			+ "block 1 1\nblock 1 2\nblock 2 1\nblock 1 2\nunblock 1 3\nunblock 1 2\n",
		),
	]
	write_cases("c67-issue-blockers", examples, cs.list)
}

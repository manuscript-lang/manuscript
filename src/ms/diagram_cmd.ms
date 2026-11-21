// `ms diagram` with a view, an entity or JSON output: one scoped tree, optionally marked with
// what a diff changes. Port of `view` in crates/ms-cli/src/engine/tooling.rs; the Rust
// command is the oracle (src/ms/diagram-cmd-diff.sh). The HTML page and the default
// call graph (which reads the `ms inspect` document) stay with the Rust command.
import (
	stderr, stdout from "@std/io/io.ms",
	canonicalize from "@std/os/fs.ms",
	basename, dirname from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",

	tool_matches, tree_tool, usage_status from "./cli.ms",
	mark_changes from "./mark.ms",
	compare_facts from "./review.ms",
	Change, facts_in, load_change from "./review_cmd.ms",
	build_view, model_of, render, tree_ascii, tree_json, tree_mermaid from "./views.ms",
)

// What `ms diagram` was asked for a view.
export type DiagramRequest:
	file: String
	view: String = ""
	entity: String = ""
	depth: Int = 0
	// ascii, mermaid or json.
	format: String = "ascii"
	diff: String = ""

fn view_name(request: DiagramRequest) String:
	if request.view.is_empty(): return "calls"
	return request.view.clone()

/*
The text of the scoped view. A diff marks the generic tree, so a marked view keeps the
generic rendering. Without a diff the view's own rendering applies when it has one.
*/
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.env.read
// ms: allow_effect std.console.read
export fn diagram_view(request: DiagramRequest) String!:
	absolute := canonicalize(request.file)?
	root := dirname(absolute)
	name := basename(absolute)
	head := facts_in(root.clone(), name.clone())?
	model := model_of(head.clone())
	view := view_name(request)
	if request.diff.is_empty(): return render(
		model,
		view,
		request.entity.clone(),
		request.depth,
		request.format.clone(),
	)

	var tree = build_view(model, view, request.entity.clone(), request.depth)?
	change := load_change(root, name, request.diff.clone())?
	findings := compare_facts(change.base, head, change.plan.input)
	tree = mark_changes(tree, findings, change.plan.input.touched)
	if request.format == "json": return ok(
		tree_json(view, request.entity.clone(), tree)
	)
	if request.format == "mermaid": return ok(tree_mermaid(tree))

	return ok(tree_ascii(tree))

test "a view defaults to the call graph":
	expect_equal(view_name(DiagramRequest(file: "a.ms")), "calls")?
	expect_equal(view_name(DiagramRequest(file: "a.ms", view: "effects")), "effects")?

// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.env.read
// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Int:
	parsed := tool_matches(tree_tool("diagram", []))
	if parsed.is_error(): return usage_status(parsed.err())

	m := parsed.get()
	request := DiagramRequest(
		file: m.string("file"),
		view: m.string_or_none("view").get_or(""),
		entity: m.string_or_none("entity").get_or(""),
		depth: m.int_or_none("depth").get_or(0),
		format: if m.bool("json"): "json" else: m.string_or_none(
			"format"
		).get_or("ascii"),
		diff: m.string_or_none("diff").get_or(""),
	)
	printed := diagram_view(request)

	if printed.is_error():
		stderr().write(f"ms diagram: {printed.err().message}\n").get()
		return 2

	var out = stdout()
	out.write(printed.get()).get()
	out.flush().get()
	return 0

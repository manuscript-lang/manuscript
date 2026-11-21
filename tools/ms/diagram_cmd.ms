// `ms diagram` with a view, an entity or JSON output: one scoped tree, optionally marked with
// what a diff changes. Port of `view` in crates/ms-cli/src/engine/tooling.rs; the Rust
// command is the oracle (tools/ms/diagram-cmd-diff.sh). The HTML page and the default
// call graph (which reads the `ms inspect` document) stay with the Rust command.
import (
	stderr, stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
	canonicalize from "@std/os/fs.ms",
	basename, dirname from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",

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

fn usage() Error:
	return Error(
		"usage: diagram_cmd.ms FILE [--view VIEW] [--entity NAME] [--depth N] [--format ascii|mermaid|json] [--diff PATCH|-]"
	)

// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.env.read
// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Int:
	args := arguments()
	var request = DiagramRequest(file: "")
	var i = 0

	while i < args.length():
		option := args[i].clone()
		value := args.get_or(i + 1, "")
		i += 1

		if option == "--view": request.view = value
		else if option == "--entity": request.entity = value
		else if option == "--depth": request.depth = value.parse_int().get_or(0)
		else if option == "--format": request.format = value
		else if option == "--diff": request.diff = value
		else if option.starts_with("--") or not request.file.is_empty():
			stderr().write(usage().message + "\n").get()
			return 2
		else:
			request.file = option
			continue

		i += 1

	if request.file.is_empty():
		stderr().write(usage().message + "\n").get()
		return 2

	printed := diagram_view(request)

	if printed.is_error():
		stderr().write(f"ms diagram: {printed.err().message}\n").get()
		return 2

	var out = stdout()
	out.write(printed.get()).get()
	out.flush().get()
	return 0

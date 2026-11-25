// The performance suite's index (bench/perf/groups.txt) and the rules that keep it the
// only
// index: every path under bench/perf is a group of groups.txt or its results page. A
// finished investigation is deleted, with its findings moved to the wiki. Used by
// perf.ms.
import invalid from "./lib.ms"

// One group: `kind` is time, count or probe; `command` is empty when a probe has no
// single command; `results` is empty when the group publishes through a workflow.
export type Group {
	name, area, kind, command, results String
}

KINDS := ["time", "count", "probe"]
OWN := ["README.md", "groups.txt", "results.md", "tools"]

fn field(text String) String {
	return text.trim().clone()
}

// The groups of a groups.txt text. A line is `name | area | kind | command | results`;
// `-` leaves a field empty; lines starting with `#` and blank lines are skipped.
export fn parse_groups(text String) List[Group]! {
	var groups = List[Group]()
	var seen = Set[String]()

	for line in text.split("\n") {
		if line.trim() == "" or line.starts_with(
			"#"
		) { continue }

		parts := line.split(" | ").collect()
		if parts.length() != 5 { return invalid(f"groups.txt: want five fields: {line}") }

		name := field(parts[0])
		area := field(parts[1])
		kind := field(parts[2])
		if not KINDS.contains(
			kind
		) { return invalid(f"groups.txt: unknown kind {kind} for {name}") }
		if seen.contains(
			name
		) { return invalid(f"groups.txt: duplicate group {name}") }

		seen.add(name.clone())

		command := field(parts[3])
		results := field(parts[4])
		groups.append(
			Group(
				name: name,
				area: area,
				kind: kind,
				command: if command == "-" { "" } else { command },
				results: if results == "-" { "" } else { results },
			)
		)
	}

	return ok(groups)
}

// The commands of a group, in order (` ;; ` separates several): each is a program and
// arguments, where `ms` is `binary` and `{n}` is `samples`.
export fn commands(group Group, binary String, samples Int) List[List[String]] {
	var all = List[List[String]]()

	for text in group.command.split(" ;; ") {
		var words = List[String]()

		for word in text.split(" ") {
			if word == "" { continue }

			if word == "ms" and words.is_empty() {
				words.append(binary.clone())
			} else {
				words.append(word.replace("{n}", f"{samples}"))
			}
		}

		if not words.is_empty() { all.append(words) }
	}

	return all
}

// The first path component of a results entry, or "" for none.
export fn top(path String) String {
	if path == "" or path.starts_with(
		"../"
	) { return "" }
	return path.split("#").collect()[0].split("/").collect()[0].clone()
}

// What is wrong with the layout: `entries` are the names directly under bench/perf.
// Every entry is a group's directory or page, or one of the suite's own files.
export fn layout_problems(groups List[Group], entries List[String]) List[String] {
	var problems = List[String]()
	var known = Set[String]()

	for group in groups {
		for page in group.results.split(
			", "
		).collect() { known.add(top(page.trim())) }
		known.add(group.name.clone())
		if group.kind != "probe" and group.command == "" {
			problems.append(f"group {group.name} has kind {group.kind} but no command")
		}
	}

	for entry in entries {
		if OWN.contains(
			entry
		) or known.contains(
			entry
		) { continue }

		problems.append(
			f"{entry} is not a group or a results page of one: add it to groups.txt or delete it"
		)
	}

	return problems
}

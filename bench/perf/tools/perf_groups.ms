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

		parts := line.split(" | ")
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

// The program and arguments of a group's command: `ms` is `binary`, `{n}` is `samples`.
export fn argv(group Group, binary String, samples Int) List[String] {
	var out = List[String]()

	for word in group.command.split(" ") {
		if word == "" { continue }

		if word == "ms" and out.is_empty() {
			out.append(binary.clone())
		} else if word == "ms" {
			out.append(word.clone())
		} else {
			out.append(word.replace("{n}", f"{samples}"))
		}
	}

	return out
}

// The first path component of a results entry, or "" for none.
export fn top(path String) String {
	if path == "" or path.starts_with(
		"../"
	) { return "" }
	return path.split("#")[0].split("/")[0].clone()
}

// What is wrong with the layout: `entries` are the names directly under bench/perf.
// Every entry is a group's directory or page, or one of the suite's own files.
export fn layout_problems(groups List[Group], entries List[String]) List[String] {
	var problems = List[String]()
	var known = Set[String]()

	for group in groups {
		known.add(top(group.results))
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

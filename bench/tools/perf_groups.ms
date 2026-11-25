// The performance suite's index (bench/perf/groups.txt) and the rules that keep it the
// only
// index: every group has a results page, every other path under bench/perf is listed in
// bench/perf/investigations.txt, and nothing listed is gone. Used by perf.ms.
import invalid from "./lib.ms"

// One group: `kind` is time, count or probe; `command` is empty when a probe has no
// single command; `results` is empty when the group publishes through a workflow.
export type Group {
	name, kind, command, results String
}

KINDS := ["time", "count", "probe"]

fn field(text String) String {
	return text.trim().clone()
}

// The groups of a groups.txt text. A line is `name | kind | command | results`; `-`
// leaves a field empty; lines starting with `#` and blank lines are skipped.
export fn parse_groups(text String) List[Group]! {
	var groups = List[Group]()
	var seen = Set[String]()

	for line in text.split("\n") {
		if line.trim() == "" or line.starts_with(
			"#"
		) { continue }

		parts := line.split(" | ")
		if parts.length() != 4 { return invalid(f"groups.txt: want four fields: {line}") }

		name := field(parts[0])
		kind := field(parts[1])
		if not KINDS.contains(
			kind
		) { return invalid(f"groups.txt: unknown kind {kind} for {name}") }
		if seen.contains(
			name
		) { return invalid(f"groups.txt: duplicate group {name}") }

		seen.add(name.clone())

		command := field(parts[2])
		results := field(parts[3])
		groups.append(
			Group(
				name: name,
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
	return path.split("/")[0].clone()
}

// What is wrong with the layout: `entries` are the names directly under bench/perf and
// `investigations` the names in investigations.txt.
export fn layout_problems(
	groups List[Group],
	investigations,
	entries List[String],
) List[String] {
	var problems = List[String]()
	var known = Set[String]()
	var named = Set[String]()

	for group in groups {
		known.add(top(group.results))
		named.add(group.name.clone())
		if group.kind != "probe" and group.command == "" {
			problems.append(f"group {group.name} has kind {group.kind} but no command")
		}
	}

	for name in investigations {
		if not entries.contains(name) {
			problems.append(f"investigations.txt lists {name}, which is gone")
		}
		if known.contains(name) or named.contains(name) {
			problems.append(f"{name} is both a group and an investigation")
		}
	}

	for entry in entries {
		if ["README.md", "groups.txt", "investigations.txt"].contains(
			entry
		) { continue }
		if (
			known.contains(entry)
			or named.contains(entry)
			or investigations.contains(entry)
		) { continue }

		problems.append(f"{entry} is in neither groups.txt nor investigations.txt")
	}

	return problems
}

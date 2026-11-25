import (
	JsonValue, parse, stringify from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
	monotonic from "@std/time.ms",
)

// Median-of-runs timing; mirrors node.js: warm-up, then at least `runs` runs and
// `budget` ns.
fn median_ns(body fn() Int, budget, runs Int) Int {
	_warm := body()
	var samples List[Int] = []
	var total = 0

	while total < budget or samples.length() < runs {
		started := monotonic()
		_n := body()
		elapsed := monotonic().difference(started).to_nanoseconds()
		samples.append(elapsed)
		total += elapsed
	}

	sorted := samples.sorted(fn(a, b Int) Int => a.compare(b))
	return sorted[sorted.length() / 2]
}

fn say(text String) Void {
	_ignored := stdout().write(text.clone())
}

// The typed case: a list of records, written without building a `JsonValue` first. The
// size is the text produced, the same 10,000 rows in `node.js` and `rust/`.
type Row {
	id Int
	name String
	tags List[String]
	score Float
	ok Bool
}

fn row_list() List[Row] {
	var rows List[Row] = []
	for i in 0..10000 {
		rows.append(
			Row(
				id: i,
				name: f"user{i}",
				tags: ["a", "b"],
				score: i.to_float() + 0.5,
				ok: i % 2 == 0,
			)
		)
	}
	return rows
}

fn records_body(rows List[Row]) fn() Int {
	return fn() Int {
		if out := stringify(rows) { return out.length() }
		return 0
	}
}

fn bench_records(budget, runs Int) Void {
	rows := row_list()
	size := records_body(rows.clone())()
	s := median_ns(records_body(rows), budget, runs)
	say(f"records\tstringify\t{s}\t{size}\n")
}

fn bench_one(name, op String, budget, runs Int) Void {
	if name == "records" {
		bench_records(budget, runs)
		return
	}

	read := read_file(f"bench/perf/json/data/{name}.json").wait()

	if bytes := read {
		text := bytes.decode_utf8()

		if text != null {
			bench_text(name, op, text, bytes.length(), budget, runs)
		} else {
			say(f"{name}\tnot utf-8\n")
		}
	} else {
		say(f"{name}\tunreadable\n")
	}
}

fn bench_text(name, op, text String, size, budget, runs Int) Void {
	if tree := parse(text) {
		if op == "doc" {
			d := median_ns(doc_body(text.clone()), budget, runs)
			say(f"{name}\tdoc\t{d}\t{size}\n")
		}

		if op != "stringify" and op != "doc" {
			p := median_ns(parse_body(text.clone()), budget, runs)
			say(f"{name}\tparse\t{p}\t{size}\n")
		}

		if op != "parse" and op != "doc" {
			s := median_ns(stringify_body(tree), budget, runs)
			say(f"{name}\tstringify\t{s}\t{size}\n")
		}
	} else {
		say(f"{name}\tinvalid json\n")
	}
}

// Decodes to a record with no fields, so only the document build and its release are
// timed.
type Nothing {
	placeholder Int? = null
}

fn doc_body(text String) fn() Int {
	return fn() Int {
		if _v := parse[Nothing](text) { return 1 }
		return 0
	}
}

fn parse_body(text String) fn() Int {
	return fn() Int {
		if _v := parse(text) { return 1 }
		return 0
	}
}

fn stringify_body(tree JsonValue) fn() Int {
	return fn() Int {
		if out := stringify(tree) { return out.length() }
		return 0
	}
}

// Arguments are `name` or `name:op` (op is parse or stringify); a leading `quick` makes
// it 5 runs, no time floor.
fn main() Void {
	var budget = 1000000000
	var runs = 5

	for arg in arguments() {
		if arg == "quick" {
			budget = 0
		} else {
			parts := arg.split(":").collect()
			var op = "both"
			if parts.length() > 1 { op = parts[1].clone() }
			bench_one(parts[0], op, budget, runs)
		}
	}
}

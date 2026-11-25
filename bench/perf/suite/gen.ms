// ms: allow_effect std.fs.write

// Deterministic inputs for the text, data and file programs of the benchmark suite.
// Usage: ms run bench/perf/suite/gen.ms -- <output-directory> [scale]
// scale 1 makes about 25 MB per file; every file is a pure function of the scale.
import (
	arguments from "@std/os/env.ms",
	create_directory, write_file from "@std/os/fs.ms",
)

type Rng {
	state Int
}

fn var Rng.next(limit Int) Int {
	self.state = (self.state * 1103515245 + 12345) % 2147483648
	return (self.state / 65536) % limit
}

fn save(dir, name, text String) Void {
	write_file(f"{dir}/{name}", text, replace: true).wait().get()
}

fn logs(n, seed Int) String {
	var r = Rng(seed)
	levels := ["DEBUG", "INFO", "INFO", "INFO", "WARN", "ERROR"]
	methods := ["GET", "GET", "GET", "POST", "PUT", "DELETE"]
	statuses := ["200", "200", "200", "200", "201", "301", "304", "404", "500", "503"]
	var b = ""

	for i in 0..n {
		path := f"/api/v{1 + r.next(3)}/item/{r.next(2000)}"
		b += f"2026-11-12T{10 + r.next(10)}:{10 + r.next(50)}:{10 + r.next(50)}Z {levels[r.next(6)]} {methods[r.next(6)]} {path} {statuses[r.next(10)]} {r.next(900)}\n"
	}

	return b
}

fn csv(n Int) String {
	var r = Rng(2)
	regions := ["north", "south", "east", "west", "central", "overseas"]
	var b = ""
	b += "id,region,product,qty,price_cents,note\n"

	for i in 0..n {
		note := if r.next(
			10
		) == 0 { "\"gift, wrapped \"\"fast\"\"\"" } else { "plain" }
		b += f"{i},{regions[r.next(6)]},sku-{r.next(500)},{1 + r.next(9)},{100 + r.next(99900)},{note}\n"
	}

	return b
}

fn json(n Int) String {
	var r = Rng(3)
	tags := ["red", "green", "blue", "fast", "slow", "new", "old"]
	var b = ""
	b += "["

	for i in 0..n {
		if i > 0 { b += "," }

		active := if r.next(2) == 0 { "true" } else { "false" }
		t1 := tags[r.next(7)]
		t2 := tags[r.next(7)]
		b += f"\{\"id\":{i},\"user\":\"user{r.next(1000)}\",\"score\":{r.next(10000)},\"active\":{active},\"tags\":[\"{t1}\",\"{t2}\"],\"name\":\"item \\\"{r.next(100)}\\\"\"\}\n"
	}

	b += "]"
	return b
}

fn words(n Int) String {
	var r = Rng(4)
	var b = ""

	for i in 0..n {
		var line = ""

		for j in 0..12 {
			k := r.next(5000)

			// A skewed vocabulary: low ids are frequent.
			w := (k * k) / 5000
			line += f"{if j > 0 { " " } else { "" }}{if w % 7 == 0 { "Word" } else { "word" }}{w}"
		}

		b += f"{line}.\n"
	}

	return b
}

fn records(n Int) String {
	var r = Rng(5)
	var b = ""
	for i in 0..n {
		b += f"name{r.next(100000)} {r.next(1000000)}\n"
	}
	return b
}

// A tree of 20 directories with 100 log files each, 200 lines per file at scale 1.
fn tree(dir String, scale Int) Void {
	for d in 0..20 {
		sub := f"{dir}/tree/d{d}"
		create_directory(sub, recursive: true).get()
		for f in 0..100 * scale {
			save(sub, f"f{f}.log", logs(200, 100 + d * 1000 + f))
		}
	}
}

fn main() Int {
	args := arguments()
	if args.length() < 1 { return 2 }

	scale := if args.length() > 1 { (args[1].parse_int() or 1) } else { 1 }
	dir := args[0].clone()
	create_directory(dir, recursive: true).get()
	save(dir, "access.log", logs(400000 * scale, 1))
	save(dir, "orders.csv", csv(500000 * scale))
	save(dir, "records.json", json(200000 * scale))
	save(dir, "words.txt", words(400000 * scale))
	save(dir, "records.txt", records(1000000 * scale))
	tree(dir, scale)
	return 0
}

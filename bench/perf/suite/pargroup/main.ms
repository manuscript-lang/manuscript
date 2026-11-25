import (
	map_concurrent from "@std/concurrency/resilience.ms",
	arguments from "@std/os/env.ms",
	list, read_file from "@std/os/fs.ms",
)

type Stats {
	lines, latency, c2, c3, c4, c5 Int
}

fn files_under(dir String) List[String] {
	var out = List[String]()

	for entry in list(dir).get() {
		path := f"{dir}/{entry.name}"

		if entry.directory {
			out.extend(files_under(path))
		} else {
			out.append(path)
		}
	}

	return out
}

// Statistics of one log file; runs on a worker.
fn summarize(path String) Stats {
	text := read_file(path).wait().get().decode_utf8() or ""
	var s = Stats(0, 0, 0, 0, 0, 0)

	for line in text.split("\n") {
		if line.is_empty() { continue }

		f := line.split(" ")
		s.lines += 1
		s.latency += f[5].parse_int() or 0

		first := f[4].scalar_at(0)

		if first == 50 {
			s.c2 += 1
		} else if first == 51 {
			s.c3 += 1
		} else if first == 52 {
			s.c4 += 1
		} else {
			s.c5 += 1
		}
	}

	return s
}

fn main() Void {
	files := files_under(arguments()[0])
	parts := map_concurrent(files, 4, summarize).get()
	var t = Stats(0, 0, 0, 0, 0, 0)

	for p in parts {
		t.lines += p.lines
		t.latency += p.latency
		t.c2 += p.c2
		t.c3 += p.c3
		t.c4 += p.c4
		t.c5 += p.c5
	}

	print(f"files: {files.length()}")
	print(f"lines: {t.lines}")
	print(f"status: 2xx={t.c2} 3xx={t.c3} 4xx={t.c4} 5xx={t.c5}")
	print(f"latency: {t.latency}")
}

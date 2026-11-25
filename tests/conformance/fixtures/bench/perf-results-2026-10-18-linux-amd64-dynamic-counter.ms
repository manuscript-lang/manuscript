// conform: tags=control-flow,diagnostics,interpolation,modules,mutation,stdlib-io,stdlib-time,tier-io
// conform: phase=check
// conform: origin=bench/perf/results/2026-10-18-linux-amd64/dynamic-counter.ms
import (
	stdout from "@std/io/io.ms",
	Instant, monotonic from "@std/time.ms",
)

fn measure(start Int) Int {
	t := monotonic()
	var i = start
	var hits = 0

	while i < 10000000 {
		hits += i % 3
		i += 1
	}

	elapsed := monotonic().difference(t).to_nanoseconds()
	line := f"{start} {elapsed} {hits}\n"
	ignored := stdout().write(line.to_bytes())
	return hits
}

fn main() Void {
	measure(-137)
	measure(0)
	measure(5)
}

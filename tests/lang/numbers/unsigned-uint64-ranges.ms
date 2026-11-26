// conform: tags=numbers,types,tier-core
// conform: phase=run
// conform: origin=unsigned integer types UInt64 range analysis
import stdout from "@std/io/io.ms"

fn count(start UInt64, stop UInt64) UInt64 {
	var i = start
	var steps UInt64 = 0

	while i < stop {
		i += 1
		steps += 1
	}

	return steps
}

fn countdown(from UInt64) UInt64 {
	var i = from
	var steps UInt64 = 0

	while i > 0 {
		i -= 1
		steps += 1
	}

	return steps
}

fn clamp_sub(a UInt64, b UInt64) UInt64 {
	if a >= b {
		return a - b
	}
	return 0
}

fn mix(seed UInt64) UInt64 {
	var h = seed
	var i = 0

	while i < 5 {
		h = h * 3 + 1
		i += 1
	}

	return h
}

fn main() Void {
	top UInt64 := 18446744073709551615
	near UInt64 := 9223372036854775806
	void stdout().write(
		f"{count(near, near + 4)} {count(top - 3, top)} {countdown(5)}\n"
	)
	void stdout().write(
		f"{clamp_sub(3, 5)} {clamp_sub(top, 1)} {clamp_sub(top, top)}\n"
	)
	void stdout().write(f"{mix(1)} {mix(0)}\n")
	void stdout().write(f"{near + near} {near * 2 + 1} {top / 3 * 3}\n")
	void stdout().write(f"{mix(top / 1000)}\n")
}
// expect-exit: 0
// expect-stdout: 4 3 5
// expect-stdout: 0 18446744073709551614 0
// expect-stdout: 364 121
// expect-stdout: 18446744073709551612 18446744073709551613 18446744073709551615
// expect-stdout: 4482558809911421014

// conform: tags=strings,numbers,lists,interpolation,tier-stdlib
// conform: phase=run
// conform: origin=perf fast paths: builder append fusion, chars, parse_int, sort
import (
	stdout from "@std/io/io.ms",
	parse_int from "@std/math/math.ms",
)

fn compare(left Int, right Int) Int {
	if left < right { return -1 }
	if left > right { return 1 }

	return 0
}

fn say(text String) Void {
	_ignored := stdout().write(text.clone())
}

fn main() Void {
	var b = ""
	var i = -3

	while i < 4 {
		b += f"{i * 1000003},"
		b += f"<{i}>"
		i += 1
	}

	b += f"{9223372036854775807}|{-9223372036854775807}|"

	joined := b
	say(f"{joined}\n")

	var total = 0

	for part in "12,-7,+5,x,,99999999999999999999,999999999999999999".split(",") {
		v := part.parse_int()

		if v != null {
			total += v
		} else {
			total += 1
		}
	}

	say(f"{total}\n")

	var hits = 0
	for c in "hello wörld, ünï".chars() {
		if c == "l" {
			hits += 1
		}
	}
	say(f"{hits} {"naïve".chars().length()} {"".chars().length()}\n")

	var xs List[Int] = []
	var k = 0

	while k < 200 {
		xs.append(k * 7919 % 101)
		k += 1
	}

	sorted := xs.sorted(compare)
	say(f"{sorted[0]} {sorted[100]} {sorted[199]}\n")

	var ordered = true
	var j = 1

	while j < sorted.length() {
		if sorted[j - 1] > sorted[j] {
			ordered = false
		}
		j += 1
	}

	say(f"{ordered}\n")
}
// expect-exit: 0
// expect-stdout: -3000009,<-3>-2000006,<-2>-1000003,<-1>0,<0>1000003,<1>2000006,<2>3000009,<3>9223372036854775807|-9223372036854775807|
// expect-stdout: 1000000000000000012
// expect-stdout: 3 5 0
// expect-stdout: 0 50 100
// expect-stdout: true

// Guard: a custom iterator that skips items until one matches runs as a scalar loop.
// LLVM's early-exit vectorizer made it about 7x slower (50 instructions of vector setup
// per match).
import Iterator from "@std/core.ms"

type Counter {
	at Int
	end Int
}

fn var Counter.next() Int? {
	if self.at >= self.end { return null }

	self.at += 1
	return self.at - 1
}

type Evens {
	inner Iterator[Int]
}

fn var Evens.next() Int? {
	while true {
		v := self.inner.next()

		if v != null {
			if v % 2 == 0 { return v }
		} else {
			return null
		}
	}

	return null
}

fn main() Void {
	var t = 0
	for v in Evens(Counter(0, 2000000)) {
		t += v % 11
	}
	print(f"{t}")
}

import (
	Iterator from "@std/core.ms",
	monotonic from "@std/time.ms",
)

type Counter {
	at, end Int
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

type Scaled {
	inner Iterator[Int]
	k Int
}

fn var Scaled.next() Int? {
	v := self.inner.next()
	if v != null { return v * self.k }

	return null
}

type Rec {
	id, score Int
}

type RecIter {
	items List[Rec]
	at Int
}

fn var RecIter.next() Rec? {
	if self.at >= self.items.length() { return null }

	self.at += 1
	return self.items[self.at - 1].clone()
}

fn stop(name String, t0, chk Int) Void {
	now := monotonic().tick
	print(f"{name} {(now - t0) / 1000} {chk}")
}

fn w_counter() Int {
	var t = 0
	for v in Counter(0, 50000000) {
		t += v % 7
	}
	return t
}

fn w_counter_while() Int {
	var t = 0
	var i = 0

	while i < 50000000 {
		t += i % 7
		i += 1
	}

	return t
}

fn w_adapter_chain() Int {
	var t = 0
	for v in Scaled(Evens(Counter(0, 50000000)), 3) {
		t += v % 11
	}
	return t
}

fn w_rec_iter() Int {
	var xs List[Rec] = []
	for i in 0..1000000 {
		xs.append(Rec(i, i % 13))
	}

	var t = 0
	for r in 0..10 {
		for v in RecIter(xs.clone(), 0) {
			t += v.score
		}
	}
	return t
}

fn run(name String, f fn() Int) Void {
	t0 := monotonic().tick
	c := f()
	stop(name, t0, c)
}

fn main() Void {
	run("w_counter", w_counter)
	run("w_counter_while", w_counter_while)
	run("w_adapter_chain", w_adapter_chain)
	run("w_rec_iter", w_rec_iter)
}

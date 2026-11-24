import monotonic from "@std/time.ms"

fn main() Void {
	var xs List[String] = []
	for i in 0..2000 {
		xs.append(f"item-number-{i}")
	}

	t0 := monotonic().tick
	var t = 0
	for i in 0..20000 {
		t += xs.index_of(f"item-number-{i % 2000}") or 0
	}

	t1 := monotonic().tick
	print(f"index_of {(t1 - t0) / 1000} us {t}")
}

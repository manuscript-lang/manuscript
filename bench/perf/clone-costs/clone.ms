// ms: allow_effect std.clock.read
// ms: allow_effect std.console.write

import monotonic from "@std/time.ms"

type P {
	x, y Int
	name String
}

type Q {
	x, y Int
}

fn stop(name String, t0, chk Int) Void {
	now := monotonic().tick
	print(f"{name} {(now - t0) / 1000} {chk}")
}

fn main() Void {
	var li List[Int] = []
	for i in 0..1000000 { li.append(i) }

	var ls List[String] = []
	for i in 0..200000 {
		ls.append(f"a-longer-string-than-inline-{i}")
	}

	var lp List[P] = []
	for i in 0..200000 {
		lp.append(P(x: i, y: i, name: f"a-longer-string-than-inline-{i}"))
	}

	var lq List[Q] = []
	for i in 0..1000000 { lq.append(Q(x: i, y: i)) }

	var mi Map[Int, Int] = {}
	for i in 0..200000 { mi[i] = i }

	var ms Map[String, Int] = {}
	for i in 0..200000 { ms[f"key-number-{i}"] = i }

	var big = "x".repeat(1000000)
	var t0 = monotonic().tick
	var c = 0

	for r in 0..50 {
		var a = li.clone()
		a[0] = r
		c += a[0] + a[a.length() - 1]
	}

	stop("list_int_1M_x50", t0, c)
	t0 = monotonic().tick

	for r in 0..50 {
		var a = lq.clone()
		a[0] = Q(x: r, y: r)
		c += a[0].x + a[a.length() - 1].x
	}

	stop("list_plainrec_1M_x50", t0, c)
	t0 = monotonic().tick

	for r in 0..20 {
		var a = ls.clone()
		a[0] = "z"
		c += a[0].length()
	}

	stop("list_str_200k_x20", t0, c)
	t0 = monotonic().tick

	for r in 0..20 {
		var a = lp.clone()
		a[0] = P(x: r, y: r, name: "z")
		c += a[0].x + a[a.length() - 1].x
	}

	stop("list_strrec_200k_x20", t0, c)
	t0 = monotonic().tick

	for r in 0..20 {
		a := mi.clone()
		c += a.length()
	}

	stop("map_int_200k_x20", t0, c)
	t0 = monotonic().tick

	for r in 0..20 {
		a := ms.clone()
		c += a.length()
	}

	stop("map_str_200k_x20", t0, c)
	t0 = monotonic().tick

	for r in 0..200 {
		var a = big.clone()
		a += "y"
		c += a.length()
	}

	stop("string_1MB_x200", t0, c)
}

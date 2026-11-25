import (
	panic from "@std/core.ms",

	Point, ints from "./src/harness.ms",
)

// Index of the greatest key; `key` is a known lambda at every call site (see
// design/proposals/specialize-closure-args.md).
fn best_index(points List[Point], key fn(Point) Int) Int {
	var best = 0
	var best_key = key(points.get_or(0, Point(x: 0, y: 0)))

	for i in 1..points.length() {
		k := key(points.get_or(i, Point(x: 0, y: 0)))

		if k > best_key {
			best_key = k
			best = i
		}
	}

	return best
}

fn best_index_loop(points List[Point], scale Int) Int {
	var best = 0
	var best_key = points.get_or(0, Point(x: 0, y: 0)).y * scale

	for i in 1..points.length() {
		k := points.get_or(i, Point(x: 0, y: 0)).y * scale

		if k > best_key {
			best_key = k
			best = i
		}
	}

	return best
}

type BenchData {
	points List[Point]
	scale Int
	points_2 List[Point]
	scale_2 Int
	data List[Int]
	data_5 List[Int]
	data_6 List[Int]
	data_7 List[Int]
	data_8 List[Int]
	data_9 List[Int]
	data_10 List[Int]
	data_11 List[Int]
	data_12 List[Int]
	data_13 List[Int]
	data_14 List[Int]
	data_15 List[Int]
	data_16 List[Int]
	data_17 List[Int]
	data_18 List[Int]
	data_19 List[Int]
	data_20 List[Int]
	data_21 List[Int]
	small_points List[Point]
	data_22 List[Int]
	small_points_22 List[Point]
	data_23 List[Int]
	values List[Int]
	values_25 List[Int]
}

fn make_fixture() BenchData {
	var points List[Point] = []
	for i in 0..100000 {
		points.append(Point(x: i, y: (i * 7919) % 10007))
	}

	scale := 3
	var points_2 List[Point] = []
	for i in 0..100000 {
		points_2.append(Point(x: i, y: (i * 7919) % 10007))
	}

	scale_2 := 3
	data := ints(100000)
	data_5 := ints(100000)
	data_6 := ints(100000)
	data_7 := ints(100000)
	data_8 := ints(100000)
	data_9 := ints(100000)
	data_10 := ints(100000)
	data_11 := ints(100000)
	data_12 := ints(100000)
	data_13 := ints(100000)
	data_14 := ints(100000)
	data_15 := ints(100000)
	data_16 := ints(100000)
	data_17 := ints(100000)
	data_18 := ints(100000)
	data_19 := ints(100000)
	data_20 := ints(100000)
	data_21 := ints(100000)
	small_points := data_21.map(fn(x Int) Point => Point(x, (x * 7) % 1000))
	data_22 := ints(100000)
	small_points_22 := data_22.map(fn(x Int) Point => Point(x, (x * 7) % 1000))
	data_23 := ints(100000)
	values List[Int] := []
	values_25 := [1, 2, 3, 4]
	return BenchData(
		points: points,
		scale: scale,
		points_2: points_2,
		scale_2: scale_2,
		data: data,
		data_5: data_5,
		data_6: data_6,
		data_7: data_7,
		data_8: data_8,
		data_9: data_9,
		data_10: data_10,
		data_11: data_11,
		data_12: data_12,
		data_13: data_13,
		data_14: data_14,
		data_15: data_15,
		data_16: data_16,
		data_17: data_17,
		data_18: data_18,
		data_19: data_19,
		data_20: data_20,
		data_21: data_21,
		small_points: small_points,
		data_22: data_22,
		small_points_22: small_points_22,
		data_23: data_23,
		values: values,
		values_25: values_25,
	)
}

bench "list.callable_key" per 100000 {
	best_index(fixture.points, fn(p Point) Int => p.y * fixture.scale)
}

bench "list.callable_key_loop" per 100000 {
	best_index_loop(fixture.points_2, fixture.scale_2)
}

bench "list.append" per 200000 {
	var xs List[Int] = []
	for i in 0..200000 {
		xs.append(i)
	}
	xs.length()
}

bench "list.at" per 200000 {
	var n = 0
	for i in 0..200000 {
		n += fixture.data.get_or(i % 100000, 0)
	}
	n
}

bench "list.for_in" per 100000 {
	var n = 0
	for x in fixture.data_5 {
		n += x
	}
	n
}

bench "list.map" per 100000 {
	fixture.data_6.map(fn(x Int) Int => x * 2).length()
}

bench "list.filter" per 100000 {
	fixture.data_7.filter(fn(x Int) Bool => x % 2 == 0).length()
}

bench "list.zip" per 100000 {
	fixture.data_8.zip(fixture.data_8).length()
}

bench "list.chunks" per 100000 {
	fixture.data_9.chunks(64).length()
}

bench "list.windows" per 100000 {
	fixture.data_10.windows(4).length()
}

bench "list.partition" per 100000 {
	fixture.data_11.partition(fn(x Int) Bool => x % 2 == 0).matching.length()
}

bench "list.fold" per 100000 {
	fixture.data_12.fold(0, fn(acc, x Int) Int => acc + x)
}

bench "list.sorted" per 100000 {
	sorted := fixture.data_13.sorted(fn(left, right Int) Int => left - right)
	sorted.length()
}

bench "list.sorted_natural" per 100000 {
	fixture.data_14.sorted().length()
}

bench "list.sum" per 100000 {
	fixture.data_15.sum()
}

bench "list.max" per 100000 {
	fixture.data_16.max() or panic("called Optional.get() on null")
}

bench "list.contains" per 100 {
	var n = 0
	for i in 0..100 {
		if fixture.data_17.contains(-1) { n += 1 }
	}
	n
}

bench "list.distinct" per 100000 {
	fixture.data_18.distinct().length()
}

bench "list.concat_reverse" per 100000 {
	fixture.data_19.concat(fixture.data_19).reversed().length()
}

bench "list.any_early_exit" per 100000 {
	var n = 0
	for i in 0..100000 {
		if fixture.data_20.any(fn(x Int) Bool => x == 0) { n += 1 }
	}
	n
}

bench "list.max_by" per 100 {
	var n = 0

	for i in 0..100 {
		best := fixture.small_points.max_by(fn(p Point) Int => p.y)
		if best != null { n += best.x }
	}

	n
}

bench "list.max_by_loop" per 100 {
	var n = 0

	for i in 0..100 {
		var best = 0
		for j in 1..fixture.small_points_22.length() {
			if fixture.small_points_22[j].y > fixture.small_points_22[best].y { best = j }
		}
		n += fixture.small_points_22[best].x
	}

	n
}

bench "list.records_map" per 100000 {
	mapped := fixture.data_23.map(fn(x Int) Point => Point(x, x + 1))
	mapped.fold(0, fn(acc Int, p Point) Int => acc + p.y)
}

bench "list.repeated empty" {
	fixture.values.repeated(1000000).length()
}

bench "list.repeated small" {
	fixture.values_25.repeated(2).length()
}

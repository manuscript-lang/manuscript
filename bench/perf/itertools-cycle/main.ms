import (
	cycle from "@std/collections/itertools.ms",
	keep, measure from "@std/test/bench.ms",
	expect_equal from "@std/test/test.ms",
)

bench "cycle.empty.large_count":
	values := List[Int]()
	expect_equal(cycle(values, 100000000), List[Int]())?
	measure(1, fn: keep(cycle(values, 100000000).length()))?

bench "cycle.singleton.one":
	values := [1]
	expect_equal(cycle(values, 1), [1])?
	measure(1, fn: keep(cycle(values, 1).length()))?

bench "cycle.sixteen.eight":
	values := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
	expect_equal(cycle(values, 8).length(), 128)?
	measure(1, fn: keep(cycle(values, 8).length()))?

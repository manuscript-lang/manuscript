import (
	cycle from "@std/collections/itertools.ms",
	expect_equal from "@std/test/test.ms",
)

type BenchData {
	values List[Int]
	values_2 List[Int]
	values_3 List[Int]
}

fn make_fixture() BenchData {
	values := List[Int]()
	values_2 := [1]
	values_3 := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
	return BenchData(values: values, values_2: values_2, values_3: values_3)
}

fn var BenchData.before_all() Void! {
	expect_equal(cycle(self.values, 100000000), List[Int]())?
	expect_equal(cycle(self.values_2, 1), [1])?
	expect_equal(cycle(self.values_3, 8).length(), 128)?
	return ok()
}

bench "cycle.empty.large_count" {
	cycle(fixture.values, 100000000).length()
}

bench "cycle.singleton.one" {
	cycle(fixture.values_2, 1).length()
}

bench "cycle.sixteen.eight" {
	cycle(fixture.values_3, 8).length()
}

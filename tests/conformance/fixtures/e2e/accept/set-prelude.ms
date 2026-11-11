// conform: tags=closures,generics,lists,modules,sets,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/set-prelude.ms
import expect_equal, expect_false from "@std/test/test.ms"

fn insert[T: Hashable](var values: Set[T], value: T) Unit: values.add(value)

test "set construction and methods need no import":
    var values: Set[Int] = Set()
    expect_false(not values.is_empty())?
    insert(var values, 3)
    values.add(1)
    values.add(3)
    values.add(2)
    expect_false(values.length() != 3 or not values.contains(2))?
    expect_equal(values.values(), [3, 1, 2])?

    copy := values.clone()
    values.remove(1)
    expect_false(values.contains(1) or not copy.contains(1))?

    other := Set[Int]([4, 2])
    expect_equal(values.union(other).values(), [3, 2, 4])?
    expect_equal(values.filter(fn(value: Int) Bool: value > 2).values(), [3])?
    expect_equal(values.map(fn(value: Int) Int: value * 2).values(), [6, 4])?

    nested: List[Set[Int]] := [values.clone()]
    expect_equal(nested[0].length(), 2)?
    values.clear()
    expect_false(not values.is_empty() or copy.length() != 3)?

test "set constructor accepts a list":
    values := Set[Int]([3, 1, 3, 2])
    expect_equal(values.values(), [3, 1, 2])?

    inferred := Set(["a", "b"])
    expect_equal(inferred.length(), 2)?

    empty: Set[Int] := Set([])
    expect_false(not empty.is_empty())?

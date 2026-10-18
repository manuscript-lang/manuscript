import {expect_equal} from "@std/testing.ms"

fn positives(values: List[Int]) -> List[Int]:
    var result: List[Int] = []
    for value in values:
        if value > 0:
            result = result.append(value: value)
    return result

test "dynamic mutable data and explicit copies":
    positives(values: [3, -1, 2]) | try expect_equal(expected: [3, 2])
    let absent: Optional[Int] = none
    [1].at(index: 5) | try expect_equal(expected: absent)
    let original = Map[String, Int]().add(key: "a", value: 1)
    let updated = (original.clone().add(key: "b", value: 2).add(key: "a", value: 3))
    original.get(key: "a") | try expect_equal(expected: some(1))
    updated.get(key: "a") | try expect_equal(expected: some(3))

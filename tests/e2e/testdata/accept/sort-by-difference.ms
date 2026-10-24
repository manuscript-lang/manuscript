import {expect_contains, expect_equal, expect_fault} from "@std/testing.ms"

fn ascending(xs: List[Int]) List[Int]:
    return xs.sorted(compare: fn(left: Int, right: Int) Int: return left - right)

fn descending(xs: List[Int]) List[Int]:
    return xs.sorted(compare: fn(left: Int, right: Int) Int: return right - left)

test "a difference comparator sorts by value":
    ascending([5, -3, 9, 0, -3, 7]) | try expect_equal([-3, -3, 0, 5, 7, 9])
    descending([5, -3, 9, 0, -3, 7]) | try expect_equal([9, 7, 5, 0, -3, -3])
    ascending([]) | try expect_equal(List[Int]())
    ascending([4]) | try expect_equal([4])

test "a difference comparator still faults when a subtraction overflows":
    let wide = [9223372036854775807, -9223372036854775807, 0]
    (try expect_fault(fn(): let ignored = ascending(wide))) | try expect_contains(
        "Int overflow"
    )

    let near = [9223372036854775807, 1, 0]
    ascending(near) | try expect_equal([0, 1, 9223372036854775807])

import expect_equal from "@std/test.ms"

fn singleton(var values: List[Int]) List[Int]:
    values.append(1)
    return values.clone()

fn bump(var values: List[Int]) Unit:
    values.append(1)

test "closure direct":
    var values: List[Int] = []
    let callback = fn() List[Int]: singleton(var values)
    let _r = callback()
    values.length() | try expect_equal(1)

test "closure unit":
    var values: List[Int] = []
    let callback = fn() Unit: bump(var values)
    callback()
    values.length() | try expect_equal(1)

test "closure append":
    var values: List[Int] = []
    let callback = fn() Unit: values.append(1)
    callback()
    values.length() | try expect_equal(1)

test "closure default passes a captured variable":
    var values: List[Int] = []
    let callback = fn(value: List[Int] = singleton(var values)) Int: value.length()
    callback() | try expect_equal(1)
    values.length() | try expect_equal(1)

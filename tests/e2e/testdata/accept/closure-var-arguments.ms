from "@std/testing.ms" import expect_equal

def singleton(var values: List[Int]) -> List[Int]:
    values.append(1)
    return values.clone()

def bump(var values: List[Int]) -> Unit:
    values.append(1)

test "closure direct":
    var values: List[Int] = []
    let callback = lambda () -> List[Int]: singleton(var values)
    let _r = callback()
    values.length() | try expect_equal(1)

test "closure unit":
    var values: List[Int] = []
    let callback = lambda () -> Unit: bump(var values)
    callback()
    values.length() | try expect_equal(1)

test "closure append":
    var values: List[Int] = []
    let callback = lambda () -> Unit: values.append(1)
    callback()
    values.length() | try expect_equal(1)

test "closure default passes a captured variable":
    var values: List[Int] = []
    let callback = lambda (value: List[Int] = singleton(var values)) -> Int: value.length()
    callback() | try expect_equal(1)
    values.length() | try expect_equal(1)

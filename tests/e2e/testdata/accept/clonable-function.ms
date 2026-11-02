import expect_equal from "@std/test/test.ms"

# A function value is Clonable: its captures cannot change, so a copy shares them.
fn twice[T: Clonable](value: T) List[T]:
    return [value.clone(), value]

test "a function value is cloned through a Clonable bound":
    let offset = 2
    let fs = twice(fn(x: Int) Int: x + offset)
    fs[0](1) | try expect_equal(3)
    fs[1](2) | try expect_equal(4)

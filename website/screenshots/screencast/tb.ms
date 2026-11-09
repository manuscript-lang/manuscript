import expect_equal from "@std/test/test.ms"

fn double(n: Int) Int:
    return n * 2

test "double":
    return expect_equal(double(4), 8)

bench "double":
    double(1000)

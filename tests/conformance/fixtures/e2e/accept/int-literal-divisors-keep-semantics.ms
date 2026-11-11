// conform: tags=control-flow,modules,mutation,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/int-literal-divisors-keep-semantics.ms
import expect_true from "@std/test/test.ms"

test "literal divisors":
    n := -7
    expect_true((n / 2 == -3))?
    expect_true((n % 3 == -1))?
    expect_true((9 % 2 == 1))?

    var i = 0
    var hits = 0

    while i < 100:
        if i % 3 == 0:
            hits = hits + 1
        i = i + 1

    expect_true((hits == 34))?

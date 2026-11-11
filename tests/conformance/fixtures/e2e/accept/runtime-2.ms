// conform: tags=alternatives,match,modules,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/runtime-2.ms
import expect_equal from "@std/test/test.ms"

type Items:
    count: Int

enum Outcome:
    Value(value: Int)

fn compute(value: Int) Int:
    return value

fn ordinary() Outcome:
    return Outcome.Value(compute(3))

test "non-prelude spellings are ordinary names":
    expect_equal(Items(2).count, 2)?

    forward := compute
    expect_equal(forward(4), 4)?

    match ordinary():
        Value(value):
            expect_equal(value, 3)?

# conform: tags=closures,control-flow,formatter,lists,modules,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-18.ms
from "@std/testing.ms" import expect_equal

def apply(value: Int, transform: Callable[[Int], Int]) -> Int:
    return transform(value)

test "function suite boundaries":
    var calls: List[Int] = []
    let _dormant = lambda () -> Unit:
        calls.append(1)

    let grouped = apply(
        transform: (
            lambda value:
                if value > 0:
                    return value - 1

                return 0
        ),
        value: 3
    )

    let final_argument = apply(value: 3, transform: lambda value: return value - 1)
    calls.length() | try expect_equal(0)
    grouped | try expect_equal(2)
    final_argument | try expect_equal(2)

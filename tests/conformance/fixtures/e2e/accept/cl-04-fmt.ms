# conform: tags=formatter,lists,modules,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-04.ms
from "@std/test.ms" import expect_equal

def difference(values: List[Int]) -> Int:
    let [first, second] = values
    return first - second

test "list binding":
    try expect_equal(difference([9, 4]), 5)

    let {value: label} = Label("ready")
    try expect_equal(label, "ready")

type Label:
    value: String

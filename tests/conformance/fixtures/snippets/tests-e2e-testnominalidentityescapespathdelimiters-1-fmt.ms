# conform: tags=control-flow,faults,formatter,generics,interfaces,modules,parser,records,stdlib-testing,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/e2e_test.go:381 TestNominalIdentityEscapesPathDelimiters
from "@std/testing.ms" import expect_true, fail

interface Read:
    def get() -> Int

type Box[T]:
    value: T

impl Read for Box[T]:
    def get() -> Int:
        return 3

test "encoded nominal identity":
    let box = Box(value: 1)
    let view = Read(value: box)
    if not (view.get() == 3):
        return fail("check failed")

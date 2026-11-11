// conform: tags=diagnostics
// conform: phase=check
import expect_true, fail from "@std/test/test.ms"

interface Read:
    fn get() Int
type Box[T]:
    value: T
impl Read for Box[T]:
    fn get() Int:
        return 3
test "encoded nominal identity":
    box := Box(value: 1)
    view := Read(value: box)
    if not (view.get() == 3):
        return fail("check failed")

# conform: tags=control-flow,formatter,generics,interfaces,lists,modules,parser,records,stdlib-cleanup,stdlib-testing,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cleanup-dispatch.ms
from "@std/testing.ms" import expect_equal, expect_fault
from "@std/core.ms" import panic
from "@std/core.ms" import Closeable

interface OtherClose:
    var def close(flag: Bool) -> Int

interface Disposable:
    var def close() -> Unit

type Resource:
    closed: Int

impl OtherClose for Resource:
    var def close(flag: Bool) -> Int:
        panic("other")
        return 0

impl Closeable for Resource:
    var def close() -> Unit:
        panic("closeable")

impl Disposable for Resource:
    var def close() -> Unit:
        panic("disposable")

def bound_cleanup[T: Disposable](resource: T) -> Unit:
    with let item = resource:
        let _completed = ()

def canonical_cleanup[T: Closeable](resource: T) -> Unit:
    with let item = resource:
        let _completed = ()

test "cleanup uses the selected contract":
    let direct = try expect_fault(
        lambda:
            with let resource = Resource(0):
                let _completed = ()
    )
    try expect_equal(direct, "closeable")

    let bound = try expect_fault(lambda: bound_cleanup(resource: Resource(0)))
    try expect_equal(bound, "disposable")

    let canonical = try expect_fault(lambda: canonical_cleanup(resource: Resource(0)))
    try expect_equal(canonical, "closeable")

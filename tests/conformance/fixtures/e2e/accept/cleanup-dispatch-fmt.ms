# conform: tags=control-flow,formatter,generics,interfaces,lists,modules,parser,records,stdlib-cleanup,stdlib-testing,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cleanup-dispatch.ms
import {expect_equal, expect_fault} from "@std/test.ms"
import panic from "@std/core.ms"
import Closeable from "@std/core.ms"

interface OtherClose:
    var fn close(flag: Bool) Int

interface Disposable:
    var fn close() Unit

type Resource:
    closed: Int

impl OtherClose for Resource:
    var fn close(flag: Bool) Int:
        panic("other")
        return 0

impl Closeable for Resource:
    var fn close() Unit:
        panic("closeable")

impl Disposable for Resource:
    var fn close() Unit:
        panic("disposable")

fn bound_cleanup[T: Disposable](resource: T) Unit:
    with let item = resource:
        let _completed = unit

fn canonical_cleanup[T: Closeable](resource: T) Unit:
    with let item = resource:
        let _completed = unit

test "cleanup uses the selected contract":
    let direct = try expect_fault(
        fn:
            with let resource = Resource(0):
                let _completed = unit
    )
    try expect_equal(direct, "closeable")

    let bound = try expect_fault(fn: bound_cleanup(resource: Resource(0)))
    try expect_equal(bound, "disposable")

    let canonical = try expect_fault(fn: canonical_cleanup(resource: Resource(0)))
    try expect_equal(canonical, "closeable")

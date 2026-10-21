# conform: tags=control-flow,generics,interfaces,lists,modules,records,stdlib-cleanup,stdlib-testing,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/cleanup-dispatch.ms
import {expect_equal, expect_fault} from "@std/testing.ms"
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
    with item = resource:
        let completed = unit

fn canonical_cleanup[T: Closeable](resource: T) Unit:
    with item = resource:
        let completed = unit

test "cleanup uses the selected contract":
    let direct = try expect_fault(
        fn():
            with resource = Resource(0):
                let completed = unit
    )
    try expect_equal(direct, "closeable")
    let bound = try expect_fault(fn(): bound_cleanup(resource: Resource(0)))
    try expect_equal(bound, "disposable")
    let canonical = try expect_fault(fn(): canonical_cleanup(resource: Resource(0)))
    try expect_equal(canonical, "closeable")

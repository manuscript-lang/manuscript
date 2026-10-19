# conform: tags=aliasing,control-flow,generics,interfaces,lists,modules,records,stdlib-cleanup,stdlib-testing,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/cleanup-dispatch.ms
import {expect_true} from "@std/testing.ms"
import Closeable from "@std/cleanup.ms"

type Flag:
    value: Bool

interface OtherClose:
    fn close(flag: Bool) Int

interface Disposable:
    fn close() Unit

type Resource:
    closed: Flag
    unexpected: List[Int]

impl OtherClose for Resource:
    fn close(flag: Bool) Int:
        self.unexpected.append(1)
        return 0

impl Closeable for Resource:
    fn close() Unit:
        self.closed.value = true

impl Disposable for Resource:
    fn close() Unit:
        self.closed.value = true

fn bound_cleanup[T: Disposable](resource: T) Unit:
    with item = resource:
        let completed = unit

fn canonical_cleanup[T: Closeable](resource: T) Unit:
    with item = resource:
        let completed = unit

test "cleanup uses the selected contract":
    var closed = Flag(value: false)
    let unexpected: List[Int] = []
    with resource = Resource(closed, unexpected):
        (not closed.value) | try expect_true
    closed.value | try expect_true
    closed.value = false
    bound_cleanup(resource: Resource(closed, unexpected))
    closed.value | try expect_true
    closed.value = false
    canonical_cleanup(resource: Resource(closed, unexpected))
    closed.value | try expect_true
    unexpected.is_empty() | try expect_true

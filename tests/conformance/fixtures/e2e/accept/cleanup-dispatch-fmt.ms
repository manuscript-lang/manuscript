// conform: tags=control-flow,formatter,generics,interfaces,lists,modules,parser,records,stdlib-cleanup,stdlib-testing,testing,tier-stdlib,try-result,scope-cleanup
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/cleanup-dispatch.ms
import expect_equal, expect_fault from "@std/test/test.ms"
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
    var fn close() Unit!:
        panic("closeable")

impl Disposable for Resource:
    var fn close() Unit:
        panic("disposable")

fn bound_cleanup[T: Disposable](resource: T) Unit:
    var item = resource
    item.close()

fn canonical_cleanup[T: Closeable](resource: T) Unit:
    _item := resource
    _completed := unit

test "cleanup uses the selected contract":
    direct := expect_fault(
        fn:
            _resource := Resource(0)
            _completed := unit
    )?

    expect_equal(direct, "closeable")?

    bound := expect_fault(fn: bound_cleanup(resource: Resource(0)))?
    expect_equal(bound, "disposable")?

    canonical := expect_fault(fn: canonical_cleanup(resource: Resource(0)))?
    expect_equal(canonical, "closeable")?

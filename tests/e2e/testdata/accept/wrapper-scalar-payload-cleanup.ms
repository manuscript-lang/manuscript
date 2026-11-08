import Closeable from "@std/core.ms"
import expect_contains, expect_fault from "@std/test/test.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: error(Error("scalar wrapper payload closed"))

fn present() Marker?: Marker(1)

fn success() Marker!Int: ok(Marker(2))

fn failure() Int!Marker: error(Marker(3))

fn optional_cause() Unit:
    let _kept = present().ok_or(0)

fn optional_callback() Unit:
    let _kept = present().ok_or_else(fn: 0)

fn result_error_map() Unit:
    let _kept = success().map_error(fn cause: cause + 1)

fn result_optional() Unit:
    let _kept = success().to_optional()

fn result_map() Unit:
    let _kept = failure().map(fn item: item + 1)

fn result_then() Unit:
    let _kept = failure().and_then(fn item: ok(item + 1))

fn transformed_map() Unit:
    let _mapped = success().map(fn item: item.id)

fn transformed_error() Unit:
    let _mapped = failure().map_error(fn item: item.id)

fn transformed_then() Unit:
    let _mapped: Int!Int = success().and_then(fn item: ok(item.id))

test "scalar retained wrapper branches retain their cleanup duty":
    (try expect_fault(optional_cause)) | try expect_contains(
        "resource could not be closed"
    )
    (try expect_fault(optional_callback)) | try expect_contains(
        "resource could not be closed"
    )
    (try expect_fault(result_error_map)) | try expect_contains(
        "resource could not be closed"
    )
    (try expect_fault(result_optional)) | try expect_contains(
        "resource could not be closed"
    )
    (try expect_fault(result_map)) | try expect_contains("resource could not be closed")
    (try expect_fault(result_then)) | try expect_contains(
        "resource could not be closed"
    )

test "direct transforming callbacks close their owned scalar input":
    (try expect_fault(transformed_map)) | try expect_contains(
        "resource could not be closed"
    )
    (try expect_fault(transformed_error)) | try expect_contains(
        "resource could not be closed"
    )
    (try expect_fault(transformed_then)) | try expect_contains(
        "resource could not be closed"
    )

fn optional_or_else() Unit:
    let _kept = present().or_else(fn: none)

fn result_or_else() Unit:
    let _kept = success().or_else(fn cause: error(cause))

test "scalar or_else success branches retain their cleanup duty":
    (try expect_fault(optional_or_else)) | try expect_contains(
        "resource could not be closed"
    )
    (try expect_fault(result_or_else)) | try expect_contains(
        "resource could not be closed"
    )

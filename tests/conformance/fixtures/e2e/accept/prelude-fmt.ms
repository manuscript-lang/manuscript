# conform: tags=closures,control-flow,faults,formatter,interfaces,match,modules,optional,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/prelude.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"

type Failure:
    message_text: String

impl Error for Failure:
    fn message() String:
        return self.message_text.clone()

fn success() Int?!:
    return ok(7)

fn failure() Int!Failure:
    return error(Failure("failed"))

fn propagated() Int!:
    return ok(try failure())

test "prelude cases and optional methods need no imports":
    let inferred: Int? = 3
    let absent: Int? = none
    let qualified: Int? = 5
    try expect_false(not inferred.is_some() or not absent.is_none())
    try expect_false(inferred.get() != 3 or qualified.get() != 5)
    try expect_false(
        (
            absent.get(9) != 9
            or absent.or_else(
                fn() Int?: return 11
            ).get() != 11
        )
    )

    let value = try success()
    try expect_equal(value.get(), 7)

test "prelude Error preserves concrete failures through try":
    let outcome = propagated()
    try expect_false(not outcome.is_error())

    let cause = outcome.err()
    try expect_equal(cause.message(), "failed")

    match cause:
        Failure(value):
            try expect_equal(value.message_text, "failed")
        _: return fail("concrete error lost")

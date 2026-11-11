// conform: tags=tier-core
// conform: phase=test
import expect_true from "@std/test/test.ms"

test "defaulted closure converts to a required callable":
    fallback := "abc"
    choose := fn(value: String = fallback) Bool: not value.is_empty()
    required: fn(String) Bool := choose
    try expect_true(choose() and required(fallback))

test "escaping adapter keeps owning behavior":
    fn make(fallback: String) fn(String) Bool:
        choose := fn(value: String = fallback) Bool: not value.is_empty()
        required: fn(String) Bool := choose
        return required

    f := make("xy")
    try expect_true(f("z"))

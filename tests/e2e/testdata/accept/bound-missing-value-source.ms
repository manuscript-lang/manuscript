import expect_equal, expect_true, expect_fault from "@std/test/test.ms"

fn generic_convert[T](value: T?) T!MissingValue:
    let convert = value.ok_or[MissingValue]
    return convert()

fn ordinary(cause: MissingValue? = none) Int!MissingValue:
    return ok(if cause.is_none(): 77 else: 88)

interface Convert:
    fn convert(cause: MissingValue? = none) Int!MissingValue

type Source:
    sentinel: Int

impl Convert for Source:
    fn convert(cause: MissingValue?) Int!MissingValue:
        return ok(if cause.is_none(): self.sentinel else: 88)

# Exact expectations deliberately identify invocation lines, not binding lines.
test "bound MissingValue defaults use each invocation line":
    let absent: Int? = none
    let convert = absent.ok_or[MissingValue]
    let first_result = convert()
    let second_result = convert()
    try expect_equal(
        first_result.err().message(),
        "missing value at bound-missing-value-source.ms:24"
    )
    try expect_equal(
        second_result.err().message(),
        "missing value at bound-missing-value-source.ms:25"
    )

test "immutable copies and captured native values keep invocation defaults":
    let absent: Int? = none
    let convert = absent.ok_or[MissingValue]
    let copied = convert
    let copied_result = copied()
    let nested = fn:
        return copied()
    let nested_result = nested()
    try expect_equal(
        copied_result.err().message(),
        "missing value at bound-missing-value-source.ms:39"
    )
    try expect_equal(
        nested_result.err().message(),
        "missing value at bound-missing-value-source.ms:41"
    )

test "generic callers and direct calls keep their invocation lines":
    let absent: Int? = none
    try expect_equal(
        generic_convert(absent).err().message(),
        "missing value at bound-missing-value-source.ms:5"
    )

    let direct = absent.ok_or()
    try expect_equal(
        direct.err().message(), "missing value at bound-missing-value-source.ms:59"
    )

    let zero: Int? = 0
    let text: String? = "present"
    try expect_equal(generic_convert(zero).get(), 0)
    try expect_equal(generic_convert(text).get(), "present")

test "ordinary callable and inherited defaults receive none":
    let source = ordinary
    let copied = source
    try expect_equal(copied().get(), 77)

    let implementation = Source(77)
    let inherited = implementation.convert
    try expect_equal(inherited().get(), 77)
    try expect_equal(inherited(none).get(), 77)

test "required joins preserve native and source behavior with supplied none":
    let zero: Int? = 0

    for flag in [true, false]:
        let native_first = match flag:
            true: zero.ok_or[MissingValue]
            false: ordinary

        let source_first = match flag:
            true: ordinary
            false: zero.ok_or[MissingValue]

        let native_only = match flag:
            true: zero.ok_or[MissingValue]
            false: zero.ok_or[MissingValue]

        let conditional = if flag: zero.ok_or[MissingValue] else: ordinary
        try expect_equal(native_first(none).get(), if flag: 0 else: 77)
        try expect_equal(source_first(none).get(), if flag: 77 else: 0)
        try expect_equal(native_only(none).get(), 0)
        try expect_equal(conditional(none).get(), if flag: 0 else: 77)

test "supplied none remains supplied and nested Optional errors remain intact":
    let absent: Int? = none
    let convert = absent.ok_or[MissingValue]
    let bound_fault = try expect_fault(
        fn:
            let _ignored = convert(none)
    )
    let direct_fault = try expect_fault(
        fn:
            let _ignored = absent.ok_or[MissingValue](none)
    )
    try expect_true(bound_fault.contains("Optional.get() on none"))
    try expect_true(direct_fault.contains("Optional.get() on none"))

    let supplied = absent.ok_or().err()
    try expect_equal(convert(supplied).err().message(), supplied.message())

    let nested = absent.ok_or[Int?]
    let inner_none: Int? = none
    try expect_true(nested(inner_none).err().is_none())

    let inner_zero: Int? = 0
    try expect_equal(nested(inner_zero).err().get(), 0)

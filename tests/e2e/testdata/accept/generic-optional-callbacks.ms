import expect_true, expect_false, expect_equal, expect_fault from "@std/test/test.ms"

fn every[T](values: List[T], predicate: fn(T) Bool) Bool:
    return values.all(fn value: predicate(value))

fn every_value[T](values: Map[String, T], predicate: fn(T) Bool) Bool:
    return values.all(fn key, value: predicate(value))

fn nested[T](value: T, predicate: fn(T) Bool) Bool:
    outer := fn:
        inner := fn(item: T) Bool: predicate(item)
        return inner(value)

    return outer()

fn defaulted[T](fallback: T, supplied: T, equal: fn(T, T) Bool) Bool:
    choose := fn(value: T = fallback) Bool: equal(value, fallback)
    omitted := choose()
    supplied_result := choose(supplied)
    required: fn(T) Bool = choose
    return omitted and supplied_result and required(supplied)

fn same_optional(left: Int?, right: Int?) Bool:
    if left.is_none(): return right.is_none()
    if right.is_none(): return false

    return left.get() == right.get()

fn optional_default(value: Int? = 7) Int: value.get(-1)

fn bound_missing[T: Clonable](value: T?) T!Error:
    convert := value.ok_or[Error]
    return convert()

fn nested_bound_missing[T: Clonable](value: T?) T!Error:
    convert := fn:
        bound := value.ok_or[Error]
        return bound()

    return convert()

type Defaults:
    base: Int

impl Defaults:
    fn optional(value: Int? = self.base) Int: value.get(-1)

test "generic callbacks preserve Optional inputs and present zero":
    values: List[Int?] = [none, 0, 4]
    try expect_true(every(values, fn value: value.is_none() or value.get() >= 0))
    try expect_false(every(values, fn value: value.is_none()))
    try expect_true(
        every_value(
            {"missing": none, "zero": 0},
            fn(value: Int?): (value.is_none() or value.get() == 0)
        )
    )

test "generic callbacks preserve both layers of nested Optional inputs":
    absent: Int?? = none
    inner_absent: Int? = none
    present_absent: Int?? = inner_absent
    inner_zero: Int? = 0
    present_zero: Int?? = inner_zero
    try expect_true(every([absent], fn value: value.is_none()))
    try expect_true(
        every(
            [present_absent], fn value: (value.is_some() and value.get().is_none())
        )
    )
    try expect_true(
        every(
            [present_zero], fn value: (value.is_some() and value.get().get() == 0)
        )
    )

test "generic callbacks keep Optional inputs through nested closures":
    value: Int? = none
    zero: Int? = 0
    try expect_true(nested(value, fn item: item.is_none()))
    try expect_true(nested(zero, fn item: item.is_some() and item.get() == 0))

test "generic closure defaults and explicit callable arguments keep their behavior":
    try expect_true(defaulted(7, 7, fn left, right: left == right))
    try expect_true(defaulted("seven", "seven", fn left, right: left == right))

    present: Int? = 7
    absent: Int? = none
    try expect_true(defaulted(present, present, same_optional))
    try expect_true(defaulted(absent, absent, same_optional))

test "Optional closure defaults distinguish omitted and explicitly absent values":
    choose := fn(value: Int? = 7) Int: value.get(-1)
    try expect_equal(choose(), 7)
    try expect_equal(choose(none), -1)
    try expect_equal(choose(0), 0)

    required: fn(Int?) Int = choose
    try expect_equal(required(none), -1)

test "named and bound Optional defaults distinguish omitted and absent arguments":
    named := optional_default
    try expect_equal(named(), 7)
    try expect_equal(named(none), -1)

    typed: fn(Int?) Int = named
    try expect_equal(typed(none), -1)

    defaults := Defaults(9)
    bound := defaults.optional
    try expect_equal(bound(), 9)
    try expect_equal(bound(none), -1)
    try expect_equal(bound(0), 0)

test "implicit Optional lambda defaults remain callable through inferred and explicit types":
    implicit := fn(value: Int?) Bool: value.is_none()
    try expect_true(implicit())
    try expect_true(implicit(none))
    try expect_false(implicit(0))

    required: fn(Int?) Bool = implicit
    try expect_true(required(none))

test "bound native Optional arguments stay required after explicit function typing":
    values := [3, 4]
    get := values.get
    try expect_equal(get(0), 3)
    try expect_equal(get(9, 7), 7)

    required: fn(Int, Int?) Int = get
    try expect_equal(required(1, none), 4)
    try expect_equal(required(9, 0), 0)

test "generic native folds accept Optional accumulators without omission wrappers":
    values := {"one": 1, "two": 2}
    initial: Int? = none
    sum := values.fold_right(initial, fn acc, key, value: acc.get(0) + value)
    try expect_equal(sum.get(), 3)

    fold := values.fold_right[Int?]
    bound_sum := fold(initial, fn acc, key, value: acc.get(0) + value)
    try expect_equal(bound_sum.get(), 3)

    set := Set([1, 2])
    set_sum := set.fold_right(initial, fn acc, value: acc.get(0) + value)
    try expect_equal(set_sum.get(), 3)

    fold_set := set.fold_right[Int?]
    bound_set_sum := fold_set(initial, fn acc, value: acc.get(0) + value)
    try expect_equal(bound_set_sum.get(), 3)

test "bound generic native defaults preserve concrete and Optional payload types":
    missing: Int? = none
    text := missing.ok_or[String]
    try expect_equal(text("absent").err(), "absent")

    number := missing.ok_or[Int]
    try expect_equal(number(0).err(), 0)

    nested := missing.ok_or[Int?]
    absent: Int? = none
    try expect_true(nested(absent).err().is_none())

    present: Int? = 0
    try expect_equal(nested(present).err().get(), 0)

test "bound Error defaults distinguish omission from explicit none":
    missing: Int? = none
    direct := missing.ok_or()
    try expect_true(direct.err().message.contains("generic-optional-callbacks.ms:"))

    convert := missing.ok_or[Error]
    converted := convert()
    try expect_true(converted.err().message.contains("generic-optional-callbacks.ms:"))
    try expect_true(
        bound_missing(missing).err().message.contains(
            "generic-optional-callbacks.ms:"
        )
    )
    try expect_true(
        nested_bound_missing(missing).err().message.contains(
            "generic-optional-callbacks.ms:"
        )
    )

    direct_fault := try expect_fault(
        fn:
            _ignored := missing.ok_or[Error](none)
    )
    bound_fault := try expect_fault(
        fn:
            _ignored := convert(none)
    )
    try expect_true(direct_fault.contains("Optional.get() on none"))
    try expect_true(bound_fault.contains("Optional.get() on none"))

    present: Int? = 0
    keep := present.ok_or[Error]
    try expect_equal(keep().get(), 0)
    try expect_equal(keep(none).get(), 0)
    try expect_equal(bound_missing(present).get(), 0)
    try expect_equal(nested_bound_missing(present).get(), 0)

    text: String? = "present"
    try expect_equal(bound_missing(text).get(), "present")
    try expect_equal(nested_bound_missing(text).get(), "present")

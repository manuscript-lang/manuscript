import timestamp, TimeError from "@std/os/time.ms"
import expect_equal from "@std/test/test.ms"

test "calendar format keeps token boundaries and literal text":
    let moment = timestamp(1710073815, 250999999).get()
    try expect_equal(moment.format("", "UTC").get(), "")
    try expect_equal(moment.format("literal", "UTC").get(), "literal")
    try expect_equal(
        moment.format("YYY M D H m s SS Z zon", "UTC").get(), "YYY M D H m s SS Z zon"
    )
    try expect_equal(
        moment.format(
            "YYYYYYYYYMMMMMDDDDHHHHmmmmssssSSSSSSSZZZZzonezone", "UTC"
        ).get(),
        "20242024Y0303M1010121230301515250250S+00:00+00:00UTCUTC"
    )
    try expect_equal(
        moment.format("日付 YYYY 年 MM 月 DD 日 🕰 HH:mm:ss", "UTC").get(),
        "日付 2024 年 03 月 10 日 🕰 12:30:15"
    )

    let bad_zone: String!TimeError = error(TimeError.InvalidInput)
    try expect_equal(moment.format("", "Nowhere/City"), bad_zone)
    try expect_equal(moment.format("literal", "Nowhere/City"), bad_zone)

test "calendar format retains minimum widths outside UTC year limits":
    let first = timestamp(-62135596800, 0).get()
    let last = timestamp(253402300799, 999999999).get()
    try expect_equal(
        first.format("YYYY-MM-DD HH:mm:ss.SSS ZZ [zone]", "-23:59").get(),
        "0000-12-31 00:01:00.000 -23:59 [-23:59]"
    )
    try expect_equal(
        last.format("YYYY-MM-DD HH:mm:ss.SSS ZZ [zone]", "+23:59").get(),
        "10000-01-01 23:58:59.999 +23:59 [+23:59]"
    )

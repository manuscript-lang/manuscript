import expect_equal, expect_ok from "@std/test.ms"
import parse, YamlValue, YamlError, YamlLimits from "@std/yaml.ms"

test "YAML scalar alias fits its exact expanded value budget":
    let text = "[&a 1, *a]"
    let expected = YamlValue.ArrayValue(
        [YamlValue.NumberValue("1"), YamlValue.NumberValue("1")]
    )
    parse(text, YamlLimits(max_values: 3)) | try expect_ok | try expect_equal(expected)

    let limited: YamlValue!YamlError = error(YamlError.LimitExceeded)
    parse(text, YamlLimits(max_values: 2)) | try expect_equal(limited)

test "YAML container alias fits its exact expanded value budget":
    let text = "a: &a [1, 2]\nb: *a"
    let expected = parse(text) | try expect_ok
    parse(text, YamlLimits(max_values: 7)) | try expect_ok | try expect_equal(expected)

    let limited: YamlValue!YamlError = error(YamlError.LimitExceeded)
    parse(text, YamlLimits(max_values: 6)) | try expect_equal(limited)

test "YAML mapping alias keys stay outside the value budget":
    let text = "[&s name, \{*s : 1\}]"
    let expected = parse(text) | try expect_ok
    parse(text, YamlLimits(max_values: 4)) | try expect_ok | try expect_equal(expected)

    let limited: YamlValue!YamlError = error(YamlError.LimitExceeded)
    parse(text, YamlLimits(max_values: 3)) | try expect_equal(limited)

test "YAML nested aliases fit their exact expanded value budget":
    let text = "[&a [1], &b [*a], *b]"
    let expected = parse(text) | try expect_ok
    parse(text, YamlLimits(max_values: 9)) | try expect_ok | try expect_equal(expected)

    let limited: YamlValue!YamlError = error(YamlError.LimitExceeded)
    parse(text, YamlLimits(max_values: 8)) | try expect_equal(limited)

test "YAML alias expansion still checks the returned tree depth":
    let text = "[&a [1], [*a]]"
    let expected = parse(text) | try expect_ok
    parse(text, YamlLimits(max_depth: 4)) | try expect_ok | try expect_equal(expected)

    let limited: YamlValue!YamlError = error(YamlError.LimitExceeded)
    parse(text, YamlLimits(max_depth: 3)) | try expect_equal(limited)

from "@std/test.ms" import expect_equal, expect_false, expect_ok, expect_true, fail
from "@std/string.ms" import from_scalars
from "@std/core.ms" import TextError
from "@std/collections.ms" import range
from "@std/yaml.ms" import parse, stringify, YamlValue, YamlError, YamlLimits

def entries(value: YamlValue) -> Result[Map[String, YamlValue], Error]:
    match value:
        case ObjectValue(values): return ok(values)
        case _: return error(TextError("expected YAML mapping"))

def items(value: YamlValue) -> Result[List[YamlValue], Error]:
    match value:
        case ArrayValue(values): return ok(values)
        case _: return error(TextError("expected YAML sequence"))

def limits(
    bytes: Optional[Int],
    depth: Optional[Int],
    values: Optional[Int]
) -> Optional[YamlLimits]:
    return some(YamlLimits(max_bytes: bytes, max_depth: depth, max_values: values))

type ScalarCase:
    text: String
    expected: String

def scalar(text: String, expected: String) -> Result[Unit, Error]:
    let root = parse(text: text) | try expect_ok | try entries
    if root.get("a").get() != YamlValue.StringValue(expected): return error(
        TextError(f"scalar folding: {text}")
    )

    return ok(())


from "@std/io.ms" import stdout

def run() -> Result[Unit, Error]:
    let cases = [
        ScalarCase(text: "a: 'x \t\n \t\n  y'", expected: "x\ny"),
        ScalarCase(text: "a: \"x \t\n \t\n\n  y\"", expected: "x\n\ny"),
        ScalarCase(text: "a: ' x  \n  y '", expected: " x y "),
        ScalarCase(text: "a: \"x\\t\n  y\"", expected: "x\t y"),
        ScalarCase(text: "a: \"x\\ \n  y\"", expected: "x  y"),
        ScalarCase(text: "a: \"x \\\n  y\"", expected: "x y"),
        ScalarCase(text: "a: \"x \\\n \t\n\n  y\"", expected: "x \n\ny"),
        ScalarCase(
            text: "a: 'x\n\n  # hash: text\n\n  it''s y' # outside",
            expected: "x\n# hash: text\nit's y"
        ),
        ScalarCase(
            text: "a: \"x\n\n  \\\"y\\\"\" # outside", expected: "x\n\"y\""
        )
    ]
    for example in cases:
        for ending in ["\n", "\r\n", "\r"]:
            (
                try scalar(
                    text: (
                        example
                        .text
                        .replace(old: "\n", new: ending)
                    ),
                    expected: example.expected.clone()
                )
            )
    return ok(())

export def main() -> Int:
    for n in range(0, 300):
        match run():
            case ok(_): continue
            case error(_): return 1
    let _ = stdout().write("done\n")
    return 0

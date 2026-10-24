from "@std/io.ms" import stdout

type DivideError:
    case DivideByZero
    case Overflow

impl Error for DivideError:
    def message() -> String:
        match self:
            case DivideByZero: return "divide by zero"
            case Overflow: return "overflow"

extern def greet_divide(left: Int, right: Int) -> Result[Int, DivideError]

extern def greet_shout(name: String) -> Result[String, DivideError]

extern def greet_check(value: Int) -> Result[Unit, DivideError]

extern def greet_double(value: Int) -> Int

extern def greet_scale(value: Float, factor: Float) -> Float

extern def greet_is_long(name: String, limit: Int) -> Bool

extern def greet_hello(name: String) -> String

def describe(result: Result[Int, DivideError]) -> String:
    if let value = result:
        return f"ok {value}"

    return f"error {result.err().message()}"

def shout(result: Result[String, DivideError]) -> String:
    if let value = result:
        return value.clone()

    return f"error {result.err().message()}"

export def main() -> Int:
    var out = stdout()
    out.write(greet_double(21).to_string() + "\n")
    out.write(greet_scale(1.5, 4.0).to_string() + "\n")
    out.write(
        greet_is_long("short", 10).to_string() + " " + greet_is_long(
            "a much longer name than that", 10
        ).to_string() + "\n"
    )
    out.write(greet_hello("world") + "\n")
    out.write(greet_hello("a considerably longer visitor name") + "\n")
    out.write(describe(greet_divide(7, 2)) + " " + describe(greet_divide(1, 0)) + "\n")
    out.write(
        shout(greet_shout("quiet")) + "|" + shout(
            greet_shout("")
        ) + "|" + shout(
            greet_shout(
                "this name is much too long to fit into the sixty-four byte buffer ok"
            )
        ) + "\n"
    )
    out.write(
        greet_check(3).is_ok().to_string() + " " + greet_check(
            -3
        ).is_error().to_string() + "\n"
    )
    return 0

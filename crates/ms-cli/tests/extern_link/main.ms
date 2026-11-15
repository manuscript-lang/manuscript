import stdout from "@std/io/io.ms"

enum DivideError:
    DivideByZero
    Overflow

fn text(cause: DivideError) String:
    match cause:
        DivideByZero: return "divide by zero"
        Overflow: return "overflow"

extern fn greet_divide(left: Int, right: Int) Result[Int, DivideError]

extern fn greet_shout(name: String) Result[String, DivideError]

extern fn greet_check(value: Int) Result[Void, DivideError]

extern fn greet_double(value: Int) Int

extern fn greet_scale(value: Float, factor: Float) Float

extern fn greet_is_long(name: String, limit: Int) Bool

extern fn greet_hello(name: String) String

fn describe(result: Result[Int, DivideError]) String:
    if value := result:
        return "ok {value}"

    return "error {text(result.err())}"

fn shout(result: Result[String, DivideError]) String:
    if value := result:
        return value.clone()

    return "error {text(result.err())}"

fn main() Void:
    var out = stdout()
    void out.write(greet_double(21).to_string() + "\n")
    void out.write(greet_scale(1.5, 4.0).to_string() + "\n")
    void out.write(
        greet_is_long("short", 10).to_string() + " " + greet_is_long(
            "a much longer name than that", 10
        ).to_string() + "\n"
    )
    void out.write(greet_hello("world") + "\n")
    void out.write(greet_hello("a considerably longer visitor name") + "\n")
    void out.write(
        describe(greet_divide(7, 2)) + " " + describe(greet_divide(1, 0)) + "\n"
    )
    void out.write(
        shout(greet_shout("quiet")) + "|" + shout(
            greet_shout("")
        ) + "|" + shout(
            greet_shout(
                "this name is much too long to fit into the sixty-four byte buffer ok"
            )
        ) + "\n"
    )
    void out.write(
        greet_check(3).is_ok().to_string() + " " + greet_check(
            -3
        ).is_error().to_string() + "\n"
    )

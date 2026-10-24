import {stdout} from "@std/io.ms"

extern fn greet_double(value: Int) Int
extern fn greet_scale(value: Float, factor: Float) Float
extern fn greet_is_long(name: String, limit: Int) Bool
extern fn greet_hello(name: String) String

export fn main() Int:
    var out = stdout()
    out.write(greet_double(21).to_string() + "\n")
    out.write(greet_scale(1.5, 4.0).to_string() + "\n")
    out.write(greet_is_long("short", 10).to_string() + " " + greet_is_long("a much longer name than that", 10).to_string() + "\n")
    out.write(greet_hello("world") + "\n")
    out.write(greet_hello("a considerably longer visitor name") + "\n")
    return 0

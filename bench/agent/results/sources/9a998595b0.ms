import stdout from "@std/io.ms"
import dump, format_number, parse_whole, Json from "./json.ms"

export fn main() Int:
    stdout().write(dump(Json.JNum(1.5e-7)).concat("\n")).get()
    return 0

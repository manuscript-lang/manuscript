from "@std/io.ms" import stdout
from "./json.ms" import dump, format_number, parse_whole, Json

export def main() -> Int:
    stdout().write(dump(Json.JNum(1.5e-7)).concat("\n")).get()
    return 0

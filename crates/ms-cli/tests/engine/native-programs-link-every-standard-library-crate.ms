import parse, format from "@std/data/semver.ms"

export fn main() Int:
    let v = parse("1.2.3").get()
    if format(v) == "1.2.3":
        return 0

    return 1

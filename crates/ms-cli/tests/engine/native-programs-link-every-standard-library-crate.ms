from "@std/semver.ms" import parse, format

export def main() -> Int:
    let v = parse("1.2.3").get()
    if format(v) == "1.2.3":
        return 0
    return 1

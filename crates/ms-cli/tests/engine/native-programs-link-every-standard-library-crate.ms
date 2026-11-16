import parse from "@std/data/semver.ms"

export fn main() Int:
    v := parse("1.2.3").get()
    if v.to_string() == "1.2.3":
        return 0

    return 1

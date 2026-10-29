import {lines, stdin} from "@std/io.ms"

export fn main() Int:
    let reader = lines(stdin())
    for line in reader:
        if line == "":
            return 1
    return 0

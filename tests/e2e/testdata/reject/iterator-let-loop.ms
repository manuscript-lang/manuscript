from "@std/io.ms" import lines, stdin

export def main() -> Int:
    let reader = lines(stdin())
    for line in reader:
        if line == "":
            return 1
    return 0

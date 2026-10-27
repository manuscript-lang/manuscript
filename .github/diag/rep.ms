from "@std/io.ms" import stdout

export def main() -> Int:
    let texts = ["a: 'x \t\n \t\n  y'", "a: \"x\\t\n  y\"", "a: x\n\n  y\nb: 1"]
    for text in texts:
        for ending in ["\n", "\r\n", "\r"]:
            let out = text.replace(old: "\n", new: ending)
            let _ = stdout().write(f"{out.length()}\n")
    return 0

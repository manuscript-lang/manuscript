from "@std/io.ms" import stdout
from "@std/yaml.ms" import parse

export def main() -> Int:
    let texts = ["a: 'x \t\n \t\n  y'", "a: \"x \t\n \t\n\n  y\"", "a: ' x  \n  y '", "a: \"x\\t\n  y\""]
    for text in texts:
        for ending in ["\n", "\r\n", "\r"]:
            let _m = stdout().write(f"parse {ending.length()}\n")
            let r = parse(text: text.replace(old: "\n", new: ending))
            let _ = stdout().write(f"ok {r.is_ok()}\n")
    return 0

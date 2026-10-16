import panic from "@std/faults.ms"

# Deterministic generator so failures reproduce from the seed in the message.
export type Rng:
    state: Int

export fn next(rng: Rng, bound: Int) -> Int:
    rng.state = (rng.state * 1103515245 + 12345) % 2147483648
    return (rng.state / 65536) % bound

let pieces = [
    "",
    " ",
    "a",
    "key",
    "-",
    "- ",
    ":",
    ": ",
    "#",
    " #",
    "'",
    "\"",
    "\\",
    "\n",
    "\t",
    "é",
    "🙂",
    "null",
    "true",
    "yes",
    "123",
    "1e3",
    "~",
    "[",
    "]",
    "\{",
    "\}",
    ",",
    "&a",
    "*a",
    "!",
    "|",
    ">",
    "%",
    "---",
    "...",
    "@",
    "`",
    "?",
    "="
]

export fn text(rng: Rng) -> String:
    var out = ""
    var count = next(rng, 4)

    while count > 0:
        out = out + pieces[next(rng, pieces.length())].unwrap_or("")
        count = count - 1

    return out

# Deletes, inserts or replaces one character-sized piece of source text.
export fn mutate(rng: Rng, source: String) -> String:
    let chars = source.chars()
    let at = next(rng, chars.length() + 1)
    let kind = next(rng, 3)

    if kind != 1 and at < chars.length(): chars.remove(at)

    if kind != 0: chars.insert(at, pieces[next(rng, pieces.length())].unwrap_or(""))

    return chars.join("")

from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines
from "@std/string.ms" import from_scalars

def is_upper(c: Int) -> Bool: c >= 65 and c <= 90

def is_lower(c: Int) -> Bool: c >= 97 and c <= 122

def is_letter(c: Int) -> Bool: is_upper(c) or is_lower(c)

def is_digit(c: Int) -> Bool: c >= 48 and c <= 57

# Code point of the first letter of the alphabet in the same case as `c`.
def base_of(c: Int) -> Int: 97 if is_lower(c) else 65

# Shifts an ASCII letter by `amount` positions, wrapping within its case.
def shift_letter(c: Int, amount: Int) -> Int:
    let base = base_of(c)
    return base + (c - base + amount % 26 + 26) % 26

def is_caesar_key(key: String) -> Bool:
    let values = key.scalar_values()
    var start = 0
    if values.length() > 0 and values[0] == 45:
        start = 1

    let count = values.length() - start
    if count < 1 or count > 7:
        return False

    for i in start..values.length():
        if not is_digit(values[i]):
            return False
    return True

def is_vigenere_key(key: String) -> Bool:
    let values = key.scalar_values()
    if values.length() == 0:
        return False

    for c in values:
        if not is_letter(c):
            return False
    return True

def caesar(text: List[Int], amount: Int) -> List[Int]:
    var out = List[Int]()
    for c in text:
        out.append(shift_letter(c, amount) if is_letter(c) else c)
    return out

def vigenere(text: List[Int], key: List[Int], decrypt: Bool) -> List[Int]:
    var out = List[Int]()
    var k = 0

    for c in text:
        if is_letter(c):
            let shift = key[k] - base_of(key[k])
            out.append(shift_letter(c, -shift if decrypt else shift))
            k = (k + 1) % key.length()
        else:
            out.append(c)

    return out

# Rejoins the fields from `start` on with single spaces, restoring the text that was split on spaces.
def join_from(parts: List[String], start: Int) -> String:
    var out = ""

    for i in start..parts.length():
        if i > start:
            out = out + " "
        out = out + parts[i]

    return out

def convert(line: String) -> String:
    let parts = line.split(" ")
    if parts.length() < 4:
        return "error: bad command"

    let cipher = parts[0]
    let mode = parts[1]
    let key = parts[2]
    let rest = join_from(parts, 3)
    if rest.is_empty():
        return "error: bad command"
    if cipher != "caesar" and cipher != "vigenere":
        return "error: bad cipher"
    if mode != "enc" and mode != "dec":
        return "error: bad mode"

    let decrypt = mode == "dec"
    let text = rest.scalar_values()

    if cipher == "caesar":
        if not is_caesar_key(key):
            return "error: bad key"

        let amount = key.parse_int().get(0)
        return from_scalars(caesar(text, -amount if decrypt else amount)).get("")

    if not is_vigenere_key(key):
        return "error: bad key"

    return from_scalars(vigenere(text, key.scalar_values(), decrypt)).get("")

def is_blank(line: String) -> Bool:
    for c in line.scalar_values():
        if c != 32:
            return False
    return True

export def main() -> Int:
    for line in read_lines(stdin()).get():
        if not is_blank(line):
            stdout().write(convert(line) + "\n").get()
    return 0

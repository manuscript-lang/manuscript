from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines
from "@std/string.ms" import from_scalars
from "@std/collections.ms" import range

def is_letter(c: Int) -> Bool: (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

def is_digit(c: Int) -> Bool: c >= 48 and c <= 57

def is_space(c: Int) -> Bool: c == 32

# Shifts one ASCII letter forward by `shift` (0-25), keeping its case; other scalars pass through.
def rotate(c: Int, shift: Int) -> Int:
    if c >= 65 and c <= 90: return 65 + (c - 65 + shift) % 26
    if c >= 97 and c <= 122: return 97 + (c - 97 + shift) % 26

    return c

def all_scalars(values: List[Int], check: Callable[[Int], Bool]) -> Bool:
    for c in values:
        if not check(c): return False
    return True

def caesar_key(key: String) -> Optional[Int]:
    let scalars = key.scalar_values()

    let start = (1 if scalars.length() > 0 and scalars[0] == 45 else 0)

    if scalars.length() - start < 1 or scalars.length() - start > 7: return none

    for i in range(start, scalars.length()):
        if not is_digit(scalars[i]): return none
    return key.parse_int()

# Returns the alphabet index (0-25) of each letter of a Vigenere key, or none if the key is empty or has a non-letter.
def vigenere_shifts(key: String) -> Optional[List[Int]]:
    let scalars = key.scalar_values()
    if scalars.length() == 0 or not all_scalars(scalars.clone(), is_letter): return none

    var shifts: List[Int] = []

    for c in scalars:
        if c >= 97: shifts.append(c - 97)
        else: shifts.append(c - 65)

    return some(shifts)

def run_line(line: String) -> String:
    let parts = line.split(" ")
    if parts.length() < 4: return "error: bad command"

    let text = parts.slice(3, parts.length()).get().join(" ")
    if text.is_empty(): return "error: bad command"

    let cipher = parts[0]
    let mode = parts[1]
    let key = parts[2]
    let scalars = text.scalar_values()
    if cipher != "caesar" and cipher != "vigenere": return "error: bad cipher"
    if mode != "enc" and mode != "dec": return "error: bad mode"

    var sign = -1
    if mode == "enc": sign = 1

    if cipher == "caesar":
        if let n = caesar_key(key):
            let shift = ((sign * n) % 26 + 26) % 26
            return from_scalars(scalars.map(lambda c: rotate(c, shift))).get()

        return "error: bad key"

    if let shifts = vigenere_shifts(key):
        var out: List[Int] = []
        var k = 0

        for c in scalars:
            if is_letter(c):
                let s = shifts[k % shifts.length()]
                out.append(rotate(c, ((sign * s) % 26 + 26) % 26))
                k += 1
            else:
                out.append(c)

        return from_scalars(out).get()

    return "error: bad key"

export def main() -> Int:
    for line in read_lines(stdin()).get():
        if all_scalars(line.scalar_values(), is_space): continue

        stdout().write(f"{run_line(line)}\n").get()

    return 0

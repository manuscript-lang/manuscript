import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"
import from_scalars from "@std/string.ms"

# First code point of the alphabet that `v` belongs to ('A' or 'a'), or -1 for any other character.
fn letter_base(v: Int) Int:
    if v >= 65 and v <= 90: return 65
    if v >= 97 and v <= 122: return 97

    return -1

# Shifts a letter forward by `shift` (may be negative), keeping its case; other characters are unchanged.
fn rotate(v: Int, shift: Int) Int:
    let base = letter_base(v)
    if base < 0: return v

    return base + (v - base + (shift % 26) + 26) % 26

# A decimal integer: optional leading "-", then 1 to 7 digits.
fn caesar_key(key: String) Optional[Int]:
    let start = if key.starts_with("-"): 1 else: 0

    let digits = key.length() - start
    if digits < 1 or digits > 7: return none

    let vs = key.scalar_values()
    for i in start..vs.length():
        if vs[i] < 48 or vs[i] > 57: return none
    return key.parse_int()

fn vigenere_key(key: String) Optional[List[Int]]:
    if key.length() == 0: return none

    let vs = key.scalar_values()
    for v in vs:
        if letter_base(v) < 0: return none
    return some(vs.map(fn(v: Int) Int: v - letter_base(v)))

fn is_blank(line: String) Bool:
    for v in line.scalar_values():
        if v != 32: return false
    return true

fn run(cipher: String, sign: Int, key: String, text: String) String:
    let vs = text.scalar_values()

    if cipher == "caesar":
        if let k = caesar_key(key):
            return from_scalars(vs.map(fn(v: Int) Int: rotate(v, sign * k))).get("")

        return "error: bad key"

    if let shifts = vigenere_key(key):
        var j = 0
        var out = List[Int]()

        for v in vs:
            if letter_base(v) < 0:
                out.append(v)
            else:
                out.append(rotate(v, sign * shifts[j]))
                j = (j + 1) % shifts.length()

        return from_scalars(out).get("")

    return "error: bad key"

fn process(line: String) String:
    let parts = line.split(" ")
    if parts.length() < 4: return "error: bad command"

    # The text is everything after the third space, so it keeps any spaces it contains.
    var rest = List[String]()
    for i in 3..parts.length(): rest.append(parts[i].clone())

    let text = rest.join(" ")
    if text.length() == 0: return "error: bad command"

    let cipher = parts[0]
    let mode = parts[1]
    if cipher != "caesar" and cipher != "vigenere": return "error: bad cipher"
    if mode != "enc" and mode != "dec": return "error: bad mode"

    let sign = if mode == "enc": 1 else: -1

    return run(cipher, sign, parts[2], text)

export fn main() Int:
    if let lines = read_lines(stdin()):
        var out = stdout()
        for line in lines:
            if not is_blank(line):
                out.write(process(line) + "\n").get()

    return 0

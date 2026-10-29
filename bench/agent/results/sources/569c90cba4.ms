import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"
import from_scalars from "@std/string.ms"

fn is_upper(c: Int) Bool: c >= 65 and c <= 90

fn is_lower(c: Int) Bool: c >= 97 and c <= 122

fn is_letter(c: Int) Bool: is_upper(c) or is_lower(c)

# Index 0 for 'A'/'a' through 25 for 'Z'/'z'; only valid for ASCII letters.
fn letter_index(c: Int) Int:
    if is_lower(c): return c - 97

    return c - 65

fn wrap(n: Int) Int: (n % 26 + 26) % 26

# Shifts one scalar within its ASCII case; every other scalar is returned unchanged.
fn rotate(c: Int, shift: Int) Int:
    if is_upper(c): return 65 + wrap(c - 65 + shift)
    if is_lower(c): return 97 + wrap(c - 97 + shift)

    return c

# Parses an optional '-' followed by 1 through 7 ASCII digits.
fn caesar_key(key: String) Optional[Int]:
    let codes = key.scalar_values()
    let negative = codes.length() > 0 and codes[0] == 45

    let start = if negative: 1 else: 0

    let digits = codes.length() - start
    if digits < 1 or digits > 7: return none

    var value = 0

    for i in start..codes.length():
        let c = codes[i]
        if c < 48 or c > 57: return none

        value = value * 10 + c - 48

    return if negative: -value else: value

fn is_key_word(codes: List[Int]) Bool:
    if codes.length() == 0: return false

    for c in codes:
        if not is_letter(c): return false
    return true

fn caesar(text: String, key: Int, decrypt: Bool) String:
    let shift = if decrypt: -key else: key

    var out = List[Int]()
    for c in text.scalar_values():
        out.append(rotate(c, shift))
    return from_scalars(out).get()

fn vigenere(text: String, key: String, decrypt: Bool) String:
    let key_codes = key.scalar_values()
    var out = List[Int]()
    var k = 0

    for c in text.scalar_values():
        if is_letter(c):
            let s = letter_index(key_codes[k % key_codes.length()])
            out.append(rotate(c, if decrypt: -s else: s))
            k += 1
        else:
            out.append(c)

    return from_scalars(out).get()

fn run(line: String) String:
    let parts = line.split(" ")
    if parts.length() < 4: return "error: bad command"

    let text = line.drop(parts[0].length() + parts[1].length() + parts[2].length() + 3)
    if text.is_empty(): return "error: bad command"

    let cipher = parts[0]
    let mode = parts[1]
    let key = parts[2]
    if cipher != "caesar" and cipher != "vigenere": return "error: bad cipher"
    if mode != "enc" and mode != "dec": return "error: bad mode"

    let decrypt = mode == "dec"

    if cipher == "caesar":
        if let shift = caesar_key(key):
            return caesar(text, shift, decrypt)
        else:
            return "error: bad key"

    if not is_key_word(key.scalar_values()): return "error: bad key"

    return vigenere(text, key, decrypt)

fn is_blank(line: String) Bool: line.split(" ").join("").is_empty()

export fn main() Int:
    for line in read_lines(stdin()).get():
        if not is_blank(line):
            stdout().write(run(line) + "\n").get()
    return 0

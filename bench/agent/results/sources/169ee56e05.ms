import {stdin, stdout} from "@std/io.ms"
import {read_lines} from "@std/streams.ms"
import {range} from "@std/collections.ms"

let UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
let LOWER = "abcdefghijklmnopqrstuvwxyz"
let DIGITS = "0123456789"

# Returns the alphabet index (0 through 25) of an ASCII letter, or -1 for any other text.
fn letter_index(c: String) Int:
    let code = c.to_bytes().get(0, -1)
    if code >= 65 and code <= 90:
        return code - 65
    if code >= 97 and code <= 122:
        return code - 97

    return -1

# Shifts one character by `shift` places, keeping its case; other characters are returned unchanged.
fn shift_char(c: String, shift: Int) String:
    let index = letter_index(c)
    if index < 0:
        return c

    let wrapped = ((index + shift) % 26 + 26) % 26
    if c.to_bytes().get(0) >= 97:
        return LOWER.slice(wrapped, wrapped + 1).get()

    return UPPER.slice(wrapped, wrapped + 1).get()

fn is_blank(line: String) Bool:
    for c in line.chars():
        if c != " ":
            return false
    return true

# Returns the caesar shift for a key, or none when the key is not an integer of at most 7 digits.
fn caesar_shift(key: String) Optional[Int]:
    var digits = 0
    var sign = 0

    for c in key.chars():
        if c == "-" and digits == 0 and sign == 0:
            sign = 1
        else if DIGITS.contains(c):
            digits += 1
        else:
            return none

    if digits < 1 or digits > 7:
        return none

    return key.parse_int()

# Returns the shift of each key letter, or none when the key is empty or has a non-letter.
fn vigenere_shifts(key: String) Optional[List[Int]]:
    var shifts: List[Int] = []

    for c in key.chars():
        let index = letter_index(c)
        if index < 0:
            return none

        shifts.append(index)

    if shifts.is_empty():
        return none

    return shifts

fn transform(text: String, cipher: String, decrypt: Bool, key: String) Optional[String]:
    var out = ""

    if cipher == "caesar":
        if let shift = caesar_shift(key):
            var amount = shift
            if decrypt:
                amount = -shift
            for c in text.chars():
                out = out.concat(shift_char(c, amount))
            return out

        return none

    if let shifts = vigenere_shifts(key):
        var pos = 0

        for c in text.chars():
            if letter_index(c) < 0:
                out = out.concat(c)
            else:
                let base = shifts[pos % shifts.length()]
                var amount = base
                if decrypt:
                    amount = -amount
                out = out.concat(shift_char(c, amount))
                pos += 1

        return out

    return none

fn process(line: String) String:
    let parts = line.split(" ")
    if parts.length() < 4:
        return "error: bad command"

    var text = ""

    for i in range(3, parts.length()):
        if i > 3:
            text = text.concat(" ")
        text = text.concat(parts[i])

    if text == "":
        return "error: bad command"

    let cipher = parts[0]
    if cipher != "caesar" and cipher != "vigenere":
        return "error: bad cipher"

    let mode = parts[1]
    if mode != "enc" and mode != "dec":
        return "error: bad mode"
    if let result = transform(text, cipher, mode == "dec", parts[2]):
        return result

    return "error: bad key"

export fn main() Int:
    for line in read_lines(stdin()).get():
        if is_blank(line):
            continue

        stdout().write("{process(line)}\n").get()

    return 0

import {stdin, stdout, read_line} from "@std/io.ms"
import {from_scalars} from "@std/string.ms"
import {range} from "@std/collections.ms"

fn is_blank(line: String) Bool:
    for ch in line.chars():
        if ch != " ":
            return false
    return true

fn is_ascii_digit(value: Int) Bool:
    return value >= 48 and value <= 57

fn is_ascii_letter(value: Int) Bool:
    return (value >= 65 and value <= 90) or (value >= 97 and value <= 122)

# Base code point of the alphabet that a letter belongs to.
fn letter_base(value: Int) Int:
    if value >= 97:
        return 97

    return 65

fn valid_caesar_key(key: String) Bool:
    let values = key.scalar_values()
    var start = 0
    if key.starts_with("-"):
        start = 1
    let digits = values.length() - start
    if digits == 0 or digits > 7:
        return false

    for index in range(start, values.length()):
        if not is_ascii_digit(values.get(index)):
            return false
    return true

fn valid_vigenere_key(key: String) Bool:
    let values = key.scalar_values()
    if values.length() == 0:
        return false

    for value in values:
        if not is_ascii_letter(value):
            return false
    return true

# Caesar shift for encryption, normalized to 0..25.
fn caesar_shift(key: String) Int:
    let value = key.parse_int().get()
    return ((value % 26) + 26) % 26

fn caesar(text: String, shift: Int) String:
    var out: List[Int] = []

    for value in text.scalar_values():
        if is_ascii_letter(value):
            let base = letter_base(value)
            out.append(base + (value - base + shift) % 26)
        else:
            out.append(value)

    return from_scalars(out).get()

fn vigenere(text: String, key: String, decrypt: Bool) String:
    let key_values = key.scalar_values()
    var out: List[Int] = []
    var position = 0

    for value in text.scalar_values():
        if is_ascii_letter(value):
            let key_value = key_values.get(position % key_values.length())
            var shift = key_value - letter_base(key_value)
            if decrypt:
                shift = 26 - shift
            let base = letter_base(value)
            out.append(base + (value - base + shift) % 26)
            position += 1
        else:
            out.append(value)

    return from_scalars(out).get()

fn run_command(line: String) String:
    let parts = line.split(" ")
    if parts.length() < 4:
        return "error: bad command"

    let cipher = parts.get(0)
    let mode = parts.get(1)
    let key = parts.get(2)
    var text = ""

    for index in range(3, parts.length()):
        if index > 3:
            text = "{text} "
        text = "{text}{parts.get(index)}"

    if text == "":
        return "error: bad command"
    if cipher != "caesar" and cipher != "vigenere":
        return "error: bad cipher"
    if mode != "enc" and mode != "dec":
        return "error: bad mode"

    let decrypt = mode == "dec"

    if cipher == "caesar":
        if not valid_caesar_key(key):
            return "error: bad key"

        var shift = caesar_shift(key)
        if decrypt:
            shift = (26 - shift) % 26
        return caesar(text, shift)

    if not valid_vigenere_key(key):
        return "error: bad key"

    return vigenere(text, key, decrypt)

export fn main() Int:
    let input = stdin()
    let output = stdout()
    var more = true

    while more:
        let next = read_line(input).get()

        if let line = next:
            if not is_blank(line):
                output.write("{run_command(line)}\n").get()
        else:
            more = false

    output.flush().get()
    return 0

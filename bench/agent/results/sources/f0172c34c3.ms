import stdin, stdout, read_line from "@std/io.ms"

LOWER := "abcdefghijklmnopqrstuvwxyz"
UPPER := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
DIGITS := "0123456789"

// Index of an ASCII letter in the alphabet (case-insensitive), or -1.
fn letter_index(c: String) Int:
    if i := LOWER.index_of(c):
        return i
    if i := UPPER.index_of(c):
        return i

    return -1

// Moves a letter forward by `by` positions (0 to 25); other characters are copied.
fn rotate(c: String, by: Int) String:
    if i := LOWER.index_of(c):
        return LOWER.get((i + by) % 26)
    if i := UPPER.index_of(c):
        return UPPER.get((i + by) % 26)

    return c

fn mod26(n: Int) Int:
    return ((n % 26) + 26) % 26

// Parses an optional leading `-` and 1 to 7 decimal digits.
fn caesar_key(key: String) Optional[Int]:
    neg := key.starts_with("-")

    body := if neg: key.drop(1) else: key

    if body.is_empty() or body.scalar_length() > 7:
        return none

    var n = 0

    for c in body.chars():
        if d := DIGITS.index_of(c):
            n = n * 10 + d
        else:
            return none

    return if neg: -n else: n

fn is_blank(line: String) Bool:
    for c in line.chars():
        if c != " ":
            return false
    return true

// Returns the output line for one non-blank command line.
fn run(line: String) String:
    parts := line.split(" ")
    if parts.length() < 4:
        return "error: bad command"

    cipher := parts[0]
    mode := parts[1]
    key := parts[2]
    text := parts.slice(3, parts.length()).get().join(" ")
    if text.is_empty():
        return "error: bad command"
    if cipher != "caesar" and cipher != "vigenere":
        return "error: bad cipher"
    if mode != "enc" and mode != "dec":
        return "error: bad mode"

    decrypt := mode == "dec"
    var out = ""

    if cipher == "caesar":
        if k := caesar_key(key.clone()):
            shift := mod26(if decrypt: -k else: k)
            for c in text.chars():
                out += rotate(c, shift)
            return out

        return "error: bad key"

    if key.is_empty():
        return "error: bad key"

    var shifts = List[Int]()

    for k in key.chars():
        i := letter_index(k)
        if i < 0:
            return "error: bad key"

        shifts.append(if decrypt: -i else: i)

    var pos = 0

    for c in text.chars():
        if letter_index(c) < 0:
            out += c
        else:
            out += rotate(c, mod26(shifts[pos % shifts.length()]))
            pos += 1

    return out

export fn main() Int:
    var out = stdout()
    input := stdin()

    while true:
        got := read_line(input).get()

        if line := got:
            if is_blank(line):
                continue

            out.write("{run(line)}\n").get()
        else:
            break

    return 0

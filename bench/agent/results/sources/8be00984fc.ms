import stdin, stdout from "@std/io/io.ms"
import lines from "@std/io/streams.ms"
import from_scalars from "@std/string.ms"

fn is_blank(line: String) Bool:
    for c in line.scalar_values():
        if c != 32:
            return false
    return true

fn is_upper(c: Int) Bool:
    return c >= 65 and c <= 90

fn is_lower(c: Int) Bool:
    return c >= 97 and c <= 122

fn is_letter(c: Int) Bool:
    return is_upper(c) or is_lower(c)

fn wrap26(x: Int) Int:
    return ((x % 26) + 26) % 26

// Shifts a letter by s positions, keeping its case; other scalars are unchanged.
fn shift_scalar(c: Int, s: Int) Int:
    if is_upper(c):
        return 65 + wrap26(c - 65 + s)
    if is_lower(c):
        return 97 + wrap26(c - 97 + s)

    return c

// Parses an optional leading '-' followed by 1 to 7 decimal digits.
fn parse_caesar(k: List[Int]) Int?:
    var i = 0
    var neg = false

    if k.length() > 0 and k[0] == 45:
        neg = true
        i = 1

    let digits = k.length() - i
    if digits < 1 or digits > 7:
        return none

    var v = 0

    while i < k.length():
        let c = k[i]
        if c < 48 or c > 57:
            return none

        v = v * 10 + (c - 48)
        i += 1

    if neg:
        return -v

    return v

fn valid_vigenere_key(k: List[Int]) Bool:
    if k.length() == 0:
        return false

    for c in k:
        if not is_letter(c):
            return false
    return true

// Shift of a key letter: A/a is 0, B/b is 1, and so on.
fn key_shift(c: Int) Int:
    if is_lower(c):
        return c - 97

    return c - 65

// Index of the first space at or after `from`, or -1.
fn find_space(cs: List[Int], from: Int) Int:
    var i = from

    while i < cs.length():
        if cs[i] == 32:
            return i

        i += 1

    return -1

// Copies scalars in [start, end).
fn sub(cs: List[Int], start: Int, end: Int) List[Int]:
    var out = List[Int]()
    var i = start

    while i < end:
        out.append(cs[i])
        i += 1

    return out

fn process(line: String) String:
    let cs = line.scalar_values()
    let s1 = find_space(cs, 0)
    if s1 < 0:
        return "error: bad command"

    let s2 = find_space(cs, s1 + 1)
    if s2 < 0:
        return "error: bad command"

    let s3 = find_space(cs, s2 + 1)
    if s3 < 0 or s3 + 1 >= cs.length():
        return "error: bad command"

    let cipher = from_scalars(sub(cs, 0, s1)).get()
    let mode = from_scalars(sub(cs, s1 + 1, s2)).get()
    let kv = sub(cs, s2 + 1, s3)
    let tv = sub(cs, s3 + 1, cs.length())
    if cipher != "caesar" and cipher != "vigenere":
        return "error: bad cipher"
    if mode != "enc" and mode != "dec":
        return "error: bad mode"

    let enc = mode == "enc"

    if cipher == "caesar":
        if let k = parse_caesar(kv):
            let sh = if enc: k else: -k
            var out = List[Int]()
            for c in tv:
                out.append(shift_scalar(c, sh))
            return from_scalars(out).get()

        return "error: bad key"

    if not valid_vigenere_key(kv):
        return "error: bad key"

    var out = List[Int]()
    var j = 0

    for c in tv:
        if is_letter(c):
            let ks = key_shift(kv[j])
            let sh = if enc: ks else: -ks
            out.append(shift_scalar(c, sh))
            j = (j + 1) % kv.length()
        else:
            out.append(c)

    return from_scalars(out).get()

fn run() Unit!:
    for line in lines(stdin()):
        if is_blank(line):
            continue

        let result = process(line)
        try stdout().write("{result}\n")

    return ok(unit)

export fn main() Int:
    run().get()
    return 0

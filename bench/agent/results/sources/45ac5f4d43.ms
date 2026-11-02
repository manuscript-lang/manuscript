import stdin, stdout, read_line from "@std/io.ms"
import from_scalars from "@std/string.ms"

fn is_blank(line: String) Bool:
    for c in line.scalar_values():
        if c != 32: return false
    return true

fn wrap(n: Int) Int:
    return ((n % 26) + 26) % 26

fn is_upper(c: Int) Bool:
    return c >= 65 and c <= 90

fn is_lower(c: Int) Bool:
    return c >= 97 and c <= 122

fn is_letter(c: Int) Bool:
    return is_upper(c) or is_lower(c)

# Shift a letter by a normalized amount in 0..25; other scalars pass through.
fn shift_letter(c: Int, shift: Int) Int:
    if is_upper(c): return 65 + (c - 65 + shift) % 26
    if is_lower(c): return 97 + (c - 97 + shift) % 26

    return c

# Caesar key: optional '-', then 1 to 7 decimal digits. Returns none if invalid.
fn caesar_key(key: String) Int?:
    let vs = key.scalar_values()
    var i = 0
    var neg = false

    if vs.length() > 0 and vs[0] == 45:
        neg = true
        i = 1

    let digits = vs.length() - i
    if digits < 1 or digits > 7: return none

    var v = 0

    while i < vs.length():
        let c = vs[i]
        if c < 48 or c > 57: return none

        v = v * 10 + (c - 48)
        i += 1

    if neg: return -v

    return v

# Vigenere key letters as shifts 0..25. Returns an empty list if invalid.
fn vigenere_key(key: String) List[Int]:
    var out = List[Int]()

    for c in key.scalar_values():
        if not is_letter(c): return List[Int]()

        if is_upper(c): out.append(c - 65)
        else: out.append(c - 97)

    return out

fn run_line(line: String) String:
    let parts = line.split(" ")
    if parts.length() < 4:
        return "error: bad command"

    let cipher = parts[0]
    let mode = parts[1]
    let key = parts[2]
    let text = parts.slice(3, parts.length()).get().join(" ")
    if text.length() == 0:
        return "error: bad command"
    if cipher != "caesar" and cipher != "vigenere":
        return "error: bad cipher"
    if mode != "enc" and mode != "dec":
        return "error: bad mode"

    let encrypt = mode == "enc"
    var out = List[Int]()

    if cipher == "caesar":
        if let amount = caesar_key(key):
            let shift = wrap(if encrypt: amount else: -amount)
            for c in text.scalar_values():
                out.append(shift_letter(c, shift))
        else:
            return "error: bad key"
    else:
        let ks = vigenere_key(key)
        if ks.length() == 0:
            return "error: bad key"

        var p = 0

        for c in text.scalar_values():
            if is_letter(c):
                let k = ks[p % ks.length()]
                let shift = wrap(if encrypt: k else: -k)
                out.append(shift_letter(c, shift))
                p += 1
            else:
                out.append(c)

    return from_scalars(out).get()

export fn main() Int:
    var more = true

    while more:
        let got = read_line(stdin()).get()

        if let line = got:
            if not is_blank(line):
                let result = run_line(line)
                stdout().write("{result}\n").get()
        else:
            more = false

    return 0

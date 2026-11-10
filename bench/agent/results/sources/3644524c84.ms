import stdin, stdout from "@std/io/io.ms"
import lines from "@std/io/streams.ms"
import from_scalars from "@std/string.ms"

fn is_letter(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_blank(cs: List[Int]) Bool:
    for c in cs:
        if c != 32: return false
    return true

// Copies cs[start..end).
fn sub(cs: List[Int], start: Int, end: Int) List[Int]:
    var out = List[Int]()
    var i = start

    while i < end:
        out.append(cs[i])
        i += 1

    return out

fn same(cs: List[Int], word: String) Bool:
    ws := word.scalar_values()
    if cs.length() != ws.length(): return false

    for i in 0..cs.length():
        if cs[i] != ws[i]: return false
    return true

// Shifts a letter forward by amount (any Int), keeping its case.
fn shift(c: Int, amount: Int) Int:
    var base = 97
    if c <= 90: base = 65

    m := (amount % 26 + 26) % 26
    return base + (c - base + m) % 26

// Caesar key: optional '-', then 1 to 7 ASCII digits.
fn caesar_key(ks: List[Int]) Int?:
    var i = 0
    var neg = false

    if ks.length() > 0 and ks[0] == 45:
        neg = true
        i = 1

    digits := ks.length() - i
    if digits < 1 or digits > 7: return none

    var v = 0

    while i < ks.length():
        c := ks[i]
        if c < 48 or c > 57: return none

        v = v * 10 + (c - 48)
        i += 1

    if neg: return 0 - v

    return v

// Vigenere key letter index 0..25, either case.
fn key_shift(k: Int) Int:
    if k <= 90: return k - 65

    return k - 97

fn process(cs: List[Int]) String:
    var spaces = List[Int]()
    for i in 0..cs.length():
        if cs[i] == 32 and spaces.length() < 3: spaces.append(i)
    if spaces.length() < 3: return "error: bad command"

    s1 := spaces[0]
    s2 := spaces[1]
    s3 := spaces[2]
    if s3 + 1 >= cs.length(): return "error: bad command"

    cipher := sub(cs, 0, s1)
    mode := sub(cs, s1 + 1, s2)
    key := sub(cs, s2 + 1, s3)
    text := sub(cs, s3 + 1, cs.length())
    is_caesar := same(cipher, "caesar")
    is_vigenere := same(cipher, "vigenere")
    if not is_caesar and not is_vigenere: return "error: bad cipher"

    is_enc := same(mode, "enc")
    is_dec := same(mode, "dec")
    if not is_enc and not is_dec: return "error: bad mode"

    sign := if is_enc: 1 else: -1
    var out = List[Int]()

    if is_caesar:
        kopt := caesar_key(key)

        if k := kopt:
            for c in text:
                if is_letter(c):
                    out.append(shift(c, sign * k))
                else:
                    out.append(c)
        else:
            return "error: bad key"
    else:
        var valid = key.length() > 0
        for c in key:
            if not is_letter(c): valid = false
        if not valid: return "error: bad key"

        var ki = 0

        for c in text:
            if is_letter(c):
                amount := sign * key_shift(key[ki])
                out.append(shift(c, amount))
                ki = (ki + 1) % key.length()
            else:
                out.append(c)

    return from_scalars(out).get()

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn run() Unit!:
    for line in lines(stdin()):
        cs := line.scalar_values()
        if is_blank(cs): continue

        stdout().write(process(cs) + "\n").get()

    return ok(unit)

export fn main() Int:
    run().get()
    return 0

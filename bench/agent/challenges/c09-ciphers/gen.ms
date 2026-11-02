# Generator for c09-ciphers. Deterministic; run: ms run bench/agent/gen.ms -- c09
import GenCase, make_case, write_cases from "../../lib/gen.ms"
import seeded from "../../lib/pyrandom.ms"
import from_scalars from "@std/string.ms"
import split_max, strip_spaces from "../../lib/text.ms"

let DIGITS = "0123456789"
let LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

fn shift(text: String, keys: List[Int], fixed: Int, use_keys: Bool, sign: Int) String:
    var out = List[Int]()
    var i = 0

    for ch in text.scalar_values():
        let lower = ch >= 97 and ch <= 122

        if lower or (ch >= 65 and ch <= 90):
            let base = if lower: 97 else: 65
            let k = if use_keys: keys[i % keys.length()] else: fixed
            out.append((((ch - base + sign * k) % 26) + 26) % 26 + base)
            i += 1
        else:
            out.append(ch)

    return from_scalars(out).get("")

# A caesar key: an optional minus sign and one to seven digits.
fn caesar_key(key: String) Bool:
    let digits = if key.starts_with("-"): key.slice(1, key.length()).get("") else: key.clone()
    return (
        digits.length() >= 1
        and digits.length() <= 7
        and digits.chars().all(fn c: DIGITS.contains(c))
    )

fn solve_line(line: String) String:
    let parts = split_max(line, " ", 3)
    if parts.length() < 4 or parts[3].is_empty(): return "error: bad command"

    let cipher = parts[0].clone()
    let mode = parts[1].clone()
    let key = parts[2].clone()
    let text = parts[3].clone()
    if cipher != "caesar" and cipher != "vigenere": return "error: bad cipher"
    if mode != "enc" and mode != "dec": return "error: bad mode"

    let sign = if mode == "enc": 1 else: -1

    if cipher == "caesar":
        if not caesar_key(key): return "error: bad key"

        return shift(text, [], key.parse_int().get(0), false, sign)

    if key.is_empty() or not key.chars().all(fn c: LETTERS.contains(c)): return "error: bad key"

    let ks = key.lower().scalar_values().map(fn c: c - 97)
    return shift(text, ks, 0, true, sign)

fn solve(s: String) String:
    var lines = s.split("\n")
    if not lines.is_empty() and lines[lines.length() - 1] == "": lines.pop()
    return lines.filter(fn l: l.replace(" ", "") != "").map(
        fn l: solve_line(l) + "\n"
    ).join("")

fn mk(name: String, s: String) GenCase: make_case(name, s, solve(s))

export fn gen_c09() Unit:
    var rnd = seeded(9)
    let alpha = (LETTERS + "      .,!?" + DIGITS).chars()
    var big = List[String]()

    for _n in 0..200:
        let c = rnd.choice(["caesar", "vigenere"])
        var k = ""

        if c == "caesar":
            k = "{rnd.randint(-100, 100)}"
        else:
            let n = rnd.randint(1, 8)
            for _m in 0..n: k = k + rnd.choice(["a", "b", "c", "X", "Y", "Z"])

        let mode = rnd.choice(["enc", "dec"])
        let n = rnd.randint(1, 80)
        var text = ""
        for _m in 0..n: text = text + rnd.choice(alpha)

        var trimmed = strip_spaces(text)
        if trimmed.is_empty(): trimmed = "x"
        big.append("{c} {mode} {k} {trimmed}")

    let examples = [
        mk(
            "basic",
            "caesar enc 3 Hello, World!\ncaesar dec 3 Khoor, Zruog!\nvigenere enc Key Attack at dawn\nvigenere dec Key Kxrkgi kx bkal\nrot13 enc 13 x\ncaesar enc 3x abc\ncaesar enc\n"
        ),
        mk("wraparound", "caesar enc 1 xyz XYZ\ncaesar enc -1 abc ABC\n")
    ]
    let hidden = examples.concat(
        [
            mk(
                "big-shifts",
                "caesar enc 26 Same\ncaesar enc 27 Same\ncaesar enc -27 Same\ncaesar dec 1000000 Mixed Case 123\ncaesar enc -0 zero\ncaesar enc 0000012 padded\n"
            ),
            mk(
                "key-advances-on-letters-only",
                "vigenere enc ab a-b c d!e\nvigenere enc bcd aaa aaa aaa\nvigenere dec bcd bbb bbb bbb\n"
            ),
            mk(
                "vigenere-key-case",
                "vigenere enc KEY hello world\nvigenere enc key hello world\nvigenere enc aA zZ\nvigenere enc Z abc\n"
            ),
            mk(
                "non-letters",
                "caesar enc 5 1234 !@#$ ... ---\ncaesar enc 3 café naïve\nvigenere enc abc über\n"
            ),
            mk(
                "spaces-in-text",
                "caesar enc 1 a  b   c\ncaesar enc 1  lead\ncaesar enc 1 trail \nvigenere enc a   x\n"
            ),
            mk(
                "bad-command",
                "caesar\ncaesar enc\ncaesar enc 3\ncaesar enc 3 \nvigenere dec key \nx\n"
            ),
            mk(
                "bad-cipher",
                "Caesar enc 3 abc\nrot13 enc 3 abc\nrot enc 3 abc\n vigenere enc k abc\n"
            ),
            mk(
                "bad-mode",
                "caesar encrypt 3 abc\ncaesar ENC 3 abc\nvigenere de k abc\nvigenere  k abc\n"
            ),
            mk(
                "bad-key",
                "caesar enc +3 abc\ncaesar enc 3.5 abc\ncaesar enc abc abc\ncaesar enc - abc\ncaesar enc 12345678 abc\nvigenere enc k3 abc\nvigenere enc - abc\nvigenere enc k-y abc\ncaesar enc 3 abc\n"
            ),
            mk(
                "check-order",
                "x y z w\ncaesar y z w\ncaesar enc z w\nvigenere enc 5 w\nvigenere enc 5\n"
            ),
            mk(
                "blank-lines", "\n  \ncaesar enc 1 a\n\n   \ncaesar dec 1 b\n"
            ),
            mk("big", big.join("\n") + "\n")
        ]
    )
    write_cases("c09-ciphers", examples, hidden)

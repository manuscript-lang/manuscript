import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

// Token kinds: 0 number, 1 '+', 2 '-', 3 '*', 4 '/', 5 '(', 6 ')', -1 end
type Calc:
    kinds: List[Int]
    vals: List[Int]
    pos: Int
    bad: Bool
    divz: Bool

impl Calc:
    fn kind() Int:
        if self.pos < self.kinds.length():
            return self.kinds[self.pos]

        return -1

    var fn expr() Int:
        var v = self.term()

        while self.kind() == 1 or self.kind() == 2:
            let k = self.kind()
            self.pos += 1

            let r = self.term()

            if k == 1:
                v = v + r
            else:
                v = v - r

        return v

    var fn term() Int:
        var v = self.unary()

        while self.kind() == 3 or self.kind() == 4:
            let k = self.kind()
            self.pos += 1

            let r = self.unary()

            if k == 3:
                v = v * r
            else if r == 0:
                self.divz = true
                v = 0
            else:
                v = v / r

        return v

    var fn unary() Int:
        if self.kind() == 2:
            self.pos += 1
            return 0 - self.unary()

        return self.primary()

    var fn primary() Int:
        let k = self.kind()

        if k == 0:
            let n = self.vals[self.pos]
            self.pos += 1
            return n

        if k == 5:
            self.pos += 1

            let v = self.expr()

            if self.kind() == 6:
                self.pos += 1
            else:
                self.bad = true

            return v

        self.bad = true
        return 0

// Returns the tokens of `line`, or none if it contains an unknown character.
fn tokenize(line: String) Calc?:
    var kinds = List[Int]()
    var vals = List[Int]()
    var cur = 0
    var in_num = false
    var bad = false

    for ch in line.chars():
        let d = ch.parse_int().get(-1)

        if d >= 0:
            cur = cur * 10 + d
            in_num = true
        else:
            if in_num:
                kinds.append(0)
                vals.append(cur)
                cur = 0
                in_num = false

            if ch == " " or ch == "\t":
                continue
            else if ch == "+":
                kinds.append(1)
                vals.append(0)
            else if ch == "-":
                kinds.append(2)
                vals.append(0)
            else if ch == "*":
                kinds.append(3)
                vals.append(0)
            else if ch == "/":
                kinds.append(4)
                vals.append(0)
            else if ch == "(":
                kinds.append(5)
                vals.append(0)
            else if ch == ")":
                kinds.append(6)
                vals.append(0)
            else:
                bad = true

    if in_num:
        kinds.append(0)
        vals.append(cur)

    if bad:
        return none

    return Calc(kinds: kinds, vals: vals, pos: 0, bad: false, divz: false)

export fn main() Int:
    var rows = lines(stdin())

    while true:
        let item = rows.next().get()

        if let line = item:
            if line.trim_chars(" \t") == "":
                continue

            if let c = tokenize(line):
                var calc = c
                let v = calc.expr()

                if calc.bad or calc.pos < calc.kinds.length():
                    print("error: syntax")
                else if calc.divz:
                    print("error: division by zero")
                else:
                    print("{v}")
            else:
                print("error: syntax")
        else:
            break

    return 0

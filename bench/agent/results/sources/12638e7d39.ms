import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Parser:
    src: List[Int]
    pos: Int
    syntax: Bool
    divz: Bool

impl Parser:
    fn at() Int:
        if self.pos < self.src.length(): return self.src[self.pos]

        return -1

    var fn skip_ws() Unit:
        while self.at() == 32 or self.at() == 9:
            self.pos += 1

    var fn fail() Unit:
        self.syntax = true
        self.pos = self.src.length()

    fn blank() Bool:
        for c in self.src:
            if c != 32 and c != 9: return false
        return true

    var fn expr() Int:
        var v = self.term()

        while true:
            self.skip_ws()

            if self.at() == 43:
                self.pos += 1
                v = v + self.term()
            else if self.at() == 45:
                self.pos += 1
                v = v - self.term()
            else:
                break

        return v

    var fn term() Int:
        var v = self.unary()

        while true:
            self.skip_ws()

            if self.at() == 42:
                self.pos += 1
                v = v * self.unary()
            else if self.at() == 47:
                self.pos += 1

                let d = self.unary()

                if d == 0:
                    self.divz = true
                    v = 0
                else:
                    var a = v
                    var b = d
                    if a < 0: a = -a
                    if b < 0: b = -b

                    var q = a / b
                    if (v < 0) != (d < 0): q = -q
                    v = q
            else:
                break

        return v

    var fn unary() Int:
        self.skip_ws()

        if self.at() == 45:
            self.pos += 1
            return -self.unary()

        return self.primary()

    var fn primary() Int:
        self.skip_ws()

        let c = self.at()

        if c >= 48 and c <= 57:
            var v = 0

            while self.at() >= 48 and self.at() <= 57:
                v = v * 10 + (self.at() - 48)
                self.pos += 1

            return v

        if c == 40:
            self.pos += 1

            let v = self.expr()
            self.skip_ws()

            if self.at() != 41:
                self.fail()
                return 0

            self.pos += 1
            return v

        self.fail()
        return 0

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var out = ""

    for line in lines:
        var src = List[Int]()
        for ch in line.chars():
            src.append(ch.scalar_at(0, default: -1))

        var p = Parser(src: src, pos: 0, syntax: false, divz: false)
        if p.blank():
            continue

        let v = p.expr()
        p.skip_ws()
        if p.pos != p.src.length():
            p.fail()

        if p.syntax:
            out += "error: syntax\n"
        else if p.divz:
            out += "error: division by zero\n"
        else:
            out += "{v}\n"

    stdout().write(out).get()
    return 0

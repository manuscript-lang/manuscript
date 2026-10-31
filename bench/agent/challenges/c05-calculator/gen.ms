# Generator for c05-calculator. Deterministic; run: ms run bench/agent/gen.ms -- c05
import GenCase, make_case, write_cases from "../../lib/gen.ms"
import seeded from "../../lib/pyrandom.ms"
import Random from "../../lib/pyrandom.ms"

# A token: `n` with a value, or `o` with the operator character.
type Tok:
    kind: String
    text: String
    value: Int

fn tokens(line: String) List[Tok]:
    var out = List[Tok]()
    let chars = line.chars()
    var i = 0
    while i < chars.length():
        let c = chars[i].clone()
        if c.trim().is_empty():
            i += 1
        else if "0123456789".contains(c):
            var digits = ""
            while i < chars.length() and "0123456789".contains(chars[i]):
                digits = digits + chars[i]
                i += 1
            out.append(Tok("n", digits.clone(), digits.parse_int().get(0)))
        else:
            out.append(Tok("o", c.clone(), 0))
            i += 1
    return out

# A recursive-descent evaluator. `bad` records a syntax error (which wins over a division by zero); once set
# the parser sees no more tokens, so every loop ends.
type Parser:
    toks: List[Tok]
    pos: Int = 0
    div: Bool = false
    bad: Bool = false

impl Parser:
    fn at_op(text: String) Bool:
        if self.bad or self.pos >= self.toks.length(): return false

        return self.toks[self.pos].kind == "o" and self.toks[self.pos].text == text

    var fn expr() Int:
        var v = self.term()
        while self.at_op("+") or self.at_op("-"):
            let plus = self.at_op("+")
            self.pos += 1
            let r = self.term()
            v = if plus: v + r else: v - r
        return v

    var fn term() Int:
        var v = self.unary()
        while self.at_op("*") or self.at_op("/"):
            let times = self.at_op("*")
            self.pos += 1
            let r = self.unary()
            if times:
                v = v * r
            else if r == 0:
                self.div = true
                v = 0
            else:
                v = v / r
        return v

    var fn unary() Int:
        if self.at_op("-"):
            self.pos += 1
            return 0 - self.unary()
        return self.atom()

    var fn atom() Int:
        if self.bad or self.pos >= self.toks.length():
            self.bad = true
            return 0

        let t = self.toks[self.pos].clone()
        self.pos += 1
        if t.kind == "n": return t.value

        if t.text == "(":
            let v = self.expr()
            if not self.at_op(")"):
                self.bad = true
                return 0

            self.pos += 1
            return v
        self.bad = true
        return 0

fn evaluate(line: String) String:
    var p = Parser(tokens(line))
    let v = p.expr()
    if p.pos < p.toks.length(): p.bad = true
    if p.bad: return "error: syntax"
    if p.div: return "error: division by zero"

    return "{v}"

fn solve(s: String) String:
    return s.split("\n").filter(fn l: not l.trim().is_empty()).map(fn l: evaluate(l) + "\n").join("")

fn mk(name: String, s: String) GenCase: make_case(name, s, solve(s))

fn rexpr(var rnd: Random, d: Int) String:
    if d == 0 or rnd.random() < 0.25: return "{rnd.randint(0, 99)}"

    let r = rnd.random()
    if r < 0.15: return "-" + rexpr(var rnd, d - 1)
    if r < 0.3: return "(" + rexpr(var rnd, d - 1) + ")"
    let left = rexpr(var rnd, d - 1)
    let op = rnd.choice([" + ", "-", " * ", "/", " - "])
    return left + op + rexpr(var rnd, d - 1)

export fn gen_c05() Unit:
    var rnd = seeded(5)
    let examples = [mk("basic", "1 + 2 * 3\n(1+2)*3\n10 / (5 - 5)\n2 +\n-7 / 2\n")]
    var good = List[String]()
    for _n in 0..400: good.append(rexpr(var rnd, 5))
    let syntax = ["()", "1+", "+1", "(1", "1)", "1 2", "a", "1+*2", "2**3", "(", ")", "1 + (2", "3 $ 4", "1/0 +"]
    let hidden = examples.concat([
        mk("precedence", "2+3*4\n2*3+4\n10-2-3\n100/10/5\n2*(3+4)*5\n"), mk("unary", "-2*3\n--4\n-(3+4)\n3--2\n- 5\n"),
        mk("truncation", "-7/2\n7/-2\n-7/-2\n7/2\n0/5\n-1/2\n"), mk("spaces", "  1\t+  2  \n\t(  3 )\n"),
        mk("blank", "\n   \n1\n\n"), mk("div-zero", "1/0\n0/0\n(1+2)/(3-3)\n1/0+2\n5*(2/0)\n"),
        mk("syntax", syntax.join("\n") + "\n"),
        mk("syntax-beats-div", "1/0 +\n(1/0\n1/0 2\n"), mk("random-valid", good.join("\n") + "\n"),
        mk("deep-parens", "(".repeat(200).get("") + "7" + ")".repeat(200).get("") + "\n"),
        mk("big-numbers", "9999999999 * 99999999\n9223372036854775807\n-9223372036854775807 - 1\n"),
        mk("no-trailing-newline", "1+1")
    ])
    write_cases("c05-calculator", examples, hidden)

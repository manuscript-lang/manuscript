use std::fmt::Write;

enum Tok { Num(i64), Sym(u8) }
enum Expr { Lit(i64), Bin(u8, Box<Expr>, Box<Expr>) }

struct Parser { toks: Vec<Tok>, pos: usize }

fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }

fn gen(depth: i64, x: &mut i64, out: &mut String) {
    *x = lcg(*x);
    if depth == 0 || *x % 5 == 0 {
        write!(out, "{}", *x / 7 % 100).unwrap();
        return;
    }
    *x = lcg(*x);
    let op = ["+", "-", "*", "%"][(*x / 3 % 4) as usize];
    out.push('(');
    gen(depth - 1, x, out);
    out.push(' ');
    out.push_str(op);
    out.push(' ');
    gen(depth - 1, x, out);
    out.push(')');
}

fn tokenize(text: &str) -> Vec<Tok> {
    let b = text.as_bytes();
    let mut toks = Vec::new();
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if c.is_ascii_digit() {
            let mut v = 0i64;
            while i < b.len() && b[i].is_ascii_digit() {
                v = v * 10 + (b[i] - b'0') as i64;
                i += 1;
            }
            toks.push(Tok::Num(v));
        } else if c == b' ' {
            i += 1;
        } else {
            toks.push(Tok::Sym(c));
            i += 1;
        }
    }
    toks
}

impl Parser {
    fn expr(&mut self) -> Expr {
        match self.toks[self.pos] {
            Tok::Num(v) => { self.pos += 1; Expr::Lit(v) }
            Tok::Sym(_) => {
                self.pos += 1;
                let left = self.expr();
                let op = match self.toks[self.pos] { Tok::Sym(o) => o, Tok::Num(_) => 0 };
                self.pos += 1;
                let right = self.expr();
                self.pos += 1;
                Expr::Bin(op, Box::new(left), Box::new(right))
            }
        }
    }
}

fn eval(e: &Expr) -> i64 {
    match e {
        Expr::Lit(v) => *v,
        Expr::Bin(op, l, r) => {
            let a = eval(l);
            let b = eval(r);
            match op {
                b'+' => (a + b) % 1000003,
                b'-' => (a - b) % 1000003,
                b'*' => a * b % 1000003,
                _ => if b == 0 { a } else { a % b },
            }
        }
    }
}

fn main() {
    let mut x = 3;
    let (mut total, mut tokens, mut chars) = (0i64, 0usize, 0usize);
    for _ in 0..60000 {
        let mut text = String::new();
        gen(9, &mut x, &mut text);
        chars += text.len();
        let toks = tokenize(&text);
        tokens += toks.len();
        let mut p = Parser { toks, pos: 0 };
        total = (total + eval(&p.expr())) % 1000003;
    }
    println!("chars {chars} tokens {tokens} total {total}");
}

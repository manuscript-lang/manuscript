use std::io::{self, Read, Write};

#[derive(Debug, Clone, Copy, PartialEq)]
enum Tok {
    Num(i64),
    Plus,
    Minus,
    Star,
    Slash,
    LParen,
    RParen,
}

enum Node {
    Num(i64),
    Neg(Box<Node>),
    Bin(Tok, Box<Node>, Box<Node>),
}

fn tokenize(line: &[u8]) -> Result<Vec<Tok>, ()> {
    let mut toks = Vec::new();
    let mut i = 0;
    while i < line.len() {
        let c = line[i];
        match c {
            b' ' | b'\t' | b'\r' => i += 1,
            b'0'..=b'9' => {
                let mut v: i64 = 0;
                while i < line.len() && line[i].is_ascii_digit() {
                    v = v.wrapping_mul(10).wrapping_add((line[i] - b'0') as i64);
                    i += 1;
                }
                toks.push(Tok::Num(v));
            }
            b'+' => {
                toks.push(Tok::Plus);
                i += 1;
            }
            b'-' => {
                toks.push(Tok::Minus);
                i += 1;
            }
            b'*' => {
                toks.push(Tok::Star);
                i += 1;
            }
            b'/' => {
                toks.push(Tok::Slash);
                i += 1;
            }
            b'(' => {
                toks.push(Tok::LParen);
                i += 1;
            }
            b')' => {
                toks.push(Tok::RParen);
                i += 1;
            }
            _ => return Err(()),
        }
    }
    Ok(toks)
}

struct Parser {
    toks: Vec<Tok>,
    pos: usize,
}

impl Parser {
    fn peek(&self) -> Option<Tok> {
        self.toks.get(self.pos).copied()
    }

    // expr := term (('+' | '-') term)*
    fn expr(&mut self) -> Result<Node, ()> {
        let mut lhs = self.term()?;
        while let Some(op @ (Tok::Plus | Tok::Minus)) = self.peek() {
            self.pos += 1;
            let rhs = self.term()?;
            lhs = Node::Bin(op, Box::new(lhs), Box::new(rhs));
        }
        Ok(lhs)
    }

    // term := unary (('*' | '/') unary)*
    fn term(&mut self) -> Result<Node, ()> {
        let mut lhs = self.unary()?;
        while let Some(op @ (Tok::Star | Tok::Slash)) = self.peek() {
            self.pos += 1;
            let rhs = self.unary()?;
            lhs = Node::Bin(op, Box::new(lhs), Box::new(rhs));
        }
        Ok(lhs)
    }

    // unary := '-' unary | primary
    fn unary(&mut self) -> Result<Node, ()> {
        if self.peek() == Some(Tok::Minus) {
            self.pos += 1;
            let inner = self.unary()?;
            return Ok(Node::Neg(Box::new(inner)));
        }
        self.primary()
    }

    // primary := NUM | '(' expr ')'
    fn primary(&mut self) -> Result<Node, ()> {
        match self.peek() {
            Some(Tok::Num(v)) => {
                self.pos += 1;
                Ok(Node::Num(v))
            }
            Some(Tok::LParen) => {
                self.pos += 1;
                let inner = self.expr()?;
                if self.peek() != Some(Tok::RParen) {
                    return Err(());
                }
                self.pos += 1;
                Ok(inner)
            }
            _ => Err(()),
        }
    }
}

/// Evaluates the tree. Every division is evaluated (no short-circuit); a division
/// by zero sets `div0` and yields 0 so evaluation can continue.
fn eval(node: &Node, div0: &mut bool) -> i64 {
    match node {
        Node::Num(v) => *v,
        Node::Neg(inner) => eval(inner, div0).wrapping_neg(),
        Node::Bin(op, a, b) => {
            let x = eval(a, div0);
            let y = eval(b, div0);
            match op {
                Tok::Plus => x.wrapping_add(y),
                Tok::Minus => x.wrapping_sub(y),
                Tok::Star => x.wrapping_mul(y),
                Tok::Slash => {
                    if y == 0 {
                        *div0 = true;
                        0
                    } else {
                        x.wrapping_div(y)
                    }
                }
                _ => unreachable!(),
            }
        }
    }
}

fn process_line(line: &[u8]) -> Option<String> {
    if line.iter().all(|&c| matches!(c, b' ' | b'\t' | b'\r')) {
        return None;
    }
    let toks = match tokenize(line) {
        Ok(t) => t,
        Err(()) => return Some("error: syntax".to_string()),
    };
    let mut p = Parser { toks, pos: 0 };
    let tree = match p.expr() {
        Ok(t) if p.pos == p.toks.len() => t,
        _ => return Some("error: syntax".to_string()),
    };
    let mut div0 = false;
    let v = eval(&tree, &mut div0);
    if div0 {
        Some("error: division by zero".to_string())
    } else {
        Some(v.to_string())
    }
}

fn main() {
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).expect("read stdin");
    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());
    for line in input.split(|&c| c == b'\n') {
        if let Some(s) = process_line(line) {
            writeln!(out, "{}", s).expect("write stdout");
        }
    }
    out.flush().expect("flush stdout");
}

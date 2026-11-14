enum Op {
    Push(i64),
    Load(usize),
    Store(usize),
    Add,
    Mul,
    Mod,
    Lt,
    Jz(usize),
    Jmp(usize),
    Halt,
}

fn program(n: i64, m: i64) -> Vec<Op> {
    use Op::*;
    vec![
        Push(0), Store(0),
        Push(0), Store(1),
        Load(1), Push(n), Lt, Jz(33),
        Push(0), Store(2),
        Load(2), Push(m), Lt, Jz(28),
        Load(0), Load(1), Load(2), Mul, Push(7), Mod, Add, Store(0),
        Load(2), Push(1), Add, Store(2),
        Jmp(10), Halt,
        Load(1), Push(1), Add, Store(1), Jmp(4),
        Halt,
    ]
}

fn run(code: &[Op]) -> i64 {
    let mut stack: Vec<i64> = Vec::new();
    let mut vars = [0i64; 4];
    let mut pc = 0usize;
    let mut steps = 0i64;
    loop {
        steps += 1;
        match &code[pc] {
            Op::Push(v) => { stack.push(*v); pc += 1; }
            Op::Load(s) => { stack.push(vars[*s]); pc += 1; }
            Op::Store(s) => { vars[*s] = stack.pop().unwrap_or(0); pc += 1; }
            Op::Add => { let b = stack.pop().unwrap_or(0); let a = stack.pop().unwrap_or(0); stack.push(a + b); pc += 1; }
            Op::Mul => { let b = stack.pop().unwrap_or(0); let a = stack.pop().unwrap_or(0); stack.push(a * b); pc += 1; }
            Op::Mod => { let b = stack.pop().unwrap_or(0); let a = stack.pop().unwrap_or(0); stack.push(a % b); pc += 1; }
            Op::Lt => { let b = stack.pop().unwrap_or(0); let a = stack.pop().unwrap_or(0); stack.push((a < b) as i64); pc += 1; }
            Op::Jz(t) => { let c = stack.pop().unwrap_or(0); pc = if c == 0 { *t } else { pc + 1 }; }
            Op::Jmp(t) => pc = *t,
            Op::Halt => break,
        }
    }
    println!("steps {steps}");
    vars[0]
}

fn main() {
    println!("total {}", run(&program(3000, 2000)));
}

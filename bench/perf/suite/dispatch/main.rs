trait Shape {
    fn area(&self) -> i64;
    fn grow(&self, by: i64) -> i64;
}
struct Sq(i64);
struct Rect(i64, i64);
struct Tri(i64, i64);
impl Shape for Sq {
    fn area(&self) -> i64 { self.0 * self.0 }
    fn grow(&self, by: i64) -> i64 { (self.0 + by) * (self.0 + by) }
}
impl Shape for Rect {
    fn area(&self) -> i64 { self.0 * self.1 }
    fn grow(&self, by: i64) -> i64 { (self.0 + by) * (self.1 + by) }
}
impl Shape for Tri {
    fn area(&self) -> i64 { self.0 * self.1 / 2 }
    fn grow(&self, by: i64) -> i64 { (self.0 + by) * (self.1 + by) / 2 }
}

fn shapes(n: i64) -> i64 {
    let mut xs: Vec<Box<dyn Shape>> = Vec::new();
    for i in 0..n {
        match i % 3 {
            0 => xs.push(Box::new(Sq(i % 10 + 1))),
            1 => xs.push(Box::new(Rect(i % 7 + 1, i % 5 + 1))),
            _ => xs.push(Box::new(Tri(i % 9 + 1, i % 4 + 1))),
        }
    }
    let mut total = 0;
    for pass in 0..20 {
        for s in &xs { total += s.area() + s.grow(pass); }
    }
    total
}

fn closures(n: i64) -> i64 {
    let offset = 3;
    let steps: Vec<Box<dyn Fn(i64) -> i64>> = vec![
        Box::new(move |x| x + offset),
        Box::new(|x| x * 2),
        Box::new(|x| x - 1),
        Box::new(|x| x % 1000003),
    ];
    let mut acc = 1;
    for i in 0..n {
        for f in &steps { acc = f(acc + i); }
    }
    acc
}

struct Stack<T> { items: Vec<T> }
impl<T> Stack<T> {
    fn push(&mut self, v: T) { self.items.push(v); }
    fn pop(&mut self) -> Option<T> { self.items.pop() }
}

fn fold_with<T>(xs: &[T], init: i64, step: impl Fn(i64, &T) -> i64) -> i64 {
    let mut acc = init;
    for x in xs { acc = step(acc, x); }
    acc
}

fn generics(n: i64) -> i64 {
    let mut s = Stack { items: Vec::new() };
    let mut t = 0;
    for i in 0..n {
        s.push(i % 1000);
        if i % 3 == 2 {
            if let Some(v) = s.pop() { t += v; }
        }
    }
    t + fold_with(&s.items, 0, |a, x| a + x * 2)
}

fn main() {
    println!("shapes {}", shapes(1000000));
    println!("closures {}", closures(15000000));
    println!("generics {}", generics(20000000));
}

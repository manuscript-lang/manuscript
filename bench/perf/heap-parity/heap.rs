use std::cmp::Reverse;
use std::collections::BinaryHeap;
use std::hint::black_box;

fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut values = Vec::with_capacity(n);
    let mut r: i64 = 1;
    for _ in 0..n {
        r = (r * 1103515245 + 12345) % 2147483648;
        values.push(r % 100003);
    }
    let mut heap: BinaryHeap<Reverse<(i64, u64)>> = BinaryHeap::new();
    for (i, v) in values.iter().enumerate() {
        heap.push(Reverse((*v, i as u64)));
    }
    let mut sum: i64 = 0;
    for i in 0..n as i64 {
        let Reverse((p, _)) = heap.pop().unwrap();
        sum += (p + 1) * (i + 1);
    }
    println!("{}", black_box(sum));
}

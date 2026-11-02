use std::cmp::Reverse;
use std::collections::{BinaryHeap, VecDeque};
use std::hint::black_box;
use std::time::Instant;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let operation = &args[0];
    let size: usize = args[1].parse().unwrap();
    let shape = &args[2];
    let repeats: usize = args[3].parse().unwrap();
    let mut random = 1i64;
    let values: Vec<i64> = (0..size as i64)
        .map(|i| {
            random = (random * 1103515245 + 12345) % 2147483648;
            match shape.as_str() {
                "ascending" => i,
                "descending" => size as i64 - i,
                "duplicate" => i % 7,
                _ => random % 100003,
            }
        })
        .collect();
    let mut checksum = 0i64;
    let mut priority = BinaryHeap::new();
    let mut next_order = 0i64;
    let mut queue = VecDeque::new();
    let mut deque = VecDeque::new();
    let started = Instant::now();
    for _ in 0..repeats {
        match operation.as_str() {
            "priority" => {
                for &value in black_box(&values) {
                    priority.push(Reverse((value, next_order)));
                    next_order += 1;
                }
                for i in 0..size {
                    checksum += (priority.pop().unwrap().0.0 + 1) * (i as i64 + 1);
                }
            }
            "queue" => {
                for &value in black_box(&values) {
                    queue.push_back(value);
                }
                for i in 0..size {
                    checksum += (queue.pop_front().unwrap() + 1) * (i as i64 + 1);
                }
            }
            _ => {
                for (i, &value) in black_box(&values).iter().enumerate() {
                    if i % 2 == 0 {
                        deque.push_front(value);
                    } else {
                        deque.push_back(value);
                    }
                }
                for i in 0..size {
                    checksum += (deque.pop_front().unwrap() + 1) * (i as i64 + 1);
                }
            }
        }
        black_box(checksum);
    }
    println!("{} {}", started.elapsed().as_nanos(), checksum);
}

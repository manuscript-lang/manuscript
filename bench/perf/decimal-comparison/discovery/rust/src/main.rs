use num_bigint::BigInt;
use num_traits::ToPrimitive;
use std::{hint::black_box, time::Instant};

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let operation = &args[1];
    let n: i64 = args[2].parse().unwrap();
    let count: i64 = args[3].parse().unwrap();
    let borrowed = args.get(4).is_some_and(|s| s == "borrowed");
    let mut checksum = 0_i64;
    if operation == "factorial" {
        let modulus = BigInt::from(1_000_003);
        let mut last = BigInt::from(1);
        let start = Instant::now();
        for repeat in 0..count {
            let mut value = BigInt::from(1);
            for i in 1..=black_box(n) {
                if borrowed {
                    value = &value * BigInt::from(i);
                } else {
                    value *= i;
                }
            }
            checksum += (&value % &modulus).to_i64().unwrap() * (repeat % 7 + 1);
            last = value;
        }
        let ns = start.elapsed().as_nanos();
        println!("case={operation} n={n} count={count} ns={ns} checksum={checksum} result={last}");
    } else if operation == "lcg" {
        let mut last = 1_i64;
        let start = Instant::now();
        for repeat in 0..count {
            let mut value = 1_i64;
            for _ in 0..black_box(n) {
                value = value * 48_271 % 2_147_483_647;
            }
            checksum += value % 1_000_003 * (repeat % 7 + 1);
            last = value;
        }
        let ns = start.elapsed().as_nanos();
        println!("case={operation} n={n} count={count} ns={ns} checksum={checksum} result={last}");
    } else {
        panic!("unknown operation");
    }
}

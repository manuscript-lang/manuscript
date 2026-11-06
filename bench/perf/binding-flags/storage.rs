#[cfg(feature = "count")]
use std::alloc::{GlobalAlloc, Layout, System};
use std::{
    collections::HashMap,
    hint::black_box,
    sync::atomic::{AtomicUsize, Ordering::Relaxed},
    time::Instant,
};
#[cfg(feature = "count")]
struct Count;
static LIVE: AtomicUsize = AtomicUsize::new(0);
static BYTES: AtomicUsize = AtomicUsize::new(0);
// SAFETY: Every operation forwards the original pointer/layout to System. Atomics only
// record successful requested allocation sizes and do not access allocation contents.
#[cfg(feature = "count")]
unsafe impl GlobalAlloc for Count {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        // SAFETY: The caller supplies a valid allocation layout.
        let p = unsafe { System.alloc(l) };
        if !p.is_null() {
            LIVE.fetch_add(l.size(), Relaxed);
            BYTES.fetch_add(l.size(), Relaxed);
        }
        p
    }
    unsafe fn dealloc(&self, p: *mut u8, l: Layout) {
        LIVE.fetch_sub(l.size(), Relaxed);
        // SAFETY: The caller supplies the live System allocation and its original layout.
        unsafe { System.dealloc(p, l) }
    }
    unsafe fn alloc_zeroed(&self, l: Layout) -> *mut u8 {
        // SAFETY: The caller supplies a valid allocation layout.
        let p = unsafe { System.alloc_zeroed(l) };
        if !p.is_null() {
            LIVE.fetch_add(l.size(), Relaxed);
            BYTES.fetch_add(l.size(), Relaxed);
        }
        p
    }
    unsafe fn realloc(&self, p: *mut u8, l: Layout, n: usize) -> *mut u8 {
        // SAFETY: The caller supplies a live System allocation, its layout, and valid size.
        let q = unsafe { System.realloc(p, l, n) };
        if !q.is_null() {
            LIVE.fetch_add(n, Relaxed);
            LIVE.fetch_sub(l.size(), Relaxed);
            BYTES.fetch_add(n, Relaxed);
        }
        q
    }
}
#[cfg(feature = "count")]
#[global_allocator]
static ALLOC: Count = Count;
trait Flags: Default {
    fn set(&mut self, k: usize, b: u8);
    fn get(&self, k: usize) -> u8;
}
#[derive(Default)]
struct Dense(Vec<u8>);
impl Flags for Dense {
    fn set(&mut self, k: usize, b: u8) {
        if self.0.len() <= k {
            self.0.resize(k + 1, 0)
        }
        self.0[k] |= b;
    }
    fn get(&self, k: usize) -> u8 {
        self.0.get(k).copied().unwrap_or(0)
    }
}
#[derive(Default)]
struct Sparse(HashMap<usize, u8>);
impl Flags for Sparse {
    fn set(&mut self, k: usize, b: u8) {
        *self.0.entry(k).or_default() |= b
    }
    fn get(&self, k: usize) -> u8 {
        self.0.get(&k).copied().unwrap_or(0)
    }
}
#[derive(Default)]
struct Pages<const N: usize>(HashMap<usize, Box<[u8; N]>>);
impl<const N: usize> Flags for Pages<N> {
    fn set(&mut self, k: usize, b: u8) {
        self.0.entry(k / N).or_insert_with(|| Box::new([0; N]))[k % N] |= b;
    }
    fn get(&self, k: usize) -> u8 {
        self.0.get(&(k / N)).map_or(0, |p| p[k % N])
    }
}
fn run<T: Flags>(kind: &str, keys: &[usize], queries: &[usize], expected: usize) {
    let live = LIVE.load(Relaxed);
    let bytes = BYTES.load(Relaxed);
    let t = Instant::now();
    let mut flags = T::default();
    for (i, &k) in keys.iter().enumerate() {
        let b = (i % 63 + 1) as u8;
        flags.set(k, b & 21);
        flags.set(k, b & 42);
    }
    let build = t.elapsed().as_nanos();
    let storage = LIVE.load(Relaxed) - live;
    let allocated = BYTES.load(Relaxed) - bytes;
    let t = Instant::now();
    let mut sum = 0usize;
    for &k in queries {
        let byte = black_box(flags.get(black_box(k)));
        let has = usize::from(byte & 4 != 0);
        let borrow = if byte & 2 != 0 {
            2
        } else if byte & 1 != 0 {
            1
        } else {
            0
        };
        sum += black_box(has + borrow);
    }
    let lookup = t.elapsed().as_nanos();
    assert_eq!(sum, expected);
    println!("{kind},{build},{lookup},{storage},{allocated},{sum}");
}
fn main() {
    let a: Vec<_> = std::env::args().collect();
    let shape = &a[1];
    let trial = &a[2];
    let (n, offset, stride) = match shape.as_str() {
        "empty" => (0, 0, 1),
        "one" => (1, 0, 1),
        "four" => (4, 0, 1),
        "unaligned" => (128, 63, 1),
        "tiny" => (128, 0, 1),
        "cold-dense" => (8192, 0, 1),
        "hot-tiny" => (128, 16_000_000, 1),
        "hot-dense" => (8192, 16_000_000, 1),
        "sparse" => (128, 0, 32768),
        "holes" => (128, 16_000_000, 2),
        _ => panic!(),
    };
    let mut keys: Vec<_> = (0..n).map(|i| offset + i * stride).collect();
    let mut rng = 123456789u64;
    for i in (1..keys.len()).rev() {
        rng ^= rng << 13;
        rng ^= rng >> 7;
        rng ^= rng << 17;
        keys.swap(i, rng as usize % (i + 1));
    }
    let queries: Vec<_> = (0..2_000_000)
        .map(|i| {
            if n == 0 {
                i % 113
            } else {
                match i % 5 {
                    0 => offset + n * stride + i % 113,
                    1 if stride > 1 => keys[(i * 113) % n] + 1,
                    1 => offset + n * stride + i % 113,
                    _ => keys[(i * 113) % n],
                }
            }
        })
        .collect();
    let oracle: HashMap<_, _> = keys
        .iter()
        .enumerate()
        .map(|(i, &k)| (k, (i % 63 + 1) as u8))
        .collect();
    let expected: usize = queries
        .iter()
        .map(|k| {
            let b = oracle.get(k).copied().unwrap_or(0);
            usize::from(b & 4 != 0)
                + if b & 2 != 0 {
                    2
                } else if b & 1 != 0 {
                    1
                } else {
                    0
                }
        })
        .sum();
    println!("{shape},{trial}");
    match a[3].as_str() {
        "dense" => run::<Dense>("dense", &keys, &queries, expected),
        "sparse" => run::<Sparse>("sparse", &keys, &queries, expected),
        "pages64" => run::<Pages<64>>("pages64", &keys, &queries, expected),
        "pages256" => run::<Pages<256>>("pages256", &keys, &queries, expected),
        _ => panic!(),
    }
}

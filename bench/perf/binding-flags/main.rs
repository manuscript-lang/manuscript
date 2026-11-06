#[cfg(feature = "count")]
use std::alloc::{GlobalAlloc, Layout, System};
use std::{
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering::Relaxed},
    },
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
fn main() {
    std::thread::Builder::new()
        .stack_size(64 << 20)
        .spawn(run)
        .unwrap()
        .join()
        .unwrap();
}
fn run() {
    let a: Vec<_> = std::env::args().collect();
    let source = std::fs::read_to_string(&a[1]).unwrap();
    let repeats: usize = a[2].parse().unwrap();
    let fresh = a.get(3).is_some_and(|s| s == "fresh");
    let session = ms_check::Session::new();
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("probe.ms");
    println!("iteration,check_ns,allocated_bytes,program_live_bytes,name_bytes,diagnostics");
    for i in 0..repeats {
        let new;
        let selected = if fresh {
            new = ms_check::Session::new();
            &new
        } else {
            &session
        };
        let ast = ms_syntax::parser::parse(&file, &source).expect("parse");
        let module = ms_check::load_module(syms, &ast);
        let live = LIVE.load(Relaxed);
        let bytes = BYTES.load(Relaxed);
        let start = Instant::now();
        let p = ms_check::check_in(
            syms,
            selected,
            vec![module],
            ms_check::ImportMap::default(),
            ms_check::CheckOptions::default(),
        );
        let ns = start.elapsed().as_nanos();
        let alloc = BYTES.load(Relaxed) - bytes;
        let delta = LIVE.load(Relaxed) as i128 - live as i128;
        let ds: Vec<_> = p.diagnostics.iter().map(|d| d.to_json()).collect();
        println!(
            "{i},{ns},{alloc},{delta},{},{}",
            syms.text_bytes(),
            ds.len()
        );
        if i == 0 {
            eprintln!("[{}]", ds.join(","));
        }
    }
}

//! Randomized differential tests: runtime collections and strings against std models.
//!
//! Each test drives a seeded sequence of operations through the exported C ABI and a plain
//! `Vec`/`String` model, compares after every step, and checks that nothing leaks.
use crate::alloc::live_blocks;
use crate::desc::{msrt_desc_int, msrt_desc_string};
use crate::map::*;
use crate::string::{self, from_bytes};
use crate::testutil;
use crate::vec::*;
use ms_rt_abi::*;

/// xorshift64*: deterministic and dependency free.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_f491_4f6c_dd1d)
    }

    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
}

const STEPS: usize = if cfg!(miri) { 150 } else { 6000 };

/// Few distinct short keys, so inserts collide, removals hit and holes accumulate.
fn key(r: &mut Rng, space: usize) -> std::string::String {
    let n = r.below(space);
    if n.is_multiple_of(5) {
        std::format!("é{n}")
    } else {
        std::format!("k{n}")
    }
}

fn text(s: *const StrObj) -> std::string::String {
    // SAFETY: tests pass live strings.
    std::string::String::from_utf8_lossy(unsafe { string::bytes(s) }).into_owned()
}

fn new_str(s: &str) -> *mut StrObj {
    from_bytes(s.as_bytes())
}

unsafe fn strings(v: &VecVal) -> std::vec::Vec<std::string::String> {
    // SAFETY: tests build string lists.
    unsafe {
        (0..v.len)
            .map(|i| text(*(v.ptr as *const *const StrObj).add(i)))
            .collect()
    }
}

unsafe fn ints(v: &VecVal) -> std::vec::Vec<i64> {
    // SAFETY: tests build int lists.
    unsafe { (0..v.len).map(|i| *(v.ptr as *const i64).add(i)).collect() }
}

unsafe fn map_keys_of(m: &MapVal, kd: &TypeDesc, vd: Option<&TypeDesc>) -> VecVal {
    let mut out = VecVal {
        ptr: core::ptr::null_mut(),
        len: 0,
        cap: 0,
    };
    // SAFETY: caller passes a live map of `kd` keys.
    unsafe { msrt_map_keys(m, kd, vd.map_or(core::ptr::null(), |v| v), &mut out) };
    out
}

/// A `Map[String, Int]` against an insertion-ordered model: replacing a value keeps the
/// position, removing leaves a hole that compaction reclaims, and order survives both.
fn string_map_matches_ordered_model(seed: u64) {
    let _g = testutil::lock();
    let before = live_blocks();
    let mut r = Rng(0x9e37_79b9_7f4a_7c15 ^ seed.wrapping_mul(0x9e37_79b9_7f4a_7c15));
    let (kd, vd) = (&msrt_desc_string, &msrt_desc_int);
    let mut m = empty();
    let mut model: std::vec::Vec<(std::string::String, i64)> = std::vec::Vec::new();
    // SAFETY: descriptors match the stored types; keys and values are consumed as documented.
    unsafe {
        for step in 0..STEPS {
            let k = key(&mut r, 90);
            let mut ks = new_str(&k);
            let probe = &mut ks as *mut _ as *mut u8;
            match r.below(10) {
                0..=4 => {
                    let mut v = step as i64;
                    msrt_map_add(&mut m, kd, vd, probe, &mut v as *mut i64 as *mut u8);
                    match model.iter_mut().find(|e| e.0 == k) {
                        Some(e) => e.1 = v,
                        None => model.push((k, v)),
                    }
                }
                5..=7 => {
                    msrt_map_remove(&mut m, kd, vd, probe);
                    crate::obj::release(ks as *mut Obj);
                    model.retain(|e| e.0 != k);
                }
                8 => {
                    let p = msrt_map_get_ptr(&m, kd, vd, probe);
                    crate::obj::release(ks as *mut Obj);
                    let want = model.iter().find(|e| e.0 == k).map(|e| e.1);
                    assert_eq!(
                        if p.is_null() {
                            None
                        } else {
                            Some(*(p as *const i64))
                        },
                        want
                    );
                }
                _ => {
                    let has = msrt_map_contains(&m, kd, vd, probe) != 0;
                    crate::obj::release(ks as *mut Obj);
                    assert_eq!(has, model.iter().any(|e| e.0 == k));
                }
            }
            assert_eq!(msrt_map_length(&m) as usize, model.len());
            if step % 25 == 0 || model.len() < 3 {
                let mut keys = map_keys_of(&m, kd, Some(vd));
                let want: std::vec::Vec<_> = model.iter().map(|e| e.0.clone()).collect();
                assert_eq!(strings(&keys), want, "step {step}");
                drop_list(&mut keys, kd);
                let mut copy = empty();
                msrt_map_copy(&m, kd, vd, &mut copy);
                assert!(eq_map(&m, &copy, kd, Some(vd)));
                let mut values = VecVal {
                    ptr: core::ptr::null_mut(),
                    len: 0,
                    cap: 0,
                };
                msrt_map_values(&copy, kd, vd, &mut values);
                let want: std::vec::Vec<_> = model.iter().map(|e| e.1).collect();
                assert_eq!(ints(&values), want, "step {step}");
                drop_list(&mut values, vd);
                drop_map(&mut copy, kd, Some(vd));
            }
        }
        drop_map(&mut m, kd, Some(vd));
    }
    assert_eq!(live_blocks(), before);
}

/// `Map[Int, Int]` takes the specialised 24-byte-stride paths.
fn int_map_matches_ordered_model(seed: u64) {
    let _g = testutil::lock();
    let before = live_blocks();
    let mut r = Rng(0xdead_beef_cafe_f00d ^ seed.wrapping_mul(0x9e37_79b9_7f4a_7c15));
    let d = &msrt_desc_int;
    let mut m = empty();
    let mut model: std::vec::Vec<(i64, i64)> = std::vec::Vec::new();
    // SAFETY: int slots own nothing.
    unsafe {
        for step in 0..STEPS {
            let mut k = r.below(70) as i64 - 20;
            let kp = &mut k as *mut i64 as *mut u8;
            match r.below(4) {
                0 | 1 => {
                    let mut v = step as i64;
                    msrt_map_add(&mut m, d, d, kp, &mut v as *mut i64 as *mut u8);
                    match model.iter_mut().find(|e| e.0 == k) {
                        Some(e) => e.1 = v,
                        None => model.push((k, v)),
                    }
                }
                2 => {
                    msrt_map_remove(&mut m, d, d, kp);
                    model.retain(|e| e.0 != k);
                }
                _ => {
                    let p = msrt_map_get_ptr(&m, d, d, kp);
                    let want = model.iter().find(|e| e.0 == k).map(|e| e.1);
                    assert_eq!(
                        if p.is_null() {
                            None
                        } else {
                            Some(*(p as *const i64))
                        },
                        want
                    );
                }
            }
            if step % 16 == 0 {
                let mut keys = map_keys_of(&m, d, Some(d));
                let want: std::vec::Vec<_> = model.iter().map(|e| e.0).collect();
                assert_eq!(ints(&keys), want, "step {step}");
                drop_list(&mut keys, d);
            }
        }
        // Drain through removal until empty: the table must stay consistent through compaction.
        while let Some(&(mut k, _)) = model.first() {
            msrt_map_remove(&mut m, d, d, &mut k as *mut i64 as *mut u8);
            model.remove(0);
            assert_eq!(msrt_map_length(&m) as usize, model.len());
        }
        let (mut k, mut v) = (7i64, 8i64);
        msrt_map_add(
            &mut m,
            d,
            d,
            &mut k as *mut i64 as *mut u8,
            &mut v as *mut i64 as *mut u8,
        );
        assert_eq!(msrt_map_length(&m), 1);
        drop_map(&mut m, d, Some(d));
    }
    assert_eq!(live_blocks(), before);
}

/// Set algebra against `Vec` models (left order, first occurrence wins).
fn string_set_algebra_matches_model(seed: u64) {
    let _g = testutil::lock();
    let before = live_blocks();
    let mut r = Rng(0x1234_5678_9abc_def1 ^ seed.wrapping_mul(0x9e37_79b9_7f4a_7c15));
    let kd = &msrt_desc_string;
    // SAFETY: string keys are consumed by `msrt_map_add`.
    unsafe {
        for _ in 0..(STEPS / 40).max(4) {
            let mut sets = [empty(), empty()];
            let mut models: [std::vec::Vec<std::string::String>; 2] = Default::default();
            for (set, model) in sets.iter_mut().zip(models.iter_mut()) {
                for _ in 0..r.below(30) {
                    let k = key(&mut r, 25);
                    let mut ks = new_str(&k);
                    msrt_map_add(
                        set,
                        kd,
                        core::ptr::null(),
                        &mut ks as *mut _ as *mut u8,
                        core::ptr::null_mut(),
                    );
                    if !model.contains(&k) {
                        model.push(k);
                    }
                }
            }
            let [a, b] = &models;
            let ops: [(&str, SetOp, std::vec::Vec<std::string::String>); 4] = [
                (
                    "union",
                    msrt_set_union,
                    a.iter()
                        .chain(b.iter().filter(|k| !a.contains(k)))
                        .cloned()
                        .collect(),
                ),
                (
                    "intersection",
                    msrt_set_intersection,
                    a.iter().filter(|k| b.contains(k)).cloned().collect(),
                ),
                (
                    "difference",
                    msrt_set_difference,
                    a.iter().filter(|k| !b.contains(k)).cloned().collect(),
                ),
                (
                    "symmetric_difference",
                    msrt_set_symmetric_difference,
                    a.iter()
                        .filter(|k| !b.contains(k))
                        .chain(b.iter().filter(|k| !a.contains(k)))
                        .cloned()
                        .collect(),
                ),
            ];
            for (name, f, want) in ops {
                let mut out = empty();
                f(&sets[0], &sets[1], kd, &mut out);
                let mut keys = map_keys_of(&out, kd, None);
                assert_eq!(strings(&keys), want, "{name}");
                drop_list(&mut keys, kd);
                drop_map(&mut out, kd, None);
            }
            let sub = a.iter().all(|k| b.contains(k));
            assert_eq!(msrt_set_is_subset_of(&sets[0], &sets[1], kd) != 0, sub);
            assert_eq!(msrt_set_is_superset_of(&sets[1], &sets[0], kd) != 0, sub);
            let disjoint = !a.iter().any(|k| b.contains(k));
            assert_eq!(
                msrt_set_is_disjoint_from(&sets[0], &sets[1], kd) != 0,
                disjoint
            );
            for set in &mut sets {
                drop_map(set, kd, None);
            }
        }
    }
    assert_eq!(live_blocks(), before);
}

type SetOp =
    unsafe extern "C-unwind" fn(*const MapVal, *const MapVal, *const TypeDesc, *mut MapVal);

unsafe extern "C-unwind" fn cmp_strings(_: *mut u8, a: *const u8, b: *const u8) -> i64 {
    // SAFETY: string slots.
    unsafe {
        string::bytes(*(a as *const *const StrObj)).cmp(string::bytes(*(b as *const *const StrObj)))
            as i64
    }
}

fn pick(r: &mut Rng, len: usize) -> usize {
    r.below(len + 1)
}

/// `List[String]` mutators against `Vec<String>`; strings are reference counted, so a wrong
/// retain or release shows up as a leak or a use after free (Miri) at the end.
fn string_list_matches_vec_model(seed: u64) {
    let _g = testutil::lock();
    let before = live_blocks();
    let mut r = Rng(0x0bad_5eed_0bad_5eed ^ seed.wrapping_mul(0x9e37_79b9_7f4a_7c15));
    let d = &msrt_desc_string;
    let mut v = VecVal {
        ptr: core::ptr::null_mut(),
        len: 0,
        cap: 0,
    };
    let mut model: std::vec::Vec<std::string::String> = std::vec::Vec::new();
    // SAFETY: descriptors match the stored types; consumed arguments are fresh strings.
    unsafe {
        for step in 0..STEPS {
            let n = model.len();
            let s = key(&mut r, 14);
            let mut e = new_str(&s);
            let ep = &mut e as *mut _ as *const u8;
            match r.below(17) {
                0..=2 => {
                    msrt_list_push(&mut v, d, ep);
                    model.push(s);
                }
                3 => {
                    let i = pick(&mut r, n);
                    msrt_list_insert(&mut v, d, i as i64, ep);
                    model.insert(i, s);
                }
                4 => {
                    msrt_list_prepend(&mut v, d, ep);
                    model.insert(0, s);
                }
                5 => {
                    if n == 0 {
                        crate::obj::release(e as *mut Obj);
                    } else {
                        let i = r.below(n);
                        msrt_list_set(&mut v, d, i as i64, ep);
                        model[i] = s;
                    }
                }
                6 => {
                    crate::obj::release(e as *mut Obj);
                    if n > 0 {
                        let i = r.below(n);
                        msrt_list_remove(&mut v, d, i as i64 - n as i64);
                        model.remove(i);
                    }
                }
                7 => {
                    crate::obj::release(e as *mut Obj);
                    let mut out: *mut StrObj = core::ptr::null_mut();
                    let got = msrt_list_pop(&mut v, d, &mut out as *mut _ as *mut u8) != 0;
                    assert_eq!(got, n > 0);
                    if got {
                        assert_eq!(text(out), model.pop().unwrap());
                        crate::obj::release(out as *mut Obj);
                    }
                }
                8 => {
                    crate::obj::release(e as *mut Obj);
                    let mut out: *mut StrObj = core::ptr::null_mut();
                    let got = msrt_list_shift(&mut v, d, &mut out as *mut _ as *mut u8) != 0;
                    assert_eq!(got, n > 0);
                    if got {
                        assert_eq!(text(out), model.remove(0));
                        crate::obj::release(out as *mut Obj);
                    }
                }
                9 => {
                    crate::obj::release(e as *mut Obj);
                    let start = pick(&mut r, n);
                    let count = pick(&mut r, n - start);
                    let mut rep = VecVal {
                        ptr: core::ptr::null_mut(),
                        len: 0,
                        cap: 0,
                    };
                    let mut rep_model = std::vec::Vec::new();
                    for _ in 0..r.below(4) {
                        let k = key(&mut r, 14);
                        let mut ks = new_str(&k);
                        msrt_list_push(&mut rep, d, &mut ks as *mut _ as *const u8);
                        rep_model.push(k);
                    }
                    msrt_list_splice(&mut v, d, start as i64, count as i64, &mut rep);
                    assert_eq!(rep.len, 0);
                    model.splice(start..start + count, rep_model);
                }
                10 => {
                    crate::obj::release(e as *mut Obj);
                    msrt_list_reverse_in_place(&mut v, d);
                    model.reverse();
                }
                11 => {
                    crate::obj::release(e as *mut Obj);
                    msrt_list_sort_in_place(&mut v, d, cmp_strings, core::ptr::null_mut());
                    model.sort();
                }
                12 => {
                    crate::obj::release(e as *mut Obj);
                    let mut out = VecVal {
                        ptr: core::ptr::null_mut(),
                        len: 0,
                        cap: 0,
                    };
                    msrt_list_distinct(&v, d, &mut out);
                    let mut want: std::vec::Vec<std::string::String> = std::vec::Vec::new();
                    for k in &model {
                        if !want.contains(k) {
                            want.push(k.clone());
                        }
                    }
                    assert_eq!(strings(&out), want);
                    drop_list(&mut out, d);
                }
                13 => {
                    crate::obj::release(e as *mut Obj);
                    let (a, b) = (pick(&mut r, n), pick(&mut r, n));
                    let (a, b) = (a.min(b), a.max(b));
                    let mut out = VecVal {
                        ptr: core::ptr::null_mut(),
                        len: 0,
                        cap: 0,
                    };
                    assert_eq!(
                        msrt_list_slice(&v, d, a as i64, b as i64, &mut out),
                        STATUS_OK
                    );
                    assert_eq!(strings(&out), model[a..b]);
                    drop_list(&mut out, d);
                }
                14 => {
                    // `fill` borrows its value; the value comes from outside the list.
                    let (a, b) = (pick(&mut r, n), pick(&mut r, n));
                    let (a, b) = (a.min(b), a.max(b));
                    msrt_list_fill(&mut v, d, ep, a as i64, b as i64);
                    crate::obj::release(e as *mut Obj);
                    model[a..b].fill(s);
                }
                15 => {
                    crate::obj::release(e as *mut Obj);
                    if n > 0 {
                        let (a, b) = (r.below(n), r.below(n + 1));
                        let (a, b) = (a.min(b), a.max(b));
                        let target = r.below(n);
                        msrt_list_copy_within(&mut v, d, target as i64, a as i64, b as i64);
                        let count = (b - a).min(n - target);
                        let chunk: std::vec::Vec<_> = model[a..a + count].to_vec();
                        model[target..target + count].clone_from_slice(&chunk);
                    }
                }
                _ => {
                    crate::obj::release(e as *mut Obj);
                    let mut other = VecVal {
                        ptr: core::ptr::null_mut(),
                        len: 0,
                        cap: 0,
                    };
                    msrt_list_concat(&v, &v, d, &mut other);
                    let want: std::vec::Vec<_> =
                        model.iter().chain(model.iter()).cloned().collect();
                    assert_eq!(strings(&other), want);
                    drop_list(&mut other, d);
                }
            }
            assert_eq!(strings(&v), model, "step {step}");
        }
        drop_list(&mut v, d);
    }
    assert_eq!(live_blocks(), before);
}

/// Scalar-indexed string operations against `char` based models, over mixed-width text.
fn string_ops_match_char_model(seed: u64) {
    let _g = testutil::lock();
    let before = live_blocks();
    let mut r = Rng(0x5eed_1234_5eed_4321 ^ seed.wrapping_mul(0x9e37_79b9_7f4a_7c15));
    const ALPHABET: [char; 8] = ['a', 'b', ' ', 'é', '日', '😀', 'z', '\n'];
    let build = |r: &mut Rng, max: usize| -> std::string::String {
        (0..r.below(max))
            .map(|_| ALPHABET[r.below(ALPHABET.len())])
            .collect()
    };
    // SAFETY: strings built here are live until released.
    unsafe {
        for _ in 0..(STEPS / 10).max(8) {
            // Long inputs exercise the sequential-access hint (strings over 256 bytes).
            let max = if r.below(4) == 0 { 400 } else { 24 };
            let model = build(&mut r, max);
            let s = new_str(&model);
            let chars: std::vec::Vec<char> = model.chars().collect();
            let n = chars.len();
            assert_eq!(string::msrt_string_length(s), n as i64);
            for _ in 0..8 {
                let a = r.below(n + 1);
                let b = a + r.below(n + 1 - a);
                let mut out: *mut StrObj = core::ptr::null_mut();
                assert_eq!(
                    string::msrt_string_slice_scalars(s, a as i64, b as i64, &mut out),
                    STATUS_OK
                );
                assert_eq!(
                    text(out),
                    chars[a..b].iter().collect::<std::string::String>()
                );
                assert_eq!(string::msrt_string_length(out), (b - a) as i64);
                crate::obj::release(out as *mut Obj);
            }
            for _ in 0..n.min(6) {
                let i = r.below(n);
                let got = string::msrt_string_get(s, i as i64, core::ptr::null_mut());
                assert_eq!(text(got), chars[i].to_string());
                crate::obj::release(got as *mut Obj);
                assert_eq!(
                    string::msrt_string_scalar_at(s, i as i64 - n as i64, 0, 0),
                    chars[i] as i64
                );
            }
            let needle = build(&mut r, 3);
            let ns = new_str(&needle);
            let mut at = 0i64;
            let found = string::msrt_string_index_of(s, ns, &mut at) != 0;
            let want = model
                .find(&needle)
                .map(|b| model[..b].chars().count() as i64);
            assert_eq!(found.then_some(at), want);
            let found = string::msrt_string_last_index_of(s, ns, &mut at) != 0;
            let want = model
                .rfind(&needle)
                .map(|b| model[..b].chars().count() as i64);
            assert_eq!(found.then_some(at), want);
            if !needle.is_empty() {
                let rep = new_str("<>");
                let got = string::msrt_string_replace_n(s, ns, rep, i64::MAX);
                assert_eq!(text(got), model.replace(&needle, "<>"));
                crate::obj::release(got as *mut Obj);
                crate::obj::release(rep as *mut Obj);
                let mut parts = VecVal {
                    ptr: core::ptr::null_mut(),
                    len: 0,
                    cap: 0,
                };
                string::msrt_string_split(s, ns, 0, 0, &mut parts);
                let want: std::vec::Vec<_> = model
                    .split(&needle)
                    .map(std::string::String::from)
                    .collect();
                assert_eq!(strings(&parts), want);
                drop_list(&mut parts, &msrt_desc_string);
            }
            let rev = string::msrt_string_reverse(s);
            assert_eq!(
                text(rev),
                model.chars().rev().collect::<std::string::String>()
            );
            crate::obj::release(rev as *mut Obj);
            let trimmed = string::msrt_string_trim(s);
            assert_eq!(text(trimmed), model.trim());
            crate::obj::release(trimmed as *mut Obj);
            let cat = string::msrt_string_concat(s, ns);
            assert_eq!(text(cat), std::format!("{model}{needle}"));
            assert_eq!(
                string::msrt_string_length(cat),
                (n + needle.chars().count()) as i64
            );
            crate::obj::release(cat as *mut Obj);
            crate::obj::release(ns as *mut Obj);
            crate::obj::release(s as *mut Obj);
        }
    }
    assert_eq!(live_blocks(), before);
}

/// Each model runs over several seeds (a single one under Miri, which is slow).
#[test]
fn collections_and_strings_match_their_models() {
    let seeds = if cfg!(miri) { 1 } else { 12 };
    for seed in 0..seeds {
        string_map_matches_ordered_model(seed);
        int_map_matches_ordered_model(seed);
        string_set_algebra_matches_model(seed);
        string_list_matches_vec_model(seed);
        string_ops_match_char_model(seed);
    }
}

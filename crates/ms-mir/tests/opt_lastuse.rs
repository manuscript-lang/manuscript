use ms_mir::ir::{Module, Op};
use ms_mir::opt;
use ms_mir::parse::parse_module;
use ms_mir::verify::verify_module;

fn optimized(src: &str) -> Module {
    let mut m = parse_module(src).expect("parse");
    verify_module(&m).expect("input verifies");
    opt::lastuse::run(&mut m);
    verify_module(&m).expect("output verifies");
    m
}

/// Op names of the entry function's blocks, in order, as one line per block.
fn ops(m: &Module, name: &str) -> Vec<Vec<Op>> {
    let f = &m.funcs[m.func_by_name(name).expect("function").index()];
    f.blocks
        .iter()
        .map(|b| b.insts.iter().map(|i| i.op).collect())
        .collect()
}

const STRAIGHT: &str = r#"module "t"
file 0 "t.ms"
entry @main

fn @main() -> int export {
b0:
  %0: list<int> = list.lit
  %1: int = list.len %0
  %2: list<int> = list.lit
  %3: int = list.len %2
  %4: int = iadd %1, %3
  drop %2
  drop %0
  ret %4
}
"#;

#[test]
fn a_value_is_dropped_right_after_its_last_use() {
    let m = optimized(STRAIGHT);
    let b = &ops(&m, "main")[0];
    let drops: Vec<usize> = (0..b.len()).filter(|k| b[*k] == Op::Drop).collect();
    // `%0` goes before the second list is built; `%2` right after its length is read.
    assert_eq!(b[..4], [Op::ListLit, Op::ListLen, Op::Drop, Op::ListLit]);
    assert_eq!(drops.len(), 2);
}

const LOOP: &str = r#"module "t"
file 0 "t.ms"
entry @main

fn @main() -> int export {
b0:
  %0: list<int> = list.lit
  %1: int = iconst 0
  %2: int = iconst 3
  %3: int = iconst 1
  br b1(%1)
b1(%4: int):
  %5: bool = icmp.lt %4, %2
  br_if %5, b2(), b3()
b2():
  %6: int = list.len %0
  %7: int = iadd %4, %3
  br b1(%7)
b3():
  drop %0
  ret %1
}
"#;

#[test]
fn a_value_used_in_a_loop_is_dropped_on_the_exit_edge() {
    let m = optimized(LOOP);
    let all = ops(&m, "main");
    // Never inside the loop body.
    assert!(!all[2].contains(&Op::Drop));
    assert_eq!(all.iter().flatten().filter(|o| **o == Op::Drop).count(), 1);
}

const LENT: &str = r#"module "t"
file 0 "t.ms"
extern @msrt_map_new() -> Map<str, str>
extern @msrt_map_get_ptr(Map<str, str>, ptr, ptr, ptr) -> ptr
entry @main

fn @main() -> int export {
b0:
  %m: Map<str, str> = call.rt @msrt_map_new ()
  %k: str = str "a"
  %kd: ptr = typedesc str
  %vd: ptr = typedesc str
  %ks: ptr = slot str
  store %ks, %k
  %p: ptr = call.rt @msrt_map_get_ptr (%m, %kd, %vd, %ks)
  %miss: bool = ptr.is_null %p
  %hit: bool = not %miss
  br_if %hit, b1(), b2()
b1():
  %v: str = load str %p
  %o: opt<str> = opt.view %v
  br b3(%o)
b2():
  %n: opt<str> = opt.none
  br b3(%n)
b3(%r: opt<str>):
  %some: bool = opt.is_some %r
  %len: int = b2i %some
  drop %m
  ret %len
}
"#;

/// A map read in place (`let x = m.get(k)` lowers to the entry pointer, a `load` and
/// `opt.view`) keeps the map alive until the borrowed optional's last use: the pointer and the
/// values read through it belong to the map's family, so `drop %m` cannot move above them.
#[test]
fn a_borrowed_entry_keeps_its_container_alive() {
    let m = optimized(LENT);
    let all = ops(&m, "main");
    assert!(!all[0].contains(&Op::Drop), "{all:?}");
    assert!(!all[1].contains(&Op::Drop), "{all:?}");
    assert!(!all[2].contains(&Op::Drop), "{all:?}");
    let last = &all[3];
    let drop = last.iter().position(|o| *o == Op::Drop).expect("drop");
    let use_ = last.iter().position(|o| *o == Op::OptIsSome).expect("use");
    assert!(use_ < drop, "{all:?}");
}

/// `"a" + "b" + "c"`: a chain of concatenations whose intermediate results are dropped at the
/// end of the function.
fn concat_chain(fresh: &str) -> String {
    format!(
        r#"module "t"
file 0 "t.ms"
extern @msrt_string_concat(str, str) -> str{fresh} string_concat

fn @main() -> int export {{
b0:
  %0: str = str "a"
  %1: str = str "b"
  %2: str = call.rt @msrt_string_concat (%0, %1)
  %3: str = str "c"
  %4: str = call.rt @msrt_string_concat (%2, %3)
  %5: str = str "d"
  %6: str = call.rt @msrt_string_concat (%4, %5)
  %7: int = str.len %6
  drop %6
  drop %4
  drop %2
  ret %7
}}
"#
    )
}

#[test]
fn a_fresh_runtime_result_does_not_keep_its_arguments_alive() {
    // With `fresh`, each intermediate string is dropped right after the concat that read it,
    // so one link is live at a time instead of the whole chain until the end.
    let m = optimized(&concat_chain(" fresh"));
    let b = &ops(&m, "main")[0];
    assert_eq!(
        b[..],
        [
            Op::StrLit,
            Op::StrLit,
            Op::CallRt,
            Op::StrLit,
            Op::CallRt,
            Op::Drop,
            Op::StrLit,
            Op::CallRt,
            Op::Drop,
            Op::StrLen,
            Op::Drop,
        ]
    );
}

#[test]
fn a_runtime_result_without_fresh_may_borrow_from_its_arguments() {
    // Without the attribute the result is assumed to point into its arguments, so the
    // arguments live as long as the result: the drops stay where lowering put them.
    let m = optimized(&concat_chain(""));
    let b = &ops(&m, "main")[0];
    let drops: Vec<usize> = (0..b.len()).filter(|k| b[*k] == Op::Drop).collect();
    assert_eq!(drops, [8, 9, 10]);
}

/// `n` strings built from two literals each, measured, and all dropped at the end of the scope.
fn many_strings(n: usize) -> String {
    let mut s = String::from(
        r#"module "t"
file 0 "t.ms"
extern @msrt_string_concat(str, str) -> str fresh string_concat

fn @main() -> int export {
b0:
  %0: int = iconst 0
"#,
    );
    let mut v = 1;
    let mut acc = 0;
    let mut strings = Vec::new();
    for _ in 0..n {
        s.push_str(&format!(
            "  %{v}: str = str \"a\"\n  %{}: str = str \"b\"\n",
            v + 1
        ));
        s.push_str(&format!(
            "  %{}: str = call.rt @msrt_string_concat (%{v}, %{})\n",
            v + 2,
            v + 1
        ));
        s.push_str(&format!("  %{}: int = str.len %{}\n", v + 3, v + 2));
        s.push_str(&format!("  %{}: int = iadd %{acc}, %{}\n", v + 4, v + 3));
        strings.push(v + 2);
        acc = v + 4;
        v += 5;
    }
    for w in strings {
        s.push_str(&format!("  drop %{w}\n"));
    }
    s.push_str(&format!("  ret %{acc}\n}}\n"));
    s
}

#[test]
fn a_large_function_is_handled_in_linear_time() {
    // 3000 strings (15 000 instructions): every string is dropped right after its length is
    // read, and the pass finishes quickly. The previous pass rescanned the whole function
    // for each candidate and skipped functions over 4000 instructions altogether.
    let n = 3000;
    let start = std::time::Instant::now();
    let m = optimized(&many_strings(n));
    assert!(start.elapsed().as_secs() < 20, "took {:?}", start.elapsed());
    let b = &ops(&m, "main")[0];
    let drops = b.iter().filter(|op| **op == Op::Drop).count();
    assert_eq!(drops, n);
    assert_eq!(
        b[..7],
        [
            Op::IConst,
            Op::StrLit,
            Op::StrLit,
            Op::CallRt,
            Op::StrLen,
            Op::Drop,
            Op::IAdd
        ]
    );
    assert_eq!(b[b.len() - 2..], [Op::Drop, Op::IAdd]);
}

/// `STRAIGHT` with `padding` extra instructions in the entry block.
fn padded(padding: usize) -> String {
    let filler: String = (0..padding)
        .map(|k| format!("  %{}: int = iconst 1\n", k + 10))
        .collect();
    STRAIGHT.replace("  %4: int = iadd", &format!("{filler}  %4: int = iadd"))
}

#[test]
fn an_unoptimized_build_moves_drops_only_in_a_long_function() {
    let drop_before_second_list = |padding: usize| {
        let mut m = parse_module(&padded(padding)).expect("parse");
        opt::optimize(&mut m, opt::Level::None, false);
        let b = &ops(&m, "main")[0];
        b[2] == Op::Drop
    };
    assert!(!drop_before_second_list(0));
    assert!(drop_before_second_list(opt::LONG_FUNCTION_INSTS));
}

const JOINED_DROP: &str = r#"module "t"
file 0 "t.ms"
extern @msrt_fill(str, ptr) -> int
entry @main

fn @main() -> int export {
b0:
  %lit: str = str "a"
  %k: str = clone %lit
  %out: ptr = slot str
  %c: int = call.rt @msrt_fill (%k, %out)
  %t: str = take str %out
  br b1(%t)
b1(%p: move str):
  drop %p
  drop %k
  ret %c
}
"#;

/// The drop of a family member (`%p`, fed from an out-slot of a call that took `%k`) moves to the
/// start of its block; `%k` then lives until that drop and must still be dropped after it.
#[test]
fn a_drop_at_the_start_of_a_join_block_counts_as_a_use() {
    let m = optimized(JOINED_DROP);
    let all = ops(&m, "main");
    assert_eq!(all[1], [Op::Drop, Op::Drop]);
}

/// A chain of types that each hold two lists of the previous one: linear in types, but every
/// path through it is distinct.
fn shared_type_chain(depth: usize) -> String {
    let mut s = String::from("module \"dag\"\ntype R0 { value: str }\n");
    for k in 1..=depth {
        s += &format!(
            "type R{k} {{ left: list<R{}>, right: list<R{}> }}\n",
            k - 1,
            k - 1
        );
    }
    s += &format!(
        "entry @main\nfn @main() -> int export {{\nb0:\n %x: list<R{depth}> = list.lit\n %z: int = list.len %x\n drop %x\n ret %z\n}}\n"
    );
    s
}

/// Classifying a type once per path made this exponential in the nesting depth.
#[test]
fn shared_type_types_are_classified_once() {
    let mut m = parse_module(&shared_type_chain(60)).expect("parse");
    verify_module(&m).expect("input verifies");
    let start = std::time::Instant::now();
    opt::lastuse::run(&mut m);
    assert!(start.elapsed().as_secs() < 5, "took {:?}", start.elapsed());
    verify_module(&m).expect("output verifies");
}

/// `n` lists, each consumed on one branch and dropped on the other, one after another.
fn branching_consumers(n: usize) -> String {
    let mut s = String::from(
        r#"module "t"
file 0 "t.ms"
entry @main

fn @eat(%l: move list<int>) -> int inline(never) {
b0:
  %n: int = list.len %l
  drop %l
  ret %n
}

fn @main() -> int export {
b0:
  %z: int = iconst 0
  br b1(%z)
"#,
    );
    for k in 0..n {
        let (a, b, c, next) = (3 * k + 1, 3 * k + 2, 3 * k + 3, 3 * k + 4);
        let last = k + 1 == n;
        s.push_str(&format!(
            "b{a}(%acc{k}: int):\n  %v{k}: list<int> = list.lit\n  %t{k}: bool = icmp.eq %acc{k}, %z\n  br_if %t{k}, b{b}(), b{c}()\nb{b}():\n  %e{k}: int = call @eat (%v{k})\n  br b{next}(%e{k})\nb{c}():\n  drop %v{k}\n  br b{next}(%z)\n"
        ));
        if last {
            s.push_str(&format!("b{next}(%out: int):\n  ret %out\n"));
        }
    }
    s.push_str("}\n");
    s
}

/// A value consumed on one branch used to keep its analysis region running through the rest of
/// the function, so a chain of them was quadratic (14 s for 4000 in an unoptimized build).
#[test]
fn a_chain_of_branch_consumed_values_is_handled_in_linear_time() {
    let mut m = parse_module(&branching_consumers(6000)).expect("parse");
    verify_module(&m).expect("input verifies");
    let start = std::time::Instant::now();
    opt::lastuse::run(&mut m);
    assert!(start.elapsed().as_secs() < 10, "took {:?}", start.elapsed());
    verify_module(&m).expect("output verifies");
}

/// `n` lists, each read once right after it is built and dropped at the end of the function,
/// with a branch between one list and the next.
fn long_lived_lists(n: usize) -> String {
    let mut s = String::from(
        "module \"t\"\nfile 0 \"t.ms\"\nentry @main\n\nfn @main() -> int export {\nb0:\n  %z: int = iconst 0\n  br b1(%z)\n",
    );
    for k in 0..n {
        let (a, b, c, next) = (3 * k + 1, 3 * k + 2, 3 * k + 3, 3 * k + 4);
        s.push_str(&format!(
            "b{a}(%acc{k}: int):\n  %v{k}: list<int> = list.lit\n  %n{k}: int = list.len %v{k}\n  %t{k}: bool = icmp.eq %n{k}, %z\n  br_if %t{k}, b{b}(), b{c}()\nb{b}():\n  br b{next}(%n{k})\nb{c}():\n  br b{next}(%z)\n"
        ));
    }
    s.push_str(&format!("b{}(%out: int):\n", 3 * n + 1));
    for k in (0..n).rev() {
        s.push_str(&format!("  drop %v{k}\n"));
    }
    s.push_str("  ret %out\n}\n");
    s
}

/// The region of a value used only near its definition used to run on to the end of the
/// function, so a function of many such values was quadratic (45 s for 800 `map`/`filter`
/// pipelines in an unoptimized build).
#[test]
fn a_chain_of_long_lived_values_is_handled_in_linear_time() {
    let n = 6000;
    let mut m = parse_module(&long_lived_lists(n)).expect("parse");
    verify_module(&m).expect("input verifies");
    let start = std::time::Instant::now();
    opt::lastuse::run(&mut m);
    assert!(start.elapsed().as_secs() < 10, "took {:?}", start.elapsed());
    verify_module(&m).expect("output verifies");
    // Every list is dropped right after its length is read, in the block that built it.
    let blocks = ops(&m, "main");
    assert_eq!(blocks[1][..3], [Op::ListLit, Op::ListLen, Op::Drop]);
    let drops: usize = blocks
        .iter()
        .flatten()
        .filter(|op| **op == Op::Drop)
        .count();
    assert_eq!(drops, n);
}

#[test]
fn independent_values_in_one_block_keep_their_drop_positions() {
    let n = 2048;
    let mut src =
        String::from("module \"pending\"\nfn @main() -> int export {\nb0:\n  %z: int = iconst 0\n");
    for k in 0..n {
        src.push_str(&format!(
            "  %v{k}: list<int> = list.lit\n  %n{k}: int = list.len %v{k}\n"
        ));
    }
    for k in (0..n).rev() {
        src.push_str(&format!("  drop %v{k}\n"));
    }
    src.push_str("  ret %z\n}\n");
    let m = optimized(&src);
    let f = &m.funcs[m.func_by_name("main").unwrap().index()];
    let insts = &f.blocks[0].insts;
    assert_eq!(insts.len(), 1 + 3 * n);
    for group in insts[1..].as_chunks::<3>().0 {
        assert_eq!(group[0].op, Op::ListLit);
        assert_eq!(group[1].op, Op::ListLen);
        assert_eq!(group[2].op, Op::Drop);
        assert_eq!(group[2].args, [group[0].res.unwrap()]);
    }
}

//! Lifetime markers for block-confined stack slots of a function body written as LLVM text.
//!
//! Lowering gives every temporary (an out-parameter of a call, a string spilled for a runtime
//! call, a copied record) its own `alloca`. Without `llvm.lifetime.start` and `.end`, LLVM's
//! stack coloring cannot overlap two slots, so a function with many such statements keeps all of
//! them in its frame; a recursive parser then pays kilobytes of stack per call.
//!
//! A slot whose address is only formed, offset, loaded through, stored through and passed to
//! calls inside one block is live only in that block: the marker starts before the first
//! mention and ends before the terminator. A slot used in several blocks, whose address is
//! stored, merged by a `phi` or returned, or whose first access reads it, keeps no marker.

use std::collections::{HashMap, HashSet};

/// The declarations the markers call; the module prelude holds them once.
pub const DECLARES: &str = "declare void @llvm.lifetime.start.p0(ptr captures(none))\n\
                            declare void @llvm.lifetime.end.p0(ptr captures(none))\n";

/// Runtime calls that keep a pointer argument after they return, so its slot outlives the block.
const RETAINS: [&str; 4] = [
    "msrt_cleanup_push",
    "msrt_task_spawn",
    "msrt_promise_defer",
    "msrt_guard_call",
];

/// Operations whose result is an address derived from an operand address.
const DERIVES: [&str; 5] = ["getelementptr", "ptrtoint", "inttoptr", "add", "sub"];

/// `body` (the text after the allocas) with markers for the slots `allocas` declares.
pub fn mark(allocas: &str, body: &str) -> String {
    let slots: Vec<&str> = allocas
        .lines()
        .filter_map(|l| l.trim_start().split_once(" = alloca").map(|(name, _)| name))
        .collect();
    if slots.is_empty() {
        return body.to_string();
    }
    let lines: Vec<&str> = body.lines().collect();
    let (owner, tainted) = aliases(&slots, &lines);
    let mut starts: HashMap<usize, Vec<&str>> = HashMap::new();
    let mut ends: HashMap<usize, Vec<&str>> = HashMap::new();
    for (slot, first, end) in confined(&slots, &tainted, &owner, &lines) {
        starts.entry(first).or_default().push(slot);
        if let Some(end) = end {
            ends.entry(end).or_default().push(slot);
        }
    }
    let mut out = String::with_capacity(body.len() + 128 * starts.len());
    for (i, line) in lines.iter().enumerate() {
        for (map, which) in [(&starts, "start"), (&ends, "end")] {
            for slot in map.get(&i).into_iter().flatten() {
                let dbg = line.rfind(", !dbg !").map_or("", |at| &line[at..]);
                out.push_str(&format!(
                    "  call void @llvm.lifetime.{which}.p0(ptr {slot}){dbg}\n"
                ));
            }
        }
        out.push_str(line);
        out.push('\n');
    }
    out
}

/// Every local value name in `line`, in order.
fn names(line: &str) -> impl Iterator<Item = &str> {
    let bytes = line.as_bytes();
    let mut at = 0;
    std::iter::from_fn(move || {
        while at < bytes.len() {
            let start = at;
            at += 1;
            if bytes[start] == b'%' && bytes.get(at).is_some_and(|c| *c != b'"') {
                let len = bytes[at..]
                    .iter()
                    .take_while(|c| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'.'))
                    .count();
                at += len;
                return Some(&line[start..at]);
            }
        }
        None
    })
}

/// A defined value and its operation: `%d = op ...`.
fn def(line: &str) -> Option<(&str, &str)> {
    let (lhs, rhs) = line.trim_start().split_once(" = ")?;
    lhs.starts_with('%')
        .then(|| rhs.split_whitespace().next().map(|op| (lhs, op)))?
}

fn is_label(line: &str) -> bool {
    !line.starts_with(' ') && !line.is_empty() && line.contains(':')
}

/// Maps each address derived from a slot (a `getelementptr`, `ptrtoint` or integer offset of it)
/// to the slot, and lists the slots an address was derived from together with another slot.
fn aliases<'a>(
    slots: &[&'a str],
    lines: &[&'a str],
) -> (HashMap<&'a str, &'a str>, HashSet<&'a str>) {
    let mut owner: HashMap<&str, &str> = slots.iter().map(|s| (*s, *s)).collect();
    let mut tainted = HashSet::new();
    // Blocks need not be written in dominance order, so repeat until no address is new.
    loop {
        let before = owner.len();
        for line in lines {
            let Some((d, op)) = def(line) else { continue };
            if !DERIVES.contains(&op) {
                continue;
            }
            let roots: HashSet<&str> = names(line)
                .filter(|n| *n != d)
                .filter_map(|n| owner.get(n).copied())
                .collect();
            if roots.len() > 1 {
                tainted.extend(roots.iter().copied());
            }
            if let Some(root) = roots.into_iter().next() {
                owner.insert(d, root);
            }
        }
        if owner.len() == before {
            return (owner, tainted);
        }
    }
}

/// How one line uses an address.
#[derive(PartialEq)]
enum Use {
    Read,
    Write,
    Escape,
}

fn classify(line: &str, name: &str) -> Use {
    let has = |part: &str| names(part).any(|n| n == name);
    let text = line.trim_start();
    if let Some(rest) = text.strip_prefix("store ") {
        // `store <type> <value>, ptr <address>`: the address follows the last ", ptr ".
        let (value, address) = rest.rsplit_once(", ptr ").unwrap_or((rest, ""));
        return if !has(value) && has(address) {
            Use::Write
        } else {
            Use::Escape
        };
    }
    let rhs = text.split_once(" = ").map_or(text, |(_, rhs)| rhs);
    if rhs.starts_with("load ") {
        return Use::Read;
    }
    let Some((callee, args)) = rhs
        .strip_prefix("call ")
        .or_else(|| rhs.strip_prefix("tail call "))
        .and_then(|call| call.split_once('('))
    else {
        return Use::Escape;
    };
    let args: Vec<&str> = args.split(", ").collect();
    let Some(at) = args.iter().position(|a| has(a)) else {
        return Use::Escape;
    };
    if callee.contains("@llvm.lifetime")
        || callee.contains("@llvm.ptrmask")
        || RETAINS.iter().any(|name| callee.contains(name))
    {
        Use::Escape
    } else if callee.contains("@llvm.memcpy") || callee.contains("@llvm.memmove") {
        if at == 0 { Use::Write } else { Use::Read }
    } else if args[at].contains("readonly") {
        Use::Read
    } else {
        Use::Write
    }
}

/// What one pass over the body learns about a slot.
#[derive(Default)]
struct Slot {
    /// The line and block of the first mention.
    first: Option<(usize, usize)>,
    written: bool,
    /// A mention in another block or an unsafe one: no marker.
    dead: bool,
}

/// For each untainted slot whose mentions are all in one block and none unsafe: the line of the
/// first mention and the line before which its lifetime ends (none when the block ends in
/// `unreachable`). One pass over `lines`, each line read once.
fn confined<'a>(
    slots: &[&'a str],
    tainted: &HashSet<&str>,
    owner: &HashMap<&str, &'a str>,
    lines: &[&str],
) -> Vec<(&'a str, usize, Option<usize>)> {
    let mut state: HashMap<&str, Slot> = HashMap::new();
    let mut block = 0usize;
    for (i, line) in lines.iter().enumerate() {
        if is_label(line) {
            block += 1;
            continue;
        }
        let mut uses: Vec<(&str, &str)> = Vec::new();
        for n in names(line) {
            if let Some(slot) = owner.get(n).copied().filter(|s| !tainted.contains(s)) {
                uses.push((slot, n));
            }
        }
        let derives = def(line).map(|(d, op)| (d, DERIVES.contains(&op)));
        let mut done: Vec<&str> = Vec::new();
        for &(slot, _) in &uses {
            if done.contains(&slot) {
                continue;
            }
            done.push(slot);
            let st = state.entry(slot).or_default();
            if st.dead {
                continue;
            }
            match st.first {
                None => st.first = Some((i, block)),
                Some((_, b)) if b != block => {
                    st.dead = true;
                    continue;
                }
                Some(_) => {}
            }
            let mine = |n: &str| owner.get(n).copied() == Some(slot);
            if derives.is_some_and(|(d, is)| is && mine(d)) {
                continue;
            }
            let verdicts: Vec<Use> = uses
                .iter()
                .filter(|(s, _)| *s == slot)
                .map(|(_, n)| classify(line, n))
                .collect();
            if verdicts.contains(&Use::Escape) {
                st.dead = true;
            } else if verdicts.contains(&Use::Read) && !st.written {
                // The first access sees whatever the slot held on the previous iteration.
                st.dead = true;
            } else {
                st.written |= verdicts.contains(&Use::Write);
            }
        }
    }
    // The last line of each block is its terminator.
    let mut last = vec![0usize; lines.len()];
    for i in (0..lines.len()).rev() {
        last[i] = if i + 1 < lines.len() && !is_label(lines[i + 1]) {
            last[i + 1]
        } else {
            i
        };
    }
    slots
        .iter()
        .filter_map(|slot| {
            let st = state.get(slot)?;
            let (start, _) = st.first.filter(|_| !st.dead)?;
            let end = last[start];
            let unreachable = lines[end].trim_start().starts_with("unreachable");
            Some((*slot, start, (!unreachable).then_some(end)))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const ALLOCAS: &str = "  %v1 = alloca [16 x i8], align 8\n  %v2 = alloca [16 x i8], align 8\n";

    #[test]
    fn a_temporary_confined_to_a_block_gets_markers() {
        let body = "  %v3 = getelementptr inbounds i8, ptr %v1, i64 8, !dbg !4\n  store i64 1, ptr %v3, align 8, !dbg !4\n  call void @f(ptr %v1), !dbg !4\n  ret void, !dbg !4\n";
        let out = mark(ALLOCAS, body);
        let start = out.find("lifetime.start.p0(ptr %v1), !dbg !4").expect(&out);
        let gep = out.find("%v3 = getelementptr").unwrap();
        let end = out.find("lifetime.end.p0(ptr %v1), !dbg !4").expect(&out);
        let ret = out.find("ret void").unwrap();
        assert!(start < gep && gep < end && end < ret, "{out}");
        assert!(
            !out.contains("(ptr %v2)"),
            "an unused slot has no marker: {out}"
        );
    }

    #[test]
    fn a_slot_used_in_two_blocks_keeps_no_marker() {
        let body = "  store i64 1, ptr %v1, align 8\n  br label %b1\nb1:\n  %v3 = load i64, ptr %v1, align 8\n  ret void\n";
        assert!(!mark(ALLOCAS, body).contains("lifetime"));
    }

    #[test]
    fn a_slot_read_first_or_with_an_escaping_address_keeps_no_marker() {
        let read = "  %v3 = load i64, ptr %v1, align 8\n  ret void\n";
        assert!(!mark(ALLOCAS, read).contains("lifetime"));
        let readonly = "  call void @f(ptr readonly %v1)\n  ret void\n";
        assert!(!mark(ALLOCAS, readonly).contains("lifetime"));
        let escape = "  store ptr %v1, ptr %v2, align 8\n  ret void\n";
        assert!(!mark(ALLOCAS, escape).contains("(ptr %v1)"));
        let phi = "  br label %b1\nb1:\n  %v3 = phi ptr [ %v1, %b0 ]\n  ret void\n";
        assert!(!mark(ALLOCAS, phi).contains("lifetime"));
    }

    #[test]
    fn a_slot_the_runtime_keeps_a_pointer_to_gets_no_marker() {
        let body = "  store i64 1, ptr %v1, align 8\n  %v3 = ptrtoint ptr %v1 to i64\n  %v4 = call i64 @\"msrt_cleanup_push\"(i64 7, i64 %v3)\n  ret void\n";
        assert!(!mark(ALLOCAS, body).contains("(ptr %v1)"));
    }

    #[test]
    fn an_integer_address_reaching_another_block_blocks_the_marker() {
        let body = "  %v3 = ptrtoint ptr %v1 to i64\n  store i64 1, ptr %v1, align 8\n  br label %b1\nb1:\n  call void @f(i64 %v3)\n  ret void\n";
        assert!(!mark(ALLOCAS, body).contains("lifetime"));
    }

    #[test]
    fn a_block_ending_in_unreachable_has_no_end_marker() {
        let body = "  call void @f(ptr %v1)\n  unreachable\n";
        let out = mark(ALLOCAS, body);
        assert!(
            out.contains("lifetime.start") && !out.contains("lifetime.end"),
            "{out}"
        );
    }
}

//! The state-machine prototype on a websocket-echo-shaped loop: the converted function must
//! print what the original prints, pass the verifier, and cancel from every state.

use ms_mir::interp::{Interp, Val};
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::state_machine::convert;
use ms_mir::verify::verify_module;
use std::cell::RefCell;
use std::rc::Rc;

// recv/send are the waits. `tag` is owned and lives across both waits; `n` counts echoes.
const ECHO: &str = r#"module "ws"
entry @main
extern @recv(int) -> str fresh
extern @send(int, move str) -> void
fn @echo(%sock: int, %tag: move str) -> int {
b0:
  %z: int = iconst 0
  br loop(%z)
loop(%n: int):
  %m: str = call.rt @recv (%sock)
  %len: int = str.len %m
  %zero: int = iconst 0
  %c: bool = icmp.eq %len, %zero
  br_if %c, closed(%m), echo(%m)
echo(%e: move str):
  %w: void = call.rt @send (%sock, %e)
  %one: int = iconst 1
  %n2: int = iadd %n, %one
  br loop(%n2)
closed(%x: move str):
  drop %x
  drop %tag
  ret %n
}
fn @main() -> int {
b0:
  %z: int = iconst 0
  ret %z
}
"#;

type Log = Rc<RefCell<Vec<String>>>;

fn host(it: &mut Interp, log: &Log, inbox: Vec<&'static str>, split: bool) {
    let inbox = Rc::new(RefCell::new(inbox.into_iter().rev().collect::<Vec<_>>()));
    let l = log.clone();
    let ib = inbox.clone();
    let recv = move |_: &mut String, _: &[Val]| -> Result<Val, String> {
        Ok(Val::str(ib.borrow_mut().pop().unwrap_or("")))
    };
    let l2 = l.clone();
    let send = move |_: &mut String, a: &[Val]| -> Result<Val, String> {
        if let Val::Str(s) = &a[1] {
            l2.borrow_mut().push(format!("send {s}"));
        }
        Ok(Val::Void)
    };
    if !split {
        it.register("recv", recv.clone());
        it.register("send", send.clone());
    }
    // The split natives: `begin` starts the wait and hands back a ticket, `result` reads it.
    let pending: Rc<RefCell<Vec<Val>>> = Rc::new(RefCell::new(Vec::new()));
    let (p1, p2) = (pending.clone(), pending.clone());
    let r1 = recv.clone();
    it.register("recv_begin", move |o, a| {
        let v = r1(o, a)?;
        p1.borrow_mut().push(v);
        Ok(Val::Int(p1.borrow().len() as i64 - 1))
    });
    it.register("recv_result", move |_, a| {
        let Val::Int(t) = a[0] else {
            return Err("ticket".into());
        };
        Ok(p2.borrow()[t as usize].clone())
    });
    let s1 = send.clone();
    it.register("send_begin", move |o, a| {
        s1(o, a)?;
        Ok(Val::Int(0))
    });
    it.register("send_result", |_, _| Ok(Val::Void));
}

fn run_original(src: &str, inbox: Vec<&'static str>) -> (i64, Vec<String>) {
    let m = parse_module(src).unwrap();
    verify_module(&m).unwrap();
    let log: Log = Default::default();
    let mut it = Interp::new(&m);
    host(&mut it, &log, inbox, false);
    let f = m.func_by_name("echo").unwrap();
    let r = it.call(f, vec![Val::Int(7), Val::str("tag")]).unwrap();
    (r.as_int().unwrap(), log.take())
}

fn converted() -> (ms_mir::ir::Module, ms_mir::state_machine::Machine) {
    converted_from(ECHO)
}

fn converted_from(src: &str) -> (ms_mir::ir::Module, ms_mir::state_machine::Machine) {
    let mut m = parse_module(src).unwrap();
    let f = m.func_by_name("echo").unwrap();
    let mach = convert(&mut m, f, &["recv", "send"]).unwrap_or_else(|e| panic!("{e}"));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    (m, mach)
}

fn state_of(_it: &mut Interp, fr: &Val) -> i64 {
    let Val::Type(f) = fr else { panic!("frame") };
    f[0].as_int().unwrap()
}

#[test]
fn matches_the_original() {
    let inbox = vec!["a", "bb", "ccc"];
    let (want, want_log) = run_original(ECHO, inbox.clone());
    let (m, mach) = converted();
    let log: Log = Default::default();
    let mut it = Interp::new(&m);
    host(&mut it, &log, inbox, true);
    let mut fr = it
        .call(mach.start, vec![Val::Int(7), Val::str("tag")])
        .unwrap();
    let mut steps = 0;
    while state_of(&mut it, &fr) != mach.done {
        fr = it.call(mach.step, vec![fr]).unwrap();
        steps += 1;
        assert!(steps < 100);
    }
    let Val::Type(f) = &fr else { unreachable!() };
    assert_eq!(f[2].as_int(), Some(want));
    assert_eq!(log.take(), want_log);
    assert_eq!(want, 3);
    // 4 receives, 3 sends, the entry step and the final one: every step ends at a wait or the end.
    assert_eq!(steps, 8);
}

#[test]
fn cancels_from_every_state() {
    let (m, mach) = converted();
    for stop in 0..4 {
        let log: Log = Default::default();
        let mut it = Interp::new(&m);
        host(&mut it, &log, vec!["a", "b", "c"], true);
        let mut fr = it
            .call(mach.start, vec![Val::Int(7), Val::str("tag")])
            .unwrap();
        for _ in 0..stop {
            fr = it.call(mach.step, vec![fr]).unwrap();
        }
        let before = it.drops();
        it.call(mach.cancel, vec![fr]).unwrap();
        // The tag is the only owned value saved: the message in flight went into the wait.
        assert!(
            it.drops() > before,
            "state after {stop} steps freed nothing"
        );
    }
}

#[test]
fn reports_the_frame_size() {
    let (_, mach) = converted();
    eprintln!(
        "frame fields: {} shared, {} unshared; saved per wait (values, owned): {:?}",
        mach.fields, mach.fields_unshared, mach.saved
    );
}

#[test]
#[ignore = "prints the converted module"]
fn print_converted() {
    let (m, _) = converted();
    eprintln!("{}", print_module(&m));
}

// The same loop with the branch order swapped, so the exit block is queued after the body.
const ECHO_SWAPPED: &str = r#"module "ws"
entry @main
extern @recv(int) -> str fresh
extern @send(int, move str) -> void
fn @echo(%sock: int, %tag: move str) -> int {
b0:
  %z: int = iconst 0
  br loop(%z)
loop(%n: int):
  %m: str = call.rt @recv (%sock)
  %len: int = str.len %m
  %zero: int = iconst 0
  %c: bool = icmp.ne %len, %zero
  br_if %c, echo(%m), closed(%m)
echo(%e: move str):
  %w: void = call.rt @send (%sock, %e)
  %one: int = iconst 1
  %n2: int = iadd %n, %one
  br loop(%n2)
closed(%x: move str):
  drop %x
  drop %tag
  ret %n
}
fn @main() -> int {
b0:
  %z: int = iconst 0
  ret %z
}
"#;

#[test]
fn loop_result_does_not_depend_on_block_order() {
    let inbox = vec!["a", "bb", "ccc", "dddd"];
    let (want, want_log) = run_original(ECHO_SWAPPED, inbox.clone());
    let (m, mach) = converted_from(ECHO_SWAPPED);
    let log: Log = Default::default();
    let mut it = Interp::new(&m);
    host(&mut it, &log, inbox, true);
    let mut fr = it
        .call(mach.start, vec![Val::Int(7), Val::str("tag")])
        .unwrap();
    while state_of(&mut it, &fr) != mach.done {
        fr = it.call(mach.step, vec![fr]).unwrap();
    }
    let Val::Type(f) = &fr else { unreachable!() };
    assert_eq!(f[2].as_int(), Some(want));
    assert_eq!(want, 4);
    assert_eq!(log.take(), want_log);
}

fn refused(body: &str) -> String {
    let src = format!(
        "module \"t\"\nentry @main\nextern @recv(int) -> str fresh\nextern @send(int, move str) -> void\n{body}\nfn @main() -> int {{\nb0:\n  %z: int = iconst 0\n  ret %z\n}}\n"
    );
    let mut m = parse_module(&src).unwrap();
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    let f = m.func_by_name("w").unwrap();
    convert(&mut m, f, &["recv", "send"]).expect_err("must refuse")
}

#[test]
fn refuses_what_it_cannot_convert_soundly() {
    let slot = "fn @w(%s: int) -> int {\nb0:\n  %p: ptr = slot int\n  %m: str = call.rt @recv (%s)\n  drop %m\n  ret %s\n}";
    assert!(refused(slot).contains("slots"));
    let depth = "fn @w(%s: int) -> int {\nb0:\n  depth.enter\n  %m: str = call.rt @recv (%s)\n  drop %m\n  depth.leave\n  ret %s\n}";
    assert!(refused(depth).contains("depth"));
    let hole = "type P { a: str, b: str }\nfn @w(%s: int) -> int {\nb0:\n  %x0: str = str \"x\"\n  %x: str = clone %x0\n  %y0: str = str \"y\"\n  %y: str = clone %y0\n  %p: P = type.new P %x, %y\n  %f: str = type.get P.a %p\n  %o: str = move.out %f\n  %m: str = call.rt @recv (%s)\n  drop %m\n  drop %o\n  type.release P.a %p\n  ret %s\n}";
    assert!(refused(hole).contains("holes"));
}

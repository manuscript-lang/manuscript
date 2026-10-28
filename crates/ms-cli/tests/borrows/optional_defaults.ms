import stdout from "@std/io.ms"
import TextError from "@std/core.ms"

fn fallback(var calls: Int) Optional[List[Int]]:
    calls += 1
    return some([99])

fn choose[T](value: Optional[List[T]], default: Optional[List[T]]) List[T]:
    return value.get(default).clone()

export fn main() Int:
    let missing: Optional[List[Int]] = none
    let present = some([1])
    let failure: Result[List[Int], TextError] = error(TextError("bad"))
    let success: Result[List[Int], TextError] = ok([2])
    let values = [[3]]
    let borrowed = some([88])
    let _ = stdout().write("{missing.get(some([99]))} {present.get(some([99]))}\n")
    let _ = stdout().write("{failure.get(some([99]))} {success.get(some([99]))}\n")
    let _ = stdout().write(
        "{values.get(9, some([99]))} {values.get(0, some([99]))} {values.get(-1, some([99]))}\n"
    )
    let _ = stdout().write(
        "{missing.get(borrowed)} {failure.get(borrowed)} {values.get(9, borrowed)} {borrowed}\n"
    )
    let no_int: Optional[Int] = none
    let yes_int = some(7)
    let bad = no_int.ok_or(some(TextError("missing")))
    let good = yes_int.ok_or(some(TextError("unused")))
    let _ = stdout().write("{bad.err().message()} {good.get()}\n")
    let _ = stdout().write(
        "{present.get(none)} {success.get(none)} {values.get(0, none)}\n"
    )
    var calls = 0
    let _ = stdout().write(
        "{present.get(fallback(var calls))} {missing.get(fallback(var calls))} {success.get(fallback(var calls))} {failure.get(fallback(var calls))} {values.get(0, fallback(var calls))} {values.get(9, fallback(var calls))} {calls}\n"
    )
    let no_text: Optional[String] = none
    let text = some("fallback")
    let text_failure: Result[String, TextError] = error(TextError("bad"))
    let words = ["present"]
    let _ = stdout().write(
        "{no_text.get(text)} {text_failure.get(text)} {words.get(5, text)} {text}\n"
    )
    let _ = stdout().write("{choose(none, some([4]))} {choose(some([5]), some([6]))}\n")
    return 0

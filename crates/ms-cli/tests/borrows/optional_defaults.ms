import stdout from "@std/io/io.ms"
import TextError from "@std/core.ms"

fn fallback(var calls: Int) List[Int]?:
    calls += 1
    return [99]

fn choose[T](value: List[T]?, default: List[T]?) List[T]:
    return value.get(default).clone()

export fn main() Int:
    let missing: List[Int]? = none
    let present: List[Int]? = [1]
    let failure: Result[List[Int], TextError] = error(TextError("bad"))
    let success: Result[List[Int], TextError] = ok([2])
    let values = [[3]]
    let borrowed: List[Int]? = [88]
    let _ = stdout().write("{missing.get([99])} {present.get([99])}\n")
    let _ = stdout().write("{failure.get([99])} {success.get([99])}\n")
    let _ = stdout().write(
        "{values.get(9, [99])} {values.get(0, [99])} {values.get(-1, [99])}\n"
    )
    let _ = stdout().write(
        "{missing.get(borrowed)} {failure.get(borrowed)} {values.get(9, borrowed)} {borrowed}\n"
    )
    let no_int: Int? = none
    let yes_int: Int? = 7
    let bad = no_int.ok_or(TextError("missing"))
    let good = yes_int.ok_or(TextError("unused"))
    let _ = stdout().write("{bad.err().message()} {good.get()}\n")
    let _ = stdout().write(
        "{present.get(none)} {success.get(none)} {values.get(0, none)}\n"
    )
    var calls = 0
    let _ = stdout().write(
        "{present.get(fallback(var calls))} {missing.get(fallback(var calls))} {success.get(fallback(var calls))} {failure.get(fallback(var calls))} {values.get(0, fallback(var calls))} {values.get(9, fallback(var calls))} {calls}\n"
    )
    let no_text: String? = none
    let text: String? = "fallback"
    let text_failure: Result[String, TextError] = error(TextError("bad"))
    let words = ["present"]
    let _ = stdout().write(
        "{no_text.get(text)} {text_failure.get(text)} {words.get(5, text)} {text}\n"
    )
    let _ = stdout().write("{choose(none, [4])} {choose([5], [6])}\n")
    return 0

from "@std/io.ms" import stdout
from "@std/core.ms" import TextError

def fallback(var calls: Int) -> Optional[List[Int]]:
    calls += 1
    return some([99])

def choose[T](value: Optional[List[T]], default: Optional[List[T]]) -> List[T]:
    return value.get(default).clone()

export def main() -> Int:
    let missing: Optional[List[Int]] = none
    let present = some([1])
    let failure: Result[List[Int], TextError] = error(TextError("bad"))
    let success: Result[List[Int], TextError] = ok([2])
    let values = [[3]]
    let borrowed = some([88])
    stdout().write(f"{missing.get(some([99]))} {present.get(some([99]))}\n")
    stdout().write(f"{failure.get(some([99]))} {success.get(some([99]))}\n")
    stdout().write(
        f"{values.get(9, some([99]))} {values.get(0, some([99]))} {values.get(-1, some([99]))}\n"
    )
    stdout().write(
        f"{missing.get(borrowed)} {failure.get(borrowed)} {values.get(9, borrowed)} {borrowed}\n"
    )

    let no_int: Optional[Int] = none
    let yes_int = some(7)
    let bad = no_int.ok_or(some(TextError("missing")))
    let good = yes_int.ok_or(some(TextError("unused")))
    stdout().write(f"{bad.err().message()} {good.get()}\n")
    stdout().write(f"{present.get(none)} {success.get(none)} {values.get(0, none)}\n")

    var calls = 0
    stdout().write(
        f"{present.get(fallback(var calls))} {missing.get(fallback(var calls))} {success.get(fallback(var calls))} {failure.get(fallback(var calls))} {values.get(0, fallback(var calls))} {values.get(9, fallback(var calls))} {calls}\n"
    )

    let no_text: Optional[String] = none
    let text = some("fallback")
    let text_failure: Result[String, TextError] = error(TextError("bad"))
    let words = ["present"]
    stdout().write(
        f"{no_text.get(text)} {text_failure.get(text)} {words.get(5, text)} {text}\n"
    )
    stdout().write(f"{choose(none, some([4]))} {choose(some([5]), some([6]))}\n")
    return 0

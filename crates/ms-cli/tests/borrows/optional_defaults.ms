import stdout from "@std/io/io.ms"

fn fallback(var calls: Int) List[Int]?:
    calls += 1
    return [99]

fn choose[T: Clonable](value: List[T]?, default: List[T]?) List[T]:
    return value.get(default).clone()

fn main() Unit:
    missing: List[Int]? := none
    present: List[Int]? := [1]
    failure: Result[List[Int], Error] := error(Error("bad"))
    success: Result[List[Int], Error] := ok([2])
    values := [[3]]
    borrowed: List[Int]? := [88]
    _ := stdout().write("{missing.get([99])} {present.get([99])}\n")
    _ := stdout().write("{failure.get([99])} {success.get([99])}\n")
    _ := stdout().write(
        "{values.get(9, [99])} {values.get(0, [99])} {values.get(-1, [99])}\n"
    )
    _ := stdout().write(
        "{missing.get(borrowed)} {failure.get(borrowed)} {values.get(9, borrowed)} {borrowed}\n"
    )
    no_int: Int? := none
    yes_int: Int? := 7
    bad := no_int.ok_or(Error("missing"))
    good := yes_int.ok_or(Error("unused"))
    _ := stdout().write("{bad.err().message} {good.get()}\n")
    _ := stdout().write(
        "{present.get(none)} {success.get(none)} {values.get(0, none)}\n"
    )
    var calls = 0
    _ := stdout().write(
        "{present.get(fallback(var calls))} {missing.get(fallback(var calls))} {success.get(fallback(var calls))} {failure.get(fallback(var calls))} {values.get(0, fallback(var calls))} {values.get(9, fallback(var calls))} {calls}\n"
    )
    no_text: String? := none
    text: String? := "fallback"
    text_failure: Result[String, Error] := error(Error("bad"))
    words := ["present"]
    _ := stdout().write(
        "{no_text.get(text)} {text_failure.get(text)} {words.get(5, text)} {text}\n"
    )
    _ := stdout().write("{choose(none, [4])} {choose([5], [6])}\n")

import stdout from "@std/io/io.ms"

fn fallback(var calls: Int) List[Int]?:
    calls += 1
    return [99]

fn choose[T: Clonable](value: List[T]?, default: List[T]?) List[T]:
    return value.get_or(default).clone()

fn main() Void:
    missing: List[Int]? := none
    present: List[Int]? := [1]
    failure: Result[List[Int], Error] := error(Error("bad"))
    success: Result[List[Int], Error] := ok([2])
    values := [[3]]
    borrowed: List[Int]? := [88]
    void stdout().write(f"{missing.get_or([99])} {present.get_or([99])}\n")
    void stdout().write(f"{failure.get_or([99])} {success.get_or([99])}\n")
    void stdout().write(
        f"{values.get_or(9, [99])} {values.get_or(0, [99])} {values.get_or(-1, [99])}\n"
    )
    void stdout().write(
        f"{missing.get_or(borrowed)} {failure.get_or(borrowed)} {values.get_or(9, borrowed)} {borrowed}\n"
    )
    no_int: Int? := none
    yes_int: Int? := 7
    bad := no_int.ok_or(Error("missing"))
    good := yes_int.ok_or(Error("unused"))
    void stdout().write(f"{bad.err().message} {good.get()}\n")
    void stdout().write(
        f"{present.get_or(none)} {success.get_or(none)} {values.get_or(0, none)}\n"
    )
    var calls = 0
    void stdout().write(
        f"{present.get_or(fallback(calls))} {missing.get_or(fallback(calls))} {success.get_or(fallback(calls))} {failure.get_or(fallback(calls))} {values.get_or(0, fallback(calls))} {values.get_or(9, fallback(calls))} {calls}\n"
    )
    no_text: String? := none
    text: String? := "fallback"
    text_failure: Result[String, Error] := error(Error("bad"))
    words := ["present"]
    void stdout().write(
        f"{no_text.get_or(text)} {text_failure.get_or(text)} {words.get_or(5, text)} {text}\n"
    )
    void stdout().write(f"{choose(none, [4])} {choose([5], [6])}\n")

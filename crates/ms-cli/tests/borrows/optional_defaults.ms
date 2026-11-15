import stdout from "@std/io/io.ms"

fn fallback(var calls: Int) List[Int]?:
    calls += 1
    return [99]

fn choose[T: Clonable](value: List[T]?, default: List[T]?) List[T]:
    return value.get(default).clone()

fn main() Void:
    missing: List[Int]? := none
    present: List[Int]? := [1]
    failure: Result[List[Int], Error] := error(Error("bad"))
    success: Result[List[Int], Error] := ok([2])
    values := [[3]]
    borrowed: List[Int]? := [88]
    void stdout().write(f"{missing.get([99])} {present.get([99])}\n")
    void stdout().write(f"{failure.get([99])} {success.get([99])}\n")
    void stdout().write(
        f"{values.get(9, [99])} {values.get(0, [99])} {values.get(-1, [99])}\n"
    )
    void stdout().write(
        f"{missing.get(borrowed)} {failure.get(borrowed)} {values.get(9, borrowed)} {borrowed}\n"
    )
    no_int: Int? := none
    yes_int: Int? := 7
    bad := no_int.ok_or(Error("missing"))
    good := yes_int.ok_or(Error("unused"))
    void stdout().write(f"{bad.err().message} {good.get()}\n")
    void stdout().write(
        f"{present.get(none)} {success.get(none)} {values.get(0, none)}\n"
    )
    var calls = 0
    void stdout().write(
        f"{present.get(fallback(var calls))} {missing.get(fallback(var calls))} {success.get(fallback(var calls))} {failure.get(fallback(var calls))} {values.get(0, fallback(var calls))} {values.get(9, fallback(var calls))} {calls}\n"
    )
    no_text: String? := none
    text: String? := "fallback"
    text_failure: Result[String, Error] := error(Error("bad"))
    words := ["present"]
    void stdout().write(
        f"{no_text.get(text)} {text_failure.get(text)} {words.get(5, text)} {text}\n"
    )
    void stdout().write(f"{choose(none, [4])} {choose([5], [6])}\n")

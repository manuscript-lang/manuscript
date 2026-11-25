# Collections and pipelines

Prelude constructors: `[1, 2]`, `{"a": 1}`, `List[Int](reserve: 8)`, `Map[String, Int]()`, `Set[Int]()`. An empty `[]` or `{}` is an error unless the context gives its type (`xs List[Int] := []`, an argument, a return, a field). Mutation requires var; a List is read with `xs[i]`.

<!-- complete: collections.ms -->
```manuscript
fn main() Int {
    values := [1, 2, 3, 4]
    total := (
        values
        | .filter(x => x > 2)
        | .map(x => x * 2)
        | .sum()
    )
    var counts = Map[String, Int]()
    counts["total"] = total
    if var n = counts["total"]? {
        n += 1
    }
    if counts.get_or("total", 0) == 15 and values.length() == 4 { return 0 }

    return 1
}
```

`values.length()` counts a List, Map, Set or String; always call it with parentheses. Map `.get(key)` returns Optional; `.get_or(key, default)` supplies a fallback. Iterate `.entries()` and read `.key`/`.value`. List `.slice(start, end)` returns a borrowed Result (an error when `end` is past the length); `xs[i]` reads an element (negative counts from the end, out of range faults) and `.get_or(index, default)` supplies a fallback. `.take(n)` and `.drop(n)` clamp. `m.keys()`, `m.values()`, `m.get(k)`, `xs.first()`, `xs.last()`, `s.split(sep)` and `s.chars()` borrow their receiver: use them in place or `.clone()` to keep them, and do not change the receiver while one is in use.

`x | f(a: 1)` passes x first; `x | .m()` calls a method; `x | f?` propagates f's Result. Thus `x | f(a: 1) | g? | .m()` means `(g(f(x, a: 1))?).m()`.

List `.filter/.map/.sum` are methods; similarly named stream steps are imported functions. Prefer these operations to bookkeeping loops.

`String.length()` counts UTF-8 bytes (`"é"` is 2); `scalar_length()` counts characters and `display_width()` (a Result) counts terminal columns, so pad and underline with those. `String.slice(a, b)` returns a String (no Result); `List.slice(a, b)` returns a Result. Read a file's text with `ok_or(read_file(path).wait()?.decode_utf8(), Error("not UTF-8"))?`: `read_file` returns a Promise of Bytes, and there is no `read_text`.

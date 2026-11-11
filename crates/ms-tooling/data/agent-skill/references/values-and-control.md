# Values and control

`x := value` binds an immutable value; `x: Int := value` adds a type. `var x = value` permits assignment and mutation. Immutable collections cannot have their contents changed. Prefix intentionally unused names with `_`.

Core types are `Int`, `Float`, `Bool`, `String` and `Unit`. `true` and `false` are Bool literals; `unit` is the Unit value. Numeric conversions are explicit. Strings interpolate with `"hello {name}"`; escape literal braces with `\{` and `\}`. Raw text such as `r"\d+"` treats backslashes literally; it does not make a backslash escape a closing quote.

Save as `control.ms`:

<!-- complete: control.ms -->
```manuscript
fn main() Int:
    var total = 0
    for n in 0..5:
        if n == 2: continue
        total += n
    while total < 10:
        total += 1
    label := if total == 10: "ready" else: "wrong"
    if label == "ready" and not (total < 10):
        return 0
    return 1
```

`ms run control.ms` prints nothing and exits 0.

- `0..n` excludes n. Use `break` to leave a loop and `continue` for its next iteration.
- Boolean operators are `and`, `or`, `not`. Branches use `if`, `else if`, `else`.

A one-line `if condition: return value` is a terse early exit. Statement `else` aligns with its `if` on a new line; an expression can use `if condition: left else: right` on one line. `+=`, `-=`, and similar assignments require a mutable target.

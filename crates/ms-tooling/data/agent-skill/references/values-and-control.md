# Values and control

Immutable: `x := value`, or `x: Int := value`. Mutable: `var x = value`; assignments require var. Prefix deliberately unused names with `_`.

Types: Int, Float, Bool, String, Unit. Literals: `true`, `false`, `unit`. Numeric conversions are explicit. `"hello {name}"` interpolates; `\{`/`\}` escape braces. Raw `r"\d+"` keeps backslashes literal, including before a quote.

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

`ms run control.ms` exits 0, without output.

`0..n` excludes n. `break` exits a loop; `continue` advances it. Boolean operators: `and`, `or`, `not`.

Statements use `if`/`else if`/`else`; align else with if. Inline `if c: return x` exits early. Expressions use `if c: a else: b`. `+=`, `-=` and other assignments require mutable targets.

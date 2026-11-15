# Values and control

Immutable: `x := value`, or `x: Int := value`. Mutable: `var x = value`; assignments require var. Name a deliberately unused binding with a leading `_`, such as `_i`; a bare `_` is not a name, so `for _ in xs` fails.

Types: Int, Float, Bool, String, Void. Literals: `true`, `false`, `void`. Numeric conversions are explicit. `"hello {name}"` interpolates. Text with literal braces and nothing to interpolate is raw: `r"{"`, `r"\d+"` (no escapes, no interpolation); use `r"""` on its own lines for JSON with quotes. `\{`/`\}` escape braces only in text that also interpolates.

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

`0..n` excludes n. `break` exits a loop; `continue` advances it. Boolean operators: `and`, `or`, `not`.

Statements use `if`/`else if`/`else`; align else with if. Inline `if c: return x` exits early. Expressions use `if c: a else: b`. `+=`, `-=` and other assignments require mutable targets.

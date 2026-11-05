+++
title = "Understanding effects"
weight = 3
+++

# Understanding effects

Use an effects view when reviewing how code reads or changes data and reaches external operations. It follows calls so you can see how a small helper reaches behavior outside the program.

Save this as `hello.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n","filename":"hello.ms"} -->
```manuscript
export fn main() Int:
    print("Hello, Manuscript!")
    return 0
```

`ms run hello.ms` prints `Hello, Manuscript!`. To inspect its calls without running it:

```sh
ms diagram hello.ms --view effects --entity main
```

```text
EFFECTS VIEW
`- main  effects: read+unknown
   `- @std/core.ms+source#fn#print
```

The summary includes behavior reachable through `print`, not just statements written directly in `main`. `unknown` means the analysis cannot classify every operation along that path; it does not mean that the call is harmless. Use the call path to find the implementation you need to review. For a larger program, open an [interactive code map](../implementation.md#interactive-code-map) or use the [review report](../implementation.md#review-report) to find newly introduced effects.

## Transitive analysis

Effects combine along calls. The vocabulary is `read`, `write` and `unknown`. Reads and writes can concern program data as well as I/O; many native operations contribute `unknown`.

| Call target | How it contributes to the summary |
| --- | --- |
| Known source target | Include its effects, including the effects of its callees. |
| Several known targets | Include the union of their effects. |
| Unresolved function value or contract call | Include `unknown`; do not treat it as having no effects. |

Summaries describe reachable behavior; no syntax promises purity or restricts effects.

## Effects and cancellation

Cancellation cannot undo a completed external write. When retrying, review both returned errors and external effects.

# Program structure

A file is a module. Put imports first, followed by module-level types, functions and methods. An executable entry file declares `fn main()` with no parameters; `export` is optional on main.

Use four spaces per nested level. A trailing `:` introduces an indented body; dedent ends it. Fields go inside `type`; receiver methods sit beside the type, not inside it. `self` is implicit, not a declared parameter. `fn var Type.method` may mutate self.

Save as `counter.ms`:

<!-- complete: counter.ms -->
```manuscript
type Counter:
    n: Int = 0

fn Counter.value() Int: self.n

fn var Counter.add(n: Int) Unit:
    self.n += n

fn main() Int:
    var counter = Counter()
    counter.add(42)
    return counter.value() - 42
```

`ms check counter.ms` succeeds; `ms run counter.ms` prints nothing and exits 0.

- An inline function body returns its expression. A multiline value-returning body uses `return`. `Unit` and `Unit!` functions may fall through.
- `main` returning `Int` sets the exit status. `Unit` succeeds with status 0. `Unit!` succeeds on `ok` and reports an error with status 1 on `error`.

## Files and visibility

`import name from "./other.ms"` imports an exported declaration; `export fn` and `export type` share it. Multiple imports use `import a, b from "./other.ms"`. Standard-library paths start with `@std/`. Names are case-sensitive. Imports do not put every declaration from that module in scope.

Record constructors accept positional or labeled arguments, such as `Counter(2)` or `Counter(n: 2)`; fields with defaults can be omitted. `export opaque` hides a type's fields or an enum's cases outside its file.

Function/type declarations have no required ordering relative to calls; module signatures are collected before bodies. Keep executable work in functions, with main coordinating the program.

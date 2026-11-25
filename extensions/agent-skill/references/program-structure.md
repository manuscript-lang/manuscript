# Program structure

A file is a module: imports, then types, functions and methods. `fn main()` takes no parameters; export is optional.

A body is a `{ ... }` block; `ms fmt` indents it with tabs. Fields belong inside `type`; receiver methods sit beside it. `self` is implicit. `fn var` mutates the receiver.

<!-- complete: counter.ms -->
```manuscript
type Counter {
    n Int = 0
}

fn Counter.value() Int => self.n

fn var Counter.add(n Int) Void {
    self.n += n
}

fn main() Int {
    var counter = Counter()
    counter.add(42)
    return counter.value() - 42
}
```

Inline functions return their expression; multiline value-returning functions use `return`. Void/Void! may fall through. Main returns Void (status 0), Int (exit status), or Void! (error prints and exits 1).

Import exported names with `import a, b from "./other.ms"`; standard paths start `@std/`. `export fn`/`export type` share declarations. Names are case-sensitive; signatures resolve before bodies.

Construct records positionally or by label: `Counter(2)`, `Counter(n: 2)`. Defaults permit omission. `export opaque` hides fields/cases outside the file.

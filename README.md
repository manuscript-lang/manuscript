<div align="center">

# Manuscript

**The language for the agentic era.**

[Get started](documentation/learn/getting-started.md) · [Why Manuscript](documentation/learn/why-manuscript.md) · [Guide](documentation/guide/_index.md) · [Performance](bench/perf/README.md) · [Agent benchmark](bench/agent/README.md) · [Vision](VISION.md)

<img src="website/static/images/screencast.gif" width="720" alt="A screencast of Manuscript: failure as values, ownership errors, promises, ms verify, the call graph and a native build, each with a short caption.">

</div>

I built Manuscript to make agent-generated code practical to work with. It's designed to be safe for agents to write: the common footguns are gone, and the syntax is token-efficient and readable at a glance. Built-in diagrams and an interactive code map let you explore what an agent built without reading it line by line.

Under the hood, the compiler enforces one owner per value with no GC. Programs run close to C speed and scale across all cores, and a simple effects system tracks what your code is allowed to do.

The whole toolchain is tuned for agents. Errors tell you how to fix them, and built-in commands let you verify, test, fuzz, benchmark and profile. I use agent benchmarks to evolve the language and toolchain together, and I probe the compiler and standard library adversarially to find and fix correctness and performance bugs.

```manuscript
fn handle(request: HttpRequest) HttpResponse:
    return HttpResponse(200, headers(), "hello {request.path}".to_bytes())

fn listen() Unit!:
    let server = try serve("127.0.0.1:0", buffered(handle))
    print("{server.address()}")
    try server.wait()
    return ok(unit)

export fn main() Int:
    if listen().is_ok(): return 0
    return 1
```

## Small enough to write and read

```manuscript
enum Item:
    Book(pages: Int)
    Coffee(grams: Int)

interface Priced:
    fn cents() Int

impl Priced for Item:
    fn cents() Int:
        match self:
            Book(pages): return 500 + pages * 2
            Coffee(grams): return grams * 3

fn sum_by[T](items: List[T], price: fn(T) Int) Int:
    var total = 0
    for item in items:
        total += price(item)
    return total

export fn main() Int:
    let cart = [Item.Book(pages: 200), Item.Coffee(grams: 250)]
    print("{sum_by(cart, fn item: item.cents())} cents")
    return 0
```

Functions, enums, interfaces and generics, spelled with plain words (`and`, `or`, `not`, `fn`, `var`, `none`) that cost few tokens. There is little to get wrong, and a program reads top to bottom.

## Errors that name the fix

```text
resolution: unknown binding len; there is no len() function: call the length member, e.g. xs.length()
parse: '&&' is not an operator; write 'and' for logical and
resolution: unknown binding null; Manuscript has no null: absence is an Optional, written none
```

Every diagnostic names the cause and the fix, and the compiler recognizes habits from other languages. `ms check --fix` applies the mechanical ones.

## Review without reading every line

```sh
ms diagram ms.toml --format html -o code-map.html
git diff main... | ms review ms.toml --diff -
```

The first command writes one offline file with source, types, calls and ownership side by side, and the declarations a change touched highlighted. The second ranks what deserves your attention first: changed contracts, error flow and resource scopes. See [working with an agent](documentation/guide/working-with-an-agent.md).

## Measure, then improve

```sh
ms test ms.toml --fuzz 30s
ms bench ms.toml
ms profile ms.toml
```

Property tests double as a fuzzer, benchmarks time each change, and the profiler shows where the time goes. An agent can run that loop on its own.

Everything here works today, and I harden it with each release. Syntax and APIs still evolve.

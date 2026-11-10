+++
title = "Organizing code"
weight = 7
+++

# Organizing code

Orders can hold books and subscriptions, and the total should add up either without caring which is which. An `interface` names the behavior you need, and a type opts in with an `impl`.

<!-- manuscript-example: {"mode":"run","stdout":"Cart: 6140 cents\nLargest: 9\n"} -->
```manuscript {filename="catalog.ms"}
interface Priced:
    fn cents() Int

type Book:
    title: String
    pages: Int

type Subscription:
    months: Int

impl Priced for Book:
    fn cents() Int:
        return 500 + self.pages * 2

impl Priced for Subscription:
    fn cents() Int:
        return self.months * 900

fn total(items: List[Priced]) Int:
    var sum = 0
    for item in items:
        sum += item.cents()
    return sum

fn largest[T: Clonable](items: List[T], score: fn(T) Int) T?:
    var best: T? = none
    var best_score = 0
    for item in items:
        value := score(item)
        if best.is_none() or value > best_score:
            best_score = value
            best = item.clone()
    return best

export fn main() Int:
    items: List[Priced] = [Book("Manuscript", 120), Subscription(6)]
    print("Cart: {total(items)} cents")
    top := largest([3, 9, 4], fn n: n)
    print("Largest: {top.get(0)}")
    return 0
```

```text
Cart: 6140 cents
Largest: 9
```

## What to notice

- `interface Priced` declares one method. `impl Priced for Book:` is where `Book` provides it. Methods never go inside the `type`.
- `total` takes a `List[Priced]` and works with any mix of types that implement the interface. It depends on behavior, not on a concrete type.
- `largest[T: Clonable]` is generic: it works for any `T` that meets its bound, and the compiler checks the bound at every call. `Clonable` is a bound that says "this type can be copied with `.clone()`". Without it the compiler refuses `item.clone()`, because a generic body cannot assume every type can be copied.
- There is no `any` and no cast. If you need to handle unknown JSON, use `JsonValue`.

## Files are modules

Each `.ms` file is a module and `export` marks what other files can import. Standard APIs come from `@std/...` and your own code from a relative path:

```manuscript
import line_total from "./pricing.ms"
```

Everything else stays private to its file. Keep modules small enough that their exports read like a short list.

**Next:** [Testing and shipping](testing-and-shipping.md). **Exact rules:** [Contracts and interfaces](../core-language/types/contracts.md), [Generics](../core-language/types/generics.md), [Modules](../core-language/modules/_index.md).

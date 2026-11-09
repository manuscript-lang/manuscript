+++
title = "Who owns what"
weight = 4
+++

# Who owns what

There is no garbage collector in Manuscript and no lifetime annotation to write. Instead every value has one owner, and the compiler tracks it. This chapter shows what that feels like with a cart of items.

<!-- manuscript-example: {"mode":"run","stdout":"Sam has 2 items\nSam has 3 items\nSam has 4 items; archived: 3\n"} -->
```manuscript {filename="cart.ms"}
type Cart:
    owner: String
    items: List[String]

fn summary(cart: Cart) String:
    return "{cart.owner} has {cart.items.length()} items"

fn add_gift(var cart: Cart) Unit:
    cart.items.append("gift card")

fn archive(cart: Cart, var history: List[Cart]) Unit:
    history.append(cart)

export fn main() Int:
    var cart = Cart("Sam", ["pen", "ink"])
    print(summary(cart))
    add_gift(var cart)
    print(summary(cart))

    var history = List[Cart]()
    archive(cart.clone(), var history)
    cart.items.append("notebook")
    print("{summary(cart)}; archived: {history[0].items.length()}")
    return 0
```

```text
Sam has 2 items
Sam has 3 items
Sam has 4 items; archived: 3
```

## What to notice

- `summary(cart)` only reads the cart. It borrows it, and `cart` is still yours afterwards.
- `add_gift(var cart)` may change the cart, so you write `var` at the call as well as at the declaration. Mutation is visible at both ends.
- `archive` stores the cart in `history`. Storing moves the value, so the call passes `cart.clone()` and keeps the original.
- `.clone()` is the only way to copy. Nothing copies a list, a type or a string behind your back, so scanning a change for `.clone()` and `var` shows you where data is duplicated or changed.

## What the compiler says

Leave out the `.clone()`:

```manuscript
    archive(cart, var history)
    print(cart.owner)
```

The compiler refuses, and its message says how to repair it:

```text
cart.ms:11:13: type: `cart` is moved here but used again at 12:11; a value has one owner, so move it only at its last use, or pass `cart.clone()` if the original is still needed
```

Two repairs fit: clone, as above, or move the value at its last use and stop using the old name.

## Why this is worth it

Memory is freed when the owner goes out of scope, so there is no collector pause and no reference counting on ordinary data. Numbers, booleans and enums without payloads copy freely, so loops and arithmetic never trip over ownership. The rule only bites on values that own heap data, which is where bugs hide in other languages.

**Next:** [Cleaning up](cleaning-up.md). **Exact rules:** [Mutation and references](../core-language/types/references.md).

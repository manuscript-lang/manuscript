+++
title = "Who owns what"
weight = 4
+++

# Who owns what

There is no garbage collector in Manuscript and no lifetime annotation to write. Instead every value has one owner, and the compiler tracks it. This chapter shows what that feels like with a cart of items.

<!-- manuscript-example: {"mode":"run","stdout":"Sam has 2 items\nSam has 3 items\nSam has 4 items; archived: 3\n"} -->
```manuscript {filename="cart.ms"}
type Cart {
    owner String
    items List[String]
}

fn summary(cart Cart) String {
    return f"{cart.owner} has {cart.items.length()} items"
}

fn add_gift(var cart Cart) Void {
    cart.items.append("gift card")
}

fn archive(move cart Cart, var history List[Cart]) Void {
    history.append(cart)
}

fn main() Void {
    var cart = Cart("Sam", ["pen", "ink"])
    print(summary(cart))
    add_gift(cart)
    print(summary(cart))

    var history = List[Cart]()
    archive(cart.clone(), history)
    cart.items.append("notebook")
    print(f"{summary(cart)}; archived: {history[0].items.length()}")
}
```

```text
Sam has 2 items
Sam has 3 items
Sam has 4 items; archived: 3
```

## What to notice

- `summary(cart)` only reads the cart. It borrows it, and `cart` is still yours afterwards.
- `add_gift(cart)` may change the cart, because `add_gift` declares the parameter `var`. The call needs no marker; the signature (and `ms` hover) shows which functions change their arguments, as with `move`.
- `archive` stores the cart in `history`. Storing moves the value, so the call passes `cart.clone()` and keeps the original.
- `.clone()` is the only way to copy. Nothing copies a list, a type or a string behind your back, so scanning a change for `.clone()` and `var` declarations shows you where data is duplicated or changed.

## What the compiler says

Leave out the `.clone()`:

<!-- manuscript-example: {"mode":"error","contains":"moved here but used again","context":"type Cart {\n    owner String\n    items List[String]\n}\n\nfn archive(move cart Cart, var history List[Cart]) Void {\n    history.append(cart)\n}","given":["cart Cart","var history List[Cart]"]} -->
```manuscript
    archive(cart, history)
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

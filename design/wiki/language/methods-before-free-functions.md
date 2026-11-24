[Wiki](../index.md) › [Language](index.md)

# Methods before free functions

Decision (Chinmay's preference): do not add "random" free functions to the standard library or examples; put the operation on the type it acts on. Free functions remain for operations with no natural receiver, and `|` flows compose them.


Apply when: naming new stdlib API or reviewing examples.
Verify: a new operation on a `String`, `List` or `Map` is a method, not a module function taking that value.

+++
title = "Control flow"
weight = 4
+++

# Control flow

Control flow chooses which work runs and how often. Use `if` for a Boolean decision, `match` to handle the distinct cases of a value, and loops to repeat work. Begin with bindings and Boolean expressions in [basics](../basics/_index.md); each construct then introduces a block with its own local names.

Choose branches for meaningful alternatives, and use early returns to keep the successful path easy to follow. Leaving a block runs its registered cleanup, whether the exit is ordinary, a return, or an error. See [scope-end cleanup](../cleanup/scopes.md) when those blocks own files or other resources.

| Concept | What you will learn |
| --- | --- |
| [Conditionals](conditionals.md) | Branch on Bool values with if and else. |
| [Loops](loops.md) | Iterate with for and while, and use break and continue. |
| [Pattern matching](pattern-matching.md) | Handle enums exhaustively and bind their payloads. |

[Wiki](../index.md) › [tooling-and-docs](index.md)

# Type parameters need scope and receiver positions

Verified: hover, definition, references and rename ignored type parameters, because the checker records a parameter as a type variable with no symbol. The index now keys each parameter by its declaring name and scopes uses by declaration.

Rules that cost time:
- Methods of one type merge into one impl block that keeps only the first receiver, so each `Method` keeps its own `receiver_args`.
- A receiver argument names the type's parameter and must match it (`fn Box[U].get` is an error), so it is a use of the type's parameter, not a new declaration.
- A type's synthesized interface repeats its parameters; skip synthetic interfaces or every parameter is declared twice.
- The checker appends a variable's bounds on every receiver resolution; dedupe them for display.
- `main` is found by name; refuse renaming it, since no graph edge names it.

Evidence: index, tests.

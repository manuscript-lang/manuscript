---
name: manuscript
description: Write, check, test, and revise idiomatic Manuscript programs. Use for .ms source, Manuscript APIs, ownership, errors, streams, and compiler diagnostics.
---

# Write Manuscript

Generated for Manuscript {{MS_VERSION}}. Compare with `ms --version`; regenerate this skill with the matching compiler when stale. Manuscript is in alpha: syntax and APIs may change.

## Start correctly

- Use four-space indentation. `:` opens a body; dedent ends it. No braces or semicolons for blocks.
- Prefer inferred immutable `name := value`. Use `var name = value` only for mutation.
- Write explicit parameter and return types on named functions. Use early returns, short pipelines, and small methods.
- Handle every Result: propagate with postfix `?` in a compatible Result-returning function, or handle success and failure. There are no exceptions or `async`/`await` keywords.
- Values have one owner. Reads can borrow; storage can move. Clone only when another independent owner is needed.

Save as `hello.ms`:

<!-- complete: hello.ms -->
```manuscript
// ms: allow_effect std.console.write
fn main() Unit:
    answer := 6 * 7
    print(answer)
```

Run `ms check hello.ms`, then `ms run hello.ms`. Output: `42`.

## Read the relevant concept before writing

These bundled references teach the syntax and operations directly; they are not links to another guide.

- [Program structure](references/program-structure.md): files, imports, indentation, entry point, types and methods.
- [Values and control](references/values-and-control.md): bindings, numbers, text, branches and loops.
- [Types and functions](references/types-and-functions.md): signatures, generics, closures, enums and interfaces.
- [Errors and optionals](references/errors-and-optionals.md): `T!`, `T?`, propagation and explicit handling.
- [Ownership and cleanup](references/ownership-and-cleanup.md): borrowing, moving, cloning, mutation and scope-end cleanup.
- [Collections and pipelines](references/collections-and-pipelines.md): lists, maps, sets and method versus function pipelines.
- [Effects and concurrency](references/effects-and-concurrency.md): effects, promises, streams and their imports.
- [Validation](references/validation.md): checking, tests, diagnostics and the edit/run loop.

## Before returning code

Run the applicable `ms check`, `ms run`, or `ms test` command. Verify actual output, not only acceptance by the checker. Keep all imports in complete examples; prelude names (`List`, `Map`, `Set`, `Optional`, `Result`, `Error`) and `print` need none. For APIs not covered here, `ms search_symbol <words>` returns declarations and import paths; do not guess signatures. Never claim a check passed if it was not run.

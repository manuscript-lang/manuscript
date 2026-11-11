# Validate before delivering

1. Save complete `.ms` files, including imports.
2. Run `ms check app.ms` to check syntax, types, ownership and effects.
3. Run `ms run app.ms`; compare output and exit status with the intended behavior.
4. Run `ms test` for the project's test blocks, and `ms verify` for project checks. `--deny-warnings` makes warnings fail validation.

Use `ms check app.ms --json` for structured diagnostics. Follow the reported location and concrete fix. `ms check app.ms --fix` applies machine-applicable fixes; always recheck afterward. `ms guide <code>` explains a diagnostic code. These are repair tools, not substitutes for checking whether the program does the right thing.

Tests use `test "name":` with an indented body; benches similarly use `bench "name":`. Keep tests deterministic and exercise failure branches, empty inputs and ownership-sensitive paths as well as success. For expected errors, inspect Results rather than expecting exceptions. Run the relevant command after the final edit, not only before it.

Save as `arithmetic.ms`:

<!-- complete-test: arithmetic.ms -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn twice(value: Int) Int: value * 2

test "twice":
    expect_equal(twice(21), 42)?
```

`ms test arithmetic.ms` reports one passing test. Assertions return Results; the trailing `?` makes a failed assertion fail the test.

Common habits to avoid:

- Bind immutable locals with `:=`, not an assignment to an undeclared name.
- Use `?` for Result propagation, not `try`, `await`, exceptions or unwrap-style calls.
- Do not write methods inside `type`; use `fn Type.method` and `fn var Type.method`.
- Do not use `case` declarations inside enums, Python `def`, or hidden GC assumptions.
- Match named-function return types to actual control flow; a multiline non-Unit function must return its value.

A check proves acceptance, not runtime correctness or performance. Report separately what compiled, what ran and what remains untested. Use `ms search_symbol` only for additional APIs beyond these references; inspect the returned signature and import path instead of inventing one.

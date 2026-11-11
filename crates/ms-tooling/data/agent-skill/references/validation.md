# Validation

After the final edit, run `ms check app.ms`, then `ms run app.ms` and verify behavior. `ms test` runs tests; `ms verify` checks projects. `--deny-warnings` rejects warnings.

`ms check app.ms --json` gives structured diagnostics. Apply indicated repairs; `--fix` applies machine fixes, then recheck. `ms explain <code>` explains diagnostics. Acceptance does not prove runtime behavior or speed.

<!-- complete-test: arithmetic.ms -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn twice(value: Int) Int: value * 2

test "twice":
	expect_equal(twice(21), 42)?
```

Assertions return Results; `?` fails the test on error. Tests need no main. `bench "name":` introduces benchmark bodies.

Test success, failure and boundary inputs. Never expect exceptions. Avoid undeclared assignment, `try`/`await`, unwrap-style calls, `def`, enum `case`, or methods inside type bodies. Use `:=`, postfix `?`, `fn Type.method` and explicit returns instead.

For additional APIs, inspect `ms search_symbol` signatures/imports. Report compiled, executed and untested checks separately.

# Fakes and limits on the effect seam

## Summary

- Problem: a test cannot control what code gets from the outside world (time, randomness, environment, files, network, a database client) without a parameter on every caller, and an agent's program cannot be held to less reach than the machine gives it.
- Change: both problems sit on one seam we already have, effects. `ms run --deny PATTERN` refuses to build a program that reaches a denied effect; `--allow PATTERN` permits only the listed effects, and scoped access (a path, a host, a table) is a packaged function that declares its own effect. `fake(original, replacement)` in a test replaces a function that declares an effect, until the test ends.
- Decision requested: approve both, and the rule that only functions declaring an effect can be faked.

## Status

Proposal, 2026-11-16. `--deny` and `--allow` are built on this branch; `fake` is not. Direction (Chinmay): simpler than passing capabilities; fit with effects; `vi.mock` ergonomics, checked when compiling; two uses, limiting agents and faking in tests; fake more than the standard library. Replaces an earlier module-swap design that keyed fakes on file paths.

## Why effects are the seam

- Every outside access is a standard function that declares an effect (`std.clock.read`, `std.fs.read`, `std.net.connect`); project code can declare its own (`// ms: effect db.write`).
- The checker already knows, for every function, which effects it reaches.
- So "what can this program touch" and "what would a test want to fake" are the same set of functions. Pure functions are deterministic and never need a fake.

## Limits: `--deny`

```text
$ ms run app.ms --deny 'std.fs.*'
app.ms:3:1: type: main reaches std.fs.read, which --deny std.fs.* forbids for this run; `ms lint` shows the call that brings it in
```

- Checked before anything is built or run, from the effects `main` reaches. No runtime cost, and the program cannot remove the flag.
- Patterns are the `allow_effect` patterns (`std.fs.*`, `*.write`, `*`).
- Measured on this branch: a program that reads a file and the clock runs with `--deny 'std.net.*'` and is refused with `--deny 'std.fs.*'` or `--deny '*.read'`.
- Not a sandbox: `extern fn`, `--link` and child processes are outside effects.

## Restricted access: declared capabilities and `--allow`

Scoped access (files under one path, one host, one table) is a function that declares its own effect, written once by trusted code. The runner allows only those effects.

```manuscript
// ms: effect data.read
// ms: allow_effect std.fs.read
export fn read_data(name: String) String!:
	if name.contains("/") or name.contains("\\") or name == "..":
		return error(Error(f"data.read: {name} is outside data/", kind: "EACCES"))

	bytes := read_file(join(["data", name])).wait()?
	return ok(bytes.decode_utf8().get(""))
```

- `ms run agent.ms --allow 'data.*' --allow std.console.write` builds only if everything `main` reaches matches an `--allow` pattern. A declared effect hides its body, so `read_data` counts as `data.read`, not `std.fs.read`.
- The same shape gives one host (`api.get` wrapping `fetch` to a fixed host) or one table (`orders.read` wrapping queries on `orders`). No new syntax, no runtime cost.
- Trust: a program must not relabel its own reads. Under `--allow`, only code it cannot edit may declare an effect: the standard library and fetched packages, which `ms.lock` pins by hash.
- Measured on this branch (`examples/allowed-effects`): `agent_ok.ms` runs; `agent_bad.ms` is refused for reaching `std.fs.read`; `agent_sneaky.ms`, which declares `data.read` over a read of `/etc/hostname`, is refused at its declaration.
- Spike gap: the trust check accepts any `@`-named module, so workspace members (editable) pass; the real rule trusts only locked packages.
- Not a sandbox: `extern fn`, `--link` and child processes are outside effects.

## Fakes: `fake(original, replacement)`

```manuscript
import fake, expect_equal from "@std/test/test.ms"
import now, Timestamp from "@std/time.ms"
import banner from "./greeting.ms"

test "banner uses a fixed clock":
	fake(now, fn: Timestamp(seconds: 86400, nanos: 0))
	expect_equal(banner()?, "hello, it is 1970-01-02T00:00:00Z")?
```

- `fake[F](original: F, replacement: F) Void` in `@std/test/test.ms`. Both arguments have the same function type, so the ordinary type checker proves the fake matches. No new syntax.
- One checker rule: `original` must name a function that declares an effect, standard or project. Anything else is an error that says the function is pure and needs no fake.
- Scope: until the test ends. Promises the test starts see the same fakes; other tests running at the same time do not.
- The replacement is an ordinary closure, so it can answer by argument (`fn path: ...`) or refuse (`fn: error(...)`).
- Effects: `ms lint` and `--deny` read the real program, so a fake never changes what effects code is charged with.

## How it works

- Test builds only: each call to a function that declares an effect checks a per-test table first, then calls the original. Release and normal builds keep direct calls.
- The cost lands only on calls that already do I/O, where one table lookup is small next to the system call.
- Runtime: a flat table of (function, replacement) pairs per test, copied to the promises it starts and dropped when the test ends. A small runtime primitive; the rest is in `@std/test`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-cli` | `--deny` for `run` and `build` (built) | e2e: denied and allowed runs |
| `crates/ms-check` | `fake` argument rule | reject: faking a pure function |
| `crates/ms-lower` | test builds call effect functions through the table | e2e: fake clock, fake project function |
| `crates/ms-rt` | per-test fake table, inherited by promises | runtime unit test |
| `stdlib/test/test.ms` | `fake` | stdlib test |

## Alternatives

- Do nothing: capability parameters (`FileTree`, `Logger`) work but add a parameter to every function between `main` and the call.
- Module swaps keyed on file paths: an earlier spike. Needed header comments, path strings, a second load, separate test builds, and its own signature rule. Lost on simplicity.
- Fakes on every function: a table check on pure calls too, slowing every test build, for functions that never need faking.
- Faking at run time in normal builds: a lookup on every effect call in production. No use case needs it.

## Stages

1. `--deny` for `run`, `build` and `test`, with the call path in the message.
2. `--allow`, with the trust rule limited to locked packages.
3. `fake`: runtime table, test-build lowering, checker rule, stdlib function.

## Open questions

- Should `fake` also accept a project function without a declared effect? Recommendation: no; declaring `// ms: effect` is what makes a seam visible to readers and tools.

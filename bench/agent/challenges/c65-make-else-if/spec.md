# make-lite: `else` with a condition

The program in this directory is a working simulator of a small `make`-like build tool (it reads a Makefile, a file table and requests from stdin and prints what would happen). Extend its conditionals as described below. Everything it does today must stay exactly as it is, including every message, warning, line number and the order in which things are printed.

## Chained conditionals

Today a conditional block can only use a plain `else`. Support GNU make's chained form: a line whose first word is `else` and whose next word is one of `ifdef`, `ifndef`, `ifeq`, `ifneq`, followed by the usual argument of that directive:

```
ifeq ($(MODE),debug)
CFLAGS = -g
else ifeq ($(MODE),release)
CFLAGS = -O2
else ifdef FAST
CFLAGS = -O1
else
CFLAGS =
endif
```

Rules:

- One `endif` closes the whole chain; a chained `else ifXXX` does not open a new block.
- The condition of an `else ifXXX` is evaluated only if the enclosing block is active and no earlier branch of the chain was taken. Otherwise the branch is skipped and its argument is not expanded or checked at all (so a malformed condition in a skipped branch is not an error and cannot produce `$(info ...)` output).
- The condition is evaluated exactly like the same directive at the start of a block, including its fatal error `invalid syntax in conditional` (reported with the line number of the `else ...` line), and it sees the variables defined so far.
- A chain may be followed by more `else ifXXX` branches and by at most one plain `else`. After the plain `else`, another `else` or `else ifXXX` is the fatal error `extraneous 'else'`. An `else ifXXX` with no open block is also `extraneous 'else'`.
- A plain `else` still takes the branch only if nothing earlier in the chain was taken. A plain `else` followed by any other text behaves as it does today (the text is ignored).
- An unclosed chain is `missing 'endif'`, reported with the line number of the `if...` that opened the block.

Everything else (the other requests, the other directives, the output framing) is unchanged.

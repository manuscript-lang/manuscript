# assembler-vm: new instructions and a call-depth limit

The program in this directory is a working two-pass assembler and virtual machine for a small 32-bit register machine (it reads assembly from stdin, assembles it, runs it and prints the output and a summary). Extend it as described below. Everything it does today must stay exactly as it is, including every error message, trap, the order in which errors are found, and the summary format.

## New instructions

All use the existing operand rules, the existing operand-error checks and the existing order of checks (unknown mnemonic, operand syntax, operand count, operand classes). `R` is a register, `I` an immediate expression, `M` a memory operand.

| Mnemonic | Operands | Effect |
| --- | --- | --- |
| `min` | `R, R/I/M` | `dst = the smaller (signed) of dst and the source` |
| `max` | `R, R/I/M` | `dst = the larger (signed) of dst and the source` |
| `xchg` | `R, R` | swap the two registers (the same register twice leaves it unchanged) |
| `loop` | `R, I` | decrement `R` (wrapping); if the new value is not 0, jump to the target. The target is an instruction index checked like every other jump target (`invalid jump target`) |

`min`, `max` and `xchg` do not change the flags. `loop` does not change the flags either. Like other instructions each counts as one step.

`xchg R, M`, `xchg R, I`, `loop I, I` and the like are `invalid operands for 'NAME'`; `min`/`max` with a memory source follow the memory rules (`memory access out of range: ADDR`).

## Call depth

The machine tracks the call depth: `call` raises it by one and `ret` lowers it by one, but never below zero (`ret` with depth zero is allowed, as today). A `call` made while the depth is already 64 traps with `call depth exceeded`. This check happens before the push, so before the existing `stack overflow` check, and the trapping `call` is not counted as a step (as for every trap). A program that recurses deeper than 64 calls therefore now traps with `call depth exceeded` where it used to trap with `stack overflow` or run on; this is the one intended change to existing behavior. The depth is not visible in any other way (it is not stored in memory and does not appear in the summary).

## Unchanged

The summary format, the trap and error messages, number parsing, the data section and the budget stay as they are.

# assembler-vm

Implement a two-pass assembler and a virtual machine for a small 32-bit register machine. The program reads assembly source (and optionally input numbers) from stdin, assembles it, runs it, and prints the program's output followed by a fixed summary. The exit status is always 0; assembler errors and runtime traps are reported on stdout.

## Input

Stdin is the assembly source. If a line consisting of exactly `====` appears, the source ends before it and everything after it is the *input section*: whitespace-separated decimal integers consumed by the `in` instruction (tokens that are not valid decimal integers, with optional leading `-`, are skipped; values are wrapped to 32 bits). Line endings may be `\n` or `\r\n`. Line numbers count from 1 over the source part.

## Machine

- 32-bit signed two's-complement arithmetic with wraparound everywhere.
- Registers: general `r0`..`r7`, stack pointer `sp`, extra register `bp` (usable like any register). Register names are lowercase only. Initially every register is 0 except `sp` = 4096.
- Memory: 4096 words (addresses 0..4095), each a 32-bit value, initially 0 except the data section (below). The stack lives in the same memory, grows downward from address 4095: `push v` does `sp = sp - 1; mem[sp] = v`; `pop` reads `mem[sp]` then increments `sp`.
- Code is a separate array of instructions addressed by index (0-based); a code address is an instruction index.
- Flags: `Z` and `L`, both initially 0. Only `cmp` sets them: `cmp a, b` sets `Z = (a == b)` and `L = (a < b)` (signed comparison).

## Source syntax

One statement per line. Case matters (mnemonics and directives are lowercase). `;` starts a comment that runs to the end of the line, except inside a string literal `"..."` or a character literal `'...'`. Blank and comment-only lines are ignored.

A line may begin with any number of labels `name:`; a label is an identifier followed by `:`. Identifiers match `[A-Za-z_][A-Za-z0-9_.]*`. The names `r0`..`r7`, `sp`, `bp` are reserved (`reserved name 'r0'`). A label (or `.equ` name) defined twice, or a label equal to an `.equ` name, is `duplicate symbol 'NAME'`. After the labels comes an optional instruction or directive.

Labels in the text section take the index of the next instruction. Labels in the data section take the address of the next data word. A label with nothing after it at the end of the text refers to the index just past the last instruction (which is not a valid jump target).

### Sections and directives

The assembler starts in the text section. Directives (the first word starts with `.`):

- `.text`, `.data`: switch section (no operands; otherwise `invalid operand 'TEXT'`).
- `.equ NAME, expr`: defines a constant (exactly two comma-separated operands, else `wrong number of operands for '.equ'`; NAME must be an identifier, else `invalid operand 'NAME'`). The expression is evaluated lazily when used, so it may refer to constants and labels defined anywhere; a circular definition is the error `circular definition of 'NAME'`.
- `.budget N`: sets the instruction budget (decimal integer 1..10000000, else `invalid operand 'TEXT'`). Default 100000. The last one wins. Allowed in either section.
- Data directives, only in the data section (in the text section: `data directive in text section`):
  - `.word e1, e2, ...`: one word per expression (at least one operand, else `wrong number of operands for '.word'`).
  - `.ascii "text"`: one word per byte of the string; `.asciz "text"` also appends a 0 word. Escapes in strings and character literals: `\n \t \0 \\ \' \"`. A bad string (no enclosing quotes, an unescaped inner quote, an unknown or trailing escape) is `invalid string`.
  - `.space N` or `.space N, fill`: N words (N >= 0) of value `fill` (default 0). N is evaluated immediately during the first pass, so it may use numbers, `.equ` constants whose own expressions resolve, and labels already defined above it. A negative N is `invalid operand 'N'` (N as written); the wrong number of operands is `wrong number of operands for '.space'`.
  - The data section is laid out from address 0 in source order. If it would exceed 4096 words: `data section too large` (reported on the directive that overflows).
- Any other word starting with `.` is `unknown directive '.NAME'`.

An instruction in the data section is `instruction in data section`.

## Operands and expressions

An operand is one of:

- a register name;
- a memory operand in square brackets: `[expr]` (absolute address), `[reg]`, `[reg + expr]`, `[reg - expr]`, `[expr + reg]`, or any mix where the bracket contains at most one register term (a register must be added, not subtracted) and any number of `+`/`-` expression terms (`[r2-1+a]`, `[a+r1]`). The address is the sum of all terms; all arithmetic wraps to 32 bits. An unclosed bracket, an empty bracket, a subtracted register, a second register or an empty term is `invalid operand 'TEXT'` (TEXT is the operand as written);
- anything else is an immediate expression.

Expressions: an optional leading `+` or `-`, then terms separated by `+` or `-`, evaluated left to right with 32-bit wraparound. There are no other operators and no parentheses. Whitespace between tokens is allowed. A term is:

- a decimal number, a hexadecimal number `0x...`, or a binary number `0b...`; a literal larger than 4294967295 is `immediate out of range` (literals from 2147483648 to 4294967295 wrap to negative values);
- a character literal `'c'` or `'\n'` (value = the byte), spelled with the escapes above;
- a symbol (label or `.equ` name; an unknown one is `undefined symbol 'NAME'`).

Anything else (empty text, a trailing operator, a malformed number such as `12abc`, a bad character literal, an unexpected character) is `invalid expression 'TEXT'` with TEXT being the whole expression text (trimmed).

## Instructions

Operand classes: `R` register, `I` immediate expression, `M` memory. In the table the operands are listed in order.

| Mnemonic | Operands | Effect |
| --- | --- | --- |
| `mov` | `R, R/I/M` or `M, R/I` | copy (the source is read first). `mov M, M` is invalid |
| `add sub mul div mod and or xor shl shr sar` | `R, R/I/M` | `dst = dst op src` |
| `cmp` | `R, R/I/M` | set flags |
| `neg not inc dec` | `R` | negate, bitwise not, +1, -1 |
| `lea` | `R, M` | `dst` = the effective address of the memory operand (no range check) |
| `push` | `R/I/M` | push the value |
| `pop` | `R` | pop into register |
| `jmp je jne jz jnz jl jle jg jge` | `I` | jump to the instruction index |
| `call` | `I` | push (index of next instruction), jump |
| `ret` | none | pop a value and jump to it |
| `in` | `R` | read the next input integer |
| `out` | `R/I/M` | print the value in decimal and a newline |
| `outc` | `R/I/M` | print one character (value must be 0..127) |
| `halt`, `nop` | none | stop normally; do nothing |

`jz` is `je`, `jnz` is `jne`. Jump conditions: `je` Z; `jne` not Z; `jl` L; `jle` L or Z; `jg` not L and not Z; `jge` not L.

Arithmetic: `div` and `mod` are signed with truncation toward zero (`-7 / 2 = -3`, `-7 mod 3 = -1`, `7 mod -3 = 1`); a zero divisor traps; `-2147483648 div -1` is `-2147483648` and `mod -1` is 0. `shl` and `shr` (logical) and `sar` (arithmetic) use the count masked with 31 (`count & 31`, so a negative count is masked too). `mul` keeps the low 32 bits.

Jump and call targets are evaluated to an integer at assembly time and must be a valid instruction index (`0 <= t < number of instructions`), otherwise the error `invalid jump target`.

Execution starts at the label `main` if one is defined in the text section, otherwise at instruction 0.

## Assembler errors

The first error found is reported alone, as

```
asm error line N: MESSAGE
```

and nothing else is printed (the program is not run). Errors are found in two passes. Pass 1 walks the lines in order, handling labels, directives and instruction shapes. For an instruction line the checks occur in this order: (1) `instruction in data section`; (2) `unknown mnemonic 'NAME'`; (3) operand syntax errors (`invalid operand 'TEXT'`), scanning operands left to right (an empty operand, e.g. from a trailing comma, is `invalid operand ''`); (4) `wrong number of operands for 'NAME'`; (5) `invalid operands for 'NAME'` when an operand has a class not allowed in its position (including `mov M, M`). Operands are split at commas outside brackets and character literals; an instruction's text after the mnemonic is split this way, with whitespace trimmed.

If pass 1 finds no error, pass 2 evaluates all expressions in line order (data directives and instructions merged by line number, operands left to right) and validates jump targets, reporting the first error (`undefined symbol`, `invalid expression`, `immediate out of range`, `circular definition`, `invalid jump target`). Expression errors inside a `.space` count are found in pass 1.

## Execution

Run until `halt`, a trap, or the budget is exhausted. `steps` counts completed instructions (the `halt` instruction counts; a trapping instruction does not). Before executing an instruction, if `steps` equals the budget the machine traps with `budget exceeded`. Running to an index outside `0..n-1` traps with `pc out of range`.

Traps (message, and when):

- `division by zero`: `div`/`mod` with a zero divisor.
- `memory access out of range: ADDR`: any memory read or write at ADDR < 0 or >= 4096 (ADDR printed as a signed decimal). The source operand of an instruction is evaluated before the destination.
- `stack overflow`: `push` or `call` when `sp <= 0` (checked after the source is read).
- `stack underflow`: `pop` or `ret` when `sp >= 4096`.
- `invalid character`: `outc` with a value outside 0..127.
- `input exhausted`: `in` with no input numbers left.
- `pc out of range`, `budget exceeded` as described.

`ret` does not validate the popped value: jumping to a bad index traps as `pc out of range` on the next fetch.

## Output

First the program output exactly as produced (`out` writes the decimal number and `\n`; `outc` writes the byte). If output exists and does not end with a newline, a newline is added. Then the summary:

```
-- halted after STEPS steps
```
or
```
-- trap: MESSAGE (pc=PC line=LINE) after STEPS steps
```

where PC is the index of the instruction that was about to execute (for `pc out of range`, the bad index) and LINE is its 1-based source line (`-` for `pc out of range`). Then two more lines:

```
regs: r0=V r1=V r2=V r3=V r4=V r5=V r6=V r7=V sp=V bp=V
flags: Z=0 L=1
```

with registers as signed decimals and flags as 0/1. This summary is printed after both normal halts and traps, but not after an assembler error.

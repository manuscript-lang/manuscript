# Bank ledger

Simulate a small ledger with overdraft limits, an overdraft fee, frozen accounts and an audit report.
Each non-blank input line is a command; tokens are separated by runs of spaces or tabs. Account ids are
arbitrary tokens. Blank lines produce no output.

| command | meaning |
| --- | --- |
| `open ID LIMIT` | create account `ID` with balance 0 and overdraft limit `LIMIT` |
| `deposit ID AMOUNT` | add `AMOUNT` |
| `withdraw ID AMOUNT` | remove `AMOUNT` |
| `transfer FROM TO AMOUNT` | move `AMOUNT` from `FROM` to `TO` |
| `freeze ID` / `unfreeze ID` | set / clear the frozen flag |
| `report` | print the audit report |

`LIMIT` must be a non-empty string of ASCII digits (0 allowed). `AMOUNT` must be a non-empty string of ASCII
digits with value greater than 0; leading zeros are fine (`007` is 7), signs and decimals are invalid.
Tests keep every value well inside signed 64-bit range.

## Rules and output

Every command prints exactly one line, except `report`. Checks run in the listed order and the first failure
wins; a failed command changes nothing except the `rejected` counter described below.

- A line with the wrong number of tokens for its command, or an unknown command word: `error: bad command`.
- `open`: invalid limit gives `error: invalid limit`; an existing id gives `error: account exists ID`.
  Success prints `ok`.
- `freeze` / `unfreeze`: unknown id gives `error: unknown account ID`; otherwise `ok` (idempotent).
- `deposit`, `withdraw`, `transfer`, in this order:
  1. unknown account: `error: unknown account ID` (for `transfer` check `FROM` before `TO`);
  2. `transfer` with `FROM` equal to `TO`: `error: same account`;
  3. invalid amount: `error: invalid amount`;
  4. frozen account: `error: account frozen ID` (for `transfer` check `FROM` before `TO`; a frozen account
     blocks the transfer in either role);
  5. for `withdraw` and for the `FROM` side of `transfer`: let `new = balance - amount`. If `balance >= 0`
     and `new < 0`, an overdraft fee of 5 is charged: `new = new - 5`. If `new < -limit` the command fails with
     `error: overdraft limit exceeded ID` and nothing changes. The fee is not credited to any account; it is
     added to the ledger's `fees` total.
- Success output: `ok B` where `B` is the account's new balance; for `transfer`, `ok F T` with the new balances
  of `FROM` and `TO`. When a fee was charged append ` fee=5` (e.g. `ok -3 fee=5`).

An account is *blamed* for a failed command at steps 2 to 5 when the error names it: step 2 and 3 blame the
(first) named account (`FROM` for `transfer`), step 4 and 5 blame the account in the error message. Each
blame adds 1 to that account's `rejected` counter. A successful `deposit`, `withdraw` or `transfer` adds 1 to
`ops` of every account involved (both accounts for `transfer`). `freeze`, `unfreeze` and `open` do not count
as ops. Errors at step 1 or earlier blame nobody.

## Report

`report` prints one line per account in ascending byte-wise order of id:

    ID balance=B limit=L ops=N rejected=R frozen=yes|no

followed by `total balance=T fees=F`, where `T` is the sum of all balances and `F` the sum of all fees
charged so far. With no accounts only the total line is printed.

## Example

Input:

    open a 20
    open b 0
    deposit a 10
    withdraw a 25
    withdraw a 10
    transfer a b 3
    freeze b
    deposit b 1
    report

Output:

    ok
    ok
    ok 10
    ok -20 fee=5
    error: overdraft limit exceeded a
    error: overdraft limit exceeded a
    ok
    error: account frozen b
    a balance=-20 limit=20 ops=2 rejected=2 frozen=no
    b balance=0 limit=0 ops=0 rejected=1 frozen=yes
    total balance=-20 fees=5

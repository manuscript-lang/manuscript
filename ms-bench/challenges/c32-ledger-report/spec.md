# Ledger report

A small accounting tool receives a bank-export ledger on standard input and must print a clean report.
The export is messy: mixed date styles, currency formatting, comments, blank lines, duplicate rows and
broken rows. All text is ASCII. All money is handled as integer cents; never use floating point.

## Input

Lines are numbered from 1 (physical lines, counting blank and comment lines). Process them in order:

- A line that is empty or whitespace-only, or whose first non-space character is `#`, is skipped.
- The first remaining line is the header; it is skipped without validation.
- Every later line is a *record* with four comma-separated fields: `date,account,description,amount`.

### Field splitting

Split a record at commas. A field that **starts with `"`** (as the very first character of the field) is
quoted: it runs to the first `"` that is not followed by another `"`, `""` stands for one `"`, and it may
contain commas; the closing quote must be followed by a comma or the end of the line. Any other field runs
to the next comma. Quote handling never fails: a record whose text does not fit this description is
processed as far as it goes, and the result is judged by the field-count rule below. After splitting, trim
spaces and tabs from both ends of every field. A record must have exactly 4 fields, otherwise it is rejected
with reason `field count`.

### Validation (first failing check wins)

1. **date** (`bad date`): either `YYYY-MM-DD` (4-2-2 digits) or `MM/DD/YYYY` (2-2-4 digits). The month must
   be 1..12 and the day must exist in that month (Gregorian leap years: divisible by 4 except centuries not
   divisible by 400; year 0000 is allowed). It is normalised to `YYYY-MM-DD`.
2. **account** (`bad account`): non-empty after trimming.
3. **amount** (`bad amount`): optional sign, optional `$`, a number, with the sign being either a leading
   `-` or the whole value wrapped in parentheses (a parenthesised value is negative; `-` together with
   parentheses is invalid; the `$` goes inside the parentheses, after the `-`). The number is either plain
   digits (`1`, `1500`) or digits with thousands commas (`1,500`, `12,345,678`: one to three leading digits
   followed by groups of exactly three), optionally followed by `.` and one or two digits. Examples of valid
   amounts: `12`, `-12.5`, `$1,234.50`, `-$3`, `(45.00)`, `($1,000)`. Invalid: `1,23`, `12.345`, `$-3`, `--1`,
   `1e3`, `.5`, `5.`, empty. Since a thousands comma would split an unquoted field, such amounts appear in
   quotes in the file. At most 12 digits in total.

A rejected record contributes the error line `line N: <reason>` (N is its physical line number).

### Duplicates

A valid record whose normalised `(date, account, description, amount in cents)` is identical to an earlier
valid record is a *duplicate*: it is counted in `duplicates` and otherwise ignored. Account and description
comparison is case-sensitive.

## Output

All money is printed as `[-]D.CC`, with the integer part grouped in thousands by commas (for example
`-1,234.50`, `0.00`, `12,345,678.90`).

    transactions: <number of valid, non-duplicate records>
    duplicates: <number of duplicate records>
    errors: <number of rejected records>
    accounts:
      <account> balance=<sum> credits=<sum of positive amounts> debits=<sum of absolute values of negative amounts> count=<n>
    months:
      <YYYY-MM> net=<sum of all accounts' amounts in that month>
    largest: <date> | <account> | <description> | <amount>
    errors:
      line <N>: <reason>

- `accounts:` lists accounts sorted ascending by byte order of the name, then each line is indented 2 spaces.
  `months:` lists months in ascending order. Both headings are always printed, even when empty.
- `largest:` is the valid non-duplicate transaction with the greatest absolute amount (the earliest in the
  file wins ties). It is printed with its signed amount, and omitted when there are no transactions.
- The final `errors:` heading and its lines (in file order, indented 2 spaces) are printed only when at least
  one record was rejected.

Example input:

    date,account,description,amount
    2024-01-05,checking,Payroll,"2,500.00"
    01/07/2024, checking ,"Coffee, beans",(12.40)
    2024-01-05,checking,Payroll,"2,500.00"
    2024-02-30,savings,Interest,1.20
    # a note
    2024-02-01,savings,Deposit,$300
    2024-02-02,savings,x

Output:

    transactions: 3
    duplicates: 1
    errors: 2
    accounts:
      checking balance=2,487.60 credits=2,500.00 debits=12.40 count=2
      savings balance=300.00 credits=300.00 debits=0.00 count=1
    months:
      2024-01 net=2,487.60
      2024-02 net=300.00
    largest: 2024-01-05 | checking | Payroll | 2,500.00
    errors:
      line 5: bad date
      line 8: field count

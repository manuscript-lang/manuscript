# Library checkout

Simulate a library with loans, renewals, a hold queue and fines. Each non-blank input line is a command;
tokens are separated by runs of spaces or tabs. Member and book ids are tokens of letters, digits and
underscores. Every command prints exactly one line, except `overdue` and `report`. Blank lines produce no
output.

| command | meaning |
| --- | --- |
| `book B N` | add `N` copies of book `B` (creating it if needed) |
| `member M` | register member `M` |
| `checkout M B DAY` | member `M` borrows a copy of `B` on day `DAY` |
| `return M B DAY` | member returns `B` on day `DAY` |
| `renew M B DAY` | extend the loan |
| `hold M B` | join the hold queue of `B` |
| `overdue DAY` | list loans that are overdue on day `DAY` |
| `report` | summary of members and books |

`N` and `DAY` are non-empty strings of ASCII digits (`N` must also be greater than 0). Constants: a loan lasts
14 days (`due = DAY + 14`), a member may hold at most 3 loans, a loan can be renewed at most 2 times, and the
fine for a late return is 10 per day late. A loan is *overdue on day D* when `D > due`.

Tokens are checked first for arity (wrong token count or unknown command word: `error: bad command`), then
for `N` / `DAY` validity (`error: bad copies`, `error: bad day`). A failing command changes nothing.

## Commands

- `book B N`: prints `ok`.
- `member M`: `error: member exists M` if already registered, otherwise `ok`.
- `checkout M B DAY`, checks in this order, first failure wins:
  `error: unknown member M`, `error: unknown book B`, `error: already borrowed` (M has an active loan of B),
  `error: loan limit reached` (M already has 3 loans), `error: has overdue loans` (some loan of M is overdue on
  `DAY`), then availability. Let `avail = copies(B) - active loans of B` and `q` the hold queue of `B`
  (earliest holder first). If `avail <= 0`: `error: no copies available`. Otherwise, if `M` is in `q` at zero-based
  position `p`, M may borrow only when `p < avail`; if `M` is not in `q`, M may borrow only when
  `avail > len(q)` (the first `len(q)` free copies are reserved for holders); else `error: reserved for holds`.
  On success M leaves `q` (if present), a loan with `due = DAY + 14` and 0 renewals is created, and
  `ok due=D` is printed.
- `return M B DAY`: `error: unknown member M`, `error: unknown book B`, `error: not borrowed`; otherwise the loan
  ends, `fine = 10 * max(0, DAY - due)` is added to M's fines (days are not required to be non-decreasing), and
  `ok fine=F` is printed.
- `renew M B DAY`: unknown member, unknown book, `error: not borrowed`, then `error: overdue` (`DAY > due`),
  `error: renewal limit` (already renewed twice), `error: held by others` (queue of `B` non-empty). On success
  `due` increases by 14, renewals increase by 1, and `ok due=D` is printed.
- `hold M B`: unknown member, unknown book, `error: already borrowed`, `error: already on hold` (M is in `q`),
  `error: copies available` (when `avail > len(q)`). Otherwise M is appended to `q` and `ok position=P`
  (1-based) is printed.
- `overdue DAY`: one line `M B late=L` per loan that is overdue on `DAY` (`L = DAY - due`), ordered by member id then
  book id (byte-wise); `none` if there are no such loans.
- `report`: first `members=X books=Y`; then one line per member in id order `M loans=N fines=F`; then one line per
  book in id order `B copies=C out=O holds=H` (`O` active loans, `H` queue length).

## Example

Input:

    book dune 1
    member ann
    member bob
    checkout ann dune 1
    hold bob dune
    renew ann dune 5
    return ann dune 20
    checkout bob dune 21
    overdue 40
    report

Output:

    ok
    ok
    ok
    ok due=15
    ok position=1
    error: held by others
    ok fine=50
    ok due=35
    bob dune late=5
    members=2 books=1
    ann loans=0 fines=50
    bob loans=1 fines=0
    dune copies=1 out=1 holds=0

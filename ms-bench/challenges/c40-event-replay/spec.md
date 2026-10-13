# Event-sourced orders

Maintain order aggregates by replaying an event log, with optimistic version checks and time-travel queries.
Each non-blank input line is either an *event line* or a *query line*; tokens are separated by runs of spaces or
tabs. Blank lines produce no output. Every line prints exactly one line of output, except `show` and `at`, which
print several. Aggregate ids and SKUs are tokens without whitespace; ids are never `show` or `at`.

## Event lines

    ID VERSION TYPE [ARGS...]

An aggregate exists once at least one event for it has been **accepted**. Its *version* is the number of accepted
events; its state starts as `none` (before any accepted event). Process an event line with these checks, first
failure wins, a failing event changes nothing:

1. fewer than 3 tokens: `error: bad line`; `VERSION` not a non-empty string of ASCII digits: `error: bad version`.
2. `VERSION` must equal current version + 1 (0 for an unknown aggregate), otherwise
   `ID: conflict v=VERSION expected=E` where `E` is current version + 1. (`VERSION` is compared numerically, leading zeros allowed, and is printed in that message exactly as written; `V` elsewhere is a plain decimal integer.)
3. unknown `TYPE`: `ID: unknown event TYPE`.
4. wrong number of arguments for the event, or a numeric argument that is not a non-empty string of ASCII digits,
   or a quantity of 0: `ID: bad arguments for TYPE`.
5. the state rules below.

Events (`QTY`, `PRICE`, `AMOUNT` are non-negative integers; `QTY` must be at least 1):

| event | allowed in state | effect |
| --- | --- | --- |
| `created` | `none` | state becomes `open` |
| `item_added SKU QTY PRICE` | `open` | add `QTY` to the quantity of `SKU` (new SKUs start at 0) and set its unit price to `PRICE` |
| `item_removed SKU` | `open` | remove `SKU` entirely; if `SKU` is not in the order the event fails with `ID: no such item SKU at vV` |
| `paid AMOUNT` | `open` | requires at least one item (else `ID: empty order at vV`) and `AMOUNT` equal to the order total (else `ID: wrong amount expected=TOTAL at vV`); state becomes `paid` |
| `shipped` | `paid` | state becomes `shipped` |
| `cancelled` | `open`, `paid` | state becomes `cancelled` |

`V` in those messages is the version the event carried. In any other state the event fails with
`ID: invalid TYPE in STATE at vV`. The order total is the sum of `quantity * price` over all items.

On success print `ID: TYPE -> STATE v=V` (the state after the event, `V` the new version).

## Query lines

- `show ID`: `error: unknown aggregate ID` if the aggregate does not exist; otherwise the summary below.
- `at ID V`: the summary of the aggregate after replaying only its first `V` accepted events. `V` must be a
  non-empty string of ASCII digits not greater than the current version (else `error: bad version`); `V = 0` gives
  state `none`. Unknown aggregate: `error: unknown aggregate ID`. Checks run in that order: arity first
  (`error: bad line`), then unknown aggregate, then `V`.

Summary format: a header line `ID state=STATE v=V items=K total=T` (`K` distinct SKUs), followed by one line per item
in ascending byte-wise SKU order: two spaces, then `SKU xQTY @PRICE`.

## Example

Input:

    o1 1 created
    o1 1 created
    o1 2 item_added pen 3 50
    o1 3 item_added ink 1 700
    o1 4 paid 100
    o1 4 paid 850
    o1 5 item_added cap 1 5
    show o1
    at o1 2

Output:

    o1: created -> open v=1
    o1: conflict v=1 expected=2
    o1: item_added -> open v=2
    o1: item_added -> open v=3
    o1: wrong amount expected=850 at v4
    o1: paid -> paid v=4
    o1: invalid item_added in paid at v5
    o1 state=paid v=4 items=2 total=850
      ink x1 @700
      pen x3 @50
    o1 state=open v=2 items=1 total=150
      pen x3 @50

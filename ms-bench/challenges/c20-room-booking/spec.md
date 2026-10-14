# Room booking desk

Read commands from stdin, one per line, and print the response lines. Blank lines (empty or only spaces) are
skipped. A command is split on single spaces (consecutive spaces produce empty tokens, which count as tokens
and are normally invalid values). Every command prints exactly one response line, except `report`.

## Commands

- `room NAME CAPACITY` - define a room. Checks in order: token count is 3 (else `error: usage`); `NAME` is a
  lowercase letter followed by 0 to 9 lowercase letters or digits (else `error: bad room name`); `CAPACITY` is
  1 to 6 ASCII digits with a value from 1 to 500 (else `error: bad capacity`); the room is new (else
  `error: room exists`). Success prints `ok`.
- `book ID ROOM DATE START END ATTENDEES` - request a booking. Checks in order, the first failure is printed:
  1. token count is 7: else `error: usage`
  2. `ID` is 1 or more characters from `a-z`, `0-9`, `-`: else `error: bad id`
  3. `ID` was never used by an earlier `book` that passed check 2 (even if that booking failed or was cancelled
     later): else `error: duplicate id`
  4. `ROOM` is defined: else `error: unknown room`
  5. `DATE` is `YYYY-MM-DD`, a real calendar date, year 2000 to 2099: else `error: bad date`
  6. `START` and `END` are `HH:MM` with hour 00 to 23 and minute 00 to 59, exactly two digits each: else
     `error: bad time`
  7. `END` is later than `START`: else `error: bad range`
  8. both times have a minute that is a multiple of 15 (00, 15, 30, 45): else `error: not aligned`
  9. the booking lies within business hours, `START` >= 08:00 and `END` <= 20:00: else `error: outside hours`
  10. the booking is at most 240 minutes long: else `error: too long`
  11. `ATTENDEES` is 1 to 6 ASCII digits with a value of at least 1: else `error: bad attendees`
  12. `ATTENDEES` is at most the room capacity: else `error: over capacity`
  13. no active booking in the same room on the same date overlaps (`start1 < end2` and `start2 < end1`;
      touching bookings do not overlap): else `error: conflict with <id>` naming the overlapping booking that
      was created first.
  Success prints `ok <ID>` and the booking becomes active. Note that the ID is consumed as soon as check 3
  passes, whether or not later checks fail.
- `cancel ID` - token count 2 (else `error: usage`); the ID must belong to a successful booking (else
  `error: unknown booking`); it must still be active (else `error: already cancelled`). Success prints `ok`
  and the slot is free again. The ID stays used.
- `report` - token count 1 (else `error: usage`). Prints, for every room in byte order of the room name:

      <name> cap=<capacity> active=<n> minutes=<total booked minutes> util=<percent>%
        <date> <start>-<end> <id> attendees=<n>

  The second form is printed once per active booking of that room, sorted by date, then start time, then ID
  (byte order). Attendees are printed as an integer without leading zeros. `util` is the booked minutes as a
  percentage of `720 * D`, where `D` is the number of distinct dates with an active booking in that room,
  rounded half up to a whole number (`util=0%` when `D` is 0). After all rooms print
  `bookings active=<A> cancelled=<C>` counting successful bookings that are currently active or cancelled.
  Times keep their input spelling (they are always two-digit `HH:MM`).
- Any other first token prints `error: unknown command`.

## Example

Input:

    room alpha 10
    room beta 4
    book b1 alpha 2024-03-04 09:00 10:30 6
    book b2 alpha 2024-03-04 10:00 11:00 2
    book b3 beta 2024-03-04 09:00 10:00 5
    book b4 alpha 2024-03-04 10:30 11:30 3
    cancel b1
    book b5 alpha 2024-03-04 09:10 10:00 1
    report

Output:

    ok
    ok
    ok b1
    error: conflict with b1
    error: over capacity
    ok b4
    ok
    error: not aligned
    alpha cap=10 active=1 minutes=60 util=8%
      2024-03-04 10:30-11:30 b4 attendees=3
    beta cap=4 active=0 minutes=0 util=0%
    bookings active=1 cancelled=1

# Unit converter

Process a script of commands that convert quantities between units, compare them, and define new units.
Every non-blank line is one command and prints exactly one line. Tokens are separated by runs of spaces and
tabs; blank lines produce no output. Command words and unit names are case-sensitive.

All arithmetic is exact integer arithmetic (no floating point is needed or allowed to change an answer).

## Numbers

A *number* token is an optional `-`, one or more ASCII digits, and optionally a `.` followed by **one to
three** ASCII digits: `5`, `-0.5`, `007`, `12.345`. Anything else is not a number (`+5`, `.5`, `5.`, `1e3`,
`1.2345`, `1,5`, a lone `-`). Its value in thousandths is an integer `m` (so `12.345` is 12345, `-0.5` is
-500, `-0` is 0). A number is in range when `|m| <= 100000000`, i.e. at most 100000 in absolute value.

## Units

| dimension | units (value in the dimension's base unit) |
| --- | --- |
| `length` | `mm`=10, `cm`=100, `m`=10000, `km`=10000000, `in`=254, `ft`=3048, `yd`=9144, `mi`=16093440 |
| `mass` | `mg`=1, `g`=1000, `kg`=1000000, `oz`=28350, `lb`=453592 |
| `time` | `ms`=1, `s`=1000, `min`=60000, `h`=3600000, `d`=86400000 |
| `volume` | `ml`=1, `l`=1000, `tsp`=5, `tbsp`=15, `cup`=240, `gal`=3785 |
| `temperature` | `c` (Celsius), `f` (Fahrenheit), `k` (Kelvin) |

Linear units convert by their table values (the numbers are exact definitions for this task, not physical
constants). Temperature units are affine and are not in the table: `F = C*9/5 + 32` and `K = C + 273.15`;
convert through Celsius with exact rational arithmetic and round only once at the end. A temperature below
absolute zero (below -273.15 C, i.e. below -459.67 F or below 0 K) is invalid.

`define` adds user units, see below. A user unit has the dimension of its base unit and the table value
`V` times the base unit's table value.

## Commands

**`convert NUMBER FROM to TO`** (exactly 5 tokens, the fourth being the word `to`). Converts the quantity
and prints `N FROM = R TO`, where `N` is the input value and `R` the result, both formatted as below. For
linear units the result in thousandths is `round(m * value(FROM) / value(TO))`. For temperatures, compute
the Celsius value as an exact fraction, convert to the target scale exactly, then round once.

**`compare NUMBER1 UNIT1 NUMBER2 UNIT2`** (exactly 5 tokens). Compares the two quantities exactly (as
exact rationals, no rounding; temperatures are compared as Celsius values) and prints
`N1 UNIT1 REL N2 UNIT2`, where `REL` is `<`, `=` or `>`.

**`define NAME = V UNIT`** (exactly 5 tokens, the third being `=`). Defines `NAME` as `V` copies of the
builtin linear unit `UNIT` and prints `ok`. `V` is a string of ASCII digits (leading zeros allowed) with
value from 1 to 1000. `UNIT` must be a builtin unit, not a user-defined one. Defined units live for the rest
of the script and can be used like any other unit, but cannot be redefined.

Rounding is to the nearest integer thousandth, with halves rounded away from zero (so `-0.0005` rounds to
`-0.001`). Tests keep all intermediate products within signed 64-bit range except where the "out of range"
check applies; a quantity of at most 100000 times a unit value of at most 1000 * 16093440 fits.

## Formatting

A value `m` in thousandths prints as a decimal with its fractional part trimmed of trailing zeros and no
decimal point when the fraction is zero: `25.4`, `3`, `0.001`, `-12.5`. The value zero always prints as `0`
(never `-0`, never `0.0`). Input like `5.10` therefore echoes as `5.1`.

## Errors

A first word that is not `convert`, `compare` or `define` is `error: syntax`. A line that fails prints `error: ...` and changes nothing. Checks run in this order and the first failure
wins.

For `convert` and `compare`:

1. wrong token count, or (for `convert`) the fourth token not being `to`: `error: syntax`;
2. each number token in order (for `compare`, `NUMBER1` then `NUMBER2`) that is not a number:
   `error: bad number TOKEN`;
3. each unit token in order (`UNIT1`/`FROM` first) that is neither builtin nor defined:
   `error: unknown unit TOKEN`;
4. a number out of range (first one in order): `error: out of range`;
5. the two units having different dimensions: `error: dimension mismatch D1 vs D2`, where `D1` is the
   dimension of the first unit and `D2` of the second (`length`, `mass`, `time`, `volume`, `temperature`);
6. a temperature below absolute zero in the input value(s): `error: below absolute zero`.

For `define`:

1. wrong token count or the third token not `=`: `error: syntax`;
2. `NAME` not matching a lowercase letter followed by lowercase letters, digits or `_`: `error: bad name NAME`;
3. `NAME` already a builtin or defined unit: `error: unit exists NAME`;
4. `V` not a digit string with value 1..1000: `error: bad number V`;
5. `UNIT` a user-defined unit: `error: not a builtin unit UNIT`; not a unit at all: `error: unknown unit UNIT`;
   a temperature unit: `error: cannot define temperature unit`.

## Example

Input:

    convert 1 in to mm
    convert 100 c to f
    convert 3 kg to m
    convert 1.0005 km to m
    define mile2 = 2 mi
    convert 1 mile2 to km
    compare 1 ft 12 in

Output:

    1 in = 25.4 mm
    100 c = 212 f
    error: dimension mismatch mass vs length
    error: bad number 1.0005
    ok
    1 mile2 = 3.219 km
    1 ft = 12 in

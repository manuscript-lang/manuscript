# Roman numerals

Each non-blank input line (blank means empty or only spaces; blank lines produce no output) holds one
token and produces one output line. The token is used exactly as written: a line with leading or trailing
spaces, or with any character that is not part of a valid token, is `invalid`.

- If the line is made only of ASCII digits, it is a decimal number. Convert it to a Roman numeral. The
  number must have no leading zeros and be in the range 1 to 3999, otherwise print `invalid`. Tests use
  at most 9 digits.
- Otherwise the line is treated as a Roman numeral and converted to decimal. Only the uppercase letters
  `I V X L C D M` may appear. The numeral must be in *canonical* form, the one produced by converting its
  value to Roman numerals with the standard subtractive rules (`IV`, `IX`, `XL`, `XC`, `CD`, `CM`, and
  nothing else subtractive; `M` repeated up to three times). Anything non-canonical, such as `IIII`,
  `IC`, `VX`, `MMMM`, `IIX` or lowercase letters, prints `invalid`.

Example input:

    1994
    MCMXCIV
    IIII
    0
    4000
    xiv
    3999

Output:

    MCMXCIV
    1994
    invalid
    invalid
    invalid
    invalid
    MMMCMXCIX

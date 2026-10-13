# JSON pretty-printer

Read one JSON document from standard input (ASCII only). If it is valid according to the grammar below, print
it pretty-printed; otherwise print the single line `invalid`. Do not use a JSON library: write the parser
yourself.

## Grammar

- **Whitespace** between tokens is any mix of space, tab (`\t`), line feed and carriage return. The input is
  `ws value ws` and nothing else: any other trailing text makes it invalid, and empty or whitespace-only input
  is invalid.
- **value**: an object, an array, a string, a number, `true`, `false` or `null` (lowercase, exact).
- **object**: `{` ws `}`, or `{` ws members `}` where members are `string ws : ws value` separated by `ws , ws`.
  Duplicate keys are allowed and kept. No trailing comma.
- **array**: `[` ws `]`, or `[` ws values `]` with values separated by `ws , ws`. No trailing comma.
- **string**: `"` followed by any number of characters and a closing `"`. A character is any character with
  code 0x20 or above except `"` and `\`, or an escape: `\` followed by one of `"` `\` `/` `b` `f` `n` `r` `t`,
  or `\u` followed by exactly four hexadecimal digits (either case). Raw control characters (below 0x20,
  including a literal tab or newline) inside a string are invalid.
- **number**: `-?` then `0` or a digit `1-9` followed by digits, then optionally `.` followed by one or more
  digits, then optionally `e` or `E`, an optional `+` or `-`, and one or more digits. So `01`, `1.`, `.5`,
  `+1`, `-`, `NaN` and `Infinity` are invalid.

Nesting depth never exceeds 200 in the tests.

## Output

Print strings and numbers exactly as they were written in the input (do not decode or re-escape strings, do
not normalize numbers). Layout, with two spaces per indentation level and `\n` line breaks:

- An empty object prints `{}` and an empty array prints `[]`.
- A non-empty object prints `{`, a newline, each member on its own line indented one level deeper as
  `"key": value` (one space after the colon), members separated by `,` at the end of each line except the
  last, then a newline, the current indentation and `}`. Arrays are the same with values instead of members
  and `[` `]`.
- Nested containers start on the same line as their key (or as the array element) and end with their closing
  bracket at that element's indentation.
- The output ends with a newline.

Example input:

    {"a":[1,2,{"b":null}],"c":"x\ty", "d":{}, "e":[]}

Output:

    {
      "a": [
        1,
        2,
        {
          "b": null
        }
      ],
      "c": "x\ty",
      "d": {},
      "e": []
    }

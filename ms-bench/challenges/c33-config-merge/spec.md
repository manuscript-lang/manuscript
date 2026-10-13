# Layered config merge

A deployment tool merges several configuration *layers* (defaults, environment, local overrides, ...) into one
effective configuration and reports where every value came from. Standard input holds all layers in order.
Output is the merged configuration plus a list of problems. All text is ASCII.

## Input

Lines are numbered from 1 (physical lines). Trim spaces and tabs from both ends of each line, then:

1. Empty lines and lines starting with `#` are ignored.
2. A line starting with `@@` starts a new layer; the layer name is the rest of the line, trimmed (use
   `unnamed` if that is empty). Lines before the first `@@` line belong to a layer named `base`.
3. `!KEY` removes `KEY` and every key that starts with `KEY.` (a dot after it). Removing nothing is fine.
4. Otherwise the line is an assignment: find the first `=`. If the character right before it is `+`, it is an
   *append* (`KEY += VALUE`), and the key is the text before the `+`; otherwise it is a *set*
   (`KEY = VALUE`). The key (trimmed) and the value (trimmed) are the two sides.
5. Anything else, or a line whose key is not valid, is a syntax error: record `line N: syntax error` and go on.

A **key** is one or more dot-separated segments; a segment is `[a-z_][a-z0-9_]*`. Keys are flat strings, so
`a` and `a.b` are independent entries (only `!a` removes both).

## Values

The (trimmed) value text is interpreted as follows:

- `true` / `false`: boolean.
- An optional `-` followed by 1 to 15 digits: integer (printed in canonical form: no leading zeros, `-0`
  becomes `0`).
- Starts with `"`: a quoted string. It must end with an unescaped `"` which is also the first unescaped `"`
  after the opening one; `\"` stands for `"` and `\\` for `\`; any other backslash is an ordinary character.
  Otherwise it is a syntax error.
- Starts with `[`: a list; it must end with `]` (else syntax error). The text between the brackets is split
  at every `,`; each piece is trimmed and must be non-empty (else syntax error) and is a scalar: boolean or
  integer as above, a `"`-quoted string (when it begins and ends with `"` and has at least 2 characters the
  quotes are removed and no escapes are processed), or otherwise a bare string. If the text between the
  brackets is empty or only blanks, the list is empty.
- Anything else, including the empty value: a bare string whose content is the trimmed text.

A syntax error in the value leaves the configuration unchanged and is recorded as `line N: syntax error`.

**Set** replaces the key's value. **Append** adds to a list: when the key is absent it starts as an empty list;
the parsed value is appended as one item, or, if the value is itself a list, all of its items are appended.
If the key already holds a non-list value, record `line N: cannot append to non-list` and change nothing.

Every successful set or append records the current layer's name as the key's *source* (the last one wins). A
removal drops the key's source with it.

## Interpolation

After all layers are processed, every top-level **string** value (not list items) is scanned left to right for
`${NAME}`: find `${`, then the next `}`; if the text between is a valid key, replace the whole `${NAME}` by the
referenced key's *plain text* and continue after it; otherwise leave the `$` as it is and continue with the
next character. Plain text: a string's (already interpolated) content, an integer or boolean as written in the
output, a list's items' plain texts joined with `,` (items are not interpolated). Replacement text is not
scanned again. Referenced strings are interpolated first (references never form cycles in the tests). If the
referenced key does not exist, keep the `${NAME}` text and record `key K: unresolved ${NAME}` for the key
`K` that contains it (one message per occurrence).

## Output

For each key in ascending byte order print `KEY = VALUE  # SOURCE` (two spaces before `#`). Values print as:
strings in double quotes with `\` written as `\\` and `"` as `\"`; integers and booleans plainly; lists as `[`
items joined by `, ` `]` with items printed like scalars (`[]` when empty).

If any problem was recorded, finish with `errors:` and then each message indented by 2 spaces: first the
parse problems in input order, then the `unresolved` messages ordered by key (ascending) and, for one key, by
position in the value. Print nothing for an empty configuration.

Example input:

    host = "db.local"
    port = 5432
    name = x
    url = ${host}:${port}/main
    tags = [a, b]
    @@ prod
    host = "db.prod"
    tags += c
    !port
    debug = maybe?
    oops
    name += 1

Output:

    debug = "maybe?"  # prod
    host = "db.prod"  # prod
    name = "x"  # base
    tags = ["a", "b", "c"]  # prod
    url = "db.prod:${port}/main"  # base
    errors:
      line 11: syntax error
      line 12: cannot append to non-list
      key url: unresolved ${port}

+++
title = "Template syntax and filters"
weight = 3
+++

# Template syntax and filters

This reference describes the template language accepted by `compile` from `@std/text/template.ms`. It is distinct from Manuscript source. Read [the template lesson](templates.md) for a complete program that loads and renders a template; the [API reference](../standard-library/reference/text/template.ms.md) defines the calls and their parameters.

The forms below are template syntax and expression schemas, not standalone Manuscript programs. Names such as `condition`, `items`, and `expression` stand for your data or expressions.

## Actions and literal text

Text outside an action is copied unchanged. An action begins with `{{` and ends with `}}`. The first closing delimiter ends the action, including inside a quoted value; do not put a literal `}}` inside an action's string.

| Form | Meaning |
| --- | --- |
| `{{ expression }}` | Evaluate and print a value. |
| `{{# comment }}` | Discard the comment. |
| `{{- expression }}` | Remove whitespace immediately before the action. Keep whitespace between the trim marker and expression. |
| `{{ expression -}}` | Remove whitespace immediately after the action. Keep whitespace before the trim marker. |
| `{{ "{{" }}` | Print a literal opening delimiter. |

A plain `}}` outside an action is literal text. Use both trim markers to trim on both sides. Trimming removes adjacent spaces, tabs, and newlines; it can therefore join lines.

## Values and paths

Expressions accept double-quoted strings, decimal number literals, `true`, `false`, `null`, and paths. Strings understand `\n`, `\t`, escaped quotes, and escaped backslashes. A leading minus can be part of a number. There are no arithmetic operators, array/object literals, function calls, or bracket-index expressions in this template language.

A path such as `user.name` walks object members; a numeric segment such as `items.0` selects a list position. Names start with an ASCII letter or underscore. Resolve the first name in the innermost loop frame first, then enclosing frames, then the root object's fields. A non-object root supplies no named fields. Loop variables can shadow root names.

Missing paths fail when printed under the default `strict: true`. With `strict: false`, a missing path behaves as null and prints empty text. Conditions and loop sources allow missing paths independently of strict printing. `default` also allows a missing input.

Text conversion prints strings without JSON quotes, booleans as `true` or `false`, and numbers using their retained number text. Null prints empty text. Arrays and objects print as compact JSON. Use `json` when a string should retain its JSON quotes and escapes.

## Conditions and operators

A conditional selects its first true branch. `else if` and `else` are optional; `end` is required:

```text
{{ if condition }}selected text{{ else if other }}other text{{ else }}fallback{{ end }}
```

False-like values are null, false, zero, empty text, and empty lists or objects. Missing paths also behave as false in a condition. All other values are true-like.

Precedence from highest to lowest is: parentheses and values, filter pipelines, one comparison (`==`, `!=`, `<`, `<=`, `>`, `>=`), `not`, `and`, then `or`. Comparison chains are not supported. `and` and `or` short-circuit and return a boolean. Operator operands allow missing paths as null, even in a printed action.

Numbers compare numerically after conversion to `Float`; this is not exact integer comparison for every large JSON number. Ordering otherwise works between two strings. Unorderable pairs make each ordering comparison false. Equality between nonnumeric values compares their rendered text and whether each is null, so it is not Manuscript's typed equality: for example, a boolean and its text spelling can compare equal. Keep domain validation and precise calculations in Manuscript.

## Loops and scope

These are template schemas; substitute paths or expressions for `items` and `object`:

```text
{{ for item in items }}{{ item }}{{ else }}empty{{ end }}
{{ for index, item in items }}{{ index }}: {{ item }}{{ end }}
{{ for key, value in object }}{{ key }}: {{ value }}{{ end }}
```

A list loop visits values in list order. With two names, the first receives a zero-based index. An object loop visits members in map order; with one name, that name holds an object with `key` and `value` fields. A missing, empty, or noncollection source runs the optional `else` branch.

Each iteration supplies `loop.index` (zero-based), `loop.first`, `loop.last`, and `loop.length`. An inner loop has its own `loop`; the enclosing frame becomes visible again after it finishes. The loop variables disappear when the loop ends.

## Filters

Write filters after a value, separated by `|`. Arguments go in parentheses; the pipeline value is already the filter's input. Filters run left to right, so `name | trim | upper` trims before changing case. Unknown filter names fail at compilation. Required missing arguments or an invalid truncate count fail during rendering.

| Filter | Behavior |
| --- | --- |
| `upper` | Uppercase the input's text form. |
| `lower` | Lowercase the input's text form. |
| `title` | Apply the String `title` operation to the text form. |
| `trim` | Remove surrounding whitespace from the text form. |
| `length` | Number of list elements or object members; otherwise the Unicode scalar length of the text form. |
| `join(separator)` | Convert each list element to text and join them; a nonlist input keeps its text form. |
| `json` | Serialize the input as compact JSON text. |
| `default(value)` | Keep a true-like input; otherwise evaluate and return the fallback. Allows a missing input. |
| `escape` | HTML-escape the text form. A final `escape` avoids a second automatic HTML escape. |
| `raw` | Preserve the input. As the final filter, disable automatic HTML escaping for this action. |
| `first` | First list element, or null for an empty list or nonlist value. |
| `last` | Last list element, or null for an empty list or nonlist value. |
| `reverse` | Reverse list order, or reverse the input's text form. |
| `keys` | Object keys as a list of strings; an empty list for a nonobject value. |
| `contains(value)` | For lists, test template equality with an element; for objects, test a key using the argument's text form; otherwise test a substring. |
| `replace(old, new)` | Replace occurrences in the input's text form; an empty `old` leaves the text unchanged. |
| `truncate(count)` | Keep at most `count` Unicode scalars and append `...` if shortened. The count must be a nonnegative integer. The suffix is additional to that count. |

Pass the documented arguments even where a filter tolerates extras. `default` uses template truthiness, so it replaces zero, false, and empty collections as well as missing values. Most other filter arguments are evaluated eagerly; a `default` fallback is evaluated only when needed.

## Partials

```text
{{ include "footer" }}
```

The expression after `include` resolves to a partial name. `render` looks it up in the supplied `partials` map; it does not read a file. A partial sees the current root and loop frames. Missing names return an error. Compile partials with the intended HTML setting: each compiled partial keeps the escaping decisions made during its own compilation.

## HTML and limits

`compile(source, html: true)` escapes printed values for HTML text and quoted attribute values. Literal template markup is unchanged. A final `raw` action trusts its data; it is appropriate only for markup you already trust. HTML escaping does not validate URL schemes or make a value safe inside JavaScript or CSS.

`render` defaults to strict missing-value handling and `max_output: 16777216`. The limit counts Unicode scalars in emitted text, after escaping, rather than UTF-8 bytes. Exceeding it returns `EOVERFLOW`. The engine also limits nesting in blocks and partials; use ordinary data iteration instead of recursively including templates without a bound.

`render` returns a completed string or an error. `render_to` renders first and writes only after rendering succeeds; a later stream-write failure can still occur. Handle the returned Result and the destination's flushing requirements separately.

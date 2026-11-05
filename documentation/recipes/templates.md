+++
title = "Render a text or HTML template"
weight = 2
+++

# Render a text or HTML template

A report often has stable presentation and changing data. Keep the presentation in a template and pass records or parsed JSON to it. The template engine can select and format values, repeat sections, and include partials; it cannot call arbitrary Manuscript functions.

This lesson builds on [JSON data](json.md) and [error propagation](../core-language/errors/propagation.md). It uses a file for the template so braces belong to the template syntax without needing escapes in a Manuscript string literal.

## Render a release announcement

Create `announcement.txt` with exactly this content, including a newline after the last line:

```text
{{ title }}
{{ for item in changes }}- {{ item }}
{{ else }}No changes.
{{ end }}
```

Save the following complete program as `announce.ms` in the same directory:

<!-- manuscript-example: {"mode":"run","files":{"announcement.txt":"{{ title }}\n{{ for item in changes }}- {{ item }}\n{{ else }}No changes.\n{{ end }}\n"},"stdout":"November release\n- CSV export\n- Faster search\n\n","cases":[{"files":{"announcement.txt":"{{ missing }}"},"stdout":"Could not render announcement\n","exit_code":1},{"files":{"announcement.txt":"{{ if title }}"},"stdout":"Could not render announcement\n","exit_code":1}]} -->
```manuscript
import read_file from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"
import compile, to_data from "@std/text/template.ms"

type Announcement:
    title: String
    changes: List[String]

fn run() Unit!:
    let bytes = try read_file("announcement.txt", max_bytes: 65536).wait()
    let source = try bytes.decode_utf8().ok_or(Error("template must be UTF-8"))
    let template = try compile(source)
    let announcement = Announcement(
        "November release", ["CSV export", "Faster search"]
    )
    let data = try to_data(announcement)
    let rendered = try template.render(data, max_output: 65536)
    try stdout().write(rendered)
    return stdout().flush().wait()

export fn main() Int:
    if run().is_error():
        print("Could not render announcement")
        return 1
    return 0
```

```sh
ms run announce.ms
```

The output is the announcement followed by a blank line:

```text
November release
- CSV export
- Faster search

```

`compile` checks template syntax once and returns a reusable `Template`. `to_data` converts a `Data` value into the `JsonValue` that templates read, following JSON encoding. Record fields become root names. `render` evaluates the template with that data and returns the completed text; the program then writes it. This keeps a failed render from producing half an announcement.

The loop binds `item` to each element of `changes`. Replace the list with `List[String]()` to exercise the `else` section, which prints `No changes.`. Literal newlines are copied, including the newline after `end`; that explains the final blank line. The trim markers `{{-` and `-}}` remove adjacent whitespace when the output format needs tighter control.

You can render the same compiled template with different data. Compile once outside a loop that generates many reports. The output limit applies to each render; it is separate from the file-read limit.

## Make missing-data policy visible

Printed paths are strict by default. Replacing the template with `{{ missing }}` makes rendering fail because the input has no such member. An unmatched `{{ if title }}` fails earlier, during compilation. Both failures travel through `try` to the application's exit-status decision.

For a field that is genuinely optional, put the choice in the template:

```text
{{ subtitle | default("Release announcement") }}
```

The `default` filter handles a missing or false-like value. Conditions treat missing paths as false; so do null, false, zero, empty text, and empty collections. A `default` is therefore broader than “member absent”: it also replaces an empty string or numeric zero. Use it when those values mean “no useful content” in your presentation.

Setting `strict: false` on `render` makes missing printed paths render empty text. That is useful for a deliberately sparse template, but it can also hide misspelled field names. Keep the default while developing a new template and choose fallbacks where the omission is intentional.

## Escape data when generating HTML

Text templates copy values as text. For HTML text and quoted attribute values, compile with `html: true`. Save this complete example as `html.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"<h1>Research &amp; development</h1>\n"} -->
```manuscript
import compile, to_data from "@std/text/template.ms"

type Heading:
    title: String

fn run() Unit!:
    let template = try compile("<h1>\{\{ title \}\}</h1>", html: true)
    let data = try to_data(Heading("Research & development"))
    print(try template.render(data))
    return ok(unit)

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
ms run html.ms
```

```html
<h1>Research &amp; development</h1>
```

The `<h1>` tags belong to trusted template source. The ampersand comes from data, so it is escaped. Here the template is inside a Manuscript string: `\{` and `\}` keep its braces literal instead of starting Manuscript interpolation.

A final `| raw` bypasses HTML escaping for that action. Use it only for markup you already trust, not for user-supplied content. HTML escaping is not URL validation or JavaScript/CSS escaping; choose how to validate and place values for those contexts separately.

## Grow a template without hiding logic

Dotted paths reach fields and list positions, such as `user.name` and `changes.0`. Filters such as `title`, `upper`, and `join(", ")` handle presentation. In loops, `loop.index`, `loop.first`, `loop.last`, and `loop.length` help with separators and labels. Conditions support comparisons and boolean operators; filters bind before those operators.

For shared sections, compile each partial and supply a `Map[String, Template]` through the `partials` argument to `render`. `{{ include "footer" }}` renders the named partial in the current scope; it does not load a file by itself. A missing partial returns an error. Keep application calculations in Manuscript and pass their results as data, where they can be checked and tested independently of the layout.

The [template API](../standard-library/reference/text/template.ms.md) lists the full syntax, filters, rendering limits, and `render_to` stream operation. For ordinary file and HTTP input, return to [task recipes](../learn/common-tasks.md).

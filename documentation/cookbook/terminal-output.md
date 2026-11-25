+++
title = "Tables and colors"
weight = 5
+++

# Tables and colors

Print aligned columns and color that turns itself off when the output is not a terminal.

## Align columns

Save as `report.ms`. A `Table` takes one alignment per column and pads every cell to the widest one, using display width, so wide characters line up.

`add` returns an error when a row has the wrong number of cells or a cell holds a control character. `render` returns the lines joined by `\n` with no final newline.

<!-- manuscript-example: {"mode":"run","stdout":"service   ms\nsearch   340\nhome      12\n"} -->
```manuscript
import Align, Table from "@std/cli/table.ms"

fn main() Void! {
    var table = Table(columns: [Align.Left, Align.Right])
    table.add(["service", "ms"])?
    table.add(["search", "340"])?
    table.add(["home", "12"])?
    print(table.render())
}
```

## Color only on a terminal

`styled` paints text for the current terminal and returns it unchanged when output is redirected to a file or pipe, when `NO_COLOR` is set, or when the terminal has no colors. A log that is piped to another tool therefore never holds escape codes. `paint(text, style, colors)` does the same for a color count you choose, which is useful in tests.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import Color, Style, styled from "@std/cli/style.ms"

fn main() Void {
    warn := Style(foreground: Color.Ansi(3), bold: true)
    print(styled("slow", warn))
}
```

- `Color` is `Default`, `Ansi(0..15)`, `Indexed(0..255)` or `Rgb(red, green, blue)`; a terminal with fewer colors gets the nearest one.
- `strip_ansi`, `visible_width`, `wrap_text` and `truncate_text` work on text that already holds escape codes.
- `terminal_capabilities()` in `@std/cli/terminal.ms` reports whether input and output are terminals and how many colors they support.

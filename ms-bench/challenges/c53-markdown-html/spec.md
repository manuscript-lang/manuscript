# Markdown to HTML

Write a converter from a subset of CommonMark (plus GitHub-style tables) to HTML. Standard input is the
Markdown document; standard output is the HTML. The rules below are an exact algorithm: follow them, not the
full CommonMark specification (they differ in several places on purpose). The exit status is 0.

Input is ASCII, contains no tab or carriage-return characters, and uses `\n` line endings. Split the input at
`\n`; if the text ends with `\n`, the empty piece after it is not a line. Empty input gives empty output. Every
block renders as text ending in `\n`; the output is the concatenation of the top-level blocks.

## Escaping

`esc(s)` replaces `&` with `&amp;`, `<` with `&lt;`, `>` with `&gt;`, `"` with `&quot;`. It is used for all text,
code, attribute values and info strings. There is no raw HTML and no entity recognition: `&copy;` renders as
`&amp;copy;`, `<b>` renders as `&lt;b&gt;`.

## Block structure

`parseBlocks(lines)` turns a list of lines into blocks; it is also applied recursively to the contents of block
quotes and list items. A *blank line* contains only spaces. *indent* is the number of leading spaces. Process
lines top to bottom; at each non-blank line try these constructs **in this order** (the first that matches wins):

1. **Fenced code.** indent <= 3, then a run of 3 or more identical `` ` `` or `~` characters (the fence), then the
   info string (rest of the line, trimmed of spaces). For backtick fences the info string must not contain a
   backtick, otherwise this is not a fence. Content lines follow up to a closing line: indent <= 3, a run of the same
   character at least as long as the opening fence, and only spaces after it. An unclosed fence runs to the end of the
   current line list. From each content line remove at most as many leading spaces as the opening fence's indent.
   Output `<pre><code>` (or `<pre><code class="language-W">` where W is `esc` of the first space-separated word of
   the info string, when there is one), then each content line escaped and followed by `\n`, then `</code></pre>\n`.
2. **ATX heading.** indent <= 3, 1 to 6 `#`, then a space or the end of the line. The content is the rest, trimmed of
   spaces on both sides; then, if the content ends with a run of `#` and that run is the whole content or is
   preceded by a space, remove the run and trim trailing spaces. Output `<hN>inline</hN>\n` (inline-processed content).
   `#######` (7), `#text`, are not headings.
3. **Thematic break.** indent <= 3, and after deleting all spaces the line is 3 or more of the same character
   from `-`, `*`, `_` and nothing else. Output `<hr />\n`.
4. **Block quote.** indent <= 3 followed by `>`. Take this line and all following consecutive lines that also start
   (indent <= 3) with `>`; from each remove the indent, the `>`, and one following space if present. Parse the
   result recursively. A blank line or any line without `>` ends the quote (there is no lazy continuation).
   Output `<blockquote>\n`, the contents, `</blockquote>\n`.
5. **List.** See below.
6. **Indented code.** indent >= 4. Take this line and all following lines that are blank or have indent >= 4;
   drop trailing blank lines; remove up to 4 leading spaces from each line. Output like fenced code without a class.
7. **Table.** See below.
8. **Paragraph.** Take this line, and then following lines while the next line is not blank, does not start a
   fenced code block, ATX heading, thematic break or block quote (rules 1-4 as tested for the line on its own), and is
   not a *list-interrupting marker* (a list marker per the list section whose item is not empty, and which, if it is an
   ordered marker, has the number 1). Everything else, including indented lines, continues the paragraph.
   Output `<p>` + inline + `</p>\n`. Paragraph text: for each line remove leading spaces; for the last line also remove
   trailing spaces; for other lines, if the line ends with two or more spaces it ends with a *hard break*, and in
   any case trailing spaces are removed; lines are joined with `\n`. A line ending in a single backslash (not the
   last line) is also a hard break (see inline).

There are no setext headings (`text` over `---` is a paragraph interrupted by a thematic break), no HTML blocks,
no link reference definitions.

### Lists

A *list marker line* has indent <= 3, then either a bullet (`-`, `*` or `+`) or an ordered marker (1 to 9
digits followed by `.` or `)`), then a space or the end of the line. Thematic break (rule 3) is tested before
lists, so `* * *` is a break. Let `M` be the marker's end column (indent + marker length). Count the spaces after
the marker: if the rest of the line is empty the item starts empty and `W = M + 1`; else if there are 5 or more
spaces, `W = M + 1` (the item starts with an indented code block); else `W = M + (number of spaces)`. The first
line of the item content is the line after its first `W` characters (empty for an empty item).

An item continues over the following lines: a blank line is tentatively included; a non-blank line with
indent >= W is included with its first `W` characters removed (and the tentatively included blank lines become empty
lines of the item); any other line ends the item. Trailing blank lines are dropped. The item's content lines are
parsed with `parseBlocks`.

After an item, look at the next non-blank line. If it is a list marker line (and not a thematic break) of the same
kind (same bullet character, or same ordered delimiter `.`/`)`) it starts the next item of the **same list**;
otherwise the list ends (a different bullet or delimiter starts a new list; a line that is not a marker ends it,
even if it would otherwise continue a paragraph: there is no lazy continuation).

A list is *loose* if any blank line separates two of its items, or if any item is loose; an item is loose if a blank
line separates two of its direct child blocks (blank lines inside a child block, such as inside fenced code or a
nested list, do not count; blank lines after the last child or before the first one do not count). Otherwise it is
tight.

Ordered lists start at the first item's number (later numbers are ignored). Output `<ul>\n` or `<ol>\n`
(`<ol start="N">\n` when N is not 1), the items, then `</ul>\n` or `</ol>\n`. An item renders as `<li>` + body +
`</li>\n`. The body is built by going through the item's child blocks in order: a paragraph inside a **tight** list
contributes only its inline HTML (no `<p>` tags, no newline); every other block (including paragraphs in a loose
list) is preceded by a `\n` unless the body built so far already ends with `\n` (a `\n` is also added when the body
is still empty), and then contributes its normal HTML. An empty item is `<li></li>`.
Examples: tight `<li>a</li>`; tight with nested list `<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>`; loose
`<li>\n<p>a</p>\n</li>`; `<li>\n<h1>x</h1>\n</li>`.

### Tables

At a line `L1` that matches none of rules 1-6, if the next line `L2` exists, `L1` contains a `|` and `L2` is a
*delimiter row*, and `L1` and `L2` split into the same number of cells, a table starts (a table never interrupts a
paragraph; tested only at the start of a block).

Cell splitting: trim the line of spaces; remove one leading `|`; remove one trailing `|` unless it is preceded by a
backslash; split at every `|` that is not preceded by a backslash; trim every cell of spaces. (A `\|` therefore stays in
the cell text as `\|` and the inline rules turn it into `|`.) A delimiter row contains a `|` and every cell is
`:?-+:?` (one or more `-`, optional colon on each side). Alignment: `:-` left, `:-:` center, `-:` right, `-` none.

Body rows: the following lines up to a blank line or a line that starts a fenced code block, ATX heading,
thematic break or block quote (but **not** a list). Each is split into cells; missing cells are empty, extra cells are
dropped. Output:

    <table>
    <thead>
    <tr>
    <th>cell</th>            (<th align="center"> etc. when aligned)
    </tr>
    </thead>
    <tbody>                  (the whole tbody is omitted when there are no body rows)
    <tr>
    <td>cell</td>
    </tr>
    </tbody>
    </table>

Cells are inline-processed (single line).

## Inline processing

`inline(text)` converts text (paragraph text, heading content, table cell) to HTML. It first builds a list of
nodes by scanning left to right, then resolves emphasis, then renders.

### Scan

At each position the first rule that applies:

1. `\` followed by `\n`: hard break. `\` followed by ASCII punctuation: that punctuation character as literal
   text. Otherwise a literal backslash.
2. A hard break at the end of a non-last paragraph line (two or more trailing spaces, or the backslash rule above)
   renders as `<br />\n`. For the two-space form, the position of the break counts as whitespace for emphasis
   flanking (the trailing spaces themselves are already removed). A plain line end between lines is a soft break and
   renders as `\n`.
3. A run of N backticks: find the next run of exactly N backticks later in the text. If found, a code span: content =
   the text between with each `\n` replaced by a space; if the content begins and ends with a space and is not all
   spaces, remove one space from each end. Renders as `<code>esc(content)</code>`; no escapes or other inline
   markup are processed inside. If no matching run exists, the backticks are literal text (the whole run).
4. A run of `*` or `_`: a *delimiter run* (see Emphasis).
5. `![` (image opener) or `[` (link opener): push a bracket marker.
6. `]`: look for the most recent bracket marker still in the node list. None: literal `]`. If found and it is a
   link opener that has been deactivated (see below): the marker becomes literal `[` and this is a literal `]`.
   Otherwise, if the next character is `(`, try to parse an inline link tail starting there:
   skip spaces/newlines; the destination is either `<` ... `>` (no newline or `<` inside; the destination is the
   content), or a run of characters up to a space/newline or an unbalanced `)`, in which parentheses must be balanced
   (a nested balanced pair is part of the destination); in both, `\` followed by punctuation stands for that
   punctuation. The destination may be empty. Then optionally (only if at least one space/newline was skipped) a title
   `"..."` (`\"` escapes; no other quote styles). Then optional spaces/newlines and `)`. If the tail parses, the nodes
   after the marker become the children of a link (or image) node whose emphasis is resolved separately (delimiters
   cannot match across a link boundary), the marker is replaced by that node, and scanning continues after `)`.
   After a *link* (not an image) is formed, every earlier link-opener marker still in the list is deactivated,
   so links never nest (images may appear inside links and links inside image text). If the tail does not parse, the marker
   becomes literal text (`[` or `![`) and the `]` is literal.
7. Anything else is literal text. Unmatched markers at the end become literal `[` or `![`.

Rendering: text -> `esc`; link -> `<a href="esc(dest)">children</a>` with ` title="esc(title)"` after the href when a
title was given (also when it is empty); image -> `<img src="esc(dest)" alt="esc(ALT)" />` with
` title="..."` between alt and `/>` when given, where ALT is the plain text of the children (text and code content
concatenated, soft/hard breaks as one space, no markup).

### Emphasis

For each delimiter run of character `c` (`*` or `_`) with length n, let *prev*/*next* be the characters just
before and after the run in the scanned text (start/end of text, a space, `\n`, or the hard-break sentinel count as
whitespace). Definitions: *left-flanking* = next is not whitespace, and (next is not ASCII punctuation or prev is whitespace or
punctuation). *right-flanking* = prev is not whitespace, and (prev is not punctuation or next is whitespace or punctuation).

- `*`: can open if left-flanking; can close if right-flanking.
- `_`: can open if left-flanking and (not right-flanking or prev is punctuation); can close if right-flanking and
  (not left-flanking or next is punctuation).

Resolution runs over a node list (the whole text, or the children of a link). Walk the list left to right; for each
delimiter node that can close: search backwards for the nearest delimiter node with the same character that can open,
still has characters left, and is allowed by the *multiple-of-3 rule*: if the opener can also close or the closer can
also open, then the sum of the two runs' **original** lengths must not be a multiple of 3 unless both original lengths
are multiples of 3 (otherwise skip that opener and keep searching backwards). If none is found, move on. If found: use
2 characters from each if both have at least 2 left, else 1. Everything between them becomes the children of a
`<strong>` (2) or `<em>` (1) node (any delimiter nodes inside are turned into literal text); the node is placed between
the opener's remaining characters and the closer's remaining characters (opener characters are consumed from its right
end, closer characters from its left end). A delimiter node with no characters left is removed. The same closer is
examined again if it still has characters. At the end, remaining delimiter nodes become literal text of their
remaining characters.

## Example

Input:

    # Hi *there*

    - a
    - b
      1. c

    | x | y |
    |---|--:|
    | 1 | 2 |

Output:

    <h1>Hi <em>there</em></h1>
    <ul>
    <li>a</li>
    <li>b
    <ol>
    <li>c</li>
    </ol>
    </li>
    </ul>
    <table>
    <thead>
    <tr>
    <th>x</th>
    <th align="right">y</th>
    </tr>
    </thead>
    <tbody>
    <tr>
    <td>1</td>
    <td align="right">2</td>
    </tr>
    </tbody>
    </table>

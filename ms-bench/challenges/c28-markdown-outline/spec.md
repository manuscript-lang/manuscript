# Markdown outline

Read a Markdown document from standard input and print a numbered outline of its headings.

A line is a *heading* when all of these hold:

- it begins, in column 0, with 1 to 6 `#` characters (a run of 7 or more `#` is not a heading);
- the `#` run is immediately followed by one or more space characters;
- after those spaces there is at least one non-space character.

The heading's *level* is the number of `#` characters. Its *title* is the rest of the line after the spaces,
with trailing spaces removed (any other characters, including further `#`, are kept).

Lines inside a fenced code block are never headings. A line that begins (in column 0) with three backticks
(```` ``` ````), with anything after them, opens a fence when none is open and closes it when one is open.
An unclosed fence lasts until the end of the input.

Numbering: keep six counters, one per level, all starting at 0. For a heading of level `L`, add 1 to counter
`L` and reset the counters of all deeper levels (`L+1` to 6) to 0. The heading's number is counters `1..L`
written in decimal and joined by `.` (levels that were skipped contribute `0`, so a `###` directly under a
`#` is numbered `1.0.1`).

Print one line per heading, in document order:

    <2 * (L - 1) spaces><number> <title>

Nothing is printed if there are no headings.

Example input:

    # Guide
    Intro text
    ## Install
    ```sh
    # not a heading
    ```
    ## Use
    ### Flags
    #hashtag
    # Appendix

Output:

    1 Guide
      1.1 Install
      1.2 Use
        1.2.1 Flags
    2 Appendix

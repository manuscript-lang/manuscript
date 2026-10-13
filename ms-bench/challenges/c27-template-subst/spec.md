# Template substitution

Standard input has two parts separated by the first line that is exactly `---`: variable definitions, then a
template. If there is no `---` line the whole input is definitions and nothing is printed.

## Definitions

Each definition line has the form `name=value`: split at the **first** `=`. The name must be a valid
identifier: a letter or underscore followed by letters, digits or underscores (ASCII only). The value is
everything after the `=`, kept exactly as written (no trimming; it may be empty or contain `=`). A line
without `=`, or whose name is not a valid identifier, is ignored. A later definition of the same name
replaces the earlier one.

## Template

Print every template line after substitution, in order (empty lines stay empty). A final newline ends the last line; it does not start another one, and every printed line ends with a newline. Scan each line left to right
at position `i`:

1. If the text at `i` is `{{`, output a single `{` and move forward 2.
2. Else if the text at `i` is `}}`, output a single `}` and move forward 2.
3. Else if the character at `i` is `{`: look for the next `}` after it. If one exists and the text between
   the braces is a valid identifier, replace `{name}` with the value of `name` (or with `<undefined:name>`
   when it is not defined) and continue after the `}`. Otherwise output the `{` literally and move forward 1.
4. Otherwise output the character and move forward 1.

Substituted values are not scanned again. A `}` that is not part of `}}` and not consumed by a placeholder is
output literally.

Example input:

    who=World
    greeting=Hello
    ---
    {greeting}, {who}!
    {{literal}} {missing} { oops }
    done

Output:

    Hello, World!
    {literal} <undefined:missing> { oops }
    done

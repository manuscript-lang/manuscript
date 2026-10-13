# Deque commands

Read commands from standard input, one per line, and apply them to a double-ended queue that starts empty.
Elements are non-empty tokens without whitespace (treat them as text; print them back exactly as given).
Tokens in a line are separated by single spaces. Blank lines are ignored.

| command | effect | output |
| --- | --- | --- |
| `push_back X` | add `X` at the back | none |
| `push_front X` | add `X` at the front | none |
| `pop_back` | remove the back element | the element, or `empty` if the deque is empty |
| `pop_front` | remove the front element | the element, or `empty` if the deque is empty |
| `back` | look at the back element without removing it | the element, or `empty` |
| `front` | look at the front element without removing it | the element, or `empty` |
| `size` | | the number of elements |
| `dump` | | `[` + elements from front to back joined by single spaces + `]`; `[]` when empty |

Every command that has an output prints it on its own line.

Example input:

    push_back a
    push_back b
    push_front c
    dump
    pop_back
    pop_front
    size
    pop_front
    pop_front

Output:

    [c a b]
    b
    c
    1
    a
    empty

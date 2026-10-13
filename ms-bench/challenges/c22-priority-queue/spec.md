# Priority queue

Read commands from standard input, one per line, and apply them to a priority queue that starts empty.
Each entry has an integer priority and a name (a non-empty token without whitespace). The entry with the
**lowest** priority comes out first; entries with equal priority come out in the order they were pushed
(first pushed, first out). Tokens in a line are separated by single spaces; blank lines are ignored.
Priorities are written as an optional `-` followed by digits (no leading `+`), and fit in 32 bits.

| command | effect | output |
| --- | --- | --- |
| `push P NAME` | add an entry with priority `P` | none |
| `pop` | remove the next entry | `NAME P`, or `empty` if the queue is empty |
| `peek` | look at the next entry without removing it | `NAME P`, or `empty` |
| `size` | | the number of entries |
| `drain` | remove every entry | one `NAME P` line per entry in pop order, or the single line `empty` if the queue was empty |

Print `P` as an integer (without leading zeros). Every output goes on its own line.

Example input:

    push 5 write
    push 1 plan
    push 5 test
    push 3 build
    pop
    peek
    size
    drain
    pop

Output:

    plan 1
    build 3
    3
    build 3
    write 5
    test 5
    empty

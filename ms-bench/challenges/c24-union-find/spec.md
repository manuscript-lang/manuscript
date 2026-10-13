# Union-find

The first non-blank line holds a single integer `N` (0 <= N <= 100000): the elements are the integers
`0` to `N-1`, and initially each is alone in its own set. Each following non-blank line is a command;
tokens are separated by single spaces.

| command | effect | output |
| --- | --- | --- |
| `union A B` | merge the sets containing `A` and `B` | `merged` if they were in different sets, otherwise `same` |
| `connected A B` | | `yes` if `A` and `B` are in the same set, otherwise `no` |
| `size A` | | the number of elements in the set containing `A` |
| `count` | | the current number of sets |

`A` and `B` are written as integers (an optional `-` followed by digits). If a command names an element
outside `0..N-1`, print `error` for that command and change nothing (check both arguments of `union` and
`connected` before doing anything). `count` never fails. Every command prints exactly one line.

Example input:

    5
    union 0 1
    union 1 2
    union 0 2
    connected 0 2
    connected 0 3
    size 1
    count
    size 9

Output:

    merged
    merged
    same
    yes
    no
    3
    3
    error

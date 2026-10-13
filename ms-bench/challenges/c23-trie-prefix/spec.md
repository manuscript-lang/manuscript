# Trie prefix queries

Maintain a dictionary of words and answer prefix queries. Read commands from standard input, one per line;
tokens are separated by single spaces and blank lines are ignored. Words and prefixes are non-empty
strings of lowercase ASCII letters `a-z`. The dictionary starts empty and holds *distinct* words
(inserting a word that is already present changes nothing).

| command | output |
| --- | --- |
| `insert WORD` | `added` if the word was new, otherwise `exists` |
| `has WORD` | `yes` or `no` (exact word) |
| `count PREFIX` | the number of dictionary words that start with `PREFIX` (a word is a prefix of itself) |
| `complete PREFIX K` | up to `K` words starting with `PREFIX`, in ascending byte order, joined by single spaces; `none` if no word matches. `K` is a positive integer |

Every command prints exactly one line.

Example input:

    insert car
    insert card
    insert care
    insert cat
    insert car
    count car
    count ca
    count d
    complete ca 3
    complete car 10
    complete x 2
    has cat
    has ca

Output:

    added
    added
    added
    added
    exists
    3
    4
    0
    car card care
    car card care
    none
    yes
    no

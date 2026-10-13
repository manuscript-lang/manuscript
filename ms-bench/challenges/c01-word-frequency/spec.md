# Word frequency

Read all of standard input as text. A *word* is a maximal run of ASCII letters (`a-z`, `A-Z`);
every other byte separates words. Words are case-insensitive: lowercase them.

Print the 10 most frequent words, one per line, as `<word> <count>`.
Order by count descending, then by word ascending (byte order). If there are fewer than
10 distinct words, print them all. Empty input prints nothing.

Example input:

    the cat and the hat

Output:

    the 2
    and 1
    cat 1
    hat 1

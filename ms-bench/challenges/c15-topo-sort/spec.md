# Dependency order

Each input line declares a task and what it depends on:

    <task>: <dep> <dep> ...

A *name* starts with a lowercase letter `a-z` followed by any number of lowercase letters, digits or
underscores. A valid line is a name immediately followed by `:`, then zero or more dependencies, each
written as one space followed by a name (so `build:` has no dependencies and `build: lint test` has two).
There are no other spaces: `a : b`, `a:b`, `a: b  c` and `a: b ` (trailing space) are all malformed. Lines
that are empty or contain only spaces are ignored.

Every name that appears anywhere, as a task or as a dependency, is a task of the graph. A task may be
declared on several lines; its dependencies are the union. Repeated dependencies count once. A task
depending on itself is a cycle.

Output:

- If any line is malformed, print `error: line N` where N is the 1-based physical line number (blank lines
  count) of the **first** malformed line, and nothing else.
- Otherwise, if the dependencies contain a cycle, print `cycle` and nothing else.
- Otherwise print every task, one per line, in an order where each task comes after all of its
  dependencies. When several tasks are ready, pick the one that is smallest in byte order, so the
  result is the lexicographically smallest valid order.
- If the input has no tasks at all, print nothing.

Example input:

    deploy: build test
    build: compile
    test: build
    compile:
    docs:

Output:

    compile
    build
    docs
    test
    deploy

+++
title = "Graphs and cycles"
weight = 11
+++

# Graphs and cycles

If you expect shared pointers, weak references, or reference counting, Manuscript has none. A value has one owner and a field owns what it holds, so a value cannot point back at its owner. Trees and singly linked lists work as [recursive data](named-types.md#recursive-data), and a tree [grows through a `fn var` method](named-types.md#growing-a-tree). For cycles, parent links, doubly linked lists and graphs, keep the nodes in one `List` and link them by position, an `Int`. An `Int` copies freely, so a cycle is just numbers.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
type Node:
    label: String
    edges: List[Int]
    parent: Int?

type Graph:
    nodes: List[Node]

fn var Graph.add(label: String) Int:
    self.nodes.append(Node(label: label, edges: [], parent: null))
    return self.nodes.length() - 1

fn var Graph.link(a: Int, b: Int) Void:
    self.nodes[a].edges.append(b)
    self.nodes[b].edges.append(a)
```

- The list owns every node, so there are no dangling pointers, and a cycle frees with the list.
- Index reads are bounds-checked.
- An index kept after a removal can name a different node, so mark a node dead instead of removing it, or update the edges that named it.
- Changing two nodes in one statement is rejected, because the checker cannot show that the indexes differ. Do one change, then the other.

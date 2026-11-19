+++
title = "Graphs and cycles"
weight = 11
+++

# Graphs and cycles

A value has one owner and a field owns what it holds, so a value cannot point back at its owner, and two values cannot point at each other. Trees and singly linked lists work as [recursive data](named-types.md#recursive-data). Cycles, parent links, doubly linked lists and general graphs need another shape. This page lists the options. Only the first ships today; the standard library has no arena or graph type yet.

## Keep nodes in a list and link by index

One owner holds every node in a `List`. A node names its neighbours by their position, an `Int`. An `Int` copies freely, so cycles and back-links are just numbers.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
type Node:
    label: String
    edges: List[Int]
    parent: Int?

type Graph:
    nodes: List[Node]

fn var Graph.add(label: String) Int:
    self.nodes.append(Node(label: label, edges: [], parent: none))
    return self.nodes.length() - 1

fn var Graph.link(a: Int, b: Int) Void:
    self.nodes[a].edges.append(b)
    self.nodes[b].edges.append(a)
```

- Reads borrow: `graph.nodes[i].label` keeps `graph` unchangeable while the borrow lives.
- Changing two nodes at once is rejected, because the checker cannot show that `i` and `j` differ. Read what you need, end the borrow, then change the other node.
- Removing a node moves later positions. Mark a node dead instead, or swap the last node into its place and update the edges that named it.

**Safety.** No dangling pointers and no leaks on cycles: the list owns every node and frees them together. Every index read is bounds-checked and faults when out of range. Nothing stops a stale index (an index kept after a removal) from naming a different live node.

## Generational handles (not shipped)

A handle is an index plus a counter. A slot's counter grows each time the slot is freed, so a lookup with an old handle finds a mismatch and returns `none` instead of the wrong node. A per-arena id in the handle also rejects a handle from another arena. This would be an `Arena[T]` written in Manuscript on top of `List`, with no compiler change. It is a design only.

**Safety.** Adds use-after-remove and wrong-arena detection to the index approach. It does not detect logic errors, such as an edge to a node you meant to delete; the lookup fails safely with `none`. Each lookup costs one counter comparison.

## Alternatives and their trade-offs

| Option | Pros | Cons |
| --- | --- | --- |
| Index into a list | Ships today. No new rules. Flat and cache-friendly. | Stale indexes are not detected. Removal needs care. |
| Generational handles | Detects stale and wrong-arena handles. Fits the one-owner model. | Not built. Slightly larger handles and a check per lookup. |
| Map from key to node | Natural for named nodes. Removal is simple. | Hashing cost. Keys can still go stale. |
| Reference counting | Familiar shared ownership. | Breaks the one-owner model. Cycles leak. |
| Weak or raw references in the language | Direct parent and back pointers. | A large language change. Weakens the borrow checker's guarantees. |

Prefer the first option today and move to handles when they ship.

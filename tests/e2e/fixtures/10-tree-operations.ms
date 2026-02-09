// @test: Tree Operations
import { max } from "std/math"

type Node
  value: number
  left: Node?
  right: Node?

fn node(val: number, left: Node?, right: Node?): Node
  Node(val, left, right)

fn tree_sum(n: Node?): number
  if n == null then 0 else n.value + tree_sum(n.left) + tree_sum(n.right)

fn tree_height(n: Node?): number
  if n == null then 0 else 1 + max(tree_height(n.left), tree_height(n.right))

fn tree_count(n: Node?): number
  if n == null then 0 else 1 + tree_count(n.left) + tree_count(n.right)

// Build tree:
//     5
//    / \
//   3   7
//  / \
// 1   4

let tree: Node = node(5, node(3, node(1, null, null), node(4, null, null)), node(7, null, null))

// @expect: 20
print(tree_sum(tree))
// @expect: 3
print(tree_height(tree))
// @expect: 5
print(tree_count(tree))

// === Tree contains ===
fn tree_contains(n: Node?, val: number): bool
  if n == null then false else (if n.value == val then true else (tree_contains(n.left, val) or tree_contains(n.right, val)))

// @expect: true
print(tree_contains(tree, 4))
// @expect: false
print(tree_contains(tree, 10))

// @test: Tree Operations

type Node
  value: number
  left: Node?
  right: Node?

fn node(val: number, left: Node?, right: Node?): Node
  Node(val, left, right)

fn tree_sum(n: Node?): number
  if n == null then return 0
  let node = n as Node
  node.value + tree_sum(node.left) + tree_sum(node.right)

fn tree_height(n: Node?): number
  if n == null then return 0
  let node = n as Node
  1 + max(tree_height(node.left), tree_height(node.right))

fn tree_count(n: Node?): number
  if n == null then return 0
  let node = n as Node
  1 + tree_count(node.left) + tree_count(node.right)

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
  if n == null then return false
  let node = n as Node
  if node.value == val then return true
  tree_contains(node.left, val) or tree_contains(node.right, val)

// @expect: true
print(tree_contains(tree, 4))
// @expect: false
print(tree_contains(tree, 10))

// === Tree min/max ===
fn tree_min(n: Node?): number?
  if n == null then return null
  var curr: Node? = n
  for
    if curr == null then return null
    let node = curr as Node
    if node.left == null then return node.value
    curr = node.left

fn tree_max(n: Node?): number?
  if n == null then return null
  var curr: Node? = n
  for
    if curr == null then return null
    let node = curr as Node
    if node.right == null then return node.value
    curr = node.right

// @expect: 1
print(tree_min(tree))
// @expect: 7
print(tree_max(tree))

// === Level order (BFS) ===
fn level_order(root: Node?): list[number]
  if root == null then return [] as list[number]
  var result = [] as list[number]
  var queue = [root]
  for
    if len(queue) == 0 then break
    let nd = queue.shift() as Node
    result.push(nd.value)
    if nd.left != null
      queue.push(nd.left)
    if nd.right != null
      queue.push(nd.right)
  result

// @expect: [5, 3, 7, 1, 4]
print(level_order(tree))

// === In-order traversal ===
fn inorder(root: Node?): list[number]
  var result = [] as list[number]
  var stack = [] as list[Node]
  var curr = root
  for
    for
      if curr == null then break
      let node = curr as Node
      stack.push(node)
      curr = node.left
    if len(stack) == 0 then break
    curr = stack.pop() as Node
    result.push(curr.value as number)
    curr = curr.right as Node?
  result

// @expect: [1, 3, 4, 5, 7]
print(inorder(tree))

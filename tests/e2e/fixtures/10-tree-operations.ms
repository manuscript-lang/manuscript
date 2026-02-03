// @test: Tree Operations

// === Tree as map ===
fn node(val: number, left, right)
  {value: val, left: left, right: right}

fn tree_sum(n): number
  if n == null then return 0
  n.value + tree_sum(n.left) + tree_sum(n.right)

fn tree_height(n): number
  if n == null then return 0
  1 + max(tree_height(n.left), tree_height(n.right))

fn tree_count(n): number
  if n == null then return 0
  1 + tree_count(n.left) + tree_count(n.right)

// Build tree:
//     5
//    / \
//   3   7
//  / \
// 1   4

let tree = node(5, node(3, node(1, null, null), node(4, null, null)), node(7, null, null))

// @expect: 20
print(tree_sum(tree))
// @expect: 3
print(tree_height(tree))
// @expect: 5
print(tree_count(tree))

// === Tree contains ===
fn tree_contains(n, val: number): bool
  if n == null then return false
  if n.value == val then return true
  tree_contains(n.left, val) or tree_contains(n.right, val)

// @expect: true
print(tree_contains(tree, 4))
// @expect: false
print(tree_contains(tree, 10))

// === Tree min/max ===
fn tree_min(n)
  if n == null then return null
  var curr = n
  for
    if curr.left == null then return curr.value
    curr = curr.left

fn tree_max(n)
  if n == null then return null
  var curr = n
  for
    if curr.right == null then return curr.value
    curr = curr.right

// @expect: 1
print(tree_min(tree))
// @expect: 7
print(tree_max(tree))

// === Level order (BFS) ===
fn level_order(root)
  if root == null then return []
  var result = []
  var queue = [root]
  for
    if len(queue) == 0 then break
    let nd = queue.shift()
    result.push(nd.value)
    if nd.left != null
      queue.push(nd.left)
    if nd.right != null
      queue.push(nd.right)
  result

// @expect: [5, 3, 7, 1, 4]
print(level_order(tree))

// === In-order traversal ===
fn inorder(root)
  var result = []
  var stack = []
  var curr = root
  for
    for
      if curr == null then break
      stack.push(curr)
      curr = curr.left
    if len(stack) == 0 then break
    curr = stack.pop()
    result.push(curr.value)
    curr = curr.right
  result

// @expect: [1, 3, 4, 5, 7]
print(inorder(tree))

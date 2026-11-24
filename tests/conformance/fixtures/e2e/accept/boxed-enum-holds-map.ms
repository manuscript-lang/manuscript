// conform: tags=alternatives,maps,match,tier-core,testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Index:
	name String
	words Map[String, Int]

// A self-containing enum keeps its payload in a heap block, so a map, a set and a record that
// holds a map have to move between their memory and the block's slots in every backend.
enum Tree:
	Leaf(v Int)
	Node(left Tree, right Tree)
	Named(m Map[String, Tree])
	Seen(s Set[Int])
	Held(index Index)

fn size(t Tree) Int:
	match t:
		Leaf(v):
			return v
		Node(l, r):
			return size(l) + size(r)
		Named(m):
			var n = 0
			for k in m.keys():
				n += size(m.get_or(k, Tree.Leaf(0)))
			return n
		Seen(s):
			return s.length()
		Held(index):
			return index.words.get_or(index.name, 0)

fn build() Tree:
	var m = Map[String, Tree]()
	m.add("a", Tree.Leaf(3))
	m.add("b", Tree.Node(Tree.Leaf(4), Tree.Leaf(5)))
	var s = Set[Int]()
	s.add(1)
	s.add(2)
	var words = Map[String, Int]()
	words.add("x", 10)
	return Tree.Node(
		Tree.Node(Tree.Named(m), Tree.Seen(s)),
		Tree.Held(Index(name: "x", words: words)),
	)

test "a map, a set and a record with a map live in a self-containing enum":
	expect_equal(size(build()), 3 + 9 + 2 + 10)?

test "cloning a self-containing enum copies its maps":
	tree := build()
	copy := tree.clone()
	expect_equal(size(copy), size(tree))?

package main

import "fmt"

type Node struct {
	key         int
	left, right *Node
}

func lcg(x int) int { return (x*1103515245 + 12345) % 2147483648 }

func (n *Node) insert(key int) {
	if key == n.key {
		return
	}
	slot := &n.right
	if key < n.key {
		slot = &n.left
	}
	if *slot == nil {
		*slot = &Node{key: key}
		return
	}
	(*slot).insert(key)
}

func (n *Node) count() int {
	t := 1
	if n.left != nil {
		t += n.left.count()
	}
	if n.right != nil {
		t += n.right.count()
	}
	return t
}

func (n *Node) height() int {
	lh, rh := 0, 0
	if n.left != nil {
		lh = n.left.height()
	}
	if n.right != nil {
		rh = n.right.height()
	}
	if lh > rh {
		return 1 + lh
	}
	return 1 + rh
}

func (n *Node) sum() int {
	t := n.key
	if n.left != nil {
		t += n.left.sum()
	}
	if n.right != nil {
		t += n.right.sum()
	}
	return t
}

type Tree struct{ left, right *Tree }

func make_(depth int) *Tree {
	if depth == 0 {
		return nil
	}
	return &Tree{make_(depth - 1), make_(depth - 1)}
}

func count(t *Tree) int {
	if t == nil {
		return 1
	}
	return 1 + count(t.left) + count(t.right)
}

type Link struct {
	value int
	next  *Link
}

func main() {
	root := &Node{key: 1000000000}
	x := 11
	for i := 0; i < 400000; i++ {
		x = lcg(x)
		root.insert(x % 2000000000)
	}
	fmt.Printf("bst %d %d %d\n", root.count(), root.height(), root.sum()%1000003)

	nodes := 0
	for r := 0; r < 40; r++ {
		nodes += count(make_(16))
	}
	fmt.Printf("trees %d\n", nodes)

	var head *Link
	for i := 0; i < 1000000; i++ {
		head = &Link{i, head}
	}
	total := 0
	for c := head; c != nil; c = c.next {
		total += c.value
	}
	fmt.Printf("list %d\n", total)
}

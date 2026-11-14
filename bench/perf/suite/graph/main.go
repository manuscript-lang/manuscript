package main

import (
	"container/heap"
	"fmt"
)

type Edge struct{ to, w int }

type Item struct{ dist, node int }
type PQ []Item

func (p PQ) Len() int            { return len(p) }
func (p PQ) Less(i, j int) bool  { return p[i].dist < p[j].dist || (p[i].dist == p[j].dist && p[i].node < p[j].node) }
func (p PQ) Swap(i, j int)       { p[i], p[j] = p[j], p[i] }
func (p *PQ) Push(x interface{}) { *p = append(*p, x.(Item)) }
func (p *PQ) Pop() interface{} {
	old := *p
	n := len(old)
	x := old[n-1]
	*p = old[:n-1]
	return x
}

func lcg(x int) int { return (x*1103515245 + 12345) % 2147483648 }

func build(n, m int) [][]Edge {
	adj := make([][]Edge, n)
	x := 7
	for i := 0; i < m; i++ {
		x = lcg(x)
		a := x % n
		x = lcg(x)
		b := x % n
		x = lcg(x)
		w := 1 + x%100
		adj[a] = append(adj[a], Edge{b, w})
		adj[b] = append(adj[b], Edge{a, w})
	}
	return adj
}

func bfs(adj [][]Edge, start int) int {
	level := make([]int, len(adj))
	for i := range level {
		level[i] = -1
	}
	queue := []int{start}
	level[start] = 0
	reached, depthSum := 0, 0
	for head := 0; head < len(queue); head++ {
		u := queue[head]
		reached++
		depthSum += level[u]
		for _, e := range adj[u] {
			if level[e.to] < 0 {
				level[e.to] = level[u] + 1
				queue = append(queue, e.to)
			}
		}
	}
	return reached*1000 + depthSum%1000
}

func dijkstra(adj [][]Edge, start int) int {
	dist := make([]int, len(adj))
	for i := range dist {
		dist[i] = 1000000000
	}
	pq := &PQ{}
	dist[start] = 0
	heap.Push(pq, Item{0, start})
	for pq.Len() > 0 {
		it := heap.Pop(pq).(Item)
		if it.dist > dist[it.node] {
			continue
		}
		for _, e := range adj[it.node] {
			nd := it.dist + e.w
			if nd < dist[e.to] {
				dist[e.to] = nd
				heap.Push(pq, Item{nd, e.to})
			}
		}
	}
	total, far := 0, 0
	for _, d := range dist {
		if d < 1000000000 {
			total += d
			if d > far {
				far = d
			}
		}
	}
	return total%1000003*1000 + far
}

func find(parent []int, x int) int {
	r := x
	for parent[r] != r {
		r = parent[r]
	}
	return r
}

func components(n, m int) int {
	parent := make([]int, n)
	for i := range parent {
		parent[i] = i
	}
	x, count := 99, n
	for i := 0; i < m; i++ {
		x = lcg(x)
		a := find(parent, x%n)
		x = lcg(x)
		b := find(parent, x%n)
		if a != b {
			parent[a] = b
			count--
		}
	}
	return count
}

func main() {
	n := 200000
	adj := build(n, 800000)
	fmt.Printf("bfs %d\n", bfs(adj, 0))
	fmt.Printf("dijkstra %d\n", dijkstra(adj, 0))
	fmt.Printf("components %d\n", components(n, 150000))
}

package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
)

type point struct{ r, c int }

func main() {
	data, err := io.ReadAll(bufio.NewReader(os.Stdin))
	if err != nil {
		fmt.Println("error: no start")
		return
	}
	fmt.Println(solve(string(data)))
}

func solve(input string) string {
	lines := strings.Split(input, "\n")
	for i, l := range lines {
		lines[i] = strings.TrimSuffix(l, "\r")
	}
	// Trailing empty lines are ignored (this also drops the piece after a final newline).
	for len(lines) > 0 && lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	if len(lines) == 0 {
		return "error: no start"
	}

	grid := make([][]rune, len(lines))
	for i, l := range lines {
		grid[i] = []rune(l)
	}

	// 1. Bad characters, in reading order.
	for r, row := range grid {
		for c, ch := range row {
			switch ch {
			case '#', '.', 'S', 'E':
			default:
				return fmt.Sprintf("error: bad character at %d,%d", r+1, c+1)
			}
		}
	}

	// 2. Ragged rows.
	width := len(grid[0])
	for _, row := range grid {
		if len(row) != width {
			return "error: ragged grid"
		}
	}

	// 3 & 4. Start and end counts.
	var starts, ends []point
	for r, row := range grid {
		for c, ch := range row {
			switch ch {
			case 'S':
				starts = append(starts, point{r, c})
			case 'E':
				ends = append(ends, point{r, c})
			}
		}
	}
	switch {
	case len(starts) == 0:
		return "error: no start"
	case len(starts) > 1:
		return "error: multiple starts"
	}
	switch {
	case len(ends) == 0:
		return "error: no end"
	case len(ends) > 1:
		return "error: multiple ends"
	}

	// BFS over non-wall cells.
	h := len(grid)
	dist := make([][]int, h)
	for r := range dist {
		dist[r] = make([]int, width)
		for c := range dist[r] {
			dist[r][c] = -1
		}
	}
	s, e := starts[0], ends[0]
	dist[s.r][s.c] = 0
	queue := []point{s}
	dirs := [4]point{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
	for len(queue) > 0 {
		p := queue[0]
		queue = queue[1:]
		if p == e {
			return fmt.Sprint(dist[p.r][p.c])
		}
		for _, d := range dirs {
			nr, nc := p.r+d.r, p.c+d.c
			if nr < 0 || nr >= h || nc < 0 || nc >= width {
				continue
			}
			if grid[nr][nc] == '#' || dist[nr][nc] >= 0 {
				continue
			}
			dist[nr][nc] = dist[p.r][p.c] + 1
			queue = append(queue, point{nr, nc})
		}
	}
	return "no path"
}

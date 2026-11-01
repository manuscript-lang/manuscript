package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

// op is one entry of the edit script.
type op struct {
	kind byte // ' ' unchanged, '-' deletion, '+' insertion
	text string
}

// readLine returns the next line without its terminator. Missing lines at
// EOF are returned as empty strings.
func readLine(r *bufio.Reader) string {
	s, err := r.ReadString('\n')
	if err != nil && err != io.EOF {
		return s
	}
	s = strings.TrimSuffix(s, "\n")
	s = strings.TrimSuffix(s, "\r")
	return s
}

func rangeStr(start, length int) string {
	if length == 1 {
		return strconv.Itoa(start)
	}
	return fmt.Sprintf("%d,%d", start, length)
}

func main() {
	r := bufio.NewReaderSize(os.Stdin, 1<<20)
	w := bufio.NewWriterSize(os.Stdout, 1<<20)
	defer w.Flush()

	header := strings.Fields(readLine(r))
	if len(header) < 5 {
		return
	}
	nameA, nameB := header[0], header[1]
	ctx, _ := strconv.Atoi(header[2])
	n, _ := strconv.Atoi(header[3])
	m, _ := strconv.Atoi(header[4])

	a := make([]string, n)
	for i := range a {
		a[i] = readLine(r)
	}
	b := make([]string, m)
	for j := range b {
		b[j] = readLine(r)
	}

	// L[i*(m+1)+j] = LCS length of a[i..] and b[j..].
	W := m + 1
	L := make([]int32, (n+1)*W)
	for i := n - 1; i >= 0; i-- {
		for j := m - 1; j >= 0; j-- {
			if a[i] == b[j] {
				L[i*W+j] = L[(i+1)*W+j+1] + 1
			} else {
				x := L[(i+1)*W+j]
				y := L[i*W+j+1]
				if x >= y {
					L[i*W+j] = x
				} else {
					L[i*W+j] = y
				}
			}
		}
	}
	lcs := func(i, j int) int32 { return L[i*W+j] }

	// Walk the edit script.
	var ops []op
	i, j := 0, 0
	for {
		if i == n && j == m {
			break
		}
		if i < n && j < m && a[i] == b[j] {
			ops = append(ops, op{' ', a[i]})
			i++
			j++
		} else if j == m || (i < n && lcs(i+1, j) >= lcs(i, j+1)) {
			ops = append(ops, op{'-', a[i]})
			i++
		} else {
			ops = append(ops, op{'+', b[j]})
			j++
		}
	}

	// Find changes.
	var changes []int
	for k, o := range ops {
		if o.kind != ' ' {
			changes = append(changes, k)
		}
	}
	if len(changes) == 0 {
		return
	}

	// Prefix counts of lines of A and B consumed before each script position.
	oldPre := make([]int, len(ops)+1)
	newPre := make([]int, len(ops)+1)
	for k, o := range ops {
		oldPre[k+1] = oldPre[k]
		newPre[k+1] = newPre[k]
		if o.kind == ' ' || o.kind == '-' {
			oldPre[k+1]++
		}
		if o.kind == ' ' || o.kind == '+' {
			newPre[k+1]++
		}
	}

	fmt.Fprintf(w, "--- %s\n", nameA)
	fmt.Fprintf(w, "+++ %s\n", nameB)

	emit := func(first, last int) {
		s := first - ctx
		if s < 0 {
			s = 0
		}
		e := last + ctx
		if e > len(ops)-1 {
			e = len(ops) - 1
		}
		la := oldPre[e+1] - oldPre[s]
		lb := newPre[e+1] - newPre[s]
		sa := oldPre[s]
		if la > 0 {
			sa++
		}
		sb := newPre[s]
		if lb > 0 {
			sb++
		}
		fmt.Fprintf(w, "@@ -%s +%s @@\n", rangeStr(sa, la), rangeStr(sb, lb))
		for k := s; k <= e; k++ {
			fmt.Fprintf(w, "%c%s\n", ops[k].kind, ops[k].text)
		}
	}

	start, last := changes[0], changes[0]
	for _, c := range changes[1:] {
		gap := c - last - 1
		if gap <= 2*ctx {
			last = c
		} else {
			emit(start, last)
			start, last = c, c
		}
	}
	emit(start, last)
}

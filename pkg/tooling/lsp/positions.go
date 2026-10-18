package lsp

import (
	"sort"
	"strings"
)

// sourcePositions indexes original line starts once for a batch of conversions.
// UTF-16 columns are counted within the selected line, without per-byte tables.
type sourcePositions struct {
	source string
	starts []int
}

func newSourcePositions(source string) sourcePositions {
	starts := make([]int, 1, strings.Count(source, "\n")+1)
	for at := 0; at < len(source); {
		next := strings.IndexByte(source[at:], '\n')
		if next < 0 {
			break
		}
		at += next + 1
		starts = append(starts, at)
	}
	return sourcePositions{source, starts}
}

func (s sourcePositions) position(offset int) position {
	if offset < 0 {
		offset = 0
	}
	if offset > len(s.source) {
		offset = len(s.source)
	}
	line := sort.Search(len(s.starts), func(i int) bool { return s.starts[i] > offset }) - 1
	return position{line, utf16Length(s.source[s.starts[line]:offset])}
}

func utf16Length(text string) int {
	length := 0
	for _, r := range text {
		length += utf16RuneWidth(r)
	}
	return length
}

func utf16RuneWidth(r rune) int {
	if r > 0xffff {
		return 2
	}
	return 1
}

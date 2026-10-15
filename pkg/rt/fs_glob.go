// Glob matching for filesystem globbing. The path module owns path.matches_glob;
// this matcher is the one the filesystem operations have always used.

package rt

import (
	"path"
	"strconv"
	"strings"
	"unicode/utf8"
)

type fsGlobAtom struct {
	kind         byte
	text         string
	alternatives [][]fsGlobAtom
}

func fsGlobSequence(pattern string) ([]fsGlobAtom, bool) {
	var atoms []fsGlobAtom
	for len(pattern) > 0 {
		ch := pattern[0]
		if strings.ContainsRune("@+?!*", rune(ch)) && len(pattern) > 1 && pattern[1] == '(' {
			opener, closer, separator, kind := byte('('), byte(')'), byte('|'), ch
			start := 2
			depth := 1
			end := start
			for end < len(pattern) && depth > 0 {
				if pattern[end] == opener {
					depth++
				}
				if pattern[end] == closer {
					depth--
				}
				if depth > 0 {
					end++
				}
			}
			if depth != 0 {
				return nil, false
			}
			inside := pattern[start:end]
			var parts []string
			at, nested := 0, 0
			for i := 0; i < len(inside); i++ {
				switch inside[i] {
				case '(':
					nested++
				case ')':
					nested--
				default:
					if inside[i] == separator && nested == 0 {
						parts = append(parts, inside[at:i])
						at = i + 1
					}
				}
			}
			parts = append(parts, inside[at:])

			alternatives := make([][]fsGlobAtom, 0, len(parts))
			for _, part := range parts {
				sequence, ok := fsGlobSequence(part)
				if !ok {
					return nil, false
				}
				alternatives = append(alternatives, sequence)
			}
			atoms = append(atoms, fsGlobAtom{kind: kind, alternatives: alternatives})
			pattern = pattern[end+1:]
			continue
		}
		switch ch {
		case '*':
			atoms = append(atoms, fsGlobAtom{kind: 's'})
			pattern = pattern[1:]
		case '?':
			atoms = append(atoms, fsGlobAtom{kind: 'q'})
			pattern = pattern[1:]
		case '[':
			end := strings.IndexByte(pattern, ']')
			if end < 0 {
				return nil, false
			}
			token := pattern[:end+1]
			if strings.HasPrefix(token, "[!") {
				token = "[^" + token[2:]
			}
			if _, err := path.Match(token, "a"); err != nil {
				return nil, false
			}
			atoms = append(atoms, fsGlobAtom{kind: 'c', text: token})
			pattern = pattern[end+1:]
		case '\\':
			if len(pattern) < 2 {
				return nil, false
			}
			_, size := utf8.DecodeRuneInString(pattern[1:])
			atoms = append(atoms, fsGlobAtom{kind: 'l', text: pattern[1 : 1+size]})
			pattern = pattern[1+size:]
		default:
			_, size := utf8.DecodeRuneInString(pattern)
			atoms = append(atoms, fsGlobAtom{kind: 'l', text: pattern[:size]})
			pattern = pattern[size:]
		}
	}
	return atoms, true
}
func fsGlobEnds(atoms []fsGlobAtom, value []rune, start int) map[int]bool {
	positions := map[int]bool{start: true}
	for _, atom := range atoms {
		next := map[int]bool{}
		if atom.kind == 's' {
			// A star reaches every position from the earliest start onward, so
			// later starts add nothing. Expanding each start separately made a
			// run of stars quadratic in the segment length.
			earliest := len(value) + 1
			for at := range positions {
				earliest = min(earliest, at)
			}
			for i := earliest; i <= len(value); i++ {
				next[i] = true
			}
			positions = next
			if len(positions) == 0 {
				break
			}
			continue
		}
		for at := range positions {
			switch atom.kind {
			case 'l':
				if at < len(value) && string(value[at]) == atom.text {
					next[at+1] = true
				}
			case 'q':
				if at < len(value) {
					next[at+1] = true
				}
			case 'c':
				if at < len(value) {
					matched, _ := path.Match(atom.text, string(value[at]))
					if matched {
						next[at+1] = true
					}
				}
			default:
				accepted := map[int]bool{}
				for _, alternative := range atom.alternatives {
					for end := range fsGlobEnds(alternative, value, at) {
						accepted[end] = true
					}
				}
				if atom.kind == '!' {
					for end := at; end <= len(value); end++ {
						if !accepted[end] {
							next[end] = true
						}
					}
					continue
				}
				for end := range accepted {
					next[end] = true
				}
				if atom.kind == '?' || atom.kind == '*' {
					next[at] = true
				}
				if atom.kind == '+' || atom.kind == '*' {
					queue := make([]int, 0, len(accepted))
					seen := map[int]bool{at: true}
					for end := range accepted {
						if !seen[end] {
							queue = append(queue, end)
							seen[end] = true
						}
					}
					for len(queue) > 0 {
						position := queue[0]
						queue = queue[1:]
						for _, alternative := range atom.alternatives {
							for end := range fsGlobEnds(alternative, value, position) {
								next[end] = true
								if !seen[end] {
									seen[end] = true
									queue = append(queue, end)
								}
							}
						}
					}
				}
			}
		}
		positions = next
		if len(positions) == 0 {
			break
		}
	}
	return positions
}
func fsValidGlob(pattern string) bool {
	if len(pattern) > 4096 || strings.ContainsRune(pattern, 0) {
		return false
	}
	patterns, ok := fsExpandBraces(pattern)
	if !ok {
		return false
	}
	for _, pattern := range patterns {
		for _, part := range strings.Split(pattern, "/") {
			if part == "**" {
				continue
			}
			if _, ok := fsGlobSequence(part); !ok {
				return false
			}
		}
	}
	return true
}
func fsGlobMatch(value, pattern string) bool {
	patterns, ok := fsExpandBraces(pattern)
	if !ok {
		return false
	}
	for _, pattern := range patterns {
		if fsGlobMatchSegments(value, pattern) {
			return true
		}
	}
	return false
}
func fsGlobMatchSegments(value, pattern string) bool {
	vs, ps := strings.Split(value, "/"), strings.Split(pattern, "/")
	previous := make([]bool, len(vs)+1)
	previous[0] = true
	for _, part := range ps {
		next := make([]bool, len(vs)+1)
		if part == "**" {
			next[0] = previous[0]
			for j := 1; j <= len(vs); j++ {
				next[j] = previous[j] || next[j-1] && !strings.HasPrefix(vs[j-1], ".")
			}
		} else {
			atoms, ok := fsGlobSequence(part)
			if !ok {
				return false
			}
			for j := 1; j <= len(vs); j++ {
				if previous[j-1] && (!strings.HasPrefix(vs[j-1], ".") || strings.HasPrefix(part, ".")) {
					next[j] = fsGlobEnds(atoms, []rune(vs[j-1]), 0)[len([]rune(vs[j-1]))]
				}
			}
		}
		previous = next
	}
	return previous[len(vs)]
}

// Brace expansion runs before segmentation, allowing alternatives to cross
// directory boundaries. The expansion bound avoids combinatorial allocation.
func fsExpandBraces(pattern string) ([]string, bool) {
	open := -1
	escaped, bracket := false, false
	for i := 0; i < len(pattern); i++ {
		ch := pattern[i]
		if escaped {
			escaped = false
			continue
		}
		if ch == '\\' {
			escaped = true
			continue
		}
		if ch == '[' {
			bracket = true
		}
		if ch == ']' {
			bracket = false
		}
		if ch == '{' && !bracket {
			open = i
			break
		}
	}
	if open < 0 {
		return []string{pattern}, true
	}
	depth := 1
	end := open + 1
	for end < len(pattern) && depth > 0 {
		if pattern[end] == '{' {
			depth++
		}
		if pattern[end] == '}' {
			depth--
		}
		if depth > 0 {
			end++
		}
	}
	if depth != 0 {
		return nil, false
	}
	inside := pattern[open+1 : end]
	parts := []string{}
	at, nested := 0, 0
	for i := 0; i < len(inside); i++ {
		if inside[i] == '{' {
			nested++
		}
		if inside[i] == '}' {
			nested--
		}
		if inside[i] == ',' && nested == 0 {
			parts = append(parts, inside[at:i])
			at = i + 1
		}
	}
	parts = append(parts, inside[at:])
	if len(parts) == 1 {
		fields := strings.Split(inside, "..")
		if len(fields) == 1 {
			tails, ok := fsExpandBraces(pattern[end+1:])
			if !ok {
				return nil, false
			}
			for i := range tails {
				tails[i] = pattern[:end+1] + tails[i]
			}
			return tails, true
		}
		if len(fields) < 2 || len(fields) > 3 {
			return nil, false
		}
		step := 1
		if len(fields) == 3 {
			n, err := strconv.Atoi(fields[2])
			if err != nil || n == 0 {
				return nil, false
			}
			step = n
			if step < 0 {
				step = -step
			}
		}
		lo, e1 := strconv.Atoi(fields[0])
		hi, e2 := strconv.Atoi(fields[1])
		alpha := false
		if e1 != nil || e2 != nil {
			if len(fields[0]) != 1 || len(fields[1]) != 1 || !fsBraceLetter(fields[0][0]) || !fsBraceLetter(fields[1][0]) {
				return nil, false
			}
			lo, hi, alpha = int(fields[0][0]), int(fields[1][0]), true
		}
		if lo < -100000 || lo > 100000 || hi < -100000 || hi > 100000 || fsGlobAbs(lo-hi)/step > 1024 {
			return nil, false
		}
		width := 0
		for _, endpoint := range fields[:2] {
			unsigned := strings.TrimPrefix(endpoint, "-")
			if len(unsigned) > 1 && unsigned[0] == '0' {
				width = max(width, len(unsigned))
			}
		}
		if lo > hi {
			step = -step
		}
		parts = nil
		for n := lo; step > 0 && n <= hi || step < 0 && n >= hi; n += step {
			value := strconv.Itoa(n)
			if alpha {
				value = string(rune(n))
			} else if width > 0 {
				unsigned := strconv.Itoa(fsGlobAbs(n))
				value = strings.Repeat("0", max(width-len(unsigned), 0)) + unsigned
				if n < 0 {
					value = "-" + value
				}
			}
			parts = append(parts, value)
		}
	}
	var result []string
	for _, part := range parts {
		expanded, ok := fsExpandBraces(pattern[:open] + part + pattern[end+1:])
		if !ok || len(result)+len(expanded) > 1025 {
			return nil, false
		}
		result = append(result, expanded...)
	}
	return result, true
}
func fsBraceLetter(ch byte) bool { return ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z' }
func fsGlobAbs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

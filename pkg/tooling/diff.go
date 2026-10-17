package tooling

import (
	"fmt"
	"strconv"
	"strings"
)

// DiffHunk is one @@ hunk of a unified diff. Lines keep their one-character
// prefix: ' ' context, '+' added, '-' removed.
type DiffHunk struct {
	OldStart, OldLen, NewStart, NewLen int
	Lines                              []string
}

// DiffFile is the hunks for one file. An empty Old marks an added file and an
// empty New a deleted one.
type DiffFile struct {
	Old, New string
	Hunks    []DiffHunk
}

func (f DiffFile) Path() string {
	if f.New != "" {
		return f.New
	}
	return f.Old
}

// ParseDiff reads a unified diff (git or plain diff -u). It never runs git.
func ParseDiff(text string) ([]DiffFile, error) {
	lines := strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n")
	var files []DiffFile
	var current *DiffFile
	git := false
	for i := 0; i < len(lines); i++ {
		line := lines[i]
		switch {
		case strings.HasPrefix(line, "diff --git "):
			files = append(files, DiffFile{})
			current, git = &files[len(files)-1], true
		case strings.HasPrefix(line, "rename from "), strings.HasPrefix(line, "rename to "):
			return nil, fmt.Errorf("renamed files are not supported; produce the diff with git diff --no-renames")
		case strings.HasPrefix(line, "--- ") && i+1 < len(lines) && strings.HasPrefix(lines[i+1], "+++ "):
			if current == nil || !git {
				files = append(files, DiffFile{})
				current = &files[len(files)-1]
			}
			current.Old = diffPath(line[4:], "a/", git)
			current.New = diffPath(lines[i+1][4:], "b/", git)
			if !git && strings.HasPrefix(current.Old, "a/") && strings.HasPrefix(current.New, "b/") && current.Old[2:] == current.New[2:] {
				current.Old, current.New = current.Old[2:], current.New[2:]
			}
			i++
		case strings.HasPrefix(line, "@@ "):
			if current == nil {
				return nil, fmt.Errorf("diff line %d: hunk before any file header", i+1)
			}
			hunk, next, err := parseHunk(lines, i)
			if err != nil {
				return nil, err
			}
			current.Hunks = append(current.Hunks, hunk)
			i = next - 1
		}
	}
	for _, file := range files {
		if file.Old == "" && file.New == "" {
			return nil, fmt.Errorf("diff has a file header with no paths")
		}
		if file.Old != "" && file.New != "" && file.Old != file.New {
			return nil, fmt.Errorf("renamed files are not supported (%s -> %s); produce the diff with git diff --no-renames", file.Old, file.New)
		}
	}
	return files, nil
}

func diffPath(field, prefix string, git bool) string {
	path, _, _ := strings.Cut(field, "\t")
	path = strings.TrimSpace(path)
	if path == "/dev/null" {
		return ""
	}
	if git {
		path = strings.TrimPrefix(path, prefix)
	}
	return path
}

func parseHunk(lines []string, start int) (DiffHunk, int, error) {
	var h DiffHunk
	header := lines[start]
	end := strings.Index(header[3:], " @@")
	if end < 0 {
		return h, 0, fmt.Errorf("diff line %d: malformed hunk header", start+1)
	}
	old, new, ok := strings.Cut(header[3:3+end], " ")
	if !ok || !strings.HasPrefix(old, "-") || !strings.HasPrefix(new, "+") {
		return h, 0, fmt.Errorf("diff line %d: malformed hunk header", start+1)
	}
	var err error
	if h.OldStart, h.OldLen, err = parseRange(old[1:]); err == nil {
		h.NewStart, h.NewLen, err = parseRange(new[1:])
	}
	if err != nil {
		return h, 0, fmt.Errorf("diff line %d: %v", start+1, err)
	}
	oldLeft, newLeft := h.OldLen, h.NewLen
	i := start + 1
	for ; i < len(lines) && (oldLeft > 0 || newLeft > 0); i++ {
		line := lines[i]
		if strings.HasPrefix(line, "\\") {
			continue
		}
		if line == "" {
			line = " "
		}
		switch line[0] {
		case ' ':
			oldLeft--
			newLeft--
		case '-':
			oldLeft--
		case '+':
			newLeft--
		default:
			return h, 0, fmt.Errorf("diff line %d: hunk ends before its declared length", i+1)
		}
		h.Lines = append(h.Lines, line)
	}
	if oldLeft != 0 || newLeft != 0 {
		return h, 0, fmt.Errorf("diff line %d: hunk is shorter than its header declares", start+1)
	}
	for i < len(lines) && strings.HasPrefix(lines[i], "\\") {
		i++
	}
	return h, i, nil
}

func parseRange(text string) (start, length int, err error) {
	first, second, has := strings.Cut(text, ",")
	if start, err = strconv.Atoi(first); err != nil {
		return 0, 0, fmt.Errorf("malformed hunk range %q", text)
	}
	length = 1
	if has {
		if length, err = strconv.Atoi(second); err != nil {
			return 0, 0, fmt.Errorf("malformed hunk range %q", text)
		}
	}
	return start, length, nil
}

// TouchedLines returns the head-side line numbers the hunks changed. A removal
// is attributed to the head line that follows it.
func (f DiffFile) TouchedLines() []int {
	var touched []int
	for _, hunk := range f.Hunks {
		line := hunk.NewStart
		if hunk.NewLen == 0 {
			line++
		}
		for _, text := range hunk.Lines {
			switch text[0] {
			case '+', '-':
				touched = append(touched, line)
			}
			if text[0] != '-' {
				line++
			}
		}
	}
	return touched
}

// ReverseApply reconstructs the base file from the head file and the hunks.
// Every context and added line is checked against the head, so a diff that
// does not describe this tree is an error rather than a guess.
func ReverseApply(head string, hunks []DiffHunk) (string, error) {
	source := strings.Split(head, "\n")
	var out []string
	position := 0
	same := func(a, b string) bool { return strings.TrimRight(a, "\r") == strings.TrimRight(b, "\r") }
	for _, hunk := range hunks {
		index := hunk.NewStart - 1
		if hunk.NewLen == 0 {
			index = hunk.NewStart
		}
		if index < position || index > len(source) {
			return "", fmt.Errorf("hunks overlap or fall outside the file at line %d", hunk.NewStart)
		}
		out = append(out, source[position:index]...)
		for _, line := range hunk.Lines {
			text := line[1:]
			if line[0] == '-' {
				out = append(out, text)
				continue
			}
			if index >= len(source) || !same(source[index], text) {
				return "", fmt.Errorf("line %d does not match the diff", index+1)
			}
			if line[0] == ' ' {
				out = append(out, source[index])
			}
			index++
		}
		position = index
	}
	out = append(out, source[position:]...)
	return strings.Join(out, "\n"), nil
}

// RemovedContent is the base text of a deleted file.
func RemovedContent(hunks []DiffHunk) string {
	var out []string
	for _, hunk := range hunks {
		for _, line := range hunk.Lines {
			if line[0] == '-' {
				out = append(out, line[1:])
			}
		}
	}
	return strings.Join(out, "\n") + "\n"
}

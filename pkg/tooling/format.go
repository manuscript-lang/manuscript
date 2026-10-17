// Package tooling supplies deterministic source formatting and checked-program views.
package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/frontend"
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"os"
	"path/filepath"
	"strings"
)

// Format preserves comments and token spellings. Invalid syntax never produces output.
func Format(filename, source string) (string, error) {
	module, err := parseFormatSource(filename, source)
	if err != nil {
		return "", err
	}
	normalized := strings.ReplaceAll(source, "\r\n", "\n")
	lines := strings.Split(normalized, "\n")
	breaks := paragraphBreaks(module, lines)
	tokens, err := lexer.Lex(filename, normalized)
	if err != nil {
		return "", err
	}
	if aligned, changed := alignSuiteHeaders(lines, tokens); changed {
		// Expression layout moves the closing line of a multi-line header back
		// to the statement's indentation, so its suite must move with it.
		normalized = strings.Join(aligned, "\n")
		lines = aligned
		if tokens, err = lexer.Lex(filename, normalized); err != nil {
			return "", err
		}
	}
	byLine := map[int][]lexer.Token{}
	for _, token := range tokens {
		switch token.Kind {
		case lexer.Indent, lexer.Dedent, lexer.Newline, lexer.EOF:
			continue
		}
		byLine[token.Pos.Line] = append(byLine[token.Pos.Line], token)
	}
	var output []string
	blank := true
	for index, line := range lines {
		if breaks[index+1] && !blank {
			output = append(output, "")
			blank = true
		}
		parts := byLine[index+1]
		if len(parts) == 0 {
			trimmed := strings.TrimSpace(line)
			if trimmed == "" {
				continue
			}
			indent := len(line) - len(strings.TrimLeft(line, " "))
			output = append(output, strings.Repeat(" ", indent/4*4)+strings.TrimRight(strings.TrimLeft(line, " "), " \t"))
			blank = false
			continue
		}
		var formatted strings.Builder
		formatted.WriteString(strings.Repeat(" ", parts[0].Pos.Column-1))
		for i, token := range parts {
			if i > 0 && tokenSpace(parts, i) {
				formatted.WriteByte(' ')
			}
			formatted.WriteString(token.Text)
		}
		last := parts[len(parts)-1]
		tail := last.Pos.Column - 1 + len(last.Text)
		if tail < len(line) {
			if comment := strings.IndexByte(line[tail:], '#'); comment >= 0 {
				formatted.WriteString("  ")
				formatted.WriteString(strings.TrimRight(line[tail+comment:], " \t"))
			}
		}
		output = append(output, formatted.String())
		blank = false
	}
	for len(output) > 0 && output[len(output)-1] == "" {
		output = output[:len(output)-1]
	}
	result := strings.Join(output, "\n") + "\n"
	result, err = formatExpressionLayout(filename, result)
	if err != nil {
		return "", err
	}
	if _, err := parseFormatSource(filename, result); err != nil {
		return "", err
	}
	return result, nil
}

// Use the same strict frontend entrypoint as compilation and editor tooling.
func parseFormatSource(filename, source string) (*syntax.Module, error) {
	module, issues := frontend.Parse(filename, source, false)
	if len(issues) != 0 {
		return nil, issues[0]
	}
	return module, nil
}

// alignSuiteHeaders re-indents a suite whose header spans several lines and
// ends on a line indented differently from the statement's first line. The
// suite is laid out relative to that last line, which the layout pass later
// moves to the first line's indentation. Headers inside delimiters (function
// expressions) keep their own rule and are left alone.
func alignSuiteHeaders(lines []string, tokens []lexer.Token) ([]string, bool) {
	indent := func(line int) int { return len(lines[line-1]) - len(strings.TrimLeft(lines[line-1], " ")) }
	shift := make([]int, len(lines)+2)
	changed := false
	depth := 0
	for i, token := range tokens {
		switch token.Kind {
		case "(", "[", "{":
			depth++
		case ")", "]", "}":
			depth--
		}
		if token.Kind != lexer.Indent || depth != 0 || i < 3 || tokens[i+1].Kind == lexer.Dedent ||
			tokens[i-1].Kind != lexer.Newline || tokens[i-2].Kind != ":" {
			continue
		}
		start := i - 2
		for start > 0 {
			if kind := tokens[start-1].Kind; kind == lexer.Newline || kind == lexer.Indent || kind == lexer.Dedent {
				break
			}
			start--
		}
		header, first := tokens[i-2].Pos.Line, tokens[start].Pos.Line
		if header == first || header > len(lines) || indent(header) == indent(first) {
			continue
		}
		end, nesting := len(lines), 0
		for _, later := range tokens[i:] {
			if later.Kind == lexer.Indent {
				nesting++
			} else if later.Kind == lexer.Dedent {
				if nesting--; nesting == 0 {
					end = min(end, later.Pos.Line-1)
					break
				}
			}
		}
		delta := indent(first) - indent(header)
		for line := header; line <= end; line++ {
			shift[line] += delta
		}
		changed = true
	}
	if !changed {
		return lines, false
	}
	out := make([]string, len(lines))
	for index, line := range lines {
		out[index] = line
		if delta := shift[index+1]; delta > 0 && strings.TrimSpace(line) != "" {
			out[index] = strings.Repeat(" ", delta) + line
		} else if delta < 0 {
			out[index] = line[min(-delta, len(line)-len(strings.TrimLeft(line, " "))):]
		}
	}
	return out, true
}

func tokenSpace(tokens []lexer.Token, at int) bool {
	current, previous := tokens[at].Kind, tokens[at-1].Kind
	if current == "." && (previous == "|" || previous == "try") {
		return true
	}
	if strings.Contains(" ) ] } , . : ", " "+current+" ") {
		return false
	}
	if previous == "(" || previous == "[" || previous == "{" || previous == "." {
		return false
	}
	if current == "=" && strings.Contains(" + - * / % ", " "+previous+" ") && tokens[at-1].End.Offset == tokens[at].Pos.Offset {
		// The two tokens of a compound assignment such as +=.
		return false
	}
	if current == "(" && (previous == lexer.Name || previous == ")" || previous == "]" || previous == "fn") {
		return false
	}
	if current == "[" && (previous == lexer.Name || previous == "]") {
		return false
	}
	if previous == "-" && (at == 1 || strings.Contains(" = ( [ , : return + - * / % < > == != <= >= ", " "+tokens[at-2].Kind+" ")) {
		return false
	}
	return true
}

func WriteFormatted(filename, source string, mode os.FileMode) error {
	file, err := os.CreateTemp(filepath.Dir(filename), ".manuscript-format-*")
	if err != nil {
		return err
	}
	name := file.Name()
	defer os.Remove(name)
	if _, err = file.WriteString(source); err != nil {
		file.Close()
		return err
	}
	if err = file.Chmod(mode); err != nil {
		file.Close()
		return err
	}
	if err = file.Close(); err != nil {
		return err
	}
	return os.Rename(name, filename)
}

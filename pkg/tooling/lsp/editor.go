package lsp

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strings"
	"unicode/utf8"
)

// Offset validates LSP positions, rejecting offsets inside surrogate pairs.
func Offset(source string, p position) (int, error) { return offset(source, p, false) }

// editOffset resolves a change range the way the protocol asks servers to:
// a character past the end of a line, or a line past the end of the document,
// clamps instead of rejecting the edit. Rejecting would leave this server's
// copy of the document out of step with the editor's for every later change.
func editOffset(source string, p position) (int, error) { return offset(source, p, true) }

func offset(source string, p position, clamp bool) (int, error) {
	if p.Line < 0 || p.Character < 0 {
		return 0, fmt.Errorf("negative position")
	}
	at := 0
	for line := 0; line < p.Line; line++ {
		next := strings.IndexByte(source[at:], '\n')
		if next < 0 {
			if clamp {
				return len(source), nil
			}
			return 0, fmt.Errorf("line outside document")
		}
		at += next + 1
	}
	column := 0
	for at < len(source) && source[at] != '\n' && source[at] != '\r' {
		if column == p.Character {
			return at, nil
		}
		r, size := utf8.DecodeRuneInString(source[at:])
		width := 1
		if r > 0xffff {
			width = 2
		}
		column += width
		at += size
		if column > p.Character {
			return 0, fmt.Errorf("position splits a surrogate pair")
		}
	}
	if column != p.Character && !clamp {
		return 0, fmt.Errorf("character outside line")
	}
	return at, nil
}

type editorToken struct {
	kind, text string
	start, end int
}

func identifier(b byte) bool {
	return b == '_' || b >= 'a' && b <= 'z' || b >= 'A' && b <= 'Z' || b >= '0' && b <= '9'
}

// editorTokens tolerates unfinished strings and delimiters. It is only a cursor
// context scanner; semantic types and visibility always come from the checker.
func editorTokens(source string) []editorToken {
	result := []editorToken{}
	for at := 0; at < len(source); {
		start := at
		b := source[at]
		if b == ' ' || b == '\r' || b == '\t' {
			at++
			continue
		}
		if b == '#' {
			for at < len(source) && source[at] != '\n' {
				at++
			}
			result = append(result, editorToken{"comment", source[start:at], start, at})
			continue
		}
		if b == '"' {
			at++
			for at < len(source) {
				if source[at] == '\\' {
					at++
					if at < len(source) {
						at++
					}
					continue
				}
				if source[at] == '"' {
					at++
					break
				}
				at++
			}
			result = append(result, editorToken{"string", source[start:at], start, at})
			continue
		}
		if identifier(b) {
			for at < len(source) && identifier(source[at]) {
				at++
			}
			result = append(result, editorToken{"name", source[start:at], start, at})
			continue
		}
		at++
		result = append(result, editorToken{string(b), string(b), start, at})
	}
	return result
}

type cursorContext struct {
	offset, start, end               int
	prefix                           string
	member                           bool
	callOpen, calleeStart, calleeEnd int
	argument                         bool
	typeContext                      bool
	literal, comment                 bool
}

func contextAt(d document, p position) (cursorContext, error) {
	offset, err := Offset(d.Text, p)
	if err != nil {
		return cursorContext{}, err
	}
	c := cursorContext{offset: offset, start: offset, end: offset, callOpen: -1, calleeStart: -1, calleeEnd: -1}
	for c.start > 0 && identifier(d.Text[c.start-1]) {
		c.start--
	}
	for c.end < len(d.Text) && identifier(d.Text[c.end]) {
		c.end++
	}
	c.prefix = d.Text[c.start:offset]
	tokens := editorTokens(d.Text)
	before := []editorToken{}
	for _, t := range tokens {
		if (t.kind == "comment" || t.kind == "string") && offset > t.start && (offset < t.end || t.kind == "comment" && offset == t.end || t.kind == "string" && !strings.HasSuffix(t.text, "\"")) {
			c.comment = t.kind == "comment"
			c.literal = t.kind == "string"
		}
		if t.end <= c.start {
			before = append(before, t)
		}
	}
	if len(before) > 0 && before[len(before)-1].kind == "." {
		c.member = true
	}

	stack := []int{}
	for index, t := range before {
		switch t.kind {
		case "(", "[", "{":
			stack = append(stack, index)
		case ")", "]", "}":
			if len(stack) > 0 {
				stack = stack[:len(stack)-1]
			}
		}
	}
	for index := len(stack) - 1; index >= 0; index-- {
		at := stack[index]
		t := before[at]
		if t.kind != "(" || at == 0 {
			continue
		}
		previous := before[at-1]
		if previous.kind != "name" && previous.kind != "]" && previous.kind != ")" {
			continue
		}
		if functionParametersAt(before, at) {
			continue
		}
		c.callOpen = t.start
		c.calleeEnd = previous.end
		c.calleeStart = previous.start
		// Include chained receivers and generic specialization in the callee span.
		depth := 0
		for j := at - 1; j >= 0; j-- {
			v := before[j]
			if v.kind == ")" || v.kind == "]" {
				depth++
			}
			if v.kind == "(" || v.kind == "[" {
				if depth == 0 {
					break
				}
				depth--
			}
			if depth == 0 && (v.kind == "\n" || v.kind == "," || v.kind == ":" || v.kind == "=" || v.text == "return" || v.text == "let" || v.text == "var") {
				break
			}
			c.calleeStart = v.start
		}
		segment := t.end
		depth = 0
		for _, v := range before[at+1:] {
			switch v.kind {
			case "(", "[", "{":
				depth++
			case ")", "]", "}":
				depth--
			case ",":
				if depth == 0 {
					segment = v.end
				}
			}
		}
		c.argument = !strings.Contains(d.Text[segment:c.start], ":")
		break
	}
	lineStart := strings.LastIndex(d.Text[:c.start], "\n") + 1
	line := strings.TrimSpace(d.Text[lineStart:c.start])
	c.typeContext = strings.HasSuffix(line, "->") || (strings.Contains(line, "let ") || strings.Contains(line, "var ")) && strings.Contains(line, ":") && !strings.Contains(line, "=") || (strings.HasPrefix(line, "fn ") || strings.HasPrefix(line, "export fn ")) && strings.Contains(line, ":")
	// A default is an expression inside a function header. Track only separators
	// at that parameter list's depth so nested calls and types keep their context.
	for index := len(stack) - 1; index >= 0; index-- {
		at := stack[index]
		if before[at].kind != "(" || !functionParametersAt(before, at) {
			continue
		}
		depth, defaultValue := 0, false
		for _, token := range before[at+1:] {
			switch token.kind {
			case "(", "[", "{":
				depth++
			case ")", "]", "}":
				depth--
			case "=":
				if depth == 0 {
					defaultValue = true
				}
			case ",":
				if depth == 0 {
					defaultValue = false
				}
			}
		}
		if defaultValue {
			c.typeContext = false
		}
		break
	}
	return c, nil
}
func functionParametersAt(tokens []editorToken, at int) bool {
	if at > 0 && tokens[at-1].text == "fn" {
		return true
	}
	previous := at - 1
	if previous >= 0 && tokens[previous].kind == "]" {
		depth := 1
		previous--
		for previous >= 0 && depth > 0 {
			if tokens[previous].kind == "]" {
				depth++
			}
			if tokens[previous].kind == "[" {
				depth--
			}
			previous--
		}
	}
	return previous > 0 && tokens[previous].kind == "name" && tokens[previous-1].text == "fn"
}
func copyDocuments(docs map[string]document) map[string]document {
	copy := map[string]document{}
	for uri, d := range docs {
		copy[uri] = d
	}
	return copy
}
func closeDelimiters(source string, line int) string {
	at := 0
	for n := 0; n < line; n++ {
		next := strings.IndexByte(source[at:], '\n')
		if next < 0 {
			return source
		}
		at += next + 1
	}
	end := strings.IndexByte(source[at:], '\n')
	if end < 0 {
		end = len(source) - at
	}
	end += at
	stack := []editorToken{}
	for _, t := range editorTokens(source) {
		switch t.kind {
		case "(", "[", "{":
			stack = append(stack, t)
		case ")", "]", "}":
			if len(stack) > 0 {
				stack = stack[:len(stack)-1]
			}
		}
	}
	var tail strings.Builder
	for i := len(stack) - 1; i >= 0; i-- {
		if stack[i].start <= end {
			// A later broken declaration must not close its opener on the
			// cursor's earlier, valid line and erase that declaration's scope.
			tail.WriteString(map[string]string{"(": ")", "[": "]", "{": "}"}[stack[i].kind])
		}
	}
	return source[:end] + tail.String() + source[end:]
}

type editorAnalysis struct {
	result     compiler.Result
	document   document
	marker     string
	expression *syntax.Expression
	scope      checker.ScopeState
}

func queryEditor(d document, docs map[string]document, c cursorContext) editorAnalysis {
	marker := "__manuscript_completion"
	for strings.Contains(d.Text, marker) {
		marker += "_"
	}
	replacement := marker
	if c.argument && !c.member {
		replacement += ": " + marker
	}
	modified := d
	modified.Text = d.Text[:c.start] + replacement + d.Text[c.end:]
	if c.typeContext {
		lineStart := strings.LastIndex(modified.Text[:c.start], "\n") + 1
		lineEnd := strings.IndexByte(modified.Text[c.start:], '\n')
		if lineEnd < 0 {
			lineEnd = len(modified.Text)
		} else {
			lineEnd += c.start
		}
		line := modified.Text[lineStart:lineEnd]
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "let ") || strings.HasPrefix(trimmed, "var ") {
			// Query the lexical environment before this local annotation. A type
			// marker alone cannot capture bindings that shadow a prelude type.
			indent := line[:len(line)-len(strings.TrimLeft(line, " \t"))]
			modified.Text = modified.Text[:lineStart] + indent + "let " + marker + "_value = " + marker + modified.Text[lineEnd:]
		}
	}
	modified.Text = closeDelimiters(modified.Text, Position(d.Text, c.offset).Line)
	copy := copyDocuments(docs)
	copy[d.URI] = modified
	var result compiler.Result
	// Repair only this private analysis snapshot. Neither diagnostics nor edits
	// are derived from fabricated text. Stop after a bounded number of faults.
	for attempt := 0; attempt < 24; attempt++ {
		result = analyzeOptions(modified, copy, compiler.Options{AnalyzeOnly: true, Recover: true, ScopeMarker: marker})
		if result.Program != nil {
			found := false
			for e := range result.Program.ScopeMarkers() {
				if e.Text == marker {
					found = true
					break
				}
			}
			if found || c.typeContext {
				break
			}
		}
		if len(result.Diagnostics) == 0 {
			break
		}
		issue := result.Diagnostics[0]
		if issue.Phase != "parse" {
			break
		}
		target := modified
		if result.SourceRoot != "" && issue.Position.File != "" {
			path := modulePath(result, issue.Position.File)
			for _, open := range copy {
				if filename(open.URI) == path {
					target = open
					break
				}
			}
		}
		lines := strings.Split(target.Text, "\n")
		line := issue.Position.Line - 1
		if line >= len(lines) {
			line = len(lines) - 1
		}
		if line < 0 {
			break
		}
		if strings.TrimSpace(lines[line]) == "" && line > 0 {
			line--
		}
		text := lines[line]
		indent := len(text) - len(strings.TrimLeft(text, " "))
		if strings.Contains(text, marker) {
			// A half-written statement can still query the scope using a standalone
			// expression at the same indentation. Member queries retain the receiver.
			start := strings.Index(text, marker)
			prefix := text[:start]
			if c.member {
				index := strings.LastIndex(prefix, "return ")
				if index >= 0 {
					prefix = prefix[index+7:]
				}
				if index := strings.LastIndex(prefix, " = "); index >= 0 {
					prefix = prefix[index+3:]
				}
				lines[line] = strings.Repeat(" ", indent) + "let " + marker + "_value = " + strings.TrimSpace(prefix) + marker
			} else {
				lines[line] = strings.Repeat(" ", indent) + "let " + marker + "_value = " + marker
			}
			if lines[line] == text {
				break
			}
		} else if strings.HasSuffix(strings.TrimSpace(text), ":") && (line+1 == len(lines) || strings.TrimSpace(lines[line+1]) == "") {
			body := []string{strings.Repeat(" ", indent+4) + "return unit"}
			if strings.HasPrefix(strings.TrimSpace(text), "match ") {
				body = []string{strings.Repeat(" ", indent+4) + "_:", strings.Repeat(" ", indent+8) + "return unit"}
			}
			lines = append(lines[:line+1], append(body, lines[line+1:]...)...)
		} else {
			lines[line] = strings.Repeat(" ", indent) + "return unit"
			if lines[line] == text {
				break
			}
		}
		target.Text = strings.Join(lines, "\n")
		copy[target.URI] = target
		if target.URI == d.URI {
			modified = target
		}
	}
	analysis := editorAnalysis{result: result, document: modified, marker: marker}
	if result.Program != nil {
		for e, state := range result.Program.ScopeMarkers() {
			if e.Pos.File == moduleFile(result, modified) && e.Text == marker {
				analysis.expression = e
				analysis.scope = state
				break
			}
		}
	}
	return analysis
}
func moduleFile(result compiler.Result, d document) string {
	if m := module(result, d); m != nil {
		return m.File
	}
	return ""
}

func diagnosticSpan(source string, offset int) span {
	start := Position(source, offset)
	end := start
	for _, token := range editorTokens(source) {
		if offset >= token.start && offset < token.end {
			end = Position(source, token.end)
			break
		}
	}
	return span{start, end}
}

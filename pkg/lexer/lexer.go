// Package lexer scans UTF-8 Manuscript source and enforces its layout rules.
package lexer

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"sort"
	"strings"
	"unicode/utf8"
)

type Token struct {
	Kind, Text string
	Pos        syntax.Position
	End        syntax.Position // Exclusive original-source position.
}

const (
	Newline = "NEWLINE"
	Indent  = "INDENT"
	Dedent  = "DEDENT"
	EOF     = "EOF"
	Name    = "NAME"
	Number  = "NUMBER"
	String  = "STRING"
)

var reserved = map[string]bool{}

func init() {
	for _, s := range strings.Fields("and break case continue else export false fixture fn for if impl import in interface let match not or return self test true try type unit var while with") {
		reserved[s] = true
	}
}

// Keywords returns the reserved words in sorted order.
func Keywords() []string {
	words := make([]string, 0, len(reserved))
	for word := range reserved {
		words = append(words, word)
	}
	sort.Strings(words)
	return words
}

func letter(b byte) bool { return b >= 'a' && b <= 'z' || b >= 'A' && b <= 'Z' || b == '_' }
func digit(b byte) bool  { return b >= '0' && b <= '9' }

type layout struct{ indent, depth int }
type scanner struct {
	file, source         string
	offset, line, column int
	tokens               []Token
	levels               []layout
	delimiters           []byte
	opened               []syntax.Position
	functionDepths       []int
	originalOffsets      []int
	interpolations       []syntax.Position
}

func (s *scanner) pos() syntax.Position {
	return syntax.Position{File: s.file, Line: s.line, Column: s.column, Offset: s.originalOffset(s.offset)}
}
func (s *scanner) fail(message string) {
	panic(syntax.Diagnostic{Position: s.pos(), Phase: "parse", Message: message})
}
func (s *scanner) failAt(p syntax.Position, message string) {
	panic(syntax.Diagnostic{Position: p, Phase: "parse", Message: message})
}
func (s *scanner) emit(kind, text string, p syntax.Position) {
	s.tokens = append(s.tokens, Token{Kind: kind, Text: text, Pos: p, End: s.pos()})
}
func (s *scanner) advance() byte {
	b := s.source[s.offset]
	s.offset++
	if b == '\n' {
		s.line++
		s.column = 1
	} else {
		s.column++
	}
	return b
}

func Lex(file, source string) (tokens []Token, err error) {
	defer func() {
		if r := recover(); r != nil {
			if d, ok := r.(syntax.Diagnostic); ok {
				err = d
			} else {
				panic(r)
			}
		}
	}()
	normalized, offsets := normalizeSource(source)
	s := &scanner{file: file, source: normalized, originalOffsets: offsets, line: 1, column: 1, levels: []layout{{0, 0}}}
	if !utf8.ValidString(source) {
		s.fail("source must be valid UTF-8; re-save the file with UTF-8 encoding")
	}
	if strings.HasPrefix(source, "\ufeff") {
		s.fail("a byte-order mark is not allowed; save the file as UTF-8 without BOM")
	}
	pending, headerIndent, pendingDepth := false, 0, 0
	// A line that starts with '.' or '|' continues the previous statement, which
	// began at statementIndent; it opens no block and ends no statement.
	continuing, statementIndent := false, 0
	for s.offset < len(s.source) {
		leading := 0
		for s.offset < len(s.source) && s.source[s.offset] == ' ' {
			s.advance()
			leading++
		}
		if s.offset == len(s.source) {
			break
		}
		if s.source[s.offset] == '\t' {
			s.fail("tabs are not allowed in code; indent with four spaces per level (tabs may appear only inside text or comments)")
		}
		if s.source[s.offset] == '#' {
			s.skipComment()
			if s.offset < len(s.source) {
				s.advance()
			}
			continue
		}
		if s.source[s.offset] == '\n' {
			s.advance()
			continue
		}
		if leading%4 != 0 {
			s.fail(fmt.Sprintf("indentation must be a multiple of four spaces, found %d; use %d or %d", leading, leading/4*4, leading/4*4+4))
		}
		if continuing {
			if leading != statementIndent+4 {
				s.fail(fmt.Sprintf("a line starting with '.' or '|' continues the previous statement and must be indented four spaces past it, to %d spaces, found %d", statementIndent+4, leading))
			}
			continuing = false
		} else {
			if len(s.delimiters) == s.levels[len(s.levels)-1].depth {
				statementIndent = leading
			}
			startedSuite := false
			if pending {
				if leading == headerIndent+4 {
					s.levels = append(s.levels, layout{leading, pendingDepth})
					s.emit(Indent, "", s.pos())
					startedSuite = true
				} else if leading <= headerIndent {
					// An empty declaration suite has the same layout boundaries as
					// a populated one. The parser decides which suites may be empty.
					s.emit(Indent, "", s.pos())
					s.emit(Dedent, "", s.pos())
				} else {
					s.fail(fmt.Sprintf("a suite must begin exactly four spaces after its header; the header is at %d spaces, so indent this line to %d", headerIndent, headerIndent+4))
				}
				pending = false
			}
			if !startedSuite {
				// A continuation line inside delimiters opened within a level does not
				// close that level; only suites opened inside the open delimiters can.
				for len(s.levels) > 1 && leading < s.levels[len(s.levels)-1].indent && s.levels[len(s.levels)-1].depth >= len(s.delimiters) {
					s.levels = s.levels[:len(s.levels)-1]
					s.emit(Dedent, "", s.pos())
				}
				top := s.levels[len(s.levels)-1]
				if len(s.delimiters) == top.depth && leading != top.indent {
					if leading > top.indent {
						s.fail(fmt.Sprintf("unexpected indentation, %d spaces where %d are expected; the previous line must end with ':' to open a block (fn, if, else, for, while, match, type, impl headers), otherwise align this line with it%s", leading, top.indent, s.continuationHint()))
					}
					s.fail(fmt.Sprintf("inconsistent dedent to %d spaces; enclosing blocks are indented at %d or %d spaces, so align with one of them", leading, top.indent, max(top.indent-4, 0)))
				}
			}
		}
		top := s.levels[len(s.levels)-1]
		if len(s.tokens) > 0 && s.tokens[len(s.tokens)-1].Kind == Dedent && len(s.delimiters) == top.depth {
			s.emit(Newline, "", s.pos())
		}
		lineStart := len(s.tokens)
		for s.offset < len(s.source) && s.source[s.offset] != '\n' {
			b := s.source[s.offset]
			p := s.pos()
			if b == ' ' {
				s.advance()
				continue
			}
			if b == '#' {
				s.skipComment()
				break
			}
			if b == '\t' || b == '\r' {
				s.fail("tabs and lone carriage returns are not allowed in code; use spaces, and line endings of LF or CRLF")
			}
			if letter(b) {
				start := s.offset
				for s.offset < len(s.source) && (letter(s.source[s.offset]) || digit(s.source[s.offset])) {
					s.advance()
				}
				value := s.source[start:s.offset]
				kind := Name
				if reserved[value] || value == "_" {
					kind = value
				}
				if value == "fn" || value == "match" {
					s.functionDepths = append(s.functionDepths, len(s.delimiters))
				}
				s.emit(kind, value, p)
				continue
			}
			if digit(b) {
				s.scanNumber(p)
				continue
			}
			if b == '"' {
				start := s.offset
				s.scanString()
				s.emit(String, s.source[start:s.offset], p)
				continue
			}
			matched := false
			for _, op := range []string{"->", "==", "!=", "<=", ">="} {
				if strings.HasPrefix(s.source[s.offset:], op) {
					s.advance()
					s.advance()
					s.emit(op, op, p)
					matched = true
					break
				}
			}
			if matched {
				continue
			}
			if strings.ContainsRune("()[]{}:,.+-*/%<>=&|", rune(b)) {
				if strings.ContainsRune("([{", rune(b)) {
					s.delimiters = append(s.delimiters, b)
					s.opened = append(s.opened, p)
				}
				if strings.ContainsRune(")]}", rune(b)) {
					if len(s.delimiters) == 0 {
						s.fail(fmt.Sprintf("unmatched closing delimiter %q; remove it or add the matching opener before it", b))
					}
					if len(s.levels) > 1 && len(s.delimiters) <= top.depth && leading >= top.indent {
						s.fail("an outer delimiter cannot close inside a function suite; close the bracket on the line where the function body ends, or dedent the body")
					}
					open := s.delimiters[len(s.delimiters)-1]
					if !((open == '(' && b == ')') || (open == '[' && b == ']') || (open == '{' && b == '}')) {
						where := s.opened[len(s.opened)-1]
						s.fail(fmt.Sprintf("mismatched closing delimiter %q; the %q opened at line %d:%d needs %q", b, open, where.Line, where.Column, map[byte]byte{'(': ')', '[': ']', '{': '}'}[open]))
					}
					s.delimiters = s.delimiters[:len(s.delimiters)-1]
					s.opened = s.opened[:len(s.opened)-1]
					for len(s.functionDepths) > 0 && s.functionDepths[len(s.functionDepths)-1] > len(s.delimiters) {
						s.functionDepths = s.functionDepths[:len(s.functionDepths)-1]
					}
				}
				s.advance()
				s.emit(string(b), string(b), p)
				continue
			}
			if b >= utf8.RuneSelf {
				r, _ := utf8.DecodeRuneInString(s.source[s.offset:])
				s.fail(fmt.Sprintf("unexpected source character %q; non-ASCII characters are only allowed inside text and '#' comments, and identifiers are ASCII", r))
			}
			s.fail(fmt.Sprintf("unexpected source character %q%s", b, characterHint(b)))
		}
		if len(s.tokens) > lineStart {
			last := s.tokens[len(s.tokens)-1]
			hasFunction := false
			for _, depth := range s.functionDepths {
				if depth == len(s.delimiters) {
					hasFunction = true
				}
			}
			if last.Kind == ":" && (len(s.delimiters) == top.depth || hasFunction) {
				pending = true
				headerIndent = leading
				pendingDepth = len(s.delimiters)
				s.emit(Newline, "", s.pos())
				s.functionDepths = nil
			} else if len(s.delimiters) == top.depth {
				s.functionDepths = nil
				if s.continuesNext() {
					continuing = true
				} else {
					s.emit(Newline, "", s.pos())
				}
			}
		}
		if s.offset < len(s.source) {
			s.advance()
		}
	}
	if pending {
		s.emit(Indent, "", s.pos())
		s.emit(Dedent, "", s.pos())
	}
	if len(s.delimiters) > 0 {
		open := s.delimiters[len(s.delimiters)-1]
		where := s.opened[len(s.opened)-1]
		s.fail(fmt.Sprintf("unterminated delimiter %q opened at line %d:%d; add the matching %q before the end of the file", open, where.Line, where.Column, map[byte]byte{'(': ')', '[': ']', '{': '}'}[open]))
	}
	for len(s.levels) > 1 {
		s.levels = s.levels[:len(s.levels)-1]
		s.emit(Dedent, "", s.pos())
	}
	s.emit(EOF, "", s.pos())
	return s.tokens, nil
}

// continuesNext reports whether the next code line begins with '.' or '|', which
// continues the statement on the current line. Blank and comment-only lines are
// skipped. No valid statement starts with either character, so this changes no
// program that was accepted before.
func (s *scanner) continuesNext() bool {
	i := s.offset
	if i >= len(s.source) {
		return false
	}
	i++
	for i < len(s.source) {
		j := i
		for j < len(s.source) && s.source[j] == ' ' {
			j++
		}
		if j >= len(s.source) {
			return false
		}
		switch s.source[j] {
		case '\n':
			i = j + 1
		case '#':
			for j < len(s.source) && s.source[j] != '\n' {
				j++
			}
			i = j + 1
		case '|':
			return true
		case '.':
			return j+1 < len(s.source) && !digit(s.source[j+1]) && s.source[j+1] != '.'
		default:
			return false
		}
	}
	return false
}

// skipComment consumes a comment through the end of its physical line. Tabs are
// allowed in comments, but a lone carriage return is not a line ending.
func (s *scanner) skipComment() {
	for s.offset < len(s.source) && s.source[s.offset] != '\n' {
		if s.source[s.offset] == '\r' {
			s.fail("lone carriage returns are not allowed in comments; use line endings of LF or CRLF")
		}
		s.advance()
	}
}

func (s *scanner) scanNumber(p syntax.Position) {
	start := s.offset
	s.advance()
	if s.source[start] == '0' && s.offset < len(s.source) && digit(s.source[s.offset]) {
		s.fail("leading zeros are not allowed in numeric literals; write the number without them, e.g. 42 instead of 042")
	}
	for s.offset < len(s.source) && digit(s.source[s.offset]) {
		s.advance()
	}
	if s.offset+1 < len(s.source) && s.source[s.offset] == '.' && digit(s.source[s.offset+1]) {
		s.advance()
		for s.offset < len(s.source) && digit(s.source[s.offset]) {
			s.advance()
		}
	}
	if s.offset < len(s.source) && (s.source[s.offset] == 'e' || s.source[s.offset] == 'E') {
		s.advance()
		if s.offset < len(s.source) && (s.source[s.offset] == '+' || s.source[s.offset] == '-') {
			s.advance()
		}
		if s.offset == len(s.source) || !digit(s.source[s.offset]) {
			s.fail("an exponent requires digits; write e.g. 1e3 or 2.5e-4")
		}
		for s.offset < len(s.source) && digit(s.source[s.offset]) {
			s.advance()
		}
	}
	if s.offset < len(s.source) && s.source[s.offset] == 'd' {
		s.advance()
	}
	if s.offset < len(s.source) && letter(s.source[s.offset]) {
		s.fail("invalid numeric suffix; the only suffix is d for Decimal (1.5d), so put a space or operator after the number")
	}
	s.emit(Number, s.source[start:s.offset], p)
}
func (s *scanner) scanString() {
	opened := s.pos()
	s.advance()
	for s.offset < len(s.source) {
		b := s.advance()
		if b == '"' {
			return
		}
		if b == '\n' {
			if n := len(s.interpolations); n > 0 {
				s.failAt(s.interpolations[n-1], "unterminated interpolation; the quote after this '{' opens a nested text that never closes ("+braceHint+")")
			}
			s.failAt(opened, "unterminated text literal; text must close with '\"' on the same line, so add the quote or write \\n for a line break")
		}
		if b < 32 {
			s.fail("literal control characters are not allowed in text; write an escape such as \\t, \\r, or \\u{H}")
		}
		if b == '\\' {
			backslash := s.pos()
			backslash.Column--
			backslash.Offset--
			if s.offset == len(s.source) {
				s.fail("unterminated text escape; a backslash needs a following character, e.g. \\n")
			}
			c := s.advance()
			if c == 'u' {
				if s.offset == len(s.source) || s.advance() != '{' {
					s.fail("Unicode escapes use \\u{H}; write 1 to 6 hexadecimal digits in braces, e.g. \\u{1F600}")
				}
				start := s.offset
				value := 0
				for s.offset < len(s.source) && s.source[s.offset] != '}' {
					c := s.advance()
					n := -1
					switch {
					case c >= '0' && c <= '9':
						n = int(c - '0')
					case c >= 'a' && c <= 'f':
						n = int(c-'a') + 10
					case c >= 'A' && c <= 'F':
						n = int(c-'A') + 10
					}
					if n < 0 {
						s.fail("invalid Unicode scalar escape; use only hexadecimal digits 0-9 and a-f inside \\u{...}")
					}
					value = value*16 + n
				}
				if s.offset == len(s.source) || s.offset-start < 1 || s.offset-start > 6 || value > 0x10ffff || value >= 0xd800 && value <= 0xdfff {
					s.fail("invalid Unicode scalar escape; use 1 to 6 hexadecimal digits for a value up to 10FFFF that is not a surrogate (D800-DFFF)")
				}
				s.advance()
			} else if !strings.ContainsRune("\"\\nrt{}", rune(c)) {
				s.failAt(backslash, fmt.Sprintf("unknown text escape \\%c; valid escapes are \\n \\t \\r \\\\ \\\" \\{ \\} and \\u{H}", c))
			}
		} else if b == '{' {
			s.scanInterpolation()
		} else if b == '}' {
			s.fail("an unmatched closing brace must be escaped; write \\} for a literal brace (and \\{ for the opening brace), or open an interpolation with {expression}")
		}
	}
	s.fail("unterminated text literal")
}

// maxInterpolationDepth bounds nested text literals inside interpolations. The
// parser re-lexes every interpolation, so deeper nesting would cost time
// proportional to depth times source size before the parser's own limit applies.
const maxInterpolationDepth = 1000

const braceHint = "'{' starts an interpolation; write \\{ and \\} for literal braces"

func (s *scanner) scanInterpolation() {
	depth := 1
	start := s.offset
	open := s.pos()
	open.Column--
	open.Offset--
	if len(s.interpolations) >= maxInterpolationDepth {
		s.failAt(open, fmt.Sprintf("nesting exceeds %d levels; split the expression, type, or block into named parts", maxInterpolationDepth))
	}
	s.interpolations = append(s.interpolations, open)
	defer func() { s.interpolations = s.interpolations[:len(s.interpolations)-1] }()
	for s.offset < len(s.source) {
		b := s.source[s.offset]
		if b == '\n' || b == '\r' || b == '#' {
			s.failAt(open, "newlines and comments are not allowed inside interpolation; keep the expression on one line, or bind it to a name first and interpolate the name ("+braceHint+")")
		}
		if b == '\\' {
			s.failAt(open, braceHint+"; a backslash cannot appear in the interpolated expression")
		}
		if b == '"' {
			s.scanString()
			continue
		}
		s.advance()
		if b == '{' {
			depth++
		}
		if b == '}' {
			depth--
			if depth == 0 {
				if strings.TrimSpace(s.source[start:s.offset-1]) == "" {
					s.fail("empty interpolation; put an expression between the braces, or write \\{ for a literal brace")
				}
				return
			}
		}
	}
	s.failAt(open, "unterminated interpolation; add the closing } before the closing quote ("+braceHint+")")
}

// originalOffset maps a normalized offset back to the source; without CRLF
// pairs the two coincide and no table is kept.
func (s *scanner) originalOffset(at int) int {
	if s.originalOffsets == nil {
		return at
	}
	return s.originalOffsets[at]
}

func normalizeSource(source string) (string, []int) {
	if !strings.Contains(source, "\r\n") {
		return source, nil
	}
	var normalized strings.Builder
	offsets := make([]int, 0, len(source)+1)
	for at := 0; at < len(source); at++ {
		offsets = append(offsets, at)
		if source[at] == '\r' && at+1 < len(source) && source[at+1] == '\n' {
			normalized.WriteByte('\n')
			at++
		} else {
			normalized.WriteByte(source[at])
		}
	}
	offsets = append(offsets, len(source))
	return normalized.String(), offsets
}

// characterHint explains the common foreign-syntax characters.
func characterHint(b byte) string {
	switch b {
	case ';':
		return "; Manuscript ends a statement at the end of the line, so remove the semicolon"
	case '\'':
		return "; text uses double quotes, e.g. \"text\""
	case '!':
		return "; write 'not x' for negation and '!=' for inequality"
	case '?':
		return "; Manuscript has no ? operator, so use 'if let' for Optional values, or 'try' for Result"
	case '`':
		return "; text uses double quotes with {expression} interpolation"
	case '$', '@', '\\', '^', '~':
		return "; this character is not part of Manuscript's syntax outside text"
	}
	return "; this character is not part of Manuscript's syntax"
}

// continuationHint explains the usual cause of an over-indented line that
// starts with a binary operator: the previous expression ended at the newline.
func (s *scanner) continuationHint() string {
	rest := s.source[s.offset:]
	end := 0
	for end < len(rest) && rest[end] != ' ' && rest[end] != '\n' {
		end++
	}
	word := string(rest[:end])
	switch word {
	case "and", "or", "+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">=":
		return "; to continue an expression on the next line, wrap the whole expression in parentheses"
	}
	return ""
}

// Package lexer scans UTF-8 Manuscript source and enforces its layout rules.
package lexer

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strings"
	"unicode/utf8"
)

type Token struct {
	Kind, Text string
	Pos        syntax.Position
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
	for _, s := range strings.Fields("and break case continue else export false fn for from if impl import in interface let match not or return self test true try type unit var while with") {
		reserved[s] = true
	}
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
	functionDepths       []int
	originalOffsets      []int
}

func (s *scanner) pos() syntax.Position {
	return syntax.Position{File: s.file, Line: s.line, Column: s.column, Offset: s.originalOffsets[s.offset]}
}
func (s *scanner) fail(message string) {
	panic(syntax.Diagnostic{Position: s.pos(), Phase: "parse", Message: message})
}
func (s *scanner) emit(kind, text string, p syntax.Position) {
	s.tokens = append(s.tokens, Token{kind, text, p})
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
		s.fail("source must be valid UTF-8")
	}
	if strings.HasPrefix(source, "\ufeff") {
		s.fail("a byte-order mark is not allowed")
	}
	pending, headerIndent, pendingDepth := false, 0, 0
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
			s.fail("tabs are not allowed in code")
		}
		if s.source[s.offset] == '#' {
			for s.offset < len(s.source) && s.source[s.offset] != '\n' {
				s.advance()
			}
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
			s.fail("indentation must be a multiple of four spaces")
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
				s.fail("a suite must begin exactly four spaces after its header")
			}
			pending = false
		}
		if !startedSuite {
			for len(s.levels) > 1 && leading < s.levels[len(s.levels)-1].indent {
				s.levels = s.levels[:len(s.levels)-1]
				s.emit(Dedent, "", s.pos())
			}
			top := s.levels[len(s.levels)-1]
			if len(s.delimiters) == top.depth && leading != top.indent {
				s.fail("unexpected indentation or inconsistent dedent")
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
				for s.offset < len(s.source) && s.source[s.offset] != '\n' {
					s.advance()
				}
				break
			}
			if b == '\t' || b == '\r' {
				s.fail("tabs and lone carriage returns are not allowed in code")
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
			if strings.ContainsRune("()[]{}:,.+-*/%<>=&", rune(b)) {
				if strings.ContainsRune("([{", rune(b)) {
					s.delimiters = append(s.delimiters, b)
				}
				if strings.ContainsRune(")]}", rune(b)) {
					if len(s.delimiters) == 0 {
						s.fail("unmatched closing delimiter")
					}
					if len(s.levels) > 1 && len(s.delimiters) <= top.depth && leading >= top.indent {
						s.fail("an outer delimiter cannot close inside a function suite")
					}
					open := s.delimiters[len(s.delimiters)-1]
					if !((open == '(' && b == ')') || (open == '[' && b == ']') || (open == '{' && b == '}')) {
						s.fail("mismatched closing delimiter")
					}
					s.delimiters = s.delimiters[:len(s.delimiters)-1]
					for len(s.functionDepths) > 0 && s.functionDepths[len(s.functionDepths)-1] > len(s.delimiters) {
						s.functionDepths = s.functionDepths[:len(s.functionDepths)-1]
					}
				}
				s.advance()
				s.emit(string(b), string(b), p)
				continue
			}
			s.fail(fmt.Sprintf("unexpected source character %q", b))
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
				s.emit(Newline, "", s.pos())
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
		s.fail("unterminated delimiter")
	}
	for len(s.levels) > 1 {
		s.levels = s.levels[:len(s.levels)-1]
		s.emit(Dedent, "", s.pos())
	}
	s.emit(EOF, "", s.pos())
	return s.tokens, nil
}
func (s *scanner) scanNumber(p syntax.Position) {
	start := s.offset
	s.advance()
	if s.source[start] == '0' && s.offset < len(s.source) && digit(s.source[s.offset]) {
		s.fail("leading zeros are not allowed in numeric literals")
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
			s.fail("an exponent requires digits")
		}
		for s.offset < len(s.source) && digit(s.source[s.offset]) {
			s.advance()
		}
	}
	if s.offset < len(s.source) && s.source[s.offset] == 'd' {
		s.advance()
	}
	if s.offset < len(s.source) && letter(s.source[s.offset]) {
		s.fail("invalid numeric suffix")
	}
	s.emit(Number, s.source[start:s.offset], p)
}
func (s *scanner) scanString() {
	s.advance()
	for s.offset < len(s.source) {
		b := s.advance()
		if b == '"' {
			return
		}
		if b < 32 {
			s.fail("literal control characters are not allowed in text")
		}
		if b == '\\' {
			if s.offset == len(s.source) {
				s.fail("unterminated text escape")
			}
			c := s.advance()
			if c == 'u' {
				if s.offset == len(s.source) || s.advance() != '{' {
					s.fail("Unicode escapes use \\u{H}")
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
						s.fail("invalid Unicode scalar escape")
					}
					value = value*16 + n
				}
				if s.offset == len(s.source) || s.offset-start < 1 || s.offset-start > 6 || value > 0x10ffff || value >= 0xd800 && value <= 0xdfff {
					s.fail("invalid Unicode scalar escape")
				}
				s.advance()
			} else if !strings.ContainsRune("\"\\nrt{}", rune(c)) {
				s.fail("unknown text escape")
			}
		} else if b == '{' {
			s.scanInterpolation()
		} else if b == '}' {
			s.fail("an unmatched closing brace must be escaped")
		}
	}
	s.fail("unterminated text literal")
}
func (s *scanner) scanInterpolation() {
	depth := 1
	start := s.offset
	for s.offset < len(s.source) {
		b := s.source[s.offset]
		if b == '\n' || b == '\r' || b == '#' {
			s.fail("newlines and comments are not allowed inside interpolation")
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
					s.fail("empty interpolation")
				}
				return
			}
		}
	}
	s.fail("unterminated interpolation")
}

func normalizeSource(source string) (string, []int) {
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

package checker

import (
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// These spellings are diagnostic migration data, never callable aliases. Match
// nominal identities so application methods with these names remain ordinary.
func migratedAccessorName(receiver *Type, name string) string {
	if std(receiver, "Duration") {
		switch name {
		case "to_nanoseconds", "to_microseconds", "to_milliseconds", "to_seconds", "to_minutes", "to_hours":
			return strings.TrimPrefix(name, "to_")
		}
	}
	if std(receiver, "SynchronizedGuard") && name == "get" {
		return "value"
	}
	return ""
}

func (c *checker) renamedAccessor(member *syntax.Expression, receiver *Type, replacement string) {
	c.unknownType = true
	message := member.Text + " was replaced by the " + replacement + " accessor on " + receiver.Name + "; write " + c.accessorReadSpelling(member, replacement)
	c.error(member.Pos, "resolution", message)
	c.accessorFix(member, replacement, false)
}

func (c *checker) calledAccessor(call *syntax.Expression, method *Method) {
	member := call.Left
	if member.Kind != syntax.KindMember {
		c.notCallable(call, method.Type.Result)
		return
	}
	c.error(call.Pos, "type", member.Text+" is a read-only accessor, not a method; write "+c.accessorReadSpelling(member, member.Text)+" without ()")
	if len(call.Args) == 0 {
		c.accessorFix(member, member.Text, true)
	}
}

func (c *checker) accessorReadSpelling(member *syntax.Expression, name string) string {
	if source := c.accessorSourceTokens(); source != nil && member.Left != nil {
		start := member.Left.Pos.Offset
		for left := member.Left.Left; left != nil; left = left.Left {
			if left.Pos.Offset < start {
				start = left.Pos.Offset
			}
		}
		first, starts := source.offsets[start]
		last, ends := source.offsets[member.Pos.Offset]
		if starts && ends && first < last {
			// Parentheses are not AST nodes. Include any wrappers closing
			// between the receiver's first token and this member's dot.
			balance := 0
			for _, token := range source.tokens[first:last] {
				switch token.Kind {
				case "(":
					balance++
				case ")":
					balance--
				}
			}
			for balance < 0 && first > 0 && source.tokens[first-1].Kind == "(" {
				first--
				balance++
			}
			start = source.tokens[first].Pos.Offset
			receiver := strings.TrimSpace(c.module.Source[start:member.Pos.Offset])
			if strings.HasSuffix(receiver, ".") {
				return strings.TrimSpace(strings.TrimSuffix(receiver, ".")) + "." + name
			}
		}
	}
	receiver := calleeName(member.Left)
	if receiver == "" {
		receiver = "receiver"
	}
	return receiver + "." + name
}

// accessorFix edits only the member suffix. It never removes arguments or
// comments, and leaves complex receiver evaluation exactly where it was. The
// lexer provides real source positions, including multiline and CRLF input.
func (c *checker) accessorFix(member *syntax.Expression, replacement string, requireCall bool) {
	if c.module == nil || len(c.Diagnostics) == 0 {
		return
	}
	diagnostic := &c.Diagnostics[len(c.Diagnostics)-1]
	if diagnostic.Position != member.Pos {
		return // recovery may have suppressed the diagnostic
	}
	source := c.accessorSourceTokens()
	if source == nil {
		return
	}
	tokens := source.tokens
	index, found := source.offsets[member.Pos.Offset]
	if !found || tokens[index].Text != member.Text {
		return
	}
	token := tokens[index]
	end := token.End
	called := index+1 < len(tokens) && tokens[index+1].Kind == "("
	if called {
		if index+2 >= len(tokens) || tokens[index+2].Kind != ")" {
			return // never discard argument evaluation
		}
		end = tokens[index+2].End
		if strings.Contains(c.module.Source[token.End.Offset:end.Offset], "#") {
			return // an automatic edit must preserve every comment
		}
	} else if requireCall {
		return
	}
	diagnostic.End = &end
	diagnostic.Fix = &syntax.DiagnosticFix{Position: member.Pos, End: end, Replacement: replacement}
}

// Failed migration calls can be numerous in a partial editor snapshot. Lex and
// index a module once rather than rescanning it for every diagnostic.
type accessorSourceTokens struct {
	module  *syntax.Module
	tokens  []lexer.Token
	offsets map[int]int
}

func (c *checker) accessorSourceTokens() *accessorSourceTokens {
	if c.module == nil {
		return nil
	}
	if c.accessorSource == nil || c.accessorSource.module != c.module {
		tokens, err := lexer.Lex(c.module.File, c.module.Source)
		c.accessorSource = &accessorSourceTokens{module: c.module, offsets: map[int]int{}}
		if err == nil {
			c.accessorSource.tokens = tokens
			for index, token := range tokens {
				c.accessorSource.offsets[token.Pos.Offset] = index
			}
		}
	}
	return c.accessorSource
}

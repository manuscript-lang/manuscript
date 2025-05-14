package visitor

import (
	"go/token"

	"github.com/antlr4-go/antlr/v4"
)

// getAntlrTokenPos converts an ANTLR token's start position to a go/token.Pos.
// This is a simplification and might need refinement if precise FileSet mapping is required.
func getAntlrTokenPos(tk antlr.Token) token.Pos {
	if tk == nil {
		return token.NoPos
	}
	return token.Pos(tk.GetStart()) // Using GetStart() as the character offset
}

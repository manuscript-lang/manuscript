package lexer

import "strings"

// Keywords are the reserved words of the language, for tools that must
// classify names when the source does not lex.
var Keywords = strings.Fields("fn type interface impl import from export let var if else for in while match case return with try break continue test and or not true false unit self")

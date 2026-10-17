// Package syntax defines source positions and the untyped Manuscript syntax tree.
package syntax

import "fmt"

type Position struct {
	File   string `json:"file"`
	Line   int    `json:"line"`
	Column int    `json:"column"`
	Offset int    `json:"offset"`
}

func (p Position) String() string { return fmt.Sprintf("%s:%d:%d", p.File, p.Line, p.Column) }

type Diagnostic struct {
	Position Position `json:"position"`
	Phase    string   `json:"phase"`
	Message  string   `json:"message"`
	// End is exclusive and omitted when the diagnostic has no known range.
	End *Position      `json:"end,omitempty"`
	Fix *DiagnosticFix `json:"fix,omitempty"`
}

// DiagnosticFix replaces one exact source range. Absence means human judgment
// is required; a prose suggestion alone is not a machine-applicable fix.
type DiagnosticFix struct {
	Position    Position `json:"position"`
	End         Position `json:"end"`
	Replacement string   `json:"replacement"`
}

func (d Diagnostic) Error() string { return fmt.Sprintf("%s: %s: %s", d.Position, d.Phase, d.Message) }

type Type struct {
	Pos    Position
	Name   string
	Args   []*Type
	Params []Parameter
	Result *Type
	// Fact is the checker's annotation of this node; nil until it is checked.
	Fact any
}
type Parameter struct {
	Pos     Position
	Name    string
	Type    *Type
	Default *Expression
}
type TypeParameter struct {
	Pos    Position
	Name   string
	Bounds []*Type
	// Default is the type argument used when none is supplied or inferred; nil when required.
	Default *Type
}
type Module struct {
	File         string
	Source       string
	Imports      []*Import
	Declarations []*Declaration
	// Omitted names declarations that editor recovery dropped because they did
	// not parse; uses of them are not reported as unknown.
	Omitted []string
	// Recovered holds the source ranges of declarations whose invalid
	// statements editor recovery blanked; their syntax error is already
	// reported, so checking diagnostics inside them are suppressed.
	Recovered []Span
}

// Span is a half-open byte range of source.
type Span struct{ Start, End int }

// Import represents one symbol binding; named import lists expand into bindings.
type Import struct {
	Pos        Position
	NamePos    Position
	Name, Path string
}
type Declaration struct {
	Pos        Position
	Kind, Name string
	Export     bool
	// Constant marks a module-level `let` constant. It is stored as a function
	// without parameters whose body returns the initializer, and every use
	// evaluates that initializer. Result is the annotation, or a placeholder
	// at the initializer's position until the checker infers the type.
	Constant                   bool
	TypeParams                 []TypeParameter
	Fields                     []Parameter
	Cases                      []Case
	Methods                    []*Declaration
	Params                     []Parameter
	Result, Contract, Receiver *Type
	Body                       []*Statement
	// Fact is the checker's annotation of this node; nil until it is checked.
	Fact any
}
type Case struct {
	Pos    Position
	Name   string
	Fields []Parameter
}
type Argument struct {
	Pos   Position
	Name  string
	Value *Expression
}
type TextPart struct {
	Text  string
	Value *Expression
}
type Expression struct {
	Pos         Position
	Kind, Text  string
	Left, Right *Expression
	Args        []Argument
	Types       []*Type
	Elements    []*Expression // Map literals store alternating key and value expressions.
	Parts       []TextPart
	Params      []Parameter
	Result      *Type
	Body        []*Statement
	Arms        []Arm
	// ConstantUse marks a call the checker made from a module-level constant's
	// name; a written `NAME()` is rejected.
	ConstantUse bool
	// Fact is the checker's annotation of this node; nil until it is checked.
	Fact any
}
type Pattern struct {
	Pos        Position
	Kind, Name string
	Elements   []*Pattern
	Fields     []PatternField
	// Fact is the checker's annotation of this node; nil until it is checked.
	Fact any
}
type PatternField struct {
	Pos     Position
	Name    string
	Pattern *Pattern
}
type Arm struct {
	Pos           Position
	Path          *Expression
	Names         []string
	NamePositions []Position // Original positions, parallel to Names (including _).
	Value         *Expression
	Body          []*Statement
	// Fact is the checker's annotation of this node; nil until it is checked.
	Fact any
}
type Statement struct {
	Pos        Position
	Kind, Name string
	// Compound is the operator of a compound assignment such as "+" for `x += 1`;
	// Value is then the equivalent binary expression over the target.
	Compound   string
	Mutable    bool
	Pattern    *Pattern
	Type       *Type
	Target     *Expression
	Value      *Expression
	Body, Else []*Statement
	// Fact is the checker's annotation of this node; nil until it is checked.
	Fact any
}

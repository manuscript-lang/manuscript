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
}

func (d Diagnostic) Error() string { return fmt.Sprintf("%s: %s: %s", d.Position, d.Phase, d.Message) }

type Type struct {
	Pos    Position
	Name   string
	Args   []*Type
	Params []Parameter
	Result *Type
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
}
type Module struct {
	File         string
	Source       string
	Imports      []*Import
	Declarations []*Declaration
}

// Import represents one symbol binding; named import lists expand into bindings.
type Import struct {
	Pos        Position
	NamePos    Position
	Name, Path string
}
type Declaration struct {
	Pos                        Position
	Kind, Name                 string
	Export                     bool
	TypeParams                 []TypeParameter
	Fields                     []Parameter
	Cases                      []Case
	Methods                    []*Declaration
	Params                     []Parameter
	Result, Contract, Receiver *Type
	Body                       []*Statement
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
	Elements    []*Expression
	Parts       []TextPart
	Params      []Parameter
	Result      *Type
	Body        []*Statement
}
type Pattern struct {
	Pos        Position
	Kind, Name string
	Elements   []*Pattern
	Fields     []PatternField
}
type PatternField struct {
	Pos     Position
	Name    string
	Pattern *Pattern
}
type Arm struct {
	Pos   Position
	Path  *Expression
	Names []string
	Body  []*Statement
}
type Statement struct {
	Pos        Position
	Kind, Name string
	Mutable    bool
	Pattern    *Pattern
	Type       *Type
	Value      *Expression
	Body, Else []*Statement
	Arms       []Arm
}

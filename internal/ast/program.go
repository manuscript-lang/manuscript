package ast

// Program represents the root of the AST
type Program struct {
	BaseNode
	Declarations []Declaration
}

// Import/Export/Extern Declarations

type ImportDecl struct {
	BaseNode
	Import ModuleImport
}

type ExportDecl struct {
	BaseNode
	Item Declaration // The exported declaration
}

type ExternDecl struct {
	BaseNode
	Import ModuleImport
}

// Module Import Types

type ModuleImport interface {
	Node
}

type DestructuredImport struct {
	BaseNode
	Items  []ImportItem
	Module string // The module path
}

type TargetImport struct {
	NamedNode
	Module string // The module path
}

type ImportItem struct {
	NamedNode
	Alias string // Optional alias, empty if no alias
}

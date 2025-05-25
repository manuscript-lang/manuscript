package ast

// Program represents the root of the AST
type Program struct {
	BaseNode
	Declarations []Declaration
}

func (p *Program) Accept(v Visitor) {
	if v = v.Visit(p); v != nil {
		for _, decl := range p.Declarations {
			decl.Accept(v)
		}
	}
}

// Import/Export/Extern Declarations

type ImportDecl struct {
	BaseNode
	Import ModuleImport
}

func (d *ImportDecl) Accept(v Visitor) {
	if v = v.Visit(d); v != nil {
		d.Import.Accept(v)
	}
}

type ExportDecl struct {
	BaseNode
	Item Declaration // The exported declaration
}

func (d *ExportDecl) Accept(v Visitor) {
	if v = v.Visit(d); v != nil {
		d.Item.Accept(v)
	}
}

type ExternDecl struct {
	BaseNode
	Import ModuleImport
}

func (d *ExternDecl) Accept(v Visitor) {
	if v = v.Visit(d); v != nil {
		d.Import.Accept(v)
	}
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

func (i *DestructuredImport) Accept(v Visitor) {
	if v = v.Visit(i); v != nil {
		for _, item := range i.Items {
			item.Accept(v)
		}
	}
}

type TargetImport struct {
	NamedNode
	Module string // The module path
}

func (i *TargetImport) Accept(v Visitor) {
	v.Visit(i)
}

type ImportItem struct {
	NamedNode
	Alias string // Optional alias, empty if no alias
}

func (i *ImportItem) Accept(v Visitor) {
	v.Visit(i)
}

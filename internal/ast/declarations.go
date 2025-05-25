package ast

// Let Declarations

type LetDecl struct {
	BaseNode
	Items []LetItem
}

func (d *LetDecl) Accept(v Visitor) {
	if v = v.Visit(d); v != nil {
		for _, item := range d.Items {
			item.Accept(v)
		}
	}
}

// LetItem represents different forms of let declarations
type LetItem interface {
	Node
}

type LetSingle struct {
	BaseNode
	ID    TypedID
	Value Expression // Optional, nil if no assignment
	IsTry bool       // true if using try expression
}

func (l *LetSingle) Accept(v Visitor) {
	if v = v.Visit(l); v != nil {
		l.ID.Accept(v)
		if l.Value != nil {
			l.Value.Accept(v)
		}
	}
}

type LetBlock struct {
	BaseNode
	Items []LetBlockItem
}

func (l *LetBlock) Accept(v Visitor) {
	if v = v.Visit(l); v != nil {
		for _, item := range l.Items {
			item.Accept(v)
		}
	}
}

type LetBlockItem interface {
	Node
}

type LetBlockItemSingle struct {
	BaseNode
	ID    TypedID
	Value Expression
}

func (l *LetBlockItemSingle) Accept(v Visitor) {
	if v = v.Visit(l); v != nil {
		l.ID.Accept(v)
		l.Value.Accept(v)
	}
}

type LetBlockItemDestructuredObj struct {
	BaseNode
	IDs   []TypedID
	Value Expression
}

func (l *LetBlockItemDestructuredObj) Accept(v Visitor) {
	if v = v.Visit(l); v != nil {
		for _, id := range l.IDs {
			id.Accept(v)
		}
		l.Value.Accept(v)
	}
}

type LetBlockItemDestructuredArray struct {
	BaseNode
	IDs   []TypedID
	Value Expression
}

func (l *LetBlockItemDestructuredArray) Accept(v Visitor) {
	if v = v.Visit(l); v != nil {
		for _, id := range l.IDs {
			id.Accept(v)
		}
		l.Value.Accept(v)
	}
}

type LetDestructuredObj struct {
	BaseNode
	IDs   []TypedID
	Value Expression
}

func (l *LetDestructuredObj) Accept(v Visitor) {
	if v = v.Visit(l); v != nil {
		for _, id := range l.IDs {
			id.Accept(v)
		}
		l.Value.Accept(v)
	}
}

type LetDestructuredArray struct {
	BaseNode
	IDs   []TypedID
	Value Expression
}

func (l *LetDestructuredArray) Accept(v Visitor) {
	if v = v.Visit(l); v != nil {
		for _, id := range l.IDs {
			id.Accept(v)
		}
		l.Value.Accept(v)
	}
}

// TypedID represents an identifier with optional type annotation
type TypedID struct {
	NamedNode
	Type TypeAnnotation // Optional, nil if no type annotation
}

func (t *TypedID) Accept(v Visitor) {
	if v = v.Visit(t); v != nil {
		if t.Type != nil {
			t.Type.Accept(v)
		}
	}
}

// Type and Interface Declarations

type TypeDecl struct {
	NamedNode
	Body TypeBody
}

func (d *TypeDecl) Accept(v Visitor) {
	if v = v.Visit(d); v != nil {
		d.Body.Accept(v)
	}
}

type TypeBody interface {
	Node
}

type TypeDefBody struct {
	BaseNode
	Extends []TypeAnnotation // Optional extends clause
	Fields  []FieldDecl
}

func (t *TypeDefBody) Accept(v Visitor) {
	if v = v.Visit(t); v != nil {
		for _, ext := range t.Extends {
			ext.Accept(v)
		}
		for _, field := range t.Fields {
			field.Accept(v)
		}
	}
}

type TypeAlias struct {
	BaseNode
	Type    TypeAnnotation
	Extends []TypeAnnotation // Optional extends clause
}

func (t *TypeAlias) Accept(v Visitor) {
	if v = v.Visit(t); v != nil {
		t.Type.Accept(v)
		for _, ext := range t.Extends {
			ext.Accept(v)
		}
	}
}

type FieldDecl struct {
	NamedNode
	Optional bool // true if field has ? modifier
	Type     TypeAnnotation
}

func (f *FieldDecl) Accept(v Visitor) {
	if v = v.Visit(f); v != nil {
		f.Type.Accept(v)
	}
}

type InterfaceDecl struct {
	NamedNode
	Extends []TypeAnnotation // Optional extends clause
	Methods []InterfaceMethod
}

func (d *InterfaceDecl) Accept(v Visitor) {
	if v = v.Visit(d); v != nil {
		for _, ext := range d.Extends {
			ext.Accept(v)
		}
		for _, method := range d.Methods {
			method.Accept(v)
		}
	}
}

type InterfaceMethod struct {
	NamedNode
	Parameters []Parameter
	ReturnType TypeAnnotation // Optional, nil if no return type
	CanThrow   bool           // true if method has ! modifier
}

func (m *InterfaceMethod) Accept(v Visitor) {
	if v = v.Visit(m); v != nil {
		for _, param := range m.Parameters {
			param.Accept(v)
		}
		if m.ReturnType != nil {
			m.ReturnType.Accept(v)
		}
	}
}

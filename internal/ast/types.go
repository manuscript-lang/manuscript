package ast

// Type Annotations with flat modifier support

// TypeKind represents the different kinds of types
type TypeKind int

const (
	SimpleType   TypeKind = iota // int, string, MyType, etc.
	ArrayType                    // Type[] (modifies another type)
	TupleType                    // (Type1, Type2, ...)
	FunctionType                 // fn(params): returnType
	VoidType                     // void
)

// TypeSpec represents all type annotations with modifiers
type TypeSpec struct {
	BaseNode
	Kind TypeKind

	// Basic type information
	Name string // For SimpleType: the type name (int, string, MyType)

	// Modifiers that can apply to any type
	IsArray    bool // true for Type[]
	IsOptional bool // true for Type?
	CanThrow   bool // true for Type!

	// For ArrayType: the element type
	ElementType TypeAnnotation

	// For FunctionType
	Parameters []Parameter
	ReturnType TypeAnnotation // nil if no return type

	// For TupleType
	ElementTypes []TypeAnnotation
}

func (t *TypeSpec) Accept(v Visitor) {
	if v = v.Visit(t); v != nil {
		// Visit element type for arrays
		if t.ElementType != nil {
			t.ElementType.Accept(v)
		}

		// Visit parameters for functions
		for _, param := range t.Parameters {
			param.Accept(v)
		}

		// Visit return type for functions
		if t.ReturnType != nil {
			t.ReturnType.Accept(v)
		}

		// Visit element types for tuples
		for _, elem := range t.ElementTypes {
			elem.Accept(v)
		}
	}
}

// Helper constructors for common type patterns

// NewSimpleType creates a simple type like int, string, MyType
func NewSimpleType(name string) *TypeSpec {
	return &TypeSpec{
		Kind: SimpleType,
		Name: name,
	}
}

// NewArrayType creates an array type like int[], string[]
func NewArrayType(elementType TypeAnnotation) *TypeSpec {
	return &TypeSpec{
		Kind:        ArrayType,
		ElementType: elementType,
	}
}

// NewOptionalType creates an optional type like string?, int?
func NewOptionalType(baseType *TypeSpec) *TypeSpec {
	result := *baseType // Copy the base type
	result.IsOptional = true
	return &result
}

// NewThrowingType creates a throwing type like fn()!
func NewThrowingType(baseType *TypeSpec) *TypeSpec {
	result := *baseType // Copy the base type
	result.CanThrow = true
	return &result
}

// NewFunctionType creates a function type
func NewFunctionType(parameters []Parameter, returnType TypeAnnotation) *TypeSpec {
	return &TypeSpec{
		Kind:       FunctionType,
		Parameters: parameters,
		ReturnType: returnType,
	}
}

// NewTupleType creates a tuple type like (int, string)
func NewTupleType(elementTypes []TypeAnnotation) *TypeSpec {
	return &TypeSpec{
		Kind:         TupleType,
		ElementTypes: elementTypes,
	}
}

// NewVoidType creates a void type
func NewVoidType() *TypeSpec {
	return &TypeSpec{
		Kind: VoidType,
	}
}

// Helper methods for type inspection

// IsSimple checks if this is a simple named type
func (t *TypeSpec) IsSimple() bool {
	return t.Kind == SimpleType
}

// IsFunction checks if this is a function type
func (t *TypeSpec) IsFunction() bool {
	return t.Kind == FunctionType
}

// IsTuple checks if this is a tuple type
func (t *TypeSpec) IsTuple() bool {
	return t.Kind == TupleType
}

// IsVoid checks if this is the void type
func (t *TypeSpec) IsVoid() bool {
	return t.Kind == VoidType
}

// GetTypeName returns a descriptive name for the type
func (t *TypeSpec) GetTypeName() string {
	switch t.Kind {
	case SimpleType:
		return t.Name
	case ArrayType:
		if t.ElementType != nil {
			return t.ElementType.(*TypeSpec).GetTypeName() + "[]"
		}
		return "unknown[]"
	case TupleType:
		return "tuple"
	case FunctionType:
		return "fn"
	case VoidType:
		return "void"
	default:
		return "unknown"
	}
}

// Implement Type interface for TypeSpec

// String returns a string representation of the type
func (t *TypeSpec) String() string {
	return t.GetTypeName()
}

// Equals checks if two types are equal
func (t *TypeSpec) Equals(other Type) bool {
	otherSpec, ok := other.(*TypeSpec)
	if !ok || t.Kind != otherSpec.Kind {
		return false
	}

	switch t.Kind {
	case SimpleType:
		return t.Name == otherSpec.Name
	case ArrayType:
		if t.ElementType == nil || otherSpec.ElementType == nil {
			return t.ElementType == otherSpec.ElementType
		}
		return t.ElementType.(*TypeSpec).Equals(otherSpec.ElementType.(*TypeSpec))
	case FunctionType:
		if len(t.Parameters) != len(otherSpec.Parameters) {
			return false
		}
		for i, param := range t.Parameters {
			if !param.Type.(*TypeSpec).Equals(otherSpec.Parameters[i].Type.(*TypeSpec)) {
				return false
			}
		}
		if t.ReturnType == nil && otherSpec.ReturnType == nil {
			return t.CanThrow == otherSpec.CanThrow
		}
		if t.ReturnType != nil && otherSpec.ReturnType != nil {
			return t.ReturnType.(*TypeSpec).Equals(otherSpec.ReturnType.(*TypeSpec)) &&
				t.CanThrow == otherSpec.CanThrow
		}
		return false
	case TupleType:
		if len(t.ElementTypes) != len(otherSpec.ElementTypes) {
			return false
		}
		for i, elem := range t.ElementTypes {
			if !elem.(*TypeSpec).Equals(otherSpec.ElementTypes[i].(*TypeSpec)) {
				return false
			}
		}
		return true
	case VoidType:
		return true
	}
	return false
}

// IsAssignableTo checks if this type can be assigned to another type
func (t *TypeSpec) IsAssignableTo(other Type) bool {
	return t.Equals(other)
}

// IsCompatibleWith checks if this type is compatible with another type
func (t *TypeSpec) IsCompatibleWith(other Type) bool {
	return t.Equals(other)
}

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

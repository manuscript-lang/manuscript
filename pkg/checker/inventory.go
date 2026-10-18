package checker

import (
	"sort"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// NativeOperation is a receiver operation of a standard type that the runtime
// implements: a method with no source body.
type NativeOperation struct {
	Receiver  *Type
	Name      string
	Type      *Type   // the signature with the receiver's variables in terms of Receiver.Def.Variables
	Variables []*Type // the operation's own type variables
	// Requirements are the receiver variables the operation constrains beyond
	// the type's own bounds, such as List.contains needing T: Equal.
	Requirements []Requirement
	Decl         *syntax.Declaration
}

// Requirement constrains a receiver variable for one operation.
type Requirement struct {
	Variable   *Type
	Constraint *Type
}

// Inventory lists the native standard declarations a runtime must implement.
type Inventory struct {
	// Types are the standard types and contracts in declaration order.
	Types []*Symbol
	// Functions are the native module functions.
	Functions []*Symbol
	// Operations are the native receiver operations.
	Operations []NativeOperation
	// Implementations are native implementations of contracts for standard types.
	Implementations []*Method
}

// StandardInventory describes every native standard declaration.
func StandardInventory() *Inventory {
	ensureStandard()
	inv := &Inventory{Implementations: standardImplementations}
	for _, module := range standardSources {
		if standardSourceModules[module.File] != nil {
			continue
		}
		for _, d := range module.Declarations {
			s := standardModules[module.File][d.Name]
			if s == nil {
				continue
			}
			if s.Kind == syntax.KindFn {
				inv.Functions = append(inv.Functions, s)
				continue
			}
			inv.Types = append(inv.Types, s)
			if s.Type.Kind == "contract" {
				continue
			}
			inv.addOperations(s)
		}
	}
	// Primitive receivers take their operations from the intrinsic declarations.
	var receivers []string
	for name := range intrinsicOperations {
		receivers = append(receivers, name)
	}
	sort.Strings(receivers)
	for _, name := range receivers {
		intrinsic := intrinsicOperations[name]
		primitive := primitive(name)
		for _, op := range intrinsic.Def.Operations {
			inv.Operations = append(inv.Operations, NativeOperation{
				Receiver: primitive, Name: op.Name, Type: op.Type,
				Variables: standardOperationVariables[intrinsic.ID+"/"+op.Name], Decl: op.Decl,
			})
		}
	}
	return inv
}

func (inv *Inventory) addOperations(s *Symbol) {
	for _, op := range s.Type.Def.Operations {
		native := s.Type.Kind == syntax.KindNative || standardReceiverBindings[s.ID+"/"+op.Name] != "" ||
			s.Type.Kind == "alternative" && s.Native != "" && standardReceiverBindings[s.ID+"/"+op.Name] != ""
		if !native {
			continue
		}
		n := NativeOperation{Receiver: s.Type, Name: op.Name, Type: op.Type, Variables: standardOperationVariables[s.ID+"/"+op.Name], Decl: op.Decl}
		for _, r := range standardReceiverRequirements[s.ID+"/"+op.Name] {
			n.Requirements = append(n.Requirements, Requirement(r))
		}
		inv.Operations = append(inv.Operations, n)
	}
}

// Capability is a type variable whose native operation needs the program to
// supply how to compare or hash its values: Go cannot see Manuscript's Equal
// and Hashable implementations from inside the runtime.
type Capability struct {
	Variable *Type
	Property string // "Equal", "Hashable", or "Comparable"
}

// OperationCapabilities lists, in order, the capabilities a native operation
// takes before its receiver: first the receiver variables its requirements
// constrain, then its own bounded variables.
func OperationCapabilities(receiver *Type, requirements []Requirement, variables []*Type) []Capability {
	var out []Capability
	for _, r := range requirements {
		if std(r.Constraint, "Equal") || std(r.Constraint, "Hashable") || std(r.Constraint, "Comparable") {
			out = append(out, Capability{Variable: r.Variable, Property: r.Constraint.Name})
		}
	}
	out = append(out, BoundCapabilities(variables)...)
	return out
}

// BoundCapabilities lists the Equal, Hashable, or Comparable bounds of variables.
func BoundCapabilities(variables []*Type) []Capability {
	var out []Capability
	for _, v := range variables {
		property := ""
		comparable := false
		for _, b := range v.Bounds {
			if std(b, "Hashable") {
				property = "Hashable"
			} else if std(b, "Equal") && property == "" {
				property = "Equal"
			}
			comparable = comparable || std(b, "Comparable")
		}
		if property != "" {
			out = append(out, Capability{Variable: v, Property: property})
		}
		if comparable {
			out = append(out, Capability{Variable: v, Property: "Comparable"})
		}
	}
	return out
}

// NativeOperationFor finds the native operation a Method call resolved to, so
// lowering can read its requirements.
func NativeOperationFor(receiver *Type, name string) (NativeOperation, bool) {
	ensureStandard()
	r := receiver
	if intrinsic := intrinsicOperations[receiver.ID]; intrinsic != nil {
		r = intrinsic
	}
	if r.Def == nil {
		return NativeOperation{}, false
	}
	for _, op := range r.Def.Operations {
		if op.Name == name {
			n := NativeOperation{Receiver: receiver, Name: name, Type: op.Type, Variables: standardOperationVariables[r.ID+"/"+name], Decl: op.Decl}
			for _, req := range standardReceiverRequirements[r.ID+"/"+name] {
				n.Requirements = append(n.Requirements, Requirement(req))
			}
			return n, true
		}
	}
	return NativeOperation{}, false
}

// StandardContract is the prelude contract with the given name, such as Comparable.
func StandardContract(name string) *Type {
	ensureStandard()
	return standard(name)
}

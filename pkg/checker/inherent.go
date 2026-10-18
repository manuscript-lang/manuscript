package checker

import (
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// inherentSuffix names the interface synthesized for a type's own methods.
// It cannot be written in source, so no program can refer to it.
const inherentSuffix = "$methods"

type inherentError struct {
	pos     syntax.Position
	message string
}

// desugarInherentImpls rewrites each `impl Type:` block of a source module into
// `impl Type$methods for Type:` with a synthesized interface carrying the same
// signatures. A type's own methods then use the ordinary implementation rules:
// visibility wherever the type is used, exact signatures, selection by receiver,
// and lowering as plain methods. Blocks for one type merge into the first. The
// rewrite is in place and idempotent.
func desugarInherentImpls(modules []*syntax.Module) []inherentError {
	var errs []inherentError
	for _, module := range modules {
		types := map[string]*syntax.Declaration{}
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindRecord || d.Kind == "alternative" || d.Kind == syntax.KindInterface {
				types[d.Name] = d
			}
		}
		first := map[string]*syntax.Declaration{}
		var out []*syntax.Declaration
		for _, d := range module.Declarations {
			if d.Kind != syntax.KindImpl || d.Contract != nil {
				out = append(out, d)
				continue
			}
			name := d.Receiver.Name
			target := types[name]
			switch {
			case target == nil:
				errs = append(errs, inherentError{d.Pos, "inherent methods belong in the module that declares " + name + "; to add operations to another module's type, declare an interface and write 'impl <Interface> for " + name + ":'"})
			case target.Kind == syntax.KindInterface:
				errs = append(errs, inherentError{d.Pos, name + " is an interface; 'impl " + name + ":' declares a type's own methods, so write 'impl " + name + " for <Type>:' to implement the interface"})
			case !repeatsTypeParameters(d.Receiver, target):
				errs = append(errs, inherentError{d.Pos, "impl must repeat the type parameters of " + name + " as its receiver arguments, as in 'impl " + name + parameterNames(target) + ":'"})
			default:
				if merged := first[name]; merged != nil {
					merged.Methods = append(merged.Methods, d.Methods...)
					continue
				}
				first[name] = d
				out = append(out, d)
			}
		}
		final := make([]*syntax.Declaration, 0, len(out)+len(first))
		for _, d := range out {
			if d.Kind != syntax.KindImpl || d.Contract != nil {
				final = append(final, d)
				continue
			}
			target := types[d.Receiver.Name]
			contract := &syntax.Declaration{Pos: d.Pos, Kind: syntax.KindInterface, Name: d.Receiver.Name + inherentSuffix, TypeParams: target.TypeParams, Synthetic: true}
			for _, method := range d.Methods {
				if len(method.TypeParams) > 0 {
					errs = append(errs, inherentError{method.Pos, "method " + method.Name + " declares its own type parameters, which source methods do not support yet; use a generic function that takes the receiver as an argument"})
				}
				signature := *method
				signature.Body = nil
				signature.Params = append([]syntax.Parameter(nil), method.Params...)
				for i := range signature.Params {
					signature.Params[i].Default = nil
				}
				contract.Methods = append(contract.Methods, &signature)
			}
			d.Contract = &syntax.Type{Pos: d.Pos, Name: contract.Name, Args: d.Receiver.Args}
			d.Synthetic = true
			final = append(final, contract, d)
		}
		out = final
		module.Declarations = out
	}
	return errs
}

func repeatsTypeParameters(receiver *syntax.Type, target *syntax.Declaration) bool {
	if len(receiver.Args) != len(target.TypeParams) {
		return false
	}
	for i, argument := range receiver.Args {
		if argument.Name != target.TypeParams[i].Name || len(argument.Args) > 0 {
			return false
		}
	}
	return true
}

func parameterNames(target *syntax.Declaration) string {
	if len(target.TypeParams) == 0 {
		return ""
	}
	names := make([]string, len(target.TypeParams))
	for i, p := range target.TypeParams {
		names[i] = p.Name
	}
	return "[" + strings.Join(names, ", ") + "]"
}

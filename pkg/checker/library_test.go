package checker

import (
	"fmt"
	rt "github.com/manuscript-lang/manuscript/pkg/runtime"
	"strings"
	"testing"
)

func libraryParseType(s string, vars map[string]*Type) *Type {
	if strings.HasPrefix(s, "fn(") {
		end := strings.Index(s, ")->")
		var ps []Param
		for _, item := range strings.Split(s[3:end], ";") {
			if item == "" {
				continue
			}
			name, typ, _ := strings.Cut(item, ":")
			ps = append(ps, Param{name, libraryParseType(typ, vars)})
		}
		return function(ps, libraryParseType(s[end+3:], vars))
	}
	name := s
	var args []*Type
	if at := strings.IndexByte(s, '['); at >= 0 {
		name = s[:at]
		for at < len(s) {
			start := at + 1
			depth := 1
			at++
			for at < len(s) && depth > 0 {
				if s[at] == '[' {
					depth++
				}
				if s[at] == ']' {
					depth--
				}
				at++
			}
			args = append(args, libraryParseType(s[start:at-1], vars))
		}
	}
	var t *Type
	if vars[name] != nil {
		t = vars[name]
	} else if standardSymbols[name] != nil {
		t = standard(name, args...)
	} else {
		t = primitive(name)
	}
	return t
}

func validateStandardNativeBindings() error {
	ensureStandard()
	receivers := map[string][2]string{}
	for receiver, operations := range rt.NativeLibraryBindings {
		typ := standardSymbols[receiver]
		if intrinsic := intrinsicOperations[receiver]; intrinsic != nil {
			typ = intrinsic.Def.Symbol
		}
		if typ == nil {
			return fmt.Errorf("missing native library receiver %s", receiver)
		}
		for name, identity := range operations {
			if standardReceiverBindings[typ.ID+"/"+name] != identity {
				return fmt.Errorf("native receiver binding does not match source: %s.%s", receiver, name)
			}
			receivers[identity] = [2]string{receiver, name}
		}
	}
	if len(receivers) != len(standardReceiverBindings) {
		return fmt.Errorf("native receiver bindings do not cover source declarations")
	}
	for _, spec := range rt.Library {
		if target, ok := receivers[spec.Module+"/"+spec.Name]; ok {
			if err := validateNativeReceiverSignature(target[0], target[1], spec); err != nil {
				return err
			}
			delete(receivers, spec.Module+"/"+spec.Name)
			continue
		}
		s := standardExports("@std/" + spec.Module + ".ms")[spec.Name]
		if s == nil {
			return fmt.Errorf("missing source declaration for native function %s/%s", spec.Module, spec.Name)
		}
		vars := map[string]*Type{}
		for _, v := range s.Variables {
			vars[v.Name] = v
		}
		params := []Param{}
		for _, p := range spec.Params {
			params = append(params, Param{p.Name, libraryParseType(p.Type, vars)})
		}
		expected := function(params, libraryParseType(spec.Result, vars))
		if !Same(s.Type, expected) {
			return fmt.Errorf("native signature does not match source: %s", s.Decl.Pos)
		}
	}
	for identity := range receivers {
		return fmt.Errorf("missing native receiver implementation %s", identity)
	}
	for _, method := range standardImplementations {
		found := false
		for _, spec := range rt.NativeImplementations {
			if spec.Name != method.Native {
				continue
			}
			found = true
			params := []Param{}
			for _, p := range spec.Params {
				params = append(params, Param{p.Name, libraryParseType(p.Type, nil)})
			}
			if !Same(method.Type, function(params, libraryParseType(spec.Result, nil))) {
				return fmt.Errorf("native implementation does not match source: %s", method.Decl.Pos)
			}
		}
		if !found {
			return fmt.Errorf("unavailable native implementation: %s", method.Decl.Pos)
		}
	}
	for _, spec := range rt.LibraryMethods {
		s := standardSymbols[spec.Receiver]
		if s == nil {
			return fmt.Errorf("missing native receiver %s", spec.Receiver)
		}
		var actual *Type
		for _, op := range s.Type.Def.Operations {
			if op.Name == spec.Name {
				actual = op.Type
			}
		}
		params := []Param{}
		for _, p := range spec.Params {
			params = append(params, Param{p.Name, libraryParseType(p.Type, nil)})
		}
		if !Same(actual, function(params, libraryParseType(spec.Result, nil))) {
			return fmt.Errorf("native operation does not match source: %s.%s", spec.Receiver, spec.Name)
		}
	}
	return nil
}

func validateNativeReceiverSignature(receiver, name string, spec rt.LibrarySpec) error {
	typ := standardSymbols[receiver]
	var receiverType *Type
	if intrinsic := intrinsicOperations[receiver]; intrinsic != nil {
		typ = intrinsic.Def.Symbol
		receiverType = primitive(receiver)
	} else {
		receiverType = typ.Type
	}
	method := nativeMethod(receiverType, name)
	if method == nil || len(spec.Params) == 0 {
		return fmt.Errorf("missing native member declaration %s.%s", receiver, name)
	}
	vars := map[string]*Type{}
	for i, variable := range typ.Variables {
		if i < len(spec.Variables) {
			vars[spec.Variables[i].Name] = variable
		}
	}
	for _, variable := range method.Variables {
		vars[variable.Name] = variable
	}
	fixed := map[string]*Type{}
	for _, requirement := range standardReceiverRequirements[typ.ID+"/"+name] {
		if requirement.Constraint.Kind != "contract" {
			fixed[requirement.Variable.ID] = requirement.Constraint
		}
	}
	if len(spec.Variables) != len(typ.Variables)-len(fixed)+len(method.Variables) {
		return fmt.Errorf("native member variables do not match source: %s.%s", receiver, name)
	}
	for _, variable := range spec.Variables {
		checked := vars[variable.Name]
		if checked == nil {
			return fmt.Errorf("unknown native member variable %s in %s.%s", variable.Name, receiver, name)
		}
		bounds := append([]*Type{}, checked.Bounds...)
		for _, requirement := range standardReceiverRequirements[typ.ID+"/"+name] {
			if requirement.Variable == checked && requirement.Constraint.Kind == "contract" {
				bounds = append(bounds, requirement.Constraint)
			}
		}
		if len(bounds) == 0 && variable.Type != "" || len(bounds) == 1 && bounds[0].Name != variable.Type || len(bounds) > 1 {
			return fmt.Errorf("native member bounds do not match source: %s.%s", receiver, name)
		}
	}
	params := []Param{}
	for _, param := range spec.Params[1:] {
		params = append(params, Param{param.Name, libraryParseType(param.Type, vars)})
	}
	if !Same(Sub(receiverType, fixed), libraryParseType(spec.Params[0].Type, vars)) ||
		!Same(Sub(method.Type, fixed), function(params, libraryParseType(spec.Result, vars))) {
		return fmt.Errorf("native member signature does not match source: %s.%s", receiver, name)
	}
	return nil
}

func TestNativeSignaturesMatchDeclarations(t *testing.T) {
	if err := validateStandardNativeBindings(); err != nil {
		t.Fatal(err)
	}
}

func TestNativeSignatureDriftIsRejected(t *testing.T) {
	original := rt.Library[0]
	defer func() { rt.Library[0] = original }()
	rt.Library[0].Result = "Never"
	if err := validateStandardNativeBindings(); err == nil {
		t.Fatal("accepted an incompatible native result")
	}
}

func TestNativeReceiverSignatureDriftIsRejected(t *testing.T) {
	for i, spec := range rt.Library {
		if spec.Module != "collections" || spec.Name != "contains" {
			continue
		}
		for _, mutation := range []struct {
			name   string
			change func(*rt.LibrarySpec)
		}{
			{"result", func(s *rt.LibrarySpec) { s.Result = "Never" }},
			{"receiver", func(s *rt.LibrarySpec) {
				s.Params = append([]rt.LibraryParam{}, s.Params...)
				s.Params[0].Type = "Set[T]"
			}},
			{"bound", func(s *rt.LibrarySpec) { s.Variables = []rt.LibraryParam{{Name: "T"}} }},
		} {
			t.Run(mutation.name, func(t *testing.T) {
				defer func() { rt.Library[i] = spec }()
				mutation.change(&rt.Library[i])
				if err := validateStandardNativeBindings(); err == nil {
					t.Fatal("accepted an incompatible native receiver signature")
				}
			})
		}
		return
	}
	t.Fatal("missing native list search implementation")
}

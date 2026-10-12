package checker

import (
	"fmt"
	rt "github.com/manuscript-lang/manuscript/runtime"
	"strings"
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
	for _, spec := range rt.Library {
		s := standardModules["@std/"+spec.Module+".ms"][spec.Name]
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
	for receiver, operations := range rt.NativeLibraryBindings {
		typ := standardSymbols[receiver]
		if intrinsic := intrinsicOperations[receiver]; intrinsic != nil {
			typ = intrinsic.Def.Symbol
		}
		if typ == nil {
			return fmt.Errorf("missing native library receiver %s", receiver)
		}
		for name := range operations {
			spec, ok := rt.NativeLibrarySpec(receiver, name)
			if !ok {
				return fmt.Errorf("missing native member function %s.%s", receiver, name)
			}
			receiverType := typ.Type
			if intrinsicOperations[receiver] != nil {
				receiverType = primitive(receiver)
			}
			method := nativeMethod(receiverType, name)
			if method == nil {
				return fmt.Errorf("missing native member declaration %s.%s", receiver, name)
			}
			vars := map[string]*Type{}
			for i, v := range typ.Variables {
				if i < len(spec.Variables) {
					vars[spec.Variables[i].Name] = v
				}
			}
			for _, v := range method.Variables {
				vars[v.Name] = v
			}
			params := []Param{}
			for _, p := range spec.Params[1:] {
				params = append(params, Param{p.Name, libraryParseType(p.Type, vars)})
			}
			if !Same(method.Type, function(params, libraryParseType(spec.Result, vars))) {
				return fmt.Errorf("native member signature does not match source: %s.%s", receiver, name)
			}
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

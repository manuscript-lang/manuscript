package checker

import (
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func documentMembers(decl *syntax.Declaration, source string, receiver *Type) []APIMember {
	var members []APIMember
	for _, field := range decl.Fields {
		signature := field.Name + ": " + documentType(field.Type)
		if field.Default != nil {
			signature += " = " + documentDefault(field, source)
		}
		members = append(members, APIMember{Name: field.Name, Kind: "field", Signature: signature, Doc: leadingComment(source, field.Pos.Offset)})
	}
	for _, c := range decl.Cases {
		signature := "case " + c.Name
		if len(c.Fields) > 0 {
			signature += documentParameters(c.Fields)
		}
		members = append(members, APIMember{Name: c.Name, Kind: "case", Signature: signature, Doc: leadingComment(source, c.Pos.Offset)})
		for _, field := range c.Fields {
			members = append(members, APIMember{Name: c.Name + "." + field.Name, Kind: "field", Signature: field.Name + ": " + documentType(field.Type), Doc: leadingComment(source, field.Pos.Offset)})
		}
	}
	for _, method := range decl.Methods {
		name := documentOperationName(receiver, method.Name)
		signature := strings.TrimSpace(documentDeclaration(method, "fn", method.Name, source))
		if decl.Kind == "interface" {
			signature = strings.TrimSuffix(signature, ":")
		}
		kind := "operation"
		if method.Accessor {
			kind = "accessor"
		}
		members = append(members, APIMember{Name: name, Kind: kind, Signature: signature, Doc: leadingComment(source, method.Pos.Offset)})
	}
	sortAPIMembers(members)
	return members
}

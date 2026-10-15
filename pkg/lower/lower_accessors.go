package lower

import (
	"go/ast"
	"go/token"
	"strconv"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// nativeAccessorHelper is chosen from checked receiver and operation identities,
// before lowering the receiver. Probing eligibility must never emit operands.
func (g *generator) nativeAccessorHelper(e *syntax.Expression, info *checker.Info) string {
	if info.Method == nil || !info.Method.Accessor || info.Method.Native == "" || info.Method.Native == "contract" {
		return ""
	}
	receiver := g.program.Info(e.Left).Type
	if receiver == nil {
		return ""
	}
	return nativeAccessorHelpers[receiver.ID+"/"+e.Text]
}

var nativeAccessorHelpers = map[string]string{
	"@std/List/length": "ListLengthRead", "@std/List/is_empty": "ListIsEmptyRead", "@std/List/first": "ListFirstRead", "@std/List/last": "ListLastRead",
	"@std/Map/length": "MapLengthRead", "@std/Map/is_empty": "MapIsEmptyRead",
	"@std/Set/length": "SetLengthRead", "@std/Set/is_empty": "SetIsEmptyRead",
	"@std/Bytes/length": "BytesLengthRead", "@std/Bytes/is_empty": "BytesIsEmptyRead",
	"String/byte_length": "StringByteLengthRead", "String/length": "StringLengthRead", "String/scalar_length": "StringScalarLengthRead", "String/is_empty": "StringIsEmptyRead",
	"@std/Optional/is_some": "OptionalSomeRead", "@std/Optional/is_none": "OptionalNoneRead",
	"@std/Result/is_ok": "ResultOKRead", "@std/Result/is_error": "ResultErrorRead",
	"Float/is_nan": "FloatNaNRead", "Float/is_finite": "FloatFiniteRead",
	"@std/Queue/length": "QueueLengthRead", "@std/Queue/is_empty": "QueueIsEmptyRead", "@std/Queue/peek": "QueuePeekRead",
	"@std/PriorityQueue/length": "PriorityQueueLengthRead", "@std/PriorityQueue/is_empty": "PriorityQueueIsEmptyRead", "@std/PriorityQueue/peek": "PriorityQueuePeekRead",
	"@std/Timestamp/unix_seconds": "TimestampUnixSecondsRead", "@std/Timestamp/nanoseconds": "TimestampNanosecondsRead",
	"@std/Duration/nanoseconds": "DurationNanosecondsRead", "@std/Duration/microseconds": "DurationMicrosecondsRead", "@std/Duration/milliseconds": "DurationMillisecondsRead",
	"@std/Duration/seconds": "DurationSecondsRead", "@std/Duration/minutes": "DurationMinutesRead", "@std/Duration/hours": "DurationHoursRead",
	"@std/HttpExchange/headers": "HttpExchangeHeadersRead", "@std/HttpExchange/method": "HttpExchangeMethodRead", "@std/HttpExchange/path": "HttpExchangePathRead", "@std/HttpExchange/query": "HttpExchangeQueryRead",
	"@std/ResponseBody/metadata": "ResponseBodyMetadataRead", "@std/ClientResponse/metadata": "ClientResponseMetadataRead",
	"@std/Directory/path": "DirectoryPathRead", "@std/TemporaryDirectory/path": "TemporaryDirectoryPathRead",
	"@std/PathOperations/separator": "PathOperationsSeparatorRead", "@std/PathOperations/delimiter": "PathOperationsDelimiterRead",
	"@std/WebSocket/subprotocol": "WebSocketSubprotocolRead", "@std/Logger/level": "LoggerLevelRead",
	"@std/IpAddress/family": "IpAddressFamilyRead", "@std/DnsKind/text": "DnsKindTextRead", "@std/IpFamily/text": "IpFamilyTextRead", "@std/HttpMethod/text": "HttpMethodTextRead",
	"@std/Connection/local_address": "ConnectionLocalAddressRead", "@std/Connection/peer_address": "ConnectionPeerAddressRead",
	"@std/Listener/address": "ListenerAddressRead", "@std/DatagramSocket/address": "DatagramSocketAddressRead", "@std/HttpServer/address": "HttpServerAddressRead",
	"@std/SynchronizedGuard/value": "SynchronizedGuardValueRead",
	"Int/milliseconds":             "IntMillisecondsRead", "Int/seconds": "IntSecondsRead", "Int/minutes": "IntMinutesRead",
}

// directAccessorTarget is a source accessor whose concrete receiver permits the
// same direct function as an ordinary source method. Views and generic receivers
// keep their implementation evidence through ReadAccessor instead.
func (g *generator) directAccessorTarget(e *syntax.Expression, info *checker.Info) *directFunction {
	if info.Method == nil || !info.Method.Accessor || info.ErrorSource != nil {
		return nil
	}
	direct := g.directMethods[info.Method.ID]
	if direct == nil {
		return nil
	}
	receiver := g.program.Info(e.Left).Type
	if receiver == nil || (receiver.Kind != syntax.KindRecord && receiver.Kind != "alternative") || len(receiver.Args) != 0 || hasTypeVariable(receiver) || receiver.ID != info.Method.Receiver.ID {
		return nil
	}
	return direct
}

func (g *generator) accessorValue(e *syntax.Expression, info *checker.Info) ast.Expr {
	if helper := g.nativeAccessorHelper(e, info); helper != "" {
		var receiver ast.Expr
		switch info.Method.Native {
		case "optional/is_some", "optional/is_none", "result/is_ok", "result/is_error":
			receiver = g.alternativePresence(e.Left)
		case "math/is_nan", "math/is_finite":
			receiver = g.scalar(e.Left, "float64")
		default:
			receiver = g.expression(e.Left)
		}
		value := orderedCall(runtimeName(helper), ident("ctx"), receiver)
		// Guard.value returns its payload through the shared Value ABI. Recover
		// its checked scalar type after validation, without another read.
		if helper == "SynchronizedGuardValueRead" {
			if scalar := primitiveEqualityType(info.Type); scalar != "" {
				return unbox(value, scalar)
			}
		}
		return value
	}
	if direct := g.directAccessorTarget(e, info); direct != nil {
		value := orderedCall(ident(direct.name), ident("ctx"), g.expression(e.Left))
		if direct.shape != nil {
			return call(selector(value, "Box"), g.key(info.Type))
		}
		return value
	}
	return orderedCall(runtimeName("ReadAccessor"), ident("ctx"), g.expression(e.Left), g.key(info.Method.Contract), textLiteral(e.Text), g.typeScope(g.program.Info(e.Left).Type))
}

// alternativePresence reads only the representation's tag. In particular it
// does not box an otherwise typed source result or inspect its payload.
func (g *generator) alternativePresence(e *syntax.Expression) ast.Expr {
	if b, shape := g.altLocalOf(e); shape != nil {
		flag := "Failed"
		if shape.optional {
			flag = "Some"
		}
		return selector(ident(b.ID), flag)
	}
	if e.Kind == syntax.KindCall || e.Kind == syntax.KindMember {
		if value, direct := g.typedDirectCall(e); value != nil && direct.shape != nil {
			flag := "Failed"
			if direct.shape.optional {
				flag = "Some"
			}
			return selector(value, flag)
		}
	}
	value := &ast.TypeAssertExpr{X: g.expression(e), Type: runtimeName("Alternative")}
	tag := "error"
	if g.program.Info(e).Type.ID == "@std/Optional" {
		tag = "some"
	}
	return &ast.BinaryExpr{X: selector(value, "Tag"), Op: token.EQL, Y: textLiteral(tag)}
}

// registerAccessor emits one receiver-only implementation entry, including for
// generic source bodies. A read never constructs a bound Function to execute it.
func (g *generator) registerAccessor(m *checker.Method, fields []ast.Expr, declarations *[]ast.Decl, initialize *[]ast.Stmt) {
	readParams := []*ast.Field{
		field("ctx", &ast.StarExpr{X: runtimeName("Execution")}),
		field("receiver", runtimeName("Value")),
		field("typeArgs", &ast.MapType{Key: ident("string"), Value: ident("string")}),
		field("typeScopes", &ast.MapType{Key: ident("string"), Value: runtimeName("TypeScope")}),
	}
	var read ast.Expr
	if direct := g.directMethods[m.ID]; direct != nil {
		d := m.Decl
		literal := g.directFunctionLiteral(direct, m.Receiver.Name+"."+d.Name, d.Params, d.Result, d.Body, g.program.ParameterBindings(d), g.program.SelfBinding(d), m.Type).(*ast.FuncLit)
		decl := &ast.FuncDecl{Name: ident(direct.name), Type: literal.Type, Body: literal.Body}
		*declarations = append(*declarations, decl)
		*initialize = append(*initialize, evaluated(runtimeCall("RegisterSource", ident(decl.Name.Name), textLiteral(m.Receiver.Name+"."+d.Name))))
		var value ast.Expr = call(ident(direct.name), ident("ctx"), ident("receiver"))
		if direct.shape != nil {
			value = call(selector(value, "Box"), g.key(m.Type.Result))
		}
		read = closure(readParams, runtimeName("Value"),
			evaluated(runtimeCall("Enter", ident("ctx"))),
			define("value", value),
			evaluated(runtimeCall("Exit", ident("ctx"))),
			returned(ident("value")))
	} else {
		_, result, position, body := g.functionParts(m.Receiver.Name+"."+m.Decl.Name, m.Decl.Params, m.Decl.Result, m.Decl.Body, g.program.ParameterBindings(m.Decl), g.program.SelfBinding(m.Decl), m.Type)
		name := "accessorBody" + strconv.Itoa(len(*initialize)+1)
		*initialize = append(*initialize, define(name, closure(readParams, runtimeName("Value"), body...)), evaluated(runtimeCall("RegisterSource", ident(name), textLiteral(m.Receiver.Name+"."+m.Decl.Name))))
		read = closure(readParams, runtimeName("Value"), returned(runtimeCall("SourceAccessorRead", ident("ctx"), ident("receiver"), result, textLiteral(position), ident("typeArgs"), ident("typeScopes"), ident(name))))
	}
	fields = append(fields, keyed("Read", read))
	*initialize = append(*initialize, evaluated(runtimeCall("Register", composite(runtimeName("Implementation"), fields...))))
}

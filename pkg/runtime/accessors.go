package msruntime

import (
	"github.com/manuscript-lang/manuscript/internal/nativeabi"
	"math"
	"strings"
)

// AccessorNative implements receiver-only native reads. It deliberately has no
// callable adaptation: reads cannot manufacture or cache a bound Function.
type AccessorNative interface {
	ReadAccessor(*Execution, string) Value
}

// ReadAccessor resolves an executable member using the receiver's lexical
// implementation evidence. Cached entries contain dispatch targets, never values.
func ReadAccessor(ctx *Execution, receiver Value, contract, name string, scope TypeScope) Value {
	if view, ok := receiver.(View); ok {
		if contract == "" {
			contract = view.Type
		}
		receiver, scope = view.Receiver, view.Scope
	}
	// Int unit reads predate executable properties and intentionally have no
	// cancellation checkpoint. All other dynamic reads retain admission.
	if _, ok := receiver.(int64); ok && (name == "milliseconds" || name == "seconds" || name == "minutes") {
		return NativeAccessorRead(ctx, receiver, name)
	}
	CheckCancelled(ctx)
	key := implementationKey{typ: ConcreteType(receiver), contract: contract, name: name, module: scope.Module, accessor: true}
	if len(scope.Args) > 0 {
		var b strings.Builder
		writeScopeKey(&b, scope)
		key.args = b.String()
	}
	var resolved *resolvedImplementation
	if key.typ != "" {
		if cached, ok := implementationCache.Load(key); ok {
			resolved = cached.(*resolvedImplementation)
		} else {
			resolved = resolveMemberImplementation(key.typ, contract, name, scope, true)
			implementationCache.Store(key, resolved)
		}
		if resolved != nil {
			if resolved.impl.Read == nil {
				return Panic("runtime invariant: accessor has no read implementation")
			}
			value := resolved.impl.Read(ctx, receiver, resolved.sub, resolved.typeScopes)
			CheckCancelled(ctx)
			return value
		}
	}
	value := NativeAccessorRead(ctx, receiver, name)
	CheckCancelled(ctx)
	return value
}

// NativeAccessorRead is the fixed native read entry used when the checked
// receiver is known. Scalar lowering uses the typed helpers below instead.
func NativeAccessorRead(ctx *Execution, receiver Value, name string) Value {
	if view, ok := receiver.(View); ok {
		receiver = view.Receiver
	}
	switch v := receiver.(type) {
	case *List:
		switch name {
		case "length":
			return ListLengthRead(ctx, v)
		case "is_empty":
			return ListIsEmptyRead(ctx, v)
		case "first":
			return ListFirstRead(ctx, v)
		case "last":
			return ListLastRead(ctx, v)
		}
	case *Map:
		switch name {
		case "length":
			return MapLengthRead(ctx, v)
		case "is_empty":
			return MapIsEmptyRead(ctx, v)
		}
	case *Set:
		switch name {
		case "length":
			return SetLengthRead(ctx, v)
		case "is_empty":
			return SetIsEmptyRead(ctx, v)
		}
	case Bytes:
		switch name {
		case "length":
			return BytesLengthRead(ctx, v)
		case "is_empty":
			return BytesIsEmptyRead(ctx, v)
		}
	case string:
		switch name {
		case "length":
			return StringLengthRead(ctx, v)
		case "byte_length":
			return StringByteLengthRead(ctx, v)
		case "is_empty":
			return StringIsEmptyRead(ctx, v)
		case "scalar_length":
			return StringScalarLengthRead(ctx, v)
		}
	case float64:
		switch name {
		case "is_nan":
			return FloatNaNRead(ctx, v)
		case "is_finite":
			return FloatFiniteRead(ctx, v)
		}
	case int64:
		switch name {
		case "milliseconds":
			return IntMillisecondsRead(ctx, v)
		case "seconds":
			return IntSecondsRead(ctx, v)
		case "minutes":
			return IntMinutesRead(ctx, v)
		}
	case Duration:
		switch name {
		case "nanoseconds":
			return DurationNanosecondsRead(ctx, v)
		case "microseconds":
			return DurationMicrosecondsRead(ctx, v)
		case "milliseconds":
			return DurationMillisecondsRead(ctx, v)
		case "seconds":
			return DurationSecondsRead(ctx, v)
		case "minutes":
			return DurationMinutesRead(ctx, v)
		case "hours":
			return DurationHoursRead(ctx, v)
		}
	case libraryTimestamp:
		switch name {
		case "unix_seconds":
			return TimestampUnixSecondsRead(ctx, v)
		case "nanoseconds":
			return TimestampNanosecondsRead(ctx, v)
		}
	case Alternative:
		kind, _, _ := strings.Cut(v.Type, "[")
		switch kind {
		case "@std/Optional":
			switch name {
			case "is_some":
				return OptionalSomeRead(ctx, v.Tag == "some")
			case "is_none":
				return OptionalNoneRead(ctx, v.Tag == "some")
			}
		case "@std/Result":
			switch name {
			case "is_ok":
				return ResultOKRead(ctx, v.Tag == "error")
			case "is_error":
				return ResultErrorRead(ctx, v.Tag == "error")
			}
		case "@std/DnsKind":
			if name == "text" {
				return DnsKindTextRead(ctx, v)
			}
		case "@std/IpFamily":
			if name == "text" {
				return IpFamilyTextRead(ctx, v)
			}
		case "@std/HttpMethod":
			if name == "text" {
				return HttpMethodTextRead(ctx, v)
			}
		}
	case Record:
		if v.Type == "@std/ClientResponse" && name == "metadata" {
			return ClientResponseMetadataRead(ctx, v)
		}
	case libraryIPAddress:
		if name == "family" {
			return IpAddressFamilyRead(ctx, v)
		}
	}
	if native, ok := receiver.(AccessorNative); ok {
		return native.ReadAccessor(ctx, name)
	}
	return Panic("runtime invariant: unavailable accessor " + name)
}

func ListLengthRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	return int64(receiver.(*List).Len())
}
func MapLengthRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	return int64(len(receiver.(*Map).Entries))
}
func SetLengthRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	return int64(len(receiver.(*Set).Items))
}
func ListIsEmptyRead(ctx *Execution, receiver Value) bool {
	CheckCancelled(ctx)
	return receiver.(*List).Len() == 0
}
func MapIsEmptyRead(ctx *Execution, receiver Value) bool {
	CheckCancelled(ctx)
	v := len(receiver.(*Map).Entries) == 0
	CheckCancelled(ctx)
	return v
}
func SetIsEmptyRead(ctx *Execution, receiver Value) bool {
	CheckCancelled(ctx)
	v := len(receiver.(*Set).Items) == 0
	CheckCancelled(ctx)
	return v
}
func ListFirstRead(ctx *Execution, receiver Value) Value { return listEndRead(ctx, receiver, false) }
func ListLastRead(ctx *Execution, receiver Value) Value  { return listEndRead(ctx, receiver, true) }
func listEndRead(ctx *Execution, receiver Value, last bool) Value {
	CheckCancelled(ctx)
	list := receiver.(*List)
	typ := typeArguments(list.Type)[0]
	var value Value
	if list.Len() == 0 {
		value = optional(typ, nil, false)
	} else {
		at := 0
		if last {
			at = list.Len() - 1
		}
		value = optional(typ, list.Get(at), true)
	}
	CheckCancelled(ctx)
	return value
}
func BytesLengthRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	v := int64(len(receiver.(Bytes).Items))
	CheckCancelled(ctx)
	return v
}
func BytesIsEmptyRead(ctx *Execution, receiver Value) bool {
	CheckCancelled(ctx)
	v := len(receiver.(Bytes).Items) == 0
	CheckCancelled(ctx)
	return v
}
func StringByteLengthRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	return int64(len(receiver.(string)))
}
func StringLengthRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	return scalarCount(receiver.(string))
}
func StringScalarLengthRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	v := scalarCount(receiver.(string))
	CheckCancelled(ctx)
	return v
}
func StringIsEmptyRead(ctx *Execution, receiver Value) bool {
	CheckCancelled(ctx)
	v := receiver.(string) == ""
	CheckCancelled(ctx)
	return v
}
func OptionalSomeRead(ctx *Execution, some bool) bool {
	CheckCancelled(ctx)
	CheckCancelled(ctx)
	return some
}
func OptionalNoneRead(ctx *Execution, some bool) bool {
	CheckCancelled(ctx)
	CheckCancelled(ctx)
	return !some
}
func ResultOKRead(ctx *Execution, failed bool) bool {
	CheckCancelled(ctx)
	CheckCancelled(ctx)
	return !failed
}
func ResultErrorRead(ctx *Execution, failed bool) bool {
	CheckCancelled(ctx)
	CheckCancelled(ctx)
	return failed
}
func FloatNaNRead(ctx *Execution, value float64) bool {
	CheckCancelled(ctx)
	v := math.IsNaN(value)
	CheckCancelled(ctx)
	return v
}
func FloatFiniteRead(ctx *Execution, value float64) bool {
	CheckCancelled(ctx)
	v := !math.IsNaN(value) && !math.IsInf(value, 0)
	CheckCancelled(ctx)
	return v
}
func IntMillisecondsRead(_ *Execution, receiver Value) Value {
	return duration(receiver, "milliseconds")
}
func IntSecondsRead(_ *Execution, receiver Value) Value { return duration(receiver, "seconds") }
func IntMinutesRead(_ *Execution, receiver Value) Value { return duration(receiver, "minutes") }

func DurationNanosecondsRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	v := int64(receiver.(Duration)) / 1
	CheckCancelled(ctx)
	return v
}

func DurationMicrosecondsRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	v := int64(receiver.(Duration)) / 1000
	CheckCancelled(ctx)
	return v
}

func DurationMillisecondsRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	v := int64(receiver.(Duration)) / 1000000
	CheckCancelled(ctx)
	return v
}

func DurationSecondsRead(ctx *Execution, receiver Value) float64 {
	CheckCancelled(ctx)
	v := float64(receiver.(Duration)) / 1000000000
	CheckCancelled(ctx)
	return v
}

func DurationMinutesRead(ctx *Execution, receiver Value) float64 {
	CheckCancelled(ctx)
	v := float64(receiver.(Duration)) / 60000000000
	CheckCancelled(ctx)
	return v
}

func DurationHoursRead(ctx *Execution, receiver Value) float64 {
	CheckCancelled(ctx)
	v := float64(receiver.(Duration)) / 3600000000000
	CheckCancelled(ctx)
	return v
}

func TimestampUnixSecondsRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	v := receiver.(libraryTimestamp).t.Unix()
	CheckCancelled(ctx)
	return v
}
func TimestampNanosecondsRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	v := int64(receiver.(libraryTimestamp).t.Nanosecond())
	CheckCancelled(ctx)
	return v
}
func ClientResponseMetadataRead(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	v := libraryResponseMetadata(receiver.(Record))
	CheckCancelled(ctx)
	return v
}
func IpAddressFamilyRead(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	family := "IPv6"
	if receiver.(libraryIPAddress).address.Is4() {
		family = "IPv4"
	}
	v := Alternative{"@std/IpFamily", family, nil}
	CheckCancelled(ctx)
	return v
}
func DnsKindTextRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := receiver.(Alternative).Tag
	CheckCancelled(ctx)
	return v
}
func IpFamilyTextRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := receiver.(Alternative).Tag
	CheckCancelled(ctx)
	return v
}
func HttpMethodTextRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := libraryHTTPMethodText(receiver)
	CheckCancelled(ctx)
	return v
}

func QueueLengthRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	v := int64(len(ContractReceiver(receiver).(*Queue).items))
	CheckCancelled(ctx)
	return v
}

func QueueIsEmptyRead(ctx *Execution, receiver Value) bool {
	CheckCancelled(ctx)
	v := len(ContractReceiver(receiver).(*Queue).items) == 0
	CheckCancelled(ctx)
	return v
}

func QueuePeekRead(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	q := ContractReceiver(receiver).(*Queue)
	typ := typeArguments(q.typ)[0]
	var v Value
	if len(q.items) == 0 {
		v = optional(typ, nil, false)
	} else {
		v = optional(typ, q.items[0], true)
	}
	CheckCancelled(ctx)
	return v
}

func PriorityQueueLengthRead(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	v := int64(len(ContractReceiver(receiver).(*PriorityQueue).items))
	CheckCancelled(ctx)
	return v
}

func PriorityQueueIsEmptyRead(ctx *Execution, receiver Value) bool {
	CheckCancelled(ctx)
	v := len(ContractReceiver(receiver).(*PriorityQueue).items) == 0
	CheckCancelled(ctx)
	return v
}

func PriorityQueuePeekRead(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	q := ContractReceiver(receiver).(*PriorityQueue)
	typ := typeArguments(q.typ)[0]
	var v Value
	if len(q.items) == 0 {
		v = optional(typ, nil, false)
	} else {
		v = optional(typ, q.items[0].value, true)
	}
	CheckCancelled(ctx)
	return v
}

func DirectoryPathRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	d := ContractReceiver(receiver).(*libraryDirectory)
	d.mu.Lock()
	v := d.file.Name()
	d.mu.Unlock()
	CheckCancelled(ctx)
	return v
}

func TemporaryDirectoryPathRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	d := ContractReceiver(receiver).(*libraryTemporary)
	d.mu.Lock()
	v := d.path
	d.mu.Unlock()
	CheckCancelled(ctx)
	return v
}

func PathOperationsSeparatorRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := ContractReceiver(receiver).(libraryPaths).native("/")
	CheckCancelled(ctx)
	return v
}

func PathOperationsDelimiterRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := ":"
	if ContractReceiver(receiver).(libraryPaths).windows {
		v = ";"
	}
	CheckCancelled(ctx)
	return v
}

func LoggerLevelRead(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	l := ContractReceiver(receiver).(*libraryLogger)
	l.mu.Lock()
	v := Alternative{Type: "@std/LogLevel", Tag: logLevels[l.threshold]}
	l.mu.Unlock()
	CheckCancelled(ctx)
	return v
}

func SynchronizedGuardValueRead(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	g := ContractReceiver(receiver).(*SynchronizedGuard)
	cell := g.cell
	cell.mu.Lock()
	if cell.holder != g {
		cell.mu.Unlock()
		return Panic(closedGuardMessage)
	}
	v := cell.value
	cell.mu.Unlock()
	CheckCancelled(ctx)
	return v
}

func nativeAccessorMember(receiver Value, name string) bool {
	var kind string
	switch v := receiver.(type) {
	case interface{ accessorKind() string }:
		kind = v.accessorKind()
	case *List:
		kind = "List"
	case *Map:
		kind = "Map"
	case *Set:
		kind = "Set"
	case Bytes:
		kind = "Bytes"
	case string:
		kind = "String"
	case int64:
		kind = "Int"
	case float64:
		kind = "Float"
	case Duration:
		kind = "Duration"
	case libraryTimestamp:
		kind = "Timestamp"
	case libraryIPAddress:
		kind = "IpAddress"
	case Alternative:
		kind, _, _ = strings.Cut(strings.TrimPrefix(v.Type, "@std/"), "[")
	case Record:
		kind = strings.TrimPrefix(v.Type, "@std/")
	}
	return nativeabi.IsAccessor(kind, name)
}

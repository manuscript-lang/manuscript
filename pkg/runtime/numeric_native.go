package msruntime

// Native implementations calculate host sizes and counters in signed64. The
// checked declaration selects their source width; this is not source coercion.
func nativeInteger(value Value) int64 {
	if result, ok := nativeIntegerValue(value); ok {
		return result
	}
	Panic("runtime invariant: native integer parameter")
	return 0
}

func nativeIntegerValue(value Value) (int64, bool) {
	switch value := value.(type) {
	case int64:
		return value, true
	case Int64:
		return int64(value), true
	}
	return 0, false
}

func nativeNumericResult(typ string, value Value) Value {
	name, args := splitType(typ)
	if (name == "@std/Result" || name == "Result") && len(args) == 2 {
		typ = args[0]
	}
	switch typ {
	case "Int64":
		if value, ok := value.(int64); ok {
			return Int64(value)
		}
	case "Float64":
		if value, ok := value.(float64); ok {
			return Float64(value)
		}
	}
	return value
}

// Host factories call this before publishing fresh records. Generic payloads
// and source records never pass through this constructor or get retyped.
func nativeHostRecord(typ string, fields map[string]Value) Record {
	wide := nativeWideHostFields[typ]
	for _, name := range wide {
		if value, ok := fields[name].(int64); ok {
			fields[name] = Int64(value)
		}
	}
	return Record{Type: typ, Fields: fields}
}

var nativeWideHostFields = map[string][]string{
	"@std/FileInfo":       {"size", "block_size", "blocks", "rdev", "device", "inode", "links", "uid", "gid"},
	"@std/FileSystemInfo": {"type_id", "block_size", "blocks", "blocks_free", "blocks_available", "files", "files_free"},
	"@std/MemoryUsage":    {"heap_used", "heap_total", "heap_system", "external", "resident"},
	"@std/CpuUsage":       {"user_microseconds", "system_microseconds"},
	"@std/ResourceUsage":  {"user_microseconds", "system_microseconds", "max_resident_bytes", "minor_faults", "major_faults", "filesystem_reads", "filesystem_writes", "voluntary_switches", "involuntary_switches"},
	"@std/CpuInfo":        {"user", "nice", "system", "idle", "irq"},
	"@std/SystemMetrics":  {"total_memory", "free_memory", "available_memory"},
	"@std/ProcessInfo":    {"uid", "gid", "effective_uid", "effective_gid"},
	"@std/UserInfo":       {"uid", "gid"},
}

func checkedWideAdd(a, b int64) int64 { return int64(integer64Binary("+", Int64(a), Int64(b)).(Int64)) }
func checkedWideSub(a, b int64) int64 { return int64(integer64Binary("-", Int64(a), Int64(b)).(Int64)) }
func checkedWideMul(a, b int64) int64 { return int64(integer64Binary("*", Int64(a), Int64(b)).(Int64)) }

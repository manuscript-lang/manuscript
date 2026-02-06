// @test: Map [] access - no prototype pollution
// Map literals use null prototype so map["__proto__"] and map["constructor"] are stored as own properties.

let m = {}
m["__proto__"] = 1

// @expect: undefined
print((m["constructor"] as map[string, unknown])?.["constructor"])

// @expect: 1
print(m["__proto__"])

m["constructor"] = "ok"
// @expect: ok
print(m["constructor"])

let empty = {}
// @expect: 0
print(len(empty))

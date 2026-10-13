package checker

// These public entries have no .ms declaration to attach a source comment to.
// Keep their semantic descriptions beside the checker's primitive definitions;
// numeric representation/range details belong to the canonical numeric rules.
// Width migrations must describe any newly exposed primitive here too.
var primitiveDocumentation = map[string]string{
	"Bool":    "Boolean truth values true and false; conditions require this type.",
	"Int":     "Signed whole numbers with checked arithmetic; overflow and division by zero fault.",
	"Int64":   "Explicit signed64 whole numbers with checked arithmetic; overflow and division by zero fault.",
	"Float":   "Binary floating-point values, including signed zero, infinities and NaN.",
	"Float64": "Explicit IEEE binary64 floating-point values, including signed zero, infinities and NaN.",
	"String":  "UTF-8 text indexed by Unicode scalar values; byte_length counts encoded bytes instead.",
	"Unit":    "The single value unit, used when an operation returns no useful payload.",
	"Never":   "The return type of computations that cannot return a value, such as panic.",
}

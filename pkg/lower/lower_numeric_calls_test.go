package lower

import (
	"strings"
	"testing"
)

func TestNumericCallsUseCheckedIdentity(t *testing.T) {
	result := compileSource("math.ms", `import {sqrt, floor, ceil, abs} from "@std/math.ms"
fn calculate(value: Float, integer: Int) -> Float:
    return sqrt(value) + floor(value) + ceil(value) + abs(value) + integer.to_float()
fn dynamic(value: Float) -> Float:
    let callback = sqrt
    return callback(value)
`)
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, name := range []string{"NativeFloatSqrt", "NativeFloatFloor", "NativeFloatCeil", "NativeFloatAbs", "NativeIntToFloat"} {
		if !strings.Contains(result.Source, "rt."+name+"(") {
			t.Fatal("missing typed native", name, result.Source)
		}
	}
	if !strings.Contains(result.Source, "rt.Invoke(") {
		t.Fatal("first-class native must retain callable dispatch")
	}
	shadow := compileSource("shadow.ms", `fn sqrt(value: Float) -> Float: value + 1.0
fn use() -> Float: sqrt(4.0)
`)
	if !shadow.Success() || strings.Contains(shadow.Source, "NativeFloatSqrt") {
		t.Fatal("source spelling selected native behavior", shadow.Diagnostics)
	}
}

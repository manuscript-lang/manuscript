package msruntime

import (
	"fmt"
	"math"
	"reflect"
	"strconv"
	"strings"
)

// testSkip deliberately remains distinct from faults and cancellation.
type testSkip struct{ Reason string }

func testingCheck(ok bool, message func() string) Unit {
	if !ok {
		Raise(message())
	}
	return Unit{}
}

// Testing_ExpectTrue fails unless actual is true.
func Testing_ExpectTrue(_ *Execution, actual bool) Unit {
	return testingCheck(actual, func() string { return "expected true, got false" })
}

// Testing_ExpectFalse fails unless actual is false.
func Testing_ExpectFalse(_ *Execution, actual bool) Unit {
	return testingCheck(!actual, func() string { return "expected false, got true" })
}

// Testing_ExpectEqual compares with the program's equality of T.
func Testing_ExpectEqual[T any](ctx *Execution, eq Eq[T], actual, expected T) Unit {
	return testingCheck(eq(ctx, actual, expected), func() string {
		return "expected " + testFormat(expected) + ", got " + testFormat(actual)
	})
}

// Testing_ExpectNotEqual fails when the values are equal.
func Testing_ExpectNotEqual[T any](ctx *Execution, eq Eq[T], actual, expected T) Unit {
	return testingCheck(!eq(ctx, actual, expected), func() string {
		return "expected different values, got " + testFormat(actual)
	})
}

// Testing_ExpectClose checks the absolute difference against tolerance.
func Testing_ExpectClose(_ *Execution, actual, expected, tolerance float64) Unit {
	if tolerance < 0 || math.IsNaN(tolerance) || math.IsInf(tolerance, 0) {
		Raise("expect_close: tolerance must be finite and nonnegative")
	}
	ok := !math.IsNaN(actual) && !math.IsNaN(expected) && (actual == expected || math.Abs(actual-expected) <= tolerance)
	return testingCheck(ok, func() string {
		return fmt.Sprintf("expected %s within %s, got %s", FormatFloat(expected), FormatFloat(tolerance), FormatFloat(actual))
	})
}

// Testing_ExpectContains checks for an exact substring.
func Testing_ExpectContains(_ *Execution, actual, expected string) Unit {
	return testingCheck(strings.Contains(actual, expected), func() string {
		return fmt.Sprintf("expected %q to contain %q", actual, expected)
	})
}

// Testing_ExpectSome requires some and returns its payload.
func Testing_ExpectSome[T any](_ *Execution, actual Option[T]) T {
	if !actual.Some {
		Raise("expected some, got none")
	}
	return actual.Val
}

// Testing_ExpectNone requires none.
func Testing_ExpectNone[T any](_ *Execution, actual Option[T]) Unit {
	return testingCheck(!actual.Some, func() string { return "expected none, got " + testFormat(actual) })
}

// Testing_ExpectOk requires ok and returns its payload.
func Testing_ExpectOk[T, E any](_ *Execution, actual Result[T, E]) T {
	if actual.Failed {
		Raise("expected ok, got " + testFormat(actual))
	}
	return actual.Val
}

// Testing_ExpectError requires error and returns its cause.
func Testing_ExpectError[T, E any](_ *Execution, actual Result[T, E]) E {
	if !actual.Failed {
		Raise("expected error, got " + testFormat(actual))
	}
	return actual.Err
}

// Testing_ExpectFault runs operation, requires a programming fault, and
// returns its message. Cancellation and skips propagate.
func Testing_ExpectFault(ctx *Execution, operation func(*Execution) Unit) (message string) {
	depth := Depth(ctx)
	caught := false
	func() {
		defer func() {
			if failure := recover(); failure != nil {
				fault, ok := failure.(Fault)
				if !ok {
					panic(failure)
				}
				RestoreDepth(ctx, depth)
				message, caught = fault.Message, true
			}
		}()
		operation(ctx)
	}()
	if !caught {
		Raise("expected a programming fault, operation returned normally")
	}
	return message
}

// Testing_Fail fails the test with message.
func Testing_Fail(_ *Execution, message string) Unit {
	Raise(message)
	return Unit{}
}

// Testing_Skip ends the test as skipped.
func Testing_Skip(_ *Execution, reason string) Unit { panic(testSkip{reason}) }

// The assert_* names are aliases of expect_*.
func Testing_AssertTrue(ctx *Execution, actual bool) Unit  { return Testing_ExpectTrue(ctx, actual) }
func Testing_AssertFalse(ctx *Execution, actual bool) Unit { return Testing_ExpectFalse(ctx, actual) }
func Testing_AssertEqual[T any](ctx *Execution, eq Eq[T], actual, expected T) Unit {
	return Testing_ExpectEqual(ctx, eq, actual, expected)
}
func Testing_AssertNotEqual[T any](ctx *Execution, eq Eq[T], actual, expected T) Unit {
	return Testing_ExpectNotEqual(ctx, eq, actual, expected)
}
func Testing_AssertClose(ctx *Execution, actual, expected, tolerance float64) Unit {
	return Testing_ExpectClose(ctx, actual, expected, tolerance)
}
func Testing_AssertContains(ctx *Execution, actual, expected string) Unit {
	return Testing_ExpectContains(ctx, actual, expected)
}
func Testing_AssertSome[T any](ctx *Execution, actual Option[T]) T {
	return Testing_ExpectSome(ctx, actual)
}
func Testing_AssertNone[T any](ctx *Execution, actual Option[T]) Unit {
	return Testing_ExpectNone(ctx, actual)
}
func Testing_AssertOk[T, E any](ctx *Execution, actual Result[T, E]) T {
	return Testing_ExpectOk(ctx, actual)
}
func Testing_AssertError[T, E any](ctx *Execution, actual Result[T, E]) E {
	return Testing_ExpectError(ctx, actual)
}
func Testing_AssertFault(ctx *Execution, operation func(*Execution) Unit) string {
	return Testing_ExpectFault(ctx, operation)
}

// testFormat renders a value of any lowered type for an assertion message.
// Assertions are generic over T and receive only its equality, so the text
// follows the Go representation: scalars, collections, Optional, Result,
// records and alternative cases.
func testFormat(v any) string {
	var b strings.Builder
	testFormatValue(&b, reflect.ValueOf(v), 0)
	return b.String()
}

func testFormatValue(b *strings.Builder, v reflect.Value, depth int) {
	if depth > 8 {
		b.WriteString("...")
		return
	}
	switch v.Kind() {
	case reflect.Invalid:
		b.WriteString("unit")
	case reflect.Interface, reflect.Pointer:
		if v.IsNil() {
			b.WriteString("unit")
			return
		}
		testFormatValue(b, v.Elem(), depth)
	case reflect.Int, reflect.Int64:
		b.WriteString(strconv.FormatInt(v.Int(), 10))
	case reflect.Float64:
		b.WriteString(FormatFloat(v.Float()))
	case reflect.Bool:
		b.WriteString(FormatBool(v.Bool()))
	case reflect.String:
		fmt.Fprintf(b, "%q", v.String())
	case reflect.Slice:
		b.WriteByte('[')
		for i := range v.Len() {
			if i > 0 {
				b.WriteString(", ")
			}
			testFormatValue(b, v.Index(i), depth+1)
		}
		b.WriteByte(']')
	case reflect.Struct:
		testFormatStruct(b, v, depth)
	default:
		fmt.Fprint(b, v.Interface())
	}
}

func testFormatStruct(b *strings.Builder, v reflect.Value, depth int) {
	name, _, _ := strings.Cut(v.Type().Name(), "[")
	switch name {
	case "Unit":
		b.WriteString("unit")
		return
	case "Option":
		if !v.FieldByName("Some").Bool() {
			b.WriteString("none")
			return
		}
		b.WriteString("some(")
		testFormatValue(b, v.FieldByName("Val"), depth+1)
		b.WriteByte(')')
		return
	case "Result":
		if v.FieldByName("Failed").Bool() {
			b.WriteString("error(")
			testFormatValue(b, v.FieldByName("Err"), depth+1)
		} else {
			b.WriteString("ok(")
			testFormatValue(b, v.FieldByName("Val"), depth+1)
		}
		b.WriteByte(')')
		return
	case "List":
		testFormatValue(b, v.FieldByName("Items"), depth)
		return
	}
	if _, tag, ok := strings.Cut(name, "_"); ok {
		name = tag
	}
	b.WriteString(name)
	if v.NumField() == 0 {
		return
	}
	b.WriteByte('(')
	for i := range v.NumField() {
		if i > 0 {
			b.WriteString(", ")
		}
		if field := v.Type().Field(i); field.IsExported() {
			b.WriteString(strings.ToLower(field.Name[:1]) + field.Name[1:] + ": ")
			testFormatValue(b, v.Field(i), depth+1)
		}
	}
	b.WriteByte(')')
}

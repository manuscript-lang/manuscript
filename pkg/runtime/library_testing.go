package msruntime

import (
	"fmt"
	"math"
	"strings"
)

// testSkip deliberately remains distinct from faults and cancellation.
type testSkip struct{ Reason string }

func testingCheck(ok bool, message string) Value {
	if !ok {
		return Panic(message)
	}
	return Unit{}
}

func testingFault(ctx *Execution, operation Value) (message string, caught bool) {
	depth := Depth(ctx)
	defer func() {
		if failure := recover(); failure != nil {
			if fault, ok := failure.(Fault); ok {
				if ctx.calls != nil {
					ctx.calls.depth = depth
				}
				message, caught = fault.Message, true
				return
			}
			panic(failure)
		}
	}()
	Invoke(ctx, operation, nil)
	return "", false
}

func init() {
	boolParams := []LibraryParam{{"actual", "Bool"}}
	for _, name := range []string{"expect_true", "expect_false"} {
		libraryAdd("testing", name, "Unit", boolParams, func(_ *Execution, _ string, args []Value) Value {
			want := name == "expect_true"
			return testingCheck(args[0].(bool) == want, fmt.Sprintf("expected %t, got %t", want, args[0]))
		})
	}
	for _, name := range []string{"expect_equal", "expect_not_equal"} {
		libraryGeneric("testing", name, "Unit", []LibraryParam{{"T", "Equal"}}, []LibraryParam{{"actual", "T"}, {"expected", "T"}}, func(ctx *Execution, _ string, args []Value) Value {
			same := EqualIn(ctx, args[0], args[1])
			if name == "expect_not_equal" {
				return testingCheck(!same, "expected different values, got "+Format(args[0]))
			}
			return testingCheck(same, "expected "+Format(args[1])+", got "+Format(args[0]))
		})
	}
	libraryAdd("testing", "expect_close", "Unit", []LibraryParam{{"actual", "Float"}, {"expected", "Float"}, {"tolerance", "Float"}}, func(_ *Execution, _ string, args []Value) Value {
		actual, expected, tolerance := args[0].(float64), args[1].(float64), args[2].(float64)
		if tolerance < 0 || math.IsNaN(tolerance) || math.IsInf(tolerance, 0) {
			return Panic("expect_close: tolerance must be finite and nonnegative")
		}
		ok := !math.IsNaN(actual) && !math.IsNaN(expected) && (actual == expected || math.Abs(actual-expected) <= tolerance)
		return testingCheck(ok, fmt.Sprintf("expected %s within %s, got %s", Format(expected), Format(tolerance), Format(actual)))
	})
	libraryAdd("testing", "expect_contains", "Unit", []LibraryParam{{"actual", "String"}, {"expected", "String"}}, func(_ *Execution, _ string, args []Value) Value {
		return testingCheck(strings.Contains(args[0].(string), args[1].(string)), fmt.Sprintf("expected %q to contain %q", args[0], args[1]))
	})
	for _, name := range []string{"expect_some", "expect_none", "expect_ok", "expect_error"} {
		vars := []LibraryParam{{"T", ""}}
		typ, result, tag := "Optional[T]", "T", "some"
		switch name {
		case "expect_none":
			result, tag = "Unit", "none"
		case "expect_ok":
			typ, tag = "Result[T][E]", "ok"
			vars = append(vars, LibraryParam{"E", ""})
		case "expect_error":
			typ, result, tag = "Result[T][E]", "E", "error"
			vars = append(vars, LibraryParam{"E", ""})
		}
		libraryGeneric("testing", name, result, vars, []LibraryParam{{"actual", typ}}, func(_ *Execution, _ string, args []Value) Value {
			actual := args[0].(Alternative)
			if actual.Tag != tag {
				return Panic("expected " + tag + ", got " + Format(actual))
			}
			if tag == "none" {
				return Unit{}
			}
			return actual.Fields[0]
		})
	}
	libraryAdd("testing", "expect_fault", "String", []LibraryParam{{"operation", "fn()->Unit"}}, func(ctx *Execution, _ string, args []Value) Value {
		message, caught := testingFault(ctx, args[0])
		if !caught {
			return Panic("expected a programming fault, operation returned normally")
		}
		return message
	})
	libraryAdd("testing", "fail", "Never", []LibraryParam{{"message", "String"}}, func(_ *Execution, _ string, args []Value) Value { return Panic(args[0].(string)) })
	libraryAdd("testing", "skip", "Never", []LibraryParam{{"reason", "String"}}, func(_ *Execution, _ string, args []Value) Value { panic(testSkip{args[0].(string)}) })
	for _, name := range []string{"true", "false", "equal", "not_equal", "close", "contains", "some", "none", "ok", "error", "fault"} {
		libraryAlias("testing", "assert_"+name, "expect_"+name)
	}
}

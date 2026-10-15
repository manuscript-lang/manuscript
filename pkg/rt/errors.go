package rt

import (
	"reflect"
	"unsafe"
)

// Errors_Message_TextError is the wrapped text, verbatim.
func Errors_Message_TextError(_ *Execution, cause TextError) string {
	if cause, ok := cause.(TextError_Text); ok {
		return cause.Message
	}
	return "text: operation failed"
}

// Errors_Message_MissingValue names where the absent value was converted to
// an error.
func Errors_Message_MissingValue(_ *Execution, cause MissingValue) string {
	if cause, ok := cause.(MissingValue_Missing); ok {
		return "missing value at " + cause.Location
	}
	return "missing value: operation failed"
}

// errorUnwrapper is implemented by an Error view that exposes the value it
// adapts, so classification reads the concrete standard error without calling
// its message.
type errorUnwrapper interface{ UnwrapError() Error }

// Errors_Category classifies a standard error by its shared category. Custom
// errors and domain-specific cases (Failed, Full, OutputLimit, OutOfRange,
// AuthenticationFailed and wrapped LogError causes) have none. Messages are
// never parsed and user code is never invoked.
func Errors_Category(_ *Execution, cause Error) Option[ErrorCategory] {
	for depth := 0; cause != nil && depth < 8; depth++ {
		if c, ok := cause.(errorCategorized); ok {
			return Some(c.errorCategory())
		}
		inner := viewReceiver(cause)
		if inner == nil {
			break
		}
		cause = inner
	}
	return None[ErrorCategory]()
}

// viewReceiver returns the Error a view adapts. A view that implements
// errorUnwrapper answers directly; otherwise the generated view struct's
// receiver field "self" is read by reflection. The lowerer's views keep their
// receiver in an unexported field of that name.
func viewReceiver(view Error) Error {
	if u, ok := view.(errorUnwrapper); ok {
		return u.UnwrapError()
	}
	v := reflect.ValueOf(view)
	if v.Kind() != reflect.Struct {
		return nil
	}
	field := v.FieldByName("self")
	if !field.IsValid() {
		return nil
	}
	// Read the unexported field without calling any method on its value.
	holder := reflect.New(v.Type()).Elem()
	holder.Set(v)
	exposed := reflect.NewAt(field.Type(), unsafe.Pointer(holder.FieldByName("self").UnsafeAddr())).Elem()
	if exposed.Kind() == reflect.Interface && exposed.IsNil() {
		return nil
	}
	if err, ok := exposed.Interface().(Error); ok {
		return err
	}
	if err, ok := exposed.Interface().(errorCategorized); ok {
		return categorizedError{err}
	}
	return nil
}

// categorizedError adapts a bare standard error case to Error for the
// classification loop; its message is never requested.
type categorizedError struct{ errorCategorized }

func (categorizedError) Message(*Execution) string { return "" }

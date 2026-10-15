package msruntime

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

// Errors_Category classifies a standard error by its shared category. Custom
// errors and domain-specific cases (Failed, Full, OutputLimit, OutOfRange,
// AuthenticationFailed and wrapped LogError causes) have none. Messages are
// never parsed and user code is never invoked.
func Errors_Category(_ *Execution, cause Error) Option[ErrorCategory] {
	var value any = cause
	for depth := 0; value != nil && depth < 8; depth++ {
		if c, ok := value.(Categorized); ok {
			return Some(c.Category())
		}
		value = viewReceiver(value)
	}
	return None[ErrorCategory]()
}

// viewReceiver returns the value a generated Error view adapts, which is
// either an Error or a bare case carrying its category.
func viewReceiver(view any) any {
	if v, ok := view.(interface{ Receiver() any }); ok {
		return v.Receiver()
	}
	return nil
}

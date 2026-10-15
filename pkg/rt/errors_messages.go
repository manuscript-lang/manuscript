// Code generated from the standard error cases of std_types_gen.go; see TestErrorMessageCoverage (host-layer error types only; other modules define their own). DO NOT EDIT.
//
// Diagnostics stay independent of input values: URLs, data, and host arguments can
// contain secrets. Explicit Failed and Crashed messages are returned verbatim.

package rt

// Errors_Message_CommandError is the Error message of CommandError.
func Errors_Message_CommandError(ctx *Execution, cause CommandError) string {
	switch cause := cause.(type) {
	case CommandError_InvalidInput:
		return "command: invalid input"
	case CommandError_Unavailable:
		return "command: service unavailable"
	case CommandError_Timeout:
		return "command: operation timed out"
	case CommandError_OutputLimit:
		return "command: output limit exceeded"
	case CommandError_Failed:
		return cause.Message
	}
	return "command: operation failed"
}

// Errors_Message_FileSystemError is the Error message of FileSystemError.
func Errors_Message_FileSystemError(ctx *Execution, cause FileSystemError) string {
	switch cause := cause.(type) {
	case FileSystemError_InvalidInput:
		return "filesystem: invalid input"
	case FileSystemError_InvalidData:
		return "filesystem: invalid data"
	case FileSystemError_LimitExceeded:
		return "filesystem: limit exceeded"
	case FileSystemError_NotFound:
		return "filesystem: file or directory not found"
	case FileSystemError_AlreadyExists:
		return "filesystem: already exists"
	case FileSystemError_NotEmpty:
		return "filesystem: directory not empty"
	case FileSystemError_PermissionDenied:
		return "filesystem: permission denied"
	case FileSystemError_Unsupported:
		return "filesystem: operation not supported"
	case FileSystemError_Closed:
		return "filesystem: resource is closed"
	case FileSystemError_Failed:
		return cause.Message
	}
	return "filesystem: operation failed"
}

// Errors_Message_IoError is the Error message of IoError.
func Errors_Message_IoError(ctx *Execution, cause IoError) string {
	switch cause := cause.(type) {
	case IoError_Closed:
		return "I/O: resource is closed"
	case IoError_InvalidInput:
		return "I/O: invalid input"
	case IoError_Unavailable:
		return "I/O: service unavailable"
	case IoError_InvalidData:
		return "I/O: invalid data"
	case IoError_LimitExceeded:
		return "I/O: limit exceeded"
	case IoError_Failed:
		return cause.Message
	}
	return "I/O: operation failed"
}

// Errors_Message_LogError is the Error message of LogError.
func Errors_Message_LogError(ctx *Execution, cause LogError) string {
	switch cause := cause.(type) {
	case LogError_InvalidInput:
		return "logging: invalid input"
	case LogError_InvalidData:
		return "logging: invalid data"
	case LogError_LimitExceeded:
		return "logging: limit exceeded"
	case LogError_Closed:
		return "logging: resource is closed"
	case LogError_Io:
		return Errors_Message_IoError(ctx, cause.Cause)
	case LogError_FileSystem:
		return Errors_Message_FileSystemError(ctx, cause.Cause)
	}
	return "logging: operation failed"
}

// Errors_Message_ProcessError is the Error message of ProcessError.
func Errors_Message_ProcessError(ctx *Execution, cause ProcessError) string {
	switch cause := cause.(type) {
	case ProcessError_InvalidInput:
		return "process: invalid input"
	case ProcessError_InvalidData:
		return "process: invalid data"
	case ProcessError_LimitExceeded:
		return "process: limit exceeded"
	case ProcessError_NotFound:
		return "process: not found"
	case ProcessError_AlreadyExists:
		return "process: already exists"
	case ProcessError_PermissionDenied:
		return "process: permission denied"
	case ProcessError_Unsupported:
		return "process: operation not supported"
	case ProcessError_Closed:
		return "process: resource is closed"
	case ProcessError_Failed:
		return cause.Message
	}
	return "process: operation failed"
}

// Errors_Message_SystemError is the Error message of SystemError.
func Errors_Message_SystemError(ctx *Execution, cause SystemError) string {
	switch cause := cause.(type) {
	case SystemError_InvalidInput:
		return "system: invalid input"
	case SystemError_InvalidData:
		return "system: invalid data"
	case SystemError_LimitExceeded:
		return "system: limit exceeded"
	case SystemError_NotFound:
		return "system: not found"
	case SystemError_AlreadyExists:
		return "system: already exists"
	case SystemError_PermissionDenied:
		return "system: permission denied"
	case SystemError_Unsupported:
		return "system: operation not supported"
	case SystemError_Closed:
		return "system: resource is closed"
	case SystemError_Failed:
		return cause.Message
	}
	return "system: operation failed"
}

// Errors_Message_TimeError is the Error message of TimeError.
func Errors_Message_TimeError(ctx *Execution, cause TimeError) string {
	switch cause.(type) {
	case TimeError_InvalidInput:
		return "time: invalid input"
	case TimeError_Closed:
		return "time: resource is closed"
	case TimeError_InvalidData:
		return "time: invalid data"
	case TimeError_OutOfRange:
		return "time: value out of range"
	}
	return "time: operation failed"
}

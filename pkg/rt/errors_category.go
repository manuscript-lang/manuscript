// Code generated from the shared error cases of std_types_gen.go; see TestErrorCategoryCoverage. DO NOT EDIT.

package rt

// Categorized is implemented by the standard error cases that have a
// shared ErrorCategory. Cases without one (Failed, OutputLimit, ...) do not
// implement it.
type Categorized interface{ Category() ErrorCategory }

func (ArchiveError_InvalidInput) Category() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (ArchiveError_InvalidData) Category() ErrorCategory   { return ErrorCategory_InvalidData{} }
func (ArchiveError_LimitExceeded) Category() ErrorCategory { return ErrorCategory_LimitExceeded{} }
func (ArchiveError_Unsupported) Category() ErrorCategory   { return ErrorCategory_Unsupported{} }
func (BigIntError_InvalidInput) Category() ErrorCategory   { return ErrorCategory_InvalidInput{} }
func (BigIntError_InvalidData) Category() ErrorCategory    { return ErrorCategory_InvalidData{} }
func (BigIntError_LimitExceeded) Category() ErrorCategory  { return ErrorCategory_LimitExceeded{} }
func (BinaryError_InvalidInput) Category() ErrorCategory   { return ErrorCategory_InvalidInput{} }
func (CollectionError_InvalidInput) Category() ErrorCategory {
	return ErrorCategory_InvalidInput{}
}
func (CollectionError_LimitExceeded) Category() ErrorCategory {
	return ErrorCategory_LimitExceeded{}
}
func (CompressionError_InvalidInput) Category() ErrorCategory {
	return ErrorCategory_InvalidInput{}
}
func (CompressionError_InvalidData) Category() ErrorCategory { return ErrorCategory_InvalidData{} }
func (CompressionError_LimitExceeded) Category() ErrorCategory {
	return ErrorCategory_LimitExceeded{}
}
func (CompressionError_Unsupported) Category() ErrorCategory { return ErrorCategory_Unsupported{} }
func (CryptoError_InvalidInput) Category() ErrorCategory     { return ErrorCategory_InvalidInput{} }
func (CryptoError_Unsupported) Category() ErrorCategory      { return ErrorCategory_Unsupported{} }
func (CsvError_InvalidInput) Category() ErrorCategory        { return ErrorCategory_InvalidInput{} }
func (CsvError_InvalidData) Category() ErrorCategory         { return ErrorCategory_InvalidData{} }
func (CsvError_LimitExceeded) Category() ErrorCategory       { return ErrorCategory_LimitExceeded{} }
func (EncodingError_InvalidInput) Category() ErrorCategory   { return ErrorCategory_InvalidInput{} }
func (EncodingError_InvalidData) Category() ErrorCategory    { return ErrorCategory_InvalidData{} }
func (EncodingError_LimitExceeded) Category() ErrorCategory {
	return ErrorCategory_LimitExceeded{}
}
func (FileSystemError_InvalidInput) Category() ErrorCategory {
	return ErrorCategory_InvalidInput{}
}
func (FileSystemError_InvalidData) Category() ErrorCategory { return ErrorCategory_InvalidData{} }
func (FileSystemError_LimitExceeded) Category() ErrorCategory {
	return ErrorCategory_LimitExceeded{}
}
func (FileSystemError_NotFound) Category() ErrorCategory { return ErrorCategory_NotFound{} }
func (FileSystemError_AlreadyExists) Category() ErrorCategory {
	return ErrorCategory_AlreadyExists{}
}
func (FileSystemError_PermissionDenied) Category() ErrorCategory {
	return ErrorCategory_PermissionDenied{}
}
func (FileSystemError_Unsupported) Category() ErrorCategory { return ErrorCategory_Unsupported{} }
func (FileSystemError_Closed) Category() ErrorCategory      { return ErrorCategory_Closed{} }
func (HtmlError_InvalidInput) Category() ErrorCategory      { return ErrorCategory_InvalidInput{} }
func (HtmlError_InvalidData) Category() ErrorCategory       { return ErrorCategory_InvalidData{} }
func (HtmlError_LimitExceeded) Category() ErrorCategory     { return ErrorCategory_LimitExceeded{} }
func (HttpError_InvalidInput) Category() ErrorCategory      { return ErrorCategory_InvalidInput{} }
func (HttpError_InvalidData) Category() ErrorCategory       { return ErrorCategory_InvalidData{} }
func (HttpError_LimitExceeded) Category() ErrorCategory     { return ErrorCategory_LimitExceeded{} }
func (HttpError_PermissionDenied) Category() ErrorCategory {
	return ErrorCategory_PermissionDenied{}
}
func (HttpError_Closed) Category() ErrorCategory           { return ErrorCategory_Closed{} }
func (HttpError_Timeout) Category() ErrorCategory          { return ErrorCategory_Timeout{} }
func (IoError_Closed) Category() ErrorCategory             { return ErrorCategory_Closed{} }
func (IoError_InvalidInput) Category() ErrorCategory       { return ErrorCategory_InvalidInput{} }
func (IoError_Unavailable) Category() ErrorCategory        { return ErrorCategory_Unavailable{} }
func (IoError_InvalidData) Category() ErrorCategory        { return ErrorCategory_InvalidData{} }
func (IoError_LimitExceeded) Category() ErrorCategory      { return ErrorCategory_LimitExceeded{} }
func (JsonError_InvalidInput) Category() ErrorCategory     { return ErrorCategory_InvalidInput{} }
func (JsonError_InvalidData) Category() ErrorCategory      { return ErrorCategory_InvalidData{} }
func (JsonError_LimitExceeded) Category() ErrorCategory    { return ErrorCategory_LimitExceeded{} }
func (LogError_InvalidInput) Category() ErrorCategory      { return ErrorCategory_InvalidInput{} }
func (LogError_InvalidData) Category() ErrorCategory       { return ErrorCategory_InvalidData{} }
func (LogError_LimitExceeded) Category() ErrorCategory     { return ErrorCategory_LimitExceeded{} }
func (LogError_Closed) Category() ErrorCategory            { return ErrorCategory_Closed{} }
func (NetworkError_InvalidInput) Category() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (NetworkError_InvalidData) Category() ErrorCategory   { return ErrorCategory_InvalidData{} }
func (NetworkError_LimitExceeded) Category() ErrorCategory { return ErrorCategory_LimitExceeded{} }
func (NetworkError_PermissionDenied) Category() ErrorCategory {
	return ErrorCategory_PermissionDenied{}
}
func (NetworkError_Unsupported) Category() ErrorCategory   { return ErrorCategory_Unsupported{} }
func (NetworkError_Closed) Category() ErrorCategory        { return ErrorCategory_Closed{} }
func (NetworkError_Timeout) Category() ErrorCategory       { return ErrorCategory_Timeout{} }
func (NumberError_InvalidInput) Category() ErrorCategory   { return ErrorCategory_InvalidInput{} }
func (NumberError_InvalidData) Category() ErrorCategory    { return ErrorCategory_InvalidData{} }
func (PathError_InvalidInput) Category() ErrorCategory     { return ErrorCategory_InvalidInput{} }
func (CommandError_InvalidInput) Category() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (CommandError_Unavailable) Category() ErrorCategory   { return ErrorCategory_Unavailable{} }
func (CommandError_Timeout) Category() ErrorCategory       { return ErrorCategory_Timeout{} }
func (ProcessError_InvalidInput) Category() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (ProcessError_InvalidData) Category() ErrorCategory   { return ErrorCategory_InvalidData{} }
func (ProcessError_LimitExceeded) Category() ErrorCategory { return ErrorCategory_LimitExceeded{} }
func (ProcessError_NotFound) Category() ErrorCategory      { return ErrorCategory_NotFound{} }
func (ProcessError_AlreadyExists) Category() ErrorCategory { return ErrorCategory_AlreadyExists{} }
func (ProcessError_PermissionDenied) Category() ErrorCategory {
	return ErrorCategory_PermissionDenied{}
}
func (ProcessError_Unsupported) Category() ErrorCategory  { return ErrorCategory_Unsupported{} }
func (ProcessError_Closed) Category() ErrorCategory       { return ErrorCategory_Closed{} }
func (RandomError_InvalidInput) Category() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (RandomError_LimitExceeded) Category() ErrorCategory { return ErrorCategory_LimitExceeded{} }
func (RegexError_InvalidInput) Category() ErrorCategory   { return ErrorCategory_InvalidInput{} }
func (RegexError_InvalidData) Category() ErrorCategory    { return ErrorCategory_InvalidData{} }
func (RegexError_LimitExceeded) Category() ErrorCategory  { return ErrorCategory_LimitExceeded{} }
func (StringError_InvalidInput) Category() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (StringError_LimitExceeded) Category() ErrorCategory { return ErrorCategory_LimitExceeded{} }
func (SystemError_InvalidInput) Category() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (SystemError_InvalidData) Category() ErrorCategory   { return ErrorCategory_InvalidData{} }
func (SystemError_LimitExceeded) Category() ErrorCategory { return ErrorCategory_LimitExceeded{} }
func (SystemError_NotFound) Category() ErrorCategory      { return ErrorCategory_NotFound{} }
func (SystemError_AlreadyExists) Category() ErrorCategory { return ErrorCategory_AlreadyExists{} }
func (SystemError_PermissionDenied) Category() ErrorCategory {
	return ErrorCategory_PermissionDenied{}
}
func (SystemError_Unsupported) Category() ErrorCategory     { return ErrorCategory_Unsupported{} }
func (SystemError_Closed) Category() ErrorCategory          { return ErrorCategory_Closed{} }
func (ExecutionError_Timeout) Category() ErrorCategory      { return ErrorCategory_Timeout{} }
func (StartError_Closed) Category() ErrorCategory           { return ErrorCategory_Closed{} }
func (StartError_InvalidInput) Category() ErrorCategory     { return ErrorCategory_InvalidInput{} }
func (TimeError_InvalidInput) Category() ErrorCategory      { return ErrorCategory_InvalidInput{} }
func (TimeError_Closed) Category() ErrorCategory            { return ErrorCategory_Closed{} }
func (TimeError_InvalidData) Category() ErrorCategory       { return ErrorCategory_InvalidData{} }
func (TlsError_InvalidInput) Category() ErrorCategory       { return ErrorCategory_InvalidInput{} }
func (TlsError_InvalidData) Category() ErrorCategory        { return ErrorCategory_InvalidData{} }
func (TlsError_LimitExceeded) Category() ErrorCategory      { return ErrorCategory_LimitExceeded{} }
func (UrlError_InvalidInput) Category() ErrorCategory       { return ErrorCategory_InvalidInput{} }
func (UrlError_InvalidData) Category() ErrorCategory        { return ErrorCategory_InvalidData{} }
func (UrlError_LimitExceeded) Category() ErrorCategory      { return ErrorCategory_LimitExceeded{} }
func (WebSocketError_InvalidInput) Category() ErrorCategory { return ErrorCategory_InvalidInput{} }
func (WebSocketError_InvalidData) Category() ErrorCategory  { return ErrorCategory_InvalidData{} }
func (WebSocketError_LimitExceeded) Category() ErrorCategory {
	return ErrorCategory_LimitExceeded{}
}
func (WebSocketError_PermissionDenied) Category() ErrorCategory {
	return ErrorCategory_PermissionDenied{}
}
func (WebSocketError_Closed) Category() ErrorCategory  { return ErrorCategory_Closed{} }
func (WebSocketError_Timeout) Category() ErrorCategory { return ErrorCategory_Timeout{} }

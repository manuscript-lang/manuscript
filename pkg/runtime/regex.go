package msruntime

import (
	"regexp"
	"strings"
)

// Regex is a compiled pattern. It is safe for concurrent use.
type Regex struct{ pattern *regexp.Regexp }

func regexFail[T any](e RegexError) Result[T, RegexError] { return Fail[T, RegexError](e) }

func Errors_Message_RegexError(_ *Execution, e RegexError) string {
	switch e.(type) {
	case RegexError_InvalidInput:
		return "regular expression: " + txInvalidInput
	case RegexError_InvalidData:
		return "regular expression: " + txInvalidData
	case RegexError_LimitExceeded:
		return "regular expression: " + txLimitExceeded
	}
	return "regular expression: operation failed"
}

func Regex_Compile(_ *Execution, pattern string) Result[*Regex, RegexError] {
	re, err := regexp.Compile(pattern)
	if err != nil {
		return regexFail[*Regex](RegexError_InvalidData{})
	}
	return Ok[*Regex, RegexError](&Regex{re})
}

func Regex_Matches(_ *Execution, re *Regex, text string) bool { return re.pattern.MatchString(text) }

func Regex_FindAll(ctx *Execution, re *Regex, text string, maxMatches Option[int]) Result[*List[string], RegexError] {
	n := txLimit(maxMatches)
	if n < 0 {
		return regexFail[*List[string]](RegexError_InvalidInput{})
	}
	if n > len(text)+1 {
		n = len(text) + 1
	}
	matches := re.pattern.FindAllString(text, int(n)+1)
	CheckCancelled(ctx)
	if len(matches) > n {
		return regexFail[*List[string]](RegexError_LimitExceeded{})
	}
	if matches == nil {
		matches = []string{}
	}
	return Ok[*List[string], RegexError](NewList(matches...))
}

func Regex_ReplaceAll(ctx *Execution, re *Regex, text, replacement string, maxBytes Option[int]) Result[string, RegexError] {
	max := txLimit(maxBytes)
	if max < 0 {
		return regexFail[string](RegexError_InvalidInput{})
	}
	var out strings.Builder
	at := 0
	for _, index := range re.pattern.FindAllStringIndex(text, -1) {
		CheckCancelled(ctx)
		if int(index[0]-at) > max-int(out.Len()) {
			return regexFail[string](RegexError_LimitExceeded{})
		}
		out.WriteString(text[at:index[0]])
		if len(replacement) > max-int(out.Len()) {
			return regexFail[string](RegexError_LimitExceeded{})
		}
		out.WriteString(replacement)
		at = index[1]
	}
	if int(len(text)-at) > max-int(out.Len()) {
		return regexFail[string](RegexError_LimitExceeded{})
	}
	out.WriteString(text[at:])
	return Ok[string, RegexError](out.String())
}

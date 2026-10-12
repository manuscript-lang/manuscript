// Package decimal defines exact Decimal literal rules shared by checking and execution.
package decimal

import (
	"strconv"
	"strings"
)

func Valid(text string) bool { _, _, _, valid := Parts(text); return valid }

func Parts(text string) (string, int, bool, bool) {
	raw := strings.TrimSuffix(text, "d")
	negative := strings.HasPrefix(raw, "-")
	if strings.HasPrefix(raw, "-") || strings.HasPrefix(raw, "+") {
		raw = raw[1:]
	}
	mantissa, exponentText := raw, "0"
	if at := strings.IndexAny(raw, "eE"); at >= 0 {
		mantissa = raw[:at]
		exponentText = raw[at+1:]
	}
	digits := exponentText
	if strings.HasPrefix(digits, "-") || strings.HasPrefix(digits, "+") {
		digits = digits[1:]
	}
	if digits == "" || mantissa == "" {
		return "", 0, false, false
	}
	for _, c := range digits {
		if c < '0' || c > '9' {
			return "", 0, false, false
		}
	}
	fraction := 0
	coefficient := mantissa
	if at := strings.IndexByte(mantissa, '.'); at >= 0 {
		if at == 0 || at == len(mantissa)-1 {
			return "", 0, false, false
		}
		fraction = len(mantissa) - at - 1
		coefficient = mantissa[:at] + mantissa[at+1:]
	}
	for _, c := range coefficient {
		if c < '0' || c > '9' {
			return "", 0, false, false
		}
	}
	coefficient = strings.TrimLeft(coefficient, "0")
	// Zero is exact regardless of written exponent; never allocate its power of ten.
	if coefficient == "" {
		return "0", 0, false, true
	}
	exponent, err := strconv.ParseInt(exponentText, 10, 32)
	if err != nil {
		return "", 0, false, false
	}
	trimmed := strings.TrimRight(coefficient, "0")
	quantum := int(exponent) - fraction + len(coefficient) - len(trimmed)
	valid := len(trimmed) <= 34 && quantum >= -6176 && quantum+len(trimmed)-1 <= 6144
	return trimmed, quantum, negative, valid
}

package main

import (
	"bufio"
	"os"
	"strings"
)

func main() {
	reader := bufio.NewReaderSize(os.Stdin, 1<<16)
	writer := bufio.NewWriterSize(os.Stdout, 1<<16)
	defer writer.Flush()

	for {
		line, err := reader.ReadString('\n')
		if len(line) > 0 || err == nil {
			line = strings.TrimSuffix(line, "\n")
			line = strings.TrimSuffix(line, "\r")
			if !isBlank(line) {
				writer.WriteString(processLine(line))
				writer.WriteByte('\n')
			}
		}
		if err != nil {
			break
		}
	}
}

// isBlank reports whether a line is empty or consists only of spaces.
func isBlank(s string) bool {
	return strings.Trim(s, " ") == ""
}

// processLine handles one non-blank command line and returns its output (without newline).
func processLine(line string) string {
	// Split on the first three spaces: cipher, mode, key, text.
	parts := strings.SplitN(line, " ", 4)
	if len(parts) < 4 || parts[3] == "" {
		return "error: bad command"
	}
	cipher, mode, key, text := parts[0], parts[1], parts[2], parts[3]

	if cipher != "caesar" && cipher != "vigenere" {
		return "error: bad cipher"
	}
	if mode != "enc" && mode != "dec" {
		return "error: bad mode"
	}
	decrypt := mode == "dec"

	if cipher == "caesar" {
		shift, ok := parseCaesarKey(key)
		if !ok {
			return "error: bad key"
		}
		if decrypt {
			shift = -shift
		}
		return caesar(text, shift)
	}

	if !isLetters(key) {
		return "error: bad key"
	}
	shifts := make([]int, len(key))
	for i := 0; i < len(key); i++ {
		shifts[i] = int(lower(key[i]) - 'a')
	}
	return vigenere(text, shifts, decrypt)
}

// parseCaesarKey validates an optional leading '-' followed by 1..7 decimal digits.
func parseCaesarKey(key string) (int, bool) {
	neg := false
	digits := key
	if strings.HasPrefix(digits, "-") {
		neg = true
		digits = digits[1:]
	}
	if len(digits) < 1 || len(digits) > 7 {
		return 0, false
	}
	n := 0
	for i := 0; i < len(digits); i++ {
		c := digits[i]
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n*10 + int(c-'0')
	}
	if neg {
		n = -n
	}
	return n, true
}

func isLetters(s string) bool {
	if len(s) == 0 {
		return false
	}
	for i := 0; i < len(s); i++ {
		if !isLetter(s[i]) {
			return false
		}
	}
	return true
}

func isLetter(c byte) bool {
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
}

func lower(c byte) byte {
	if c >= 'A' && c <= 'Z' {
		return c + ('a' - 'A')
	}
	return c
}

// shiftLetter shifts an ASCII letter by n positions (n may be negative), keeping case.
func shiftLetter(c byte, n int) byte {
	var base byte
	if c >= 'a' && c <= 'z' {
		base = 'a'
	} else {
		base = 'A'
	}
	off := (int(c-base) + n) % 26
	if off < 0 {
		off += 26
	}
	return base + byte(off)
}

func caesar(text string, shift int) string {
	b := []byte(text)
	for i, c := range b {
		if isLetter(c) {
			b[i] = shiftLetter(c, shift)
		}
	}
	return string(b)
}

func vigenere(text string, shifts []int, decrypt bool) string {
	b := []byte(text)
	k := 0
	for i, c := range b {
		if isLetter(c) {
			s := shifts[k%len(shifts)]
			if decrypt {
				s = -s
			}
			b[i] = shiftLetter(c, s)
			k++
		}
	}
	return string(b)
}

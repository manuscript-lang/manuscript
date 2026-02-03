// @test: String Processing

// === Word count ===
fn count_words(text: string): number
  let words = split(text, " ")
  var count = 0
  for w in words
    if len(trim(w)) > 0
      count = count + 1
  return count

// @expect: 5
print(count_words("hello world foo bar baz"))

// === Reverse string ===
fn reverse_str(s: string): string
  var result = ""
  for i in 0..len(s)
    result = substring(s, i, i + 1) + result
  return result

// @expect: dlrow olleh
print(reverse_str("hello world"))

// === Palindrome check ===
fn is_palindrome(s: string): bool
  let cleaned = lower(s)
  return cleaned == reverse_str(cleaned)

// @expect: true
print(is_palindrome("racecar"))
// @expect: false
print(is_palindrome("hello"))

// === Count char occurrences ===
fn count_char(s: string, c: string): number
  var count = 0
  for i in 0..len(s)
    if substring(s, i, i + 1) == c
      count = count + 1
  return count

// @expect: 3
print(count_char("hello world", "l"))

// === Capitalize first letter ===
fn capitalize(s: string): string
  if len(s) == 0 then return ""
  return upper(substring(s, 0, 1)) + substring(s, 1, len(s))

// @expect: Hello
print(capitalize("hello"))

// === Simple join and split ===
let csv = "a,b,c,d"
let parts = split(csv, ",")
// @expect: 4
print(len(parts))
// @expect: a|b|c|d
print(join(parts, "|"))

// === String contains check ===
fn str_contains(haystack: string, needle: string): bool
  for i in 0..(len(haystack) - len(needle) + 1)
    if substring(haystack, i, i + len(needle)) == needle
      return true
  return false

// @expect: true
print(str_contains("hello world", "world"))
// @expect: false
print(str_contains("hello world", "foo"))

// === Repeat string ===
fn repeat_str(s: string, n: number): string
  var result = ""
  for _ in 0..n
    result = result + s
  return result

// @expect: abcabcabc
print(repeat_str("abc", 3))

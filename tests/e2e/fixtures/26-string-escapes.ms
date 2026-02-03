// @test: String Escapes and Multiline - String features

// === Basic strings ===
// @expect: hello
print("hello")
// @expect: hello world
print("hello world")

// === Empty string ===
// @expect: 0
print(len(""))

// === String with quotes ===
let quoted = "He said \"hello\""
// @expect: He said "hello"
print(quoted)

// === Newline escape ===
let with_newline = "line1\nline2"
// @expect: 2
print(len(split(with_newline, "\n")))

// === Tab escape ===
let with_tab = "col1\tcol2"
// @expect: true
print(len(with_tab) > 8)

// === Backslash escape ===
let with_backslash = "path\\to\\file"
// @expect: path\to\file
print(with_backslash)

// === String concatenation ===
let part1 = "Hello"
let part2 = "World"
// @expect: Hello World
print(part1 + " " + part2)

// === Multiline string ===
let multi = """first
second
third"""
let lines = split(multi, "\n")
// @expect: 3
print(len(lines))
// @expect: first
print(lines[0])

// === String interpolation ===
let name = "Alice"
let age = 30
let greeting = "Name: " + name + ", Age: " + to_str(age)
// @expect: Name: Alice, Age: 30
print(greeting)

// === String length ===
// @expect: 5
print(len("hello"))
// @expect: 11
print(len("hello world"))

// === Unicode strings ===
let unicode_str = "Hello"
// @expect: 5
print(len(unicode_str))

// === String comparison ===
// @expect: true
print("abc" == "abc")
// @expect: false
print("abc" == "ABC")
// @expect: true
print("a" < "b")

// === String methods ===
// @expect: HELLO
print(upper("hello"))
// @expect: hello
print(lower("HELLO"))
// @expect: hello
print(trim("  hello  "))

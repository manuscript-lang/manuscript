// Test cases for Tagged Templates

let varName = "some_value";
let anotherVar = "another_value";

// Simple cases
let a = customTag"hello ${varName}";
let b = anotherTag'world ${anotherVar}';

// Block string cases
let c = html"""Simple block string with ${varName}""";
let d = sql'''Another block string with ${anotherVar}''';

// No interpolations
let e = staticTag"just_a_plain_string";
let f = staticBlockTag"""another_plain_string_block""";

// Multiple interpolations
let g = multiTag"first ${varName} second ${anotherVar} third";
let h = multiBlockTag'''start ${varName} middle ${anotherVar} end''';

// Tag that might be a keyword
let k = let"keyword_tag_test ${varName}";
let l = fn"""fn_keyword_tag_test ${anotherVar}""";

// Edge case: Empty string
let m = emptyTag"";
let n = emptyBlockTag''''''

// Edge case: Only interpolation
let o = interpOnlyTag"${varName}";
let p = interpOnlyBlockTag"""${anotherVar}""";

// Escaped literal dollar curly for regular strings
let q = escapedTag"This is not an interpolation: \\${varName}. This is: ${anotherVar}";

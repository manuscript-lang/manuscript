# Newline and Semicolon Tests

## 1. Mandatory Semicolons

### Case 1.1: Missing semicolon between let statements
```ms
let x = 1
let y = 2
```
```go
ERR_SYNTAX
```

### Case 1.2: Correct semicolons between let statements
```ms
let x = 1;
let y = 2;
```

### Case 1.3: Missing semicolon between fn and let
```ms
fn foo() {}
let z = 3
```
```go
ERR_SYNTAX
```

### Case 1.4: Correct semicolon between fn and let
```ms
fn foo() {};
let z = 3;
```

### Case 1.5: Missing semicolon for return statement
```ms
fn testReturn() {
    return 1
}
```
```go
ERR_SYNTAX
```

### Case 1.6: Correct semicolon for return statement
```ms
fn testReturn() {
    return 1;
}
```

## 2. Newlines Inside Strings

### Case 2.1: Double-quoted string with newline
```ms
let s = "hello
world";
```

### Case 2.2: Single-quoted raw string with newline
```ms
let s = 'raw
string';
```

### Case 2.3: Template string with newlines
```ms
let s = `template
${1+1}
end`;
```

## 3. Newlines Inside Comments

### Case 3.1: Single-line comments with newlines
```ms
// comment
// another line
let a = 1;
```

### Case 3.2: Multi-line comment with newlines
```ms
/* multi-line
comment */
let b = 2;
```

## 4. Newlines Inside Parentheses/Brackets/Braces

### Case 4.1: Array literal with newlines
```ms
let arr = [1, 2,
3];
```

### Case 4.2: Object literal with newlines
```ms
let obj = {a: 1,
b: 2};
```

### Case 4.3: Function call with newlines in arguments
```ms
fn foo(a:int, b:int):int { return 1; }
let val = foo(1,
2);
```

### Case 4.4: Function definition with newlines in parameters
```ms
fn bar(x:int
, y:int) {};
```

### Case 4.5: Expression with newlines inside parentheses
```ms
let complex = (1 +
 2) * 3;
```

## 5. Newlines Inside Let Destructuring

### Case 5.1: Object destructuring with newlines
```ms
let myObj = {a:1, b:2, c:3};
let {a,
b
,c} = myObj;
```

### Case 5.2: Array destructuring with newlines
```ms
let myArr = [1,2,3];
let [x,
y
,z] = myArr;
```

## 6. Code Blocks

### Case 6.1: Newlines inside if block (should act as semicolons)
```ms
if true {
    let x = 1
    let y = 2
}
```

### Case 6.2: Mixed newline behavior in if block
```ms
if true {
    let x = (1
+2)
    let y = 2
}
```

## 7. Keyword/Argument List Newlines (Strict Interpretation)

### Case 7.1: Newline between function name and parameter list
```ms
fn baz
() {};
```
```go
ERR_SYNTAX
```

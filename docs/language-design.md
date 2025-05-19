# Manuscript Language Specification

## 1. Introduction

Manuscript is a modern, statically-typed programming language designed for clarity, conciseness, and developer productivity. It aims to blend the efficiency of compiled languages with the ease of use found in scripting languages. Manuscript draws inspiration from languages like Go, Rust, Python/TypeScript, and Swift.

Manuscript compiles to valid go code.

This document specifies the syntax, semantics, and core features of the Manuscript language.

## 2. Lexical Structure

This section describes the fundamental lexical elements of Manuscript, including comments, identifiers, keywords, operators, and literals. Manuscript source code is Unicode text.

### 2.1 Comments

Comments are used for explanatory notes within the code and are ignored by the compiler.

*   **Single-line comments**: Start with `//` and extend to the end of the line.
    ```ms
    // This is a single-line comment.
    let x = 10 // This comment explains the variable assignment.
    ```
*   **Multi-line comments (Block comments)**: 
    ```ms
    /*
      This would be a
      multi-line block comment.
    */
    ```

### 2.2 Identifiers

Identifiers are names used to denote variables, types, functions, labels, and other named entities. 

*   **Rules**: Identifiers must begin with a letter (a-z, A-Z) or an underscore (`_`). Subsequent characters can include letters, digits (0-9), and underscores.
*   **Case Sensitivity**: Identifiers are case-sensitive. `myVariable` and `MyVariable` are distinct identifiers.
*   **Reserved Words**: Keywords (see Section 2.3) cannot be used as identifiers.

```ms
let userName = "Alice"
let _internalCounter = 0
fn calculateTotalValue() { /* ... */ }
type Point2D { x: number, y: number }
```

### 2.3 Keywords

The following tokens are reserved keywords in Manuscript and cannot be used as identifiers. Their usage is defined throughout this specification.

```
// Declarations & Structure
let, fn, return, yield
type, interface, extends
import, export, extern

// Control Flow & Conditionals
if, else, for, while, in, match, case, default

// Error Handling & Preconditions
check, try

// Concurrency
go

// Literals & Special Values
as, void, null, true, false
```

**Keyword Usage Overview:**

*   **`let`**: Declares constants and variables (mutability to be defined, typically `let` implies immutable by default in modern languages, or Manuscript might have a `var` keyword if `let` is strictly for constants).
*   **`fn`**: Declares functions and methods.
*   **`return`**: Exits a function, optionally returning a value.
*   **`yield`**: Pauses a generator function, producing a value to its caller.
*   **`type`**: Defines custom data structures (structs, algebraic data types).
*   **`interface`**: Defines a contract of methods that types can implement.
*   **`extends`**: Used for inheritance with structs and interfaces.
*   **`import`**: Imports symbols from other modules.
*   **`export`**: Makes symbols available to other modules.
*   **`extern`**: Declares symbols defined externally (e.g., in another language).
*   **`if`, `else`**: Conditional execution.
*   **`for`, `while`, `in`**: Loop constructs.
*   **`match`, `case`, `default`**: Pattern matching control flow.
*   **`check`**: Asserts a precondition; if false, exits the current function with an error.
*   **`try`**: Used for error propagation in expressions.
*   **`async`**: Defines an asynchronous function.
*   **`await`**: Pauses execution of an async function until an awaited task completes.
*   **`as`**: Used for type casting or renaming imports.
*   **`void`**: Specifies that a function does not return a value.
*   **`null`**: Represents the absence of a value for reference types.
*   **`true`, `false`**: Boolean literal values.

### 2.4 Operators

Manuscript will include a standard set of operators (arithmetic, comparison, logical, bitwise, etc.). The specific operators and their precedence will be defined in a dedicated subsection or an appendix on expressions.

( `+`, `-`, `*`, `/`, `%`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `&&`, `||`, `!`, `&`, `|`, `^`, `<<`, `>>`, `.` for member access, `[]` for indexing, `()` for function calls)

### 2.5 Literals

Literals are notations for constant values of built-in types. These are detailed further in Section 3.3.

## 3. Types and Variables

Manuscript is a statically-typed language, meaning the type of every variable is known at compile time. This allows for early error detection and performance optimizations. Manuscript strongly emphasizes type safety and aims for a clear and expressive type system, featuring type inference to reduce boilerplate.

### 3.1 Primitive Types

Primitive types are the most basic data types available in Manuscript.

*   **`bool`**: Represents a logical value, which can be either `true` or `false`. Booleans are commonly used in control flow statements.
    ```ms
    let is_feature_enabled: bool = true
    let has_critical_errors = false // Type inferred as boolean

    if is_feature_enabled && !has_critical_errors {
        // Launch new feature module
        print("Feature module launched.")
    }
    ```

*   **Numeric Types**: Manuscript provides a range of numeric types for integers and floating-point numbers. The choice of type depends on the required range and precision.
    *   **Integer Types**: Represent whole numbers.
        *   `i32`: A 32-bit signed integer. Often the default for integer literals if not otherwise specified or inferred.
        *   `i64`: A 64-bit signed integer (aliased as `long`). Suitable for larger whole numbers, like database IDs or timestamps.
        *   `int`: A signed integer whose size is platform-dependent (e.g., 32-bit or 64-bit). Use when the specific size is not critical for logic but performance on the target platform is a consideration.
        *   `i8`, `i16`: Signed integers of 8 and 16 bits, for memory-constrained scenarios or specific data formats (e.g., network protocols, image processing).
        *   Unsigned integer types like `uint8`, `uint16`, `uint32`, `uint64`
    *   **Floating-Point Types**: Represent numbers with a fractional component.
        *   `f32`: A 32-bit single-precision floating-point number. This is the type of the `number` alias, suitable for graphics or general calculations where high precision is not paramount.
        *   `f64`: A 64-bit double-precision floating-point number (aliased as `double`). Offers higher precision than `f32`, preferred for financial or scientific computations.
    *   **`number` Alias**: The keyword `number` is an alias for `f32`. This is often the default type for numeric literals with a decimal point if not otherwise specified or inferred.

    ```ms
    let server_response_code: i32 = 200
    let user_id: i64 = 103_729_554_928i64 // Using i64 suffix and readability underscores for a large ID
    let items_in_inventory = 5_000 // Likely inferred as i32 or int

    let product_price: number = 49.95 // Alias for f32
    let earth_gravity: f64 = 9.80665f64 // Using f64 for a scientific constant
    let processing_time_seconds = 0.075 // Likely inferred as number (f32)

    let network_packet_type: i8 = 0x02i8 // An 8-bit type field from a packet
    let image_pixel_red_component = 0xE4 // Hex literal, inferred as integer, context might refine type
    let system_flags_register = 0b10010011 // Binary literal
    ```

*   **`string`**: Represents an immutable sequence of Unicode characters. Strings are fundamental for text manipulation, and Manuscript provides rich support for string literals and operations.
    ```ms
    let api_endpoint_path: string = "/users/query/active"
    let report_title = 'Monthly Sales Performance' // Single quotes also common
    let empty_json_array = "[]"
    ```

*   **`void`**: Represents the absence of a value. It is primarily used as the return type for functions that do not return any meaningful value to their caller (e.g., functions performing only side effects, like logging or updating external state).

*   **`null`**: Represents an intentional absence of a value, typically for reference types (like strings, objects, or user-defined types). Using `null` with non-nullable primitive types (like `number` or `bool` without a `?` marker) is typically a compile-time error. Manuscript promotes null safety, likely through optional types (e.g., `string?`, see Section 3.5 on Optional Types if it exists, or specify here).
    ```ms
    let optionalValue: string? = null // A user might not have a middle name
    // let accountBalance: number = null    // ERROR: 'number' (f32) is not nullable by default.
                                         // Would require 'number?' or similar.
    ```

### 3.2 Variable Declarations

Variables store values that can be referenced and potentially manipulated. Manuscript uses the `let` keyword for declaring bindings.
```ms
let serverBaseUrl = "https://api.example.com"
```

#### Let Block Syntax
You can declare multiple variables at once using a let block:
```ms
let (a = 1, b = 2)
```
This is equivalent to declaring `a` and `b` separately.

#### Destructuring Assignment
Manuscript supports destructuring assignment for arrays and objects (structs). This allows for concisely extracting multiple values into separate variables, improving readability.

```ms
// For Objects (Structs)
type ServerConfig { host: string, port: i32, use_tls: bool }
let current_config ServerConfig = {
    host: "localhost", 
    port: 8080, 
    use_tls: false
}
let {host, port} = current_config
// host is "localhost", port is 8080

// For Arrays
let semver_components = "1.2.3-beta".split('.') // Assume split returns string[]
let [major_version, minor_version] = semver_components // major = "1", minor = "2"
// To get all parts, or handle variable length, other patterns might be needed:
// let [major, minor, patch_and_prerelease...] = sem_ver_parts // Spread for remaining parts
```

> **Note:** Tuple destructuring on the left-hand side of `let` (e.g., `let (a, b) = ...`) is not directly supported by the grammar. To destructure a tuple, assign it to a variable and then access its elements by index or use array destructuring if the tuple is returned as an array.

*   **Type Annotation and Inference**: Type annotations are optional if the compiler can unambiguously infer the type from the initializer expression. Explicit type annotations improve code clarity, act as documentation, and are required in situations where inference is not possible or desired for contract clarity (e.g., function signatures, uninitialized variable declarations if allowed).

    ```ms
    let default_api_version = "v1"          // Type inferred as string
    let max_connections i32 = 100          // Type explicitly annotated
    let default_timeout_seconds = 15.0      // Type inferred as number (f32)

    let loaded_plugin PluginType? // Declaring a nullable variable, type annotation is essential here.
                                    // It will be initialized to null by default for optional types.
    loaded_plugin = plugin_manager.load("advanced-renderer") // Assuming function returns PluginType?
    ```

### 3.3 Literals

Literals are source code representations of fixed values of primitive or built-in types.

#### 3.3.1 Boolean Literals
*   `true`: The boolean true value.
*   `false`: The boolean false value.

#### 3.3.2 Numeric Literals
Numeric literals represent numbers.
*   **Integers**: Can be decimal (e.g., `123`), hexadecimal (prefix `0x`, e.g., `0xFF`), binary (prefix `0b`, e.g., `0b1010`), or octal (prefix `0o`, e.g., `0o17`).
*   **Floating-point**: Contain a decimal point (e.g., `3.14`) and/or an exponent part (e.g., `6.022e23`, `1.0E-9`).
*   **Suffixes for Explicit Typing**: Suffixes can specify the exact numeric type, overriding default inference.
    *   Integer: `i8`, `i16`, `i32`, `i64` (e.g., `100i64`, `0xFFi8`). (And `u...` if unsigned types are supported).
    *   Float: `f32`, `f64` (e.g., `3.14f32`, `0.123f64`).
*   **Readability**: Underscores (`_`) can be used as separators within numeric literals (e.g., `1_000_000`, `3.141_592_65`).

    ```ms
    let max_file_size_bytes = 2_147_483_648i64 // 2GiB as i64
    let default_permissions = 0o755 // Octal literal for permissions
    let important_ratio = 0.618_033_988_7f64 // Golden ratio with f64 precision
    let fixed_point_value_scaled = 12345i32 // Integer part of a scaled fixed-point number
    ```

#### 3.3.3 String Literals

String literals represent sequences of Unicode characters and are immutable.

*   **Single-quoted (`'`) and Double-quoted (`"`) strings**: Both can be used for standard string literals. The choice is often stylistic, but they behave identically in terms_of escape sequence processing and interpolation.
    ```ms
    let log_message_prefix = '[INFO]:'
    let error_details_json = "{\"error\": \"FileNotFound\", \"path\": \"/data/input.txt\"}"
    ```
    *   **Escape Sequences**: Standard escape sequences are supported: `\n` (newline), `\t` (tab), `\r` (carriage return), `\'` (single quote within single-quoted string), `\"` (double quote within double-quoted string), `\\` (backslash). Unicode escapes like `\u{XXXX}` (where XXXX are 1-6 hex digits for a Unicode code point) allow specifying any Unicode character.
        ```ms
        let formatted_address = "Contoso, Ltd.\n123 Main St.\nAnytown, WA 98000\u{2122}" // Includes trademark symbol
        ```

*   **Multiline Strings (Concise Form)**: For single or double-quoted strings spanning multiple source lines, the compiler typically performs intelligent unindentation. It might determine a common non-whitespace prefix from the content lines and remove that prefix, preserving relative indentation. This allows readable formatting in code while producing a clean string value.
    ```ms
    let html_snippet = '<div class="profile">
                          <img src="avatar.png" alt="User Avatar">
                          <p class="username">DefaultUser</p>
                        </div>'
    // The exact rules for unindentation (e.g., based on the indent of the closing quote or least indented line)
    // need to be clearly defined. The goal is to remove common leading whitespace.
    ```

*   **String Interpolation**: Expressions can be embedded within string literals (both single and double-quoted) using `${expression}`. The expression is evaluated, its string representation is obtained (e.g., via a standard `toString()`-like conversion), and it's inserted into the string.
    ```ms
    let current_user_name = "Satoshi"
    let account_balance = 123.456
    let notification = "User: ${current_user_name}, Balance: $${account_balance.toFixed(2)}"
    // notification -> "User: Satoshi, Balance: $123.46" (assuming toFixed exists)

    let query_params = "id=${generate_request_id()}&ts=${current_timestamp_millis()}"
    ```

*   **Block Strings (Raw/Verbatim Strings)**: Enclosed in triple single quotes (`'''`) or triple double quotes (`"""`). These preserve all whitespace, newlines, and indentation *within the delimiters* exactly as they appear in the source code. Escape sequences are generally not processed, except possibly for escaping the delimiter itself (e.g., `''\'` or `""\"`).
    ```ms
    let bash_script_heredoc = '''
    #!/bin/bash
    echo "Processing files in $1..."
    for f in "$1"/*.txt; do
      echo "  - $f"
    done
    echo "Finished."
    '''
    // This is useful for embedding code snippets, configuration data, or pre-formatted text.
    ```

*   **Tagged Block Strings (e.g., `upper'''...'''`)**: The syntax `tag_name'''...'''` (or with `"""`) allows for custom compile-time or runtime processing of block string content by a `tag_name` function or macro. This is a powerful extensibility feature for DSLs or specialized string transformations.
    *   The `tag_name` function would receive the raw string content and potentially any interpolated expressions as arguments.

    ```ms
    // Example: Built-in 'upper' tag for uppercasing while preserving structure.
    let marketing_header = upper'''
      limited time offer!
      get it now before it's too late.
    '''
    // Expected marketing_header (conceptual, exact newline/indent rules for tags apply):
    // "LIMITED TIME OFFER!\nGET IT NOW BEFORE IT'S TOO LATE."

    // Example: Hypothetical 'markdown' tag for converting Markdown to HTML at compile/runtime.
    // type HtmlString { raw: string } // A type to represent HTML to prevent XSS if not careful
    // fn markdown(raw_md_parts: string[], ...interpolated_values): HtmlString { /* ... */ }
    // let comment_text = "This is **bold** and *italic*."
    // let rendered_comment: HtmlString = markdown'''
    //   ### User Comment
    //   ${comment_text}
    //   --- 
    //   Posted by: ${current_user_name}
    // '''
    // // rendered_comment.raw might be "<h3>User Comment</h3><p>This is <strong>bold</strong> and <em>italic</em>.</p><hr /><p>Posted by: Satoshi</p>"
    ```
    The specific capabilities (compile-time vs. runtime, handling of interpolation, type of result) of tagged strings must be clearly defined.

### 3.4 Complex Data Types

Manuscript provides several built-in complex data types for organizing collections of data. These types generally have value semantics when passed around (i.e., a copy is made) unless explicitly defined or used as reference types (which would be a separate language feature to specify, e.g., via pointers or explicit reference wrappers).

*   **Arrays**: Dynamically-sized, ordered collections of elements of the **same type**. Arrays are 0-indexed and provide efficient random access. Manuscript arrays are expected to support common operations like length, append, iteration, and indexed access/modification (if the array binding is mutable).
    ```ms
    let pending_job_ids: i32[] = [101, 102, 105, 108]
    let user_roles = ["admin", "editor", "viewer"] 
    let event_timestamps: i64[] = []
    ```

*   **Objects (Ad-hoc Struct Literals)**: Collections of key-value pairs, where keys are identifiers (strings) and values can be of any type. These are useful for creating simple, unstructured data containers without needing a formal `type` definition. Their structure is fixed at the point of creation.
    ```ms
    let options = {
        method: "POST",
        url: "https://api.example.com/submit",
        timeout_ms: 5000,
        headers: {
            "Content-Type": "application/json",
            "X-API-Key": "secret-key"
        },
        body: "{\"data\": \"sample\"}"
    }
    print("Requesting ${options.method} to ${options.url}")
    ```

*   **Maps (Dictionaries)**: Unordered collections of key-value pairs, where keys are of a single, hashable type (e.g., `string`, `i32`, `bool`), and all keys within a map instance are unique. Values can be of any single type. Maps provide efficient lookups, insertions, and deletions by key.
    ```ms
    // Using 'var' for a mutable map
    var user_preferences: [string:string] = ["theme": "dark", "language": "en"]
    user_preferences["notifications"] = "enabled" // Add/update entry
    user_preferences["language"] = "de"          // Update existing entry

    let feature_flags: [string:bool] = [
        "newDashboardFeature": true,
        "experimentalApiAccess": false,
        "betaUserProgram": true
    ]
    if feature_flags["newDashboardFeature"] == true {
        // Display new dashboard
    }
    ```

*   **Sets**: Unordered collections of unique elements of a single **type**. Sets are highly optimized for membership testing (checking if an element is present) and for set operations like union, intersection, and difference.
    ```ms
    let active_session_ids: <string> = <"sess_abc", "sess_def", "sess_xyz">
    active_session_ids.add("sess_123") // Add new session
    active_session_ids.add("sess_abc") // No change, already present

    let required_permissions: <string> = <"read_data", "write_data", "execute_report">
    let user_granted_permissions: <string> = <"read_data", "view_audit_log">
    ```

*   **Tuples**: Fixed-size, ordered collections where each element can be of a **different type**. Tuples are immutable once created and are useful for grouping a small, fixed number of related items, often for returning multiple distinct values from functions or representing simple compound records.
    ```ms
    fn get_rgb_color_components(color_name: string): (i8, i8, i8, string)? {
        if color_name == "red" { return (255i8, 0i8, 0i8, "sRGB") }
        if color_name == "blue" { return (0i8, 0i8, 255i8, "sRGB") }
        return null // Color not found
    }

    let primary_red: (i8, i8, i8, string) = (255i8, 0i8, 0i8, "sRGB") // Type annotation for clarity
    let (red_val, green_val, blue_val, color_space) = primary_red
    // red_val is 255i8, green_val is 0i8, blue_val is 0i8, color_space is "sRGB"

    // Accessing tuple elements by index (e.g., primary_red.0) might be supported,
    // but destructuring is generally preferred for readability.
    ```

## 4. User-Defined Types

Manuscript allows users to define their own custom types using `type` for structs and `interface` for contracts.

### 4.1 Structs (`type`)

Structs are composite data types that group together variables under a single name.

```ms
type Point {
    x: number
    y: number
}

type ColorPoint {
    point: Point
    color: string
    alpha: number? // Optional field
}

let anon_struct: { name: string, value: number } = { name: 'test', value: 123 }
```

**Inheritance with `extends`**: Structs can inherit fields from other structs.
```ms
type Shape {
    id: string
}

type Circle extends Shape {
    radius: number
}

// A Circle instance will have 'id' and 'radius' fields.
```

**Type Aliases with Constraints**: You can create a type alias with an optional constraint using `extends`:
```ms
type NewName = ExistingType extends Constraint
```
This means `NewName` is an alias for `ExistingType` with the additional constraint `Constraint` (which may be an interface or another type).

**Object Creation (Instantiation)**: Instances of structs are created by calling the type name as a function with named fields:
```ms
let p1 = Point() // x and y will have default values for 'number' (e.g., 0)
let p2 = Point(x: 10, y: 20) // Using named fields for initialization
```

**Constructors**: Custom constructor functions can be defined using `fn` with the same name as the type. These are regular functions that return an instance of the struct. If no constructor is defined, a default one is provided which initializes fields to their default values.
```ms
type Vector {
    x number
    y number
}

fn Vector(x_val number, y_val number) Vector {
    let v: Vector = {
        x: 10,
        y: 20
    }
    v
}

let v1 = Vector(3, 4)
let v2 = Vector()
```
The primary way to instantiate a struct is via the named-field literal, either directly or from a constructor function.

### 4.2 Interfaces (`interface`)

Interfaces define a contract of methods that a type can implement. They specify method signatures (name, parameters, return type) but not their implementation.

```ms
interface Renderer {
    draw() void
    setColor(hex: string) bool
}

interface Logger {
    log(message string) void
    error(message string, code number?): void
}
```

**Interface Inheritance with `extends`**: Interfaces can extend other interfaces, inheriting their method signatures.
```ms
interface AdvancedRenderer extends Renderer {
    setShader(shaderId string) void
}
```
The syntax is `interface B extends name {}`.

### 4.3 Methods

Methods are functions associated with a specific type. They are defined using the `methods` keyword.

**Implementing Interface Methods**:
```ms
interface ILogger {
    log(message string) void
    error(message string, code number?): void
}

type ConsoleLogger {
    prefix string
}

methods ConsoleLogger as self {
    fn log(message string) void {
        print('${self.prefix}: ${message}')
    }

    fn error(message string, code? number) void {
        if code != null {
            print('ERROR (${code}): ${self.prefix}: ${message}')
        } else {
            print('ERROR: ${self.prefix}: ${message}')
        }
    }
}

let logger = ConsoleLogger()
logger.error("asdas", 10)
```

**Non-Interface Methods (Intrinsic Methods)**: Types can also have methods that are not part of any interface.
```ms
type Counter {
    value: number
}

methods Counter as c {
    fn increment(amount number) void {
        c.value = c.value + amount
    }

    fn getValue() number {
        return c.value
    }
}

let c = Counter(value 0)
c.increment(5)
c.getValue()
```

**Method and Field access on a nullable**
To call methods on a nullable use the coalace operator
```
let user: User?
user?.name 
user?.getFullName()
```

## 5. Functions

Functions are fundamental building blocks in Manuscript. They encapsulate reusable blocks of code.

### 5.1 Declaration Syntax

Functions are declared using the `fn` keyword.

```ms
fn greet() {
    print('Hello, Manuscript!')
}

let my_function = fn() {
    print('This is a function variable.')
}

fn add(a number, b number) number {
    return a + b
}
```

### 5.2 Parameters

Functions can accept zero or more parameters. Each parameter must have a name, and its type can be specified.

```ms
fn print_message(message string) {
    print(message)
}

type Data {value number}
type Options {verbose bool}
fn process_data(data Data, options? Options) {
    if options?.verbose {
        print('Processing: ${data.value}')
    }
}
```

### 5.3 Return Values
If the last statement is an expression then last value from the block is returned automatically, however functions can return values using the `return` keyword.
*   **Single Return Value**:
    ```ms
    fn get_pi() number {
        return 3.14159
    }
    ```
*   **Void Return Type**: If a function does not return a value, its return type is `void`. The `return` keyword can be omitted, or used without an expression.
    ```ms
    fn log_message(message string) void {
        print(message)
    }

    fn do_nothing() { /* no return statement needed */ }
    ```

*   **Multiple Return Values**: Functions can return multiple values as a tuple.
    ```ms
    fn get_coordinates() (number, number) {
        (10.5, -3.2)
    }
    let (x, y) = get_coordinates()
    ```

*   **Error Indication**: The `!` suffix on a return type (e.g., `string!`) indicates that a function might throw an error or return an error state. This is often used in conjunction with `try/catch` or `check`.
    ```ms
    fn read_file_content(path string) string! {
        // ... logic that might fail ...
        // if path_does_not_exist {
            // throw new Error('File not found') // Exact error throwing mechanism TBD
        // }
        return "file content"
    }

    fn withErrorShorthand(arg1 string) string! { "placeholder!" }
    ```

*   **Implicit Returns**: For single-expression functions, the `return` keyword can sometimes be omitted, and the result of the expression is automatically returned.
    ```ms
    fn get_one() number { 1 }
    fn square(x number) number { x * x }
    ```

### 5.5 Generator Functions (`yield`)

Generator functions can pause execution and yield multiple values one at a time, without returning. They are defined using the `fn` keyword and use the `yield` keyword to produce values.

```ms
fn count_to(n number) {
    let i = 0
    while i < n {
        yield i
        i = i + 1
    }
}

// Consuming a generator
// for item_val in count_to(3) {
// print(item_val)
// }

fn range_generator(start number, end number, step number = 1) {
    let current = start
    while current < end {
        yield current
        current = current + step
    }
}
```

### 5.7 Default Parameter Values

Function parameters can have default values, making them optional when the function is called.

```ms
fn greet_person(namestring, greeting string = 'Hello') {
    print('${greeting}, ${name}!')
}

// greet_person('Alice')           // Example call
// greet_person('Bob', 'Hi')     // Example call

fn setup_service(port number = 8080, retries number = 3) {
    print('Setting up service on port ${port} with ${retries} retries.')
}
// setup_service() // Example call
// setup_service(port 9000) // Example call
```

### 5.8 Anonymous function
Anonymous functions can be declared using fn keyword, but without the name, eg - 

```ms
fn(a int, b int) int { a + b }
fn(a int, b int) { a + b }

let filterFunc = fn(a string) { a.startWith("a") }
list.filter(filterFunc)
```

## 6. Imports and Modules

Manuscript supports modular programming by allowing code to be organized into separate files and modules. The `import` and `export` keywords manage visibility and access between modules. The `extern` keyword is used for interfacing with code written in other languages.

### 6.1 `export` Declarations

The `export` keyword makes functions, variables, types, or interfaces available for use in other modules.

```ms
// module: 'math_utils.ms'
export fn add_numbers(a number, b number) number {
    return a + b
}

export let PI_VALUE number = 3.14159

export type PointType {
    x_val number
    y_val number
}
```

### 6.2 `import` Declarations

The `import` keyword is used to bring exported members from other modules into the current scope.

```ms
// Assuming 'math_utils.ms' is in a resolvable location
import { add_numbers, PI_VALUE } from 'math_utils'
import { PointType as Vec2D } from 'math_utils'

let sum_val = add_numbers(5, PI_VALUE)
let p_vec Vec2D = {x_val:0, y_val:0}

import b1_service_client from 'b/v1/client'

// Grouped imports from original notes:
 import {
    b from 'b'          
    {c_val as d_val} from 'd' 
}
```
The exact syntax for default imports and how they interact with named imports, especially within grouped import statements, requires precise definition in the language grammar.

### 6.3 `extern` Declarations

The `extern` keyword declares functions or variables that are defined externally, typically in another language (e.g., C, Go, JavaScript) and linked with the Manuscript program. This allows Manuscript code to call foreign functions or access foreign variables. Type signatures for `extern` members are crucial.

```ms
extern external_logging_library from 'external_logging_library'

extern { global_system_config } from 'config/store' 

// Grouped extern declarations from original notes:
extern {
    sqrt_math_function from 'math_lib' 
    { PI_MATH_CONSTANT as PI } from 'math_lib' 
}

sqrt_math_function(16)
```
Mechanisms for specifying the actual external library linkage (e.g., library name, symbol name) and type marshalling are important details for the implementation of `extern`.

## 7. Control Flow

Manuscript provides several control flow statements to direct the execution path of a program.

### 7.1 Conditional Execution: `if`/`else`

The `if` statement executes a block of code if a condition is true. An optional `else` block can be provided for execution if the condition is false. `else if` can be used for multiple conditions.

```ms
fn check_number_sign(n number) string {
    if n > 0 {
        return 'Positive'
    } else if n < 0 {
        return 'Negative'
    } else {
        return 'Zero'
    }
}

fn get_llm_provider(modelName string) string {
    if modelName == 'gpt4' { 'OpenAI' }
    if modelName == 'gemini-pro' { 'Google' }
    return 'UnknownProvider' 
}

fn determine_provider_style1(modelName string) string {
    let provider string
    if modelName == 'gpt4' { provider = 'OpenAI' }
    else if modelName == 'gemini-pro' { provider = 'Google' }
    else { provider = 'UnknownProvider' }
    provider
}
```

### 7.2 Pattern Matching: `match`

The `match` statement provides a way to compare a value against a series of patterns and execute code based on the first matching pattern. This is often more powerful and readable than `if/else if` chains for complex conditional logic.

```ms
fn get_llm_provider_with_match(modelName string) string {
    match modelName {
        case 'gpt4': 'OpenAI' 
        case 'gemini-pro': 'Google'
        case 'claude-3': {
            print('Anthropic model Claude 3 selected.') // Side-effect
            'Anthropic'
        }
        default: 'UnknownProvider' 
    }
}
```

### 7.3 Loops

Loops are used to execute a block of code repeatedly.

#### 7.3.1 `while` Loops

A `while` loop executes as long as a condition remains true.

```ms
fn perform_countdown_while(start_val number) {
    let i = start_val
    while i > 0 {
        // print(i) // Example action
        i--
    }
    // print('Liftoff!') // Example action
}
```

#### 7.3.2 `for` Loops

Manuscript supports several styles of `for` loops.

*   **C-style `for` loop** (syntax based on original notes):
    ```ms
    fn print_numbers_c_loop(limit_val number) {
        for i = 0; i < limit_val; i++ { 
            // print(i) // Example action
        }
    }
    ```

*   **`for...in` with Collections**: Iterates over elements in a collection (e.g., arrays, map keys/values). The exact behavior (e.g., whether it provides index/value or just value for arrays, key/value or just key for maps) needs to be defined.
    ```ms
    fn process_collections_for_loop() {
        let web_frameworks = ['React', 'Vue', 'Svelte']
        for framework in web_frameworks {
            // print(framework) 
        }

        let country_capitals = ['USA': 'Washington D.C.', 'France': 'Paris']
        for country_name in country_capitals {
            // print(country_name) // Example action
        }

        for country_name, capital_city in country_capitals {
            // print('Capital of ${country_name} is ${capital_city}') // Example action
        }
    }
    ```

## 8. Error Handling

Manuscript provides mechanisms for handling errors that may occur during program execution. This involves conventions for functions to signal errors and constructs for catching and managing these errors.

### 8.1 Signaling Errors

Functions can indicate that an error might occur in a few primary ways:

*   **Returning a Tuple `(value, error)`**: A common pattern is for a function to return a tuple where one element is the intended result and the other is an error object. On success, the error object is typically `null`.
    ```ms
    type ArithmeticError {
        message: string
        operation: string
    }

    methods ArithmeticError as self {
        error(): string { '${self.operation} ${self.message}' }
    }

    fn safe_divide(numerator: number, denominator: number): (number, ArithmeticError) {
        if denominator == 0 {
            return (null, ArithmeticError{message: 'Division by zero', operation: 'divide'})
        }
        return (numerator / denominator, null)
    }
    ```

*   **Using `!` Suffix in Return Type**: A `!` suffix on a function's return type (e.g., `string!`, `User!`) signals that the function might fail and that this failure must be explicitly handled by the caller. This is often associated with an exception-like mechanism or a required check.
    ```ms
    type AppConfig { serverUrl: string, timeoutMs: number }
    fn load_app_configuration(filePath: string): AppConfig! {
        if filePath == 'missing.json' { 
            return Error('Configuration file not found: ${filePath}') 
        }
        // ... logic to parse file ...
        AppConfig{serverUrl: 'http://api.example.com', timeoutMs: 5000}
    }
    ```
    The exact nature of what `!` implies (e.g., checked exceptions, monadic error type) needs to be fully specified in the language semantics.

### 8.3 `try` Expressions and Blocks

try works on function call expressions that return a error type in go, one can use try on a individual function call, or a tuple of function calls

*   **`try` as an expression**: This allows `try` to be used in assignments, potentially unwrapping the success value or propagating the error.
    ```ms
    fn fetch_data() (string, OperationError) {
        // return ("User data", null) // example success
        return (null, OperationError(message: 'Network timeout', code: 504)) // example failure
    }

    fn process_data_with_try_expr() {
        let user_json = try fetch_data() // translates to user_json, err := fetch_data(); if err !=nil { return nil, err }
    }
    ```

*   **`try` block for multiple operations**: A `try` block can wrap multiple expressions, which is shorthand for writing try for expression individually.
    ```ms
    let (a, b) = try (
        fetch_data(),
        user.dosomething(),
    )
    
    ```
which translates to 
```go
a, err := fetch_data()
if err != nil {
    return nil, err
}
b, err := user.dosomething()
if err != nil {
    return nil, err
}
```

### 8.4 The `check` Keyword

The `check` keyword in Manuscript provides a concise way to assert preconditions. It is similar in spirit to Swift's `guard` statement but with a more terse syntax. It evaluates a condition and, if the condition is false, causes the current function to exit by returning an error, using the provided error message.

**Syntax:**

`check <condition>, <error_message_string_literal>`

**Semantics:**

1.  The `<condition>` is evaluated.
2.  If the `<condition>` is true, execution proceeds to the next statement.
3.  If the `<condition>` is false, the current function immediately terminates. It returns an error value (or throws an error if the function is marked with `!`). The error created will use the `<error_message_string_literal>`.

This is particularly useful for validating parameters or state at the beginning of a function.

**Example:**

Consider the Manuscript code:
```ms
fn process_payment(amount number, currency string) string! { 
    check amount > 0, 'Payment amount must be positive'
    check currency == 'USD' || currency == 'EUR', 'Unsupported currency: ${currency}'

    // process payment logic 
}
```

This `check` statement:
```ms
check amount > 0, 'Payment amount must be positive'
```

would translate to Go-like logic as follows 

```go
if !(amount > 0) {
    return nil, fmt.Errorf("Payment amount must be positive")
}
```
---
title: "Piped Syntax"
linkTitle: "Piped Syntax"
weight: 80
description: >
  Chain function calls using pipeline syntax for data processing workflows.
---

# Piped Syntax

Manuscript's piped syntax transforms how you write data processing code by allowing you to chain function calls in a readable, left-to-right pipeline. Instead of nested function calls or intermediate variables, you can express data transformations as a clear sequence of operations.

## What Piped Syntax Achieves

**Readability**: Data flows naturally from left to right, making the transformation sequence obvious at a glance.

**Composability**: Functions become building blocks that can be easily combined, reordered, or replaced without restructuring your code.

**Maintainability**: Each step in the pipeline is isolated and testable, making debugging and modifications straightforward.

**Functional Style**: Encourages writing pure functions that transform data rather than mutating state.

## Prerequisites

- [Functions](../functions/) - Understanding function definitions and calls
- [Variables](../variables/) - Basic variable usage

## Basic Pipeline Syntax

The pipe operator (`|`) takes the output from one expression and passes it as input to the next function in the chain.

### Example 1: Simple Data Processing

```ms
fn main() {
  // Traditional nested approach
  let result = save(validate(transform(getData())))
  
  // Piped syntax - clear data flow
  getData() | transform | validate | save
}
```

**What this achieves**: The piped version reads like a sentence describing the data flow: "get data, then transform it, then validate it, then save it." The nested version requires reading inside-out and becomes unreadable with more operations.

### Example 2: Pipeline with Arguments

```ms
fn processNumbers() {
  // Traditional approach with intermediate variables
  let numbers = [1, 2, 3, 4, 5]
  let doubled = multiply(numbers, 2)
  let shifted = add(doubled, 10)
  let formatted = format(shifted, 2)
  
  // Piped syntax with named arguments
  [1, 2, 3, 4, 5] 
    | multiply factor=2 
    | add offset=10 
    | format precision=2
}
```

**What this achieves**: Named arguments in pipelines make the transformation intent explicit. You can see exactly what each step does without looking up function signatures. The pipeline eliminates temporary variables that clutter the code.

### Example 3: Method Calls in Pipelines

```ms
fn analyzeData() {
  // Traditional object-oriented chaining
  let result = data.getEntries().filter(isValid).transform(normalize).save()
  
  // Piped syntax mixing functions and methods
  data.getEntries() 
    | filter condition=isValid 
    | processor.transform 
    | save
}
```

**What this achieves**: Piped syntax works seamlessly with both functions and methods, giving you flexibility in how you structure your code. You're not locked into a specific object hierarchy.

### Example 4: Error Handling in Pipelines

```ms
fn processFile(filename string) Report! {
  // Pipeline with error handling
  let result = try readFile(filename) 
    | parseLines 
    | validateEntries 
    | generateReport
  
  return result
}
```

**What this achieves**: Error handling integrates naturally with pipelines. If any step fails, the entire pipeline stops and returns the error. This prevents the pyramid of doom you get with traditional error checking.

### Example 5: Complex Data Transformation

```ms
fn analyzeLogFile(filename string) []PageStats! {
  // Compare traditional approach:
  let content = try readFile(filename)
  let lines = split(content, "\n")
  let entries = []LogEntry
  for line in lines {
    let entry = try parseLogLine(line) else { continue }
    if isValidEntry(entry) {
      entries.append(entry)
    }
  }
  let stats = calculatePageStats(entries)
  let sorted = sortByHits(stats)
  return sorted[0:min(10, len(sorted))]
  
  // Piped approach:
  return readFile(filename)
    | split content="\n"
    | parseLogEntries
    | calculatePageStats
    | sortByHits
    | takeTop count=10
}
```

**What this achieves**: The data transformation becomes a declarative description of what you want to happen, not how to make it happen.

## How Pipelines Work

Manuscript transpiles pipelines into efficient Go code that creates processor functions and iterates through data:

```ms
// Manuscript pipeline
data | transform | validate
```

Becomes equivalent to:
```go
// Generated Go code (simplified)
proc1 := transform()
proc2 := validate()
for _, v := range data() {
    a1 := v
    a2 := proc1(a1)
    a3 := proc2(a2)
}
```

This gives you the readability benefits of functional programming with the performance of imperative code.

## When to Use Piped Syntax

**Perfect for:**
- Data transformation workflows (ETL, parsing, analysis)
- Sequential processing where each step depends on the previous
- Functional programming patterns
- Stream processing of collections

**Consider alternatives for:**
- Simple single-step operations
- Complex branching logic
- Operations that need multiple inputs from different sources

## Best Practices

**Keep pipelines focused**: Each pipeline should have a single, clear purpose.

```ms
// Good: Clear purpose
userInput | sanitize | validate | store

// Avoid: Mixed concerns
userInput | sanitize | validate | store | sendEmail | logActivity
```

**Use descriptive function names**: Pipeline steps should read like a story.

```ms
// Good: Self-documenting
csvData | parseRows | filterValid | calculateTotals | generateReport

// Less clear: Abbreviated names
csvData | parse | filter | calc | gen
```

**Break up long pipelines**: If a pipeline has more than 5-6 steps, consider splitting it.

```ms
// Good: Logical grouping
let cleanData = rawData | parse | validate | normalize
let analysis = cleanData | analyze | aggregate | summarize
```

## Related Features

- [Functions](../functions/) - Defining functions used in pipelines
- [Error Handling](../error-handling/) - Handling errors in pipeline operations
- [Data Structures](../data-structures/) - Working with collections in pipelines

## Next Steps

- [Data Processing Pipeline Tutorial](../../tutorials/data-processing-pipeline/) - Build a complete application using piped syntax
- [Error Handling](../error-handling/) - Advanced error handling patterns 
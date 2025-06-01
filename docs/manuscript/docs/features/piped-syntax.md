---
title: "Piped Syntax"
linkTitle: "Piped Syntax"
weight: 80
description: >
  Chain function calls using pipeline syntax for data processing workflows.
---

# Piped Syntax: Your Data's Express Lane!

Tired of juggling data between functions like a circus performer? Manuscript's piped syntax is here to turn your data transformations into a smooth, elegant ballet! Instead of nested function calls or intermediate variables, you can express data transformations as a clear sequence of operations.

## What Piped Syntax Achieves

**Readability**: Your code reads like a story: 'Get the data, then transform it, then validate it.' No more deciphering nested hieroglyphics!

**Composability**: Functions become like LEGO® bricks. Snap 'em together, rearrange 'em, build something awesome!

**Maintainability**: Each step in the pipeline is isolated and testable, making debugging and modifications straightforward. (It's like having a pit crew for each segment of the race!)

**Functional Style**: Encourages writing pure functions that transform data rather than mutating state. (Keep your hands clean, let the data flow!)

## Prerequisites

- [Functions](../functions/) - Understanding function definitions and calls
- [Variables](../variables/) - Basic variable usage

## Basic Pipeline Syntax

Data flows along,
Through each function, step by step,
Clean, and oh so clear.

The pipe operator (`|`) is your friendly data courier. It takes the result from the left and dutifully delivers it as the first argument to the function on the right. First-class service! It takes the output from one expression and passes it as input to the next function in the chain.

### Example 1: Simple Data Processing

```ms
fn main() {
  // Traditional nested approach
  let result = save(validate(transform(getData())))
  
  // Piped syntax - clear data flow
  getData() | transform | validate | save // So smooth, so readable!
}
```

**What this achieves**: The piped version reads like a sentence describing the data flow: "get data, then transform it, then validate it, then save it." // Ah, much better! Reads like a recipe, doesn't it? The nested version requires reading inside-out and becomes unreadable with more operations.

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
    | format precision=2 // Each step clearly states its business.
}
```

**What this achieves**: No more playing 'guess the parameter'! Named arguments make it crystal clear what each step is doing with its newfound data. You can see exactly what each step does without looking up function signatures. The pipeline eliminates temporary variables that clutter the code.

### Example 3: Method Calls in Pipelines

```ms
fn analyzeData() {
  // Traditional object-oriented chaining
  let result = data.getEntries().filter(isValid).transform(normalize).save()
  
  // Piped syntax mixing functions and methods
  data.getEntries() 
    | filter condition=isValid 
    | processor.transform 
    | save // Functions and methods, playing nicely together in the pipe!
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
    | generateReport // If readFile cries "Error!", the whole chain stops. Sensible!
  
  return result
}
```

**What this achieves**: Even errors flow gracefully. If one step stumbles, the whole pipeline pauses, hands you the error, and says, 'Houston, we have a situation.' Error handling integrates naturally with pipelines. If any step fails, the entire pipeline stops and returns the error. This prevents the pyramid of doom you get with traditional error checking.

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
    | takeTop count=10 // From file to top 10 stats, like a well-oiled machine.
}
```

**What this achieves**: The data transformation becomes a declarative description of what you want to happen, not how to make it happen.

## How Pipelines Work

Behind the scenes, Manuscript is like a clever stage manager, efficiently handling the data flow. You get the beautiful performance, Manuscript handles the backstage hustle.

```ms
// Manuscript pipeline
data | transform | validate // You write this...
```

Becomes equivalent to:
```go
// Generated Go code (simplified)
// ... Manuscript turns it into efficient Go code like this! Sneaky.
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
- Data transformation workflows (ETL, parsing, analysis) – This is where pipes *shine*, turning data spaghetti into a clean conveyor belt.
- Sequential processing where each step depends on the previous
- Functional programming patterns
- Stream processing of collections

**Consider alternatives for:**
- Simple single-step operations
- Complex branching logic
- Operations that need multiple inputs from different sources

## Best Practices

**Keep pipelines focused**: Each pipeline should have a single, clear purpose. Don't try to make one pipeline rule them all. If it's longer than a grocery list for a family of ten, maybe split it up.
```ms
// Good: Clear purpose, like getting user input ready for storage
userInput | sanitize | validate | store

// Avoid: Trying to do everything at once (the "kitchen sink" pipeline)
// userInput | sanitize | validate | store | sendConfirmationEmail | logUserActivity | updateUserProfile | syncToCRM
// ^^^ This is a recipe for a headache!
```

**Use descriptive function names**: Pipeline steps should read like a story, not be a cryptic crossword puzzle.
```ms
// Good: Ah, a clear narrative!
customerData | parseJson | filterActiveAccounts | calculateLifetimeValue | generateLoyaltyReport

// Less clear: What dark magic is this?
data | pJson | fActive | calcLTV | genReport
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
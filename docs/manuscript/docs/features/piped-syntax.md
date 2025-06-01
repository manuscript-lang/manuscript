---
title: "Piped Syntax: Your Data's Express Lane to Awesome"
linkTitle: "Piped Syntax"
weight: 80
description: >
  Chain function calls like a pro using Manuscript's pipeline syntax. It's like a super-efficient assembly line for your data!
---

# Piped Syntax: The Magical Data Conveyor Belt!

Tired of code that looks like a Matryoshka doll of nested function calls? Enter Manuscript's **piped syntax** (`|`)! This nifty feature transforms your data processing into a beautifully readable, left-to-right conveyor belt. Instead of juggling intermediate variables or deciphering deeply nested spells, you can express complex data transformations as a clear, elegant sequence of operations. It's like watching your data glide effortlessly from one transformation station to the next.

## What This Magical Piped Syntax Achieves (Besides Looking Cool)

So, why bother with these pipes? Oh, let us count the ways!

**Readability Nirvana**: Your data's journey flows from left to right, as natural as reading a sentence (a very logical, data-transforming sentence). The sequence of operations becomes so obvious, your rubber duck might just start nodding in agreement.

**LEGO-like Composability**: Functions become like interchangeable LEGO bricks. You can easily snap them together, reorder them, or swap one out for another, all without causing your entire code castle to crumble. It's modularity at its finest!

**Maintainability Bliss**: Each step in your data pipeline is a distinct, isolated operation. This makes debugging less like finding a needle in a haystack and more like spotting a bright red elephant in a snowstorm. Modifications become straightforward, not terrifying.

**Functional Programming Street Cred**: It gently nudges you towards writing pure functions – little elves that take data, transform it, and pass it on without messing with anything else. This is a good thing, trust us. It leads to cleaner, more predictable code.

> Data flows along,
> Step by step, it changes form,
> Clean, clear, and so neat.

## Prerequisites (What You Should Know Before Hopping on the Conveyor Belt)

- [Functions](../functions/) - A solid grasp of defining and calling functions (your transformation stations).
- [Variables](../variables/) - Basic variable usage (sometimes you still need to hold onto things).

## Basic Pipeline Syntax: How the Magic Works

The pipe operator (`|`) is the star of the show. It gracefully takes the output from the expression on its left and elegantly passes it as input to the function on its right. If the function on the right needs multiple arguments, the piped value usually becomes the *first* argument, but Manuscript is clever enough to let you specify where it goes, as we'll see.

### Example 1: Simple Data Processing - The "Before and After" Makeover

Let's see how piped syntax declutters your code.

```ms
// Hypothetical functions for our data spa day
// fn getData() any { /* ... returns some raw data ... */ }
// fn transform(data any) any { /* ... processes data ... */ }
// fn validate(data any) any { /* ... checks data ... */ }
// fn save(data any) any { /* ... saves data ... */ }

fn main_simple_pipe() {
  // Traditional nested approach: Peeling the onion of doom.
  // let result = save(validate(transform(getData())))
  // print("Nested result (imagine it's useful): " + string(result))

  // Piped syntax: A clear, flowing river of data.
  // getData() | transform | validate | save
  // print("Piped result is just as useful, but prettier to write!")
}
```

**What this achieves (besides aesthetic superiority)**: The piped version reads like a story: "First, you `getData`, then you `transform` it, then `validate` its integrity, and finally, `save` it." The nested version? You have to read it from the inside out, like deciphering an ancient scroll written by a programmer who loved parentheses a bit too much.

### Example 2: Pipeline with Arguments - Telling the Stations What to Do

Functions in a pipeline often need specific instructions (arguments).

```ms
// Assume these functions exist:
// fn multiply(data []int, factor int) []int { /* ... */ }
// fn add(data []int, offset int) []int { /* ... */ }
// fn format(data []int, precision int) string { /* ... */ }

fn processNumbers_pipe_args() {
  // Traditional approach with a parade of intermediate variables:
  let numbers = [1, 2, 3, 4, 5]
  // let doubled = multiply(numbers, 2)
  // let shifted = add(doubled, 10)
  // let formatted = format(shifted, 2)
  // print("Traditional formatted: " + formatted)
  
  // Piped syntax with named arguments: So distinguished!
  // [1, 2, 3, 4, 5]
  //   | multiply factor=2  // Data becomes first arg to multiply
  //   | add offset=10      // Result of multiply becomes first arg to add
  //   | format precision=2 // Result of add becomes first arg to format
  // print("Piped formatted: " + theFinalResult) // Assuming the last step returns the string
}
```

**What this achieves (besides saving keystrokes)**: Named arguments in pipelines make the transformation's intent crystal clear. You see exactly what `factor`, `offset`, or `precision` is being used at each step without needing to peek at the function's definition. The pipeline also bids farewell to those temporary variables that just clutter up your workspace.

### Example 3: Method Calls in Pipelines - Yes, Objects Can Play Too!

Piped syntax isn't just for standalone functions; methods of objects can join the conveyor belt fun.

```ms
// Assume 'data' is an object with a method 'getEntries()'
// Assume 'isValid' is a boolean or a function usable in filter
// Assume 'processor' is an object with a method 'transform'
// fn filter(collection any, condition any) any { /* ... */ }
// fn save(data any) any { /* ... */ }

fn analyzeData_pipe_methods() {
  // Traditional object-oriented chaining (which is often quite readable itself):
  // let result = data.getEntries().filter(isValid).transform(normalize).save()
  
  // Piped syntax mixing functions and methods: The best of both worlds!
  // data.getEntries()            // Start with a method call
  //   | filter condition=isValid // Pipe its result to a standalone function
  //   | processor.transform      // Then pipe to another method
  //   | save                     // And finally, to another function
}
```

**What this achieves (flexibility!)**: Piped syntax harmonizes beautifully with both standalone functions and object methods. You're not forced into one paradigm; you can mix and match to create the most expressive and readable data flow.

### Example 4: Error Handling in Pipelines - Keeping the Conveyor Belt Safe

What happens if a station on our assembly line has a mishap? Errors integrate quite naturally.

```ms
// Assume these bang functions exist:
// fn readFile(filename string) string!
// fn parseLines(content string) []string!
// fn validateEntries(entries []string) []ValidEntry!
// fn generateReport(entries []ValidEntry) Report!

fn processFile_pipe_errors(filename string) Report! { // Notice the '!'
  // Pipeline with error handling: if any step errors, the chain stops.
  let result = try readFile(filename) 
    | parseLines 
    | validateEntries 
    | generateReport
  
  return result // This will be the report or the error from the failed step.
}
```

**What this achieves (sanity!)**: Error handling doesn't turn your code into a "pyramid of doom" (deeply nested `if err != nil` checks). If `readFile` fails, the error is caught by `try`, and `parseLines` (and subsequent steps) are never even attempted. The whole pipeline gracefully stops and returns the error.

### Example 5: Complex Data Transformation - The "Wow" Factor

Let's see a more involved example to truly appreciate the elegance.

```ms
// Assume these functions exist and do what their names suggest:
// fn readFile(filename string) string!
// fn split(content string, separator string) []string
// fn parseLogEntries(lines []string) []LogEntry! // Might fail per line or as a whole
// fn calculatePageStats(entries []LogEntry) []PageStats
// fn sortByHits(stats []PageStats) []PageStats
// fn takeTop(stats []PageStats, count int) []PageStats

fn analyzeLogFile_pipe_complex(filename string) []PageStats! {
  // Compare the traditional, more imperative approach:
  /*
  let content = try readFile(filename)
  let lines = split(content, "\n")
  let entries = []LogEntry
  for line in lines {
    let entry = try parseLogLine(line) else { continue } // Assuming parseLogLine is a helper
    if isValidEntry(entry) { // Assuming isValidEntry helper
      entries.append(entry)
    }
  }
  let stats = calculatePageStats(entries)
  let sorted = sortByHits(stats)
  return sorted[0:min(10, len(sorted))] // Manually taking top 10
  */
  
  // Now, the gloriously declarative piped approach:
  return try readFile(filename)    // Start with reading the file (could error)
    | split separator="\n"     // Split content by newlines
    | parseLogEntries          // Parse these lines into structured log entries
    | calculatePageStats       // Calculate statistics from these entries
    | sortByHits               // Sort these stats by hit count
    | takeTop count=10         // And finally, take the top 10 results
}
```

**What this achieves (declarative beauty!)**: The piped version reads like a high-level recipe for data transformation. You're describing *what* you want to happen to the data, step by step, rather than getting bogged down in the mechanics of loops, temporary variables, and manual indexing.

## How the Magic Pipes Actually Work (A Peek Behind the Curtain)

You might be wondering if this is some slow, interpretive magic. Fear not! Manuscript is clever. It transpiles these elegant pipelines into efficient Go code. While the exact Go code can be complex, conceptually, it's like creating a series of processing stages.

```ms
// Your elegant Manuscript pipeline:
// data | transform | validate
```

Conceptually becomes something like this in Go (highly simplified):
```go
// Generated Go code (very conceptual):
// proc1 := prepare_transform_function()
// proc2 := prepare_validate_function()
//
// for _, item_from_data := range data_source {
//     intermediate_result1 := proc1(item_from_data)
//     final_step_result := proc2(intermediate_result1)
//     // ... and so on ...
// }
```
This means you get the expressive power and readability of a functional, piped style, but with performance that's much closer to carefully handcrafted imperative code. It's the best of both worlds!

## When to Unleash the Power of Pipes (And When to Keep Them Tucked Away)

Piped syntax is a fantastic tool, but like any tool, it has its ideal use cases. Our seasoned factory foreman advises:

**Perfect for situations like:**
- **Data Transformation Workflows:** Think ETL (Extract, Transform, Load), parsing complex data formats, log analysis, data cleansing. If your data needs to go on a multi-step journey of refinement, pipes are your best friend.
- **Sequential Processing:** When each step clearly and logically follows the previous one, transforming the data bit by bit.
- **Embracing Functional Programming:** If you love breaking problems down into small, pure, composable functions, pipes will feel like coming home.
- **Stream Processing of Collections:** When you're mapping, filtering, reducing, or otherwise processing items in a list or stream.

**Consider alternatives (or use pipes sparingly) for:**
- **Super Simple Single-Step Operations:** If you're just calling one function, `data | doOneThing` isn't much clearer than `doOneThing(data)`. Don't overcomplicate for the sake of pipes!
- **Complex Branching Logic:** If your data flow involves lots of `if-else` conditions that dramatically change the path of data, traditional control flow structures might be clearer than trying to force everything into a single pipeline.
- **Operations Needing Multiple, Unrelated Inputs:** Pipes are primarily designed for a linear flow where one function's output becomes the next's input. If a function needs three completely separate pieces of data that don't flow from one to the other, pipes aren't the natural fit for that specific call.

## Foreman's Best Practices for Smooth-Running Data Assembly Lines

A few tips to keep your pipelines efficient, readable, and a joy to work with.

**Keep Pipelines Focused**: Each pipeline should have a single, clear purpose, like a well-defined assembly line. Don't try to build a car and bake a cake on the same line.

```ms
// Good: This pipeline clearly focuses on user input processing.
// userInput | sanitize | validate | storeUserRecord

// Avoid: This pipeline is trying to do too many unrelated things.
// userInput | sanitize | validate | storeUserRecord | sendWelcomeEmail | logLoginActivity | scheduleFollowUpCall
// Consider breaking the latter tasks into separate processes or pipelines.
```

**Use Descriptive Function Names**: The steps in your pipeline should read like a well-written story or a clear set of instructions.

```ms
// Good: So clear, it's practically self-documenting.
// csvData | parseRowsFromCSV | filterOutInvalidRecords | calculateMonthlyTotals | generateSalesReport

// Less clear: What arcane rituals are these?
// csvData | parse | filt | calc | genRep
```

**Break Up Marathon Pipelines**: If your pipeline starts looking longer than a grocery list for a family of twelve, consider splitting it into smaller, logical sub-pipelines. Assign intermediate results to variables if it improves clarity.

```ms
// Good: Breaking a long process into logical chunks.
// let cleanedAndNormalizedData = rawData | parseRawInput | validateEntries | normalizeTextCasing
// let analyticalResults = cleanedAndNormalizedData | performStatisticalAnalysis | aggregateResults | summarizeKeyFindings
```

## Related Spells and Scrolls

- [Functions](../functions/) - The individual transformation stations (functions) you'll be piping data through.
- [Error Handling](../error-handling/) - Essential for when a station on your assembly line encounters a hiccup.
- [Data Structures](../data-structures/) - Understanding the collections (arrays, maps, etc.) you'll often be processing in pipelines.

## Your Next Adventure in Piping

- [Data Processing Pipeline Tutorial](../../tutorials/data-processing-pipeline/) - Ready to get your hands dirty? Build a complete application using piped syntax. This is where the theory meets glorious practice!
- [Error Handling](../error-handling/) - Dive deeper into advanced error handling patterns, which are crucial for robust pipelines.

---
title: "Manuscript in Action: A Showcase of Examples"
linkTitle: "Examples"

description: >
  Behold! Practical code examples demonstrating Manuscript's nifty features and best-kept secrets (well, not so secret anymore).
---

Welcome to the Manuscript Example Arena! This is where the rubber meets the road, the code meets the compiler, and abstract concepts transform into tangible results. We've gathered a collection of practical examples to show you how Manuscript can be wielded effectively. All these spells, err, examples are tested and itching to be run.

> Code snippets gleam,
> Ideas take their solid form,
> Learning lights the way.

## Quick Peeks: Bite-Sized Brilliance

Need a quick taste of Manuscript? These tiny titans pack a punch.

### Hello World
The timeless classic, Manuscript style.
```ms
fn main() {
  print("Hello, Manuscript!")
}
```

### Variables and Types
A brief reminder of how Manuscript handles data.
```ms
fn main() {
  let name = "Alice"
  let age = 30
  let score = 95.5
  let active = true
  
  print("User: ${name}, Age: ${age}, Score: ${score}, Active: ${active}")
}
```

### Functions
Crafting reusable blocks of code.
```ms
fn greet(name string, enthusiastic bool = false) string {
  let punctuation = enthusiastic ? "!" : "."
  return "Hello, ${name}${punctuation}"
}

fn main() {
  print(greet("World"))
  print(greet("Manuscript", true))
}
```

### Error Handling
Because sometimes, things go delightfully sideways.
```ms
fn divide(a float, b float) float! {
  if b == 0.0 {
    return error("Division by zero, a bold move!")
  }
  return a / b
}

fn main() {
  let result = try divide(10.0, 2.0)
  print("Result: ${result}")
  
  let safe = try divide(10.0, 0.0) else 0.0 // Gracefully handling the void
  print("Safe result: ${safe}")
}
```

## Example Categories: Choose Your Adventure

Navigate through our curated collections of coded wonders.

### [Basic Examples](basic/)
The building blocks! These examples illuminate fundamental language features and common patterns that you'll use every day:

- **Variables and Types** - Getting cozy with how Manuscript stores and categorizes data.
- **Functions** - The art of defining and using reusable code spells.
- **Control Flow** - Directing the currents of your program with conditions and loops.
- **Collections** - Juggling arrays, objects, maps, and sets like a pro.
- **String Processing** - Twisting and turning text to your will.

### [Applications](applications/)
Behold! More substantial creations, showcasing Manuscript in real-world(ish) scenarios:

- **CLI Tools** - Forging command-line utilities and nifty scripts.
- **Web Services** - Spinning up HTTP servers and API endpoints with flair.
- **Data Processing** - Parsing files and transforming data as if by magic.
- **Utilities** - Crafting helper functions and common algorithms for your toolkit.

## Featured Productions: Our Star Performers

Some examples just love the spotlight. Here are a few more elaborate pieces.

### Configuration Parser
A rather practical demonstration of parsing configuration files. Because who likes hardcoded settings?

```ms
import { readFile } from 'os'
import { split, trim } from 'strings'

type Config {
  host string
  port int
  debug bool
  features []string
}

fn parseConfig(filename string) Config! {
  let content = try readFile(filename)
  let config = Config{
    host: "localhost"
    port: 8080
    debug: false
    features: []
  }
  
  let lines = split(content, "\n")
  for line in lines {
    let cleaned = trim(line)
    if cleaned == "" || startsWith(cleaned, "#") {
      continue  // Politely ignore empty lines and wise comments
    }
    
    let parts = split(cleaned, "=")
    if len(parts) != 2 {
      continue  // Skip lines that don't play by the rules
    }
    
    let key = trim(parts[0])
    let value = trim(parts[1])
    
    match key {
      "host": config.host = value
      "port": config.port = parseInt(value) // Convert text to a proper number
      "debug": config.debug = value == "true" // Boolean conversion
      "features": config.features = split(value, ",") // A list of cool things
    }
  }
  
  return config
}

fn main() {
  let config = try parseConfig("app.conf") else {
    print("Oh no! Error loading config: ${error}")
    return
  }
  
  print("Server will run on: ${config.host}:${config.port}")
  print("Debug mode activated: ${config.debug}")
  print("Enabled features: ${join(config.features, ", ")}")
}
```

### Simple HTTP Server
Witness Manuscript's ability to serve web content. It's simpler than you might think!

```ms
import { http } from 'net'
import { json } from 'encoding'

type User {
  id int
  name string
  email string
}

// Our prestigious, in-memory user database
let users = []User{
  User{id: 1, name: "Alice", email: "alice@example.com"}
  User{id: 2, name: "Bob", email: "bob@example.com"}
}

fn handleUsers(req http.Request) http.Response! {
  match req.method {
    "GET": {
      let body = try json.marshal(users) // Convert our users to JSON
      return http.Response{
        status: 200
        headers: {"Content-Type": "application/json"}
        body: body
      }
    }
    "POST": {
      let user = try json.unmarshal(req.body, User) // Welcome a new user from JSON
      user.id = len(users) + 1 // Assign a shiny new ID
      users.append(user)
      
      let body = try json.marshal(user)
      return http.Response{
        status: 201 // Created!
        headers: {"Content-Type": "application/json"}
        body: body
      }
    }
    default: {
      return http.Response{ // For methods we don't support
        status: 405
        body: "Method Not Allowed (Perhaps try GET or POST?)"
      }
    }
  }
}

fn main() {
  let server = http.Server{port: 8080}
  
  server.handle("/users", handleUsers)
  server.handle("/health", fn(req) { // A quick health check endpoint
    return http.Response{status: 200, body: "OK, feeling groovy!"}
  })
  
  print("Server starting on port 8080... Go visit in your browser!")
  try server.listen()
}
```

### Data Processing Pipeline
An example of transforming data with the rather elegant piped syntax. It's like an assembly line for your data.

```ms
import { readFile, writeFile } from 'os'
import { split, trim, join } from 'strings'
import { parseFloat } from 'strconv'

type Sale {
  date string
  product string
  amount float
  customer string
}

// Turns a line of text into a structured Sale, or complains if it can't
fn parseLine(line string, index int) Sale! {
  if index == 0 || trim(line) == "" { // Skip headers or empty lines
    return error("Skip header or empty line")
  }
  
  let fields = split(line, ",")
  if len(fields) != 4 {
    return error("Invalid format at line ${index + 1}. Tut tut.")
  }
  
  let amount = try parseFloat(trim(fields[2])) // Text to number, carefully
  
  return Sale{
    date: trim(fields[0])
    product: trim(fields[1])
    amount: amount
    customer: trim(fields[3])
  }
}

// Only interested in sales that actually made money
fn filterValidSales(sale Sale) bool {
  return sale.amount > 0
}

// Crunch some numbers: total sales, and totals per product/customer
fn calculateTotals(sales []Sale) (float, [:]float, [:]float) {
  let totalSales = 0.0
  let productTotals = [:]float // A map to store product totals
  let customerTotals = [:]float // And one for customer totals
  
  for sale in sales {
    totalSales += sale.amount
    productTotals[sale.product] = productTotals[sale.product] + sale.amount
    customerTotals[sale.customer] = customerTotals[sale.customer] + sale.amount
  }
  
  return totalSales, productTotals, customerTotals
}

// Make the report look presentable
fn formatReport(totalSales float, sales []Sale, productTotals [:]float) string {
  let report = []string{
    "Super Awesome Sales Report"
    "=========================="
    ""
    "Total Sales: $${totalSales}"
    "Number of Transactions: ${len(sales)}"
    "Average Sale Value: $${totalSales / float(len(sales))}" // Watch for division by zero if sales is empty!
    ""
    "Top Products by Revenue:"
  }
  
  // This part could be enhanced to sort products by total, for a true "Top Products" list!
  for product, total in productTotals {
    report.append("  ${product}: $${total}")
  }
  
  return join(report, "\n")
}

fn main() {
  // The traditional, step-by-step way
  let content = try readFile("sales.csv") else {
    print("Error reading sales data: ${error}")
    return
  }
  
  let lines = split(content, "\n")
  let sales = []Sale
  
  for i, line in lines {
    let sale = try parseLine(line, i) else { continue } // Skip if parsing fails
    if filterValidSales(sale) {
      sales.append(sale)
    }
  }
  
  let totalSales, productTotals, customerTotals = calculateTotals(sales)
  let report = formatReport(totalSales, sales, productTotals)
  
  // Now, let's admire the elegance of a pipeline for the same job!
  // This assumes each function in the pipeline is designed to accept
  // the output of the previous one. Not fully shown here for brevity,
  // but imagine functions like `read`, `parseLines`, `filterSales`, etc.
  fn processWithPipelineConceptual() {
    // readFile("sales.csv")
    //   | splitLines
    //   | parseSalesLines
    //   | filterValidSalesData
    //   | calculateSalesTotals
    //   | formatSalesReport
    //   | writeFile filename="report_piped.txt"
    print("Piped version would be cool, eh? (Conceptual for now)")
  }
  
  try writeFile("report.txt", report) else {
    print("Error writing lovely report: ${error}")
    return
  }
  
  print("Report generated: report.txt")
  print("Processed ${len(sales)} valid sales records. High five!")
}
```

## How to Wield These Examples

Ready to dive in? Here’s how to get these examples running and bend them to your will.

### Running Examples Like a Boss

1.  **Liberate the code:** Copy it into a file ending with `.ms` (e.g., `my_precious_example.ms`).
2.  **Dependencies?** If the example `import`s anything, you might need to ensure those modules are available. (For standard library modules, you're usually good to go!)
3.  **Compile and Unleash**:
    ```bash
    msc example.ms # This compiles and runs your Manuscript masterpiece
    ```

### Tinkering and Tailoring

Don't just run the examples – make them your own!

- **Parameter Power:** Change input values and function arguments to see how the behavior morphs.
- **Fortify with Error Handling:** What if things go wrong? Add more checks for edge cases.
- **Feature Creep (The Good Kind):** Extend the functionality. What else could this example do?
- **Franken-Code:** Combine bits and pieces from different examples to build something new and exciting!

### Fueling Your Examples (Test Data)

Many examples hunger for data. You might need to create sample files:

```bash
# For the configuration parser example
echo "host=api.coolexample.com
port=3000
debug=true
features=auth,logging,awesomeness" > app.conf

# For the sales data processing example
echo "Date,Product,Amount,Customer
2024-01-01,Shiny Widget A,29.99,John Doe
2024-01-02,Robust Gadget B,45.50,Jane Smith
2024-01-03,Shiny Widget A,29.99,Bob Johnson" > sales.csv
```

## Your Learning Quest (Suggested Path)

Embark on this learning journey, one example at a time.

1.  **Begin with the Basics:** Start with [Basic Examples](basic/) to solidify your grasp of core concepts.
2.  **Study the Applications:** Move to [Applications](applications/) to see how these concepts assemble into larger structures.
3.  **Become a Mad Scientist:** Modify the examples. Break them. Fix them. Learn their secrets.
4.  **Forge Your Own Path:** Create your own original applications. Solve a problem you care about!
5.  **Share Your Wisdom:** Consider contributing your examples back to the community.

## Got Examples? Share the Sparkle!

We enthusiastically welcome contributions to our example hoard! A truly great example:

- **Solves a real (or realistically fake) problem:** It should address common use cases.
- **Is well-documented:** Clear explanations are like signposts in a friendly forest.
- **Follows best practices:** Show off good Manuscript style and conventions.
- **Includes test data:** If it needs input, provide a sample so others can play along.

Our [Contributing Guide](https://github.com/manuscript-lang/manuscript/blob/main/CONTRIBUTING.md) has all the nitty-gritty details.

{{% alert title="The Joy of Tinkering" %}}
Reading about code is one thing, but running it, tweaking it, and watching it react is where the real learning party's at. So go ahead, copy, paste, and experiment away!
{{% /alert %}}

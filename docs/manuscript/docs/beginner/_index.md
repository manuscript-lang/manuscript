---
title: "Your Epic Quest into Manuscript!"
linkTitle: "Beginner"
description: >
  Embark on a joyous journey to learn the magical arts of Manuscript programming. Perfect for aspiring code wizards and seasoned sorcerers new to Manuscript!
---
Greetings, brave adventurer! Welcome to the Beginner's Guide to Manuscript, where you'll uncover the secrets to programming like a pro (or at least a very enthusiastic amateur). Whether you've never typed a line of code or you're a veteran from other mystical coding lands, these scrolls will equip you with a rock-solid foundation.

## What Arcane Knowledge Awaits?

By the time you conquer this section, you'll be able to:

- **Variables and Types** - Wrangle data like a digital zookeeper! Learn to name your creatures (variables) and understand their species (types).
- **Functions** - Craft your own reusable spells! Why chant the same incantation repeatedly when you can bottle it up in a function?
- **Control Flow** - Become the master of your program's destiny! Make it do your bidding with decisions and nifty loops.
- **Data Structures** - Organize your loot! Learn to manage collections of treasures (data) efficiently.

> Code flows, new worlds,
> Bugs may try to cause you strife,
> You will crush them all.

## Your Legendary Learning Path

Follow these ancient maps in order for the most enlightening (and least confusing) experience:

### 1. [Variables and Types](variables-and-types/)
Uncover the secrets of naming things and telling Manuscript what kind of *thing* it is. It's like labeling your potions, but way less smelly.

```ms
let name = "Alice"        // string (basically, fancy text)
let age = 25             // int (a whole number, no fractions!)
let height = 5.6         // float (for when numbers get decimal-ly)
let active = true        // bool (is it ON or OFF? TRUE or FALSE?)
```

### 2. [Functions](functions/)
Become a master of code reuse! Define your own spells (functions), tell them what ingredients (parameters) they need, what they conjure (return values), and even how to politely cough if something goes wrong (basic error handling).

```ms
fn greet(name string) {
  print("Salutations, " + name + "!") // A friendly greeting spell
}

fn add(a int, b int) int {
  return a + b // The ancient art of addition
}
```

### 3. [Control Flow](control-flow/)
Learn to boss your program around! Make it choose paths with conditions, or do things over and over with loops until it gets them right.

```ms
if age >= 18 {
  print("Huzzah! An adult!")
} else {
  print("A promising young squire!")
}

for i = 1; i <= 10; i++ {
  print(i) // Let's count to ten, shall we?
}
```

### 4. [Basic Data Structures](data-structures/)
Got lots of stuff? Learn to store it neatly in magical containers like arrays and objects. No more stuffing everything under your digital bed.

```ms
let numbers = [1, 2, 3, 4, 5]    // A neat row of numbers
let person = {                   // Info about a legendary hero
  name: "Alice"
  age: 30
}
```

## Before You Embark: Gather Your Gear!

Make sure you've got these items in your adventurer's kit:

- ✅ [Installed Manuscript](../getting-started/installation/) (The sacred runes and compiler)
- ✅ [Written your first program](../getting-started/first-program/) (Your first successful incantation!)
- ✅ [Read the language overview](../getting-started/overview/) (Scouted the terrain ahead)

## Pro Gamer Moves for Learning

### Practice Like a Bard Learning a New Tune
Each section has example spells you can cast. Tinker with them! Change the ingredients and see if you can make them do something even cooler (or explode spectacularly – that’s learning too!).

```ms
// Try changing these values and see what happens!
let greeting = "Greetings"
let name = "Adventurer"
print(greeting + ", " + name + "!")
```

### Experiment Like a Daring Alchemist
Don't be shy! Mix potions, I mean, write small programs to test your brilliant theories. The worst that can happen is a puff of digital smoke.

```ms
fn main() {
  // Your secret laboratory for code experiments!
  let x = 10
  let y = 20
  print("Behold, the sum: " + string(x + y))
}
```

### Build Something Real (Even if it's a Digital Mud Hut at First)
After each chapter of your training, try building a small, wondrous contraption using your newfound knowledge.

## Code Examples: Certified Fresh!

All spells and incantations in this guide are tested and guaranteed to work (unless your cat walks on the keyboard). You can copy and cast them directly:

```bash
# Save your spell to test.ms
echo 'fn main() {
  let message = "Mastering Manuscript, one spell at a time!"
  print(message)
}' > test.ms

# Unleash its power!
msc test.ms
```

## Stuck in Quicksand? (Getting Help)

If you find yourself wrestling with a particularly stubborn gremlin (or bug):

1.  **Consult the Spellbook** - Each concept has working code examples. Are yours similar?
2.  **Poke It With a Stick (Experiment)** - Try small changes to see what makes the gremlin tick.
3.  **Send a Carrier Pigeon (Ask Questions)** - Use the mystical [GitHub Discussions](https://github.com/manuscript-lang/manuscript/discussions) to seek aid from fellow sorcerers.
4.  **Read Ahead (Sometimes the Future Holds the Key)** - Occasionally, later scrolls illuminate earlier mysteries.

## What's Next on Your Quest?

After you've mastered the beginner's grimoire:

- **[Intermediate Guide](../intermediate/)** - Learn even more potent magic and complex enchantments!
- **[Tutorials](../tutorials/)** - Forge legendary artifacts (real applications)!
- **[Examples](../examples/)** - Gaze upon the works of other master mages!

## Quick Reference Scroll

A handy cheat-sheet for when your memory gets a bit foggy.

### Variables
```ms
let name = "value"           // Declare with a treasure
let count int = 42          // Explicitly state the treasure's nature
let x, y = 10, 20          // Two treasures, one stone!
```

### Functions
```ms
fn functionName(param type) returnType {
  // The heart of your spell
  return value // What your spell conjures
}
```

### Control Flow
```ms
if condition {
  // If this path is true...
} else {
  // Otherwise, this path...
}

for init; condition; update {
  // Repeat until destiny is fulfilled!
}
```

### Collections
```ms
let array = [1, 2, 3]      // A treasure chest of items in order
let object = {key: "value"} // A map to your named treasures
```

Ready to become a Manuscript Mage? Your journey starts with [Variables and Types](variables-and-types/)!

{{% alert title="Slow and Steady Wins the Race (Even Against Digital Tortoises)" %}}
Learning to code is like leveling up in your favorite RPG. It takes practice and patience. Don't try to speedrun the tutorial – make sure you truly understand each spell before enchanting the next.
{{% /alert %}}

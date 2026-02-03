// @test: Method Override Errors - inherited types cannot change method signatures
// @error: different parameters

// === Base type with method ===
type Animal extends Context
  name: string
  fn speak(volume: number): string
    "..."

// === Wrong: changing parameter types ===
type BadDog extends Animal
  fn speak(volume: string): string
    "woof"

// NOTE: Additional error cases that can be tested separately:
// - Changing return type: fn speak(volume: number): number
// - Changing using clause: fn speak(volume: number): string using (x: SomeContext)
// - Changing parameter count: fn speak(): string

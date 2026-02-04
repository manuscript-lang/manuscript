// Benchmark: Class vs Shared Null-Prototype Factory
// Run with: bun bench-prototype.js && node bench-prototype.js

const ITERATIONS = 1_000_000;

// ============================================
// Approach 1: Traditional JS Classes (current)
// ============================================
class AnimalClass {
  constructor(name, sound) {
    this.name = name;
    this.sound = sound;
  }
  speak() { return this.sound; }
  move() { return "moving"; }
}

class DogClass extends AnimalClass {
  constructor(name, sound, breed) {
    super(name, sound);
    this.breed = breed;
  }
  bark() { return "woof!"; }
}

// ============================================
// Approach 2: Shared Null-Prototype (proposed)
// ============================================
const Animal$methods = Object.assign(Object.create(null), {
  speak() { return this.sound; },
  move() { return "moving"; },
});

function AnimalFactory(name, sound) {
  const self = Object.create(Animal$methods);
  self.name = name;
  self.sound = sound;
  return self;
}

const Dog$methods = Object.assign(Object.create(null), {
  bark() { return "woof!"; },
});

function DogFactory(animal, breed) {
  const self = Object.create(Dog$methods);
  self.Animal = animal;
  self.breed = breed;
  return self;
}

// ============================================
// Approach 3: Object.create(null) each time (slow)
// ============================================
function DogFactorySlow(name, sound, breed) {
  const self = Object.create(null);
  self.name = name;
  self.sound = sound;
  self.breed = breed;
  self.speak = function() { return this.sound; };
  self.bark = function() { return "woof!"; };
  return self;
}

// ============================================
// Benchmarks
// ============================================

function bench(name, fn) {
  // Warmup
  for (let i = 0; i < 10000; i++) fn();
  
  const start = performance.now();
  for (let i = 0; i < ITERATIONS; i++) {
    fn();
  }
  const elapsed = performance.now() - start;
  const opsPerSec = Math.round(ITERATIONS / (elapsed / 1000));
  console.log(`${name}: ${elapsed.toFixed(2)}ms (${(opsPerSec / 1_000_000).toFixed(2)}M ops/sec)`);
  return elapsed;
}

console.log(`\n=== Prototype Pattern Benchmark (${ITERATIONS.toLocaleString()} iterations) ===`);
console.log(`Runtime: ${typeof Bun !== 'undefined' ? 'Bun' : 'Node.js'}\n`);

console.log("--- Object Creation ---");
const classTime = bench("Class (new DogClass)", () => new DogClass("Rex", "bark", "Lab"));
const factoryTime = bench("Factory (shared null-proto)", () => DogFactory(AnimalFactory("Rex", "bark"), "Lab"));
const slowTime = bench("Factory (null each time)", () => DogFactorySlow("Rex", "bark", "Lab"));

console.log("\n--- Method Calls (on pre-created instances) ---");
const classInstance = new DogClass("Rex", "bark", "Lab");
const factoryInstance = DogFactory(AnimalFactory("Rex", "bark"), "Lab");

bench("Class method call", () => classInstance.speak() + classInstance.bark());
bench("Factory method call", () => factoryInstance.Animal.speak() + factoryInstance.bark());

console.log("\n--- Property Access ---");
bench("Class property", () => classInstance.name + classInstance.breed);
bench("Factory property", () => factoryInstance.Animal.name + factoryInstance.breed);

console.log("\n--- Summary ---");
const ratio = factoryTime / classTime;
if (ratio < 1.5) {
  console.log(`✓ Shared null-proto is ${ratio < 1 ? 'FASTER' : 'within 50%'} of classes (${ratio.toFixed(2)}x)`);
} else {
  console.log(`⚠ Shared null-proto is ${ratio.toFixed(2)}x slower than classes`);
}

const slowRatio = slowTime / factoryTime;
console.log(`✓ Shared proto is ${slowRatio.toFixed(2)}x faster than per-instance null-proto`);

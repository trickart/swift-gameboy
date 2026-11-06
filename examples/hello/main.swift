import GameBoy

// Sample showing that core Swift features (structs, classes, generics, arrays,
// optionals, ...) run on the Game Boy.

struct Vec2 { var x: Int; var y: Int }

final class Counter {
  private(set) var value = 0
  func increment() { value += 1 }
}

protocol Shape { func area() -> Int }
struct Square: Shape { let side: Int; func area() -> Int { side * side } }
struct Rect: Shape { let w: Int, h: Int; func area() -> Int { w * h } }

func totalArea<S: Shape>(_ shapes: [S]) -> Int {
  var total = 0
  for s in shapes { total += s.area() }
  return total
}

Console.initialize()

print("Hello, Game Boy!")
print("Swift 6 on SM83")
print("")

let v = Vec2(x: 3, y: 4)
Console.write("Vec2: "); Console.write(v.x); Console.write(","); Console.write(v.y); print("")

let squares = [Square(side: 2), Square(side: 3)]
Console.write("Squares: "); print(totalArea(squares))
Console.write("Rect: "); print(Rect(w: 5, h: 6).area())

let numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
let evens = numbers.filter { $0 % 2 == 0 }.map { $0 * $0 }
Console.write("Sum sq even: "); print(evens.reduce(0, +))

let maybe: Int? = numbers.first { $0 > 7 }
if let m = maybe { Console.write("First >7: "); print(m) }

Console.write("Heap free: "); print(Memory.heapFree)
print("")

let counter = Counter()
while true {
  Display.waitVBlank()
  counter.increment()
  if counter.value % 60 == 0 {
    Console.write("tick "); print(counter.value / 60)
  }
}

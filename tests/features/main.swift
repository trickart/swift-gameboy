import GameBoy
enum Shape { case circle(r: Int); case rect(w: Int, h: Int) }
func area(_ s: Shape) -> Int { switch s { case .circle(let r): return 3 * r * r; case .rect(let w, let h): return w * h } }
enum MyError: Error { case tooBig(Int) }
func check(_ v: Int) throws(MyError) -> Int { if v > 100 { throw .tooBig(v) }; return v * 2 }
protocol Animal: AnyObject { func legs() -> Int }
final class Dog: Animal { func legs() -> Int { 4 } }
final class Bird: Animal { func legs() -> Int { 2 } }
struct Stack<T> { var items: [T] = []; mutating func push(_ x: T) { items.append(x) }; mutating func pop() -> T? { items.popLast() } }
Console.initialize()
print(area(.circle(r: 2)) + area(.rect(w: 3, h: 4)))
do { print(try check(21)); print(try check(200)) } catch { if case .tooBig(let v) = error { print(v) } }
let animals: [any Animal] = [Dog(), Bird()]
print(animals.reduce(0) { $0 + $1.legs() })
var st = Stack<UInt8>(); st.push(7); st.push(9); print(st.pop() ?? 0)
print([5, 2, 9, 1].sorted()[0])
print(Int64(1) << 40)
let f: Float = 1.5; print(Int(f * 10))
while true { Display.waitVBlank() }

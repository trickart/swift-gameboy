/// 16-bit xorshift random number generator
public enum Random {
  static var state: UInt16 = 0xACE1

  /// Seeds the generator, e.g. from the DIV register
  public static func seed(_ s: UInt16) { state = s == 0 ? 0xACE1 : s }

  public static func next() -> UInt16 {
    var x = state
    x ^= x &<< 7
    x ^= x &>> 9
    x ^= x &<< 8
    state = x
    return x
  }

  /// Returns a value in 0..<n
  public static func next(below n: UInt16) -> UInt16 {
    n == 0 ? 0 : next() % n
  }
}

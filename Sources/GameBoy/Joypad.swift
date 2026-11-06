/// Joypad input
public struct Joypad: OptionSet {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }

  public static let a = Joypad(rawValue: 0x01)
  public static let b = Joypad(rawValue: 0x02)
  public static let select = Joypad(rawValue: 0x04)
  public static let start = Joypad(rawValue: 0x08)
  public static let right = Joypad(rawValue: 0x10)
  public static let left = Joypad(rawValue: 0x20)
  public static let up = Joypad(rawValue: 0x40)
  public static let down = Joypad(rawValue: 0x80)

  /// Reads the current input from the hardware
  public static func read() -> Joypad {
    HW.joyp = 0x20                         // select the direction keys
    var v = HW.joyp
    v = HW.joyp
    var result = UInt8(~v & 0x0F) << 4
    HW.joyp = 0x10                         // select the buttons
    v = HW.joyp
    v = HW.joyp
    v = HW.joyp
    result |= ~v & 0x0F
    HW.joyp = 0x30                         // deselect both
    return Joypad(rawValue: result)
  }

  static var current = Joypad()
  static var previous = Joypad()

  /// Call once per frame to update the button state
  public static func poll() {
    previous = current
    current = read()
  }
  /// Buttons currently held down
  public static var held: Joypad { current }
  /// Buttons newly pressed since the previous poll
  public static var pressed: Joypad { Joypad(rawValue: current.rawValue & ~previous.rawValue) }
  /// Buttons released since the previous poll
  public static var released: Joypad { Joypad(rawValue: previous.rawValue & ~current.rawValue) }
}

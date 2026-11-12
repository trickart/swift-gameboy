/// A Game Boy Color color: 15-bit RGB with 5 bits per channel
public struct Color {
  /// 0b0BBBBBGGGGGRRRRR, the format of the palette registers
  public let rawValue: UInt16
  public init(rawValue: UInt16) { self.rawValue = rawValue }

  /// Each channel is 0...31
  public init(red: UInt8, green: UInt8, blue: UInt8) {
    rawValue = UInt16(red & 31) | UInt16(green & 31) << 5 | UInt16(blue & 31) << 10
  }

  /// From a 24-bit 0xRRGGBB value (the low 3 bits of each channel are dropped)
  public init(rgb: UInt32) {
    self.init(red: UInt8(truncatingIfNeeded: rgb >> 19), green: UInt8(truncatingIfNeeded: rgb >> 11),
              blue: UInt8(truncatingIfNeeded: rgb >> 3))
  }

  public static let white = Color(rawValue: 0x7FFF)
  public static let black = Color(rawValue: 0x0000)
}

/// Game Boy Color palettes. They only take effect on a Game Boy Color running a ROM built with `gb-rom --color`;
/// the original Game Boy ignores them and keeps using `backgroundPalette` / `spritePalette0` / `spritePalette1`.
/// Set them while the LCD is off or during VBlank (palette memory cannot be written while the PPU is drawing).
extension Display {
  /// Sets the four colors of background palette `palette` (0-7). Tiles use palette 0 unless the attribute map says otherwise
  public static func setBackgroundColors(_ colors: [Color], palette: Int = 0) {
    HW.bcps = 0x80 | UInt8(truncatingIfNeeded: palette & 7) << 3   // auto-increment from color 0
    for color in colors.prefix(4) {
      HW.bcpd = UInt8(truncatingIfNeeded: color.rawValue)
      HW.bcpd = UInt8(truncatingIfNeeded: color.rawValue >> 8)
    }
  }

  /// Sets the four colors of sprite palette `palette` (0-7). Color 0 is transparent
  public static func setSpriteColors(_ colors: [Color], palette: Int = 0) {
    HW.ocps = 0x80 | UInt8(truncatingIfNeeded: palette & 7) << 3
    for color in colors.prefix(4) {
      HW.ocpd = UInt8(truncatingIfNeeded: color.rawValue)
      HW.ocpd = UInt8(truncatingIfNeeded: color.rawValue >> 8)
    }
  }
}

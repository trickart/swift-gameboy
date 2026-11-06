/// Minimal sound support (square-wave beep on channel 1)
public enum Sound {
  public static func enable() {
    HW.nr52 = 0x80
    HW.nr50 = 0x77
    HW.nr51 = 0xFF
  }

  /// Plays a short beep at the given frequency register value (0-2047). Larger values are higher pitched
  public static func beep(frequency: UInt16, length: UInt8 = 0x20, volume: UInt8 = 0xF) {
    HW.nr10 = 0x00
    HW.nr11 = 0x80 | (0x3F - (length & 0x3F))
    HW.nr12 = (volume & 0x0F) << 4 | 0x03
    HW.nr13 = UInt8(truncatingIfNeeded: frequency)
    HW.nr14 = 0xC0 | UInt8(truncatingIfNeeded: frequency >> 8) & 0x07
  }
}

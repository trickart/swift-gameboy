/// Sprites (OAM). Writes go to the shadow OAM (WRAM 0xC000-0xC09F) and `flush()` DMA-transfers them
public enum Sprites {
  public static let count = 40

  public struct Attributes: OptionSet {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let palette1 = Attributes(rawValue: 0x10)
    public static let flipX = Attributes(rawValue: 0x20)
    public static let flipY = Attributes(rawValue: 0x40)
    public static let behindBackground = Attributes(rawValue: 0x80)
  }

  static var shadow: UnsafeMutablePointer<UInt8> { UnsafeMutablePointer(bitPattern: HW.oamShadowBase)! }

  /// Places sprite i at screen coordinates (x, y). Use negative x/y to hide it off-screen
  public static func set(_ index: Int, x: Int, y: Int, tile: UInt8, attributes: Attributes = []) {
    let p = shadow + index * 4
    p[0] = UInt8(truncatingIfNeeded: y + 16)
    p[1] = UInt8(truncatingIfNeeded: x + 8)
    p[2] = tile
    p[3] = attributes.rawValue
  }

  public static func hide(_ index: Int) {
    (shadow + index * 4).pointee = 0
  }

  public static func hideAll() {
    let p = shadow
    for i in 0..<(count * 4) { p[i] = 0 }
  }

  /// DMA-transfers the shadow OAM into OAM. Must be called during VBlank
  public static func flush() {
    gb_oam_dma(UInt8(truncatingIfNeeded: HW.oamShadowBase >> 8))
  }
}

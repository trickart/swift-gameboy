/// LCD / VRAM operations
public enum Display {
  public static let width = 160
  public static let height = 144
  public static let tilesPerRow = 20
  public static let tilesPerColumn = 18

  /// Bits of the LCDC register
  public struct Options: OptionSet {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let backgroundOn = Options(rawValue: 0x01)
    public static let spritesOn = Options(rawValue: 0x02)
    public static let spriteSize8x16 = Options(rawValue: 0x04)
    public static let backgroundMap1 = Options(rawValue: 0x08)   // use 0x9C00
    public static let tileData8000 = Options(rawValue: 0x10)     // treat tile numbers as unsigned
    public static let windowOn = Options(rawValue: 0x20)
    public static let windowMap1 = Options(rawValue: 0x40)
    public static let lcdOn = Options(rawValue: 0x80)
  }

  public static var isOn: Bool { HW.lcdc & 0x80 != 0 }

  /// Waits for the start of the next VBlank (busy loop)
  public static func waitVBlank() {
    while HW.ly >= 144 {}
    while HW.ly < 144 {}
  }

  /// Turns the LCD off safely (it may only be turned off during VBlank). While it is off, VRAM/OAM can be accessed freely
  public static func turnOff() {
    if isOn {
      waitVBlank()
      HW.lcdc &= 0x7F
    }
  }

  public static func turnOn() { HW.lcdc |= 0x80 }

  public static func configure(_ options: Options) { HW.lcdc = options.rawValue }

  /// Waits until VRAM is accessible (any mode other than mode 3).
  /// Caution: if too much time passes between returning and the VRAM write, the PPU may enter mode 3 and the write is dropped.
  /// To write single bytes reliably, use `writeVRAM` (`gb_vram_write` in C)
  @inline(__always)
  public static func waitVRAMAccess() {
    while HW.stat & 0x03 == 3 {}
  }

  /// Background palette (4 colors x 2 bits; default 0xE4 = color 0 is the lightest)
  public static var backgroundPalette: UInt8 { get { HW.bgp } set { HW.bgp = newValue } }
  public static var spritePalette0: UInt8 { get { HW.obp0 } set { HW.obp0 = newValue } }
  public static var spritePalette1: UInt8 { get { HW.obp1 } set { HW.obp1 = newValue } }
  public static var scrollX: UInt8 { get { HW.scx } set { HW.scx = newValue } }
  public static var scrollY: UInt8 { get { HW.scy } set { HW.scy = newValue } }

  /// Writes one byte to VRAM. While the LCD is on, it waits for HBlank/VBlank first (gb_vram_write in C;
  /// waiting in Swift and then writing can be too slow: the PPU enters mode 3 and the write is dropped)
  @inline(__always)
  public static func writeVRAM(_ p: UnsafeMutablePointer<UInt8>, _ value: UInt8, lcdOn: Bool) {
    if lcdOn { gb_vram_write(p, value) } else { p.pointee = value }
  }

  /// Loads 2bpp tile data (16 bytes per tile)
  public static func loadTiles(_ data: UnsafeBufferPointer<UInt8>, startingAt index: Int) {
    guard let src = data.baseAddress, !data.isEmpty else { return }
    gb_vram_copy(HW.tileData + index * 16, src, UInt16(truncatingIfNeeded: data.count))
  }

  public static func loadTiles(_ data: [UInt8], startingAt index: Int) {
    data.withUnsafeBufferPointer { loadTiles($0, startingAt: index) }
  }

  /// Loads 1bpp tile data (8 bytes per tile), expanding it to 2bpp. Set pixels become color 3
  public static func loadTiles1bpp(_ data: UnsafeBufferPointer<UInt8>, startingAt index: Int) {
    guard let src = data.baseAddress, !data.isEmpty else { return }
    gb_vram_copy_1bpp(HW.tileData + index * 16, src, UInt16(truncatingIfNeeded: data.count))
  }

  /// Fills tiles with zero
  public static func clearTiles(from index: Int, count: Int) {
    gb_vram_fill(HW.tileData + index * 16, 0, UInt16(truncatingIfNeeded: count * 16))
  }

  /// Writes a tile number into one cell of the background tile map (32x32)
  public static func setBackgroundTile(x: Int, y: Int, _ tile: UInt8, map: UnsafeMutablePointer<UInt8> = HW.bgMap0) {
    writeVRAM(map + ((y & 31) << 5 | (x & 31)), tile, lcdOn: isOn)
  }

  /// Fills the whole background tile map (32x32) with a single tile
  public static func fillBackground(_ tile: UInt8, map: UnsafeMutablePointer<UInt8> = HW.bgMap0) {
    gb_vram_fill(map, tile, 1024)
  }
}

/// Waits n frames
public func delayFrames(_ n: Int) {
  for _ in 0..<n { Display.waitVBlank() }
}

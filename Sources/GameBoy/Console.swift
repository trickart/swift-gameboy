/// Text console drawn on the background tile map (20 columns x 18 rows).
/// `print` output (`putchar`) is routed here as well.
public enum Console {
  static var cursorX = 0
  static var cursorY = 0       // Row on screen (0-17)
  static var topRow = 0        // Tile-map row shown at the top of the screen (0-31)
  static var ready = false

  /// Initializes the LCD, loads the font and clears the screen
  public static func initialize() {
    Display.turnOff()
    Display.clearTiles(from: 0, count: 32)
    Font.bitmap.withUTF8Buffer { Display.loadTiles1bpp($0, startingAt: Int(Font.firstCharacter)) }
    Display.fillBackground(0)
    HW.scx = 0
    HW.scy = 0
    HW.bgp = 0xE4
    cursorX = 0
    cursorY = 0
    topRow = 0
    ready = true
    Display.configure([.lcdOn, .backgroundOn, .tileData8000])
  }

  /// Clears the screen and moves the cursor to the top-left corner
  public static func clear() {
    Display.fillBackground(0)
    cursorX = 0
    cursorY = 0
  }

  public static func setCursor(x: Int, y: Int) {
    cursorX = x
    cursorY = y
  }

  @inline(__always)
  static func mapRow(_ screenRow: Int) -> Int { (topRow + screenRow) & 31 }

  static func newline() {
    cursorX = 0
    cursorY += 1
    if cursorY >= Display.tilesPerColumn {
      // Hardware scroll: advance SCY by one row and clear the new bottom row
      topRow = (topRow + 1) & 31
      HW.scy = UInt8(truncatingIfNeeded: topRow * 8)
      cursorY = Display.tilesPerColumn - 1
      gb_vram_fill(HW.bgMap0 + (mapRow(cursorY) << 5), 0, 32)
    }
  }

  /// Writes one ASCII character. '\n' is a newline. The byte is also sent to the serial port
  public static func put(_ c: UInt8) {
    Serial.write(c)
    if !ready { initialize() }
    if c == 0x0A { newline(); return }
    if c == 0x0D { cursorX = 0; return }
    var tile = c
    if c < Font.firstCharacter || c > Font.lastCharacter { tile = 0x3F } // '?'
    if cursorX >= Display.tilesPerRow { newline() }
    let p = HW.bgMap0 + (mapRow(cursorY) << 5 | cursorX)
    Display.writeVRAM(p, tile, lcdOn: Display.isOn)
    cursorX += 1
  }

  public static func write(_ s: StaticString) {
    s.withUTF8Buffer { for b in $0 { put(b) } }
  }

  public static func write(_ value: some BinaryInteger) {
    print(value, terminator: "")
  }

  /// Writes a string at the given position (the cursor is not moved)
  public static func write(_ s: StaticString, x: Int, y: Int) {
    let savedX = cursorX, savedY = cursorY
    cursorX = x
    cursorY = y
    write(s)
    cursorX = savedX
    cursorY = savedY
  }
}

/// Serial port output (useful for emulator logs or debug output over the link cable)
public enum Serial {
  public static func write(_ byte: UInt8) {
    HW.sb = byte
    HW.sc = 0x81
  }
}

/// putchar called by Embedded Swift's `print`
@_cdecl("putchar")
public func putchar(_ c: Int16) -> Int16 {
  Console.put(UInt8(truncatingIfNeeded: c))
  return c
}

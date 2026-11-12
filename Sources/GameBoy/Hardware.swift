import _Volatile

/// Volatile access to memory-mapped I/O
@inline(__always)
func _reg(_ address: UInt) -> VolatileMappedRegister<UInt8> {
  VolatileMappedRegister<UInt8>(unsafeBitPattern: address)
}

/// Game Boy hardware registers and memory regions
public enum HW {
  @inline(__always) public static func read(_ address: UInt) -> UInt8 { _reg(address).load() }
  @inline(__always) public static func write(_ address: UInt, _ value: UInt8) { _reg(address).store(value) }

  // --- Joypad / serial / timer ---
  public static var joyp: UInt8 { get { read(0xFF00) } set { write(0xFF00, newValue) } }
  public static var sb: UInt8 { get { read(0xFF01) } set { write(0xFF01, newValue) } }
  public static var sc: UInt8 { get { read(0xFF02) } set { write(0xFF02, newValue) } }
  public static var div: UInt8 { get { read(0xFF04) } set { write(0xFF04, newValue) } }
  public static var tima: UInt8 { get { read(0xFF05) } set { write(0xFF05, newValue) } }
  public static var tma: UInt8 { get { read(0xFF06) } set { write(0xFF06, newValue) } }
  public static var tac: UInt8 { get { read(0xFF07) } set { write(0xFF07, newValue) } }
  public static var interruptFlag: UInt8 { get { read(0xFF0F) } set { write(0xFF0F, newValue) } }
  public static var interruptEnable: UInt8 { get { read(0xFFFF) } set { write(0xFFFF, newValue) } }

  // --- LCD ---
  public static var lcdc: UInt8 { get { read(0xFF40) } set { write(0xFF40, newValue) } }
  public static var stat: UInt8 { get { read(0xFF41) } set { write(0xFF41, newValue) } }
  public static var scy: UInt8 { get { read(0xFF42) } set { write(0xFF42, newValue) } }
  public static var scx: UInt8 { get { read(0xFF43) } set { write(0xFF43, newValue) } }
  public static var ly: UInt8 { read(0xFF44) }
  public static var lyc: UInt8 { get { read(0xFF45) } set { write(0xFF45, newValue) } }
  public static var dma: UInt8 { get { read(0xFF46) } set { write(0xFF46, newValue) } }
  public static var bgp: UInt8 { get { read(0xFF47) } set { write(0xFF47, newValue) } }
  public static var obp0: UInt8 { get { read(0xFF48) } set { write(0xFF48, newValue) } }
  public static var obp1: UInt8 { get { read(0xFF49) } set { write(0xFF49, newValue) } }
  public static var wy: UInt8 { get { read(0xFF4A) } set { write(0xFF4A, newValue) } }
  public static var wx: UInt8 { get { read(0xFF4B) } set { write(0xFF4B, newValue) } }

  // --- Game Boy Color palettes ---
  public static var bcps: UInt8 { get { read(0xFF68) } set { write(0xFF68, newValue) } }
  public static var bcpd: UInt8 { get { read(0xFF69) } set { write(0xFF69, newValue) } }
  public static var ocps: UInt8 { get { read(0xFF6A) } set { write(0xFF6A, newValue) } }
  public static var ocpd: UInt8 { get { read(0xFF6B) } set { write(0xFF6B, newValue) } }

  // --- Sound (bare minimum) ---
  public static var nr10: UInt8 { get { read(0xFF10) } set { write(0xFF10, newValue) } }
  public static var nr11: UInt8 { get { read(0xFF11) } set { write(0xFF11, newValue) } }
  public static var nr12: UInt8 { get { read(0xFF12) } set { write(0xFF12, newValue) } }
  public static var nr13: UInt8 { get { read(0xFF13) } set { write(0xFF13, newValue) } }
  public static var nr14: UInt8 { get { read(0xFF14) } set { write(0xFF14, newValue) } }
  public static var nr50: UInt8 { get { read(0xFF24) } set { write(0xFF24, newValue) } }
  public static var nr51: UInt8 { get { read(0xFF25) } set { write(0xFF25, newValue) } }
  public static var nr52: UInt8 { get { read(0xFF26) } set { write(0xFF26, newValue) } }

  // --- Memory regions ---
  public static let vramBase: UInt = 0x8000
  public static let tileDataBase: UInt = 0x8000      // tiles 0-383 (16 bytes/tile)
  public static let bgMap0Base: UInt = 0x9800        // 32x32 tile map
  public static let bgMap1Base: UInt = 0x9C00
  public static let oamBase: UInt = 0xFE00
  public static let oamShadowBase: UInt = 0xC000     // reserved by the linker script (gb.ld)

  public static var vram: UnsafeMutablePointer<UInt8> { UnsafeMutablePointer(bitPattern: vramBase)! }
  public static var tileData: UnsafeMutablePointer<UInt8> { UnsafeMutablePointer(bitPattern: tileDataBase)! }
  public static var bgMap0: UnsafeMutablePointer<UInt8> { UnsafeMutablePointer(bitPattern: bgMap0Base)! }
  public static var bgMap1: UnsafeMutablePointer<UInt8> { UnsafeMutablePointer(bitPattern: bgMap1Base)! }
  public static var oam: UnsafeMutablePointer<UInt8> { UnsafeMutablePointer(bitPattern: oamBase)! }
}

// C functions provided by crt0.s / runtime.c
@_extern(c, "gb_ei") func gb_ei()
@_extern(c, "gb_di") func gb_di()
@_extern(c, "gb_halt") func gb_halt()
@_extern(c, "gb_oam_dma") func gb_oam_dma(_ sourcePage: UInt8)
@_extern(c, "gb_heap_free") func gb_heap_free() -> UInt
@_extern(c, "gb_vram_write") func gb_vram_write(_ p: UnsafeMutablePointer<UInt8>, _ value: UInt8)
@_extern(c, "gb_vram_fill") func gb_vram_fill(_ p: UnsafeMutablePointer<UInt8>, _ value: UInt8, _ count: UInt16)
@_extern(c, "gb_vram_copy") func gb_vram_copy(_ p: UnsafeMutablePointer<UInt8>, _ src: UnsafePointer<UInt8>, _ count: UInt16)
@_extern(c, "gb_vram_copy_1bpp") func gb_vram_copy_1bpp(_ p: UnsafeMutablePointer<UInt8>, _ src: UnsafePointer<UInt8>, _ count: UInt16)

/// Interrupts
public struct Interrupt: OptionSet {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }
  public static let vblank = Interrupt(rawValue: 0x01)
  public static let stat = Interrupt(rawValue: 0x02)
  public static let timer = Interrupt(rawValue: 0x04)
  public static let serial = Interrupt(rawValue: 0x08)
  public static let joypad = Interrupt(rawValue: 0x10)
}

public enum Interrupts {
  /// Enables the given interrupts (IE register). Handlers are defined on the Swift side as
  /// `@_cdecl("gb_vblank_handler") func ...()` (likewise for stat/timer/serial/joypad)
  public static func enable(_ set: Interrupt) {
    HW.interruptFlag = 0
    HW.interruptEnable |= set.rawValue
    gb_ei()
  }
  public static func disable(_ set: Interrupt) { HW.interruptEnable &= ~set.rawValue }
  /// Sets IME (ei)
  public static func enableGlobal() { gb_ei() }
  /// Clears IME (di)
  public static func disableGlobal() { gb_di() }
  /// Stops the CPU until the next interrupt (halt). Useful as a low-power VBlank wait
  public static func halt() { gb_halt() }
}

public enum Memory {
  /// Number of free heap bytes (for debugging)
  public static var heapFree: UInt { gb_heap_free() }
}

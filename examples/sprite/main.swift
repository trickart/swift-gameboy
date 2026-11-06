import GameBoy

// Sample that moves a sprite with the D-pad. A beeps, START resets the position.

final class Player {
  var x = 76
  var y = 68
  var frame = 0

  func update(_ input: Joypad) {
    if input.contains(.left) && x > 0 { x -= 1 }
    if input.contains(.right) && x < Display.width - 8 { x += 1 }
    if input.contains(.up) && y > 0 { y -= 1 }
    if input.contains(.down) && y < Display.height - 8 { y += 1 }
    frame &+= 1
  }

  func draw() {
    // Animate by alternating between two tiles every 8 frames
    let tile: UInt8 = (frame & 8) == 0 ? 0x80 : 0x81
    Sprites.set(0, x: x, y: y, tile: tile)
  }
}

// 2bpp sprite tiles (two frames of a round character)
let playerTiles: [UInt8] = [
  0x3C, 0x3C, 0x7E, 0x42, 0xFF, 0x99, 0xFF, 0x81, 0xFF, 0xA5, 0xFF, 0x99, 0x7E, 0x42, 0x3C, 0x3C,
  0x3C, 0x3C, 0x7E, 0x42, 0xFF, 0x99, 0xFF, 0x81, 0xFF, 0x81, 0xFF, 0xBD, 0x7E, 0x42, 0x3C, 0x3C,
]

Console.initialize()
Display.turnOff()
Display.loadTiles(playerTiles, startingAt: 0x80)
Sprites.hideAll()
Display.spritePalette0 = 0xE4
Display.configure([.lcdOn, .backgroundOn, .spritesOn, .tileData8000])
Sound.enable()

Console.write("D-PAD: move", x: 0, y: 0)
Console.write("A:beep START:reset", x: 0, y: 1)

let player = Player()
var beeps = 0

while true {
  Joypad.poll()
  player.update(Joypad.held)
  if Joypad.pressed.contains(.a) {
    Sound.beep(frequency: 1750)
    beeps += 1
    Console.setCursor(x: 0, y: 17)
    Console.write("beeps: "); Console.write(beeps); Console.write("   ")
  }
  if Joypad.pressed.contains(.start) {
    player.x = 76
    player.y = 68
  }
  Display.waitVBlank()
  player.draw()
  Sprites.flush()
}

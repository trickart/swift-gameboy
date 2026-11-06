#!/usr/bin/env python3
"""Generate Font.swift for the GameBoy module from the 5x7 dot-font definitions below.

Each glyph occupies columns 1-5 and rows 0-6 of an 8x8 tile. The largest possible row byte is 0x7C (< 0x80),
so each row fits in one byte of a StaticString's UTF-8 representation as-is and the font ends up as a constant in ROM.
"""
import sys

GLYPHS = {
' ': "     /     /     /     /     /     /     ",
'!': "  #  /  #  /  #  /  #  /  #  /     /  #  ",
'"': " # # / # # / # # /     /     /     /     ",
'#': " # # / # # /#####/ # # /#####/ # # / # # ",
'$': "  #  / ####/# #  / ### /  # #/#### /  #  ",
'%': "##   /##  #/   # /  #  / #   /#  ##/   ##",
'&': " ##  /#  # /# #  / #   /# # #/#  # / ## #",
"'": " ##  /  #  / #   /     /     /     /     ",
'(': "   # /  #  / #   / #   / #   /  #  /   # ",
')': " #   /  #  /   # /   # /   # /  #  / #   ",
'*': "     /  #  /# # #/ ### /# # #/  #  /     ",
'+': "     /  #  /  #  /#####/  #  /  #  /     ",
',': "     /     /     /     / ##  /  #  / #   ",
'-': "     /     /     /#####/     /     /     ",
'.': "     /     /     /     /     / ##  / ##  ",
'/': "     /    #/   # /  #  / #   /#    /     ",
'0': " ### /#   #/#  ##/# # #/##  #/#   #/ ### ",
'1': "  #  / ##  /  #  /  #  /  #  /  #  / ### ",
'2': " ### /#   #/    #/   # /  #  / #   /#####",
'3': "#####/   # /  #  /   # /    #/#   #/ ### ",
'4': "   # /  ## / # # /#  # /#####/   # /   # ",
'5': "#####/#    /#### /    #/    #/#   #/ ### ",
'6': "  ## / #   /#    /#### /#   #/#   #/ ### ",
'7': "#####/    #/   # /  #  / #   / #   / #   ",
'8': " ### /#   #/#   #/ ### /#   #/#   #/ ### ",
'9': " ### /#   #/#   #/ ####/    #/   # / ##  ",
':': "     / ##  / ##  /     / ##  / ##  /     ",
';': "     / ##  / ##  /     / ##  /  #  / #   ",
'<': "   # /  #  / #   /#    / #   /  #  /   # ",
'=': "     /     /#####/     /#####/     /     ",
'>': " #   /  #  /   # /    #/   # /  #  / #   ",
'?': " ### /#   #/    #/   # /  #  /     /  #  ",
'@': " ### /#   #/    #/ ## #/# # #/# # #/ ### ",
'A': " ### /#   #/#   #/#####/#   #/#   #/#   #",
'B': "#### /#   #/#   #/#### /#   #/#   #/#### ",
'C': " ### /#   #/#    /#    /#    /#   #/ ### ",
'D': "###  /#  # /#   #/#   #/#   #/#  # /###  ",
'E': "#####/#    /#    /#### /#    /#    /#####",
'F': "#####/#    /#    /#### /#    /#    /#    ",
'G': " ### /#   #/#    /# ###/#   #/#   #/ ####",
'H': "#   #/#   #/#   #/#####/#   #/#   #/#   #",
'I': " ### /  #  /  #  /  #  /  #  /  #  / ### ",
'J': "  ###/   # /   # /   # /   # /#  # / ##  ",
'K': "#   #/#  # /# #  /##   /# #  /#  # /#   #",
'L': "#    /#    /#    /#    /#    /#    /#####",
'M': "#   #/## ##/# # #/# # #/#   #/#   #/#   #",
'N': "#   #/#   #/##  #/# # #/#  ##/#   #/#   #",
'O': " ### /#   #/#   #/#   #/#   #/#   #/ ### ",
'P': "#### /#   #/#   #/#### /#    /#    /#    ",
'Q': " ### /#   #/#   #/#   #/# # #/#  # / ## #",
'R': "#### /#   #/#   #/#### /# #  /#  # /#   #",
'S': " ####/#    /#    / ### /    #/    #/#### ",
'T': "#####/  #  /  #  /  #  /  #  /  #  /  #  ",
'U': "#   #/#   #/#   #/#   #/#   #/#   #/ ### ",
'V': "#   #/#   #/#   #/#   #/#   #/ # # /  #  ",
'W': "#   #/#   #/#   #/# # #/# # #/# # #/ # # ",
'X': "#   #/#   #/ # # /  #  / # # /#   #/#   #",
'Y': "#   #/#   #/#   #/ # # /  #  /  #  /  #  ",
'Z': "#####/    #/   # /  #  / #   /#    /#####",
'[': " ### / #   / #   / #   / #   / #   / ### ",
'\\': "     /#    / #   /  #  /   # /    #/     ",
']': " ### /   # /   # /   # /   # /   # / ### ",
'^': "  #  / # # /#   #/     /     /     /     ",
'_': "     /     /     /     /     /     /#####",
'`': " #   /  #  /   # /     /     /     /     ",
'a': "     /     / ####/    #/ ####/#   #/ ####",
'b': "#    /#    /# ## /##  #/#   #/##  #/# ## ",
'c': "     /     / ### /#   #/#    /#   #/ ### ",
'd': "    #/    #/ ## #/#  ##/#   #/#  ##/ ## #",
'e': "     /     / ### /#   #/#####/#    / ### ",
'f': "  ## / #  #/ #   /###  / #   / #   / #   ",
'g': "     / ####/#   #/#   #/ ####/    #/ ### ",
'h': "#    /#    /# ## /##  #/#   #/#   #/#   #",
'i': "  #  /     / ##  /  #  /  #  /  #  / ### ",
'j': "   # /     /  ## /   # /   # /#  # / ##  ",
'k': "#    /#    /#  # /# #  /##   /# #  /#  # ",
'l': " ##  /  #  /  #  /  #  /  #  /  #  / ### ",
'm': "     /     /## # /# # #/# # #/#   #/#   #",
'n': "     /     /# ## /##  #/#   #/#   #/#   #",
'o': "     /     / ### /#   #/#   #/#   #/ ### ",
'p': "     /     /#### /#   #/#### /#    /#    ",
'q': "     /     / ####/#   #/ ####/    #/    #",
'r': "     /     /# ## /##  #/#    /#    /#    ",
's': "     /     / ####/#    / ### /    #/#### ",
't': " #   / #   /###  / #   / #   / #  #/  ## ",
'u': "     /     /#   #/#   #/#   #/#  ##/ ## #",
'v': "     /     /#   #/#   #/#   #/ # # /  #  ",
'w': "     /     /#   #/#   #/# # #/# # #/ # # ",
'x': "     /     /#   #/ # # /  #  / # # /#   #",
'y': "     /     /#   #/#   #/ ####/    #/ ### ",
'z': "     /     /#####/   # /  #  / #   /#####",
'{': "  ## / #   / #   /##   / #   / #   /  ## ",
'|': "  #  /  #  /  #  /  #  /  #  /  #  /  #  ",
'}': "##   /  #  /  #  /   ##/  #  /  #  /##   ",
'~': "     /     / #   /# # #/   # /     /     ",
}


def glyph_bytes(ch: str) -> list:
    rows = GLYPHS[ch].split('/')
    assert len(rows) == 7, ch
    out = []
    for r in rows:
        assert len(r) == 5, (ch, r)
        v = 0
        for i, c in enumerate(r):
            if c == '#':
                v |= 1 << (6 - i)
        out.append(v)
    out.append(0)
    return out


def main():
    out_path = sys.argv[1]
    data = []
    for code in range(0x20, 0x7F):
        data.extend(glyph_bytes(chr(code)))
    assert all(b < 0x80 for b in data)
    # StaticString cannot be concatenated with +, so emit all bytes in one multi-line literal (a trailing \ suppresses the newline)
    lines = []
    for code in range(0x20, 0x7F):
        chunk = data[(code - 0x20) * 8:(code - 0x20) * 8 + 8]
        lines.append('    ' + ''.join(f'\\u{{{b:02X}}}' for b in chunk) + '\\')
    lines[-1] = lines[-1][:-1]  # the last line must not end with a trailing \
    body = '\n'.join(lines)
    with open(out_path, 'w') as f:
        f.write(f'''// Generated by tools/genfont.py. Do not edit by hand.
//
// 5x7 dot font for ASCII 0x20-0x7E (1bpp, 8 bytes per character, {len(data)} bytes total).
// Every byte is below 0x80, so it maps 1:1 onto the UTF-8 representation of a StaticString and is placed as a ROM constant.
// One line per character (8 bytes); the first line is 0x20 (space), the rest follow in ASCII order.

public enum Font {{
  /// 8 bytes per character (1 byte per row; bits 6-2 are columns 1-5; the last row is blank)
  public static let bytesPerGlyph = 8
  public static let firstCharacter: UInt8 = 0x20
  public static let lastCharacter: UInt8 = 0x7E
  public static let glyphCount = {len(data) // 8}
  public static let bitmap: StaticString = """
{body}
    """
}}
''')
    print(f'{out_path}: {len(data)} bytes, {len(data)//8} glyphs')


if __name__ == '__main__':
    main()

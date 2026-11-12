#!/usr/bin/env python3
"""Minimal Game Boy (DMG) emulator bundled with swift-gameboy (python3 tools/sm83emu.py rom.gb --ascii). Headless, intended for tests.

- Full SM83 CPU instruction set, interrupts, timer, serial port (output is captured), OAM DMA
- The PPU renders BG / window / sprites per scanline (timing is simplified)
- Game Boy Color: only the color palettes (for ROMs with the CGB flag; tile attributes always use palette 0 / bank 0)
- Writes the screen as PNG / ASCII art after running the requested number of frames
- `--press` feeds button input at the given frames
- Detects the infinite loop at an RST vector (a Swift trap) and stops

Usage:
  sm83emu.py game.gb --frames 60 --screenshot out.png [--ascii] [--press 10:RIGHT+A,30:]
"""
import argparse
import collections
import struct
import sys
import zlib

FZ, FN, FH, FC = 0x80, 0x40, 0x20, 0x10

# Cycle counts of the base instructions (T-cycles, branch not taken)
CYCLES = [
    4, 12, 8, 8, 4, 4, 8, 4, 20, 8, 8, 8, 4, 4, 8, 4,
    4, 12, 8, 8, 4, 4, 8, 4, 12, 8, 8, 8, 4, 4, 8, 4,
    8, 12, 8, 8, 4, 4, 8, 4, 8, 8, 8, 8, 4, 4, 8, 4,
    8, 12, 8, 8, 12, 12, 12, 4, 8, 8, 8, 8, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    8, 8, 8, 8, 8, 8, 4, 8, 4, 4, 4, 4, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    8, 12, 12, 16, 12, 16, 8, 16, 8, 16, 12, 4, 12, 24, 8, 16,
    8, 12, 12, 0, 12, 16, 8, 16, 8, 16, 12, 0, 12, 0, 8, 16,
    12, 12, 8, 0, 0, 16, 8, 16, 16, 4, 16, 0, 0, 0, 8, 16,
    12, 12, 8, 4, 0, 16, 8, 16, 12, 8, 16, 4, 0, 0, 8, 16,
]

BUTTONS = {'A': 0x01, 'B': 0x02, 'SELECT': 0x04, 'START': 0x08,
           'RIGHT': 0x10, 'LEFT': 0x20, 'UP': 0x40, 'DOWN': 0x80}

PALETTE = [(155, 188, 15), (139, 172, 15), (48, 98, 48), (15, 56, 15)]


class TrapError(Exception):
    pass


class GameBoy:
    def __init__(self, rom: bytes):
        self.rom = bytes(rom) + b'\xff' * max(0, 0x8000 - len(rom))
        self.mem = bytearray(0x10000)
        self.mem[:0x8000] = self.rom[:0x8000]
        self.a = 0x01; self.f = 0xB0; self.b = 0x00; self.c = 0x13
        self.d = 0x00; self.e = 0xD8; self.h = 0x01; self.l = 0x4D
        self.sp = 0xFFFE; self.pc = 0x0100
        self.ime = False; self.ei_pending = False; self.halted = False
        self.cycles = 0
        # I/O
        io = self.mem
        io[0xFF00] = 0xCF; io[0xFF40] = 0x91; io[0xFF41] = 0x85; io[0xFF47] = 0xFC
        io[0xFF48] = 0xFF; io[0xFF49] = 0xFF; io[0xFF0F] = 0xE1; io[0xFF02] = 0x7E
        self.div_counter = 0; self.tima_counter = 0
        self.ppu_clock = 0; self.ly = 0; self.window_line = 0; self.frame = 0
        self.mode = 2
        self.dropped_vram_writes = 0   # number of VRAM/OAM writes dropped during mode 3 (mode 2/3 for OAM) while the LCD was on
        self.fb = bytearray(160 * 144)
        # Game Boy Color palettes (ROMs with the CGB flag): 8 BG palettes followed by 8 sprite palettes,
        # 4 colors x 2 bytes each. fb_pal holds the palette-memory offset of every pixel
        self.cgb = bool(self.rom[0x143] & 0x80)
        self.cgb_pal = bytearray(b'\xff\x7f' * 32 + bytes(64))
        self.fb_pal = bytearray(160 * 144)
        if self.cgb:
            self.a = 0x11
        self.serial_log = bytearray()
        self.buttons = 0  # bit set of currently pressed buttons (see BUTTONS)
        self.trap_pc = None
        self.history = collections.deque(maxlen=64)  # recently executed PCs
        self.finished = False  # main returned and execution entered crt0's halt loop

    # ---------------------------------------------------------------- memory
    def rd(self, addr):
        addr &= 0xFFFF
        if addr < 0x8000:
            return self.rom[addr]
        if 0xA000 <= addr < 0xC000:
            return 0xFF
        if 0xE000 <= addr < 0xFE00:
            return self.mem[addr - 0x2000]
        if addr == 0xFF00:
            p1 = self.mem[0xFF00]
            v = 0xCF | (p1 & 0x30)
            if not (p1 & 0x10):
                v &= ~((self.buttons >> 4) & 0x0F) & 0xFF
            if not (p1 & 0x20):
                v &= ~(self.buttons & 0x0F) & 0xFF
            return v
        if addr == 0xFF44:
            return self.ly
        if self.mem[0xFF40] & 0x80:
            if 0x8000 <= addr < 0xA000 and self.mode == 3:
                return 0xFF
            if 0xFE00 <= addr < 0xFEA0 and self.mode >= 2:
                return 0xFF
        if addr == 0xFF41:
            stat = (self.mem[0xFF41] & 0x78) | 0x80 | self.mode
            if self.ly == self.mem[0xFF45]:
                stat |= 0x04
            return stat
        return self.mem[addr]

    def wr(self, addr, val):
        addr &= 0xFFFF; val &= 0xFF
        if addr < 0x8000:
            return  # ROM ONLY (no MBC)
        if 0xA000 <= addr < 0xC000:
            return
        if 0xE000 <= addr < 0xFE00:
            self.mem[addr - 0x2000] = val; return
        if self.mem[0xFF40] & 0x80:
            # As on real hardware, writes to VRAM (mode 3) / OAM (modes 2, 3) are dropped while the PPU is using them
            if 0x8000 <= addr < 0xA000 and self.mode == 3:
                self.dropped_vram_writes += 1; return
            if 0xFE00 <= addr < 0xFEA0 and self.mode >= 2:
                self.dropped_vram_writes += 1; return
        if addr == 0xFF02:
            self.mem[addr] = val
            if val & 0x80:
                self.serial_log.append(self.mem[0xFF01])
                self.mem[0xFF01] = 0xFF
                self.mem[0xFF02] = val & 0x7F
                self.mem[0xFF0F] |= 0x08
            return
        if addr == 0xFF04:
            self.div_counter = 0; self.mem[addr] = 0; return
        if addr in (0xFF69, 0xFF6B) and self.cgb:
            spec = self.mem[addr - 1]
            self.cgb_pal[(64 if addr == 0xFF6B else 0) + (spec & 0x3F)] = val
            if spec & 0x80:  # auto-increment
                self.mem[addr - 1] = 0x80 | ((spec + 1) & 0x3F)
            return
        if addr == 0xFF44:
            return
        if addr == 0xFF46:
            src = val << 8
            for i in range(0xA0):
                self.mem[0xFE00 + i] = self.rd(src + i)
            self.mem[addr] = val
            return
        if addr == 0xFF40:
            if not (val & 0x80) and (self.mem[0xFF40] & 0x80):
                self.ly = 0; self.ppu_clock = 0; self.mode = 0
            self.mem[addr] = val
            return
        self.mem[addr] = val

    def rd16(self, addr):
        return self.rd(addr) | (self.rd(addr + 1) << 8)

    def wr16(self, addr, val):
        self.wr(addr, val & 0xFF); self.wr(addr + 1, val >> 8)

    def fetch(self):
        v = self.rd(self.pc); self.pc = (self.pc + 1) & 0xFFFF; return v

    def fetch16(self):
        v = self.rd16(self.pc); self.pc = (self.pc + 2) & 0xFFFF; return v

    def push(self, v):
        self.sp = (self.sp - 2) & 0xFFFF; self.wr16(self.sp, v)

    def pop(self):
        v = self.rd16(self.sp); self.sp = (self.sp + 2) & 0xFFFF; return v

    # -------------------------------------------------------------- regs
    def get_r(self, i):
        if i == 0: return self.b
        if i == 1: return self.c
        if i == 2: return self.d
        if i == 3: return self.e
        if i == 4: return self.h
        if i == 5: return self.l
        if i == 6: return self.rd((self.h << 8) | self.l)
        return self.a

    def set_r(self, i, v):
        v &= 0xFF
        if i == 0: self.b = v
        elif i == 1: self.c = v
        elif i == 2: self.d = v
        elif i == 3: self.e = v
        elif i == 4: self.h = v
        elif i == 5: self.l = v
        elif i == 6: self.wr((self.h << 8) | self.l, v)
        else: self.a = v

    def get_rr(self, i):
        if i == 0: return (self.b << 8) | self.c
        if i == 1: return (self.d << 8) | self.e
        if i == 2: return (self.h << 8) | self.l
        return self.sp

    def set_rr(self, i, v):
        v &= 0xFFFF
        if i == 0: self.b, self.c = v >> 8, v & 0xFF
        elif i == 1: self.d, self.e = v >> 8, v & 0xFF
        elif i == 2: self.h, self.l = v >> 8, v & 0xFF
        else: self.sp = v

    def cond(self, cc):
        if cc == 0: return not (self.f & FZ)
        if cc == 1: return bool(self.f & FZ)
        if cc == 2: return not (self.f & FC)
        return bool(self.f & FC)

    # -------------------------------------------------------------- ALU
    def alu(self, op, v):
        a = self.a
        if op == 0:  # ADD
            r = a + v
            self.f = (FZ if (r & 0xFF) == 0 else 0) | (FH if ((a & 0xF) + (v & 0xF)) > 0xF else 0) | (FC if r > 0xFF else 0)
            self.a = r & 0xFF
        elif op == 1:  # ADC
            c = 1 if self.f & FC else 0
            r = a + v + c
            self.f = (FZ if (r & 0xFF) == 0 else 0) | (FH if ((a & 0xF) + (v & 0xF) + c) > 0xF else 0) | (FC if r > 0xFF else 0)
            self.a = r & 0xFF
        elif op == 2:  # SUB
            r = a - v
            self.f = FN | (FZ if (r & 0xFF) == 0 else 0) | (FH if (a & 0xF) < (v & 0xF) else 0) | (FC if r < 0 else 0)
            self.a = r & 0xFF
        elif op == 3:  # SBC
            c = 1 if self.f & FC else 0
            r = a - v - c
            self.f = FN | (FZ if (r & 0xFF) == 0 else 0) | (FH if (a & 0xF) < (v & 0xF) + c else 0) | (FC if r < 0 else 0)
            self.a = r & 0xFF
        elif op == 4:  # AND
            self.a = a & v; self.f = FH | (FZ if self.a == 0 else 0)
        elif op == 5:  # XOR
            self.a = a ^ v; self.f = FZ if self.a == 0 else 0
        elif op == 6:  # OR
            self.a = a | v; self.f = FZ if self.a == 0 else 0
        else:  # CP
            r = a - v
            self.f = FN | (FZ if (r & 0xFF) == 0 else 0) | (FH if (a & 0xF) < (v & 0xF) else 0) | (FC if r < 0 else 0)

    def inc8(self, v):
        r = (v + 1) & 0xFF
        self.f = (self.f & FC) | (FZ if r == 0 else 0) | (FH if (v & 0xF) == 0xF else 0)
        return r

    def dec8(self, v):
        r = (v - 1) & 0xFF
        self.f = (self.f & FC) | FN | (FZ if r == 0 else 0) | (FH if (v & 0xF) == 0 else 0)
        return r

    def add_hl(self, v):
        hl = (self.h << 8) | self.l
        r = hl + v
        self.f = (self.f & FZ) | (FH if ((hl & 0xFFF) + (v & 0xFFF)) > 0xFFF else 0) | (FC if r > 0xFFFF else 0)
        self.h, self.l = (r >> 8) & 0xFF, r & 0xFF

    def sp_offset(self):
        e = self.fetch()
        if e > 127: e -= 256
        r = (self.sp + e) & 0xFFFF
        self.f = (FH if ((self.sp & 0xF) + (e & 0xF)) > 0xF else 0) | (FC if ((self.sp & 0xFF) + (e & 0xFF)) > 0xFF else 0)
        return r

    # CB-prefixed instructions
    def cb(self):
        op = self.fetch()
        r = op & 7; kind = op >> 6; bit = (op >> 3) & 7
        v = self.get_r(r)
        if kind == 0:
            c = 1 if self.f & FC else 0
            if bit == 0: res = ((v << 1) | (v >> 7)) & 0xFF; carry = v >> 7
            elif bit == 1: res = ((v >> 1) | (v << 7)) & 0xFF; carry = v & 1
            elif bit == 2: res = ((v << 1) | c) & 0xFF; carry = v >> 7
            elif bit == 3: res = ((v >> 1) | (c << 7)) & 0xFF; carry = v & 1
            elif bit == 4: res = (v << 1) & 0xFF; carry = v >> 7
            elif bit == 5: res = (v >> 1) | (v & 0x80); carry = v & 1
            elif bit == 6: res = ((v << 4) | (v >> 4)) & 0xFF; carry = 0
            else: res = v >> 1; carry = v & 1
            self.f = (FZ if res == 0 else 0) | (FC if carry else 0)
            self.set_r(r, res)
            return 16 if r == 6 else 8
        if kind == 1:
            self.f = (self.f & FC) | FH | (0 if v & (1 << bit) else FZ)
            return 12 if r == 6 else 8
        if kind == 2:
            self.set_r(r, v & ~(1 << bit))
        else:
            self.set_r(r, v | (1 << bit))
        return 16 if r == 6 else 8

    # -------------------------------------------------------------- step
    def step(self):
        """Execute one instruction and return the number of T-cycles consumed"""
        if self.ei_pending:
            self.ei_pending = False
            self.ime = True
        # Interrupts
        pending = self.mem[0xFF0F] & self.mem[0xFFFF] & 0x1F
        if pending:
            self.halted = False
            if self.ime:
                self.ime = False
                for i in range(5):
                    if pending & (1 << i):
                        self.mem[0xFF0F] &= ~(1 << i)
                        self.push(self.pc)
                        self.pc = 0x40 + i * 8
                        return 20
        if self.halted:
            return 4
        pc = self.pc
        self.history.append(pc)
        op = self.fetch()
        cyc = CYCLES[op]
        hi = op >> 6
        if hi == 1:  # LD r,r' / HALT
            if op == 0x76:
                self.halted = True
            else:
                self.set_r((op >> 3) & 7, self.get_r(op & 7))
            return cyc
        if hi == 2:  # ALU A,r
            self.alu((op >> 3) & 7, self.get_r(op & 7))
            return cyc
        if hi == 0:
            lo = op & 7
            if lo == 0:
                if op == 0x00: pass
                elif op == 0x08: self.wr16(self.fetch16(), self.sp)
                elif op == 0x10: self.fetch()  # STOP: treated as NOP
                elif op == 0x18:
                    e = self.fetch(); self.pc = (self.pc + (e - 256 if e > 127 else e)) & 0xFFFF
                else:  # JR cc
                    e = self.fetch()
                    if self.cond((op >> 3) & 3):
                        self.pc = (self.pc + (e - 256 if e > 127 else e)) & 0xFFFF; cyc += 4
            elif lo == 1:
                if op & 8: self.add_hl(self.get_rr(op >> 4))
                else: self.set_rr(op >> 4, self.fetch16())
            elif lo == 2:
                rr = op >> 4
                if rr == 0: addr = (self.b << 8) | self.c
                elif rr == 1: addr = (self.d << 8) | self.e
                else:
                    addr = (self.h << 8) | self.l
                    nhl = (addr + 1 if rr == 2 else addr - 1) & 0xFFFF
                    self.h, self.l = nhl >> 8, nhl & 0xFF
                if op & 8: self.a = self.rd(addr)
                else: self.wr(addr, self.a)
            elif lo == 3:
                rr = op >> 4
                self.set_rr(rr, self.get_rr(rr) + (-1 if op & 8 else 1))
            elif lo == 4:
                r = (op >> 3) & 7; self.set_r(r, self.inc8(self.get_r(r)))
            elif lo == 5:
                r = (op >> 3) & 7; self.set_r(r, self.dec8(self.get_r(r)))
            elif lo == 6:
                self.set_r((op >> 3) & 7, self.fetch())
            else:
                k = (op >> 3) & 7
                a = self.a
                if k == 0: self.a = ((a << 1) | (a >> 7)) & 0xFF; self.f = FC if a & 0x80 else 0
                elif k == 1: self.a = ((a >> 1) | (a << 7)) & 0xFF; self.f = FC if a & 1 else 0
                elif k == 2:
                    c = 1 if self.f & FC else 0; self.a = ((a << 1) | c) & 0xFF; self.f = FC if a & 0x80 else 0
                elif k == 3:
                    c = 1 if self.f & FC else 0; self.a = (a >> 1) | (c << 7); self.f = FC if a & 1 else 0
                elif k == 4:  # DAA
                    adj = 0; f = self.f
                    if f & FH or (not f & FN and (a & 0xF) > 9): adj |= 0x06
                    if f & FC or (not f & FN and a > 0x99): adj |= 0x60
                    a = (a - adj) if f & FN else (a + adj)
                    self.a = a & 0xFF
                    self.f = (f & FN) | (FZ if self.a == 0 else 0) | (FC if (adj & 0x60) else 0)
                elif k == 5: self.a = a ^ 0xFF; self.f |= FN | FH
                elif k == 6: self.f = (self.f & FZ) | FC
                else: self.f = (self.f & FZ) | ((self.f & FC) ^ FC)
            return cyc
        # hi == 3
        lo = op & 7
        if lo == 0:
            if op < 0xE0:  # RET cc
                if self.cond((op >> 3) & 3): self.pc = self.pop(); cyc += 12
            elif op == 0xE0: self.wr(0xFF00 | self.fetch(), self.a)
            elif op == 0xE8: self.sp = self.sp_offset()
            elif op == 0xF0: self.a = self.rd(0xFF00 | self.fetch())
            else:  # F8 LD HL,SP+e
                r = self.sp_offset(); self.h, self.l = r >> 8, r & 0xFF
        elif lo == 1:
            if op == 0xC9: self.pc = self.pop()
            elif op == 0xD9: self.pc = self.pop(); self.ime = True
            elif op == 0xE9: self.pc = (self.h << 8) | self.l
            elif op == 0xF9: self.sp = (self.h << 8) | self.l
            else:  # POP
                v = self.pop(); rr = (op >> 4) & 3
                if rr == 3: self.a, self.f = v >> 8, v & 0xF0
                else: self.set_rr(rr, v)
        elif lo == 2:
            if op == 0xC2 or op == 0xCA or op == 0xD2 or op == 0xDA:
                addr = self.fetch16()
                if self.cond((op >> 3) & 3): self.pc = addr; cyc += 4
            elif op == 0xE2: self.wr(0xFF00 | self.c, self.a)
            elif op == 0xEA: self.wr(self.fetch16(), self.a)
            elif op == 0xF2: self.a = self.rd(0xFF00 | self.c)
            elif op == 0xFA: self.a = self.rd(self.fetch16())
            else: self.illegal(op, pc)
        elif lo == 3:
            if op == 0xC3: self.pc = self.fetch16()
            elif op == 0xCB: cyc = self.cb()
            elif op == 0xF3: self.ime = False; self.ei_pending = False
            elif op == 0xFB: self.ei_pending = True
            else: self.illegal(op, pc)
        elif lo == 4:
            if op < 0xE0:
                addr = self.fetch16()
                if self.cond((op >> 3) & 3): self.push(self.pc); self.pc = addr; cyc += 12
            else: self.illegal(op, pc)
        elif lo == 5:
            if op == 0xCD: addr = self.fetch16(); self.push(self.pc); self.pc = addr
            elif op & 0x0F == 0x05:
                rr = (op >> 4) & 3
                self.push(((self.a << 8) | self.f) if rr == 3 else self.get_rr(rr))
            else: self.illegal(op, pc)
        elif lo == 6:
            self.alu((op >> 3) & 7, self.fetch())
        else:  # RST
            self.push(self.pc); self.pc = op & 0x38
        return cyc

    def illegal(self, op, pc):
        raise TrapError(f'illegal instruction 0x{op:02X} at PC=0x{pc:04X}')

    # -------------------------------------------------------------- timers/PPU
    def tick(self, cyc):
        self.cycles += cyc
        # DIV
        self.div_counter += cyc
        while self.div_counter >= 256:
            self.div_counter -= 256
            self.mem[0xFF04] = (self.mem[0xFF04] + 1) & 0xFF
        tac = self.mem[0xFF07]
        if tac & 4:
            period = (1024, 16, 64, 256)[tac & 3]
            self.tima_counter += cyc
            while self.tima_counter >= period:
                self.tima_counter -= period
                t = self.mem[0xFF05] + 1
                if t > 0xFF:
                    t = self.mem[0xFF06]; self.mem[0xFF0F] |= 0x04
                self.mem[0xFF05] = t
        # PPU
        if not (self.mem[0xFF40] & 0x80):
            # Frame time keeps advancing while the LCD is off
            self.ppu_clock += cyc
            if self.ppu_clock >= 70224:
                self.ppu_clock -= 70224
                self.frame += 1
                for i in range(160 * 144): self.fb[i] = 0
            return
        self.ppu_clock += cyc
        while self.ppu_clock >= 456:
            self.ppu_clock -= 456
            if self.ly < 144:
                self.render_line(self.ly)
            self.ly += 1
            if self.ly == 144:
                self.mem[0xFF0F] |= 0x01
                if self.mem[0xFF41] & 0x10: self.mem[0xFF0F] |= 0x02
            elif self.ly >= 154:
                self.ly = 0; self.window_line = 0; self.frame += 1
            if self.ly == self.mem[0xFF45] and self.mem[0xFF41] & 0x40:
                self.mem[0xFF0F] |= 0x02
        # Mode within the current scanline
        if self.ly >= 144:
            self.mode = 1
        elif self.ppu_clock < 80:
            self.mode = 2
        elif self.ppu_clock < 252:
            self.mode = 3
        else:
            if self.mode != 0 and self.mem[0xFF41] & 0x08:
                self.mem[0xFF0F] |= 0x02
            self.mode = 0

    def render_line(self, y):
        mem = self.mem
        lcdc = mem[0xFF40]
        bgp = mem[0xFF47]
        row = self.fb
        pal_row = self.fb_pal
        base = y * 160
        bg_color = [0] * 160  # color indices before palette mapping (used for sprite priority)
        if lcdc & 0x01:
            scx, scy = mem[0xFF43], mem[0xFF42]
            map_base = 0x9C00 if lcdc & 0x08 else 0x9800
            signed = not (lcdc & 0x10)
            yy = (y + scy) & 0xFF
            trow = (yy >> 3) * 32; fine_y = (yy & 7) * 2
            for x in range(160):
                xx = (x + scx) & 0xFF
                tile = mem[map_base + trow + (xx >> 3)]
                # In signed mode (0x8800 addressing) tiles 0..127 live at 0x9000 and up (= tile numbers 256..383)
                if signed and tile < 128: tile += 256
                addr = 0x8000 + tile * 16 + fine_y
                lo, hi = mem[addr], mem[addr + 1]
                bit = 7 - (xx & 7)
                ci = ((hi >> bit) & 1) << 1 | ((lo >> bit) & 1)
                bg_color[x] = ci
                row[base + x] = (bgp >> (ci * 2)) & 3
                pal_row[base + x] = ci * 2
            # Window
            if lcdc & 0x20:
                wy, wx = mem[0xFF4A], mem[0xFF4B] - 7
                if y >= wy and wx < 160:
                    wmap = 0x9C00 if lcdc & 0x40 else 0x9800
                    wl = self.window_line
                    trow = (wl >> 3) * 32; fine_y = (wl & 7) * 2
                    for x in range(max(wx, 0), 160):
                        xx = x - wx
                        tile = mem[wmap + trow + (xx >> 3)]
                        if signed and tile < 128: tile += 256
                        addr = 0x8000 + tile * 16 + fine_y
                        lo, hi = mem[addr], mem[addr + 1]
                        bit = 7 - (xx & 7)
                        ci = ((hi >> bit) & 1) << 1 | ((lo >> bit) & 1)
                        bg_color[x] = ci
                        row[base + x] = (bgp >> (ci * 2)) & 3
                        pal_row[base + x] = ci * 2
                    self.window_line += 1
        else:
            for x in range(160): row[base + x] = 0; pal_row[base + x] = 0
        # Sprites
        if lcdc & 0x02:
            height = 16 if lcdc & 0x04 else 8
            sprites = []
            for i in range(40):
                sy = mem[0xFE00 + i * 4] - 16
                if sy <= y < sy + height:
                    sprites.append((mem[0xFE01 + i * 4], i))
                    if len(sprites) == 10: break
            # Smaller x wins, ties are broken by OAM order. Draw lowest priority first so higher ones overwrite
            sprites.sort(key=lambda s: (s[0], s[1]), reverse=True)
            for sx, i in sprites:
                o = 0xFE00 + i * 4
                sy = mem[o] - 16; tile = mem[o + 2]; attr = mem[o + 3]
                line = y - sy
                if attr & 0x40: line = height - 1 - line
                if height == 16: tile &= 0xFE
                addr = 0x8000 + tile * 16 + line * 2
                lo, hi = mem[addr], mem[addr + 1]
                pal = mem[0xFF49 if attr & 0x10 else 0xFF48]
                for px in range(8):
                    x = sx - 8 + px
                    if not 0 <= x < 160: continue
                    bit = px if attr & 0x20 else 7 - px
                    ci = ((hi >> bit) & 1) << 1 | ((lo >> bit) & 1)
                    if ci == 0: continue
                    if attr & 0x80 and bg_color[x] != 0: continue
                    row[base + x] = (pal >> (ci * 2)) & 3
                    pal_row[base + x] = 64 + (attr & 7) * 8 + ci * 2

    # -------------------------------------------------------------- run
    def run_frames(self, n, trap_check=True, press=None):
        target = self.frame + n
        while self.frame < target:
            if press is not None:
                self.buttons = press(self.frame)
            pc = self.pc
            cyc = self.step()
            self.tick(cyc)
            if trap_check and 0x08 <= pc <= 0x3F and self.rd(pc) == 0x18 and self.rd(pc + 1) == 0xFE:
                raise TrapError(f'reached the infinite loop at RST 0x{pc:02X} (probably a Swift trap / fatal error)')
            if trap_check and self.halted and not (self.mem[0xFFFF] & 0x1F):
                # halt with all interrupts disabled never wakes up again.
                # If this is crt0's _halt (halt; nop; jr _halt), main returned normally; otherwise it is the halt emitted for llvm.trap
                if self.rd(pc) == 0x76 and self.rd(pc + 1) == 0x00 and self.rd(pc + 2) == 0x18 and self.rd(pc + 3) == 0xFC:
                    self.finished = True
                    return
                raise TrapError(f'reached a Swift trap (halt instruction) at PC=0x{pc:04X}: fatal error such as an out-of-bounds array access or integer overflow')

    # -------------------------------------------------------------- output
    def dump_history(self):
        out = []
        for pc in self.history:
            op = self.rd(pc)
            out.append(f'{pc:04X}: {op:02X} {self.rd(pc+1):02X} {self.rd(pc+2):02X}')
        return '\n'.join(out)

    def dump_state(self):
        m = self.mem
        return (f'AF={self.a:02X}{self.f:02X} BC={self.b:02X}{self.c:02X} DE={self.d:02X}{self.e:02X} '
                f'HL={self.h:02X}{self.l:02X} SP={self.sp:04X} PC={self.pc:04X} IME={int(self.ime)} '
                f'LCDC={m[0xFF40]:02X} STAT={self.rd(0xFF41):02X} LY={self.ly} IE={m[0xFFFF]:02X} IF={m[0xFF0F]:02X}')

    def ascii_screen(self):
        chars = ' .:#'
        lines = []
        for y in range(0, 144, 4):
            line = ''
            for x in range(0, 160, 2):
                s = max(self.fb[(y + dy) * 160 + x + dx] for dy in range(4) for dx in range(2))
                line += chars[s]
            lines.append(line)
        return '\n'.join(lines)

    def pixel_rgb(self, i):
        if not self.cgb:
            return PALETTE[self.fb[i]]
        o = self.fb_pal[i]
        c = self.cgb_pal[o] | self.cgb_pal[o + 1] << 8
        return tuple((v << 3 | v >> 2) for v in (c & 31, (c >> 5) & 31, (c >> 10) & 31))

    def png(self, scale=2):
        w, h = 160 * scale, 144 * scale
        raw = bytearray()
        for y in range(h):
            raw.append(0)
            srow = (y // scale) * 160
            for x in range(w):
                raw += bytes(self.pixel_rgb(srow + x // scale))

        def chunk(t, d):
            c = struct.pack('>I', len(d)) + t + d
            return c + struct.pack('>I', zlib.crc32(t + d) & 0xFFFFFFFF)
        return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))


def parse_press(spec):
    """'10:RIGHT+A,30:,40:START' -> function mapping a frame number to a button mask"""
    if not spec:
        return None
    events = []
    for item in spec.split(','):
        frame, _, names = item.partition(':')
        mask = 0
        for n in filter(None, names.upper().split('+')):
            if n not in BUTTONS:
                raise SystemExit(f'unknown button name: {n} (available: {", ".join(BUTTONS)})')
            mask |= BUTTONS[n]
        events.append((int(frame), mask))
    events.sort()

    def press(frame):
        cur = 0
        for f, m in events:
            if frame >= f: cur = m
        return cur
    return press


def main():
    ap = argparse.ArgumentParser(description='Minimal Game Boy emulator bundled with swift-gameboy')
    ap.add_argument('rom')
    ap.add_argument('--frames', type=int, default=60, help='number of frames to run (default 60)')
    ap.add_argument('--screenshot', help='write a PNG screenshot to this path')
    ap.add_argument('--scale', type=int, default=2)
    ap.add_argument('--ascii', action='store_true', help='print the screen to stdout as ASCII art')
    ap.add_argument('--press', help='button input: "10:RIGHT+A,30:,40:START" (frame:buttons, held until the next entry)')
    ap.add_argument('--no-trap-check', action='store_true')
    ap.add_argument('--quiet', action='store_true')
    ap.add_argument('--trace', action='store_true', help='on exit, print the PCs of the last 64 instructions and the registers (for debugging)')
    args = ap.parse_args()

    with open(args.rom, 'rb') as f:
        rom = f.read()
    gb = GameBoy(rom)
    title = rom[0x134:0x143].rstrip(b'\x00').decode('ascii', 'replace') if len(rom) > 0x143 else ''
    status = 'OK'
    try:
        gb.run_frames(args.frames, trap_check=not args.no_trap_check, press=parse_press(args.press))
    except TrapError as e:
        status = f'TRAP: {e}'
    if gb.finished:
        status = 'FINISHED (main returned)'
    if not args.quiet:
        print(f'title={title!r} frames={gb.frame} cycles={gb.cycles} pc=0x{gb.pc:04X} sp=0x{gb.sp:04X} status={status}')
    if gb.dropped_vram_writes:
        print(f'warning: LCD on: {gb.dropped_vram_writes} VRAM/OAM writes were made while the PPU had the memory locked and were dropped (the display would be corrupted on real hardware)')
    if gb.serial_log:
        print('--- serial ---')
        print(gb.serial_log.decode('ascii', 'replace'))
        print('--------------')
    if args.trace or status != 'OK':
        print(gb.dump_state())
    if args.trace:
        print('--- recent instructions ---')
        print(gb.dump_history())
    if args.ascii:
        print(gb.ascii_screen())
    if args.screenshot:
        with open(args.screenshot, 'wb') as f:
            f.write(gb.png(args.scale))
    sys.exit(0 if not status.startswith('TRAP') else 1)


if __name__ == '__main__':
    main()

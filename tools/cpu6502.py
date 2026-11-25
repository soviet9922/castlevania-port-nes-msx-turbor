"""A small 6502 interpreter (official opcodes, no decimal mode: the NES has
none) for running bits of NES code at build time, e.g. the sound driver.

    cpu = CPU(read, write)       # read(addr) -> byte, write(addr, byte)
    cpu.call(addr, a=0, x=0, y=0, max_steps=200000)

Standard library only.
"""

C, Z, I, D, B, U, V, N = 1, 2, 4, 8, 16, 32, 64, 128


class CPU:
    def __init__(self, read, write):
        self.read, self.write = read, write
        self.a = self.x = self.y = 0
        self.sp = 0xFD
        self.p = U | I
        self.pc = 0
        self.ops = self._table()

    # --- helpers ---
    def _rw(self, a):
        return self.read(a & 0xFFFF) | self.read((a + 1) & 0xFFFF) << 8

    def _nz(self, v):
        v &= 0xFF
        self.p = (self.p & ~(N | Z)) | (v & N) | (Z if v == 0 else 0)
        return v

    def _push(self, v):
        self.write(0x100 | self.sp, v & 0xFF)
        self.sp = (self.sp - 1) & 0xFF

    def _pop(self):
        self.sp = (self.sp + 1) & 0xFF
        return self.read(0x100 | self.sp)

    def _fetch(self):
        v = self.read(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        return v

    def _fetch16(self):
        lo = self._fetch()
        return lo | self._fetch() << 8

    # addressing modes -> effective address
    def imm(self):
        a = self.pc
        self.pc = (self.pc + 1) & 0xFFFF
        return a

    def zp(self):
        return self._fetch()

    def zpx(self):
        return (self._fetch() + self.x) & 0xFF

    def zpy(self):
        return (self._fetch() + self.y) & 0xFF

    def ab(self):
        return self._fetch16()

    def abx(self):
        return (self._fetch16() + self.x) & 0xFFFF

    def aby(self):
        return (self._fetch16() + self.y) & 0xFFFF

    def izx(self):
        z = (self._fetch() + self.x) & 0xFF
        return self.read(z) | self.read((z + 1) & 0xFF) << 8

    def izy(self):
        z = self._fetch()
        return ((self.read(z) | self.read((z + 1) & 0xFF) << 8) + self.y) & 0xFFFF

    def ind(self):
        a = self._fetch16()
        return self.read(a) | self.read((a & 0xFF00) | ((a + 1) & 0xFF)) << 8

    # --- operations ---
    def _adc(self, v):
        r = self.a + v + (self.p & C)
        self.p &= ~(C | V)
        if r > 0xFF:
            self.p |= C
        if ~(self.a ^ v) & (self.a ^ r) & 0x80:
            self.p |= V
        self.a = self._nz(r)

    def _cmp(self, r, v):
        t = r - v
        self.p = (self.p & ~C) | (C if t >= 0 else 0)
        self._nz(t)

    def _branch(self, cond):
        off = self._fetch()
        if cond:
            self.pc = (self.pc + (off - 256 if off > 127 else off)) & 0xFFFF

    def _table(self):
        t = {}
        modes = {"imm": self.imm, "zp": self.zp, "zpx": self.zpx, "zpy": self.zpy,
                 "ab": self.ab, "abx": self.abx, "aby": self.aby, "izx": self.izx,
                 "izy": self.izy}
        rd = self.read

        def alu(base, fn):
            for m, off in (("izx", 1), ("zp", 5), ("imm", 9), ("ab", 0xD), ("izy", 0x11),
                           ("zpx", 0x15), ("aby", 0x19), ("abx", 0x1D)):
                mf = modes[m]
                t[base + off] = (lambda mf=mf: fn(rd(mf())))

        def ora(v): self.a = self._nz(self.a | v)
        def and_(v): self.a = self._nz(self.a & v)
        def eor(v): self.a = self._nz(self.a ^ v)
        def lda(v): self.a = self._nz(v)
        alu(0x00, ora); alu(0x20, and_); alu(0x40, eor); alu(0x60, self._adc)
        alu(0xA0, lda); alu(0xC0, lambda v: self._cmp(self.a, v))
        alu(0xE0, lambda v: self._adc(v ^ 0xFF))
        for m, op in (("izx", 0x81), ("zp", 0x85), ("ab", 0x8D), ("izy", 0x91),
                      ("zpx", 0x95), ("aby", 0x99), ("abx", 0x9D)):
            mf = modes[m]
            t[op] = (lambda mf=mf: self.write(mf(), self.a))

        def shift(op, acc, fn):
            t[acc] = lambda: setattr(self, "a", fn(self.a))
            for m, o in (("zp", 0x06), ("ab", 0x0E), ("zpx", 0x16), ("abx", 0x1E)):
                mf = modes[m]

                def f(mf=mf):
                    ad = mf()
                    self.write(ad, fn(rd(ad)))
                t[op + o] = f

        def asl(v):
            self.p = (self.p & ~C) | (v >> 7)
            return self._nz(v << 1)

        def rol(v):
            c = self.p & C
            self.p = (self.p & ~C) | (v >> 7)
            return self._nz(v << 1 | c)

        def lsr(v):
            self.p = (self.p & ~C) | (v & 1)
            return self._nz(v >> 1)

        def ror(v):
            c = self.p & C
            self.p = (self.p & ~C) | (v & 1)
            return self._nz(v >> 1 | c << 7)
        shift(0x00, 0x0A, asl); shift(0x20, 0x2A, rol); shift(0x40, 0x4A, lsr); shift(0x60, 0x6A, ror)

        def incdec(base, d):
            for m, o in (("zp", 6), ("ab", 0xE), ("zpx", 0x16), ("abx", 0x1E)):
                mf = modes[m]

                def f(mf=mf):
                    ad = mf()
                    self.write(ad, self._nz(rd(ad) + d))
                t[base + o] = f
        incdec(0xE0, 1); incdec(0xC0, -1)

        def ldx(v): self.x = self._nz(v)
        def ldy(v): self.y = self._nz(v)
        for m, op in (("imm", 0xA2), ("zp", 0xA6), ("ab", 0xAE), ("zpy", 0xB6), ("aby", 0xBE)):
            mf = modes[m]
            t[op] = (lambda mf=mf: ldx(rd(mf())))
        for m, op in (("imm", 0xA0), ("zp", 0xA4), ("ab", 0xAC), ("zpx", 0xB4), ("abx", 0xBC)):
            mf = modes[m]
            t[op] = (lambda mf=mf: ldy(rd(mf())))
        for m, op in (("zp", 0x86), ("ab", 0x8E), ("zpy", 0x96)):
            mf = modes[m]
            t[op] = (lambda mf=mf: self.write(mf(), self.x))
        for m, op in (("zp", 0x84), ("ab", 0x8C), ("zpx", 0x94)):
            mf = modes[m]
            t[op] = (lambda mf=mf: self.write(mf(), self.y))
        for m, op in (("imm", 0xE0), ("zp", 0xE4), ("ab", 0xEC)):
            mf = modes[m]
            t[op] = (lambda mf=mf: self._cmp(self.x, rd(mf())))
        for m, op in (("imm", 0xC0), ("zp", 0xC4), ("ab", 0xCC)):
            mf = modes[m]
            t[op] = (lambda mf=mf: self._cmp(self.y, rd(mf())))

        def bit(v):
            self.p = (self.p & ~(N | V | Z)) | (v & (N | V)) | (0 if self.a & v else Z)
        t[0x24] = lambda: bit(rd(self.zp()))
        t[0x2C] = lambda: bit(rd(self.ab()))

        for op, flag, want in ((0x10, N, 0), (0x30, N, 1), (0x50, V, 0), (0x70, V, 1),
                               (0x90, C, 0), (0xB0, C, 1), (0xD0, Z, 0), (0xF0, Z, 1)):
            t[op] = (lambda flag=flag, want=want: self._branch(bool(self.p & flag) == bool(want)))

        def jsr():
            a = self._fetch16()
            r = (self.pc - 1) & 0xFFFF
            self._push(r >> 8)
            self._push(r)
            self.pc = a

        def rts():
            lo = self._pop()
            self.pc = ((self._pop() << 8 | lo) + 1) & 0xFFFF

        def rti():
            self.p = (self._pop() | U) & ~B
            lo = self._pop()
            self.pc = self._pop() << 8 | lo
        t[0x20] = jsr
        t[0x60] = rts
        t[0x40] = rti
        t[0x4C] = lambda: setattr(self, "pc", self.ab())
        t[0x6C] = lambda: setattr(self, "pc", self.ind())

        def flag(op, f, v):
            t[op] = lambda: setattr(self, "p", (self.p | f) if v else (self.p & ~f))
        flag(0x18, C, 0); flag(0x38, C, 1); flag(0x58, I, 0); flag(0x78, I, 1)
        flag(0xB8, V, 0); flag(0xD8, D, 0); flag(0xF8, D, 1)

        t[0xAA] = lambda: setattr(self, "x", self._nz(self.a))
        t[0xA8] = lambda: setattr(self, "y", self._nz(self.a))
        t[0x8A] = lambda: setattr(self, "a", self._nz(self.x))
        t[0x98] = lambda: setattr(self, "a", self._nz(self.y))
        t[0xBA] = lambda: setattr(self, "x", self._nz(self.sp))
        t[0x9A] = lambda: setattr(self, "sp", self.x)
        t[0xE8] = lambda: setattr(self, "x", self._nz(self.x + 1))
        t[0xC8] = lambda: setattr(self, "y", self._nz(self.y + 1))
        t[0xCA] = lambda: setattr(self, "x", self._nz(self.x - 1))
        t[0x88] = lambda: setattr(self, "y", self._nz(self.y - 1))
        t[0x48] = lambda: self._push(self.a)
        t[0x08] = lambda: self._push(self.p | B | U)
        t[0x68] = lambda: setattr(self, "a", self._nz(self._pop()))
        t[0x28] = lambda: setattr(self, "p", (self._pop() | U) & ~B)
        t[0xEA] = lambda: None
        return t

    def call(self, addr, a=0, x=0, y=0, max_steps=200000):
        """Run the subroutine at addr until it returns."""
        self.a, self.x, self.y = a, x, y
        self.sp = 0xFD
        sentinel = 0xFFF0
        r = sentinel - 1
        self._push(r >> 8)
        self._push(r)
        self.pc = addr
        for _ in range(max_steps):
            if self.pc == sentinel:
                return
            op = self._fetch()
            f = self.ops.get(op)
            if f is None:
                raise RuntimeError(f"unknown opcode {op:02X} at {self.pc - 1:04X}")
            f()
        raise RuntimeError(f"subroutine {addr:04X} did not return")

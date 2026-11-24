#!/usr/bin/env python3
"""Minimal 6502 disassembler for studying the NES PRG banks.

  dis6502.py ROM BANK START [END]      disassemble CPU range START..END
  dis6502.py ROM --find HEXBYTES       find a byte pattern in all banks

Bank 7 is the fixed bank at $C000; banks 0-6 are switched in at $8000
(Castlevania uses UNROM). Addresses are CPU addresses.
"""

import sys

MODES = {
    "imp": 0, "acc": 0, "imm": 1, "zp": 1, "zpx": 1, "zpy": 1, "izx": 1,
    "izy": 1, "rel": 1, "abs": 2, "abx": 2, "aby": 2, "ind": 2,
}

OPS = {}


def _def(spec):
    for item in spec.split():
        op, mn, mode = item.split(":")
        OPS[int(op, 16)] = (mn, mode)


_def("""
00:brk:imp 01:ora:izx 05:ora:zp 06:asl:zp 08:php:imp 09:ora:imm 0a:asl:acc
0d:ora:abs 0e:asl:abs 10:bpl:rel 11:ora:izy 15:ora:zpx 16:asl:zpx 18:clc:imp
19:ora:aby 1d:ora:abx 1e:asl:abx 20:jsr:abs 21:and:izx 24:bit:zp 25:and:zp
26:rol:zp 28:plp:imp 29:and:imm 2a:rol:acc 2c:bit:abs 2d:and:abs 2e:rol:abs
30:bmi:rel 31:and:izy 35:and:zpx 36:rol:zpx 38:sec:imp 39:and:aby 3d:and:abx
3e:rol:abx 40:rti:imp 41:eor:izx 45:eor:zp 46:lsr:zp 48:pha:imp 49:eor:imm
4a:lsr:acc 4c:jmp:abs 4d:eor:abs 4e:lsr:abs 50:bvc:rel 51:eor:izy 55:eor:zpx
56:lsr:zpx 58:cli:imp 59:eor:aby 5d:eor:abx 5e:lsr:abx 60:rts:imp 61:adc:izx
65:adc:zp 66:ror:zp 68:pla:imp 69:adc:imm 6a:ror:acc 6c:jmp:ind 6d:adc:abs
6e:ror:abs 70:bvs:rel 71:adc:izy 75:adc:zpx 76:ror:zpx 78:sei:imp 79:adc:aby
7d:adc:abx 7e:ror:abx 81:sta:izx 84:sty:zp 85:sta:zp 86:stx:zp 88:dey:imp
8a:txa:imp 8c:sty:abs 8d:sta:abs 8e:stx:abs 90:bcc:rel 91:sta:izy 94:sty:zpx
95:sta:zpx 96:stx:zpy 98:tya:imp 99:sta:aby 9a:txs:imp 9d:sta:abx a0:ldy:imm
a1:lda:izx a2:ldx:imm a4:ldy:zp a5:lda:zp a6:ldx:zp a8:tay:imp a9:lda:imm
aa:tax:imp ac:ldy:abs ad:lda:abs ae:ldx:abs b0:bcs:rel b1:lda:izy b4:ldy:zpx
b5:lda:zpx b6:ldx:zpy b8:clv:imp b9:lda:aby ba:tsx:imp bc:ldy:abx bd:lda:abx
be:ldx:aby c0:cpy:imm c1:cmp:izx c4:cpy:zp c5:cmp:zp c6:dec:zp c8:iny:imp
c9:cmp:imm ca:dex:imp cc:cpy:abs cd:cmp:abs ce:dec:abs d0:bne:rel d1:cmp:izy
d5:cmp:zpx d6:dec:zpx d8:cld:imp d9:cmp:aby dd:cmp:abx de:dec:abx e0:cpx:imm
e1:sbc:izx e4:cpx:zp e5:sbc:zp e6:inc:zp e8:inx:imp e9:sbc:imm ea:nop:imp
ec:cpx:abs ed:sbc:abs ee:inc:abs f0:beq:rel f1:sbc:izy f5:sbc:zpx f6:inc:zpx
f8:sed:imp f9:sbc:aby fd:sbc:abx fe:inc:abx
""")

FMT = {
    "imp": "", "acc": "a", "imm": "#${:02x}", "zp": "${:02x}", "zpx": "${:02x},x",
    "zpy": "${:02x},y", "izx": "(${:02x},x)", "izy": "(${:02x}),y",
    "abs": "${:04x}", "abx": "${:04x},x", "aby": "${:04x},y", "ind": "(${:04x})",
}


def load_prg(path):
    d = open(path, "rb").read()
    assert d[:4] == b"NES\x1a"
    return d[16:16 + d[4] * 16384]


def bank_base(bank, nbanks=8):
    return 0xC000 if bank == nbanks - 1 else 0x8000


def disasm(prg, bank, start, end):
    base = bank_base(bank)
    data = prg[bank * 16384:(bank + 1) * 16384]
    pc = start
    out = []
    while pc < end:
        off = pc - base
        op = data[off]
        if op not in OPS:
            out.append(f"{pc:04x}  {op:02x}        .db ${op:02x}")
            pc += 1
            continue
        mn, mode = OPS[op]
        n = MODES[mode]
        raw = data[off:off + 1 + n]
        if mode == "rel":
            rel = raw[1] - 256 if raw[1] >= 128 else raw[1]
            arg = f"${pc + 2 + rel:04x}"
        elif n == 1:
            arg = FMT[mode].format(raw[1])
        elif n == 2:
            arg = FMT[mode].format(raw[1] | raw[2] << 8)
        else:
            arg = FMT[mode]
        out.append(f"{pc:04x}  {' '.join(f'{b:02x}' for b in raw):<9} {mn} {arg}".rstrip())
        pc += 1 + n
    return out


def main():
    if len(sys.argv) >= 4 and sys.argv[2] == "--find":
        prg = load_prg(sys.argv[1])
        pat = bytes.fromhex(sys.argv[3])
        for bank in range(len(prg) // 16384):
            data = prg[bank * 16384:(bank + 1) * 16384]
            i = data.find(pat)
            while i >= 0:
                print(f"bank {bank} ${bank_base(bank) + i:04x}")
                i = data.find(pat, i + 1)
        return
    prg = load_prg(sys.argv[1])
    bank = int(sys.argv[2])
    start = int(sys.argv[3], 16)
    end = int(sys.argv[4], 16) if len(sys.argv) > 4 else start + 0x40
    print("\n".join(disasm(prg, bank, start, end)))


if __name__ == "__main__":
    main()

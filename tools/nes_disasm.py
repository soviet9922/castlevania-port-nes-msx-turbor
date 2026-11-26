#!/usr/bin/env python3
"""Disassemble the user's own Castlevania (NES) ROM into annotated listings.

  nes_disasm.py ROM OUT_DIR [COVERAGE_FILES...]

Writes OUT_DIR/bank0.asm .. bank7.asm (bank 7 is the fixed bank at $C000,
banks 0-6 are switched in at $8000) and OUT_DIR/report.txt. The listings
are made from the ROM on the user's machine and, like everything converted
from it, go into the git-ignored build/ folder: never commit them.

Code is found from
  - coverage files written by tools/nes_probe/trace_code.lua ("X bank addr":
    every instruction the game executed while a bot played, with the bank
    that was mapped at $8000),
  - the CPU vectors and the entry points in tools/nes_labels.txt,
  - recursive descent from all of those: branches, JSR and JMP targets in the
    same bank (or the fixed bank), and inline jump tables: the game calls a
    dispatcher (JSR $CA6D) that is followed by a table of addresses indexed
    by A ("inline" in nes_labels.txt).
Everything else is data, listed 8 bytes a line with a label wherever code
addresses it. Known RAM and routines are named from tools/nes_labels.txt;
every call and jump target gets a label and a list of the places that use it.
"""

import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dis6502 import MODES, OPS        # noqa: E402

BANK = 0x4000
NBANKS = 8
DEFAULT_BANK = 6       # what restore_bank maps ($24, set once at reset)
FIXED = 7
BRANCH = {"bpl", "bmi", "bvc", "bvs", "bcc", "bcs", "bne", "beq"}
STOP = {"rts", "rti", "brk"}
LABELS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "nes_labels.txt")


def base_of(bank):
    return 0xC000 if bank == FIXED else 0x8000


def bank_of_target(bank, addr):
    """the bank holding CPU address addr when called from code in `bank`
    (None: a switchable address reached from the fixed bank: unknown)"""
    if addr >= 0xC000:
        return FIXED
    if addr >= 0x8000:
        return None if bank == FIXED else bank
    return -1                           # RAM / registers


class Rom:
    def __init__(self, path):
        d = open(path, "rb").read()
        if d[:4] != b"NES\x1a" or d[4] != NBANKS:
            raise SystemExit("not the expected Castlevania ROM (iNES, 8 PRG banks)")
        self.prg = d[16:16 + NBANKS * BANK]

    def byte(self, bank, addr):
        return self.prg[bank * BANK + addr - base_of(bank)]

    def word(self, bank, addr):
        return self.byte(bank, addr) | self.byte(bank, addr + 1) << 8

    def inside(self, bank, addr):
        return base_of(bank) <= addr < base_of(bank) + BANK


def load_labels():
    ram, code, data, inline, comments = {}, {}, {}, set(), {}
    for line in open(LABELS_FILE):
        line = line.split("#")[0].strip()
        if not line:
            continue
        parts = line.split(None, 4)
        if parts[0] == "ram":
            ram[int(parts[1], 16)] = parts[2]
            if len(parts) > 3:
                comments[("ram", int(parts[1], 16))] = " ".join(parts[3:])
            continue
        kind, bank, addr, name = parts[0], int(parts[1]), int(parts[2], 16), parts[3]
        rest = parts[4] if len(parts) > 4 else ""
        if kind in ("code", "inline"):
            code[(bank, addr)] = name
        if kind == "inline":
            inline.add((bank, addr))
        if kind == "data":
            data[(bank, addr)] = name
        if rest:
            comments[(bank, addr)] = rest
    return ram, code, data, inline, comments


class Disassembly:
    def __init__(self, rom, coverage):
        self.rom = rom
        self.ram, self.names, self.data_names, self.inline, self.comments = load_labels()
        self.code = {}                  # (bank, addr) -> instruction length
        self.executed = set()
        self.refs = defaultdict(set)    # (bank, addr) -> {(bank, from addr, kind)}
        self.tables = {}                # (bank, addr) -> number of words (inline jump tables)
        self.unknown_far = defaultdict(set)   # $8000 targets from the fixed bank
        self.ran_in = defaultdict(set)  # $8000-$BFFF address -> banks it ran in
        for bank, addr in coverage:
            self.executed.add((bank, addr))
            if bank != FIXED:
                self.ran_in[addr].add(bank)
        seeds = set(self.executed)
        for (bank, addr) in self.names:
            seeds.add((bank, addr))
        for v in (0xFFFA, 0xFFFC, 0xFFFE):
            seeds.add((FIXED, rom.word(FIXED, v)))
        self.switch_bank = next(a for (b, a), n in self.names.items() if n == "switch_bank")
        self.restore_bank = next(a for (b, a), n in self.names.items() if n == "restore_bank")
        self.bank_ctx = {}
        for _ in range(4):              # resolve, walk again with what it found
            self.walk(seeds)
            ctx = self.find_bank_contexts()
            if ctx == self.bank_ctx:
                break
            self.bank_ctx = ctx
            self.code.clear()
            self.refs.clear()
            self.tables.clear()
            self.unknown_far.clear()

    def target_bank(self, bank, addr, src=None):
        """bank_of_target, with switchable addresses reached from the fixed
        bank resolved by the bank mapped there (bank_ctx: found from the
        bank-switch calls) or else by the coverage, when they ran in exactly
        one bank"""
        tb = bank_of_target(bank, addr)
        if tb is None and src is not None and self.bank_ctx:
            # the bank mapped there, else the usual one restore_bank maps
            tb = self.bank_ctx.get(src, DEFAULT_BANK)
        if tb is None and len(self.ran_in.get(addr, ())) == 1:
            tb = next(iter(self.ran_in[addr]))
        return tb

    def find_bank_contexts(self):
        """Fixed-bank code reached right after "LDY #n / JSR switch_bank" runs
        with bank n mapped: mark it (and the fixed-bank code it reaches without
        switching again) with n."""
        switch = self.switch_bank
        starts = []
        for (bank, addr), size in sorted(self.code.items()):
            if bank != FIXED:
                continue
            ins = self.decode(bank, addr)
            if ins[0] == "jsr" and ins[3] == switch:
                prev = [(a, s) for (b, a), s in self.code.items() if b == FIXED and a + s == addr]
                if not prev:
                    continue
                p = self.decode(FIXED, prev[0][0])
                if p[0] != "ldy" or p[1] != "imm":
                    continue
                n = p[3]
                starts.append((addr + 3, n))
        # fixed-bank code a switchable bank calls runs with that bank mapped
        for (tb, t), srcs in self.refs.items():
            if tb == FIXED:
                for (b, _, _) in srcs:
                    if b != FIXED:
                        starts.append((t, b))
        ctx = {}
        for start, n in starts:
            todo = [start]
            while todo:
                a = todo.pop()
                while (FIXED, a) in self.code and a not in ctx:
                    ctx[a] = n
                    mn, mode, size, arg = self.decode(FIXED, a)
                    if mn == "jsr" and arg in (switch, self.restore_bank):
                        break           # switches again: stop here
                    if (mn in BRANCH or mn in ("jsr", "jmp")) and mode in ("rel", "abs") \
                            and arg >= 0xC000:
                        todo.append(arg)
                    if (FIXED, a + size) in self.tables:
                        t = a + size
                        for i in range(self.tables[(FIXED, t)]):
                            ctx[t + 2 * i] = n
                            w = self.rom.word(FIXED, t + 2 * i)
                            if w >= 0xC000:
                                todo.append(w)
                        break
                    if mn in STOP or mn == "jmp":
                        break
                    a += size
        return ctx

    # --- recursive descent ---
    def decode(self, bank, addr):
        op = self.rom.byte(bank, addr)
        if op not in OPS:
            return None
        mn, mode = OPS[op]
        n = MODES[mode]
        if not self.rom.inside(bank, addr + n):
            return None
        arg = None
        if n == 1:
            arg = self.rom.byte(bank, addr + 1)
            if mode == "rel":
                arg = addr + 2 + (arg - 256 if arg >= 128 else arg)
        elif n == 2:
            arg = self.rom.word(bank, addr + 1)
        return mn, mode, n + 1, arg

    def walk(self, seeds):
        todo = list(seeds)
        while todo:
            bank, addr = todo.pop()
            while self.rom.inside(bank, addr) and (bank, addr) not in self.code:
                ins = self.decode(bank, addr)
                if ins is None:
                    break
                mn, mode, size, arg = ins
                if any((bank, addr + i) in self.code for i in range(1, size)):
                    break               # overlaps code found another way
                self.code[(bank, addr)] = size
                nxt = addr + size
                if mn in BRANCH or (mn in ("jsr", "jmp") and mode == "abs"):
                    tb = self.target_bank(bank, arg, addr if bank == FIXED else None)
                    kind = "jsr" if mn == "jsr" else ("jmp" if mn == "jmp" else "br")
                    if tb is None:
                        self.unknown_far[arg].add((bank, addr))
                    elif tb >= 0:
                        self.refs[(tb, arg)].add((bank, addr, kind))
                        todo.append((tb, arg))
                    if mn == "jsr" and tb is not None and tb >= 0 and (tb, arg) in self.inline:
                        nxt = self.read_table(bank, nxt, todo)
                        if nxt is None:
                            break
                        addr = nxt
                        continue
                if mn in STOP or mn == "jmp":
                    break
                addr = nxt

    def read_table(self, bank, addr, todo):
        """an inline jump table at addr: words while they point at code in this
        bank or the fixed bank, up to code that follows it. -> None: ends the
        code there (the dispatcher never returns)"""
        n = 0
        while self.rom.inside(bank, addr + 1) and (bank, addr) not in self.code:
            w = self.rom.word(bank, addr)
            tb = self.target_bank(bank, w, addr if bank == FIXED else None)
            if tb is None and w >= 0x8000:
                tb = -2                 # (a switchable bank not known here)
            if tb is None or tb == -1 or (w & 0xFF00) == 0:
                break
            if (bank, addr) in self.executed and n > 0:
                break                   # code runs here: the table has ended
            if tb >= 0:
                self.refs[(tb, w)].add((bank, addr, "tab"))
                todo.append((tb, w))
            addr += 2
            n += 1
        if n:
            self.tables[(bank, addr - 2 * n)] = n
        return None

    # --- output ---
    def label(self, bank, addr):
        key = (bank, addr)
        if key in self.names:
            return self.names[key]
        if key in self.data_names:
            return self.data_names[key]
        kinds = {k for _, _, k in self.refs.get(key, ())}
        if key in self.code:
            if "jsr" in kinds or "tab" in kinds:
                return f"sub_{bank}_{addr:04X}" if bank != FIXED else f"sub_{addr:04X}"
            return f"L{bank}_{addr:04X}" if bank != FIXED else f"L{addr:04X}"
        return f"dat_{bank}_{addr:04X}" if bank != FIXED else f"dat_{addr:04X}"

    def operand(self, bank, addr, mn, mode, arg):
        if mode in ("imp",):
            return ""
        if mode == "acc":
            return "a"
        if mode == "imm":
            return f"#${arg:02X}"
        if mode == "rel" or (mn in ("jsr", "jmp") and mode == "abs"):
            tb = self.target_bank(bank, arg, addr if bank == FIXED else None)
            if tb is not None and tb >= 0:
                return self.label(tb, arg)
            return f"${arg:04X}"
        if mode in ("zp", "zpx", "zpy", "izx", "izy"):
            name = self.ram.get(arg, f"${arg:02X}")
        else:
            tb = bank_of_target(bank, arg)
            if arg < 0x0800 and arg in self.ram:
                name = self.ram[arg]
            elif tb is not None and tb >= 0:
                name = self.label(tb, arg)
                self.data_refs.add((tb, arg))
            else:
                name = f"${arg:04X}"
        return {"zp": "{}", "zpx": "{},x", "zpy": "{},y", "izx": "({},x)", "izy": "({}),y",
                "abs": "{}", "abx": "{},x", "aby": "{},y", "ind": "({})"}[mode].format(name)

    def write(self, out_dir):
        os.makedirs(out_dir, exist_ok=True)
        # first pass: data addressed by code gets labels
        self.data_refs = set()
        for (bank, addr), size in self.code.items():
            mn, mode, _, arg = self.decode(bank, addr)
            self.operand(bank, addr, mn, mode, arg)
        report = []
        for bank in range(NBANKS):
            lines = self.bank_lines(bank)
            with open(os.path.join(out_dir, f"bank{bank}.asm"), "w") as f:
                f.write("\n".join(lines) + "\n")
            code_bytes = sum(s for (b, _), s in self.code.items() if b == bank)
            ex = sum(1 for (b, _) in self.executed if b == bank)
            report.append(f"bank {bank}: {code_bytes:5d} bytes of code "
                          f"({100 * code_bytes / BANK:4.1f}%), {ex} instructions seen running")
        report.append(f"inline jump tables: {len(self.tables)}")
        far = sorted(self.unknown_far)
        report.append(f"switchable-bank targets called from the fixed bank without a known bank: "
                      f"{len(far)}")
        report += [f"  ${a:04X} from " + ", ".join(f"${x:04X}" for _, x in sorted(self.unknown_far[a]))
                   for a in far[:200]]
        with open(os.path.join(out_dir, "report.txt"), "w") as f:
            f.write("\n".join(report) + "\n")
        return report

    def bank_lines(self, bank):
        lines = [f"; Castlevania (NES), PRG bank {bank} at ${base_of(bank):04X}",
                 "; Disassembled from your own ROM by tools/nes_disasm.py: never commit this file.",
                 "; Labels: sub_ (called), L (jumped to), dat_ (data the code reads);",
                 "; '*' after the address: seen running in the coverage runs.", ""]
        addr = base_of(bank)
        end = addr + BANK
        while addr < end:
            key = (bank, addr)
            is_label = (key in self.refs or key in self.names or key in self.data_names
                        or key in self.data_refs or key in self.tables)
            if is_label:
                lines.append("")
                if key in self.comments:
                    lines.append(f"; {self.comments[key]}")
                refs = sorted(self.refs.get(key, ()))
                if refs:
                    by = ", ".join(f"{self.label(b, a)}" if (b, a) in self.names else
                                   (f"${a:04X}" if b == FIXED else f"{b}:${a:04X}")
                                   for b, a, _ in refs[:8])
                    more = f" (+{len(refs) - 8})" if len(refs) > 8 else ""
                    lines.append(f"; from {by}{more}")
                lines.append(f"{self.label(bank, addr)}:")
            if key in self.code:
                mn, mode, size, arg = self.decode(bank, addr)
                raw = " ".join(f"{self.rom.byte(bank, addr + i):02X}" for i in range(size))
                mark = "*" if key in self.executed else " "
                ops = self.operand(bank, addr, mn, mode, arg)
                comment = ""
                if mode in ("zp", "abs", "zpx", "abx", "aby") and arg in self.ram and \
                        ("ram", arg) in self.comments:
                    comment = f"  ; {self.comments[('ram', arg)]}"
                lines.append(f"  {addr:04X}{mark} {raw:<9} {mn} {ops}".rstrip() + comment)
                addr += size
                if mn in STOP or mn == "jmp":
                    lines.append("")
                continue
            if key in self.tables:
                for i in range(self.tables[key]):
                    w = self.rom.word(bank, addr)
                    tb = self.target_bank(bank, w, addr if bank == FIXED else None)
                    name = self.label(tb, w) if tb is not None and tb >= 0 else f"${w:04X}"
                    lines.append(f"  {addr:04X}  .word {name}   ; {i}")
                    addr += 2
                continue
            # data: up to 8 bytes, stopping at the next label or code
            n = 0
            while n < 8 and addr + n < end:
                k = (bank, addr + n)
                if n and (k in self.code or k in self.refs or k in self.data_refs
                          or k in self.names or k in self.data_names or k in self.tables):
                    break
                if k in self.code:
                    break
                n += 1
            bs = ", ".join(f"${self.rom.byte(bank, addr + i):02X}" for i in range(n))
            lines.append(f"  {addr:04X}  .byte {bs}")
            addr += n
        return lines


def load_coverage(files):
    cov = set()
    for fn in files:
        for line in open(fn):
            p = line.split()
            if len(p) == 3 and p[0] == "X":
                cov.add((int(p[1]), int(p[2], 16)))
    return cov


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    rom = Rom(sys.argv[1])
    cov = load_coverage(sys.argv[3:])
    d = Disassembly(rom, cov)
    for line in d.write(sys.argv[2]):
        print(line)


if __name__ == "__main__":
    main()

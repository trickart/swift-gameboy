#!/usr/bin/env python3
"""Sum up and print the section sizes of an ELF object/executable (parses the output of llvm-objdump -h)."""
import subprocess
import sys


def section_sizes(objdump: str, path: str) -> dict:
    out = subprocess.run([objdump, '-h', path], capture_output=True, text=True, check=True).stdout
    sizes = {}
    for line in out.splitlines():
        p = line.split()
        if len(p) >= 3 and p[1].startswith('.'):
            name = p[1]
            try:
                size = int(p[2], 16)
            except ValueError:
                continue
            if name.startswith('.rela') or name in ('.strtab', '.symtab', '.shstrtab'):
                continue
            key = '.text' if name.startswith('.text') else '.rodata' if name.startswith('.rodata') else name
            sizes[key] = sizes.get(key, 0) + size
    return sizes


def main():
    objdump, path = sys.argv[1], sys.argv[2]
    label = sys.argv[3] if len(sys.argv) > 3 else path
    s = section_sizes(objdump, path)
    print(f"{label}: text={s.get('.text', 0):6d} rodata={s.get('.rodata', 0):5d} "
          f"data={s.get('.data', 0):4d} bss={s.get('.bss', 0):4d}")


if __name__ == '__main__':
    main()

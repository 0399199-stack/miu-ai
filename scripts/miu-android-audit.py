"""Check every packaged ELF LOAD segment for Android 16 KB compatibility."""
import struct
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as apk:
    libraries = [name for name in apk.namelist() if name.startswith('lib/') and name.endswith('.so')]
    if not libraries:
        raise SystemExit('No native libraries found')
    for name in libraries:
        data = apk.read(name)
        assert data[:4] == b'\x7fELF' and data[4:6] == b'\x02\x01', name
        phoff = struct.unpack_from('<Q', data, 32)[0]
        phsize, phnum = struct.unpack_from('<HH', data, 54)
        aligns = []
        for i in range(phnum):
            entry = struct.unpack_from('<IIQQQQQQ', data, phoff + i * phsize)
            if entry[0] == 1:
                aligns.append(entry[7])
                assert entry[7] >= 16384, f'{name}: LOAD alignment {entry[7]}'
                assert (entry[2] - entry[3]) % 16384 == 0, f'{name}: unaligned LOAD offset'
        assert aligns, name
        print(f'{name}: PASS {aligns}')

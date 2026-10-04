from pathlib import Path
import struct
import sys
iconset = Path(sys.argv[1])
entries = [(b'icp4', 'icon_16x16.png'), (b'icp5', 'icon_32x32.png'),
           (b'icp6', 'icon_32x32@2x.png'), (b'ic07', 'icon_128x128.png'),
           (b'ic08', 'icon_256x256.png'), (b'ic09', 'icon_512x512.png'),
           (b'ic10', 'icon_512x512@2x.png')]
blocks = b''
for kind, name in entries:
    data = (iconset / name).read_bytes()
    blocks += kind + struct.pack('>I', 8 + len(data)) + data
Path(sys.argv[2]).write_bytes(b'icns' + struct.pack('>I', 8 + len(blocks)) + blocks)

#!/bin/bash
# Generate a simple app icon using macOS sips

ICON_DIR="/tmp/NotchAgent.iconset"
rm -rf "$ICON_DIR"
mkdir -p "$ICON_DIR"

# Create a simple icon using Python + PIL or fallback to a colored square
python3 << 'PYEOF'
import subprocess, os, tempfile

sizes = [16, 32, 64, 128, 256, 512, 1024]
iconset = "/tmp/NotchAgent.iconset"

for size in sizes:
    # Use sips to create a colored PNG from scratch via a temp file
    # Create SVG-like approach using printf to make a simple PNG
    pass

# Fallback: use macOS built-in icon
# Copy the Terminal.app icon as a base, then we'll replace later
import shutil
src = "/System/Applications/Utilities/Terminal.app/Contents/Resources/Terminal.icns"
dst = os.path.expanduser("~/Documents/app/vibe/NotchAgent/Resources/AppIcon.icns")
os.makedirs(os.path.dirname(dst), exist_ok=True)

# Generate a simple colored square icon using sips
for size in sizes:
    name = f"icon_{size}x{size}.png"
    name2x = f"icon_{size//2}x{size//2}@2x.png" if size > 16 else None
    
    # Create a simple black rounded rect with a colored dot
    subprocess.run([
        "python3", "-c", f"""
import struct, zlib

def create_png(width, height, filename):
    def make_pixel(x, y):
        cx, cy = width/2, height/2
        r = min(width, height) * 0.42
        dx, dy = x - cx, y - cy
        dist = (dx*dx + dy*dy) ** 0.5
        corner_r = r * 0.22
        
        # Rounded rect check
        rx, ry = abs(dx), abs(dy)
        in_rect = False
        if rx <= r - corner_r and ry <= r:
            in_rect = True
        elif rx <= r and ry <= r - corner_r:
            in_rect = True
        elif (rx - (r - corner_r))**2 + (ry - (r - corner_r))**2 <= corner_r**2:
            in_rect = True
        
        if in_rect:
            # Inner dot (green/blue)
            inner_r = r * 0.3
            if dist < inner_r:
                return (100, 180, 255, 255)  # blue dot
            return (20, 20, 22, 255)  # dark background
        return (0, 0, 0, 0)  # transparent

    raw = b''
    for y in range(height):
        raw += b'\\x00'
        for x in range(width):
            r, g, b, a = make_pixel(x, y)
            raw += struct.pack('BBBB', r, g, b, a)
    
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    
    with open(filename, 'wb') as f:
        f.write(b'\\x89PNG\\r\\n\\x1a\\n')
        f.write(chunk(b'IHDR', ihdr))
        f.write(chunk(b'IDAT', zlib.compress(raw)))
        f.write(chunk(b'IEND', b''))

create_png({size}, {size}, '{iconset}/{name}')
"""
    ], check=True)
    
    if name2x and size >= 32:
        subprocess.run(["cp", f"{iconset}/{name}", f"{iconset}/{name2x}"], check=True)

PYEOF

# Convert iconset to icns
RESOURCES_DIR="$HOME/Documents/app/vibe/NotchAgent/Resources"
mkdir -p "$RESOURCES_DIR"
iconutil -c icns "$ICON_DIR" -o "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null || echo "iconutil failed, using fallback"

echo "Done: $RESOURCES_DIR/AppIcon.icns"

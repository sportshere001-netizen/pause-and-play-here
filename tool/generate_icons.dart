import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() {
  Directory('assets').createSync(recursive: true);
  Directory('windows/runner/resources').createSync(recursive: true);

  // 1. Generate 512x512 PNG for Microsoft Store MSIX
  final png512 = encodePng(renderLogo(512), 512, 512);
  File('assets/logo.png').writeAsBytesSync(png512);
  stdout.writeln('Created assets/logo.png (512x512)');

  // 2. Generate multi-size Windows .ico (16, 32, 48, 64 as 32-bit BMP + 256 as PNG)
  final icoSizes = [16, 32, 48, 64, 256];
  final entries = <Uint8List>[];
  for (final s in icoSizes) {
    final rgba = renderLogo(s);
    entries.add(s == 256 ? encodePng(rgba, s, s) : encodeIcoBmp(rgba, s));
  }
  final icoBytes = buildIcoFile(icoSizes, entries);
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(icoBytes);
  stdout.writeln('Updated windows/runner/resources/app_icon.ico');
}

Uint8List renderLogo(int size) {
  final out = Uint8List(size * size * 4);
  const samples = 3; // 3x3 anti-aliasing

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      double rAcc = 0, gAcc = 0, bAcc = 0, aAcc = 0;
      for (int sy = 0; sy < samples; sy++) {
        for (int sx = 0; sx < samples; sx++) {
          final u = (x + (sx + 0.5) / samples) / size;
          final v = (y + (sy + 0.5) / samples) / size;

          // Rounded square badge
          if (roundedRectSdf(u, v, 0.03, 0.03, 0.97, 0.97, 0.22) <= 0) {
            final t = ((u + v) * 0.5).clamp(0.0, 1.0);
            double r, g, b;
            if (t < 0.5) {
              final k = t * 2.0;
              r = 0;
              g = 229 + (149 - 229) * k;
              b = 195 + (217 - 195) * k;
            } else {
              final k = (t - 0.5) * 2.0;
              r = 0 + (21 - 0) * k;
              g = 149 + (69 - 149) * k;
              b = 217 + (199 - 217) * k;
            }

            // Two white rounded Pause bars + white Play triangle
            final inBar1 =
                roundedRectSdf(u, v, 0.20, 0.28, 0.305, 0.72, 0.045) <= 0;
            final inBar2 =
                roundedRectSdf(u, v, 0.34, 0.28, 0.445, 0.72, 0.045) <= 0;
            final inPlay = inTriangle(u, v, 0.53, 0.27, 0.82, 0.50, 0.53, 0.73);

            if (inBar1 || inBar2 || inPlay) {
              r = 255;
              g = 255;
              b = 255;
            }
            rAcc += r;
            gAcc += g;
            bAcc += b;
            aAcc += 255;
          }
        }
      }
      final idx = (y * size + x) * 4;
      final total = samples * samples;
      final alpha = (aAcc / total).round().clamp(0, 255);
      if (alpha > 0) {
        out[idx] = (rAcc / (aAcc / 255)).round().clamp(0, 255);
        out[idx + 1] = (gAcc / (aAcc / 255)).round().clamp(0, 255);
        out[idx + 2] = (bAcc / (aAcc / 255)).round().clamp(0, 255);
        out[idx + 3] = alpha;
      }
    }
  }
  return out;
}

double roundedRectSdf(
    double px, double py, double x0, double y0, double x1, double y1, double r) {
  final cx = (x0 + x1) * 0.5;
  final cy = (y0 + y1) * 0.5;
  final hx = (x1 - x0) * 0.5 - r;
  final hy = (y1 - y0) * 0.5 - r;
  final dx = (px - cx).abs() - hx;
  final dy = (py - cy).abs() - hy;
  final outside = sqrt(max(dx, 0.0) * max(dx, 0.0) + max(dy, 0.0) * max(dy, 0.0));
  final inside = min(max(dx, dy), 0.0);
  return outside + inside - r;
}

bool inTriangle(double px, double py, double ax, double ay, double bx, double by,
    double cx, double cy) {
  double s(double x1, double y1, double x2, double y2, double x3, double y3) =>
      (x1 - x3) * (y2 - y3) - (x2 - x3) * (y1 - y3);
  final d1 = s(px, py, ax, ay, bx, by);
  final d2 = s(px, py, bx, by, cx, cy);
  final d3 = s(px, py, cx, cy, ax, ay);
  return !(((d1 < 0) || (d2 < 0) || (d3 < 0)) && ((d1 > 0) || (d2 > 0) || (d3 > 0)));
}

Uint8List encodeIcoBmp(Uint8List rgba, int size) {
  final andRowBytes = ((size + 31) ~/ 32) * 4;
  final xorBytes = size * size * 4;
  final andBytes = andRowBytes * size;
  final buf = ByteData(40 + xorBytes + andBytes);
  buf.setUint32(0, 40, Endian.little);
  buf.setInt32(4, size, Endian.little);
  buf.setInt32(8, size * 2, Endian.little); // XOR + AND height
  buf.setUint16(12, 1, Endian.little);
  buf.setUint16(14, 32, Endian.little);
  buf.setUint32(20, xorBytes, Endian.little);

  int offset = 40;
  for (int y = size - 1; y >= 0; y--) {
    for (int x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      buf.setUint8(offset++, rgba[i + 2]); // B
      buf.setUint8(offset++, rgba[i + 1]); // G
      buf.setUint8(offset++, rgba[i]);     // R
      buf.setUint8(offset++, rgba[i + 3]); // A
    }
  }
  return buf.buffer.asUint8List();
}

Uint8List buildIcoFile(List<int> sizes, List<Uint8List> images) {
  final headerSize = 6 + sizes.length * 16;
  int totalSize = headerSize;
  for (final img in images) {
    totalSize += img.length;
  }
  final out = Uint8List(totalSize);
  final bd = ByteData.view(out.buffer);
  bd.setUint16(0, 0, Endian.little);
  bd.setUint16(2, 1, Endian.little);
  bd.setUint16(4, sizes.length, Endian.little);

  int dataOffset = headerSize;
  for (int i = 0; i < sizes.length; i++) {
    final entryOffset = 6 + i * 16;
    final dim = sizes[i] >= 256 ? 0 : sizes[i];
    out[entryOffset] = dim;
    out[entryOffset + 1] = dim;
    bd.setUint16(entryOffset + 4, 1, Endian.little);
    bd.setUint16(entryOffset + 6, 32, Endian.little);
    bd.setUint32(entryOffset + 8, images[i].length, Endian.little);
    bd.setUint32(entryOffset + 12, dataOffset, Endian.little);
    out.setRange(dataOffset, dataOffset + images[i].length, images[i]);
    dataOffset += images[i].length;
  }
  return out;
}

Uint8List encodePng(Uint8List rgba, int width, int height) {
  final raw = BytesBuilder();
  for (int y = 0; y < height; y++) {
    raw.addByte(0);
    final start = y * width * 4;
    raw.add(rgba.sublist(start, start + width * 4));
  }
  final compressed = Uint8List.fromList(zlib.encode(raw.toBytes()));
  final ihdr = ByteData(13)
    ..setUint32(0, width, Endian.big)
    ..setUint32(4, height, Endian.big)
    ..setUint8(8, 8)
    ..setUint8(9, 6);

  final png = BytesBuilder()
    ..add([137, 80, 78, 71, 13, 10, 26, 10])
    ..add(_pngChunk('IHDR', ihdr.buffer.asUint8List()))
    ..add(_pngChunk('IDAT', compressed))
    ..add(_pngChunk('IEND', Uint8List(0)));
  return png.toBytes();
}

Uint8List _pngChunk(String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  final crcInput = BytesBuilder()..add(typeBytes)..add(data);
  final out = BytesBuilder();
  final len = ByteData(4)..setUint32(0, data.length, Endian.big);
  final crc = ByteData(4)..setUint32(0, _crc32(crcInput.toBytes()), Endian.big);
  out..add(len.buffer.asUint8List())..add(typeBytes)..add(data)..add(crc.buffer.asUint8List());
  return out.toBytes();
}

int _crc32(Uint8List bytes) {
  int crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (int k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : (crc >>> 1);
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

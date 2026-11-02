#include "vtf.hpp"

#include <algorithm>
#include <cstring>

namespace zmv {

namespace {

enum Format : int32_t {
    RGBA8888 = 0, ABGR8888 = 1, RGB888 = 2, BGR888 = 3, RGB565 = 4, I8 = 5, IA88 = 6, P8 = 7, A8 = 8,
    RGB888_BLUESCREEN = 9, BGR888_BLUESCREEN = 10, ARGB8888 = 11, BGRA8888 = 12, DXT1 = 13, DXT3 = 14, DXT5 = 15,
    BGRX8888 = 16, BGR565 = 17, BGRX5551 = 18, BGRA4444 = 19, DXT1_ONEBITALPHA = 20, BGRA5551 = 21,
    UV88 = 22, UVWQ8888 = 23, RGBA16161616F = 24, RGBA16161616 = 25,
};

constexpr uint32_t kFlagEnvmap = 0x4000;

int BytesPerPixel(int32_t f) {
    switch (f) {
        case RGBA8888: case ABGR8888: case ARGB8888: case BGRA8888: case BGRX8888: case UVWQ8888: return 4;
        case RGB888: case BGR888: case RGB888_BLUESCREEN: case BGR888_BLUESCREEN: return 3;
        case RGB565: case IA88: case BGR565: case BGRX5551: case BGRA4444: case BGRA5551: case UV88: return 2;
        case I8: case P8: case A8: return 1;
        case RGBA16161616F: case RGBA16161616: return 8;
        default: return 0;
    }
}

bool IsDxt(int32_t f) { return f == DXT1 || f == DXT1_ONEBITALPHA || f == DXT3 || f == DXT5; }

size_t MipBytes(int32_t f, int w, int h) {
    w = std::max(1, w);
    h = std::max(1, h);
    if (IsDxt(f)) {
        const size_t blocks = static_cast<size_t>((w + 3) / 4) * static_cast<size_t>((h + 3) / 4);
        return blocks * ((f == DXT1 || f == DXT1_ONEBITALPHA) ? 8 : 16);
    }
    return static_cast<size_t>(w) * h * BytesPerPixel(f);
}

template <typename T>
T ReadAt(const std::string& s, size_t offset) {
    T v{};
    if (offset + sizeof(T) <= s.size()) std::memcpy(&v, s.data() + offset, sizeof(T));
    return v;
}

void Expand565(uint16_t c, uint8_t out[3]) {
    out[0] = static_cast<uint8_t>(((c >> 11) & 31) * 255 / 31);
    out[1] = static_cast<uint8_t>(((c >> 5) & 63) * 255 / 63);
    out[2] = static_cast<uint8_t>((c & 31) * 255 / 31);
}

void DecodeDxt(const uint8_t* src, int32_t f, int w, int h, uint8_t* dst) {
    const int bw = (w + 3) / 4, bh = (h + 3) / 4;
    const bool dxt1 = f == DXT1 || f == DXT1_ONEBITALPHA;
    for (int by = 0; by < bh; ++by) {
        for (int bx = 0; bx < bw; ++bx) {
            uint8_t alpha[16];
            std::fill(alpha, alpha + 16, 255);
            const uint8_t* color = src;
            if (f == DXT3) {
                for (int i = 0; i < 16; ++i) {
                    const int nib = (src[i / 2] >> ((i & 1) * 4)) & 15;
                    alpha[i] = static_cast<uint8_t>(nib * 17);
                }
                color = src + 8;
            } else if (f == DXT5) {
                uint8_t a[8];
                a[0] = src[0];
                a[1] = src[1];
                if (a[0] > a[1]) {
                    for (int i = 1; i < 7; ++i) a[i + 1] = static_cast<uint8_t>(((7 - i) * a[0] + i * a[1]) / 7);
                } else {
                    for (int i = 1; i < 5; ++i) a[i + 1] = static_cast<uint8_t>(((5 - i) * a[0] + i * a[1]) / 5);
                    a[6] = 0;
                    a[7] = 255;
                }
                uint64_t bits = 0;
                for (int i = 0; i < 6; ++i) bits |= static_cast<uint64_t>(src[2 + i]) << (8 * i);
                for (int i = 0; i < 16; ++i) alpha[i] = a[(bits >> (3 * i)) & 7];
                color = src + 8;
            }
            const uint16_t c0 = static_cast<uint16_t>(color[0] | (color[1] << 8));
            const uint16_t c1 = static_cast<uint16_t>(color[2] | (color[3] << 8));
            uint8_t pal[4][4];
            Expand565(c0, pal[0]);
            Expand565(c1, pal[1]);
            pal[0][3] = pal[1][3] = pal[2][3] = pal[3][3] = 255;
            if (c0 > c1 || !dxt1) {
                for (int k = 0; k < 3; ++k) {
                    pal[2][k] = static_cast<uint8_t>((2 * pal[0][k] + pal[1][k]) / 3);
                    pal[3][k] = static_cast<uint8_t>((pal[0][k] + 2 * pal[1][k]) / 3);
                }
            } else {
                for (int k = 0; k < 3; ++k) {
                    pal[2][k] = static_cast<uint8_t>((pal[0][k] + pal[1][k]) / 2);
                    pal[3][k] = 0;
                }
                pal[3][3] = 0;
            }
            const uint32_t idx = static_cast<uint32_t>(color[4]) | (static_cast<uint32_t>(color[5]) << 8) |
                                 (static_cast<uint32_t>(color[6]) << 16) | (static_cast<uint32_t>(color[7]) << 24);
            for (int py = 0; py < 4; ++py) {
                for (int px = 0; px < 4; ++px) {
                    const int x = bx * 4 + px, y = by * 4 + py;
                    if (x >= w || y >= h) continue;
                    const int i = py * 4 + px;
                    const uint8_t* p = pal[(idx >> (2 * i)) & 3];
                    uint8_t* d = dst + (static_cast<size_t>(y) * w + x) * 4;
                    d[0] = p[0];
                    d[1] = p[1];
                    d[2] = p[2];
                    d[3] = dxt1 ? p[3] : alpha[i];
                }
            }
            src += dxt1 ? 8 : 16;
        }
    }
}

bool DecodeLinear(const uint8_t* s, int32_t f, size_t pixels, uint8_t* d) {
    for (size_t i = 0; i < pixels; ++i, d += 4) {
        switch (f) {
            case RGBA8888: d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = s[3]; s += 4; break;
            case ABGR8888: d[0] = s[3]; d[1] = s[2]; d[2] = s[1]; d[3] = s[0]; s += 4; break;
            case ARGB8888: d[0] = s[1]; d[1] = s[2]; d[2] = s[3]; d[3] = s[0]; s += 4; break;
            case BGRA8888: d[0] = s[2]; d[1] = s[1]; d[2] = s[0]; d[3] = s[3]; s += 4; break;
            case BGRX8888: d[0] = s[2]; d[1] = s[1]; d[2] = s[0]; d[3] = 255; s += 4; break;
            case RGB888: case RGB888_BLUESCREEN: d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = 255; s += 3; break;
            case BGR888: case BGR888_BLUESCREEN: d[0] = s[2]; d[1] = s[1]; d[2] = s[0]; d[3] = 255; s += 3; break;
            case I8: d[0] = d[1] = d[2] = s[0]; d[3] = 255; s += 1; break;
            case A8: d[0] = d[1] = d[2] = 255; d[3] = s[0]; s += 1; break;
            case IA88: d[0] = d[1] = d[2] = s[0]; d[3] = s[1]; s += 2; break;
            case RGB565: case BGR565: {
                uint8_t c[3];
                Expand565(static_cast<uint16_t>(s[0] | (s[1] << 8)), c);
                // BGR565 (like DXT endpoints) keeps red in the high bits; RGB565 keeps it in the low bits.
                if (f == RGB565) { d[0] = c[2]; d[1] = c[1]; d[2] = c[0]; }
                else { d[0] = c[0]; d[1] = c[1]; d[2] = c[2]; }
                d[3] = 255;
                s += 2;
                break;
            }
            case BGRA4444: {
                const uint16_t v = static_cast<uint16_t>(s[0] | (s[1] << 8));
                d[2] = static_cast<uint8_t>((v & 15) * 17);
                d[1] = static_cast<uint8_t>(((v >> 4) & 15) * 17);
                d[0] = static_cast<uint8_t>(((v >> 8) & 15) * 17);
                d[3] = static_cast<uint8_t>(((v >> 12) & 15) * 17);
                s += 2;
                break;
            }
            case BGRX5551: case BGRA5551: {
                const uint16_t v = static_cast<uint16_t>(s[0] | (s[1] << 8));
                d[2] = static_cast<uint8_t>((v & 31) * 255 / 31);
                d[1] = static_cast<uint8_t>(((v >> 5) & 31) * 255 / 31);
                d[0] = static_cast<uint8_t>(((v >> 10) & 31) * 255 / 31);
                d[3] = (f == BGRA5551 && !(v >> 15)) ? 0 : 255;
                s += 2;
                break;
            }
            default: return false;
        }
    }
    return true;
}

bool Fail(std::string* why, const char* reason) {
    if (why) *why = reason;
    return false;
}

}  // namespace

bool LoadVtf(const GameFileSystem& fs, const std::string& path, int targetSize, VtfImage& out, std::string* why) {
    std::string head;
    if (!fs.Read(path, head, 4096)) return Fail(why, "missing");
    if (head.size() < 64 || std::memcmp(head.data(), "VTF\0", 4) != 0) return Fail(why, "not a VTF");
    const uint32_t major = ReadAt<uint32_t>(head, 4);
    const uint32_t minor = ReadAt<uint32_t>(head, 8);
    if (major != 7) return Fail(why, "unsupported version");
    const uint32_t headerSize = ReadAt<uint32_t>(head, 12);
    const int width = ReadAt<uint16_t>(head, 16);
    const int height = ReadAt<uint16_t>(head, 18);
    const uint32_t flags = ReadAt<uint32_t>(head, 20);
    const int frames = std::max<int>(1, ReadAt<uint16_t>(head, 24));
    const int32_t format = ReadAt<int32_t>(head, 52);
    const int mipCount = std::max<int>(1, static_cast<uint8_t>(head[56]));
    const int32_t lowFormat = ReadAt<int32_t>(head, 57);
    const int lowW = static_cast<uint8_t>(head[61]);
    const int lowH = static_cast<uint8_t>(head[62]);
    const int depth = minor >= 2 ? std::max<int>(1, ReadAt<uint16_t>(head, 63)) : 1;
    if (width <= 0 || height <= 0) return Fail(why, "empty");
    if (flags & kFlagEnvmap) return Fail(why, "envmap");
    if (!IsDxt(format) && BytesPerPixel(format) == 0) return Fail(why, "unsupported format");
    if (format == P8 || format == UV88 || format == UVWQ8888 || format == RGBA16161616F || format == RGBA16161616)
        return Fail(why, "unsupported format");

    size_t dataOffset = 0;
    if (minor >= 3) {
        const uint32_t resources = ReadAt<uint32_t>(head, 68);
        bool found = false;
        for (uint32_t i = 0; i < resources && 80 + i * 8 + 8 <= head.size(); ++i) {
            const size_t e = 80 + i * 8;
            if (static_cast<uint8_t>(head[e]) == 0x30 && head[e + 1] == 0 && head[e + 2] == 0) {
                dataOffset = ReadAt<uint32_t>(head, e + 4);
                found = true;
                break;
            }
        }
        if (!found) return Fail(why, "no image resource");
    } else {
        dataOffset = headerSize + ((lowFormat >= 0 && lowW > 0 && lowH > 0) ? MipBytes(lowFormat, lowW, lowH) : 0);
    }

    int level = 0;
    while (level + 1 < mipCount && std::max(width >> (level + 1), height >> (level + 1)) >= targetSize) ++level;
    // Mips are stored smallest first; each mip holds frames x faces(1) x slices.
    size_t offset = dataOffset;
    for (int m = mipCount - 1; m > level; --m) {
        offset += MipBytes(format, width >> m, height >> m) * frames * depth;
    }
    const int w = std::max(1, width >> level), h = std::max(1, height >> level);
    const size_t bytes = MipBytes(format, w, h);
    std::string data;
    if (!fs.Read(path, data, offset + bytes) || data.size() < offset + bytes) return Fail(why, "truncated");

    out.width = w;
    out.height = h;
    out.fullWidth = width;
    out.fullHeight = height;
    out.rgba.assign(static_cast<size_t>(w) * h * 4, 255);
    const uint8_t* src = reinterpret_cast<const uint8_t*>(data.data() + offset);
    if (IsDxt(format)) {
        DecodeDxt(src, format, w, h, out.rgba.data());
        return true;
    }
    if (!DecodeLinear(src, format, static_cast<size_t>(w) * h, out.rgba.data())) return Fail(why, "decode");
    return true;
}

}  // namespace zmv

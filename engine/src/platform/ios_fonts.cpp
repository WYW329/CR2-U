#include "platform/ios_fonts.hpp"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreText/CoreText.h>

#include <SDL3/SDL.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <vector>

namespace crios {
namespace {
void put32(std::vector<uint8_t>& b, size_t at, uint32_t v) {
    b[at] = uint8_t(v >> 24), b[at + 1] = uint8_t(v >> 16), b[at + 2] = uint8_t(v >> 8), b[at + 3] = uint8_t(v);
}
void put16(std::vector<uint8_t>& b, size_t at, uint16_t v) { b[at] = uint8_t(v >> 8), b[at + 1] = uint8_t(v); }
uint32_t checksum(const uint8_t* p, size_t n) {
    uint32_t sum = 0;
    for (size_t k = 0; k < n; k += 4) {
        uint32_t w = 0;
        for (size_t j = 0; j < 4; ++j) w = (w << 8) | (k + j < n ? p[k + j] : 0);
        sum += w;
    }
    return sum;
}
} // namespace

std::string systemFontFile(const char* postScriptName, const std::string& cacheDir) {
    std::string out = cacheDir + postScriptName + ".otf";
    if (SDL_GetPathInfo(out.c_str(), nullptr)) return out; // (an earlier start's)
    CFStringRef name = CFStringCreateWithCString(nullptr, postScriptName, kCFStringEncodingUTF8);
    if (!name) return {};
    CTFontRef font = CTFontCreateWithName(name, 12.0, nullptr);
    CFRelease(name);
    if (!font) return {};
    // (an unknown name gets a substitute: only the asked-for face is taken)
    bool same = false;
    if (CFStringRef got = CTFontCopyPostScriptName(font)) {
        char buf[256] = {};
        CFStringGetCString(got, buf, sizeof buf, kCFStringEncodingUTF8);
        same = std::string(buf) == postScriptName;
        CFRelease(got);
    }
    CFArrayRef tags = same ? CTFontCopyAvailableTables(font, kCTFontTableOptionNoOptions) : nullptr;
    if (!tags) {
        CFRelease(font);
        SDL_Log("font: iOS has no %s", postScriptName);
        return {};
    }
    struct Table {
        uint32_t tag;
        CFDataRef data;
    };
    std::vector<Table> tables;
    bool cff = false;
    for (CFIndex k = 0; k < CFArrayGetCount(tags); ++k) {
        const uint32_t tag = uint32_t(uintptr_t(CFArrayGetValueAtIndex(tags, k)));
        if (CFDataRef d = CTFontCopyTable(font, tag, kCTFontTableOptionNoOptions)) {
            tables.push_back({tag, d});
            cff |= tag == 'CFF ' || tag == 'CFF2';
        }
    }
    CFRelease(tags);
    CFRelease(font);
    if (tables.empty()) return {};
    // the sfnt: its header, the directory (tags ascending), each table 4-aligned
    std::sort(tables.begin(), tables.end(), [](const Table& a, const Table& b) { return a.tag < b.tag; });
    const uint16_t n = uint16_t(tables.size());
    uint16_t pow2 = 1, log2 = 0;
    while (pow2 * 2 <= n) pow2 *= 2, ++log2;
    std::vector<uint8_t> b(12 + 16 * size_t(n), 0);
    put32(b, 0, cff ? 0x4F54544Fu : 0x00010000u); // ('OTTO' or TrueType)
    put16(b, 4, n), put16(b, 6, uint16_t(pow2 * 16)), put16(b, 8, log2), put16(b, 10, uint16_t(n * 16 - pow2 * 16));
    for (size_t k = 0; k < tables.size(); ++k) {
        const uint8_t* p = CFDataGetBytePtr(tables[k].data);
        const size_t len = size_t(CFDataGetLength(tables[k].data));
        const size_t at = b.size();
        b.insert(b.end(), p, p + len);
        b.resize((b.size() + 3) & ~size_t(3), 0);
        const size_t e = 12 + 16 * k;
        put32(b, e, tables[k].tag), put32(b, e + 4, checksum(p, len)), put32(b, e + 8, uint32_t(at)), put32(b, e + 12, uint32_t(len));
        CFRelease(tables[k].data);
    }
    SDL_CreateDirectory(cacheDir.c_str());
    const std::string tmp = out + ".part";
    std::FILE* f = std::fopen(tmp.c_str(), "wb");
    if (!f) return {};
    const bool ok = std::fwrite(b.data(), 1, b.size(), f) == b.size();
    std::fclose(f);
    if (!ok || !SDL_RenamePath(tmp.c_str(), out.c_str())) return {};
    SDL_Log("font: %s from iOS (%zu tables, %zu bytes)", postScriptName, tables.size(), b.size());
    return out;
}
} // namespace crios

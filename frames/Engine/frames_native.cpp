#include "frames_native.h"
#include <cstdio>
#include <cstring>

int frames_probe_container_type(const char *path) {
    if (!path) return -1;
    FILE *f = std::fopen(path, "rb");
    if (!f) return -1;
    unsigned char header[16];
    size_t n = std::fread(header, 1, 16, f);
    std::fclose(f);
    if (n < 4) return -1;
    // EBML Header: 0x1A 0x45 0xDF 0xA3
    if (header[0] == 0x1A && header[1] == 0x45 && header[2] == 0xDF && header[3] == 0xA3) {
        return 0; // matroska
    }
    // ISO BMFF: bytes 4..<8 are 'ftyp', 'moov', etc.
    if (n >= 8) {
        char fourcc[5] = { (char)header[4], (char)header[5], (char)header[6], (char)header[7], 0 };
        if (std::strcmp(fourcc, "ftyp") == 0 || std::strcmp(fourcc, "moov") == 0 ||
            std::strcmp(fourcc, "wide") == 0 || std::strcmp(fourcc, "mdat") == 0 ||
            std::strcmp(fourcc, "free") == 0 || std::strcmp(fourcc, "skip") == 0 ||
            std::strcmp(fourcc, "styp") == 0) {
            return 1; // mp4
        }
    }
    // Fallback to extension
    const char *dot = std::strrchr(path, '.');
    if (dot) {
        if (strcasecmp(dot, ".mkv") == 0 || strcasecmp(dot, ".webm") == 0 ||
            strcasecmp(dot, ".mka") == 0) return 0;
        if (strcasecmp(dot, ".mp4") == 0 || strcasecmp(dot, ".mov") == 0 ||
            strcasecmp(dot, ".m4v") == 0) return 1;
    }
    return -1;
}

void frames_fast_copy(void *dst, const void *src, size_t n) {
    if (!dst || !src || n == 0) return;
    std::memcpy(dst, src, n);
}

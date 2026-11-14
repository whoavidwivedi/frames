#ifndef FRAMES_NATIVE_H
#define FRAMES_NATIVE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns 0 = matroska, 1 = mp4, -1 = unknown
int frames_probe_container_type(const char *path);

// Zero-copy-ish fast memcpy for hot paths (uses restrict + prefetch hints)
void frames_fast_copy(void *dst, const void *src, size_t n);

#ifdef __cplusplus
}
#endif

#endif

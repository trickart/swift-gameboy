/* swift-gameboy: minimal C runtime required by Embedded Swift (for SM83)
 *
 * Embedded Swift's heap allocations bottom out in posix_memalign / free.
 * This file provides a first-fit allocator over __heap_start..__heap_end in WRAM.
 */
#include <stddef.h>
#include <stdint.h>

extern char _heap_start[];   /* __heap_start from the linker script */
extern char _heap_end[];     /* __heap_end from the linker script   */

/* Block header: 2 bytes. size is the byte count including the header (even), bit0 = in use */
typedef uint16_t hdr_t;
#define HDR_SIZE  ((size_t)sizeof(hdr_t))
#define USED      ((hdr_t)1)
#define BLK_SIZE(h) ((size_t)(*(h) & ~USED))
#define NEXT(h)   ((hdr_t *)((char *)(h) + BLK_SIZE(h)))

static hdr_t *heap_begin;
static hdr_t *heap_limit;
static uint8_t heap_ready;

static void heap_init(void) {
  heap_begin = (hdr_t *)_heap_start;
  heap_limit = (hdr_t *)_heap_end;
  *heap_begin = (hdr_t)((char *)heap_limit - (char *)heap_begin);
  heap_ready = 1;
}

void *malloc(size_t size) {
  if (!heap_ready) heap_init();
  size_t need = (size + HDR_SIZE + 1) & ~(size_t)1;
  if (need < HDR_SIZE + 2) need = HDR_SIZE + 2;
  hdr_t *h = heap_begin;
  while (h < heap_limit) {
    if (!(*h & USED)) {
      /* Coalesce following free blocks */
      hdr_t *n = NEXT(h);
      while (n < heap_limit && !(*n & USED)) {
        *h = (hdr_t)(BLK_SIZE(h) + BLK_SIZE(n));
        n = NEXT(h);
      }
      size_t avail = BLK_SIZE(h);
      if (avail >= need) {
        if (avail - need >= HDR_SIZE + 2) {
          hdr_t *rest = (hdr_t *)((char *)h + need);
          *rest = (hdr_t)(avail - need);
          *h = (hdr_t)need;
        }
        *h |= USED;
        return (char *)h + HDR_SIZE;
      }
    }
    h = NEXT(h);
  }
  return NULL;
}

void free(void *p) {
  if (!p) return;
  hdr_t *h = (hdr_t *)((char *)p - HDR_SIZE);
  *h &= (hdr_t)~USED;
}

void *calloc(size_t n, size_t sz) {
  size_t total = n * sz;
  char *p = (char *)malloc(total);
  if (p) for (size_t i = 0; i < total; i++) p[i] = 0;
  return p;
}

void *realloc(void *p, size_t size) {
  if (!p) return malloc(size);
  hdr_t *h = (hdr_t *)((char *)p - HDR_SIZE);
  size_t old = BLK_SIZE(h) - HDR_SIZE;
  if (old >= size) return p;
  char *np = (char *)malloc(size);
  if (!np) return NULL;
  for (size_t i = 0; i < old; i++) np[i] = ((char *)p)[i];
  free(p);
  return np;
}

/* Receives Swift's alignMask+1. SM83 has no alignment requirements; since the header is
 * 2 bytes the returned address is always even, so alignments up to 2 are satisfied naturally. */
int posix_memalign(void **out, size_t align, size_t size) {
  (void)align;
  void *p = malloc(size);
  if (!p) return 12; /* ENOMEM */
  *out = p;
  return 0;
}

/* Free heap space (for debugging). Accessible from Swift as gb_heap_free() */
size_t gb_heap_free(void) {
  if (!heap_ready) heap_init();
  size_t total = 0;
  for (hdr_t *h = heap_begin; h < heap_limit; h = NEXT(h))
    if (!(*h & USED)) total += BLK_SIZE(h) - HDR_SIZE;
  return total;
}

/* ---- Other functions required by the Swift standard library ------------------- */

/* Used to seed Hasher. No cryptographic strength needed on a game console:
 * xorshift seeded from the DIV register */
void arc4random_buf(void *buf, size_t n) {
  static uint16_t state;
  if (state == 0) state = (uint16_t)(*(volatile uint8_t *)0xFF04) | 0x8000u;
  uint8_t *p = (uint8_t *)buf;
  for (size_t i = 0; i < n; i++) {
    state ^= state << 7;
    state ^= state >> 9;
    state ^= state << 8;
    p[i] = (uint8_t)state;
  }
}

/* Rounding for double (built on compiler-rt's soft-float). Valid for |x| < 2^63 */
double floor(double x) {
  long long i = (long long)x;
  double d = (double)i;
  if (d > x) d = d - 1.0;
  return d;
}

double ceil(double x) {
  long long i = (long long)x;
  double d = (double)i;
  if (d < x) d = d + 1.0;
  return d;
}

double trunc(double x) { return (double)(long long)x; }

double fabs(double x) { return x < 0.0 ? -x : x; }

double round(double x) { return x < 0.0 ? ceil(x - 0.5) : floor(x + 0.5); }

/* ---- VRAM access --------------------------------------------------------------
 * While the LCD is on, writes to VRAM are dropped during PPU mode 3 (drawing) (reads return 0xFF).
 * We wait for the STAT mode to become 0 (HBlank) or 1 (VBlank) and write immediately afterwards.
 * Only 2 M-cycles elapse between the check and the write, so even if we leave the loop at the very
 * end of mode 0 the write completes during the following mode 2 (20 M-cycles).
 * If Swift does "wait, then write" itself, too much code runs between the wait and the write, mode 3
 * begins and the write is dropped (missing characters on real hardware and in mGBA). So we provide
 * functions here that do the wait and write together, and Swift calls these. */
#define GB_LCDC (*(volatile uint8_t *)0xFF40)
#define GB_STAT (*(volatile uint8_t *)0xFF41)
#define GB_VRAM_WAIT() while (GB_STAT & 2) {}

void gb_vram_write(uint8_t *p, uint8_t v) {
  GB_VRAM_WAIT();
  *p = v;
}

void gb_vram_fill(uint8_t *p, uint8_t v, uint16_t n) {
  if (GB_LCDC & 0x80) {
    while (n--) { GB_VRAM_WAIT(); *p++ = v; }
  } else {
    while (n--) *p++ = v;
  }
}

void gb_vram_copy(uint8_t *p, const uint8_t *src, uint16_t n) {
  if (GB_LCDC & 0x80) {
    while (n--) { GB_VRAM_WAIT(); *p++ = *src++; }
  } else {
    while (n--) *p++ = *src++;
  }
}

/* Expand 1bpp (8 bytes per tile) to 2bpp (16 bytes) while writing. n is the source byte count */
void gb_vram_copy_1bpp(uint8_t *p, const uint8_t *src, uint16_t n) {
  if (GB_LCDC & 0x80) {
    while (n--) { uint8_t b = *src++; GB_VRAM_WAIT(); *p++ = b; GB_VRAM_WAIT(); *p++ = b; }
  } else {
    while (n--) { uint8_t b = *src++; *p++ = b; *p++ = b; }
  }
}

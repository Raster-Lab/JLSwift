# Performance Tuning

How to get the most out of JLSwift, how to benchmark it honestly, and what the
codec does under the hood. Everything in this document describes shipping
code; measured numbers come from real radiology DICOM data (CT/DX/MG/MR/PX/XA)
and the built-in synthetic benchmark on Apple Silicon.

## TL;DR

- The codec is fast by default — there is nothing to enable for single-image
  encode/decode.
- For **large frames** (e.g. 17 MP mammography), set
  `Configuration.restartInterval` to parallelise a single image across cores.
- For **many files**, use `jpegls batch` (or your own task pool — the encoder
  and decoder are `Sendable` value types, safe to use concurrently).
- Always benchmark release builds: `swift build -c release`.

## What makes the hot path fast

These are the structural properties of the codec, useful to know when
profiling an integration:

1. **Flat scan planes.** Each scan converts to one contiguous `UInt16` plane
   and the whole scan loop runs over an unsafe buffer — no nested-array
   indirection, per-access bounds checks, or copy-on-write traffic per pixel,
   and half the memory bandwidth of boxed `[[Int]]` rows.
2. **64-bit bitstream I/O.** The writer packs bits into a `UInt64` accumulator
   over a pre-reserved `[UInt8]`; the reader refills a 64-bit window several
   bytes at a time (applying the ISO 14495-1 §9.1 stuff-bit rule per byte) and
   decodes Golomb unary prefixes with `leadingZeroBitCount` instead of one
   call per bit.
3. **Init-time gradient tables.** Gradient quantisation (ITU-T.87 Table A.7)
   is a table lookup built once per scan, on both the encode and decode side,
   and each pixel's gradients are quantised exactly once.
4. **Packed context records.** The 365 per-context adaptation statistics
   (A/B/C/N) live in a single record array: one load and one store per pixel,
   with bias correction, Golomb-k, and the k = 0 error-correction term all
   derived from one record read.
5. **Run scanning.** Lossless run detection is an exact-equality scan over the
   row, 4-way unrolled, with no per-element `abs()`.

The public API is unchanged by all of this: pixels in and out are `[[Int]]`,
and encoded streams are byte-identical to previous releases (verified by a
golden-bitstream gate during development).

## Restart-interval parallelism (single large image)

JPEG-LS entropy coding is inherently sequential — each pixel's coding state
depends on every pixel before it — so a single scan cannot be parallelised
without help from the bitstream. Restart markers (DRI/RSTm, ITU-T.87 §C.2.5)
are the standards-compliant way to provide that help: at every interval
boundary the coding state resets exactly as at scan start, which makes the
intervals independently codable.

```swift
// Encode a large frame with one restart interval every 256 lines.
let config = try JPEGLSEncoder.Configuration(restartInterval: 256)
let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)

// Decoding needs no configuration: the DRI segment is in the stream, and the
// decoder splits at the RST markers and decodes the intervals concurrently.
let decoded = try JPEGLSDecoder().decode(encoded)
```

CLI equivalent:

```bash
jpegls encode huge.pgm huge.jls --restart-interval 256
```

Measured on a 4096×4096 16-bit image (Apple Silicon, interval 256, wall
clock including file I/O): encode 0.84 s → 0.31 s, decode 0.69 s → 0.24 s,
at a size cost of about **+0.03 %**.

Notes and trade-offs:

- Each interval restarts the adaptive contexts, so compression ratio drops
  slightly; the cost shrinks as the interval grows. Intervals of 64–512 lines
  are a good range for multi-megapixel frames.
- Currently supported for lossless (NEAR = 0), non-interleaved scans — the
  DICOM grayscale case. The configuration initializer rejects unsupported
  combinations rather than producing a non-parallel stream silently.
- Streams with restart markers are valid JPEG-LS and decode in any conformant
  decoder; conversely JLSwift decodes restart streams produced by other
  encoders (intervals are validated to cycle FFD0–FFD7).
- A side benefit is error resilience: a corrupted interval cannot corrupt the
  decode of subsequent intervals.

## Batch throughput (many files)

`jpegls batch` runs encode/decode/info/verify over a glob or directory with a
worker pool sized to the machine:

```bash
jpegls batch encode "scans/*.pgm" --output-dir encoded/ --parallelism 8
jpegls batch decode "encoded/*.jls" --output-dir decoded/
```

Batch encode output is byte-identical to serial `jpegls encode` of the same
files. In library code, the same effect is one `withTaskGroup` away —
`JPEGLSEncoder` and `JPEGLSDecoder` are stateless `Sendable` structs, so one
instance per task or a shared instance are both safe.

## Benchmarking

Use the built-in benchmark for CPU-bound numbers without file-I/O noise:

```bash
# 16-bit synthetic benchmark (the trustworthy one — see note below)
jpegls benchmark --size 2048 --bits-per-sample 16 --iterations 10 --warmup 3 --json

# Real-data round-trip over a DICOM corpus, grouped by modality
jpegls bench-dicom /path/to/corpus --limit 20
```

Caveats that will save you from misleading numbers:

- **Prefer the 16-bit synthetic benchmark.** The 8-bit gradient image
  compresses ~59:1 and spends most of its time in run mode, which flatters
  run-path changes and hides regular-mode regressions. Real medical data sits
  around 2–6:1.
- `bench-dicom` measures codec time only, but reads files inside the loop —
  run it from a local disk, not cloud-synced storage.
- Benchmark release builds on AC power, and A/B alternate binaries within one
  session to cancel thermal drift.

## Profiling

On macOS, `sample` against a long benchmark run gives a quick hot-function
picture:

```bash
jpegls benchmark --size 2048 --bits-per-sample 16 --iterations 200 &
sample $! 10 -file /tmp/jls-profile.txt
```

For allocation work, Instruments' Allocations template on the same invocation
shows per-scan transients; the codec performs no per-pixel allocations, so
anything hot there is in the integration layer (e.g. converting pixel
formats).

## A note on GPU / SIMD acceleration layers

Earlier releases shipped a `Platform/` layer (Metal, Vulkan, Accelerate,
ARM64/x86-64 SIMD wrappers) advertised as accelerating the codec. Profiling
during the 0.9 optimisation effort showed none of it was invoked on the
encode/decode hot path, and the GPU kernels could not produce conformant
streams: JPEG-LS bias correction and context adaptation make the value being
entropy-coded depend on all previously coded pixels, which is exactly what a
data-parallel kernel cannot see. The layer was removed in favour of the
measured CPU optimisations above; restart intervals are the supported (and
standards-compliant) parallelism mechanism.

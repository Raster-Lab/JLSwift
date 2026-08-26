# JLSwift Optimization Plan

Synthesis of six verified analysis lenses + measured baseline. Scope: pure-Swift JPEG-LS codec (`Sources/JPEGLS`), lossless correctness non-negotiable. All file:line references verified against HEAD (`bcf00eb`).

---

## 1. The performance story

**Where time goes today.** Baseline (release, Apple Silicon): real DICOM encode **26.4 MB/s**, decode **40.1 MB/s** aggregate (CT 21.8/30.8, MG 33.1/53.1); synthetic 16-bit 2048² encode 37.3 MB/s, decode 58.0 MB/s. Optimised native C++ JPEG-LS codecs commonly reach 200–400+ MB/s single-threaded — a 5–10x gap.

The profile (8,482 samples, 150-iteration 16-bit roundtrip; full report was at `/tmp/jlswift-sample.txt`) shows the gap is **Swift mechanics, not JPEG-LS math**:

| Cost | Share | Root cause |
|---|---|---|
| `Array._checkSubscript` | ~15% | `[[Int]]` pixel storage, double bounds checks everywhere |
| Encoder loop body | ~16% | includes per-pixel `getNeighbors` w/ Dictionary lookup + boundary branches |
| Decoder loop body | ~12% | same pattern, plus per-pixel `[[Int]]` writes |
| `updateContext` + CoW checks | ~15% | 4 parallel `[Int]` arrays, uniqueness check per store |
| `quantizeGradient` (decoder, outlined) | ~6.5% | 8-branch chain called 3x/pixel; encoder has a LUT, decoder doesn't |
| `Hasher._hash` + `find` | ~6.5% | `Dictionary<UInt8,[[Int]]>` subscript **per pixel** in the encoder |
| Bitstream read/write leaves | ~6.6% | per-byte Foundation `Data` append/subscript, per-bit unary reads |

Corroboration: a measured `-Ounchecked` A/B gave **+65–85% encode, +35–48% decode** — i.e., checks alone are a third to half the runtime. A writer microbench measured `Data.append(UInt8)` at **38.9 ns/byte vs 0.53 ns** for `[UInt8]` (~70x), against a total per-pixel budget of ~20–120 ns.

**Realistic end state.** Phase 1 (days): ~1.5–2x → real-DICOM encode ~40–55 MB/s. Phase 2 (structural, 1–2 weeks): cumulative 3–6x → **100–200+ MB/s single-threaded**, i.e. the low end of optimised native implementations. Phase 3 adds multicore wall-clock wins (restart-interval stripes, batch parallelism), not single-thread MB/s. The core scanline loop is inherently sequential (causal prediction + adaptive Golomb + run mode); nothing below violates that.

**Invariant for all phases:** every change in Phases 1–2 is representational — it must produce **byte-identical encoded streams and pixel-identical decodes**. Gate every merge on the golden-hash check + bench-dicom lossless round-trip (§6).

---

## 2. Phase 1 — Quick wins (days each, ordered by impact-per-effort)

### W1.1 Bitstream writer: `[UInt8]` backing + 64-bit accumulator
*Merges: encoder/memory/swiftperf writer findings.*
- **Change:** `Sources/JPEGLS/Core/JPEGLSBitstreamWriter.swift:12-14, 125-154, 187-216`. Replace `Data` + `UInt32 bitBuffer` with a pre-reserved `[UInt8]` (capacity already estimated at `JPEGLSEncoder.swift:148-152`) and a `UInt64` accumulator so a whole Golomb code (unary prefix + k-bit remainder) packs in one call. Flush 8 bytes at a time with a single no-0xFF-byte word test, falling back to byte-wise stuffing when 0xFF is present. Convert to `Data` once in `getData()`.
- **Safety:** ISO 14495-1 §9.1 stuffing depends only on each emitted byte being 0xFF (current rule at line 149), so bulk flush gated on the no-0xFF test is bit-exact — verified bit-identical in the microbench. Preserve `endMarkerSegment`'s by-index patch (lines 250-259).
- **Impact:** measured 5.4x ([UInt8] swap alone) to 8.5x (full 64-bit) on the writer path; end-to-end ~1.3–2x encode on poorly-compressing modalities (CT/DX/PX at 2–3.5:1, ~0.5–1 output byte/pixel), single digits at 25:1. The backing-store swap alone captures most of the win if time is short.
- **Verify:** golden encode hashes identical; bench-dicom round-trip; synthetic 16-bit encode MB/s.

### W1.2 Hoist the encoder's per-pixel Dictionary lookup
*Merges: encoder/memory/swiftperf getNeighbors-dictionary findings (minimal version; full neighbor-carrying is W2.2).*
- **Change:** `JPEGLSEncoder.swift:698, 730, 771, 785, 897, 1105, 1139` + `Encoder/JPEGLSPixelBuffer.swift:275-338`. Resolve `componentPixels[componentId]` **once per scan** before the row loop (mirror the decoder, whose private `getNeighbors(pixels: [[Int]], ...)` at `JPEGLSDecoder.swift:1076` already takes the array directly); hoist the current/previous row arrays once per line; kill the per-run `getComponentPixels` lookups at 730/785.
- **Safety:** pure mechanical hoist — identical values read in identical order; component is fixed for the scan.
- **Impact:** removes the ~6.5% Hasher+find cost plus per-pixel ARC retain/release on the returned `[[Int]]`; est. 10–15% encode.
- **Verify:** golden hashes; bench-dicom.

### W1.3 Encoder: quantize gradients once per pixel
- **Change:** `JPEGLSEncoder.swift:721-724` (and 920-923, 1115-1118) compute q1/q2/q3 for the run-entry test; `Encoder/JPEGLSRegularMode.swift:375-384` recomputes them. Add an `encodePixel` overload taking precomputed (q1,q2,q3); have `computeContextIndex` return (index, sign) in one call (`Core/JPEGLSContextModel.swift:161-177`). For near==0, the run-entry test is exactly `a==b && b==c && b==d`.
- **Safety:** identical inputs → identical quantized values; the lossless shortcut equivalence is verified from the table construction (`JPEGLSRegularMode.swift:100-113`).
- **Impact:** release-disassembly confirmed **six** gradient-LUT lookup sequences per pixel (each with an outlined bounds-check call and SIMD register spill/reload) where three suffice; est. 5–15% encode.
- **Verify:** golden hashes; synthetic 16-bit encode.

### W1.4 Decoder: gradient LUT + single computation pass-down
*Merges: decoder triple-quantization + decoder-LUT findings. Calibrated expectation — see Do-NOT #4.*
- **Change:** Port the encoder's init-time `gradientTable` (`Encoder/JPEGLSRegularMode.swift:94-114, 157-163`) into `Decoder/JPEGLSRegularModeDecoder.swift:103-115`, matching the strict-vs-inclusive Table A.7 boundary semantics (verified line-by-line bit-identical by the verifier). Pass q1/q2/q3 (or contextIndex+sign) from the scan-loop run-test (`JPEGLSDecoder.swift:611-614`) into `decodeSinglePixel` (:783-792) and a slimmed `decodePixel` (`JPEGLSRegularModeDecoder.swift:304-313`).
- **Safety:** pure functions of the same (a,b,c,d) and immutable thresholds; LUT semantics verified bit-identical.
- **Impact:** the profile shows `quantizeGradient` as an outlined call at ~6.5% of total; disassembly shows the compiler already CSEs the source-level 9x down to 3 calls — so expect ~5–10% decode, not more.
- **Verify:** golden decoded-pixel hashes against deterministic generated vectors; bench-dicom.

### W1.5 Run-length scan: per-line hoist + word-compare for near==0
- **Change:** `Encoder/JPEGLSRunMode.swift:91-113` scans `[Int]` element-wise with `abs()`. For near==0 scan via `withUnsafeBufferPointer` with plain `!=` / 64-bit word compares against the run value; keep `abs()` only for near>0. Hoist the row slice once per line instead of per run entry (`JPEGLSEncoder.swift:730-738`, 928-936, ~1150-1165).
- **Safety:** `detectRunLength` is pure counting; near==0 is exact equality; buffer immutable during scan. Scan must still extend to true end-of-line (`JPEGLSRunMode.swift:79-84`).
- **Impact:** ~2–6x on the scan itself while rows are still `[Int]` (full SIMD lands with W2.2); end-to-end ~10–20% on background-heavy modalities (MG, collimated CT), ~0 on dense ones.
- **Verify:** golden hashes; bench-dicom per-modality table (watch MG/MR).

### W1.6 Free-wins bundle (each ≤ half a day)
1. **Gate the dead `reconstructed` allocation on `near > 0`** — `JPEGLSEncoder.swift:678-685` allocates+zeroes a full H×W `[[Int]]` (32 MB per 2048² scan, ~136 MB per 17 MP MG frame) that is never read when near==0; the line-interleaved path already guards the identical allocation at :876-879. One-line fix.
2. **Trusted decode-result init** — `JPEGLSDecoder.swift:128-131` runs a full O(W·H) validation pass via `MultiComponentImageData.init` (`Encoder/JPEGLSPixelBuffer.swift:96-113`); decoder output is clamped by construction (`JPEGLSRegularModeDecoder.swift:270`, `JPEGLSRunModeDecoder.swift:188, 272`). Add `init(uncheckedComponents:frameHeader:)` for the decoder only. **Required guards:** add an O(1) parse-time check `MAXVAL <= (1<<P)-1` (LSE currently validated only to [1,65535], `JPEGLSPresetParameters.swift:45`), and do not use the trusted init after `applyMappingTable` (mapping outputs are unbounded, `JPEGLSMappingTable.swift:104-109`).
3. **Parser records scan ranges; delete `extractScanData`** — `JPEGLSParser.swift:203-220` already skips each scan body byte-by-byte; record start/end offsets in `JPEGLSParseResult` and hand the reader the original `Data` + offset, deleting the second full-file walk and copy at `JPEGLSDecoder.swift:170-235`. Both passes implement the identical §9.1 boundary rule, so offsets are byte-identical. Note the reader indexes from 0 — pass a base offset or rebased slice. ~3–10% decode at 2–3:1 ratios.

### W1.7 `-Ounchecked` diagnostic build (not a ship item)
- **Change:** none to the manifest. Document `swift build -c release -Xswiftc -Ounchecked` (with the git workaround, §6) as an opt-in measurement mode in a Makefile/CI variant.
- **Why:** measured +35–85%; it is the *upper bound* for what bounds/overflow-check elimination via `withUnsafeBufferPointer` (W2.2) can recover safely. Re-run after each phase-2 item — when the gap between `-O` and `-Ounchecked` collapses, the structural work is done.
- **Never ship it as default:** converts overflow traps to UB; this codebase had a real gradient-overflow bug (commit `db25f17`). Medical lossless data argues for targeted `&+`/`&-` with cited bounds (post-Phase-2, profile-driven) instead.

---

## 3. Phase 2 — Structural rewrites (1–2 weeks total)

### W2.1 64-bit bitstream reader with clz unary decode
*Merges: decoder/memory/swiftperf bit-reader findings.*
- **Change:** Rewrite `Core/JPEGLSBitstreamReader.swift:147-195` around a `UInt64` bit window over `[UInt8]` (one-time copy of the scan range from W1.6.3, or scoped `withUnsafeBytes`): refill 4–6 bytes at a time applying the 0xFF/stuff-bit rule per refilled byte (current logic at :164-177 contributes 8+7 bits per FF+stuffed pair — replicate exactly); add nonthrowing `peekBits`/`consume`; decode the unary prefix with one `leadingZeroBitCount` on the peeked word. Replace the per-bit `readBits(1)` loops in `readGolombCode` (`JPEGLSDecoder.swift:969-984`) and `readRunLength` (:1012-1038) with peek+clz+consume.
- **Safety:** consumes the identical bit sequence; preserve (a) the limited-code threshold at :978 (cap the clz path), (b) `readRunLength`'s early exit at `runLength >= remainingInLine` (:1027 — a run can end without a terminating 0 bit).
- **Impact:** today every unary bit is a function call with refill check + Data-subscript byte fetch; this is the canonical decoder optimization. Est. 1.5–2.5x decode combined with W1.6.3.
- **Verify:** golden decoded-pixel hashes on deterministic generated vectors plus synthetic DICOM round trips; bench-dicom.

### W2.2 Flat pixel storage + carried-neighbor scan loops (the keystone)
*Merges: encoder getNeighbors-restructure, decoder getNeighbors/CoW-rows, three `[[Int]]`-storage findings, fillRunResult branch.*
- **Change:** Keep the public `[[Int]]` API; convert once per scan at `encodeScanData` (`JPEGLSEncoder.swift:556-624`) / `decodeComponent` (`JPEGLSDecoder.swift:573-662`) entry to a flat `ContiguousArray<UInt16>` (UInt8 for bps≤8) per component plane, and run the entire scan over `withUnsafeBufferPointer` regions with two line pointers (previousLine/currentLine). Carry neighbors in locals — per pixel: `c=b; b=d; a=justCoded; d=prevLine[col+2]` — handling row==0/col==0 once per line via an edge-padded previous-line buffer. Replicate exactly: encoder boundary semantics at `JPEGLSPixelBuffer.swift:292-328` (row 0 → b=c=d=0; col 0 → Ra=Rb=top, Rc=prevRowEdge; last col → Rd=Rb) and decoder `prevRowEdge` (`JPEGLSDecoder.swift:592-604, 1073-1074`: Rc at col 0 = row r−2 first pixel). Fill runs with `initialize(repeating:)` (run length already clamped to `remainingInLine` at :1042, so the per-element branch at :752-756 is provably dead). Convert back to `[[Int]]` once when building `ComponentData`. Samples validated to [0, maxval≤65535] at `JPEGLSPixelBuffer.swift:104-113`, so UInt16 is lossless.
- **Safety:** purely representational — identical a/b/c/d values feed unchanged gradient/context/Golomb logic → bit-exact. Note `Core/JPEGLSCacheFriendlyBuffer.swift` is *not* a drop-in (flat `[Int]` behind a Dictionary); build fresh.
- **Impact:** eliminates the ~15% bounds-check line, the per-row hidden CoW copies and per-store uniqueness checks (~7%), the residual nested-array indirection, and 4x cache footprint; reduces neighbor fetch from 4–5 random 2D reads to one load. Verifiers' estimate: 1.5–3x decode, comparable encode (on top of Phase 1). Also unlocks true SIMD run scanning (upgrade W1.5 to `SIMD16/32` equality + mask-based first-false afterward) and makes run fills memset-cheap.
- **Verify:** golden hashes (encode bytes + decode pixels); bench-dicom full gate; re-check the `-O` vs `-Ounchecked` gap (W1.7) — it should mostly vanish.

### W2.3 Packed context records
- **Change:** `Core/JPEGLSContextModel.swift:28-46, 202-343`. Replace the four parallel `[Int]` arrays with one array of a packed struct (A, B, C, **N all Int32** — Int16 N is unsafe because RESET is user-settable); drop the four redundant `0..<365` guards (sole producer clamps at :176; all 7 producers verified to flow through it); fuse getC/computeGolombParameter/getErrorCorrection/updateContext into one read-modify-write per pixel under `withUnsafeMutableBufferPointer` scoped over the scan; hoist `2*near+1` (:266) and `parameters.reset` (:271) into stored lets.
- **Safety:** A bounded by RESET·MAXVAL ≈ 4.2M fits Int32; C clamped to [−128,127] at :288/291; storage-only change, arithmetic untouched. Disassembly confirmed `updateContext` survives as an outlined function with 4+ uniqueness-check runtime calls and outlined bounds checks per pixel — real, uneliminated cost.
- **Impact:** `updateContext` is ~8% + a share of the ~7% CoW line; est. 5–15% both sides.
- **Verify:** golden hashes; round-trip tests including custom-RESET/16-bit edge cases.

---

## 4. Phase 3 — Larger bets

### W3.1 Wire up batch encode/decode (dead feature, easiest multicore win)
- `Sources/jpeglscli/BatchCommand.swift:420-430`: `processEncode`/`processDecode` unconditionally throw "not yet implemented" while the semaphore-throttled pool (:318-354) is real. Wire them to `JPEGLSEncoder`/`JPEGLSDecoder` exactly as `EncodeCommand.swift:313` / `DecodeCommand.swift:83` do. Both codecs are stateless `Sendable` structs with no global mutable state — concurrent per-file use is safe and trivially bit-exact (identical code path). Yields ~Ncores aggregate for multi-file radiology series. Effort: medium.

### W3.2 Restart-interval (DRI/RSTm) intra-frame parallelism
- The only standards-compliant way to parallelize a single large scan (17 MP MG frames). Implement per T.87: encoder writes DRI, emits RSTm every N lines with full context + run-index + bit-buffer reset; intervals encode in parallel into per-interval buffers and concatenate; decoder indexes RST markers (cheap byte scan) and decodes intervals concurrently. Today the parser stores `restartInterval` but nothing consumes it, and `extractScanData` truncates at the first RST marker — a conformant restart stream currently **fails to decode**; fix that first regardless. `Core/JPEGLSTileProcessor.swift` is dead code — delete it or rebind it to this stripe partitioning.
- **Caveats:** changes the bitstream (small ratio cost), so the bit-identical gate does not apply — gate on lossless round trips, standards-derived restart vectors, and independent implementation testing before release. Make it an opt-in encode flag, default off. Near-linear multicore on big frames; does **not** close the single-thread gap. Effort: large. Do this only after Phase 2, when single-thread is respectable.

### W3.3 Acceleration-layer disposition + docs honesty
- The entire `Sources/JPEGLS/Platform/` layer (11 files, 4,365 lines) plus `JPEGLSBufferPool` and `JPEGLSCacheFriendlyBuffer` have **zero production call sites** — the baseline is pure scalar Swift. Delete Platform/Vulkan, Platform/Metal, Platform/x86_64 (removal guide exists: `docs/X86_64_REMOVAL_GUIDE.md`), Platform/Accelerate and their ~4,750 lines of tests; the one salvageable *idea* (SIMD run scan) is re-implemented properly in W2.2's follow-up, not transplanted (the existing version takes `[Int32]`, builds vectors from bounds-checked subscripts, and resolves matches lane-by-lane).
- Rewrite `docs/PERFORMANCE_TUNING.md` (advertises automatic accelerator selection with "~2–3x" speedups, nonexistent APIs `computeBatchGradients`/`computeStatistics`, a non-compiling TaskGroup example), `README.md:101-104`, and `docs/METAL_GPU_ACCELERATION.md` around what actually runs. Zero MB/s change; the value is stopping future sessions from optimizing a layer that never executes.

### W3.4 Parallel multi-component `.none` scans (low priority)
- Scans are context-isolated and byte-aligned (fresh context per `encodeScanData`, `writer.flush()` per scan; stuffing carries no state across flush), so per-component parallel encode + ordered splice is provably byte-identical, and the decoder's pre-split `scanDataList` parallelizes trivially. But the DICOM corpus is effectively all single-component grayscale → zero benefit there. Only do this if planar RGB workloads materialize.

---

## 5. Do NOT do (re-litigated and rejected — leave these alone)

1. **GPU acceleration (Metal/Vulkan), in any form.** Vulkan's GPU path is commented-out pseudocode over a hardcoded-empty device list. Metal's encode kernel computes raw `x − MED`, which is *not* the value that gets Golomb-coded (bias correction C[Q] is applied sequentially *before* the error), and its decode kernel is logically circular — its inputs are already-decoded neighbors that cannot exist before the answer. The sequential entropy stage cannot be GPU-ified. Delete (W3.3), don't fix.
2. **Wiring the `PlatformAccelerator` protocol into the codec.** Per-pixel existential dispatch, and the "SIMD" implementations are packing-overhead wrappers that execute more instructions than the scalar code. The CLZ Golomb trick it contains is already in production (`JPEGLSContextModel.swift:319-322`).
3. **A Traits-generic "lossless specialization" redesign.** The code already hand-specializes every near==0 arm; the residue is ~4 loop-invariant predicted compares per pixel. The only real waste found was the unconditional `reconstructed` allocation — fixed by the one-line guard in W1.6.1.
4. **Expecting a big decoder win from de-duplicating the source-level 9x gradient quantization.** Release disassembly showed the optimizer fully inlines decodeSinglePixel/decodePixel and CSEs the duplication down to 3 `quantizeGradient` calls + 1 `computeContextIndex` per pixel. The recoverable cost is the outlined call + branch chain (W1.4, ~5–10%), no more. (The *encoder's* 6-vs-3 duplication is disassembly-confirmed real — that's W1.3.)
5. **Parallelizing bench-dicom.** Its serial timed region is the measurement instrument; parallel encode would invalidate the per-modality MB/s metric. Multi-file parallelism belongs in BatchCommand (W3.1).
6. **`unsafeFlags`/`-Ounchecked` in Package.swift.** Breaks the package as a versioned dependency, and `-Ounchecked` turns overflow traps into UB (recent real overflow bug: `db25f17`). Opt-in diagnostic build only (W1.7).
7. **Build-flag hunting beyond default `-O`.** SwiftPM release already does WMO; cross-module opt is irrelevant (hot loops are one module); Swift has no mature PGO. The structural fixes deliver the same wins safely.

---

## 6. Measurement protocol (this machine)

**Build (git `safe.bareRepository=explicit` workaround required):**
```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  swift build -c release
# binary: .build/arm64-apple-macosx/release/jpegls
```

**Bit-exactness gate (run after EVERY Phase 1–2 change; this is the merge blocker):**
1. Before starting work, with the baseline binary: encode the two synthetic references and ~10 fixed DICOM frames (one per modality from the local corpus copy below) to `.jls`; store SHA-256 of each encoded file and of each decoded pixel dump in a `golden/` checksum file.
2. After each change: re-encode/re-decode the same inputs; **all hashes must match**. Exception: W3.2 (restart markers) legitimately changes bytes — gate it on lossless round trips plus the restart-interval regression suite instead.
3. Full test suite: `GIT_CONFIG_COUNT=1 ... swift test` (same prefix).

**Synthetic CPU-truth benchmark (no I/O noise, matches the profiled baseline):**
```sh
.build/arm64-apple-macosx/release/jpegls benchmark --size 2048 --bits-per-sample 16 \
  --iterations 10 --warmup 3 --json        # baseline: enc 214.61 ms / dec 137.83 ms
.build/arm64-apple-macosx/release/jpegls benchmark --size 2048 --bits-per-sample 8 \
  --iterations 10 --warmup 3 --json        # baseline: enc 30.80 ms / dec 31.55 ms
```
Trust the **16-bit** number; the 8-bit gradient image compresses 59:1 (run-mode heavy) and flatters run-path changes while hiding regular-mode regressions. Report means; run on a quiet machine on AC power; alternate old/new binaries A/B within one session to cancel thermal drift.

**Real-DICOM end-to-end:** the corpus lives on Google Drive CloudStorage (`/Users/raster/Library/CloudStorage/GoogleDrive-…/Radiology DICOM Data`, ~30k files, top-level folder = modality). To kill sync/download noise, **copy a fixed subset locally once** (e.g., the first ~20 uncompressed Implicit-VR files per modality to `~/dicom-bench/`, preserving the modality folder structure), then:
```sh
.build/arm64-apple-macosx/release/jpegls bench-dicom ~/dicom-bench --limit 20 --near 0 --json
```
Baseline to beat: ALL 26.4 MB/s encode / 40.1 MB/s decode / 3.01:1; per-modality CT 21.8/30.8, DX 19.7/28.4, MG 33.1/53.1, MR 35.7/49.7, PX 16.2/23.2, XA 21.0/29.7; 107/107 frames lossless. **Regression gate: every frame still round-trips losslessly (zero mismatches).** US is expected to skip (non-grayscale/encapsulated). Throughput columns are codec-time-only; treat as approximate but comparable run-to-run on local files.

**Profiling between changes:** start a long run (e.g., a 150-iteration 16-bit roundtrip via `benchmark --iterations 150`), then `sample <pid> 10` (1 ms interval); diff top frames against the baseline attribution in §1. After each Phase 2 item, also re-measure the `-O` vs `-Ounchecked` gap (W1.7) — remaining gap ≈ remaining bounds/CoW headroom.

**Discipline:** one work item per measurement cycle; record (commit, synthetic 16-bit enc/dec ms, bench-dicom ALL row, golden-hash pass/fail) in a running table so wins compose honestly and regressions are attributable.

# 2026-11-20 WeChat video chat: remote video stretched (PYB .201 slot A)

Symptom (user): in WeChat video chat the other side's video is shown in the wrong aspect ratio. Front camera capture is fine (WeChat uses Camera1 1280x720@15 from camera 1, sensor mode 2328x1748, normal centre crop); user confirmed it is the received video.

## What the logs showed
- Incoming stream is decoded by `c2.qti.hevc.decoder` into a SurfaceTexture. It starts 640x288 (20:9) and switches mid-call to 640x480 (4:3) (SurfaceTexture `setBuffersDimensions [640,288]` then `[640,480]`). Screenshot: the 4:3 picture is stretched over the full 20:9 screen.

## Reproduction without WeChat (tools/live/wechat-resize-test/)
`MCTest.java` (build: javac --release 17 + d8; run `CLASSPATH=/data/local/tmp/mctest.dex app_process / MCTest <decoder> <file> <w> <h> <surface|buffer> <hevc|avc> [maxW maxH]`) feeds an Annex-B stream that changes size mid-way (`resize_288_480.hevc/.h264`: 640x288 x45 frames then 640x480 x45) and prints every `INFO_OUTPUT_FORMAT_CHANGED` plus the consumer `ImageReader` size.

| decoder / mode | output format after the change | frames |
| --- | --- | --- |
| c2.qti.hevc.decoder, ByteBuffer | width=640 **height=480** crop-bottom=479 (correct) | ok |
| c2.android.hevc.decoder, Surface | width=640 **height=480** crop-bottom=479 (correct) | 640x480 |
| **c2.qti.hevc.decoder, Surface** | width=640 **height=288 (stale)** crop-bottom=479 | 640x480 |
| **c2.qti.avc.decoder, Surface** | width=640 **height=288 (stale)** crop-bottom=479 | 640x480 |
| c2.qti.hevc.decoder, Surface + max 1920x1080 | height=288 (stale), same | 640x480 |

So the actual frames are right (ImageReader gets 640x480), but with a Surface output every QTI hardware decoder reports the new crop and a stale `width`/`height` in the output MediaFormat after a mid-stream resolution change. An app that derives the aspect from width/height (WeChat) keeps 20:9 and stretches the 4:3 frames. Software decoders and ByteBuffer mode are correct.

## Not yet known
- Whether it also happens on 17k-r3 (slot B) = regression of the .201 system (Android 17 CCodec + Oplus `OplusCCodec`) vs the SM8150 LOS vendor QC2 stack, or older. Run the same MCTest commands on slot B (needs a reboot to slot B, user OK).
- Which layer drops the size update (vendor QC2 component not sending `C2StreamPictureSizeInfo::output` in surface mode, or the system CCodec ignoring it). QC2/CCodec logs at default level show nothing at the change; ALOGV is compiled out.

## Ideas (none applied)
1. A/B on slot B; if fine there, diff system media stack (`libstagefright`, `libcodec2_*`, `/system/etc/media_codecs*`, Oplus CCodec ext) between builds.
2. If it is the component: vendor QC2 libs are closed; look for a config/feature switch (adaptive playback, `max-width/height` already tried), or binary patch.
3. Last resort for WeChat only: none in system config (codec choice is not per app).

Phone state: only `/data/local/tmp/{mctest.dex,resize_288_480.hevc,resize_288_480.h264}` added; log.tag props restored.

## Fix (B34, 2026-11-20)
- Layer: the stale size comes from the QTI component/CCodec path; fixed on the system side in `android.media.MediaCodec` (framework.jar classes3): new `portFixOutputFormat(Map)` sets width/height = crop-right+1 / crop-bottom+1 for `video/raw` formats without `stride` (Surface outputs only; ByteBuffer outputs untouched). Called in `getOutputFormat()`, `getOutputFormat(int)` and the async `onOutputFormatChanged` path. Patcher: `tools/live/wechat-resize-test/patch_mediacodec_crop.py`.
- MCTest after the fix: c2.qti.hevc / c2.qti.avc Surface -> height=480 after the change; ByteBuffer and c2.android unchanged.
- WeChat's own decoder paths read width/height (and crop for ByteBuffer) from MediaFormat; its VoIP native libs do not use the NDK codec API, so the Java fix covers it.
- framework.jar is in the boot image: a changed dex makes ART reject the whole system boot image (`dex file checksum ... does not match`, "fall back to imageless running"). Removing only boot-framework.* does not help (boot.art is one 23-component set). odrefresh's boot-time check only tests that the system files exist. Bake: the primary boot image odrefresh compiles against the patched classpath (`odrefresh --force-compile`, 33 s on the phone) is pinned in `bootimage/` and replaces the 144 stock files per ISA.
- Live test (user, real WeChat video call): bind-mounted patched framework.jar + /data boot image + framework restart -> remote video no longer stretched.
- Trap found: toybox `unshare -m` + `mount --make-rprivate /` fails silently, binds leak into the global namespace; use `mount -o rprivate none /` and check `grep -c shared: /proc/self/mountinfo` = 0.

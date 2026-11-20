"""patch_mediacodec_crop.py <smali root of the framework.jar dex holding android/media/MediaCodec>

B34 (WeChat remote video stretched): with a Surface output, the QTI Codec2 decoders of the SM8150 LOS vendor report a new crop
but a stale width/height in the output MediaFormat after a mid-stream resolution change (640x288 -> 640x480 gives width=640
height=288 crop-bottom=479). Apps that take the aspect from width/height (WeChat VoIP) stretch the picture.

Adds android.media.MediaCodec.portFixOutputFormat(Map): for decoded video delivered to a Surface (mime video/raw, no "stride"
key; ByteBuffer outputs always carry stride and are left alone) it sets width = crop-right + 1, height = crop-bottom + 1.
Called on the native map right before the MediaFormat is built in getOutputFormat(), getOutputFormat(int) and the async
onOutputFormatChanged callback (MediaCodec$EventHandler). Every edit asserts the exact original instruction sequence.
"""
import pathlib
import sys

root = pathlib.Path(sys.argv[1]) / "android" / "media"
MC = root / "MediaCodec.smali"
EH = root / "MediaCodec$EventHandler.smali"
CALL = "invoke-static {%s}, Landroid/media/MediaCodec;->portFixOutputFormat(Ljava/util/Map;)V"
CTOR = "invoke-direct {%s, %s}, Landroid/media/MediaFormat;-><init>(Ljava/util/Map;)V"

HELPER = r"""
.method static blacklist portFixOutputFormat(Ljava/util/Map;)V
    .registers 6

    if-eqz p0, :done

    :try_start
    const-string v0, "mime"
    invoke-interface {p0, v0}, Ljava/util/Map;->get(Ljava/lang/Object;)Ljava/lang/Object;
    move-result-object v0
    const-string v1, "video/raw"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-eqz v1, :done

    const-string v0, "stride"
    invoke-interface {p0, v0}, Ljava/util/Map;->containsKey(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :done

    const-string v0, "crop-right"
    invoke-interface {p0, v0}, Ljava/util/Map;->get(Ljava/lang/Object;)Ljava/lang/Object;
    move-result-object v2
    instance-of v1, v2, Ljava/lang/Integer;
    if-eqz v1, :done
    const-string v0, "crop-bottom"
    invoke-interface {p0, v0}, Ljava/util/Map;->get(Ljava/lang/Object;)Ljava/lang/Object;
    move-result-object v3
    instance-of v1, v3, Ljava/lang/Integer;
    if-eqz v1, :done

    check-cast v2, Ljava/lang/Integer;
    invoke-virtual {v2}, Ljava/lang/Integer;->intValue()I
    move-result v2
    add-int/lit8 v2, v2, 0x1
    check-cast v3, Ljava/lang/Integer;
    invoke-virtual {v3}, Ljava/lang/Integer;->intValue()I
    move-result v3
    add-int/lit8 v3, v3, 0x1
    if-lez v2, :done
    if-lez v3, :done

    const-string v0, "width"
    invoke-static {v2}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;
    move-result-object v4
    invoke-interface {p0, v0, v4}, Ljava/util/Map;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
    const-string v0, "height"
    invoke-static {v3}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;
    move-result-object v4
    invoke-interface {p0, v0, v4}, Ljava/util/Map;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
    :try_end
    .catch Ljava/lang/RuntimeException; {:try_start .. :try_end} :done

    :done
    return-void
.end method
"""


def method_body(src, sig):
    i = src.index(sig)
    j = src.index(".end method", i)
    return i, j


def patch_method(src, sig, old, new):
    i, j = method_body(src, sig)
    body = src[i:j]
    if body.count(old) != 1:
        sys.exit(f"{sig}: expected one '{old.strip()}' (found {body.count(old)}), the class changed")
    return src[:i] + body.replace(old, new) + src[j:]


s = MC.read_text(encoding="utf-8")
if "portFixOutputFormat" in s:
    sys.exit("MediaCodec already patched")
get0 = "\n    invoke-direct {p0, v1}, Landroid/media/MediaCodec;->getFormatNative(Z)Ljava/util/Map;\n\n    move-result-object v1\n\n    " + CTOR % ("v0", "v1")
s = patch_method(s, ".method public final whitelist getOutputFormat()Landroid/media/MediaFormat;", get0,
                 get0.replace("    " + CTOR % ("v0", "v1"), "    " + CALL % "v1" + "\n\n    " + CTOR % ("v0", "v1")))
get1 = "\n    invoke-direct {p0, p1}, Landroid/media/MediaCodec;->getOutputFormatNative(I)Ljava/util/Map;\n\n    move-result-object v1\n\n    " + CTOR % ("v0", "v1")
s = patch_method(s, ".method public final whitelist getOutputFormat(I)Landroid/media/MediaFormat;", get1,
                 get1.replace("    " + CTOR % ("v0", "v1"), "    " + CALL % "v1" + "\n\n    " + CTOR % ("v0", "v1")))
s = s.rstrip("\n") + "\n" + HELPER
MC.write_text(s, encoding="utf-8", newline="\n")

e = EH.read_text(encoding="utf-8")
old = ("    check-cast v3, Ljava/util/Map;\n\n    " + CTOR % ("v2", "v3") + "\n\n"
       "    invoke-virtual {v0, v1, v2}, Landroid/media/MediaCodec$Callback;->onOutputFormatChanged(Landroid/media/MediaCodec;Landroid/media/MediaFormat;)V")
if e.count(old) != 1:
    sys.exit(f"MediaCodec$EventHandler: onOutputFormatChanged site not found once ({e.count(old)})")
e = e.replace(old, old.replace("    " + CTOR % ("v2", "v3"), "    " + CALL % "v3" + "\n\n    " + CTOR % ("v2", "v3")))
EH.write_text(e, encoding="utf-8", newline="\n")
print("MediaCodec: portFixOutputFormat added, 3 call sites patched")

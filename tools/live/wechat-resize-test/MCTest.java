import android.media.MediaCodec;
import android.media.MediaFormat;
import java.io.*;
import java.nio.ByteBuffer;
import android.media.Image;
import android.media.ImageReader;
import android.graphics.ImageFormat;
import android.graphics.Rect;
import java.util.*;

/** Feed an Annex-B HEVC file (AUD-delimited access units) to a named decoder and log every output format change.
 *  usage: app_process / MCTest <decoderName> <file.hevc> <initialW> <initialH> */
public class MCTest {
    static String fmt(MediaFormat f) {
        StringBuilder sb = new StringBuilder();
        for (String k : new String[]{"width","height","stride","slice-height","crop-left","crop-top","crop-right","crop-bottom","color-format","rotation-degrees"}) {
            if (f.containsKey(k)) sb.append(k).append('=').append(f.getInteger(k)).append(' ');
        }
        return sb.toString();
    }
    public static void main(String[] a) throws Exception {
        boolean surf = a.length > 4 && a[4].equals("surface");
        String name = a[0]; String file = a[1]; int w = Integer.parseInt(a[2]), h = Integer.parseInt(a[3]);
        byte[] all; try (FileInputStream in = new FileInputStream(file)) { all = in.readAllBytes(); }
        // split at AUD NAL (type 35): 00 00 01 46 01 or 00 00 00 01 46 01
        List<Integer> starts = new ArrayList<>();
        for (int i = 0; i + 4 < all.length; i++) {
            boolean h264 = a.length > 5 && a[5].equals("avc"); if (all[i]==0 && all[i+1]==0 && all[i+2]==1 && (h264 ? ((all[i+3]&0x1f)==9) : (((all[i+3]>>1)&0x3f)==35))) { starts.add(i>0 && all[i-1]==0 ? i-1 : i); }
        }
        starts.add(all.length);
        System.out.println("access units: " + (starts.size()-1) + " decoder=" + name);
        MediaCodec c = MediaCodec.createByCodecName(name);
        MediaFormat f = MediaFormat.createVideoFormat(a.length > 5 && a[5].equals("avc") ? "video/avc" : "video/hevc", w, h); if (a.length > 7) { f.setInteger(MediaFormat.KEY_MAX_WIDTH, Integer.parseInt(a[6])); f.setInteger(MediaFormat.KEY_MAX_HEIGHT, Integer.parseInt(a[7])); }
        ImageReader ir = null; if (surf) ir = ImageReader.newInstance(w, h, ImageFormat.YUV_420_888, 6);
        c.configure(f, surf ? ir.getSurface() : null, null, 0);
        c.start();
        MediaCodec.BufferInfo bi = new MediaCodec.BufferInfo();
        String lastImg = ""; int au = 0, outFrames = 0; long pts = 0; boolean eos = false, inDone = false;
        long t0 = System.currentTimeMillis();
        while (!eos && System.currentTimeMillis() - t0 < 30000) {
            if (!inDone) {
                int ii = c.dequeueInputBuffer(10000);
                if (ii >= 0) {
                    ByteBuffer ib = c.getInputBuffer(ii);
                    if (au + 1 < starts.size()) {
                        int s = starts.get(au), e = starts.get(au+1);
                        ib.clear(); ib.put(all, s, e - s);
                        c.queueInputBuffer(ii, 0, e - s, pts, 0); pts += 66666; au++;
                    } else { c.queueInputBuffer(ii, 0, 0, pts, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inDone = true; }
                }
            }
            int oi = c.dequeueOutputBuffer(bi, 10000);
            if (oi >= 0) {
                outFrames++;
                MediaFormat of = c.getOutputFormat(oi);
                if ((outFrames % 15) == 1) System.out.println("frame " + outFrames + " size=" + bi.size + " fmt: " + fmt(of));
                c.releaseOutputBuffer(oi, surf);
                if (surf) { Thread.sleep(8); Image im = ir.acquireLatestImage(); if (im != null) { Rect cr = im.getCropRect(); String d = im.getWidth()+"x"+im.getHeight()+" crop="+cr.toShortString(); if (!d.equals(lastImg)) { System.out.println("IMAGE at output frame "+outFrames+": "+d); lastImg = d; } im.close(); } }
                if ((bi.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) eos = true;
            } else if (oi == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                System.out.println("OUTPUT FORMAT CHANGED at output frame " + outFrames + ": " + fmt(c.getOutputFormat()));
            }
        }
        System.out.println("done: input AUs=" + au + " output frames=" + outFrames);
        c.stop(); c.release();
    }
}

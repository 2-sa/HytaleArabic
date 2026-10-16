using System;
using System.Runtime.InteropServices;
using System.Text;

public static class ArabicText {
    [DllImport("icu.dll", CallingConvention=CallingConvention.Cdecl, CharSet=CharSet.Unicode)]
    private static extern int u_shapeArabic(string source, int length, StringBuilder output, int capacity, uint options, ref int error);
    [DllImport("icu.dll", CallingConvention=CallingConvention.Cdecl)]
    private static extern IntPtr ubidi_open();
    [DllImport("icu.dll", CallingConvention=CallingConvention.Cdecl)]
    private static extern void ubidi_close(IntPtr bidi);
    [DllImport("icu.dll", CallingConvention=CallingConvention.Cdecl, CharSet=CharSet.Unicode)]
    private static extern void ubidi_setPara(IntPtr bidi, string text, int length, byte paragraphLevel, IntPtr levels, ref int error);
    [DllImport("icu.dll", CallingConvention=CallingConvention.Cdecl, CharSet=CharSet.Unicode)]
    private static extern int ubidi_writeReordered(IntPtr bidi, StringBuilder output, int capacity, ushort options, ref int error);

    public static string Visual(string logical) {
        var shaped = new StringBuilder(logical.Length * 3 + 32);
        int error = 0;
        u_shapeArabic(logical, logical.Length, shaped, shaped.Capacity, 8, ref error);
        if (error > 0) throw new Exception("ICU shaping error " + error);
        string input = shaped.ToString();
        IntPtr bidi = ubidi_open();
        if (bidi == IntPtr.Zero) throw new Exception("Cannot allocate ICU bidi context.");
        // The ICU paragraph keeps a pointer to this unmanaged UTF-16 buffer.
        // Use a pinned buffer for the entire setPara/writeReordered lifetime.
        var pinned = GCHandle.Alloc(input, GCHandleType.Pinned);
        try {
            error = 0;
            SetPinned(bidi, pinned.AddrOfPinnedObject(), input.Length, 1, IntPtr.Zero, ref error);
            if (error > 0) throw new Exception("ICU paragraph error " + error);
            var output = new StringBuilder(input.Length * 3 + 32);
            ubidi_writeReordered(bidi, output, output.Capacity, 10, ref error);
            if (error > 0) throw new Exception("ICU bidi error " + error);
            return output.ToString();
        } finally { ubidi_close(bidi); pinned.Free(); }
    }
    [DllImport("icu.dll", EntryPoint="ubidi_setPara", CallingConvention=CallingConvention.Cdecl)]
    private static extern void SetPinned(IntPtr bidi, IntPtr text, int length, byte paragraphLevel, IntPtr levels, ref int error);
}

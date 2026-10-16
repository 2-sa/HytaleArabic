using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

public sealed class ArabicGlyph {
    public int unicode;
    public double advance;
    public double left, top, right, bottom;
    public int x, y, width, height;
}

// All outlines come from the recipient's installed Windows font.
// Existing game pixels are only read and retained on that recipient's PC.
public static class ArabicAtlas {
    public static ArabicGlyph[] Extend(string originalPng, string outputPng,
        double emSize, double distanceRange, int[] characters, bool bold) {
        using (var original = new Bitmap(originalPng))
        using (var family = new FontFamily("Arial")) {
            FontStyle style = bold ? FontStyle.Bold : FontStyle.Regular;
            int cell = (int)Math.Ceiling(emSize * 2.7 + distanceRange * 2);
            // Keep the source atlas's square, power-of-two layout. A tall
            // append-only image changes the texture contract unnecessarily.
            int side = 1;
            while (side < Math.Max(original.Width, original.Height)) side *= 2;
            int columns;
            while (true) {
                columns = side / cell;
                if (columns > 0 && original.Height + ((characters.Length + columns - 1) / columns) * cell <= side) break;
                side *= 2;
                if (side > 4096) throw new Exception("Arabic atlas would exceed 4096x4096.");
            }
            // Match the game's RGB PNG atlas encoding (PNG color type 2).
            // An alpha channel changes the decoded buffer from 3 to 4 bytes/pixel.
            using (var output = new Bitmap(side, side, PixelFormat.Format24bppRgb))
            using (var outputGraphics = Graphics.FromImage(output)) {
                outputGraphics.Clear(Color.Black);
                outputGraphics.DrawImageUnscaled(original, 0, 0);
                double ascent = family.GetCellAscent(style) * emSize / family.GetEmHeight(style);
                var result = new List<ArabicGlyph>();
                for (int i = 0; i < characters.Length; i++) {
                    string s = Char.ConvertFromUtf32(characters[i]);
                    int x = (i % columns) * cell;
                    int y = original.Height + (i / columns) * cell;
                    using (var path = new GraphicsPath())
                    using (var format = (StringFormat)StringFormat.GenericTypographic.Clone())
                    using (var measureFont = new Font(family, (float)emSize, style, GraphicsUnit.Pixel)) {
                        format.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces | StringFormatFlags.NoClip;
                        path.AddString(s, family, (int)style, (float)emSize, new PointF(0, 0), format);
                        var bounds = path.GetBounds();
                        int pad = (int)Math.Ceiling(distanceRange / 2) + 2;
                        int minX = (int)Math.Floor(bounds.Left) - pad;
                        int minY = (int)Math.Floor(bounds.Top - ascent) - pad;
                        int w = (int)Math.Ceiling(bounds.Right) + pad - minX;
                        int h = (int)Math.Ceiling(bounds.Bottom - ascent) + pad - minY;
                        if (w > cell || h > cell) throw new Exception("Arabic glyph exceeds atlas cell.");
                        using (var matrix = new Matrix()) {
                            matrix.Translate(-minX, (float)(-minY - ascent));
                            path.Transform(matrix);
                        }
                        using (var mask = new Bitmap(w, h, PixelFormat.Format32bppArgb))
                        using (var g = Graphics.FromImage(mask)) {
                            g.Clear(Color.Black);
                            g.SmoothingMode = SmoothingMode.AntiAlias;
                            g.FillPath(Brushes.White, path);
                            var signed = MakeDistance(mask, distanceRange);
                            using (signed) outputGraphics.DrawImageUnscaled(signed, x, y);
                        }
                        var advance = outputGraphics.MeasureString(s, measureFont, Int32.MaxValue, format).Width;
                        result.Add(new ArabicGlyph {
                            unicode = characters[i], advance = advance / emSize,
                            left = minX / emSize, top = minY / emSize,
                            right = (minX + w) / emSize, bottom = (minY + h) / emSize,
                            x = x, y = y, width = w, height = h
                        });
                    }
                }
                output.Save(outputPng, ImageFormat.Png);
                return result.ToArray();
            }
        }
    }

    // An identical signed-distance value in all RGB channels is valid for
    // median-based MSDF sampling, though corner quality needs in-game QA.
    private static Bitmap MakeDistance(Bitmap mask, double range) {
        int w = mask.Width, h = mask.Height;
        var coverage = new double[w, h];
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++)
            coverage[x, y] = mask.GetPixel(x, y).R / 255.0;
        var output = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        int radius = (int)Math.Ceiling(range / 2) + 1;
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
            bool inside = coverage[x, y] >= 0.5;
            double distance = range / 2;
            for (int dy = -radius; dy <= radius; dy++) for (int dx = -radius; dx <= radius; dx++) {
                int xx = x + dx, yy = y + dy;
                bool other = xx >= 0 && xx < w && yy >= 0 && yy < h && coverage[xx, yy] >= 0.5;
                if (inside == other) continue;
                double candidate = Math.Max(0, Math.Sqrt(dx * dx + dy * dy) - 0.5);
                if (candidate < distance) distance = candidate;
            }
            double signed = inside ? distance : -distance;
            if (coverage[x, y] > 0 && coverage[x, y] < 1) signed = coverage[x, y] - 0.5;
            int value = (int)Math.Round(255 * Math.Max(0, Math.Min(1, 0.5 + signed / range)));
            output.SetPixel(x, y, Color.FromArgb(255, value, value, value));
        }
        return output;
    }
}

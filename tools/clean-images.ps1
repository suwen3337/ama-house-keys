# 阿嬤家找鑰匙：場景圖處理腳本
#
# 遊戲裡「拿起東西後原位變空」「東西移到別的地方」需要兩種圖：
#   1. 擦掉東西的背景圖（scene3-clean.jpg、scene4-clean.jpg）
#   2. 東西本身的去背圖（thermos-cut.png、can-cut.png、fern-front.png）
#
# 做法：
#   - 擦掉：把要擦掉的像素，用周圍的顏色一圈一圈往內「擴散」補起來（反覆取上下左右的平均）
#   - 去背：比較「原圖」和「擦掉後的圖」，差越多的像素越不透明，差不多的就是背景
#
# 執行方式（在這個資料夾按右鍵用 PowerShell 執行，或在終端機輸入）：
#   powershell -ExecutionPolicy Bypass -File tools\clean-images.ps1

$code = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
public static class SceneTools {
  public delegate bool P(int x, int y);

  // 擴散補圖：inMask 是要補的像素；usable 是可以拿來當顏色來源的像素；
  // split > 0 時，這條 y 座標的上下兩邊分開補（例如牆壁和地板不要混在一起）
  public static void Diffuse(Bitmap b, int x0, int y0, int x1, int y1, P inMask, P usable, int split) {
    int W = x1 - x0 + 3, H = y1 - y0 + 3;
    double[,,] c = new double[3, W, H]; bool[,] m = new bool[W, H], u = new bool[W, H];
    for (int i = 0; i < W; i++) for (int j = 0; j < H; j++) {
      int x = x0 - 1 + i, y = y0 - 1 + j;
      Color p = b.GetPixel(x, y);
      c[0, i, j] = p.R; c[1, i, j] = p.G; c[2, i, j] = p.B;
      bool inside = x >= x0 && x <= x1 && y >= y0 && y <= y1;
      m[i, j] = inside && inMask(x, y);
      u[i, j] = m[i, j] || usable(x, y);
    }
    for (int it = 0; it < 2500; it++)
      for (int i = 1; i < W - 1; i++) for (int j = 1; j < H - 1; j++) {
        if (!m[i, j]) continue;
        int y = y0 - 1 + j; bool top = split > 0 && y < split;
        double s0 = 0, s1 = 0, s2 = 0, n = 0;
        int[] di = { -1, 1, 0, 0 }, dj = { 0, 0, -1, 1 };
        for (int k = 0; k < 4; k++) {
          int a = i + di[k], bb = j + dj[k];
          if (!u[a, bb]) continue;
          if (split > 0) { bool t2 = (y0 - 1 + bb) < split; if (t2 != top) continue; }
          s0 += c[0, a, bb]; s1 += c[1, a, bb]; s2 += c[2, a, bb]; n++;
        }
        if (n > 0) { c[0, i, j] = s0 / n; c[1, i, j] = s1 / n; c[2, i, j] = s2 / n; }
      }
    // 補完加一點雜點，不然會太平滑、看起來像塑膠
    var rnd = new Random(5);
    for (int i = 0; i < W; i++) for (int j = 0; j < H; j++) if (m[i, j]) {
      double nz = (rnd.NextDouble() - 0.5) * 5;
      b.SetPixel(x0 - 1 + i, y0 - 1 + j, Color.FromArgb(Cl(c[0, i, j] + nz), Cl(c[1, i, j] + nz), Cl(c[2, i, j] + nz)));
    }
  }

  // 去背：原圖和擦掉後的圖差越多，越不透明
  public static void Cutout(Bitmap orig, Bitmap clean, int x0, int y0, int x1, int y1, P keep, string outPng) {
    var o = new Bitmap(x1 - x0 + 1, y1 - y0 + 1, PixelFormat.Format32bppArgb);
    for (int x = x0; x <= x1; x++) for (int y = y0; y <= y1; y++) {
      Color a = orig.GetPixel(x, y), c = clean.GetPixel(x, y);
      int d = Math.Max(Math.Abs(a.R - c.R), Math.Max(Math.Abs(a.G - c.G), Math.Abs(a.B - c.B)));
      int al = keep(x, y) ? Cl((d - 12) * 255.0 / 22) : 0;
      o.SetPixel(x - x0, y - y0, Color.FromArgb(al, a.R, a.G, a.B));
    }
    o.Save(outPng, ImageFormat.Png); o.Dispose();
  }

  // 植物去背：夜景裡偏黃的暗綠色（G 比 B 高很多，R 和 G 差不多）
  public static void FernCut(Bitmap orig, int x0, int y0, int x1, int y1, string outPng) {
    var o = new Bitmap(x1 - x0 + 1, y1 - y0 + 1, PixelFormat.Format32bppArgb);
    for (int x = x0; x <= x1; x++) for (int y = y0; y <= y1; y++) {
      Color a = orig.GetPixel(x, y);
      double gb = a.G - a.B, rg = a.R - a.G;
      double al = rg < 25 ? (gb - 9) * 255.0 / 12 : 0;
      o.SetPixel(x - x0, y - y0, Color.FromArgb(Cl(al), a.R, a.G, a.B));
    }
    o.Save(outPng, ImageFormat.Png); o.Dispose();
  }

  // 澆水壺的顏色：偏暖的灰色（不鮮豔、不太暗）
  public static bool CanColor(Bitmap b, int x, int y) {
    Color p = b.GetPixel(x, y);
    return p.R - p.B < 50 && p.R - p.G < 35 && (p.R + p.G + p.B) / 3 > 50;
  }
  public static bool Bright(Bitmap b, int x, int y) { Color p = b.GetPixel(x, y); return (p.R + p.G + p.B) / 3 > 150; }
  public static int Cl(double v) { return v < 0 ? 0 : v > 255 ? 255 : (int)v; }
  public static void SaveJpg(Bitmap b, string path) {
    ImageCodecInfo jpg = null;
    foreach (var e in ImageCodecInfo.GetImageEncoders()) if (e.MimeType == "image/jpeg") jpg = e;
    var ps = new EncoderParameters(1); ps.Param[0] = new EncoderParameter(Encoder.Quality, 93L);
    b.Save(path, jpg, ps);
  }
}
'@
Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing
$img = Join-Path $PSScriptRoot '..\阿嬤家\images'
$img = (Resolve-Path $img).Path

# ===== 第 3 關（阿嬤的房間）：板凳、熱水瓶 =====
Write-Host '處理第 3 關…'
$o3 = New-Object System.Drawing.Bitmap "$img\scene3.jpg"
$c3 = New-Object System.Drawing.Bitmap "$img\scene3.jpg"
# 板凳：右邊的棉被不能拿來當顏色來源；牆壁和地板（y=621）分開補
[SceneTools]::Diffuse($c3, 298, 509, 396, 648, { param($x, $y) $true }, { param($x, $y) -not ($x -gt 396 -and $y -lt 633) }, 621)
# 熱水瓶：前面的書本保留，也不拿來當顏色來源
$books = { param($x, $y) ($x -lt 1088 -and $y -ge 468) }
[SceneTools]::Diffuse($c3, 1055, 389, 1099, 478, { param($x, $y) -not (& $books $x $y) }, { param($x, $y) -not (& $books $x $y) }, 0)
[SceneTools]::SaveJpg($c3, "$img\scene3-clean.jpg")
# 熱水瓶去背：把手右邊的亮牆不要
$keepT = { param($x, $y) (-not (& $books $x $y)) -and $x -le 1097 -and -not ($x -gt 1090 -and [SceneTools]::Bright($o3, $x, $y)) }.GetNewClosure()
[SceneTools]::Cutout($o3, $c3, 1055, 389, 1099, 478, $keepT, "$img\thermos-cut.png")
$o3.Dispose(); $c3.Dispose()

# ===== 第 4 關（頂樓陽台）：澆水壺、倉庫掛鎖、倉庫前的蕨類 =====
Write-Host '處理第 4 關…'
$o4 = New-Object System.Drawing.Bitmap "$img\scene4.jpg"
$c4 = New-Object System.Drawing.Bitmap "$img\scene4.jpg"
# 澆水壺：只在壺的範圍裡找灰色的像素，再往外擴 2 像素（陶盆上的枝條、右邊的椅腳排除）
$X0 = 608; $Y0 = 536; $MW = 64; $MH = 60
$mask = New-Object 'bool[,]' $MW, $MH
for ($x = 0; $x -lt $MW; $x++) { for ($y = 0; $y -lt $MH; $y++) { $mask[$x, $y] = [SceneTools]::CanColor($o4, $X0 + $x, $Y0 + $y) } }
$dil = New-Object 'bool[,]' $MW, $MH
for ($x = 0; $x -lt $MW; $x++) { for ($y = 0; $y -lt $MH; $y++) {
  $hit = $false
  for ($dx = -2; $dx -le 2 -and -not $hit; $dx++) { for ($dy = -2; $dy -le 2; $dy++) {
    $a = $x + $dx; $b = $y + $dy
    if ($a -ge 0 -and $a -lt $MW -and $b -ge 0 -and $b -lt $MH -and $mask[$a, $b]) { $hit = $true; break } } }
  $dil[$x, $y] = $hit } }
$canMask = { param($x, $y) $i = $x - $X0; $j = $y - $Y0; ($i -ge 0 -and $i -lt $MW -and $j -ge 0 -and $j -lt $MH -and $dil[$i, $j]) }.GetNewClosure()
[SceneTools]::Diffuse($c4, 608, 536, 671, 595, $canMask, { param($x, $y) $true }, 0)
# 倉庫的掛鎖
[SceneTools]::Diffuse($c4, 110, 476, 155, 536, { param($x, $y) $true }, { param($x, $y) $true }, 0)
[SceneTools]::SaveJpg($c4, "$img\scene4-clean.jpg")
[SceneTools]::Cutout($o4, $c4, 608, 536, 671, 595, $canMask, "$img\can-cut.png")
[SceneTools]::FernCut($o4, 0, 515, 200, 600, "$img\fern-front.png")
$o4.Dispose(); $c4.Dispose()

Write-Host '完成！'

# Draws the flow diagrams embedded in the concept note.
# Rendered at 2x for print, using the deck's purple/white palette.

Add-Type -AssemblyName System.Drawing

$OUT = "c:\Users\user\WEB DEVELOPMENT\ekonnect\docs\diagrams"
New-Item -ItemType Directory -Path $OUT -Force | Out-Null

$PURPLE      = [System.Drawing.ColorTranslator]::FromHtml('#3D1152')
$PURPLE_SOFT = [System.Drawing.ColorTranslator]::FromHtml('#F3EEF8')
$CORAL       = [System.Drawing.ColorTranslator]::FromHtml('#FF4D5E')
$INK         = [System.Drawing.ColorTranslator]::FromHtml('#1B1524')
$GREY        = [System.Drawing.ColorTranslator]::FromHtml('#6B6577')
$RULE        = [System.Drawing.ColorTranslator]::FromHtml('#D8D2E0')
$GREEN       = [System.Drawing.ColorTranslator]::FromHtml('#2E7D32')
$WHITE       = [System.Drawing.Color]::White

function New-Canvas($w, $h) {
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.TextRenderingHint = 'ClearTypeGridFit'
  $g.Clear($WHITE)
  return @($bmp, $g)
}

function Get-RoundedPath($x, $y, $w, $h, $r) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $path.AddArc($x, $y, $d, $d, 180, 90)
  $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  return $path
}

function Draw-Box($g, $x, $y, $w, $h, $fill, $border, $title, $sub, $titleColor, $subColor) {
  $path = Get-RoundedPath $x $y $w $h 14
  $g.FillPath((New-Object System.Drawing.SolidBrush($fill)), $path)
  if ($border) {
    $g.DrawPath((New-Object System.Drawing.Pen($border, 2.5)), $path)
  }
  $fTitle = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
  $fSub   = New-Object System.Drawing.Font('Segoe UI', 11.5)
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'

  if ($sub) {
    $g.DrawString($title, $fTitle, (New-Object System.Drawing.SolidBrush($titleColor)),
      (New-Object System.Drawing.RectangleF($x, ($y + $h/2 - 26), $w, 26)), $fmt)
    $g.DrawString($sub, $fSub, (New-Object System.Drawing.SolidBrush($subColor)),
      (New-Object System.Drawing.RectangleF(($x + 10), ($y + $h/2 + 2), ($w - 20), 40)), $fmt)
  } else {
    $g.DrawString($title, $fTitle, (New-Object System.Drawing.SolidBrush($titleColor)),
      (New-Object System.Drawing.RectangleF($x, $y, $w, $h)), $fmt)
  }
}

function Draw-Arrow($g, $x1, $y1, $x2, $y2, $color, $label) {
  $pen = New-Object System.Drawing.Pen($color, 2.5)
  $pen.EndCap = 'ArrowAnchor'
  $g.DrawLine($pen, $x1, $y1, $x2, $y2)
  if ($label) {
    $f = New-Object System.Drawing.Font('Segoe UI', 10.5)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
    $mx = ($x1 + $x2) / 2; $my = ($y1 + $y2) / 2
    $sz = $g.MeasureString($label, $f)
    $g.FillRectangle((New-Object System.Drawing.SolidBrush($WHITE)),
      ($mx - $sz.Width/2 - 6), ($my - $sz.Height/2 - 2), ($sz.Width + 12), ($sz.Height + 4))
    $g.DrawString($label, $f, (New-Object System.Drawing.SolidBrush($GREY)),
      (New-Object System.Drawing.PointF($mx, $my)), $fmt)
  }
}

function Draw-Caption($g, $x, $y, $w, $textStr) {
  $f = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
  $g.DrawString($textStr, $f, (New-Object System.Drawing.SolidBrush($PURPLE)),
    (New-Object System.Drawing.PointF($x, $y)))
}

# ── 1. System architecture ───────────────────────────────────────────────────
$r = New-Canvas 1500 760; $bmp = $r[0]; $g = $r[1]

Draw-Caption $g 40 30 1420 'System architecture'

Draw-Box $g 60  110 380 130 $PURPLE_SOFT $PURPLE 'Patient App'      'Flutter - SOS, live tracking, voice reporting' $PURPLE $GREY
Draw-Box $g 560 110 380 130 $PURPLE_SOFT $PURPLE 'Responder App'    'Flutter - duty, accept, navigation, referral' $PURPLE $GREY
Draw-Box $g 1060 110 380 130 $PURPLE_SOFT $PURPLE 'Admin Dashboard' 'React - map, verification, teams, journeys' $PURPLE $GREY

Draw-Box $g 340 340 820 120 $PURPLE $null 'Firebase' 'Firestore  -  Authentication  -  Realtime Database  -  Cloud Messaging' $WHITE ([System.Drawing.Color]::FromArgb(220,220,220))

Draw-Arrow $g 250 240 560 340 $RULE $null
Draw-Arrow $g 750 240 750 340 $RULE $null
Draw-Arrow $g 1250 240 940 340 $RULE $null

Draw-Box $g 60   560 400 120 $WHITE $RULE 'Google Maps + Routes API' 'Live tracking, road routing, turn-by-turn' $INK $GREY
Draw-Box $g 550  560 400 120 $WHITE $RULE 'Groq LLM (Llama 3.3)'     'Voice triage and care-point matching' $INK $GREY
Draw-Box $g 1040 560 400 120 $WHITE $RULE 'Google Places API'        'Nearby hospitals, clinics and stations' $INK $GREY

Draw-Arrow $g 600 460 300 560 $RULE $null
Draw-Arrow $g 750 460 750 560 $RULE $null
Draw-Arrow $g 900 460 1200 560 $RULE $null

$bmp.Save("$OUT\architecture.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# ── 2. Incident lifecycle ────────────────────────────────────────────────────
$r = New-Canvas 1500 620; $bmp = $r[0]; $g = $r[1]

Draw-Caption $g 40 30 1420 'Incident lifecycle - every step timestamped'

$steps = @(
  @('SOS raised',      'Caller taps and holds'),
  @('Accepted',        'Verified responder takes it'),
  @('En route',        'Voice-guided navigation'),
  @('Reached patient', 'On-scene assessment'),
  @('Resolved',        'Care delivered')
)
$x = 55
foreach ($s in $steps) {
  Draw-Box $g $x 130 250 130 $PURPLE_SOFT $PURPLE $s[0] $s[1] $PURPLE $GREY
  if ($x -lt 1100) { Draw-Arrow $g ($x + 250) 195 ($x + 297) 195 $PURPLE $null }
  $x += 297
}

# Referral branch
Draw-Box $g 649 380 250 110 $WHITE $CORAL 'Referred'  'Care point cannot help' $CORAL $GREY
Draw-Box $g 946 380 250 110 $WHITE $CORAL 'Arrived at' 'Handover recorded' $CORAL $GREY
Draw-Arrow $g 774 260 774 380 $CORAL 'if onward care needed'
Draw-Arrow $g 899 435 946 435 $CORAL $null
Draw-Arrow $g 1196 435 1276 435 $CORAL $null
Draw-Arrow $g 1276 435 1276 260 $CORAL $null

$f = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Italic)
$g.DrawString('Each transition writes a timestamped event, so response time, on-scene time and transport time are all measurable after the fact.',
  $f, (New-Object System.Drawing.SolidBrush($GREY)), (New-Object System.Drawing.PointF(55, 545)))

$bmp.Save("$OUT\lifecycle.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# ── 3. Responder verification pipeline ───────────────────────────────────────
$r = New-Canvas 1500 560; $bmp = $r[0]; $g = $r[1]

Draw-Caption $g 40 30 1420 'Responder verification - nobody self-registers onto the network'

Draw-Box $g 55  130 300 130 $WHITE $RULE 'Registers as a user' 'Signs up in the app like any citizen' $INK $GREY
Draw-Box $g 420 130 300 130 $WHITE $RULE 'Admin promotes'      'Role, organisation, public or private' $INK $GREY
Draw-Box $g 785 130 300 130 $PURPLE_SOFT $PURPLE 'Pending'     'Credentials under review' $PURPLE $GREY

Draw-Arrow $g 355 195 420 195 $PURPLE $null
Draw-Arrow $g 720 195 785 195 $PURPLE $null

Draw-Box $g 1150 60  300 110 $WHITE $GREEN 'Verified'  'Can go on duty' $GREEN $GREY
Draw-Box $g 1150 220 300 110 $WHITE $CORAL 'Rejected'  'Reason recorded' $CORAL $GREY
Draw-Box $g 1150 370 300 110 $WHITE $CORAL 'Suspended' 'Removed from duty' $CORAL $GREY

Draw-Arrow $g 1085 175 1150 115 $GREEN $null
Draw-Arrow $g 1085 215 1150 275 $CORAL $null
Draw-Arrow $g 1085 250 1150 425 $CORAL $null

$f = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Italic)
$g.DrawString('Only a verified responder can go on duty. Rejecting or suspending immediately removes them from the live network.',
  $f, (New-Object System.Drawing.SolidBrush($GREY)), (New-Object System.Drawing.PointF(55, 500)))

$bmp.Save("$OUT\verification.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# ── 4. Public vs private routing ─────────────────────────────────────────────
$r = New-Canvas 1500 620; $bmp = $r[0]; $g = $r[1]

Draw-Caption $g 40 30 1420 'Dispatch routing - public network and private providers on the same platform'

Draw-Box $g 55 230 300 130 $PURPLE $null 'SOS raised' 'Caller presses the button' $WHITE ([System.Drawing.Color]::FromArgb(210,200,220))

Draw-Box $g 440 210 320 170 $WHITE $PURPLE 'Registered with a private provider?' '' $PURPLE $GREY
Draw-Arrow $g 355 295 440 295 $PURPLE $null

Draw-Box $g 870 90  560 140 $WHITE $CORAL 'Their provider only' "That company's own crew is dispatched directly. No public responder sees the call." $CORAL $GREY
Draw-Box $g 870 360 560 140 $WHITE $GREEN 'Public network'      'Any nearby verified responder can accept. Private crews never see it.' $GREEN $GREY

Draw-Arrow $g 760 260 870 160 $CORAL 'yes'
Draw-Arrow $g 760 330 870 430 $GREEN 'no'

$f = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Italic)
$g.DrawString('Routing is decided once, when the incident is created, so a lapsing subscription cannot reassign an emergency mid-response.',
  $f, (New-Object System.Drawing.SolidBrush($GREY)), (New-Object System.Drawing.PointF(55, 550)))

$bmp.Save("$OUT\routing.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

Get-ChildItem "$OUT\*.png" | Select-Object Name, @{n='KB';e={[math]::Round($_.Length/1KB)}} | Format-Table -AutoSize

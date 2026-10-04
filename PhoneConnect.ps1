#Requires -Version 5.1
# Phone Connect - a simple GUI wrapper around adb + scrcpy
# Lives in the scrcpy folder and calls the adb.exe / scrcpy.exe next to it.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Adb       = Join-Path $ScriptDir 'adb.exe'
$Scrcpy    = Join-Path $ScriptDir 'scrcpy.exe'
$IconPath  = Join-Path $ScriptDir 'PhoneConnect.ico'
$ExePath   = Join-Path $ScriptDir 'PhoneConnect.exe'
$ConfigPath = Join-Path $ScriptDir 'phoneconnect.config.json'

# ---- config (remembers last IP / port) ----
$cfg = [ordered]@{ connectIp = '192.168.18.2'; connectPort = ''; }
if (Test-Path $ConfigPath) {
    try {
        $loaded = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        if ($loaded.connectIp)   { $cfg.connectIp   = $loaded.connectIp }
        # port changes every time Wireless debugging is toggled, so always start blank
        if (-not $loaded.connectIp -and $loaded.connectAddr -and $loaded.connectAddr -match '^([^:]+):(\d*)') {  # migrate old ip
            $cfg.connectIp = $matches[1]
        }
    } catch {}
}
function Save-Config {
    try {
        [ordered]@{ connectIp = $txtIp.Text; connectPort = $txtPort.Text } |
            ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
    } catch {}
}

# ---- colors / fonts ----
$bg     = [System.Drawing.Color]::FromArgb(30,30,38)
$panel  = [System.Drawing.Color]::FromArgb(42,42,54)
$accent = [System.Drawing.Color]::FromArgb(88,166,255)
$green  = [System.Drawing.Color]::FromArgb(63,185,80)
$red    = [System.Drawing.Color]::FromArgb(200,64,64)
$text   = [System.Drawing.Color]::FromArgb(230,230,235)
$muted  = [System.Drawing.Color]::FromArgb(150,150,165)
$fontUI    = New-Object System.Drawing.Font('Segoe UI',10)
$fontSmall = New-Object System.Drawing.Font('Segoe UI',8.5)
$fontMono  = New-Object System.Drawing.Font('Consolas',9)
$fontBig   = New-Object System.Drawing.Font('Segoe UI Semibold',11)

# ---- form ----
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Phone Connect'
# content spans x=14..520, so a 534-wide client gives equal 14px left/right margins
$form.ClientSize = New-Object System.Drawing.Size(534,572)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $bg
$form.ForeColor = $text
$form.Font = $fontUI
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
try {
    if (Test-Path $IconPath) { $form.Icon = New-Object System.Drawing.Icon($IconPath) }
    else { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($Scrcpy) }
} catch {}

function New-Label($t,$x,$y,$w,$h,$f,$c) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $t; $l.Location = New-Object System.Drawing.Point($x,$y)
    $l.Size = New-Object System.Drawing.Size($w,$h)
    if ($f) { $l.Font = $f }; if ($c) { $l.ForeColor = $c }
    $form.Controls.Add($l); return $l
}
function Style-Button($b,$fill) {
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $fill; $b.ForeColor = [System.Drawing.Color]::White
    $b.Cursor = 'Hand'; $b.Font = $fontUI
}
function New-TextBox($val,$x,$y,$w) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.AutoSize = $false   # otherwise height snaps to the font (~20px) and misaligns with buttons
    $t.Text = $val; $t.Location = New-Object System.Drawing.Point($x,$y)
    $t.Size = New-Object System.Drawing.Size($w,24)
    $t.BackColor = $panel; $t.ForeColor = $text; $t.BorderStyle = 'FixedSingle'
    $form.Controls.Add($t); return $t
}

New-Label '  Phone Connect' 0 12 180 28 $fontBig $accent | Out-Null
New-Label 'Connect by' 14 44 68 18 $fontSmall $muted | Out-Null
$btnModeUsb = New-Object System.Windows.Forms.Button
$btnModeUsb.Text = 'USB'; $btnModeUsb.Location = New-Object System.Drawing.Point(84,40)
$btnModeUsb.Size = New-Object System.Drawing.Size(70,24); Style-Button $btnModeUsb $panel; $btnModeUsb.Font = $fontSmall
$form.Controls.Add($btnModeUsb)
$btnModeCode = New-Object System.Windows.Forms.Button
$btnModeCode.Text = 'Wi-Fi code'; $btnModeCode.Location = New-Object System.Drawing.Point(156,40)
$btnModeCode.Size = New-Object System.Drawing.Size(96,24); Style-Button $btnModeCode $accent; $btnModeCode.Font = $fontSmall
$form.Controls.Add($btnModeCode)
$btnModeQr = New-Object System.Windows.Forms.Button
$btnModeQr.Text = 'QR code'; $btnModeQr.Location = New-Object System.Drawing.Point(254,40)
$btnModeQr.Size = New-Object System.Drawing.Size(84,24); Style-Button $btnModeQr $panel; $btnModeQr.Font = $fontSmall
$form.Controls.Add($btnModeQr)
$btnCheckUpd = New-Object System.Windows.Forms.Button
$btnCheckUpd.Text = 'Check update'; $btnCheckUpd.Location = New-Object System.Drawing.Point(232,12)
$btnCheckUpd.Size = New-Object System.Drawing.Size(92,26); Style-Button $btnCheckUpd $panel
$btnCheckUpd.Font = $fontSmall
$form.Controls.Add($btnCheckUpd)
$btnHelp = New-Object System.Windows.Forms.Button
$btnHelp.Text = 'How to use'; $btnHelp.Location = New-Object System.Drawing.Point(330,12)
$btnHelp.Size = New-Object System.Drawing.Size(88,26); Style-Button $btnHelp $accent
$btnHelp.Font = $fontSmall
$form.Controls.Add($btnHelp)
$btnShortcut = New-Object System.Windows.Forms.Button
$btnShortcut.Text = 'Add shortcut'; $btnShortcut.Location = New-Object System.Drawing.Point(424,12)
$btnShortcut.Size = New-Object System.Drawing.Size(96,26); Style-Button $btnShortcut $panel
$btnShortcut.Font = $fontSmall
$form.Controls.Add($btnShortcut)
$btnCheckUpd.BringToFront(); $btnHelp.BringToFront(); $btnShortcut.BringToFront()
$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = 'Update scrcpy'; $btnUpdate.Location = New-Object System.Drawing.Point(270,148)
$btnUpdate.Size = New-Object System.Drawing.Size(122,28); Style-Button $btnUpdate $green
$btnUpdate.Font = $fontSmall
$btnUpdate.Visible = $false
$form.Controls.Add($btnUpdate)

# ---- Connect section (IP | Port | Pairing code) ----
$script:usbSerial = $null
$lblIp   = New-Label 'IP address' 14 70 118 18 $fontSmall $muted
$lblPort = New-Label 'Port'       138 70 58 18 $fontSmall $muted
$lblPcode = New-Label 'Pairing code' 202 70 140 18 $fontSmall $muted
$txtIp   = New-TextBox $cfg.connectIp   14 89 118
$txtPort = New-TextBox $cfg.connectPort 138 89 58
$txtCode = New-TextBox '' 202 89 94

$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Text = 'Connect'; $btnConnect.Location = New-Object System.Drawing.Point(302,89)
$btnConnect.Size = New-Object System.Drawing.Size(102,24); Style-Button $btnConnect $accent; $btnConnect.Font = $fontSmall
$form.Controls.Add($btnConnect)
$btnDisconnect = New-Object System.Windows.Forms.Button
$btnDisconnect.Text = 'Disconnect'; $btnDisconnect.Location = New-Object System.Drawing.Point(410,89)
$btnDisconnect.Size = New-Object System.Drawing.Size(110,24); Style-Button $btnDisconnect $panel; $btnDisconnect.Font = $fontSmall
$form.Controls.Add($btnDisconnect)
$lblCodeHelp = New-Label "Enter IP, Port & 6-digit code from 'Pair device with pairing code'." 14 116 506 18 $fontSmall $muted

# ---- utility buttons ----
$btnDevices = New-Object System.Windows.Forms.Button
$btnDevices.Text = 'Check devices'; $btnDevices.Location = New-Object System.Drawing.Point(14,148)
$btnDevices.Size = New-Object System.Drawing.Size(120,28); Style-Button $btnDevices $panel
$form.Controls.Add($btnDevices)
$btnRestart = New-Object System.Windows.Forms.Button
$btnRestart.Text = 'Restart ADB'; $btnRestart.Location = New-Object System.Drawing.Point(142,148)
$btnRestart.Size = New-Object System.Drawing.Size(120,28); Style-Button $btnRestart $panel
$form.Controls.Add($btnRestart)
$lblUsbHelp = New-Label 'Enable USB debugging, plug in, tap Allow on the phone, then Detect. See How to use for details.' 14 70 506 36 $fontSmall $muted
$btnUsb = New-Object System.Windows.Forms.Button
$btnUsb.Text = 'Detect USB device'; $btnUsb.Location = New-Object System.Drawing.Point(14,108)
$btnUsb.Size = New-Object System.Drawing.Size(506,32); Style-Button $btnUsb $accent
$form.Controls.Add($btnUsb)
# ---- QR-code mode: embedded overlay panel ----
$qrPanel = New-Object System.Windows.Forms.Panel
$qrPanel.Location = New-Object System.Drawing.Point(8,64)
$qrPanel.Size = New-Object System.Drawing.Size(524,278)
$qrPanel.BackColor = $bg
$form.Controls.Add($qrPanel)
$lblQrHelp = New-Object System.Windows.Forms.Label
$lblQrHelp.Text = 'Phone: Wireless debugging > Pair device with QR code, then scan the code below.'
$lblQrHelp.Location = New-Object System.Drawing.Point(6,2)
$lblQrHelp.Size = New-Object System.Drawing.Size(512,32); $lblQrHelp.Font = $fontSmall; $lblQrHelp.ForeColor = $muted
$qrPanel.Controls.Add($lblQrHelp)
$qrWeb = New-Object System.Windows.Forms.WebBrowser
$qrWeb.Location = New-Object System.Drawing.Point(162,36)
$qrWeb.Size = New-Object System.Drawing.Size(200,200); $qrWeb.ScrollBarsEnabled = $false
$qrWeb.IsWebBrowserContextMenuEnabled = $false; $qrWeb.WebBrowserShortcutsEnabled = $false; $qrWeb.AllowWebBrowserDrop = $false
$qrPanel.Controls.Add($qrWeb)
$btnQrStart = New-Object System.Windows.Forms.Button
$btnQrStart.Text = 'Show QR code'; $btnQrStart.Location = New-Object System.Drawing.Point(96,242)
$btnQrStart.Size = New-Object System.Drawing.Size(160,30); Style-Button $btnQrStart $accent
$qrPanel.Controls.Add($btnQrStart)
$btnQrStop = New-Object System.Windows.Forms.Button
$btnQrStop.Text = 'Stop'; $btnQrStop.Location = New-Object System.Drawing.Point(268,242)
$btnQrStop.Size = New-Object System.Drawing.Size(160,30); Style-Button $btnQrStop $panel
$qrPanel.Controls.Add($btnQrStop)

# ---- mirroring options ----
New-Label 'Mirroring options' 14 188 160 18 $null $accent | Out-Null
function New-Toggle($txt,$x,$y,$w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $txt; $b.Location = New-Object System.Drawing.Point($x,$y)
    $b.Size = New-Object System.Drawing.Size($w,26); Style-Button $b $panel; $b.Font = $fontSmall
    $b.Tag = $false
    $b.Add_Click({ $this.Tag = -not $this.Tag; if ($this.Tag) { $this.BackColor = $accent } else { $this.BackColor = $panel } })
    $form.Controls.Add($b); return $b
}
$btnOnTop   = New-Toggle 'Always on top'   14  212 110
$btnHiRes   = New-Toggle 'High resolution' 130 212 116
$btnNoAudio = New-Toggle 'No audio'        252 212 72
$btnMaxFps  = New-Toggle 'Limit FPS'       330 212 74
$txtMaxFps  = New-TextBox '30' 410 213 40
# High resolution ON by default; No audio OFF by default
$btnHiRes.Tag = $true; $btnHiRes.BackColor = $accent
# ---- recording & capture row ----
$btnRecord = New-Object System.Windows.Forms.Button
$btnRecord.Text = 'Record'; $btnRecord.Location = New-Object System.Drawing.Point(14,246)
$btnRecord.Size = New-Object System.Drawing.Size(160,24); Style-Button $btnRecord $panel
$form.Controls.Add($btnRecord)
$btnShot = New-Object System.Windows.Forms.Button
$btnShot.Text = 'Screenshot'; $btnShot.Location = New-Object System.Drawing.Point(184,246)
$btnShot.Size = New-Object System.Drawing.Size(160,24); Style-Button $btnShot $panel
$form.Controls.Add($btnShot)
$btnOpenRec = New-Object System.Windows.Forms.Button
$btnOpenRec.Text = 'Open folder'; $btnOpenRec.Location = New-Object System.Drawing.Point(14,271)
$btnOpenRec.Size = New-Object System.Drawing.Size(160,18); Style-Button $btnOpenRec $panel
$btnOpenRec.Font = $fontSmall
$form.Controls.Add($btnOpenRec)
$btnOpenShot = New-Object System.Windows.Forms.Button
$btnOpenShot.Text = 'Open folder'; $btnOpenShot.Location = New-Object System.Drawing.Point(184,271)
$btnOpenShot.Size = New-Object System.Drawing.Size(160,18); Style-Button $btnOpenShot $panel
$btnOpenShot.Font = $fontSmall
$form.Controls.Add($btnOpenShot)
# ---- big start button ----
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'Start Mirroring'; $btnStart.Location = New-Object System.Drawing.Point(14,294)
$btnStart.Size = New-Object System.Drawing.Size(506,44); Style-Button $btnStart $green
$btnStart.Font = $fontBig
$form.Controls.Add($btnStart)
$lblNoDevice = New-Object System.Windows.Forms.Label
$lblNoDevice.Location = New-Object System.Drawing.Point(14,340); $lblNoDevice.Size = New-Object System.Drawing.Size(506,18)
$lblNoDevice.Font = $fontSmall; $lblNoDevice.ForeColor = $red; $lblNoDevice.TextAlign = 'MiddleCenter'
$lblNoDevice.Text = 'No device detected - connect your phone first (USB / Wi-Fi code / QR code).'
$lblNoDevice.Visible = $false
$form.Controls.Add($lblNoDevice)

# ---- log boxes (left: activity, right: scrcpy live) ----
New-Label 'Activity' 14 360 240 18 $fontSmall $muted | Out-Null
New-Label 'Live output' 264 360 130 18 $fontSmall $muted | Out-Null
$lblFps = New-Object System.Windows.Forms.Label
$lblFps.Location = New-Object System.Drawing.Point(398,360); $lblFps.Size = New-Object System.Drawing.Size(122,18)
$lblFps.Font = $fontSmall; $lblFps.ForeColor = [System.Drawing.Color]::FromArgb(130,200,235); $lblFps.TextAlign = 'MiddleRight'
$lblFps.Text = 'FPS: --'
$form.Controls.Add($lblFps)
$log = New-Object System.Windows.Forms.RichTextBox
$log.Location = New-Object System.Drawing.Point(14,380)
$log.Size = New-Object System.Drawing.Size(242,150)
$log.ScrollBars = 'Vertical'; $log.ReadOnly = $true; $log.WordWrap = $true; $log.DetectUrls = $false
$log.BorderStyle = 'FixedSingle'
$log.BackColor = [System.Drawing.Color]::FromArgb(20,20,26); $log.ForeColor = $green
$log.Font = $fontMono
$form.Controls.Add($log)
$scrcpyLog = New-Object System.Windows.Forms.TextBox
$scrcpyLog.Location = New-Object System.Drawing.Point(264,380)
$scrcpyLog.Size = New-Object System.Drawing.Size(256,150)
$scrcpyLog.Multiline = $true; $scrcpyLog.ScrollBars = 'Vertical'; $scrcpyLog.ReadOnly = $true; $scrcpyLog.WordWrap = $true
$scrcpyLog.BackColor = [System.Drawing.Color]::FromArgb(20,20,26); $scrcpyLog.ForeColor = [System.Drawing.Color]::FromArgb(130,200,235)
$scrcpyLog.Font = $fontMono
$form.Controls.Add($scrcpyLog)

$statusBar = New-Object System.Windows.Forms.Label
$statusBar.Location = New-Object System.Drawing.Point(14,536)
$statusBar.Size = New-Object System.Drawing.Size(380,20)
$statusBar.ForeColor = $muted; $statusBar.Font = $fontSmall
$statusBar.Text = 'Ready.'
$form.Controls.Add($statusBar)
$lblVer = New-Object System.Windows.Forms.Label
$lblVer.Location = New-Object System.Drawing.Point(400,536)
$lblVer.Size = New-Object System.Drawing.Size(120,20)
$lblVer.ForeColor = $muted; $lblVer.Font = $fontSmall; $lblVer.TextAlign = 'MiddleRight'
$lblVer.Text = ''
$form.Controls.Add($lblVer)

# ---- helpers ----
$script:logColErr  = [System.Drawing.Color]::FromArgb(240,95,95)
$script:logColOk   = [System.Drawing.Color]::FromArgb(90,225,130)
$script:logColWarn = [System.Drawing.Color]::FromArgb(240,190,80)
$script:logColInfo = [System.Drawing.Color]::FromArgb(120,165,140)
function Write-Log($msg, $level) {
    $ts = Get-Date -Format 'HH:mm:ss'
    if (-not $level) {
        if     ($msg -match '(?i)\b(error|fail|failed|cannot|not found|missing|no device|offline|unauthorized|denied|timed out|interrupted)\b') { $level = 'err' }
        elseif ($msg -match '(?i)\b(warning|not saved|could not|retry|stopped)\b') { $level = 'warn' }
        elseif ($msg -match '(?i)\b(success|saved|connected|reconnected|paired|detected|ready|done|started|mirroring|recording to)\b') { $level = 'ok' }
        else   { $level = 'info' }
    }
    $color = switch ($level) {
        'err'  { $script:logColErr }
        'warn' { $script:logColWarn }
        'ok'   { $script:logColOk }
        default { $script:logColInfo }
    }
    # timestamp in muted grey
    $log.SelectionStart = $log.TextLength; $log.SelectionLength = 0
    $log.SelectionColor = $muted; $log.SelectionFont = $log.Font
    $log.AppendText("[$ts] ")
    # message in its level colour (bold for errors / key successes so they stand out)
    $log.SelectionStart = $log.TextLength; $log.SelectionLength = 0
    $log.SelectionColor = $color
    if ($level -eq 'err' -or $level -eq 'ok') {
        $log.SelectionFont = New-Object System.Drawing.Font($log.Font,[System.Drawing.FontStyle]::Bold)
    } else {
        $log.SelectionFont = $log.Font
    }
    $log.AppendText("$msg`r`n")
    $log.SelectionStart = $log.TextLength; $log.SelectionLength = 0
    $log.SelectionColor = $log.ForeColor; $log.SelectionFont = $log.Font
    $log.ScrollToCaret()
}
function Get-LocalScrcpyVersion {
    try {
        $v = (& $Scrcpy --version 2>&1 | Out-String)
        if ($v -match 'scrcpy\s+v?([0-9]+(?:\.[0-9]+)+)') { return $matches[1] }
    } catch {}
    return $null
}
function Get-LatestRelease {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    return Invoke-RestMethod -Uri 'https://api.github.com/repos/Genymobile/scrcpy/releases/latest' `
        -Headers @{ 'User-Agent' = 'PhoneConnect'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 20
}
function Run-Adb {
    param([string[]]$CmdArgs, [string]$Doing)
    if (-not (Test-Path $Adb)) { Write-Log "ERROR: adb.exe not found next to this tool."; return }
    $statusBar.Text = $Doing
    Write-Log (">> adb " + ($CmdArgs -join ' '))
    $form.Refresh()
    try {
        $out = & $Adb @CmdArgs 2>&1 | Out-String
        $out = $out.Trim()
        if ($out) { Write-Log $out }
        $statusBar.Text = 'Ready.'
    } catch {
        Write-Log ("ERROR: " + $_.Exception.Message)
        $statusBar.Text = 'Error - see output.'
    }
}

# ---- button actions ----
$btnConnect.Add_Click({
    $ip   = $txtIp.Text.Trim()
    $port = $txtPort.Text.Trim()
    $code = $txtCode.Text.Trim()
    if (-not $ip)   { Write-Log 'Enter the IP address, e.g. 192.168.18.2'; return }
    if ($port -notmatch '^\d+$') { Write-Log 'Enter the numeric Port, e.g. 37123'; return }
    $addr = "$($ip):$($port)"
    $script:usbSerial = $null   # prefer this wireless device for mirroring
    Save-Config
    if ($code) {
        Run-Adb -CmdArgs @('pair',$addr,$code) -Doing "Pairing with $addr ..."
        Start-Sleep -Milliseconds 1800
        Write-Log 'Checking whether the phone connected ...'
        Run-Adb -CmdArgs @('devices','-l') -Doing 'Listing devices ...'
        Write-Log 'If a device is listed above you are ready - just Start Mirroring.'
    } else {
        Run-Adb -CmdArgs @('connect',$addr) -Doing "Connecting to $addr ..."
    }
    Start-Sleep -Milliseconds 400
    if (Test-DeviceConnected) { $lblNoDevice.Visible = $false }
})
$btnUsb.Add_Click({
    if (-not (Test-Path $Adb)) { Write-Log 'ERROR: adb.exe not found next to this tool.'; return }
    $statusBar.Text = 'Checking USB ...'
    Write-Log '>> adb devices -l'
    $form.Refresh()
    try {
        $out = (& $Adb devices -l 2>&1 | Out-String).Trim()
        if ($out) { Write-Log $out }
        $usb = @()
        foreach ($ln in ($out -split "`r?`n")) {
            $ln = $ln.Trim()
            if ($ln -match '^List') { continue }
            if ($ln -match '^(\S+)\s+device\b') {
                $serial = $matches[1]
                if ($serial -notmatch ':\d+$') { $usb += $serial }   # IP:port => wireless; otherwise USB
            }
        }
        if ($usb.Count -gt 0) {
            $script:usbSerial = $usb[0]
            Write-Log "USB device ready: $($usb[0]).  Click Start Mirroring."
            $statusBar.Text = "USB device: $($usb[0])"
        } else {
            $script:usbSerial = $null
            Write-Log 'No USB device found. Plug in the phone, enable USB debugging, and tap "Allow" on the phone.'
            $statusBar.Text = 'No USB device.'
        }
    } catch {
        Write-Log ('ERROR: ' + $_.Exception.Message)
        $statusBar.Text = 'Error - see output.'
    }
})
$btnDisconnect.Add_Click({
    $ip = $txtIp.Text.Trim(); $port = $txtPort.Text.Trim()
    if ($ip -and $port -match '^\d+$') { Run-Adb -CmdArgs @('disconnect',"$($ip):$($port)") -Doing 'Disconnecting ...' }
    else { Run-Adb -CmdArgs @('disconnect') -Doing 'Disconnecting all ...' }
    $script:usbSerial = $null
    Start-Sleep -Milliseconds 400
    if (-not (Test-DeviceConnected)) {
        $lblNoDevice.Visible = $true
        $statusBar.Text = 'Disconnected - no device.'
    } else {
        $lblNoDevice.Visible = $false
        $statusBar.Text = 'A device is still connected.'
    }
})
$script:qrTimer = $null
$script:qrService = $null
$script:qrPassword = $null
$script:qrTries = 0
function Clear-QrImage {
    try { $qrWeb.DocumentText = '<html><body style="background:#1e1e26;margin:0"></body></html>' } catch {}
}
function Stop-QrPolling {
    if ($script:qrTimer) { $script:qrTimer.Stop(); $script:qrTimer.Dispose(); $script:qrTimer = $null }
}
function Show-QrImage($html) {
    $qrWeb.DocumentText = $html
}

$script:mode = 'code'
function Set-Mode($m) {
    $script:mode = $m
    $isCode = ($m -eq 'code'); $isUsb = ($m -eq 'usb'); $isQr = ($m -eq 'qr')
    foreach ($c in @($lblIp,$lblPort,$lblPcode,$txtIp,$txtPort,$txtCode,$btnConnect,$btnDisconnect,$lblCodeHelp)) { $c.Visible = $isCode }
    foreach ($c in @($lblUsbHelp,$btnUsb)) { $c.Visible = $isUsb }
    $qrPanel.Visible = $isQr
    if ($isQr) { $qrPanel.BringToFront() } else { Clear-QrImage }
    $on = [System.Drawing.Color]::White
    $btnModeUsb.BackColor  = $(if($isUsb){$accent}else{$panel});  $btnModeUsb.ForeColor  = $(if($isUsb){$on}else{$muted})
    $btnModeCode.BackColor = $(if($isCode){$accent}else{$panel}); $btnModeCode.ForeColor = $(if($isCode){$on}else{$muted})
    $btnModeQr.BackColor   = $(if($isQr){$accent}else{$panel});   $btnModeQr.ForeColor   = $(if($isQr){$on}else{$muted})
    if (-not $isUsb) { $script:usbSerial = $null }
    if (-not $isQr) { Stop-QrPolling }
    $statusBar.Text = $(switch($m){ 'usb'{'USB mode.'} 'qr'{'QR-code mode.'} default{'Wi-Fi (code) mode.'} })
}
$btnModeUsb.Add_Click({ Set-Mode 'usb' })
$btnModeCode.Add_Click({ Set-Mode 'code' })
$btnModeQr.Add_Click({ Set-Mode 'qr' })

$btnQrStart.Add_Click({
    if (-not (Test-Path $Adb)) { Write-Log 'ERROR: adb.exe not found next to this tool.'; return }
    $qrLib = Join-Path $ScriptDir 'qrcode.min.js'
    if (-not (Test-Path $qrLib)) { Write-Log 'ERROR: qrcode.min.js is missing, cannot draw the QR.'; return }
    $rng = [Guid]::NewGuid().ToString('N')
    $script:qrService  = 'ADB_WIFI_' + $rng.Substring(0,8)
    $script:qrPassword = $rng.Substring(8,12)
    $content = "WIFI:T:ADB;S:$($script:qrService);P:$($script:qrPassword);;"
    $lib = Get-Content $qrLib -Raw
    $html = @"
<!-- saved from url=(0014)about:internet -->
<!doctype html><html><head><meta charset='utf-8'>
<style>html,body{margin:0;background:#fff;overflow:hidden}
#qr{position:absolute;top:0px;left:0px;width:200px;height:200px}
#qr table{margin:0 auto;border-collapse:collapse}#qr img{display:block;margin:0 auto}</style></head>
<body><div id='qr'></div>
<script>$lib</script>
<script>new QRCode(document.getElementById('qr'),{text:'$content',width:200,height:200,correctLevel:QRCode.CorrectLevel.L});</script>
</body></html>
"@
    Stop-QrPolling
    $script:qrTries = 0
    Show-QrImage $html
    Write-Log 'QR shown in the app window. On the phone: Wireless debugging > Pair device with QR code, then scan it.'
    $statusBar.Text = 'Waiting for the phone to scan ...'
    $script:qrTimer = New-Object System.Windows.Forms.Timer
    $script:qrTimer.Interval = 1500
    $script:qrTimer.Add_Tick({
        $script:qrTries++
        if ($script:qrTries -gt 60) { Stop-QrPolling; Write-Log 'QR pairing timed out (90s). Click "Show QR code" to try again.'; $statusBar.Text = 'QR timed out.'; return }
        try {
            $svc = (& $Adb mdns services 2>&1 | Out-String)
            $ipport = $null
            foreach ($ln in ($svc -split "`r?`n")) {
                if ($ln -match 'adb-tls-pairing') {
                    $parts = @($ln -split '\s+' | Where-Object { $_ -ne '' })
                    if ($parts.Count -ge 3) {
                        $name = $parts[0]; $addr = $parts[-1]
                        if ($name -eq $script:qrService) { $ipport = $addr; break }
                        elseif (-not $ipport) { $ipport = $addr }
                    }
                }
            }
            if ($ipport) {
                Stop-QrPolling
                Write-Log "Phone detected at $ipport - pairing ..."; $statusBar.Text = 'Pairing ...'; $form.Refresh()
                $out = (& $Adb pair $ipport $script:qrPassword 2>&1 | Out-String).Trim()
                if ($out) { Write-Log $out }
                Start-Sleep -Milliseconds 1200
                $dev = (& $Adb devices -l 2>&1 | Out-String).Trim()
                if ($dev) { Write-Log $dev }
                if ($out -match 'Successfully paired') {
                    Write-Log 'Paired via QR. The phone auto-connects shortly - then click Start Mirroring.'
                    $statusBar.Text = 'QR paired.'
                    Set-Mode 'code'
                } else {
                    $statusBar.Text = 'QR pairing finished - see output.'
                }
            }
        } catch { Stop-QrPolling; Write-Log ('ERROR during QR pairing: ' + $_.Exception.Message); $statusBar.Text = 'Error - see output.' }
    })
    $script:qrTimer.Start()
})
$btnQrStop.Add_Click({ Stop-QrPolling; Clear-QrImage; Write-Log 'QR pairing stopped.'; $statusBar.Text = 'Ready.' })

$btnHelp.Add_Click({
    $guide = @"
<!-- saved from url=(0014)about:internet -->
<!doctype html><html><head><meta charset='utf-8'>
<style>
body{font-family:Segoe UI,Arial;background:#1e1e26;color:#e6e6eb;margin:0;padding:18px 22px;line-height:1.55}
h1{color:#58a6ff;font-size:20px;margin:0 0 4px}
h2{color:#58a6ff;font-size:15px;margin:18px 0 6px;border-bottom:1px solid #3a3a48;padding-bottom:3px}
p,li{font-size:13px;color:#d4d4dc} b{color:#fff}
ul{margin:4px 0 4px 0;padding-left:20px} li{margin:3px 0}
code{background:#2a2a36;color:#9fe1cb;padding:1px 5px;border-radius:4px;font-family:Consolas}
.muted{color:#9a9aa5;font-size:12px} table{border-collapse:collapse;margin:4px 0}
td{padding:2px 10px 2px 0;font-size:13px;color:#d4d4dc} td.k{color:#9fe1cb;font-family:Consolas;white-space:nowrap}
</style></head><body>
<h1>Phone Connect - How to use</h1>
<p class='muted'>Mirror and control your Android phone with scrcpy + adb. Pick a connection method, connect, then Start Mirroring.</p>

<h2>Connect by: USB</h2>
<ul>
<li>On the phone, enable <b>Developer options &gt; USB debugging</b>.</li>
<li>Plug the phone into the PC and tap <b>Allow</b> on the "Allow USB debugging?" prompt.</li>
<li>Click <b>Detect USB device</b>. When it is found, click <b>Start Mirroring</b>.</li>
<li>USB gives the lowest latency - use it if Wi-Fi feels laggy.</li>
</ul>

<h2>Connect by: Wi-Fi code</h2>
<ul>
<li>On the phone: <b>Developer options &gt; Wireless debugging</b> (turn it on).</li>
<li><b>First time (pairing):</b> open <b>Pair device with pairing code</b>. Enter that screen's IP in <b>IP address</b>, its Port in <b>Port</b>, and the 6-digit code in <b>Pairing code</b>, then <b>Connect</b>.</li>
<li><b>Reconnecting (already paired):</b> use the IP and Port shown on the <b>main</b> Wireless debugging screen, leave <b>Pairing code</b> blank, then <b>Connect</b>.</li>
<li>Note: the pairing Port and the connect Port are different numbers, and the Port changes each time Wireless debugging is toggled off/on.</li>
</ul>

<h2>Connect by: QR code</h2>
<ul>
<li>On the phone: <b>Wireless debugging &gt; Pair device with QR code</b>.</li>
<li>Click <b>Show QR code</b> and scan the code shown in the app. Pairing and connecting finish automatically.</li>
</ul>

<h2>Mirroring</h2>
<ul>
<li><b>Start Mirroring</b> opens the live screen; the button becomes <b>Stop Mirroring</b>. Closing the mirror window also stops it.</li>
<li>If no device is found it tries to reconnect to the last IP:Port; if that fails it shows "No device detected".</li>
<li><b>Always on top</b>: keep the mirror window above other windows.</li>
<li><b>High resolution</b> (on by default): full-resolution capture. Turn it off for a smaller, lower-latency stream (handy over Wi-Fi).</li>
<li><b>No audio</b>: turn on to drop audio for less overhead. <b>Limit FPS</b>: cap the frame rate to the number in the box.</li>
<li>These options apply to both mirroring and recording.</li>
</ul>

<h2>Recording &amp; screenshots</h2>
<ul>
<li><b>Record</b> starts a recording; the button turns red and reads <b>Stop rec</b>. Click it (or close the mirror window) to save.</li>
<li>Recordings save to <code>recordings\</code> as timestamped <code>.mkv</code> files. Use the <b>Open folder</b> button under <b>Record</b> to find them.</li>
<li><b>Screenshot</b> saves a PNG to <code>screenshots\</code>; its <b>Open folder</b> button opens that folder.</li>
</ul>

<h2>Output panels</h2>
<ul>
<li><b>Activity</b> (left): your clicks and plain-English results.</li>
<li><b>Live output</b> (right): scrcpy's live messages - useful if something fails.</li>
</ul>

<h2>Troubleshooting</h2>
<ul>
<li><b>No device detected:</b> reconnect (USB / Wi-Fi code / QR), then <b>Check devices</b>. If the phone's IP or Port changed, re-enter them.</li>
<li><b>Laggy / delayed:</b> turn off <b>High resolution</b> (and optionally on <b>No audio</b>), use 5 GHz Wi-Fi near the router, or connect by USB.</li>
<li><b>Connection stuck:</b> click <b>Restart ADB</b>, then connect again.</li>
<li><b>Recording didn't save:</b> use <b>Stop rec</b> or close the mirror window (do not force-kill); check the Live output panel for the reason.</li>
</ul>
</body></html>
"@
    $gf = New-Object System.Windows.Forms.Form
    $gf.Text = 'Phone Connect - How to use'
    $gf.Size = New-Object System.Drawing.Size(620,680)
    $gf.StartPosition = 'CenterParent'
    $gf.BackColor = [System.Drawing.Color]::FromArgb(30,30,38)
    $gw = New-Object System.Windows.Forms.WebBrowser
    $gw.Dock = 'Fill'; $gw.IsWebBrowserContextMenuEnabled = $false; $gw.AllowWebBrowserDrop = $false
    $gw.DocumentText = $guide
    $gf.Controls.Add($gw)
    $gf.Show($form)
})
$btnShortcut.Add_Click({
    try {
        $targets = [ordered]@{
            'Desktop'    = (Join-Path ([Environment]::GetFolderPath('Desktop'))  'Phone Connect.lnk')
            'Start menu' = (Join-Path ([Environment]::GetFolderPath('Programs')) 'Phone Connect.lnk')
        }
        $ws = New-Object -ComObject WScript.Shell
        # prefer the compiled .exe (it carries the icon); fall back to powershell + script
        $useExe = Test-Path $ExePath
        $psExe  = (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
        $psArgs = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$(Join-Path $ScriptDir 'PhoneConnect.ps1')`""
        foreach ($where in $targets.Keys) {
            $lnkPath = $targets[$where]
            try { $dir = Split-Path $lnkPath -Parent; if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } } catch {}
            $lnk = $ws.CreateShortcut($lnkPath)
            if ($useExe) { $lnk.TargetPath = $ExePath; $lnk.Arguments = '' }
            else         { $lnk.TargetPath = $psExe;   $lnk.Arguments = $psArgs }
            $lnk.WorkingDirectory = $ScriptDir
            $lnk.WindowStyle = 7
            $lnk.Description = 'Phone Connect - scrcpy + adb'
            if (Test-Path $IconPath)      { $lnk.IconLocation = "$IconPath,0" }
            elseif (Test-Path $Scrcpy)    { $lnk.IconLocation = "$Scrcpy,0" }
            $lnk.Save()
            Write-Log "$where shortcut created: $lnkPath" 'ok'
        }
        $statusBar.Text = 'Shortcuts added (Desktop + Start menu).'
    } catch {
        Write-Log ('ERROR creating shortcut: ' + $_.Exception.Message)
        $statusBar.Text = 'Error - see output.'
    }
})
$btnCheckUpd.Add_Click({
    $statusBar.Text = 'Checking for updates ...'; $form.Refresh()
    $btnUpdate.Visible = $false
    $local = Get-LocalScrcpyVersion
    if ($local) { Write-Log "Installed scrcpy: $local" } else { Write-Log 'Could not read the installed scrcpy version.' }
    try {
        $rel = Get-LatestRelease
        $tag = $rel.tag_name; $latest = ($tag -replace '^v','')
        Write-Log "Latest release: $tag"
        if ($local) {
            try {
                if ([version]$latest -gt [version]$local) {
                    Write-Log "Update available: $local -> $latest.  Click 'Update scrcpy'."
                    $statusBar.Text = "Update available: $latest"
                    $btnUpdate.Text = "Update to $latest"; $btnUpdate.Visible = $true
                }
                elseif ([version]$latest -eq [version]$local) { Write-Log 'You are on the latest version.'; $statusBar.Text = 'Up to date.' }
                else { Write-Log 'Installed version is newer than the latest public release.'; $statusBar.Text = 'Up to date.' }
            } catch { Write-Log "Latest is $latest (could not compare version numbers)."; $statusBar.Text = "Latest: $latest" }
        } else { $statusBar.Text = "Latest: $latest" }
    } catch {
        Write-Log ('ERROR checking for updates: ' + $_.Exception.Message); $statusBar.Text = 'Error - see output.'
    }
})
$btnUpdate.Add_Click({
    try {
        $statusBar.Text = 'Checking latest release ...'; $form.Refresh()
        $rel = Get-LatestRelease
        $tag = $rel.tag_name
        $asset = $rel.assets | Where-Object { $_.name -match '^scrcpy-win64-.*\.zip$' } | Select-Object -First 1
        if (-not $asset) { Write-Log 'No win64 .zip asset found in the latest release.'; $statusBar.Text = 'Ready.'; return }
        $sizeMB = [math]::Round($asset.size / 1MB, 1)
        $msg = "Download and install scrcpy $tag?`n`nFile:   $($asset.name)`nSize:   $sizeMB MB`nSource: github.com/Genymobile/scrcpy`n`nClose any open mirror window first.`nYour settings and notes are kept."
        $res = [System.Windows.Forms.MessageBox]::Show($msg,'Update scrcpy',[System.Windows.Forms.MessageBoxButtons]::OKCancel,[System.Windows.Forms.MessageBoxIcon]::Question)
        if ($res -ne [System.Windows.Forms.DialogResult]::OK) { Write-Log 'Update cancelled.'; $statusBar.Text = 'Ready.'; return }

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $tmp = Join-Path $env:TEMP ('scrcpy_update_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $zip = Join-Path $tmp $asset.name
        Write-Log "Downloading $($asset.name) ($sizeMB MB) ..."; $statusBar.Text = 'Downloading ...'; $form.Refresh()
        $oldPref = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -Headers @{ 'User-Agent' = 'PhoneConnect' } -TimeoutSec 600
        } finally { $ProgressPreference = $oldPref }

        Write-Log 'Extracting ...'; $form.Refresh()
        $ex = Join-Path $tmp 'extract'
        Expand-Archive -Path $zip -DestinationPath $ex -Force
        $src = Get-ChildItem -Path $ex -Directory | Select-Object -First 1
        if (-not $src) { $src = Get-Item $ex }

        try { & $Adb kill-server 2>&1 | Out-Null } catch {}
        Start-Sleep -Milliseconds 500

        Write-Log 'Installing new files ...'; $statusBar.Text = 'Installing ...'; $form.Refresh()
        $failed = @()
        Get-ChildItem -Path $src.FullName -Recurse -File | ForEach-Object {
            $relPath = $_.FullName.Substring($src.FullName.Length).TrimStart('\','/')
            $dest = Join-Path $ScriptDir $relPath
            $destDir = Split-Path $dest -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            try { Copy-Item -Path $_.FullName -Destination $dest -Force -ErrorAction Stop } catch { $failed += $relPath }
        }
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue

        if ($failed.Count -gt 0) {
            Write-Log ('Some files were in use and were NOT updated (close scrcpy, then retry): ' + ($failed -join ', '))
            $statusBar.Text = 'Partial update - close scrcpy and retry.'
        } else {
            $new = Get-LocalScrcpyVersion
            Write-Log "Update complete. scrcpy is now: $new"
            $statusBar.Text = "Updated to $new"
            $btnUpdate.Visible = $false
        }
    } catch {
        Write-Log ('ERROR updating: ' + $_.Exception.Message); $statusBar.Text = 'Error - see output.'
    }
})
$btnDevices.Add_Click({ Run-Adb -CmdArgs @('devices','-l') -Doing 'Listing devices ...' })
$btnRestart.Add_Click({
    Run-Adb -CmdArgs @('kill-server')  -Doing 'Stopping ADB ...'
    Run-Adb -CmdArgs @('start-server') -Doing 'Starting ADB ...'
    Write-Log 'ADB restarted.'
})
$script:scrcpyProc = $null
$script:mirrorTimer = $null
$script:recording = $false
$script:recordFile = $null
$RecordDir = Join-Path $ScriptDir 'recordings'
$ShotDir   = Join-Path $ScriptDir 'screenshots'
function Set-MirrorButton($running) {
    if ($running) { $btnStart.Text = 'Stop Mirroring'; $btnStart.BackColor = $red }
    else { $btnStart.Text = 'Start Mirroring'; $btnStart.BackColor = $green }
}
function Set-RecIndicator {
    if ($script:recording) {
        $btnRecord.Text = 'Stop rec'; $btnRecord.BackColor = $red
    } else {
        $btnRecord.Text = 'Record'; $btnRecord.BackColor = $panel
    }
}
function Report-Recording($f) {
    if ($f -and (Test-Path $f)) {
        $mb = [math]::Round((Get-Item $f).Length / 1MB, 1)
        Write-Log "Recording saved: $f  ($mb MB)"; $statusBar.Text = 'Recording saved.'
    } else {
        Write-Log "WARNING: no recording file was created - see the scrcpy> lines above for the reason: $f"
        $statusBar.Text = 'Recording not saved.'
    }
}
function Stop-MirrorWatch {
    if ($script:mirrorTimer) { $script:mirrorTimer.Stop(); $script:mirrorTimer.Dispose(); $script:mirrorTimer = $null }
}
function Test-Mirroring {
    return ($script:scrcpyProc -and -not $script:scrcpyProc.HasExited)
}
function Test-DeviceConnected {
    if (-not (Test-Path $Adb)) { return $false }
    try {
        $out = (& $Adb devices 2>&1 | Out-String)
        foreach ($ln in ($out -split "`r?`n")) {
            $ln = $ln.Trim()
            if ($ln -match '^List') { continue }
            if ($ln -match '\sdevice$') { return $true }   # connected (not offline/unauthorized)
        }
    } catch {}
    return $false
}
function Send-Key($code, $name) {
    if (-not (Test-DeviceConnected)) { Write-Log "No device - cannot send $name."; return }
    $sel = @(); if ($script:usbSerial) { $sel = @('-s',$script:usbSerial) }
    try {
        $out = (& $Adb @sel shell input keyevent $code 2>&1 | Out-String)
        if ($out -match 'INJECT_EVENTS|SecurityException') {
            Write-Log "Could not send $name - this phone blocks input injection."
            Write-Log 'Fix: Developer options > enable "USB debugging (Security settings)". (Or control via the mirror window.)'
        } else { Write-Log "Sent: $name" }
    } catch { Write-Log ('ERROR: ' + $_.Exception.Message) }
}
function Go-Home {
    if (-not (Test-DeviceConnected)) { Write-Log 'No device - cannot go Home.'; return }
    $sel = @(); if ($script:usbSerial) { $sel = @('-s',$script:usbSerial) }
    try { & $Adb @sel shell am start -a android.intent.action.MAIN -c android.intent.category.HOME 2>&1 | Out-Null; Write-Log 'Sent: Home' }
    catch { Write-Log ('ERROR: ' + $_.Exception.Message) }
}
function Open-Notifications {
    if (-not (Test-DeviceConnected)) { Write-Log 'No device - cannot open notifications.'; return }
    $sel = @(); if ($script:usbSerial) { $sel = @('-s',$script:usbSerial) }
    try { & $Adb @sel shell cmd statusbar expand-notifications 2>&1 | Out-Null; Write-Log 'Opened notifications.' }
    catch { Write-Log ('ERROR: ' + $_.Exception.Message) }
}
function Take-Screenshot {
    if (-not (Test-Path $Adb)) { Write-Log 'ERROR: adb.exe not found next to this tool.'; return }
    try { if (-not (Test-Path $ShotDir)) { New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null } } catch {}
    $local = Join-Path $ShotDir ("shot_" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + ".png")
    $remote = '/sdcard/__pc_shot.png'
    $sel = @(); if ($script:usbSerial) { $sel = @('-s',$script:usbSerial) }
    $statusBar.Text = 'Taking screenshot ...'; Write-Log '>> adb screencap'; $form.Refresh()
    try {
        $e1 = (& $Adb @sel shell screencap -p $remote 2>&1 | Out-String).Trim(); if ($e1) { Write-Log $e1 }
        $e2 = (& $Adb @sel pull $remote $local 2>&1 | Out-String).Trim(); if ($e2) { Write-Log $e2 }
        & $Adb @sel shell rm $remote 2>&1 | Out-Null
        if (Test-Path $local) { Write-Log "Screenshot saved: $local"; $statusBar.Text = 'Screenshot saved.' }
        else { Write-Log 'Screenshot failed - is a device connected?'; $statusBar.Text = 'Screenshot failed.' }
    } catch { Write-Log ('ERROR: ' + $_.Exception.Message); $statusBar.Text = 'Error - see output.' }
}
function Get-BaseOpts {
    $opts = New-Object System.Collections.Generic.List[string]
    if ($script:usbSerial) { $opts.Add('-s'); $opts.Add($script:usbSerial) }
    if ($btnOnTop.Tag)  { $opts.Add('--always-on-top') }
    # Resolution: High resolution ON = full res; OFF = scaled down for lower latency.
    # These options apply to both mirroring and recording.
    if (-not $btnHiRes.Tag) {
        $opts.Add('--max-size');       $opts.Add('1280')
        $opts.Add('--video-bit-rate'); $opts.Add('4M')
        $opts.Add('--video-codec');    $opts.Add('h264')
    }
    # Audio: No audio ON = drop the audio pipeline.
    if ($btnNoAudio.Tag) { $opts.Add('--no-audio') }
    $opts.Add('--print-fps')
    if ($btnMaxFps.Tag) { $f = $txtMaxFps.Text.Trim(); if ($f -match '^\d+$') { $opts.Add("--max-fps=$f") } }
    return ,$opts
}
function Start-Watch {
    Stop-MirrorWatch
    $script:mirrorTimer = New-Object System.Windows.Forms.Timer
    $script:mirrorTimer.Interval = 1000
    $script:mirrorTimer.Add_Tick({
        Tail-ScrcpyLog
        if (-not (Test-Mirroring)) {
            Stop-MirrorWatch
            Tail-ScrcpyLog
            Stop-ScrcpyEvents
            $wasRec = $script:recording; $f = $script:recordFile
            $script:scrcpyProc = $null; $script:recording = $false
            Set-MirrorButton $false; Set-RecIndicator
            if ($wasRec) { Report-Recording $f }
            else { Write-Log 'Mirror window closed.'; $statusBar.Text = 'Ready.' }
        }
    })
    $script:mirrorTimer.Start()
}
$script:scrcpyLogFile = Join-Path $env:TEMP 'phoneconnect_scrcpy.log'
$script:scrcpyLogPos = 0
$script:scrcpyEvents = @()
function Stop-ScrcpyEvents {
    foreach ($sid in @('ScrcpyOut','ScrcpyErr')) { try { Unregister-Event -SourceIdentifier $sid -ErrorAction SilentlyContinue } catch {} }
    foreach ($j in $script:scrcpyEvents) { try { Remove-Job -Job $j -Force -ErrorAction SilentlyContinue } catch {} }
    $script:scrcpyEvents = @()
}
function Tail-ScrcpyLog {
    try {
        if (-not (Test-Path $script:scrcpyLogFile)) { return }
        $all = @(Get-Content $script:scrcpyLogFile -ErrorAction SilentlyContinue)
        if ($all.Count -gt $script:scrcpyLogPos) {
            for ($i = $script:scrcpyLogPos; $i -lt $all.Count; $i++) {
                $line = $all[$i]
                if (-not $line) { continue }
                if ($line -match '(\d+)\s+fps') { $lblFps.Text = "FPS: $($matches[1])" }      # FPS -> its own readout
                elseif ($line -match 'FPS counter started') { $lblFps.Text = 'FPS: 0' }
                else { $scrcpyLog.AppendText($line + "`r`n") }
            }
            $script:scrcpyLogPos = $all.Count
        }
    } catch {}
}
function Start-Scrcpy($recordPath) {
    if (-not (Test-Path $Scrcpy)) { Write-Log 'ERROR: scrcpy.exe not found next to this tool.'; return $false }
    if (-not (Test-DeviceConnected)) {
        # auto-reconnect to the last IP:Port before giving up
        $ip = $txtIp.Text.Trim(); $port = $txtPort.Text.Trim()
        if ($ip -and $port -match '^\d+$') {
            Write-Log "No device - trying to reconnect to $($ip):$($port) ..."
            $statusBar.Text = 'Reconnecting ...'; $form.Refresh()
            try { $r = (& $Adb connect "$($ip):$($port)" 2>&1 | Out-String).Trim(); if ($r) { Write-Log $r } } catch {}
            Start-Sleep -Milliseconds 1300
        }
        if (-not (Test-DeviceConnected)) {
            $lblNoDevice.Visible = $true
            Write-Log 'No device detected. Connect your phone first (USB / Wi-Fi code / QR code).'
            $statusBar.Text = 'No device detected.'
            return $false
        }
        Write-Log 'Reconnected.'
    }
    $lblNoDevice.Visible = $false
    $opts = Get-BaseOpts
    if ($recordPath) { $opts.Add('--record'); $opts.Add($recordPath) }
    Write-Log (">> scrcpy " + ($opts -join ' '))
    Stop-ScrcpyEvents
    try { Remove-Item $script:scrcpyLogFile -ErrorAction SilentlyContinue } catch {}
    $script:scrcpyLogPos = 0
    try { $scrcpyLog.Clear() } catch {}
    try { $lblFps.Text = 'FPS: --' } catch {}
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Scrcpy
        $psi.WorkingDirectory = $ScriptDir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.Arguments = ($opts | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' '
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        $writer = { if ($EventArgs.Data) { try { Add-Content -Path $Event.MessageData -Value $EventArgs.Data -Encoding UTF8 } catch {} } }
        $sa = Register-ObjectEvent -InputObject $p -EventName OutputDataReceived -SourceIdentifier 'ScrcpyOut' -MessageData $script:scrcpyLogFile -Action $writer
        $sb = Register-ObjectEvent -InputObject $p -EventName ErrorDataReceived  -SourceIdentifier 'ScrcpyErr' -MessageData $script:scrcpyLogFile -Action $writer
        $script:scrcpyEvents = @($sa,$sb)
        [void]$p.Start()
        $p.BeginOutputReadLine(); $p.BeginErrorReadLine()
        $script:scrcpyProc = $p
        $script:recording = [bool]$recordPath; $script:recordFile = $recordPath
        Set-MirrorButton $true; Set-RecIndicator; Start-Watch
        return $true
    } catch {
        Write-Log ("ERROR: " + $_.Exception.Message); Set-MirrorButton $false
        $script:recording = $false; Set-RecIndicator; Stop-ScrcpyEvents; return $false
    }
}
function Stop-Scrcpy {
    Stop-MirrorWatch                      # stop the watcher first so it cannot race us
    $proc   = $script:scrcpyProc
    $wasRec = $script:recording
    $f      = $script:recordFile
    if ($proc -and -not $proc.HasExited) {
        if ($wasRec) { Write-Log 'Finalizing recording ...'; $statusBar.Text = 'Finalizing recording ...'; $form.Refresh() }
        # make sure the scrcpy window exists so a graceful close can reach it
        $w = 0
        while ($w -lt 40 -and -not $proc.HasExited) { try { $proc.Refresh() } catch {}; if ($proc.MainWindowHandle -ne 0) { break }; Start-Sleep -Milliseconds 100; $w++ }
        $hwnd = 0; try { $hwnd = $proc.MainWindowHandle } catch {}
        $closed = $false; try { $closed = $proc.CloseMainWindow() } catch {}
        Write-Log "stop: hwnd=$hwnd  closeSent=$closed"
        $n = 0
        while (-not $proc.HasExited -and $n -lt 120) { Start-Sleep -Milliseconds 100; $n++ }   # up to 12s for a clean finalize
        if (-not $proc.HasExited) {
            try { $proc.Kill() } catch {}
            if ($wasRec) { Write-Log 'scrcpy did not close gracefully - recording may be incomplete.' }
        }
    }
    Start-Sleep -Milliseconds 200
    Tail-ScrcpyLog
    Stop-ScrcpyEvents
    $script:scrcpyProc = $null; $script:recording = $false
    Set-MirrorButton $false; Set-RecIndicator
    return @{ wasRec = $wasRec; file = $f }
}
$btnStart.Add_Click({
    if (-not (Test-Path $Scrcpy)) { Write-Log 'ERROR: scrcpy.exe not found next to this tool.'; return }
    if (Test-Mirroring) {
        $r = Stop-Scrcpy
        if ($r.wasRec) { Report-Recording $r.file }
        else { Write-Log 'Mirror stopped.'; $statusBar.Text = 'Mirror stopped.' }
        return
    }
    if (Start-Scrcpy $null) {
        Write-Log 'scrcpy launched. Click Stop Mirroring (or close the mirror window) to stop.'
        $statusBar.Text = 'Mirroring.'
    }
})
$btnRecord.Add_Click({
    if (-not (Test-Path $Scrcpy)) { Write-Log 'ERROR: scrcpy.exe not found next to this tool.'; return }
    # toggle: if a recording is running, stop and save
    if (Test-Mirroring -and $script:recording) {
        $r = Stop-Scrcpy
        Report-Recording $r.file
        return
    }
    if (Test-Mirroring) {
        Write-Log 'Stopping the plain mirror to start a recording ...'
        Stop-Scrcpy | Out-Null
    }
    try { if (-not (Test-Path $RecordDir)) { New-Item -ItemType Directory -Path $RecordDir -Force | Out-Null } } catch {}
    $file = Join-Path $RecordDir ("scrcpy_" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + ".mkv")
    if (Start-Scrcpy $file) {
        Write-Log "Recording to $file"
        Write-Log 'Click Stop rec (or close the mirror window) to save it.'
        $statusBar.Text = 'Recording ...'
    }
})
$btnOpenRec.Add_Click({
    try {
        if (-not (Test-Path $RecordDir)) { New-Item -ItemType Directory -Path $RecordDir -Force | Out-Null }
        Start-Process explorer.exe $RecordDir
    } catch { Write-Log ('ERROR opening folder: ' + $_.Exception.Message) }
})
$btnOpenShot.Add_Click({
    try {
        if (-not (Test-Path $ShotDir)) { New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null }
        Start-Process explorer.exe $ShotDir
    } catch { Write-Log ('ERROR opening folder: ' + $_.Exception.Message) }
})
$btnShot.Add_Click({ Take-Screenshot })

$form.Add_FormClosing({ if ($script:devTimer) { $script:devTimer.Stop() }; Stop-QrPolling; Stop-MirrorWatch; Stop-ScrcpyEvents; Save-Config })

# ---- auto-hide the "No device detected" warning once a device shows up (any mode) ----
$script:devTimer = New-Object System.Windows.Forms.Timer
$script:devTimer.Interval = 1500
$script:devTimer.Add_Tick({
    if ($lblNoDevice.Visible -and (Test-DeviceConnected)) {
        $lblNoDevice.Visible = $false
        $statusBar.Text = 'Device detected.'
    }
})
$script:devTimer.Start()

Set-Mode 'code'
Set-RecIndicator
$ver = Get-LocalScrcpyVersion
$lblVer.Text = $(if ($ver) { "scrcpy v$ver" } else { 'scrcpy' })
Write-Log 'Ready. Click "How to use" for a quick guide.'
[void]$form.ShowDialog()

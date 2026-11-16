<#
  Dreamcast CDI to CHD converter.
  Standalone mode: place this folder inside the folder containing CDI files,
  then double-click Start-Dreamcast-CDI-to-CHD.cmd.
  Original CDI files are never modified or deleted.

  v1.0.1
    - Extracted tracks are now ordered by track number (numeric sort), so a
      disc with 10+ tracks can no longer map track 10 before track 2.
    - Tracks are renamed in two phases, so a file can never overwrite another.
    - Dreamcast header check ("SEGA SEGAKATANA") on the extracted data track.
      It logs a warning by default; -StrictHeader turns it into a failure.
    - All log messages are now in English.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string]$Src = '',

  [Parameter(Mandatory = $false)]
  [string]$Out = '',

  [Parameter(Mandatory = $false)]
  [string]$Tools = '',

  [int]$Limit = 0,

  [switch]$DeleteTempOnError,

  # Fail the conversion if no data track starts with the Dreamcast header.
  [switch]$StrictHeader
)

$ErrorActionPreference = 'Stop'

# Standalone mode: this package is placed inside the folder containing the CDI files.
$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CollectionRoot = Split-Path -Parent $PackageRoot
if ([string]::IsNullOrWhiteSpace($Src)) { $Src = $CollectionRoot }
if ([string]::IsNullOrWhiteSpace($Out)) { $Out = Join-Path $CollectionRoot 'CHD' }
if ([string]::IsNullOrWhiteSpace($Tools)) { $Tools = Join-Path $PackageRoot 'tools' }

function Fail([string]$Message) {
  throw $Message
}

# Resolve paths and perform initial checks.
$Src = [IO.Path]::GetFullPath($Src)
$Out = [IO.Path]::GetFullPath($Out)
$Tools = [IO.Path]::GetFullPath($Tools)

if (-not (Test-Path -LiteralPath $Src -PathType Container)) {
  Fail "Source folder not found : $Src"
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$JournalDir = Join-Path $PackageRoot 'journal'
New-Item -ItemType Directory -Force -Path $JournalDir | Out-Null

$chdman = Join-Path $Tools 'chdman.exe'
$cdirip = Join-Path $Tools 'cdirip.exe'

foreach ($tool in @($chdman, $cdirip)) {
  if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
    Fail "Tool not found : $tool"
  }
}

$log = Join-Path $JournalDir 'cdi2chd_log.txt'

function Log([string]$Message) {
  $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  Write-Host $line
  Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}

function Log-Diagnostics([string]$Prefix, [object[]]$Output) {
  foreach ($line in $Output) {
    $text = ([string]$line).Trim()
    if ($text -and $text -match '(?i)(error|exception|fatal|failed|failure|input/output|invalid|cannot|unable)') {
      Log ("{0}: {1}" -f $Prefix, $text)
    }
  }
}

function Get-FileSize([string]$Path) {
  return ([IO.FileInfo]$Path).Length
}

function Test-ReadableFile([string]$Path) {
  $stream = $null
  try {
    $stream = [IO.File]::Open(
      $Path,
      [IO.FileMode]::Open,
      [IO.FileAccess]::Read,
      [IO.FileShare]::Read
    )
    return $true
  }
  catch {
    return $false
  }
  finally {
    if ($null -ne $stream) {
      $stream.Dispose()
    }
  }
}

# Builds a sort key from every number found in a file name, each padded to
# 8 digits, so that "track2" sorts before "track10" (plain name sort does not).
function Get-NumericSortKey([string]$Name) {
  $parts = @([regex]::Matches($Name, '\d+') | ForEach-Object { $_.Value.PadLeft(8, '0') })
  return ($parts -join '-')
}

# A Dreamcast data track (ISO, 2048 bytes/sector) starts with "SEGA SEGAKATANA ".
function Test-DreamcastHeader([string]$Path) {
  $stream = $null
  try {
    $stream = [IO.File]::Open(
      $Path,
      [IO.FileMode]::Open,
      [IO.FileAccess]::Read,
      [IO.FileShare]::Read
    )
    $buffer = New-Object byte[] 16
    $read = $stream.Read($buffer, 0, 16)
    if ($read -lt 16) { return $false }
    return ([Text.Encoding]::ASCII.GetString($buffer) -eq 'SEGA SEGAKATANA ')
  }
  catch {
    return $false
  }
  finally {
    if ($null -ne $stream) {
      $stream.Dispose()
    }
  }
}

$files = @(Get-ChildItem -LiteralPath $Src -Filter '*.cdi' -File | Sort-Object Name)
if ($Limit -gt 0) {
  $files = @($files | Select-Object -First $Limit)
}

Log "Start: $($files.Count) CDI file(s) found in $Src"

if ($files.Count -eq 0) {
  Log 'No CDI files to process.'
  exit 0
}

$ok = 0
$skip = 0
$fail = 0
[long]$before = 0
[long]$after = 0

foreach ($f in $files) {
  $name = [IO.Path]::GetFileNameWithoutExtension($f.Name)
  $dest = Join-Path $Out ($name + '.chd')
  $tmp = $null
  $success = $false

  if (Test-Path -LiteralPath $dest -PathType Leaf) {
    Log "SKIPPED (already exists): $name"
    $skip++
    continue
  }

  try {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('cdi2chd_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    Log "EXTRACTING: $name"

    # CDIRip syntax: cdirip image.cdi destination -iso -full
    # -iso converts Mode2/2336 tracks to ISO/2048 sectors.
    # This form is better accepted by chdman 0.289 than raw Mode2/2336
    # BIN files produced by cdirip.
    # -full also prevents CDIRip from automatically cutting two sectors
    # from the first track.
    # Older cdirip versions write part of their output
    # to stderr. With ErrorActionPreference=Stop, PowerShell would turn
    # this output into an exception before the program finishes.
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $cdiripOutput = @(& $cdirip $f.FullName $tmp '-iso' '-full' 2>&1)
      $cdiripExit = $LASTEXITCODE
    }
    finally {
      $ErrorActionPreference = $savedErrorActionPreference
    }

    if ($cdiripExit -ne 0) {
      Log-Diagnostics 'CDIRIP' $cdiripOutput
      Fail "cdirip.exe failed with exit code $cdiripExit"
    }

    $tracks = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($line in $cdiripOutput) {
      $text = [string]$line
      if ($text -match 'Saving\s+Track:\s+(\d+)\s+Type:\s+(\S+)\s+Size:\s+(\d+)\s+LBA:\s+(\d+)') {
        $tracks.Add([PSCustomObject]@{
          Num  = [int]$Matches[1]
          Type = $Matches[2]
          Size = [long]$Matches[3]
          Lba  = [int]$Matches[4]
        })
      }
    }

    if ($tracks.Count -eq 0) {
      Fail 'No tracks detected in cdirip.exe output'
    }

    # Sorted by the numbers in the file name (numeric, not alphabetical),
    # so track 10 can never come before track 2.
    $extractedFiles = @(
      Get-ChildItem -LiteralPath $tmp -File |
        Where-Object { $_.Extension -in @('.bin', '.iso', '.wav', '.raw', '.cda', '.aiff') } |
        Sort-Object @{ Expression = { Get-NumericSortKey $_.BaseName } }, Name
    )

    if ($extractedFiles.Count -lt $tracks.Count) {
      Fail "Not enough extracted files: $($extractedFiles.Count) file(s) for $($tracks.Count) track(s)"
    }
    if ($extractedFiles.Count -gt $tracks.Count) {
      Log "WARNING: $($extractedFiles.Count) extracted files for $($tracks.Count) tracks; only the first $($tracks.Count) are used"
    }

    Log "Tracks detected: $($tracks.Count)"
    Log "Extracted files: $($extractedFiles.Count)"

    # Phase 1: move every track to a temporary staging name.
    # Phase 2: rename the staged files to their final trackNN name.
    # Two phases guarantee that a rename never overwrites another extracted file.
    $staged = [System.Collections.Generic.List[PSCustomObject]]::new()

    for ($i = 0; $i -lt $tracks.Count; $i++) {
      $track = $tracks[$i]
      $srcFile = $extractedFiles[$i]

      $size = Get-FileSize $srcFile.FullName
      if ($size -le 0) {
        Fail "Extracted file is empty: $($srcFile.FullName)"
      }

      if (-not (Test-ReadableFile $srcFile.FullName)) {
        Fail "Extracted file cannot be read: $($srcFile.FullName)"
      }

      Log ("TRACK {0}: {1}  {2:N0} bytes  LBA {3}" -f `
        $track.Num, $srcFile.Name, $size, $track.Lba)

      $ext = $srcFile.Extension.ToLowerInvariant()
      $stagePath = Join-Path $tmp ('_stage{0:D2}{1}' -f $track.Num, $ext)
      Move-Item -LiteralPath $srcFile.FullName -Destination $stagePath -Force

      $staged.Add([PSCustomObject]@{
        Num   = $track.Num
        Stage = $stagePath
        Ext   = $ext
      })
    }

    foreach ($item in $staged) {
      $standardPath = Join-Path $tmp ('track{0:D2}{1}' -f $item.Num, $item.Ext)
      Move-Item -LiteralPath $item.Stage -Destination $standardPath -Force
    }

    # An audio/data or data/data CDI may contain only two tracks.
    # If represented as GDI, chdman adds GD-ROM metadata and
    # Flycast then requires at least three tracks. A multi-track CUE lets
    # Flycast recognize this case as a MIL-CD and
    # rebuild the second session from the last data track.
    $cueLines = [System.Collections.Generic.List[string]]::new()
    $headerTrack = 0

    for ($i = 0; $i -lt $tracks.Count; $i++) {
      $track = $tracks[$i]
      $standardFiles = @(Get-ChildItem -LiteralPath $tmp -File -Filter ("track{0:D2}.*" -f $track.Num))
      if ($standardFiles.Count -ne 1) {
        Fail "CUE file missing or ambiguous for track $($track.Num)"
      }

      $trackFile = $standardFiles[0]
      $ext = $trackFile.Extension.ToLowerInvariant()

      $cueFileType = if ($ext -eq '.wav' -or $track.Type -match 'Audio') { 'WAVE' } else { 'BINARY' }
      $cueTrackType = if ($cueFileType -eq 'WAVE') { 'AUDIO' } else { 'MODE1/2048' }

      # Look for the Dreamcast boot header on the ISO data track(s).
      if ($cueFileType -eq 'BINARY' -and $ext -eq '.iso' -and $headerTrack -eq 0) {
        if (Test-DreamcastHeader $trackFile.FullName) {
          $headerTrack = $track.Num
        }
      }

      $cueLines.Add(('FILE "{0}" {1}' -f $trackFile.Name, $cueFileType))
      $cueLines.Add(('  TRACK {0:D2} {1}' -f $track.Num, $cueTrackType))
      $cueLines.Add('    INDEX 01 00:00:00')
    }

    if ($headerTrack -gt 0) {
      Log "Dreamcast header found on track $headerTrack"
    }
    elseif ($StrictHeader) {
      Fail 'No data track starts with the Dreamcast header (SEGA SEGAKATANA)'
    }
    else {
      Log 'WARNING: Dreamcast header not found on any ISO data track; test this game in Flycast'
    }

    $cuePath = Join-Path $tmp 'disc.cue'
    [IO.File]::WriteAllLines(
      $cuePath,
      $cueLines,
      (New-Object Text.UTF8Encoding($false))
    )

    Log "CUE created: $cuePath"
    Log "CONVERTING: $name"

    # chdman progress messages are written to stderr. Capture them without
    # triggering catch, then check the actual exit code.
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $chdOutput = @(& $chdman createcd '-i' $cuePath '-o' $dest 2>&1)
      $chdExit = $LASTEXITCODE
    }
    finally {
      $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($chdExit -ne 0) {
      Log-Diagnostics 'CHDMAN' $chdOutput
      Fail "chdman createcd failed with exit code $chdExit"
    }

    if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
      Fail 'chdman did not create the expected CHD file'
    }

    $destSize = Get-FileSize $dest
    if ($destSize -le 0) {
      Fail 'The created CHD file is empty'
    }

    Log "VERIFYING: $name"
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $verifyOutput = @(& $chdman verify '-i' $dest 2>&1)
      $verifyExit = $LASTEXITCODE
    }
    finally {
      $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($verifyExit -ne 0) {
      Log-Diagnostics 'VERIFY' $verifyOutput
      Fail "chdman verify failed with exit code $verifyExit"
    }

    $before += $f.Length
    $after += $destSize
    Log ("OK: {0}  {1:N0} MB -> {2:N0} MB" -f `
      $name, ($f.Length / 1MB), ($destSize / 1MB))
    $ok++
    $success = $true
  }
  catch {
    Log "FAILED: $name -> $($_.Exception.Message)"

    if (Test-Path -LiteralPath $dest -PathType Leaf) {
      Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    }

    if ($null -ne $tmp -and (Test-Path -LiteralPath $tmp)) {
      if ($DeleteTempOnError) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Log "Temporary folder deleted: $tmp"
      }
      else {
        Log "Temporary folder kept for diagnostics: $tmp"
      }
    }

    $fail++
  }
  finally {
    if ($success -and $null -ne $tmp -and (Test-Path -LiteralPath $tmp)) {
      Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

Log "Finished: $ok succeeded, $skip skipped, $fail failed"

if ($before -gt 0) {
  Log ("Space: {0:N2} GB -> {1:N2} GB (saved {2:N2} GB)" -f `
    ($before / 1GB), ($after / 1GB), (($before - $after) / 1GB))
}

Log 'Original CDI files were not modified. Test the CHD files before deleting anything.'

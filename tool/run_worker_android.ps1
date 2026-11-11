param([string]$Emulator = 'Pixel_3a')

$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if (-not (Test-Path -LiteralPath 'config/supabase.json')) {
        throw 'Copy config/supabase.example.json to config/supabase.json and add your project URL and publishable key.'
    }
    function Get-AndroidTarget {
        $devices = flutter devices --machine | ConvertFrom-Json
        $devices | Where-Object { $_.targetPlatform -like 'android*' } | Select-Object -First 1
    }

    $phone = Get-AndroidTarget
    if (-not $phone) {
        Write-Host "Starting Android phone emulator: $Emulator"
        flutter emulators --launch $Emulator
        if ($LASTEXITCODE -ne 0) { throw 'The Android emulator could not start.' }
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            Start-Sleep -Seconds 2
            $phone = Get-AndroidTarget
            if ($phone) { break }
        }
    }
    if (-not $phone) { throw 'No Android phone found. Start an emulator or connect a phone with USB debugging, then try again.' }
    Write-Host "Opening Uni360 Worker on $($phone.name)"
    flutter run -d $phone.id --dart-define-from-file=config/supabase.json
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}

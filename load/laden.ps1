# =====================================================================
# laden.ps1 - laadt de GTFS-bestanden in de staging-tabellen (SQL*Loader)
#
# Voorwaarden:
#   - sql\01_staging_tabellen.sql is uitgevoerd als MIVB
#   - de GTFS-bestanden staan in data\raw
#   - het commando sqlldr werkt in PowerShell
#
# Uitvoeren vanuit de projectmap:  .\load\laden.ps1
# =====================================================================

Set-Location (Join-Path $PSScriptRoot '..')
New-Item -ItemType Directory -Force 'load\logs' | Out-Null

$secure = Read-Host 'Wachtwoord voor user MIVB' -AsSecureString
$pw = [System.Net.NetworkCredential]::new('', $secure).Password

# Kleine bestanden eerst, stop_times (groot) als laatste
$bestanden = 'routes', 'stops', 'calendar', 'calendar_dates', 'trips', 'translations', 'stop_times'

foreach ($b in $bestanden) {
    Write-Host "== $b laden..." -ForegroundColor Cyan
    sqlldr userid="mivb/$pw@localhost:1521/XEPDB1" control="load\$b.ctl" `
           log="load\logs\$b.log" bad="load\logs\$b.bad" silent=header,feedback

    # Exitcodes van SQL*Loader: 0 = ok, 2 = sommige rijen geweigerd, 1/3 = fout
    switch ($LASTEXITCODE) {
        0       { Write-Host "   OK" -ForegroundColor Green }
        2       { Write-Host "   Rijen geweigerd: bekijk load\logs\$b.log en $b.bad" -ForegroundColor Yellow }
        default { Write-Host "   Fout (code $LASTEXITCODE): bekijk load\logs\$b.log" -ForegroundColor Red }
    }
}

Write-Host "`nKlaar. Voer nu tests\01_controle_staging.sql uit." -ForegroundColor Cyan

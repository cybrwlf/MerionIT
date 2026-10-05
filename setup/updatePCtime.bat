Rem Trigger the Windows Time Service to run automatically
sc triggerinfo w32time start/networkon stop/networkoff

REM Wait for internet connectivity before configuring NTP - w32tm /resync fails outright
REM without it. Loops indefinitely (30s checks) since nothing later in setup can succeed
REM without internet either - this is a real gate, not just a nice-to-have retry.
:CheckInternet
ping -n 1 google.com >nul 2>&1
if errorlevel 1 (
    timeout /t 30 /nobreak >nul
    ping -n 1 google.com >nul 2>&1
    if errorlevel 1 (
        msg * "This machine isn't connected to the internet yet. Connect it now - setup will continue automatically once it detects a connection."
        timeout /t 30 /nobreak >nul
        goto CheckInternet
    )
)

REM Update NTP Servers
w32tm /config /syncfromflags:manual /manualpeerlist:"0.us.pool.ntp.org 1.us.pool.ntp.org 2.us.pool.ntp.org 3.us.pool.ntp.org"

REM Set Timezone
tzutil /s "Eastern Standard Time"

REM Start Services
net start w32time

Rem Force Resync
w32tm /resync

Rem Trigger the Windows Time Service to run automatically
sc triggerinfo w32time start/networkon stop/networkoff

REM Update NTP Servers
w32tm /config /syncfromflags:manual /manualpeerlist:"0.us.pool.ntp.org 1.us.pool.ntp.org 2.us.pool.ntp.org 3.us.pool.ntp.org"

REM Set Timezone
tzutil /s "Eastern Standard Time"

REM Start Services
net start w32time

Rem Force Resync
w32tm /resync

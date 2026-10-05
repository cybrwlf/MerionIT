REM .NOTES
REM 	Author	: Original Script Author
REM 	Version : 1.0
REM 	Description:
REM 		This script configures various power management settings using the powercfg command.
REM 		It sets monitor and standby timeouts, and configures lid close action when on AC power.
REM 	Compatibility:
REM 		Fully compatible with both the latest Windows 10 and Windows 11 machines.
REM 		All commands and power settings are consistent across these operating systems.
REM 	Requires Administrator privileges to run.


echo --- Power Configuration Settings ---
echo Set monitor timeout for AC power to 30 minutes
Powercfg /Change monitor-timeout-ac 30
echo Set monitor timeout for DC power to 10 minutes
Powercfg /Change monitor-timeout-dc 10
echo Set standby timeout for AC power to 240 minutes (4 hours)
Powercfg /Change standby-timeout-ac 240
echo Set standby timeout for DC power to 30 minutes
Powercfg /Change standby-timeout-dc 30

echo Set the lid close action when on AC power to "Do Nothing" (0)
echo The GUIDs refer to specific power settings:
echo 4f971e89-eebd-4455-a8de-9e59040e7347 is for Display (SUB_DISPLAY)
echo 7648efa3-dd9c-4e3e-b566-50f929386280 is for the lid close action setting itself (LIDCLOSE)
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /SETACVALUEINDEX SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386280 3

echo Activate the current power scheme to ensure changes take effect
powercfg /SETACTIVE SCHEME_CURRENT

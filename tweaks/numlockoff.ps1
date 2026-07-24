Write-Host "Enabling NumLock after startup..."
            If (!(Test-Path "HKU:")) {
                New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
            }
            Set-ItemProperty -Path "HKU:\.DEFAULT\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Type DWord -Value 2

			
			Set-ItemProperty -Path "HKU:\.DEFAULT\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Type DWord -Value 2147483650
			Set-ItemProperty -Path "HKU:\.DEFAULT\Control Panel\Keyboard" -Name "KeyboardDelay" -Type DWord -Value 1
			Set-ItemProperty -Path "HKU:\.DEFAULT\Control Panel\Keyboard" -Name "KeyboardSpeed" -Type DWord -Value 31
$TestPath ='HKCU:\SOFTWARE\Policies\Microsoft\Windows'
$TestValue = 'TaskbarAl'

$KeyPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"  
$ValueName = "TaskbarAl"  
$ValueData = 0


try{  
    Get-ItemProperty -Path $KeyPath -Name $valueName -ErrorAction Stop  
	
}  
catch [System.Management.Automation.ItemNotFoundException] {  
    New-Item -Path $KeyPath -Force  
    New-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Type DWORD -Force  
}  
catch {  
    New-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Type DWORD -Force  
}  
Set-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Type DWORD -Force  

$ValueName = "TaskbarDa"
try{  
    Get-ItemProperty -Path $KeyPath -Name $valueName -ErrorAction Stop  
}  
catch [System.Management.Automation.ItemNotFoundException] {  
    New-Item -Path $KeyPath -Force  
    New-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Type DWORD -Force  
}  
catch {  
    New-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Type DWORD -Force  
}  
Set-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Type DWORD -Force  

$ValueName = "TaskbarMn"
try{  
    Get-ItemProperty -Path $KeyPath -Name $valueName -ErrorAction Stop  
}  
catch [System.Management.Automation.ItemNotFoundException] {  
    New-Item -Path $KeyPath -Force  
    New-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Type DWORD -Force  
}  
catch {  
    New-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Type DWORD -Force  
}  
Set-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Type DWORD -Force  

# Modify the registry value to show the search box
Set-Location -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
Set-ItemProperty -Path "." -Name "SearchboxTaskbarMode" -Value 2

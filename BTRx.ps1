New-Variable -Name ak -Value 'HKLM:\Software\Policies\Microsoft\Windows\AppPrivacy' -Option ReadOnly
New-Variable -Name an -Value 'LetAppsAccessRadios' -Option ReadOnly
New-Variable -Name newstate -Value 'Off'
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$asyTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and 
                                                                       $_.GetParameters().Count -eq 1 -and
                                                                       $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } )[0]
Function Await($WinRtTask) {
    $asyT = $asyTask.MakeGenericMethod([Windows.Devices.Radios.RadioAccessStatus])
    $nT = $asyT.Invoke($null, @($WinRtTask))
    $nT.Wait(-1) | Out-Null
}
Function GetRadios() {
    $asyT = $asyTask.MakeGenericMethod([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
    $nT = $asyT.Invoke($null, [Windows.Devices.Radios.Radio]::GetRadiosAsync())
    $nT.Wait(-1) | Out-Null
    $nT.Result
}

### bluetooth svc has to be running
If ((Get-Service bthserv).Status -ne 'Running') { Start-Service bthserv }

try {
  ### temporarily give apps access to radios
  New-ItemProperty -Path $ak -Name $an -PropertyType DWORD -Value 1 -Force | Out-Null

  ### dunno what these do; first is needed but second and third seemingly optional
  [Windows.Devices.Radios.Radio,               Windows.System.Devices,ContentType=WindowsRuntime] | Out-Null
  # [Windows.Devices.Radios.RadioAccessStatus, Windows.System.Devices,ContentType=WindowsRuntime] | Out-Null
  # [Windows.Devices.Radios.RadioState,        Windows.System.Devices,ContentType=WindowsRuntime] | Out-Null

  ### Essential to do whatever this does
  Await ([Windows.Devices.Radios.Radio]::RequestAccessAsync())

  ### identify the bluetooth radio [presumed to be only one] and ensure its on
  $btRadio = GetRadios | ? { $_.Kind -eq 'Bluetooth' }
  if ($btRadio.State -eq 'Off') { Await ($btRadio.SetStateAsync('On')) }
 
  ### Encourage fsquirt to use this folder (shortcut should 'start in' this folder)
  #Set-Location -Path "C:\Users\asdf\Downloads"

  ### Launch the Windows wizard directly in 'receive' mode
  # (Start-Process won't pass the argument, so we use the piping cludge to achieve synchronous operation)
  C:\Windows\System32\fsquirt.exe -receive | Out-Null
}
finally {
  ### Turn off the radio
  Await ($btRadio.SetStateAsync('Off'))

  ### block apps from accessing radios
  New-ItemProperty -Path $ak -Name $an -PropertyType DWORD -Value 0 -Force | Out-Null
}

param ([string]$cmdLine)

$Config = @{
	Title             = 'POS Services Manager'
	Version           = '0.2.0'
	ServerUrl         = 'https://github.com/mozers3/updater-test/raw/refs/heads/main'
}

# --- Блок компиляции ---
if ($cmdLine -eq "COMPILE") { 
	Invoke-PS2EXE -InputFile $PSCommandPath -x64 -noConsole -verbose -Title $Config.Title -Product $Config.Title -Version $Config.Version
	Set-Content -Path version -Value $Config.Version
	Exit 0
}

Add-Type -AssemblyName System.Windows.Forms

if ($PSCommandPath) {
	$currentPath = $PSCommandPath
	$scriptDir = $PSScriptRoot
} else {
	$currentPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
	$scriptDir = Split-Path $currentPath
}
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($currentPath)

function Get-UpdateError {
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
	$ProgressPreference = 'SilentlyContinue'

	$remoteVersion = $null
	try {
		$response = Invoke-WebRequest -Uri "$($Config.ServerUrl)/version" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
		$remoteVersion = $response.Content.Trim()
	} catch {
		return $null
	}

	if ([string]::IsNullOrEmpty($remoteVersion)) { return $null }
	if ($remoteVersion -eq $Config.Version) { return $null } # Обновление не требуется

	$msg = "Доступна новая версия приложения: $remoteVersion`n(Текущая версия: $($Config.Version))`n`nЗагрузить и установить обновление?"
	$result = [System.Windows.Forms.MessageBox]::Show($msg, "Доступно обновление", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)

	if ($result -ne 'Yes') { return $null } # Пользователь отказался

	$newExePath = Join-Path $scriptDir "${baseName}_new.exe"
	$downloadUrl = "$($Config.ServerUrl)/$baseName.exe"

	try {
		Invoke-WebRequest -Uri $downloadUrl -OutFile $newExePath -UseBasicParsing -ErrorAction Stop
	} catch {
		return "Ошибка загрузки файла:`n$($_.Exception.Message)"
	}

	if (!(Test-Path $newExePath)) { return "Файл не был сохранен на диск." }

	$updateLogic = @"
`$appDir = '$scriptDir'
`$baseName = '$baseName'
`$appExe = Join-Path `$appDir "`$baseName.exe"
`$newAppExe = Join-Path `$appDir "`${baseName}_new.exe"

`$timeout = 20
while ((Get-Process -Name `$baseName -ErrorAction SilentlyContinue) -and `$timeout -gt 0) {
	Start-Sleep -Milliseconds 500
	`$timeout--
}
Start-Sleep -Seconds 1

try {
	Remove-Item `$appExe -Force -ErrorAction Stop
	Rename-Item `$newAppExe "`$baseName.exe" -Force -ErrorAction Stop
	Start-Process `$appExe -WorkingDirectory `$appDir
} catch {
	Add-Type -AssemblyName System.Windows.Forms
	[System.Windows.Forms.MessageBox]::Show("Ошибка при установке обновления:`n`$_", "Ошибка", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}
exit
"@

	$bytes = [System.Text.Encoding]::Unicode.GetBytes($updateLogic)
	$encodedCommand = [Convert]::ToBase64String($bytes)
	$psArgs = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"

	Start-Process powershell.exe -ArgumentList $psArgs -WindowStyle Hidden
	exit 
}

# --- Проверка обновления и обработка ошибок ---
$updateError = Get-UpdateError
if ($updateError) {
	[System.Windows.Forms.MessageBox]::Show($updateError, "Ошибка обновления", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

# --- Основной код приложения ---
$frmMain = New-Object System.Windows.Forms.Form -Property @{
	Size = "500, 250"
	Text = "$($Config.Title) v$($Config.Version)"
}
[void]$frmMain.ShowDialog()
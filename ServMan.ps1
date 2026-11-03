param ([string]$cmdLine)

$Config = @{
	Title             = 'POS Services Manager'
	Version           = '0.1.0'
	ServerUrl         = 'https://github.com/mozers3/updater-test/raw/refs/heads/main'
}

# --- Блок компиляции ---
if ($cmdLine -eq "COMPILE") { 
	Invoke-PS2EXE -InputFile $PSCommandPath -x64 -noConsole -verbose -Title $Config.Title -Product $Config.Title -Version $Config.Version
	Set-Content -Path version -Value $Config.Version
	Exit 0
}

# --- Определение путей (работает и в PS, и в скомпилированном EXE) ---
$currentExePath = $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($currentExePath) -or $currentExePath -match '[<>|]') {
	$currentExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}
$scriptDir = Split-Path -Parent $currentExePath
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($currentExePath)

# --- Функция логирования ---
function Write-Log {
	param([string]$Message, [string]$Level = 'INFO')
	try {
		$logPath = Join-Path $scriptDir "update.log"
		$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
		"[$timestamp] [$Level] $Message" | Out-File -FilePath $logPath -Append -Encoding UTF8
	} catch {}
}

Write-Log "`n=== Запуск приложения версии $($Config.Version) ==="
Write-Log "currentExePath: $currentExePath"
Write-Log "scriptDir: $scriptDir"
Write-Log "baseName: $baseName"

# --- Включаем TLS 1.2/1.3 ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# --- 1. Проверка версии с таймаутом 3 секунды ---
$remoteVersion = $null
try {
	Write-Log "Запрос версии с сервера: $($Config.ServerUrl)/version"
	$response = Invoke-WebRequest -Uri "$($Config.ServerUrl)/version" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
	$remoteVersion = $response.Content.Trim()
	Write-Log "Получена версия с сервера: $remoteVersion"
} catch {
	Write-Log "Ошибка при запросе версии: $_" "ERROR"
	$remoteVersion = $null
}

# --- 2. Сравнение версий и запрос согласия ---
Write-Log "Сравнение версий: локальная=$($Config.Version), удалённая=$remoteVersion"
if ($remoteVersion -and $remoteVersion -ne $Config.Version) {
	Add-Type -AssemblyName System.Windows.Forms
	
	$msg = "Доступна новая версия приложения: $remoteVersion`n(Текущая версия: $($Config.Version))`n`nЗагрузить и установить обновление?"
	$result = [System.Windows.Forms.MessageBox]::Show($msg, "Доступно обновление", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
	Write-Log "Пользователь выбрал: $result"

	if ($result -eq 'Yes') {
		try {
			# --- 3. Загрузка нового файла ---
			$newExePath = Join-Path $scriptDir "${baseName}_new.exe"
			$downloadUrl = "$($Config.ServerUrl)/$baseName.exe"
			Write-Log "Загрузка обновления с: $downloadUrl"
			Write-Log "Сохранение в: $newExePath"
			Invoke-WebRequest -Uri $downloadUrl -OutFile $newExePath -UseBasicParsing -ErrorAction Stop
			
			if (Test-Path $newExePath) {
				$fileSize = (Get-Item $newExePath).Length
				Write-Log "Файл успешно загружен, размер: $fileSize байт"
			} else {
				Write-Log "Файл не создан после загрузки" "ERROR"
				throw "Файл не был загружен"
			}
			
			# --- 4. Проверка и запуск встроенного скрипта обновления ---
			$updateLogic = @"
# --- Функция логирования для дочернего процесса ---
function Write-UpdLog {
	param([string]`$Message, [string]`$Level = 'INFO')
	try {
		`$logPath = Join-Path '$scriptDir' '$baseName_update.log'
		`$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
		"[`$timestamp] [`$Level] [UPDATER] `$Message" | Out-File -FilePath `$logPath -Append -Encoding UTF8
	} catch {}
}

Write-UpdLog "=== Запуск скрипта обновления ==="
Write-UpdLog "appDir: '$scriptDir'"
Write-UpdLog "baseName: '$baseName'"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
`$appDir = '$scriptDir'
`$baseName = '$baseName'
`$appExe = Join-Path `$appDir "`$baseName.exe"
`$newAppExe = Join-Path `$appDir "`${baseName}_new.exe"

Write-UpdLog "appExe: `$appExe"
Write-UpdLog "newAppExe: `$newAppExe"

# Ждём завершения основного процесса (максимум 10 секунд)
Write-UpdLog "Ожидание завершения процесса `$baseName..."
`$timeout = 20
while ((Get-Process -Name `$baseName -ErrorAction SilentlyContinue) -and `$timeout -gt 0) {
	Start-Sleep -Milliseconds 500
	`$timeout--
}
Write-UpdLog "Ожидание завершено, осталось итераций: `$timeout"
Start-Sleep -Seconds 1 # Пауза для снятия файловых блокировок ОС

try {
	if (Test-Path `$appExe) { 
		Write-UpdLog "Удаление старого файла: `$appExe"
		Remove-Item `$appExe -Force -ErrorAction Stop 
		Write-UpdLog "Старый файл удалён"
	} else {
		Write-UpdLog "Старый файл не найден: `$appExe" "WARN"
	}
	
	if (Test-Path `$newAppExe) { 
		Write-UpdLog "Переименование `$newAppExe в `$baseName.exe"
		Rename-Item `$newAppExe "`$baseName.exe" -Force -ErrorAction Stop 
		Write-UpdLog "Файл успешно переименован"
	} else {
		Write-UpdLog "Новый файл не найден: `$newAppExe" "ERROR"
		throw "Новый файл не найден"
	}
	
	# Запускаем обновлённое приложение
	Write-UpdLog "Запуск обновлённого приложения: `$appExe"
	Start-Process `$appExe -WorkingDirectory `$appDir
	Write-UpdLog "Приложение запущено успешно"
} catch {
	Write-UpdLog "Ошибка при установке обновления: `$_" "ERROR"
	Add-Type -AssemblyName System.Windows.Forms
	[System.Windows.Forms.MessageBox]::Show("Ошибка при установке обновления:`n`$_", "Ошибка", "OK", "Error")
}
Write-UpdLog "=== Скрипт обновления завершён ==="
exit
"@

			Write-Log "Скрипт обновления сформирован"
			
			# Кодируем в Base64 (PowerShell требует UTF-16LE для -EncodedCommand)
			$bytes = [System.Text.Encoding]::Unicode.GetBytes($updateLogic)
			$encodedCommand = [Convert]::ToBase64String($bytes)
			Write-Log "Скрипт закодирован в Base64, длина: $($encodedCommand.Length) символов"

			# Запускаем скрытый PowerShell с нашим скриптом
			$psArgs = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
			Write-Log "Запуск PowerShell с аргументами: $psArgs"
			Start-Process powershell.exe -ArgumentList $psArgs -WindowStyle Hidden
			
			Write-Log "Завершение текущего приложения"
			# Завершаем текущее приложение
			exit
		} catch {
			Write-Log "Ошибка при загрузке обновления: $_" "ERROR"
			Add-Type -AssemblyName System.Windows.Forms
			[System.Windows.Forms.MessageBox]::Show("Не удалось загрузить обновление. Проверьте подключение к интернету.`n`n$_", "Ошибка обновления", "OK", "Error")
		}
	}
} else {
	Write-Log "Обновление не требуется или версия не определена"
}

Write-Log "=== Запуск основного интерфейса ==="

# --- Основной код приложения ---
Add-Type -AssemblyName System.Windows.Forms
$frmMain = New-Object System.Windows.Forms.Form -Property @{
	Size = "500, 250"
	Text = "$($Config.Title) v$($Config.Version)"
}
[void]$frmMain.ShowDialog()

Write-Log "=== Приложение закрыто ==="
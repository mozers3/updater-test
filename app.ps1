param ([string]$cmdLine)
$Config = @{
	Title             = 'POS Services Manager'
	Version           = '1.3.1'
}

if ($cmdLine -eq "COMPILE") { 
	if (!(Get-Module -ListAvailable -Name ps2exe)) {
		try {
			Install-Module -Name ps2exe -Scope CurrentUser -Force -ErrorAction SilentlyContinue
		} catch {
			Write-Warning $_
			return
		}
	}
	$iconPath = "$PSScriptRoot\ServMan.ico"
	Invoke-PS2EXE -InputFile $PSCommandPath -x64 -noConsole -verbose -IconFile $iconPath -Title $Config.Title -Product $Config.Title -Copyright 'https://github.com/mozers3' -Company 'mozers™' -Version $Config.Version
	Exit 0
}

# Принудительно включаем поддержку современных протоколов шифрования (TLS 1.2/1.3)
# Это критически важно для корректной работы с HTTPS на некоторых версиях Windows/PowerShell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# --- Настройки ---
$serverUrl = "https://github.com/mozers3/updater-test/raw/refs/heads/main"
$appName = "app"
$updateScriptName = "update.ps1"

# Определяем директорию, где находится запущенный exe-файл
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($scriptDir)) {
    $scriptDir = [Environment]::CurrentDirectory
}

# --- 1. Проверка версии с таймаутом 3 секунды ---
$remoteVersion = $null
try {
    $response = Invoke-WebRequest -Uri "$serverUrl/version" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
    $remoteVersion = $response.Content.Trim()
} catch {
    # Если таймаут, ошибка сети или файл не найден - молча продолжаем работу старой версии
    $remoteVersion = $null
}

# --- 2. Сравнение версий и запрос согласия ---
if ($remoteVersion -and $remoteVersion -ne $Config.Version) {
    # Подключаем сборки для отображения красивого GUI-окна (даже если консоль скрыта)
    Add-Type -AssemblyName System.Windows.Forms
    
    $msg = "Доступна новая версия приложения: $remoteVersion`n(Текущая версия: $($Config.Version))`n`nЗагрузить и установить обновление?"
    $result = [System.Windows.Forms.MessageBox]::Show($msg, "Доступно обновление", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)

    if ($result -eq 'Yes') {
        try {
            # --- 3. Загрузка нового файла ---
            $newExePath = Join-Path $scriptDir "app_new.exe"
            Invoke-WebRequest -Uri "$serverUrl/$appName.exe" -OutFile $newExePath -UseBasicParsing -ErrorAction Stop
            
            # --- 4. Проверка успешности загрузки и запуск обновителя ---
            if (Test-Path $newExePath) {
                $updateScriptPath = Join-Path $scriptDir $updateScriptName
                
                # Запускаем update.ps1 в скрытом окне с обходом политики выполнения
                Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$updateScriptPath`"" -WindowStyle Hidden
                
                # Завершаем работу текущего приложения
                exit
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Не удалось загрузить обновление. Проверьте подключение к интернету.", "Ошибка обновления", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
}

# --- Основной код вашего приложения ---
[System.Windows.Forms.MessageBox]::Show("Приложение запущено (версия $Config.Version)", "Статус")
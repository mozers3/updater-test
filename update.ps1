# Принудительно включаем TLS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$appName = "app"
$appExe = Join-Path $scriptDir "app.exe"
$newAppExe = Join-Path $scriptDir "app_new.exe"

# --- 1. Ожидание завершения основного процесса app.exe ---
# Даем основному приложению время на корректное завершение (максимум 10 секунд)
$timeout = 20 # 20 итераций по 0.5 сек = 10 секунд
while ((Get-Process -Name $appName -ErrorAction SilentlyContinue) -and $timeout -gt 0) {
    Start-Sleep -Milliseconds 500
    $timeout--
}

# Дополнительная небольшая пауза для снятия файловых блокировок ОС
Start-Sleep -Seconds 1

# --- 2. Замена файлов ---
try {
    # Удаляем старый файл, если он вдруг еще существует
    if (Test-Path $appExe) {
        Remove-Item $appExe -Force -ErrorAction Stop
    }

    # Переименовываем новый файл
    if (Test-Path $newAppExe) {
        Rename-Item $newAppExe "app.exe" -Force -ErrorAction Stop
    }

    # --- 3. Запуск обновленного приложения ---
    Start-Process $appExe -WorkingDirectory $scriptDir

} catch {
    # Если что-то пошло не так (например, нет прав администратора), можно вывести ошибку
    # Add-Type -AssemblyName System.Windows.Forms
    # [System.Windows.Forms.MessageBox]::Show("Ошибка при установке обновления: $_", "Ошибка", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

# --- 4. Завершение работы скрипта обновителя ---
exit
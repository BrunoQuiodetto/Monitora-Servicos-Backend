param (
    [string]$SMTPServer,
    [int]$SMTPPort,
    [string]$EmailSender,
    [string]$EmailPassword,
    [string[]]$EmailRecipients,

    [string]$ProcessName = "httpd",
    [int]$ThresholdStep = 500 # 500MB
)

# Preenche parametros caso não forem passados (senha só é preenchida se for o mesmo usuario que criptografou)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configPath = Join-Path -Path $ScriptDir -ChildPath "..\conf\config.psd1"
$configText = Get-Content $configPath | Out-String
$config = Invoke-Expression $configText

if (-not $SMTPServer) { $SMTPServer = $config.SMTPServer }
if (-not $SMTPPort) { $SMTPPort = $config.SMTPPort }
if (-not $EmailSender) { $EmailSender = $config.EmailSender }
if (-not $EmailRecipients) { $EmailRecipients = $config.EmailRecipients }
if ($config.EmailAlias) { $EmailAlias = $config.EmailAlias } else { $EmailAlias = $EmailSender }
if ($config.EmailAliasName) { $EmailAliasName = $config.EmailAliasName } else { $EmailAliasName = '' }
if (-not $LogFile) { $LogFile = Join-Path -Path $ScriptDir -ChildPath $config.LogFile }
if (-not $EmailPassword) { 
    $EmailPassword = Get-Content (Join-Path -Path $ScriptDir -ChildPath $config.SenhaPath) 
}
   
# Enviar e-mail informando que o monitoramento foi iniciado
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$StartupMessage = "$Timestamp - O serviço de monitoramento do processo $ProcessName foi iniciado."
$NextNotificationLevel = 0
$LastNotifiedLevel = 0

Add-Content -Path $LogFile -Value $StartupMessage

$SubjectStartup = "IT MONITORA | $ProcessName"

$SMTPClient = New-Object System.Net.Mail.SmtpClient($SMTPServer, $SMTPPort)
$SMTPClient.EnableSsl = $false

$SMTPClient.Credentials = New-Object System.Net.NetworkCredential($EmailSender, $EmailPassword)

$MailMessage = New-Object System.Net.Mail.MailMessage
$MailMessage.IsBodyHtml = $true  # Ativar HTML no e-mail
$MailMessage.From = New-Object System.Net.Mail.MailAddress($EmailAlias, $EmailAliasName)
foreach ($recipient in $EmailRecipients) {
    $MailMessage.To.Add($recipient)
}
$MailMessage.Subject = $SubjectStartup

$ImagePath = Join-Path -Path $ScriptDir -ChildPath "..\src\ITSYSTEM_p.png"

$TemplatePath_start = Join-Path -Path $ScriptDir -ChildPath "..\templates\emailMonitor_start.html"

$Subject = "MONITORAMENTO INICIADO: $ProcessName"

$Body = [System.IO.File]::ReadAllText($TemplatePath_start)
$Body = $Body -replace "{{PROCESS_NAME}}", $ProcessName
$Body = $Body -replace "{{TIMESTAMP}}", (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

# Criar visualização alternativa para suportar imagens embutidas
$AlternateView = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($Body, [System.Text.Encoding]::UTF8, "text/html")

# Criar recurso vinculado (LinkedResource) para embutir a imagem
$LinkedResource = New-Object System.Net.Mail.LinkedResource($ImagePath, "image/png")
$LinkedResource.ContentId = "logoimg"  # O mesmo CID usado no HTML
$AlternateView.LinkedResources.Add($LinkedResource)
$MailMessage.AlternateViews.Add($AlternateView)

$MailMessage.Subject = $Subject
$MailMessage.Body = $Body

try {
    $SMTPClient.Send($MailMessage)
    Add-Content -Path $LogFile -Value "$Timestamp - Notificação de início enviada para $EmailRecipients."
}
catch {
    Add-Content -Path $LogFile -Value "$Timestamp - Erro ao enviar e-mail de início: $_"
}

# Loop de monitoramento
while ($true) {
    $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    $Now = Get-Date

    if ($processes) {
        $TotalMemoryMB = ($processes | Measure-Object WorkingSet64 -Sum).Sum / 1MB
        $TotalMemoryMB = [math]::Round($TotalMemoryMB, 2)

        # Verifica se ultrapassou o próximo nível de notificação
        if ($NextNotificationLevel -eq 0) {
            # Inicia definição de limites
            $NextNotificationLevel = ($TotalMemoryMB + $ThresholdStep)
            $NextNotificationLevel = [math]::Round($NextNotificationLevel, 2)
            $LastNotificationTime = Get-Date
            $NotificationReason = "upper"
            $first = $true
        }
        elseif ($TotalMemoryMB -lt $NextNotificationLevel) {
            if (-not $LastNotificationTime) { $LastNotificationTime = Get-Date }
            $elapsed = (Get-Date) - $LastNotificationTime
            if ($elapsed.TotalHours -ge 1) {
                $NextNotificationLevel = [math]::Round($TotalMemoryMB, 2)
                $LastNotificationTime = Get-Date
                $NotificationReason = "lower"
                Add-Content -Path $LogFile -Value "$Timestamp - NextNotificationLevel ajustado para $NextNotificationLevel MB após 1 hora sem ultrapassar."
            }
        }
        else {
            $LastNotificationTime = Get-Date
            $NotificationReason = "upper"
        }

        # Obter a memória total disponível no sistema já livre para uso (não é o valor do pente de memória)
        $TotalSystemMemoryMB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1MB, 2)

        # Obtém a memória disponível no sistema (em MB)
        $AvailableMemoryMB = [math]::Round((Get-WmiObject Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes, 2)

        # Calcula o total de memória utilizada por todos os processos (em MB)
        $TotalUsedMemoryMB = $TotalSystemMemoryMB - $AvailableMemoryMB

        # Calcula o total de memória utilizada por outros aplicativos (em MB)
        $TotalUsedMemoryOtherAppsMB = $TotalUsedMemoryMB - $TotalMemoryMB

        # Calcula o total de memória disponível para o serviço (em MB)
        $TotalAvailableForAppMB = $TotalSystemMemoryMB - $TotalUsedMemoryOtherAppsMB

        # Calcular a porcentagem de memória usada
        $MemoryPercentage = [math]::Round(($TotalMemoryMB / $TotalAvailableForAppMB) * 100, 2)

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogFile -Value "$Timestamp - $ProcessName consumindo $TotalMemoryMB MB. NextNotificationLevel: $NextNotificationLevel. LastNotifiedLevel: $LastNotifiedLevel. NotificationReason: $NotificationReason"

        # Inserir dados de memória no banco Z111 (sempre que calcular TotalMemoryMB)
        try {
            $InsertMemoryScript = Join-Path -Path $ScriptDir -ChildPath "insertMemoryData.ps1"
            & $InsertMemoryScript -ProcessName $ProcessName -MemoryUsageMB $TotalMemoryMB -MemoryAvailableMB $TotalAvailableForAppMB -MemoryPercentage $MemoryPercentage -Reason $NotificationReason
        }
        catch {
            Add-Content -Path $LogFile -Value "$Timestamp - Erro ao inserir dados no banco Z111: $_"
        }

        if ($TotalMemoryMB -ge $NextNotificationLevel -and $NextNotificationLevel -ne $LastNotifiedLevel) {
            if ($first) { $first = $false; $NotificationReason = "upper" }

            $LastNotifiedLevel = $NextNotificationLevel
            $NextNotificationLevel = ($TotalMemoryMB + $ThresholdStep)

            $MailMessage = New-Object System.Net.Mail.MailMessage
            $MailMessage.IsBodyHtml = $true  # Ativar HTML no e-mail
            $MailMessage.From = New-Object System.Net.Mail.MailAddress($EmailAlias, $EmailAliasName)
            foreach ($recipient in $EmailRecipients) {
                $MailMessage.To.Add($recipient)
            }

            # Criar mensagem de log
            $LogMessage = "$Timestamp - ALERTA: $ProcessName consumindo $TotalMemoryMB MB ($MemoryPercentage% de $TotalAvailableForAppMB MB disponíveis no sistema)."
            
            # Escrever no log
            Add-Content -Path $LogFile -Value $LogMessage

            # Enviar e-mail de alerta
            $Subject = "$ProcessName ultrapassou a barreira de $LastNotifiedLevel MB"

            $TemplatePath_alert = Join-Path -Path $ScriptDir -ChildPath "..\templates\emailMonitor_alerts.html"

            $Body = [System.IO.File]::ReadAllText($TemplatePath_alert)
            $Body = $Body -replace "{{PROCESS_NAME}}", $ProcessName
            $Body = $Body -replace "{{TOTAL_MEMORY}}", $TotalMemoryMB
            $Body = $Body -replace "{{MEMORY_PERCENTAGE}}", $MemoryPercentage
            $Body = $Body -replace "{{TOTAL_SYSTEM_MEMORY}}", $TotalAvailableForAppMB
            $Body = $Body -replace "{{TIMESTAMP}}", $Timestamp
            $Body = $Body -replace "{{NEXTLIMIT}}", $NextNotificationLevel
            $Body = $Body -replace "{{NOTIFICATIONREASON}}", $NotificationReason
            
            # Criar visualização alternativa para suportar imagens embutidas
            $AlternateView = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($Body, [System.Text.Encoding]::UTF8, "text/html")

            # Criar recurso vinculado (LinkedResource) para embutir a imagem
            $LinkedResource = New-Object System.Net.Mail.LinkedResource($ImagePath, "image/png")
            $LinkedResource.ContentId = "logoimg"  # O mesmo CID usado no HTML
            $AlternateView.LinkedResources.Add($LinkedResource)
            $MailMessage.AlternateViews.Add($AlternateView)

            $MailMessage.Subject = $Subject
            $MailMessage.Body = $Body

            try {
                $SMTPClient.Send($MailMessage)
                Add-Content -Path $LogFile -Value "$Timestamp - Notificação enviada para $EmailRecipients."
            }
            catch {
                Add-Content -Path $LogFile -Value "$Timestamp - Erro ao enviar e-mail: $_"
            }
        }

        if ($Now.DayOfWeek -eq "Sunday" -and $Now.Hour -eq 3 -and $Now.Minute -lt 30) {

            $nextRestart = $Now.AddHours(24).ToString("yyyy-MM-dd HH:mm:ss")

            # Obter a memória total disponível no sistema já livre para uso (não é o valor do pente de memória)
            $TotalSystemMemoryMB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1MB, 2)

            # Obtém a memória disponível no sistema (em MB)
            $AvailableMemoryMB = [math]::Round((Get-WmiObject Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes, 2)

            # Calcula o total de memória utilizada por todos os processos (em MB)
            $TotalUsedMemoryMB = $TotalSystemMemoryMB - $AvailableMemoryMB

            # Calcula o total de memória utilizada por outros aplicativos (em MB)
            $TotalUsedMemoryOtherAppsMB = $TotalUsedMemoryMB - $TotalMemoryMB

            # Calcula o total de memória disponível para o serviço (em MB)
            $TotalAvailableForAppMB = $TotalSystemMemoryMB - $TotalUsedMemoryOtherAppsMB
         
            $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            $MemoryBeforeRestart = $TotalMemoryMB

            # Inserir dados de memória no banco Z111 (sempre que calcular TotalMemoryMB)
            try {
                $ReiniciaScriptPath = Join-Path -Path $ScriptDir -ChildPath "reiniciaApache.ps1"
                Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$ReiniciaScriptPath`" -TipoReinicio 'Programado' -NomeUsuario 'Automatico' -Motivo 'Reinicio padrao'" -WindowStyle Hidden

                # Obter novo consumo de memória
                Start-Sleep -Seconds 30

                $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
                $MemoryAfterRestart = if ($processes) { ($processes | Measure-Object WorkingSet64 -Sum).Sum / 1MB } else { 0 }
                $MemoryAfterRestart = [math]::Round($MemoryAfterRestart, 2)

                $TotalMemoryMB = $MemoryAfterRestart
                $NextNotificationLevel = ($TotalMemoryMB + $ThresholdStep)

                $MailMessage = New-Object System.Net.Mail.MailMessage
                $MailMessage.IsBodyHtml = $true  # Ativar HTML no e-mail

                $MailMessage.From = New-Object System.Net.Mail.MailAddress($EmailAlias, $EmailAliasName)

                foreach ($recipient in $EmailRecipients) {
                    $MailMessage.To.Add($recipient)
                }

                $TemplatePath_alert = Join-Path -Path $ScriptDir -ChildPath "..\templates\emailMonitor_restart.html"

                $Body = [System.IO.File]::ReadAllText($TemplatePath_alert)
                $Body = $Body -replace "{{MEMORY_BEFORE}}", $MemoryBeforeRestart
                $Body = $Body -replace "{{MEMORY_PERCENTAGE_BEFORE}}", [math]::Round(($MemoryBeforeRestart / $TotalAvailableForAppMB) * 100, 2)
                $Body = $Body -replace "{{MEMORY_AFTER}}", $MemoryAfterRestart
                $Body = $Body -replace "{{MEMORY_PERCENTAGE_AFTER}}", [math]::Round(($MemoryAfterRestart / $TotalAvailableForAppMB) * 100, 2)
                $Body = $Body -replace "{{TOTAL_SYSTEM_MEMORY}}", $TotalAvailableForAppMB
                $Body = $Body -replace "{{TIMESTAMP}}", $Timestamp
                $Body = $Body -replace "{{NEXTRESTART}}", $nextRestart

                # Criar visualização alternativa para suportar imagens embutidas
                $AlternateView = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($Body, [System.Text.Encoding]::UTF8, "text/html")

                # Criar recurso vinculado (LinkedResource) para embutir a imagem
                $LinkedResource = New-Object System.Net.Mail.LinkedResource($ImagePath, "image/png")
                $LinkedResource.ContentId = "logoimg"  # O mesmo CID usado no HTML
                $AlternateView.LinkedResources.Add($LinkedResource)
                $MailMessage.AlternateViews.Add($AlternateView)

                $MailMessage.Subject = "Reinicialização Programada: $ProcessName"
                $MailMessage.Body = $Body

                # Registrar no log
                Add-Content -Path $LogFile -Value "$Timestamp - REINÍCIO AUTOMÁTICO: $ProcessName reiniciado. Memória antes: $MemoryBeforeRestart MB, depois: $MemoryAfterRestart MB."

                try {
                    $SMTPClient.Send($MailMessage)
                    Add-Content -Path $LogFile -Value "$Timestamp - Notificação de reinício enviada para: $($EmailRecipients -join ', ')."
                }
                catch {
                    Add-Content -Path $LogFile -Value "$Timestamp - Erro ao enviar e-mail de reinício: $_"
                }
            }
            catch {
                Add-Content -Path $LogFile -Value "$Timestamp - Erro ao rodar o script de reinicialização: $_"
            }
            
            
        }
    }

    Start-Sleep -Seconds 600 # Verifica a cada 10 minutos
}
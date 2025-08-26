param (
    [string]$SMTPServer,
    [int]$SMTPPort,
    [string]$EmailSender,
    [string]$EmailPassword,
    [string[]]$EmailRecipients,

    [string[]]$ProcessNames = @(),  # Se vazio, usa do config
    [int]$ThresholdStep = 500 # 500MB
)

# Preenche parametros caso não forem passados
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configPath = Join-Path -Path $ScriptDir -ChildPath "..\conf\config.psd1"
$configText = Get-Content $configPath | Out-String
$config = Invoke-Expression $configText

# Configurações de e-mail
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

# Define processos a monitorar: parâmetro tem prioridade sobre config
if ($ProcessNames.Count -eq 0) {
    $ProcessNames = $config.ProcessesToMonitor
}

# Hash table para controlar thresholds de cada processo
$ProcessThresholds = @{}
$ProcessLastNotificationTime = @{}

# Controle para reinicialização automática aos domingos às 3h
$LastSundayRestart = [datetime]::MinValue
if ($config.LastSundayRestart) {
    try {
        $LastSundayRestart = [datetime]::Parse($config.LastSundayRestart)
    } catch {
        $LastSundayRestart = [datetime]::MinValue
    }
}

# Inicializar controles para cada processo
foreach ($ProcessName in $ProcessNames) {
    $ProcessThresholds[$ProcessName] = @{
        NextNotificationLevel = 0
        LastNotifiedLevel = 0
        NotificationReason = "upper"
        FirstRun = $true
    }
    $ProcessLastNotificationTime[$ProcessName] = Get-Date
}

# Enviar e-mail informando que o monitoramento foi iniciado
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$ProcessList = $ProcessNames -join ", "
$StartupMessage = "$Timestamp - O serviço de monitoramento dos processos [$ProcessList] foi iniciado."

Add-Content -Path $LogFile -Value $StartupMessage

# Configurar cliente SMTP
$SMTPClient = New-Object System.Net.Mail.SmtpClient($SMTPServer, $SMTPPort)
$SMTPClient.EnableSsl = $false
$SMTPClient.Credentials = New-Object System.Net.NetworkCredential($EmailSender, $EmailPassword)

# Enviar notificação de início
$SubjectStartup = "IT MONITORA | Multiplos Servicos"
$ImagePath = Join-Path -Path $ScriptDir -ChildPath "..\src\ITSYSTEM_p.png"
$TemplatePath_start = Join-Path -Path $ScriptDir -ChildPath "..\templates\emailMonitor_start.html"

$MailMessage = New-Object System.Net.Mail.MailMessage
$MailMessage.IsBodyHtml = $true
$MailMessage.From = New-Object System.Net.Mail.MailAddress($EmailAlias, $EmailAliasName)
foreach ($recipient in $EmailRecipients) {
    $MailMessage.To.Add($recipient)
}

$Body = [System.IO.File]::ReadAllText($TemplatePath_start)
$Body = $Body -replace "{{PROCESS_NAME}}", $ProcessList
$Body = $Body -replace "{{TIMESTAMP}}", (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

$AlternateView = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($Body, [System.Text.Encoding]::UTF8, "text/html")
$LinkedResource = New-Object System.Net.Mail.LinkedResource($ImagePath, "image/png")
$LinkedResource.ContentId = "logoimg"
$AlternateView.LinkedResources.Add($LinkedResource)
$MailMessage.AlternateViews.Add($AlternateView)
$MailMessage.Subject = $SubjectStartup
$MailMessage.SubjectEncoding = [System.Text.Encoding]::UTF8

try {
    $SMTPClient.Send($MailMessage)
    Add-Content -Path $LogFile -Value "$Timestamp - Notificação de início enviada para $EmailRecipients."
}
catch {
    Add-Content -Path $LogFile -Value "$Timestamp - Erro ao enviar e-mail de início: $_"
}

# Loop principal de monitoramento
while ($true) {
    # Verificar se é domingo às 3h para reinicialização automática
    $Now = Get-Date
    if ($Now.DayOfWeek -eq "Sunday" -and $Now.Hour -eq 3 -and $Now.Minute -lt 10) {
        $Today = $Now.Date
        if ($LastSundayRestart -lt $Today) {
            $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Add-Content -Path $LogFile -Value "$Timestamp - Iniciando reinicialização automática programada (Domingo 3h)"
            
            foreach ($ProcessName in $ProcessNames) {
                try {
                    $RestartScript = Join-Path -Path $ScriptDir -ChildPath "reiniciaServico.ps1"
                    if (Test-Path $RestartScript) {
                        & $RestartScript -ProcessName $ProcessName -NomeUsuario "Sistema" -Motivo "Reinicialização automática programada (Domingo 3h)" -TipoReinicio "Programado"
                        Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Reinicialização automática executada"
                    }
                } catch {
                    Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Erro na reinicialização automática: $_"
                }
            }
            
            $LastSundayRestart = $Today
            # Atualizar config com data da última reinicialização (opcional)
        }
    }

    foreach ($ProcessName in $ProcessNames) {
        $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        if ($processes) {
            # Calcula memória total do processo
            $TotalMemoryMB = ($processes | Measure-Object WorkingSet64 -Sum).Sum / 1MB
            $TotalMemoryMB = [math]::Round($TotalMemoryMB, 2)
            
            # Obtém dados do sistema
            $TotalSystemMemoryMB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1MB, 2)
            $AvailableMemoryMB = [math]::Round((Get-WmiObject Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes, 2)
            $TotalUsedMemoryMB = $TotalSystemMemoryMB - $AvailableMemoryMB
            $TotalUsedMemoryOtherAppsMB = $TotalUsedMemoryMB - $TotalMemoryMB
            $TotalAvailableForAppMB = $TotalSystemMemoryMB - $TotalUsedMemoryOtherAppsMB
            $MemoryPercentage = [math]::Round(($TotalMemoryMB / $TotalAvailableForAppMB) * 100, 2)
            
            # Controle de thresholds por processo
            $processControl = $ProcessThresholds[$ProcessName]
            
            if ($processControl.FirstRun) {
                $processControl.NextNotificationLevel = ($TotalMemoryMB + $ThresholdStep)
                $processControl.NextNotificationLevel = [math]::Round($processControl.NextNotificationLevel, 2)
                $ProcessLastNotificationTime[$ProcessName] = Get-Date
                $processControl.NotificationReason = "upper"
                $processControl.FirstRun = $false
            }
            elseif ($TotalMemoryMB -lt $processControl.NextNotificationLevel) {
                $elapsed = (Get-Date) - $ProcessLastNotificationTime[$ProcessName]
                if ($elapsed.TotalHours -ge 1) {
                    $processControl.NextNotificationLevel = [math]::Round($TotalMemoryMB, 2)
                    $ProcessLastNotificationTime[$ProcessName] = Get-Date
                    $processControl.NotificationReason = "lower"
                    Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] NextNotificationLevel ajustado para $($processControl.NextNotificationLevel) MB após 1 hora sem ultrapassar."
                }
            }
            else {
                $ProcessLastNotificationTime[$ProcessName] = Get-Date
                $processControl.NotificationReason = "upper"
            }
            
            # Log do status atual
            Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] consumindo $TotalMemoryMB MB. NextNotificationLevel: $($processControl.NextNotificationLevel). LastNotifiedLevel: $($processControl.LastNotifiedLevel). NotificationReason: $($processControl.NotificationReason). SistemaTotal: $TotalSystemMemoryMB MB. SistemaDisponivel: $AvailableMemoryMB MB. SistemaUsado: $TotalUsedMemoryMB MB"
            
            # Inserir dados de memória no banco
            try {
                $InsertMemoryScript = Join-Path -Path $ScriptDir -ChildPath "insertMemoryData.ps1"
                & $InsertMemoryScript -ProcessName $ProcessName -MemoryUsageMB $TotalMemoryMB -MemoryAvailableMB $TotalAvailableForAppMB -MemoryPercentage $MemoryPercentage -Reason $processControl.NotificationReason
            }
            catch {
                Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Erro ao inserir dados no banco: $_"
            }
            
            # Verificar se precisa enviar notificação
            if ($TotalMemoryMB -ge $processControl.NextNotificationLevel -and $processControl.NextNotificationLevel -ne $processControl.LastNotifiedLevel) {
                $processControl.LastNotifiedLevel = $processControl.NextNotificationLevel
                $processControl.NextNotificationLevel = ($TotalMemoryMB + $ThresholdStep)
                
                # Enviar e-mail de alerta
                try {
                    $MailMessage = New-Object System.Net.Mail.MailMessage
                    $MailMessage.IsBodyHtml = $true
                    $MailMessage.From = New-Object System.Net.Mail.MailAddress($EmailAlias, $EmailAliasName)
                    foreach ($recipient in $EmailRecipients) {
                        $MailMessage.To.Add($recipient)
                    }
                    
                    $Subject = "ALERTA: $ProcessName - Consumo de Memória Elevado"
                    $TemplatePath_alert = Join-Path -Path $ScriptDir -ChildPath "..\templates\emailMonitor_alerts.html"
                    
                    $Body = [System.IO.File]::ReadAllText($TemplatePath_alert)
                    $Body = $Body -replace "{{PROCESS_NAME}}", $ProcessName
                    $Body = $Body -replace "{{TOTAL_MEMORY}}", $TotalMemoryMB
                    $Body = $Body -replace "{{MEMORY_PERCENTAGE}}", $MemoryPercentage
                    $Body = $Body -replace "{{TOTAL_SYSTEM_MEMORY}}", $TotalAvailableForAppMB
                    $Body = $Body -replace "{{THRESHOLD_MB}}", $processControl.LastNotifiedLevel
                    $Body = $Body -replace "{{TIMESTAMP}}", $Timestamp
                    $Body = $Body -replace "{{NEXTLIMIT}}", $processControl.NextNotificationLevel
                    $Body = $Body -replace "{{NOTIFICATIONREASON}}", $processControl.NotificationReason

                    $AlternateView = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($Body, [System.Text.Encoding]::UTF8, "text/html")
                    $LinkedResource = New-Object System.Net.Mail.LinkedResource($ImagePath, "image/png")
                    $LinkedResource.ContentId = "logoimg"
                    $AlternateView.LinkedResources.Add($LinkedResource)
                    $MailMessage.AlternateViews.Add($AlternateView)
                    $MailMessage.Subject = $Subject
                    $MailMessage.SubjectEncoding = [System.Text.Encoding]::UTF8
                    
                    $SMTPClient.Send($MailMessage)
                    Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Alerta de memória enviado. Consumo: $TotalMemoryMB MB"
                    
                    # Limpar recursos
                    $MailMessage.Dispose()
                }
                catch {
                    Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Erro ao enviar alerta: $_"
                }
            }
        }
        else {
            Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Processo não encontrado em execução."
        }
    }
    
    # Pausa antes da próxima verificação (10 minutos)
    Start-Sleep -Seconds 600
}

# Sistema de Monitoramento de Memória de Processos
# Arquivo: verificaMemoria.ps1
# Script principal do sistema de monitoramento contínuo

<#
.SYNOPSIS
    Sistema completo de monitoramento de memória de processos com alertas automáticos

.DESCRIPTION
    Script principal que monitora continuamente o consumo de memória de processos específicos,
    enviando alertas por email quando thresholds são ultrapassados ou em intervalos regulares.
    Inclui funcionalidades de:
    - Monitoramento contínuo de memória
    - Alertas por threshold e por intervalo de tempo
    - Sistema de cores para diferentes níveis de alerta
    - Reinicialização automática programada a cada 2 dias
    - Persistência de dados em banco SQL Server
    - Rotação automática de logs
    - Templates HTML personalizados para emails

.PARAMETER SMTPServer
    Servidor SMTP para envio de emails (opcional, usa config se não fornecido)

.PARAMETER SMTPPort
    Porta do servidor SMTP (opcional, usa config se não fornecido)

.PARAMETER EmailSender
    Email remetente (opcional, usa config se não fornecido)

.PARAMETER EmailPassword
    Senha do email (opcional, usa arquivo configurado se não fornecido)

.PARAMETER EmailRecipients
    Array de destinatários (opcional, usa config se não fornecido)

.PARAMETER ProcessNames
    Array de nomes de processos a monitorar (opcional, usa config se vazio)

.PARAMETER ThresholdStep
    Incremento em MB para próximo threshold após alerta (padrão: 500MB)

.EXAMPLE
    .\verificaMemoria.ps1

.EXAMPLE
    .\verificaMemoria.ps1 -ProcessNames @("httpd", "node") -ThresholdStep 1000

.EXAMPLE
    .\verificaMemoria.ps1 -EmailRecipients @("admin@empresa.com") -ThresholdStep 250

.NOTES
    Arquivos requeridos:
    - config.psd1: Configurações do sistema
    - log-functions.ps1: Funções de gerenciamento de logs
    - database-connection.ps1: Funções de banco de dados
    - insertMemoryData.ps1: Script de inserção de dados
    - reiniciaServico.ps1: Script de reinicialização
    - Templates HTML em /templates/
    - Imagem do sistema em /src/

    Funcionalidades principais:
    - Verificação a cada 10 minutos
    - Alertas por threshold dinâmico
    - Notificações por intervalo configurável
    - Sistema de cores: Verde (menor), Amarelo (intermediário), Vermelho (maior)
    - Reinicialização automática a cada 2 dias às 3h
    - Persistência completa em banco de dados
    - Logs com rotação automática
#>

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

# Configuração de intervalo de notificações
$EmailNotificationIntervalHours = if ($config.EmailNotificationIntervalHours) { $config.EmailNotificationIntervalHours } else { 4 }

# Define processos a monitorar: parâmetro tem prioridade sobre config
if ($ProcessNames.Count -eq 0) {
    $ProcessNames = $config.ProcessesToMonitor
}

# Hash table para controlar thresholds de cada processo
$ProcessThresholds = @{}
$ProcessLastNotificationTime = @{}
$ProcessLastMemoryValue = @{}  # Nova variável para armazenar último valor de memória

# Controle para reinicialização automática a cada 2 dias às 3h
$LastAutoRestart = [datetime]::MinValue
$ScriptStartDate = (Get-Date).Date

if ($config.LastAutoRestart) {
    try {
        $LastAutoRestart = [datetime]::Parse($config.LastAutoRestart)
    } catch {
        $LastAutoRestart = [datetime]::MinValue
    }
}

# Se nunca reiniciou, considera o dia anterior como última reinicialização
# para que reinicie no primeiro dia que ligar
if ($LastAutoRestart -eq [datetime]::MinValue) {
    $LastAutoRestart = $ScriptStartDate.AddDays(-1)
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
    $ProcessLastMemoryValue[$ProcessName] = 0
}

# Importar funções auxiliares
. (Join-Path -Path $ScriptDir -ChildPath "log-functions.ps1")

# Verificar e rotacionar log se necessário
Start-LogRotation -LogFilePath $LogFile

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
$LogRotationCounter = 0
while ($true) {
    # Verificar rotação de log a cada 24 horas (144 ciclos de 10 min)
    $LogRotationCounter++
    if ($LogRotationCounter -ge 144) {
        Start-LogRotation -LogFilePath $LogFile
        $LogRotationCounter = 0
    }
    
    # Verificar se deve fazer reinicialização automática a cada 2 dias às 3h
    $Now = Get-Date
    if ($Now.Hour -eq 3 -and $Now.Minute -lt 10) {
        $Today = $Now.Date
        $DaysSinceLastRestart = ($Today - $LastAutoRestart).Days
        
        # Reinicializar se passaram 2 ou mais dias desde a última reinicialização
        if ($DaysSinceLastRestart -ge 2) {
            $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Add-Content -Path $LogFile -Value "$Timestamp - Iniciando reinicialização automática programada (a cada 2 dias às 3h)"
            
            foreach ($ProcessName in $ProcessNames) {
                try {
                    $RestartScript = Join-Path -Path $ScriptDir -ChildPath "reiniciaServico.ps1"
                    if (Test-Path $RestartScript) {
                        & $RestartScript -ProcessName $ProcessName -NomeUsuario "Sistema" -Motivo "Reinicialização automática programada (a cada 2 dias)" -TipoReinicio "Programado"
                        Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Reinicialização automática executada"
                    }
                } catch {
                    Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Erro na reinicialização automática: $_"
                }
            }
            
            $LastAutoRestart = $Today
            # Atualizar config com data da última reinicialização
            $config.LastAutoRestart = $Today.ToString("yyyy-MM-dd")
            
            # Salvar a data atualizada no arquivo de configuração
            try {
                # Lê o arquivo atual (compatível com PowerShell antigo)
                $configLines = Get-Content $configPath
                $configContent = $configLines -join "`n"
                
                $newDateValue = $Today.ToString('yyyy-MM-dd')
                $updated = $false
                
                # Processa linha por linha para substituir ou adicionar
                $newConfigLines = @()
                $foundLastAutoRestart = $false
                
                foreach ($line in $configLines) {
                    if ($line -match "^\s*LastAutoRestart\s*=") {
                        # Substitui linha existente
                        $newConfigLines += "    LastAutoRestart = '$newDateValue'"
                        $foundLastAutoRestart = $true
                        $updated = $true
                    } elseif ($line -match "^\s*}") {
                        # Se chegou no final e não encontrou LastAutoRestart, adiciona antes do }
                        if (-not $foundLastAutoRestart) {
                            $newConfigLines += "    LastAutoRestart = '$newDateValue'"
                            $updated = $true
                        }
                        $newConfigLines += $line
                    } else {
                        $newConfigLines += $line
                    }
                }
                
                if ($updated) {
                    Set-Content -Path $configPath -Value $newConfigLines -Encoding UTF8
                    Add-Content -Path $LogFile -Value "$Timestamp - Data da última reinicialização salva no config: $newDateValue"
                } else {
                    Add-Content -Path $LogFile -Value "$Timestamp - AVISO: Não foi possível atualizar LastAutoRestart no config"
                }
            } catch {
                Add-Content -Path $LogFile -Value "$Timestamp - Erro ao salvar data da reinicialização no config: $_"
            }
        }
    }

    foreach ($ProcessName in $ProcessNames) {
        $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $ShouldSendIntervalEmail = $false  # Inicializar controle de e-mail por intervalo
        
        if ($processes) {
            # Calcula memória total do processo
            $TotalMemoryMB = ($processes | Measure-Object WorkingSet64 -Sum).Sum / 1MB
            $TotalMemoryMB = [math]::Round($TotalMemoryMB, 2)
            
            # Obtém dados do sistema
            $TotalSystemMemoryMB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1MB, 2)
            $AvailableMemoryMB = [math]::Round((Get-WmiObject Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes, 2)
            $TotalUsedMemoryMB = $TotalSystemMemoryMB - $AvailableMemoryMB
            
            # Cálculos de percentuais para a nova mensagem
            $ProcessMemoryPercentageOfSystem = [math]::Round(($TotalMemoryMB / $TotalSystemMemoryMB) * 100, 2)
            $SystemUsedMemoryPercentage = [math]::Round(($TotalUsedMemoryMB / $TotalSystemMemoryMB) * 100, 2)
            
            # Controle de thresholds por processo
            $processControl = $ProcessThresholds[$ProcessName]
            $lastMemoryValue = $ProcessLastMemoryValue[$ProcessName]
            
            if ($processControl.FirstRun) {
                $processControl.NextNotificationLevel = ($TotalMemoryMB + $ThresholdStep)
                $processControl.NextNotificationLevel = [math]::Round($processControl.NextNotificationLevel, 2)
                $ProcessLastNotificationTime[$ProcessName] = Get-Date
                $processControl.NotificationReason = "upper"
                $processControl.FirstRun = $false
            }
            elseif ($TotalMemoryMB -le $processControl.NextNotificationLevel) {
                $elapsed = (Get-Date) - $ProcessLastNotificationTime[$ProcessName]
                
                # Verifica se deve enviar e-mail por intervalo de tempo (quando não ultrapassa limite)
                if ($elapsed.TotalHours -ge $EmailNotificationIntervalHours) {
                    # Determina o tipo de notificação baseado na comparação com o último valor
                    if ($TotalMemoryMB -gt $lastMemoryValue -and $lastMemoryValue -gt 0) {
                        $processControl.NotificationReason = "warning"  # Amarelo: menor que limite mas maior que anterior
                    } else {
                        $processControl.NotificationReason = "lower"    # Verde: menor que limite e menor que anterior
                    }
                    
                    $ProcessLastNotificationTime[$ProcessName] = Get-Date
                    Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Enviando notificação por intervalo ($EmailNotificationIntervalHours horas). Motivo: $($processControl.NotificationReason)"
                    
                    # Marcar para envio de e-mail
                    $ShouldSendIntervalEmail = $true
                }
                
                # Ajustar threshold após o mesmo intervalo configurado (lógica corrigida)
                if ($elapsed.TotalHours -ge $EmailNotificationIntervalHours) {
                    # Mantém uma pequena margem acima do valor atual para evitar travamento
                    $processControl.NextNotificationLevel = [math]::Round($TotalMemoryMB + 0.1, 2)
                    Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] NextNotificationLevel ajustado para $($processControl.NextNotificationLevel) MB após $EmailNotificationIntervalHours hora(s) sem ultrapassar."
                }
            }
            else {
                # Processo ultrapassou o threshold ou está na mesma faixa
                $elapsed = (Get-Date) - $ProcessLastNotificationTime[$ProcessName]
                
                # Mesmo quando ultrapassa, verificar se deve enviar por intervalo
                if ($elapsed.TotalHours -ge $EmailNotificationIntervalHours) {
                    # Determinar o motivo da notificação com base na comparação de valores
                    if ($lastMemoryValue -ne $null) {
                        if ($TotalMemoryMB -lt $lastMemoryValue) {
                            $processControl.NotificationReason = "lower"    # Verde: menor que anterior
                        } elseif ($TotalMemoryMB -gt $lastMemoryValue) {
                            $processControl.NotificationReason = "upper"    # Vermelho: maior que anterior  
                        } else {
                            $processControl.NotificationReason = "warning"  # Amarelo: igual ao anterior
                        }
                    } else {
                        $processControl.NotificationReason = "upper"        # Primeira execução, considerar vermelho
                    }
                    
                    $ProcessLastNotificationTime[$ProcessName] = Get-Date
                    Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Enviando notificação por intervalo ($EmailNotificationIntervalHours horas). Motivo: $($processControl.NotificationReason)"
                    
                    # Marcar para envio de e-mail
                    $ShouldSendIntervalEmail = $true
                } else {
                    $processControl.NotificationReason = "upper"
                }
            }
            
            # Atualizar último valor de memória para comparação futura
            $ProcessLastMemoryValue[$ProcessName] = $TotalMemoryMB
            
            # Log do status atual
            Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] consumindo $TotalMemoryMB MB ($ProcessMemoryPercentageOfSystem% do sistema). NextNotificationLevel: $($processControl.NextNotificationLevel). LastNotifiedLevel: $($processControl.LastNotifiedLevel). NotificationReason: $($processControl.NotificationReason). SistemaTotal: $TotalSystemMemoryMB MB. SistemaUsado: $TotalUsedMemoryMB MB ($SystemUsedMemoryPercentage%)"
            
            # Inserir dados de memória no banco
            try {
                $InsertMemoryScript = Join-Path -Path $ScriptDir -ChildPath "insertMemoryData.ps1"
                & $InsertMemoryScript -ProcessName $ProcessName -MemoryUsageMB $TotalMemoryMB -MemoryAvailableMB $TotalSystemMemoryMB -MemoryPercentage $ProcessMemoryPercentageOfSystem -Reason $processControl.NotificationReason
            }
            catch {
                Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Erro ao inserir dados no banco: $_"
            }
            
            # Verificar se precisa enviar notificação
            $ShouldSendThresholdEmail = ($TotalMemoryMB -ge $processControl.NextNotificationLevel -and $processControl.NextNotificationLevel -ne $processControl.LastNotifiedLevel)
            
            if ($ShouldSendThresholdEmail -or $ShouldSendIntervalEmail) {
                # Se for alerta por threshold, atualizar os controles
                if ($ShouldSendThresholdEmail) {
                    $processControl.LastNotifiedLevel = $processControl.NextNotificationLevel
                    $processControl.NextNotificationLevel = ($TotalMemoryMB + $ThresholdStep)
                }
                
                # Enviar e-mail de alerta
                try {
                    $MailMessage = New-Object System.Net.Mail.MailMessage
                    $MailMessage.IsBodyHtml = $true
                    $MailMessage.From = New-Object System.Net.Mail.MailAddress($EmailAlias, $EmailAliasName)
                    foreach ($recipient in $EmailRecipients) {
                        $MailMessage.To.Add($recipient)
                    }
                    
                    # Definir assunto baseado no tipo de alerta
                    if ($ShouldSendThresholdEmail) {
                        $Subject = "ALERTA: $ProcessName - Consumo de Memória Elevado"
                    } else {
                        $Subject = "INFO: $ProcessName - Status de Memória (Intervalo $EmailNotificationIntervalHours h)"
                    }
                    
                    $TemplatePath_alert = Join-Path -Path $ScriptDir -ChildPath "..\templates\emailMonitor_alerts.html"
                    
                    $Body = [System.IO.File]::ReadAllText($TemplatePath_alert)
                    $Body = $Body -replace "{{PROCESS_NAME}}", $ProcessName
                    $Body = $Body -replace "{{TOTAL_MEMORY}}", $TotalMemoryMB
                    $Body = $Body -replace "{{TIMESTAMP}}", $Timestamp
                    $Body = $Body -replace "{{NEXTLIMIT}}", $processControl.NextNotificationLevel
                    $Body = $Body -replace "{{NOTIFICATIONREASON}}", $processControl.NotificationReason
                    
                    # Novas variáveis para a mensagem melhorada
                    $Body = $Body -replace "{{TOTAL_SYSTEM_MEMORY_MB}}", $TotalSystemMemoryMB
                    $Body = $Body -replace "{{TOTAL_USED_MEMORY_MB}}", $TotalUsedMemoryMB
                    $Body = $Body -replace "{{PROCESS_MEMORY_PERCENT_SYSTEM}}", $ProcessMemoryPercentageOfSystem
                    $Body = $Body -replace "{{SYSTEM_USED_MEMORY_PERCENT}}", $SystemUsedMemoryPercentage

                    $AlternateView = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($Body, [System.Text.Encoding]::UTF8, "text/html")
                    $LinkedResource = New-Object System.Net.Mail.LinkedResource($ImagePath, "image/png")
                    $LinkedResource.ContentId = "logoimg"
                    $AlternateView.LinkedResources.Add($LinkedResource)
                    $MailMessage.AlternateViews.Add($AlternateView)
                    $MailMessage.Subject = $Subject
                    $MailMessage.SubjectEncoding = [System.Text.Encoding]::UTF8
                    
                    $SMTPClient.Send($MailMessage)
                    
                    if ($ShouldSendThresholdEmail) {
                        Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Alerta de memória enviado (threshold). Consumo: $TotalMemoryMB MB"
                    } else {
                        Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Notificação de status enviada (intervalo). Consumo: $TotalMemoryMB MB. Motivo: $($processControl.NotificationReason)"
                    }
                    
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

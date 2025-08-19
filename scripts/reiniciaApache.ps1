param (
   [Parameter(Mandatory=$true)]
   [string]$NomeUsuario,  # Nome de quem executou o script
   [Parameter(Mandatory=$true)]
   [string]$Motivo,  # Motivo do reinício

   [string]$SMTPServer,
   [int]$SMTPPort,
   [string]$EmailSender,
   [string]$EmailPassword,
   [string[]]$EmailRecipients,

   [string]$ProcessName = "httpd",
   [string]$TipoReinicio = "Forçado"  # Padrão será "Forçado", caso não seja especificado
)

# Preenche parametros caso não forem passados (senha só é preenchida se for o mesmo usuario que criptografou)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configPath = Join-Path -Path $ScriptDir -ChildPath "..\conf\config.psd1"
$configText = Get-Content $configPath | Out-String
$config = Invoke-Expression $configText

if (-not $SMTPServer)       { $SMTPServer     = $config.SMTPServer }
if (-not $SMTPPort)         { $SMTPPort       = $config.SMTPPort }
if (-not $EmailSender)      { $EmailSender    = $config.EmailSender }
if (-not $EmailRecipients)  { $EmailRecipients= $config.EmailRecipients }
if ($config.EmailAlias)     { $EmailAlias = $config.EmailAlias } else { $EmailAlias = $EmailSender }
if ($config.EmailAliasName) { $EmailAliasName = $config.EmailAliasName } else { $EmailAliasName = '' }
if (-not $LogFile) { $LogFile = Join-Path -Path $ScriptDir -ChildPath $config.LogFile }
if (-not $EmailPassword)    { 
    $EmailPassword = Get-Content (Join-Path -Path $ScriptDir -ChildPath $config.SenhaPath) 
}

if ($TipoReinicio -eq "Teste") {
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Timestamp - Reinício de teste solicitado por $NomeUsuario. Nenhuma ação executada."
    Write-Host "Reinício de teste solicitado. Nenhuma ação executada."
    return
}

if ($TipoReinicio -eq "Forçado") {
   $SMTPClient = New-Object System.Net.Mail.SmtpClient($SMTPServer, $SMTPPort)
   $SMTPClient.EnableSsl = $false
   
   $SMTPClient.Credentials = New-Object System.Net.NetworkCredential($EmailSender, $EmailPassword)

   $ImagePath = Join-Path -Path $ScriptDir -ChildPath "..\src\ITSYSTEM_p.png"

   # Obtém o uso de memória antes do reinício
   $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
   $MemoryBeforeRestart = if ($processes) { ($processes | Measure-Object WorkingSet64 -Sum).Sum / 1MB } else { 0 }
   $MemoryBeforeRestart = [math]::Round($MemoryBeforeRestart, 2)   
}

# Definir caminhos do Apache para todos os ambientes
$ApacheServices = @(
   "Apache2.4.10Dev"
   "Apache2.4.10Prod",
   "ApacheHomologa"
)

# Reinicia o serviço
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

try {
   Stop-Process -Name $ProcessName -Force
   Add-Content -Path $LogFile -Value "$Timestamp - Serviço $ProcessName parado com sucesso."
} catch {
   Add-Content -Path $LogFile -Value "$Timestamp - Erro ao parar o serviço $($ProcessName): $_"
}

Start-Sleep -Seconds 5 # Aguarda serviço reiniciar
foreach ($Service in $ApacheServices) {
   $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

   try {
      Start-Service -Name $Service
      Add-Content -Path $LogFile -Value "$Timestamp - Serviço $Service iniciado com sucesso."
   } catch {
      Add-Content -Path $LogFile -Value "$Timestamp - Erro ao iniciar o serviço $($Service): $_"
   }
}
Start-Sleep -Seconds 25 # Aguarda serviço reiniciar

if ($TipoReinicio -eq "Forçado") {
   # Obtém o uso de memória após o reinício
   $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
   $MemoryAfterRestart = if ($processes) { ($processes | Measure-Object WorkingSet64 -Sum).Sum / 1MB } else { 0 }
   $MemoryAfterRestart = [math]::Round($MemoryAfterRestart, 2)

   $TotalSystemMemoryMB = [math]::Round((Get-WmiObject Win32_OperatingSystem).TotalVisibleMemorySize / 1024, 2)

   # Registra no log
   $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

   $MailMessage = New-Object System.Net.Mail.MailMessage
   $MailMessage.IsBodyHtml = $true  # Ativar HTML no e-mail
   $MailMessage.From = New-Object System.Net.Mail.MailAddress($EmailAlias, $EmailAliasName)
   foreach ($recipient in $EmailRecipients) {
      $MailMessage.To.Add($recipient)
   }

   $TemplatePath_alert = Join-Path -Path $ScriptDir -ChildPath "..\templates\emailMonitor_restartForce.html"

   $Body = [System.IO.File]::ReadAllText($TemplatePath_alert)
   $Body = $Body -replace "{{MEMORY_BEFORE}}", $MemoryBeforeRestart
   $Body = $Body -replace "{{MEMORY_PERCENTAGE_BEFORE}}", [math]::Round(($MemoryBeforeRestart / $TotalSystemMemoryMB) * 100, 2)
   $Body = $Body -replace "{{MEMORY_AFTER}}", $MemoryAfterRestart
   $Body = $Body -replace "{{MEMORY_PERCENTAGE_AFTER}}", [math]::Round(($MemoryAfterRestart / $TotalSystemMemoryMB) * 100, 2)
   $Body = $Body -replace "{{TOTAL_SYSTEM_MEMORY}}", $TotalSystemMemoryMB
   $Body = $Body -replace "{{TIMESTAMP}}", $Timestamp
   $Body = $Body -replace "{{REQUERENTE}}", $NomeUsuario
   $Body = $Body -replace "{{JUSTIFICATIVA}}", $Motivo

   $AlternateView = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($Body, [System.Text.Encoding]::UTF8, "text/html")

   $LinkedResource = New-Object System.Net.Mail.LinkedResource($ImagePath, "image/png")
   $LinkedResource.ContentId = "logoimg"  # O mesmo CID usado no HTML
   $AlternateView.LinkedResources.Add($LinkedResource)
   $MailMessage.AlternateViews.Add($AlternateView)

   $MailMessage.Subject = "Reinicializacao Forcada: $ProcessName"
   $MailMessage.Body = $Body

   Add-Content -Path $LogFile -Value "$Timestamp - REINÍCIO FORÇADO: $ProcessName reiniciado. Memória antes: $MemoryBeforeRestart MB, depois: $MemoryAfterRestart MB."

   # Inserir dados de reinício no banco Z112
   try {
       $RestartTypeCode = "F"  # F = Forçado
       $InsertRestartScript = Join-Path -Path $ScriptDir -ChildPath "insertRestartData.ps1"
       & $InsertRestartScript -ProcessName $ProcessName -RestartType $RestartTypeCode -RequestedBy $NomeUsuario -Reason $Motivo -SystemRestart "S"
   }
   catch {
       Add-Content -Path $LogFile -Value "$Timestamp - Erro ao inserir dados no banco Z112: $_"
   }

   try {
      $SMTPClient.Send($MailMessage)
      Add-Content -Path $LogFile -Value "$Timestamp - Notificação de reinício enviada para: $($EmailRecipients -join ', ')."
   }
   catch {
      Add-Content -Path $LogFile -Value "$Timestamp - Erro ao enviar e-mail de reinício: $_"
   }
} else {
    # Inserir dados de reinício no banco Z112
   try {
       $RestartTypeCode = "P"  # P = Programado
       $InsertRestartScript = Join-Path -Path $ScriptDir -ChildPath "insertRestartData.ps1"
       & $InsertRestartScript -ProcessName $ProcessName -RestartType $RestartTypeCode -RequestedBy $NomeUsuario -Reason $Motivo -SystemRestart "S"
   }
   catch {
       Add-Content -Path $LogFile -Value "$Timestamp - Erro ao inserir dados no banco Z112: $_"
   }
}


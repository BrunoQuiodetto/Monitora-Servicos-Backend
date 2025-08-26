param (
   [Parameter(Mandatory=$true)]
   [string]$NomeUsuario,  # Nome de quem executou o script
   [Parameter(Mandatory=$true)]
   [string]$Motivo,  # Justificativa do usuário

   [string]$SMTPServer,
   [int]$SMTPPort,
   [string]$EmailSender,
   [string]$EmailPassword,
   [string[]]$EmailRecipients,

   [string]$ProcessName = "MonitoraApache"
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

try {
   schtasks /End /TN "$ProcessName"
   Add-Content -Path $LogFile -Value "$Timestamp - Serviço $ProcessName parado com sucesso."
}
catch {
   Add-Content -Path $LogFile -Value "$Timestamp - Erro ao parar o serviço $($ProcessName): $_"
}

Start-Sleep -Seconds 5 # Aguarda serviço reiniciar

try{
   schtasks /Run /TN "$ProcessName"
   Add-Content -Path $LogFile -Value "$Timestamp - Serviço $ProcessName iniciado com sucesso."
}
catch {
   Add-Content -Path $LogFile -Value "$Timestamp - Erro ao iniciar o serviço $($ProcessName): $_"
}

$SMTPClient = New-Object System.Net.Mail.SmtpClient($SMTPServer, $SMTPPort)
$SMTPClient.EnableSsl = $false

$SMTPClient.Credentials = New-Object System.Net.NetworkCredential($EmailSender, $EmailPassword)

$ImagePath = Join-Path -Path $ScriptDir -ChildPath "..\src\ITSYSTEM_p.png"

$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$MailMessage = New-Object System.Net.Mail.MailMessage
$MailMessage.IsBodyHtml = $true  # Ativar HTML no e-mail
$MailMessage.From = New-Object System.Net.Mail.MailAddress($EmailAlias, $EmailAliasName)
foreach ($recipient in $EmailRecipients) {
   $MailMessage.To.Add($recipient)
}

$TemplatePath_alert = Join-Path -Path $ScriptDir -ChildPath "..\templates\emailMonitor_restartProgram.html"

$Body = [System.IO.File]::ReadAllText($TemplatePath_alert)
$Body = $Body -replace "{{USUARIO}}", $NomeUsuario
$Body = $Body -replace "{{JUSTIFICATIVA}}", $Motivo
$Body = $Body -replace "{{TIMESTAMP}}", $Timestamp
$AlternateView = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($Body, [System.Text.Encoding]::UTF8, "text/html")

$LinkedResource = New-Object System.Net.Mail.LinkedResource($ImagePath, "image/png")
$LinkedResource.ContentId = "logoimg"  # O mesmo CID usado no HTML
$AlternateView.LinkedResources.Add($LinkedResource)
$MailMessage.AlternateViews.Add($AlternateView)

$MailMessage.Subject = "Atualizacao no Monitoramento"
$MailMessage.Body = $Body

# Inserir dados de reinício no banco Z112 
try {
    $RestartTypeCode = "A"  # A = Atualização
    $InsertRestartScript = Join-Path -Path $ScriptDir -ChildPath "insertRestartData.ps1"
    & $InsertRestartScript -ProcessName $ProcessName -RestartType $RestartTypeCode -RequestedBy $NomeUsuario -Reason $Motivo -SystemRestart "N"
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

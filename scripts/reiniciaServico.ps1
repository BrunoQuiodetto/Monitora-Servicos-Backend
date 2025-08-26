param (
    [Parameter(Mandatory = $true)]
    [string]$NomeUsuario,  # Nome de quem executou o script
    [Parameter(Mandatory = $true)]
    [string]$Motivo,  # Motivo do reinício

    [string]$SMTPServer,
    [int]$SMTPPort,
    [string]$EmailSender,
    [string]$EmailPassword,
    [string[]]$EmailRecipients,

    [string]$ProcessName = "httpd",  # Processo a ser reiniciado
    [string]$ServiceName = "",       # Nome do serviço Windows (opcional)
    [string]$TipoReinicio = "Forçado"  # Padrão será "Forçado", caso não seja especificado
)

# Preenche parametros caso não forem passados
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

# Determinar nome do serviço Windows se não foi especificado
if (-not $ServiceName -or $ServiceName.Trim() -eq "") {
    if ($config.ProcessServiceMap -and $config.ProcessServiceMap[$ProcessName]) {
        $ServiceName = $config.ProcessServiceMap[$ProcessName]
    }
}

# Função para reiniciar processo por nome
function Restart-ProcessByName {
    param($ProcessName, $LogFile, $ServiceName = "")

    $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    if ($processes) {
        $processes | ForEach-Object {
            Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Finalizando processo $ProcessName (PID: $($_.Id))"
            $_.Kill()
        }
        Start-Sleep -Seconds 5
        Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Processo $ProcessName finalizado"
    }
    else {
        Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Processo $ProcessName não estava em execução"
    }

    # Tenta iniciar o processo novamente
    try {
        $exePath = (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1).Path
        if ($exePath) {
            Start-Process -FilePath $exePath
            Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Processo $ProcessName iniciado novamente via executável"
            return $true
        }
        elseif ($ServiceName -and $ServiceName.Trim() -ne "") {
            # Tenta iniciar via serviço se não encontrou o executável
            Start-Sleep -Seconds 5
            schtasks /Run /TN "$ServiceName"
            Start-Sleep -Seconds 10
            Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Processo $ProcessName iniciado via task $ServiceName"
            return $true
        }
        else {
            Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Não foi possível iniciar o processo $ProcessName"
            return $false
        }
    }
    catch {
        Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Erro ao tentar iniciar o processo: $_"
        return $false
    }
}

# Função para reiniciar serviço Windows
function Restart-WindowsService {
    param($ServiceName, $LogFile)
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogFile -Value "$Timestamp - [$ServiceName] Reiniciando serviço Windows: $ServiceName"
        Restart-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 10
        $service = Get-Service -Name $ServiceName
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogFile -Value "$Timestamp - [$ServiceName] Serviço $ServiceName está: $($service.Status)"
        return $true
    }
    return $false
}

if ($TipoReinicio -eq "Teste") {
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Reinício de teste solicitado por $NomeUsuario. Nenhuma ação executada."
    Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Reinício de teste solicitado para $ProcessName. Nenhuma ação executada."
    return
}

if ($TipoReinicio -eq "Forçado" -or $TipoReinicio -eq "Programado") {
    $SMTPClient = New-Object System.Net.Mail.SmtpClient($SMTPServer, $SMTPPort)
    $SMTPClient.EnableSsl = $false
   
    $SMTPClient.Credentials = New-Object System.Net.NetworkCredential($EmailSender, $EmailPassword)

    $ImagePath = Join-Path -Path $ScriptDir -ChildPath "..\src\ITSYSTEM_p.png"

    # Obtém o uso de memória antes do reinício
    $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($processes) {
        $TotalMemoryMB = ($processes | Measure-Object WorkingSet64 -Sum).Sum / 1MB
        $TotalMemoryMB = [math]::Round($TotalMemoryMB, 2)
    }
    else {
        $TotalMemoryMB = 0
    }

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
   
    # Determinar template baseado no tipo de reinício
    $TemplatePath = switch ($TipoReinicio) {
        "Forçado" { Join-Path -Path $ScriptDir -ChildPath "..\templates\emailMonitor_restartForce.html" }
        "Programado" { Join-Path -Path $ScriptDir -ChildPath "..\templates\emailMonitor_restart.html" }
        default { Join-Path -Path $ScriptDir -ChildPath "..\templates\emailMonitor_restartForce.html" }
    }

    # Log antes do reinício
    Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Início do reinício $TipoReinicio solicitado por $NomeUsuario. Motivo: $Motivo. Memória antes: $TotalMemoryMB MB"

    # Realizar o reinício
    $reinicioSucesso = $false
   
    if ($ServiceName -and $ServiceName.Trim() -ne "") {
        # Tentar reiniciar como serviço Windows primeiro
        $reinicioSucesso = Restart-WindowsService -ServiceName $ServiceName -LogFile $LogFile
        if ($reinicioSucesso) {
            Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Serviço Windows '$ServiceName' reiniciado com sucesso"
        }
    }
   
    if (-not $reinicioSucesso) {
        # Reiniciar como processo
        $reinicioSucesso = Restart-ProcessByName -ProcessName $ProcessName -LogFile $LogFile -ServiceName $ServiceName
        if ($reinicioSucesso) {
            Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Processo '$ProcessName' finalizado com sucesso"
        }
        else {
            Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] ATENÇÃO: Processo '$ProcessName' não estava em execução"
        }
    }

    # Aguardar um tempo para o processo/serviço reiniciar
    Start-Sleep -Seconds 10

    # Verificar se o processo está rodando após o reinício
    $processosApos = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($processosApos) {
        $TotalMemoryAfterMB = ($processosApos | Measure-Object WorkingSet64 -Sum).Sum / 1MB
        $TotalMemoryAfterMB = [math]::Round($TotalMemoryAfterMB, 2)
        Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Processo reiniciado e está consumindo $TotalMemoryAfterMB MB"
    }
    else {
        Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] ATENÇÃO: Processo não foi encontrado após tentativa de reinício"
    }

    # Preparar e enviar e-mail
    try {
        $MailMessage = New-Object System.Net.Mail.MailMessage
        $MailMessage.BodyEncoding = [System.Text.Encoding]::UTF8
        $MailMessage.SubjectEncoding = [System.Text.Encoding]::UTF8
        $MailMessage.IsBodyHtml = $true
        $MailMessage.From = New-Object System.Net.Mail.MailAddress($EmailAlias, $EmailAliasName)
       
        foreach ($recipient in $EmailRecipients) {
            $MailMessage.To.Add($recipient)
        }

        $Subject = "IT MONITORA | Reinício $TipoReinicio - $ProcessName"
       
        $Body = [System.IO.File]::ReadAllText($TemplatePath)
        $Body = $Body -replace "{{SERVICE_NAME}}", $ProcessName
        $Body = $Body -replace "{{REQUERENTE}}", $NomeUsuario
        $Body = $Body -replace "{{JUSTIFICATIVA}}", $Motivo
        $Body = $Body -replace "{{RESTART_TYPE}}", $TipoReinicio
        $Body = $Body -replace "{{MEMORY_BEFORE}}", $TotalMemoryMB
        $Body = $Body -replace "{{MEMORY_AFTER}}", $(if ($processosApos) { $TotalMemoryAfterMB } else { "N/A" })
        # Obter memória total do sistema
        $TotalSystemMemoryMB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1MB, 2)

        # Calcular porcentagem de uso de memória pelo processo antes e depois
        if ($TotalSystemMemoryMB -gt 0) {
            $MemoryPercentageBefore = [math]::Round(($TotalMemoryMB / $TotalSystemMemoryMB) * 100, 2)
            $MemoryPercentageAfter = if ($processosApos) { [math]::Round(($TotalMemoryAfterMB / $TotalSystemMemoryMB) * 100, 2) } else { "N/A" }
        }
        else {
            $MemoryPercentageBefore = "N/A"
            $MemoryPercentageAfter = "N/A"
        }

        $Body = $Body -replace "{{TOTAL_SYSTEM_MEMORY}}", $TotalSystemMemoryMB
        $Body = $Body -replace "{{MEMORY_PERCENTAGE_BEFORE}}", $MemoryPercentageBefore
        $Body = $Body -replace "{{MEMORY_PERCENTAGE_AFTER}}", $MemoryPercentageAfter
        $Body = $Body -replace "{{TIMESTAMP}}", $Timestamp


        $AlternateView = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($Body, [System.Text.Encoding]::UTF8, "text/html")
       
        if (Test-Path $ImagePath) {
            $LinkedResource = New-Object System.Net.Mail.LinkedResource($ImagePath, "image/png")
            $LinkedResource.ContentId = "logoimg"
            $AlternateView.LinkedResources.Add($LinkedResource)
        }
       
        $MailMessage.AlternateViews.Add($AlternateView)
        $MailMessage.Subject = $Subject

        $SMTPClient.Send($MailMessage)
        Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] E-mail de confirmação de reinício enviado"
       
        $MailMessage.Dispose()
    }
    catch {
        Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Erro ao enviar e-mail de confirmação: $_"
    }

    # Inserir dados no banco se o script existir
    try {
        $InsertRestartScript = Join-Path -Path $ScriptDir -ChildPath "insertRestartData.ps1"
        if (Test-Path $InsertRestartScript) {
            & $InsertRestartScript -ProcessName $ProcessName -RequestedBy $NomeUsuario -Reason $Motivo -RestartType $TipoReinicio -SystemRestart 'S'
        }
    }
    catch {
        Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Erro ao inserir dados de reinício no banco: $_"
    }

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Timestamp - [$ProcessName] Reinício do processo $ProcessName concluído."
}

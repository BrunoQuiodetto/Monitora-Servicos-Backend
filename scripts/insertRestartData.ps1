# Script para inserir informações de reinício na tabela Z112
# Tabela Z112: Informações de reinício por serviço

param (
    [Parameter(Mandatory=$true)]
    [string]$ProcessName,
    
    [Parameter(Mandatory=$true)]
    [string]$RestartType,  # "P" = Programado, "F" = Forçado, "A" = Atualização
    
    [Parameter(Mandatory=$true)]
    [string]$RequestedBy,  # Nome do usuário que solicitou
    
    [Parameter(Mandatory=$true)]
    [string]$Reason,  # Motivo do reinício
    
    [Parameter(Mandatory=$true)]
    [string]$SystemRestart = "N",  # "S" = Sim, "N" = Não
    
    [string]$ServerInstance,
    [string]$Database,
    [string]$Username,
    [string]$Password,
    [string]$IntegratedSecurity = "False"
)

# Importa as funções de conexão com banco
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path -Path $ScriptDir -ChildPath "database-connection.ps1")

# Carrega configurações se não foram fornecidas
$configPath = Join-Path -Path $ScriptDir -ChildPath "..\conf\config.psd1"
if (Test-Path $configPath) {
    $configText = Get-Content $configPath | Out-String
    $config = Invoke-Expression $configText
    
    if (-not $ServerInstance) { $ServerInstance = $config.DatabaseServer }
    if (-not $Database) { $Database = $config.DatabaseName }
    if (-not $Username) { $Username = $config.DatabaseUser }
    if (-not $Password -and $config.DatabasePasswordPath) { 
        $Password = Get-Content (Join-Path -Path $ScriptDir -ChildPath $config.DatabasePasswordPath)
    }
}

try {
    # Estabelece conexão
    $Connection = New-SQLConnection -ServerInstance $ServerInstance -Database $Database -Username $Username -Password $Password -IntegratedSecurity $IntegratedSecurity
    
    if ($Connection) {
        # Prepara o comando SQL para inserir na tabela Z112
        $Now = Get-Date
        $DataReinicio = $Now.ToString("yyyyMMdd")  # Formato YYYYMMDD
        $HoraReinicio = $Now.ToString("HH:mm")     # Formato HH:MM
        
        # Escapa aspas simples no texto
        $ReasonEscaped = $Reason -replace "'", "''"
        $RequestedByEscaped = $RequestedBy -replace "'", "''"
        
        # Converte tipo de reinício para código
        $TipoCode = switch ($RestartType.ToUpper()) {
            "PROGRAMADO" { "P" }
            "FORCADO" { "F" }
            "FORÇADO" { "F" }
            "ATUALIZACAO" { "A" }
            "ATUALIZAÇÃO" { "A" }
            default { $RestartType.Substring(0,1).ToUpper() }  # Pega primeiro caractere se não encontrar
        }
        
        $InsertQuery = @"
INSERT INTO Z112020 (
    Z112_DATA,
    Z112_HORA,
    Z112_TIPO,
    Z112_AUTOR,
    Z112_MOTIVO,
    Z112_SISTEMA,
    Z112_SERVICO,
    D_E_L_E_T_
) VALUES (
    '$DataReinicio',
    '$HoraReinicio',
    '$TipoCode',
    '$RequestedByEscaped',
    '$ReasonEscaped',
    '$SystemRestart',
    '$ProcessName',
    ''
)
"@

        # Executa o comando
        $RowsAffected = Invoke-SQLCommand -Connection $Connection -Query $InsertQuery
        
        if ($RowsAffected -gt 0) {
            Write-Host "Informações de reinício inseridas com sucesso na tabela Z112" -ForegroundColor Green
            
            # Log da operação
            $LogFile = Join-Path -Path $ScriptDir -ChildPath "..\log\apacheMonitor_log.txt"
            $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            # Add-Content -Path $LogFile -Value "$Timestamp - BANCO: Dados de reinício inseridos na Z112 - Serviço: $ProcessName, Tipo: $TipoCode, Solicitante: $RequestedBy, Sistema: $SystemRestart"
        } else {
            Write-Warning "Nenhuma linha foi inserida na tabela Z112"
        }
        
        # Fecha a conexão
        Close-SQLConnection -Connection $Connection
    }
}
catch {
    Write-Error "Erro ao inserir dados na tabela Z112: $_"
    
    # Log do erro
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogFile = Join-Path -Path $ScriptDir -ChildPath "..\log\apacheMonitor_log.txt"
    Add-Content -Path $LogFile -Value "$Timestamp - ERRO BANCO Z112: $_"
}
finally {
    # Limpa a senha da memória se necessário
    if ($Password) {
        $Password = $null
    }
}

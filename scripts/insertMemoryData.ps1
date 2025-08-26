# Script para inserir informações de memória na tabela Z111
# Tabela Z111: Informações de memória por serviço

param (
    [Parameter(Mandatory=$true)]
    [string]$ProcessName,
    
    [Parameter(Mandatory=$true)]
    [double]$MemoryUsageMB,
    
    [Parameter(Mandatory=$true)]
    [double]$MemoryAvailableMB,
    
    [Parameter(Mandatory=$true)]
    [double]$MemoryPercentage,
    
    [Parameter(Mandatory=$true)]
    [string]$Reason = "MONI", # Código da razão (ex: MONI para monitoramento)
    
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
        # Prepara o comando SQL para inserir na tabela Z111
        $Now = Get-Date
        $DataRegistro = $Now.ToString("yyyyMMdd")  # Formato YYYYMMDD
        $HoraRegistro = $Now.ToString("HH:mm")     # Formato HH:MM
        
        # Formata os valores conforme necessário
        $MemoryUsageFormatted = [math]::Round($MemoryUsageMB, 2).ToString()
        $MemoryAvailableFormatted = [math]::Round($MemoryAvailableMB, 2).ToString()
        $PercentageFormatted = [math]::Round($MemoryPercentage, 0).ToString().PadLeft(3, '0')  # 3 dígitos com zeros à esquerda
        
        $InsertQuery = @"
INSERT INTO Z111020 (
    Z111_DATA,
    Z111_HORA,
    Z111_USADA,
    Z111_DISPO,
    Z111_RAZAO,
    Z111_PERCENT,
    Z111_SERVICO,
    D_E_L_E_T_
) VALUES (
    '$DataRegistro',
    '$HoraRegistro',
    '$MemoryUsageFormatted',
    '$MemoryAvailableFormatted',
    '$Reason',
    '$PercentageFormatted',
    '$ProcessName',
    ''
)
"@

        # Executa o comando
        $RowsAffected = Invoke-SQLCommand -Connection $Connection -Query $InsertQuery
        
        if ($RowsAffected -gt 0) { 
            # Log da operação
            $LogFile = Join-Path -Path $ScriptDir -ChildPath "..\log\apacheMonitor_log.txt"
            $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
        # Fecha a conexão
        Close-SQLConnection -Connection $Connection
    }
}
catch {
    # Log do erro
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogFile = Join-Path -Path $ScriptDir -ChildPath "..\log\apacheMonitor_log.txt"
    Add-Content -Path $LogFile -Value "$Timestamp - ERRO BANCO Z111: $_"
}
finally {
    # Limpa a senha da memória se necessário
    if ($Password) {
        $Password = $null
    }
}

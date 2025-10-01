# Script para inserir dados de monitoramento de memória no banco de dados
# Arquivo: insertMemoryData.ps1
# Insere informações de consumo de memória na tabela Z111020

<#
.SYNOPSIS
    Insere dados de monitoramento de memória no banco de dados

.DESCRIPTION
    Script responsável por inserir informações de consumo de memória de processos
    na tabela Z111020 do banco de dados. Utiliza as configurações do arquivo config.psd1
    e as funções de conexão do database-connection.ps1.

.PARAMETER ProcessName
    Nome do processo que está sendo monitorado (ex: "httpd", "node")

.PARAMETER MemoryUsageMB
    Quantidade de memória em uso pelo processo em MB

.PARAMETER MemoryAvailableMB
    Quantidade total de memória disponível no sistema em MB

.PARAMETER MemoryPercentage
    Percentual de uso de memória do processo em relação ao sistema

.PARAMETER Reason
    Código da razão do monitoramento (padrão: "MONI" para monitoramento)

.PARAMETER ServerInstance
    Instância do SQL Server (opcional, usa config se não fornecido)

.PARAMETER Database
    Nome do banco de dados (opcional, usa config se não fornecido)

.PARAMETER Username
    Usuário do banco (opcional, usa config se não fornecido)

.PARAMETER Password
    Senha do banco (opcional, usa config se não fornecido)

.PARAMETER IntegratedSecurity
    Usar autenticação Windows (padrão: "False")

.EXAMPLE
    .\insertMemoryData.ps1 -ProcessName "httpd" -MemoryUsageMB 1024.50 -MemoryAvailableMB 32768 -MemoryPercentage 3.12

.EXAMPLE
    .\insertMemoryData.ps1 -ProcessName "node" -MemoryUsageMB 512.25 -MemoryAvailableMB 32768 -MemoryPercentage 1.56 -Reason "ALERT"

.NOTES
    - Requer o arquivo de configuração config.psd1 
    - Requer as funções do database-connection.ps1
    - Logs de sucesso/erro são escritos no arquivo configurado em LogFile
    - A tabela Z111020 deve existir no banco de dados de destino
#>

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
    
    # Define o arquivo de log a partir da configuração
    $LogFile = Join-Path -Path $ScriptDir -ChildPath $config.LogFile
}

try {
    # Estabelece conexão
    $Connection = New-SQLConnection -ServerInstance $ServerInstance -Database $Database -Username $Username -Password $Password -IntegratedSecurity $IntegratedSecurity
    
    if ($Connection -and $Connection.State -eq 'Open') {
        # Prepara o comando SQL para inserir na tabela Z111
        $Now = Get-Date
        $DataRegistro = $Now.ToString("yyyyMMdd")  # Formato YYYYMMDD
        $HoraRegistro = $Now.ToString("HH:mm")     # Formato HH:MM
        
        # Formata os valores conforme necessário
        $MemoryUsageFormatted = [math]::Round($MemoryUsageMB, 2).ToString()
        $MemoryAvailableFormatted = [math]::Round($MemoryAvailableMB, 2).ToString()
        $PercentageFormatted = [math]::Round($MemoryPercentage, 0).ToString().PadLeft(3, '0')  # 3 dígitos com zeros à esquerda
        
        # Usa MERGE para inserir ou atualizar dados existentes
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
);
"@

        # Executa o comando
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Result = Invoke-SQLCommand -Connection $Connection -Query $InsertQuery
        
        # Log da operação com detalhes completos
        if ($Result.Success) {
            if ($Result.RowsAffected -gt 0) { 
                Add-Content -Path $LogFile -Value "$Timestamp - [DB] Dados salvos no banco para [$ProcessName]: $MemoryUsageFormatted MB ($PercentageFormatted%) [$($Result.RowsAffected) linha(s) afetada(s)]"
            } elseif ($Result.RowsAffected -eq 0) {
                Add-Content -Path $LogFile -Value "$Timestamp - [DB] AVISO: Nenhuma linha afetada para [$ProcessName] - Dados idênticos já existem"
            }
        } else {
            # Log detalhado do erro com query
            Add-Content -Path $LogFile -Value "$Timestamp - [DB] ERRO na execução para [$ProcessName]:"
            Add-Content -Path $LogFile -Value "$Timestamp - [DB] ERRO SQL: $($Result.Error)"
            if ($Result.SqlState) {
                Add-Content -Path $LogFile -Value "$Timestamp - [DB] ERRO SQL State: $($Result.SqlState)"
            }
            Add-Content -Path $LogFile -Value "$Timestamp - [DB] QUERY EXECUTADA:"
            
            # Log da query em linhas separadas para melhor legibilidade
            $QueryLines = $Result.Query -split "`n"
            foreach ($Line in $QueryLines) {
                if ($Line.Trim()) {
                    Add-Content -Path $LogFile -Value "$Timestamp - [DB] QUERY: $($Line.Trim())"
                }
            }
        }
        
        # Fecha a conexão
        Close-SQLConnection -Connection $Connection
    } else {
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        if ($LogFile) {
            Add-Content -Path $LogFile -Value "$Timestamp - [DB] ERRO: Não foi possível estabelecer conexão com o banco para [$ProcessName]"
        }
    }
}
catch {
    # Log do erro
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ($LogFile) {
        Add-Content -Path $LogFile -Value "$Timestamp - [DB] ERRO na inserção para [$ProcessName]: $_"
    }
}
finally {
    # Limpa a senha da memória se necessário
    if ($Password) {
        $Password = $null
    }
}

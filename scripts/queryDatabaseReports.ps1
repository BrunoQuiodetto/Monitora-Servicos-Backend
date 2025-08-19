# Script para consultar dados das tabelas Z111 e Z112
# Relatórios de monitoramento do Apache

param (
    [string]$ReportType = "memory", # "memory", "restart", "summary"
    [string]$ProcessName = "httpd",
    [int]$LastDays = 7,
    [string]$ServerInstance,
    [string]$Database,
    [string]$Username,
    [SecureString]$Password,
    [string]$IntegratedSecurity = "True"
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
        $PasswordString = Get-Content (Join-Path -Path $ScriptDir -ChildPath $config.DatabasePasswordPath)
        $Password = ConvertTo-SecureString $PasswordString -AsPlainText -Force
    }
}

# Converte SecureString para string (necessário para ADO.NET)
$PasswordPlainText = ""
if ($Password) {
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $PasswordPlainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

try {
    # Estabelece conexão
    $Connection = New-SQLConnection -ServerInstance $ServerInstance -Database $Database -Username $Username -Password $PasswordPlainText -IntegratedSecurity $IntegratedSecurity
    
    if ($Connection) {
        $DateFilter = (Get-Date).AddDays(-$LastDays).ToString("yyyy-MM-dd")
        
        switch ($ReportType.ToLower()) {
            "memory" {
                Write-Host "=== RELATÓRIO DE USO DE MEMÓRIA (Últimos $LastDays dias) ===" -ForegroundColor Yellow
                
                $DateFilter = (Get-Date).AddDays(-$LastDays).ToString("yyyyMMdd")
                
                $MemoryQuery = @"
SELECT 
    Z111_DATA as Data_Registro,
    Z111_HORA as Hora_Registro,
    Z111_SERVICO as Servico,
    Z111_USADA as Memoria_Usada_MB,
    Z111_DISPO as Memoria_Disponivel_MB,
    Z111_PERCENT as Percentual_Uso,
    Z111_RAZAO as Razao
FROM Z111 
WHERE Z111_SERVICO = '$ProcessName' 
    AND Z111_DATA >= '$DateFilter'
ORDER BY Z111_DATA DESC, Z111_HORA DESC
"@
                
                $MemoryData = Invoke-SQLQuery -Connection $Connection -Query $MemoryQuery
                
                if ($MemoryData.Rows.Count -gt 0) {
                    $MemoryData | Format-Table -AutoSize
                    
                    # Estatísticas (convertendo strings para números)
                    $MemoryValues = $MemoryData | ForEach-Object { [double]$_.Memoria_Usada_MB }
                    $PercentValues = $MemoryData | ForEach-Object { [int]$_.Percentual_Uso }
                    
                    $AvgMemory = ($MemoryValues | Measure-Object -Average).Average
                    $MaxMemory = ($MemoryValues | Measure-Object -Maximum).Maximum
                    $MinMemory = ($MemoryValues | Measure-Object -Minimum).Minimum
                    $AvgPercent = ($PercentValues | Measure-Object -Average).Average
                    
                    Write-Host "`n=== ESTATÍSTICAS ===" -ForegroundColor Cyan
                    Write-Host "Memória Média: $([math]::Round($AvgMemory, 2)) MB"
                    Write-Host "Memória Máxima: $MaxMemory MB"
                    Write-Host "Memória Mínima: $MinMemory MB"
                    Write-Host "Percentual Médio: $([math]::Round($AvgPercent, 1))%"
                } else {
                    Write-Host "Nenhum registro de memória encontrado para o período especificado." -ForegroundColor Yellow
                }
            }
            
            "restart" {
                Write-Host "=== RELATÓRIO DE REINÍCIOS (Últimos $LastDays dias) ===" -ForegroundColor Yellow
                
                $DateFilter = (Get-Date).AddDays(-$LastDays).ToString("yyyyMMdd")
                
                $RestartQuery = @"
SELECT 
    Z112_DATA as Data_Reinicio,
    Z112_HORA as Hora_Reinicio,
    Z112_SERVICO as Servico,
    CASE Z112_TIPO 
        WHEN 'P' THEN 'Programado'
        WHEN 'F' THEN 'Forçado'
        WHEN 'A' THEN 'Atualização'
        ELSE Z112_TIPO
    END as Tipo_Reinicio,
    Z112_AUTOR as Solicitante,
    Z112_MOTIVO as Motivo,
    CASE Z112_SISTEMA
        WHEN 'S' THEN 'Sim'
        WHEN 'N' THEN 'Não'
        ELSE Z112_SISTEMA
    END as Reinicia_Sistema
FROM Z112 
WHERE Z112_SERVICO = '$ProcessName' 
    AND Z112_DATA >= '$DateFilter'
ORDER BY Z112_DATA DESC, Z112_HORA DESC
"@
                
                $RestartData = Invoke-SQLQuery -Connection $Connection -Query $RestartQuery
                
                if ($RestartData.Rows.Count -gt 0) {
                    $RestartData | Format-Table -AutoSize
                    
                    # Estatísticas de reinícios
                    $TotalRestarts = $RestartData.Rows.Count
                    $ProgrammedRestarts = ($RestartData | Where-Object {$_.Tipo_Reinicio -eq "Programado"}).Count
                    $ForcedRestarts = ($RestartData | Where-Object {$_.Tipo_Reinicio -eq "Forçado"}).Count
                    $UpdateRestarts = ($RestartData | Where-Object {$_.Tipo_Reinicio -eq "Atualização"}).Count
                    $SystemRestarts = ($RestartData | Where-Object {$_.Reinicia_Sistema -eq "Sim"}).Count
                    
                    Write-Host "`n=== ESTATÍSTICAS DE REINÍCIOS ===" -ForegroundColor Cyan
                    Write-Host "Total de Reinícios: $TotalRestarts"
                    Write-Host "Reinícios Programados: $ProgrammedRestarts"
                    Write-Host "Reinícios Forçados: $ForcedRestarts"
                    Write-Host "Reinícios por Atualização: $UpdateRestarts"
                    Write-Host "Reinícios de Sistema: $SystemRestarts"
                } else {
                    Write-Host "Nenhum registro de reinício encontrado para o período especificado." -ForegroundColor Yellow
                }
            }
            
            "summary" {
                Write-Host "=== RELATÓRIO RESUMIDO (Últimos $LastDays dias) ===" -ForegroundColor Yellow
                
                $DateFilter = (Get-Date).AddDays(-$LastDays).ToString("yyyyMMdd")
                
                # Resumo de memória
                $MemorySummaryQuery = @"
SELECT 
    AVG(CAST(Z111_USADA as float)) as Memoria_Media,
    MAX(CAST(Z111_USADA as float)) as Memoria_Maxima,
    MIN(CAST(Z111_USADA as float)) as Memoria_Minima,
    AVG(CAST(Z111_PERCENT as int)) as Percentual_Medio,
    COUNT(*) as Total_Registros_Memoria
FROM Z111 
WHERE Z111_SERVICO = '$ProcessName' 
    AND Z111_DATA >= '$DateFilter'
"@
                
                # Resumo de reinícios
                $RestartSummaryQuery = @"
SELECT 
    COUNT(*) as Total_Reiniclos,
    SUM(CASE WHEN Z112_TIPO = 'P' THEN 1 ELSE 0 END) as Reiniclos_Programados,
    SUM(CASE WHEN Z112_TIPO = 'F' THEN 1 ELSE 0 END) as Reiniclos_Forcados,
    SUM(CASE WHEN Z112_TIPO = 'A' THEN 1 ELSE 0 END) as Reiniclos_Atualizacao,
    SUM(CASE WHEN Z112_SISTEMA = 'S' THEN 1 ELSE 0 END) as Reiniclos_Sistema
FROM Z112 
WHERE Z112_SERVICO = '$ProcessName' 
    AND Z112_DATA >= '$DateFilter'
"@
                
                $MemorySummary = Invoke-SQLQuery -Connection $Connection -Query $MemorySummaryQuery
                $RestartSummary = Invoke-SQLQuery -Connection $Connection -Query $RestartSummaryQuery
                
                Write-Host "`n--- Resumo de Memória ---" -ForegroundColor Cyan
                if ($MemorySummary.Rows.Count -gt 0 -and $MemorySummary.Rows[0]["Total_Registros_Memoria"] -gt 0) {
                    $MemorySummary | Format-Table -AutoSize
                } else {
                    Write-Host "Nenhum dado de memória disponível."
                }
                
                Write-Host "`n--- Resumo de Reinícios ---" -ForegroundColor Cyan
                if ($RestartSummary.Rows.Count -gt 0 -and $RestartSummary.Rows[0]["Total_Reiniclos"] -gt 0) {
                    $RestartSummary | Format-Table -AutoSize
                } else {
                    Write-Host "Nenhum dado de reinício disponível."
                }
            }
            
            default {
                Write-Host "Tipo de relatório inválido. Use: memory, restart ou summary" -ForegroundColor Red
            }
        }
        
        # Fecha a conexão
        Close-SQLConnection -Connection $Connection
    }
}
catch {
    Write-Error "Erro ao gerar relatório: $_"
}
finally {
    # Limpa a senha da memória
    if ($PasswordPlainText) {
        $PasswordPlainText = ""
    }
}

# Exemplos de uso:
# .\queryDatabaseReports.ps1 -ReportType "memory" -ProcessName "httpd" -LastDays 7
# .\queryDatabaseReports.ps1 -ReportType "restart" -ProcessName "httpd" -LastDays 30
# .\queryDatabaseReports.ps1 -ReportType "summary" -ProcessName "httpd" -LastDays 15

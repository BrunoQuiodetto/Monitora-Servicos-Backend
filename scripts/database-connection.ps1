# Script de conexão com banco de dados SQL Server usando ADO.NET
# Sem dependência dos módulos SqlServer ou Invoke-SqlCmd

param (
    [string]$ServerInstance,
    [string]$Database,
    [string]$Username,
    [string]$Password,
    [string]$IntegratedSecurity = "False"
)

# Função para criar conexão com SQL Server
function New-SQLConnection {
    param (
        [string]$ServerInstance,
        [string]$Database,
        [string]$Username = "",
        [string]$Password = "",
        [string]$IntegratedSecurity = "False"
    )
    
    try {
        # Monta a string de conexão
        if ($IntegratedSecurity -eq "True") {
            $ConnectionString = "Server=$ServerInstance;Database=$Database;Integrated Security=True;Connection Timeout=30;"
        } else {
            $ConnectionString = "Server=$ServerInstance;Database=$Database;User ID=$Username;Password=$Password;Connection Timeout=30;"
        }
        
        # Cria a conexão
        $Connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $Connection.Open()
        
        Write-Host "Conexão estabelecida com sucesso!" -ForegroundColor Green
        return $Connection
    }
    catch {
        Write-Error "Erro ao conectar com o banco de dados: $_"
        return $null
    }
}

# Função para executar consulta SQL (SELECT)
function Invoke-SQLQuery {
    param (
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$Query
    )
    
    try {
        $Command = New-Object System.Data.SqlClient.SqlCommand($Query, $Connection)
        $DataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($Command)
        $DataTable = New-Object System.Data.DataTable
        $DataAdapter.Fill($DataTable) | Out-Null
        
        return $DataTable
    }
    catch {
        Write-Error "Erro ao executar consulta: $_"
        return $null
    }
}

# Função para executar comando SQL (INSERT, UPDATE, DELETE)
function Invoke-SQLCommand {
    param (
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$Query
    )
    
    try {
        $Command = New-Object System.Data.SqlClient.SqlCommand($Query, $Connection)
        $RowsAffected = $Command.ExecuteNonQuery()
        
        Write-Host "Comando executado com sucesso. Linhas afetadas: $RowsAffected" -ForegroundColor Green
        return $RowsAffected
    }
    catch {
        Write-Error "Erro ao executar comando: $_"
        return -1
    }
}

# Função para fechar conexão
function Close-SQLConnection {
    param (
        [System.Data.SqlClient.SqlConnection]$Connection
    )
    
    if ($Connection -and $Connection.State -eq 'Open') {
        $Connection.Close()
        Write-Host "Conexão fechada com sucesso!" -ForegroundColor Yellow
    }
}

# Exporta as funções para uso em outros scripts
# Export-ModuleMember -Function New-SQLConnection, Invoke-SQLQuery, Invoke-SQLCommand, Close-SQLConnection

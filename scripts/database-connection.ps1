# Script de conexão com banco de dados SQL Server usando ADO.NET
# Sem dependência dos módulos SqlServer ou Invoke-SqlCmd

param (
    [string]$ServerInstance,
    [string]$Database,
    [string]$Username,
    [string]$Password,
    [string]$IntegratedSecurity = "False"
)

# Funções para conexão e operações com banco de dados SQL Server
# Arquivo: database-connection.ps1
# Utiliza ADO.NET nativo do PowerShell, sem dependências externas

<#
.SYNOPSIS
    Cria uma nova conexão com banco de dados SQL Server

.DESCRIPTION
    Estabelece conexão com SQL Server usando ADO.NET nativo do PowerShell.
    Suporta autenticação Windows (Integrated Security) ou SQL Server.
    Inclui timeout de conexão configurável e tratamento de erros robusto.

.PARAMETER ServerInstance
    Nome ou endereço do servidor SQL Server (ex: "localhost", "server\instance", "server,port")

.PARAMETER Database
    Nome do banco de dados para conectar

.PARAMETER Username
    Nome de usuário para autenticação SQL Server (ignorado se IntegratedSecurity = True)

.PARAMETER Password
    Senha para autenticação SQL Server (ignorado se IntegratedSecurity = True)

.PARAMETER IntegratedSecurity
    Se "True", usa autenticação Windows. Se "False", usa autenticação SQL Server (padrão: "False")

.OUTPUTS
    System.Data.SqlClient.SqlConnection
    Retorna objeto de conexão ativo ou $null em caso de erro

.EXAMPLE
    $conn = New-SQLConnection -ServerInstance "localhost" -Database "MyDB" -Username "user" -Password "pass"
    
.EXAMPLE
    $conn = New-SQLConnection -ServerInstance "SERVER\INSTANCE" -Database "MyDB" -IntegratedSecurity "True"

.NOTES
    A conexão deve ser fechada manualmente usando Close-SQLConnection quando não precisar mais
#>
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

<#
.SYNOPSIS
    Executa uma consulta SQL de seleção (SELECT)

.DESCRIPTION
    Executa uma consulta SELECT no banco de dados e retorna os resultados em um DataTable.
    Ideal para consultas que retornam dados. Para comandos que modificam dados, use Invoke-SQLCommand.

.PARAMETER Connection
    Objeto de conexão SQL Server ativo criado com New-SQLConnection

.PARAMETER Query
    Comando SQL SELECT a ser executado

.OUTPUTS
    System.Data.DataTable
    Retorna DataTable com os resultados da consulta ou $null em caso de erro

.EXAMPLE
    $result = Invoke-SQLQuery -Connection $conn -Query "SELECT * FROM Users WHERE Active = 1"
    foreach ($row in $result.Rows) {
        Write-Host "User: $($row.Name)"
    }

.EXAMPLE
    $data = Invoke-SQLQuery -Connection $conn -Query "SELECT COUNT(*) as Total FROM Orders"
    $total = $data.Rows[0].Total

.NOTES
    A conexão deve estar aberta antes de executar a consulta
#>
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

<#
.SYNOPSIS
    Executa comandos SQL que modificam dados (INSERT, UPDATE, DELETE)

.DESCRIPTION
    Executa comandos SQL que não retornam dados (INSERT, UPDATE, DELETE, CREATE, etc.).
    Retorna o número de linhas afetadas pela operação.

.PARAMETER Connection
    Objeto de conexão SQL Server ativo criado com New-SQLConnection

.PARAMETER Query
    Comando SQL a ser executado (INSERT, UPDATE, DELETE, etc.)

.OUTPUTS
    System.Collections.Hashtable
    Retorna hashtable com: Success (bool), RowsAffected (int), Query (string), Error (string)

.EXAMPLE
    $result = Invoke-SQLCommand -Connection $conn -Query "INSERT INTO Users (Name, Email) VALUES ('João', 'joao@email.com')"
    if ($result.Success -and $result.RowsAffected -gt 0) { Write-Host "Usuário criado com sucesso!" }

.EXAMPLE
    $result = Invoke-SQLCommand -Connection $conn -Query "UPDATE Products SET Price = Price * 1.1 WHERE Category = 'Electronics'"
    if ($result.Success) { Write-Host "Preços atualizados para $($result.RowsAffected) produtos" }

.NOTES
    Use esta função para comandos que modificam dados. Para consultas SELECT, use Invoke-SQLQuery
#>
# Função para executar comando SQL (INSERT, UPDATE, DELETE)
function Invoke-SQLCommand {
    param (
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$Query
    )
    
    try {
        $Command = New-Object System.Data.SqlClient.SqlCommand($Query, $Connection)
        $RowsAffected = $Command.ExecuteNonQuery()
        
        # Retorna objeto com informações detalhadas
        return @{
            Success = $true
            RowsAffected = $RowsAffected
            Query = $Query
            Error = $null
        }
    }
    catch {
        # Retorna objeto com erro detalhado
        return @{
            Success = $false
            RowsAffected = -1
            Query = $Query
            Error = $_.Exception.Message
            SqlState = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $null }
        }
    }
}

<#
.SYNOPSIS
    Fecha a conexão com o banco de dados SQL Server

.DESCRIPTION
    Fecha uma conexão ativa com SQL Server de forma segura.
    Verifica se a conexão existe e está aberta antes de tentar fechar.

.PARAMETER Connection
    Objeto de conexão SQL Server a ser fechado

.EXAMPLE
    Close-SQLConnection -Connection $conn

.NOTES
    Sempre feche as conexões quando não precisar mais para liberar recursos do servidor
    É uma boa prática fechar conexões em blocos try/finally ou using statements
#>
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

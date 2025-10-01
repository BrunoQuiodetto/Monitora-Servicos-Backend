# Script para criação da estrutura de banco de dados do sistema de monitoramento
# Arquivo: createDatabaseStructure.ps1
# Cria as tabelas Z111020 (memória) e Z112020 (reinicializações) 

<#
.SYNOPSIS
    Cria a estrutura de banco de dados necessária para o sistema de monitoramento

.DESCRIPTION
    Script de inicialização que cria as tabelas necessárias para armazenar dados
    de monitoramento no banco de dados SQL Server. Deve ser executado uma única vez
    durante a configuração inicial do sistema.

    Tabelas criadas:
    - Z111020: Dados de monitoramento de memória por processo
    - Z112020: Registro de reinicializações de serviços

.PARAMETER ServerInstance
    Instância do SQL Server onde criar as tabelas (opcional, usa config se não fornecido)

.PARAMETER Database
    Nome do banco de dados de destino (opcional, usa config se não fornecido)

.PARAMETER Username
    Usuário do banco com permissões de DDL (opcional, usa config se não fornecido)

.PARAMETER Password
    Senha do banco como SecureString (opcional, usa config se não fornecido)

.PARAMETER IntegratedSecurity
    Usar autenticação Windows (padrão: "True")

.EXAMPLE
    .\createDatabaseStructure.ps1

.EXAMPLE
    .\createDatabaseStructure.ps1 -ServerInstance "SERVER\INSTANCE" -Database "MonitoringDB"

.EXAMPLE
    $secPass = ConvertTo-SecureString "password" -AsPlainText -Force
    .\createDatabaseStructure.ps1 -Username "dbuser" -Password $secPass -IntegratedSecurity "False"

.NOTES
    - Execute apenas uma vez durante a configuração inicial
    - Requer permissões de CREATE TABLE no banco de dados
    - Usa arquivo de configuração config.psd1 para parâmetros padrão
    - Verifica se as tabelas já existem antes de criá-las
    - Cria índices otimizados para consultas de relatórios
#>

# Script para criar as tabelas Z111 e Z112 no banco de dados
# Execute este script uma vez para criar as estruturas necessárias

param (
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
        Write-Host "Criando tabelas de monitoramento..." -ForegroundColor Yellow
        
        # Script para criar tabela Z111 (Informações de Memória)
        $CreateZ111 = @"
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Z111020' AND xtype='U')
BEGIN
    CREATE TABLE Z111020 (
        Z111_DATA varchar(8) NOT NULL,      -- Data registro (YYYYMMDD)
        Z111_HORA varchar(5) NOT NULL,      -- Hora registro (HH:MM)
        Z111_USADA varchar(100) NOT NULL,   -- Memoria utilizada
        Z111_DISPO varchar(100) NOT NULL,   -- Memoria disponivel
        Z111_RAZAO varchar(7) NOT NULL,     -- Razao da atualizacao
        Z111_PERCENT varchar(3) NOT NULL,   -- Percentual de memoria utilizada x disponivel
        Z111_SERVICO varchar(100) NOT NULL, -- Servico monitorado
        D_E_L_E_T_ varchar(1) DEFAULT '' NOT NULL -- Campo padrao sistema
    )
    
    -- Índices para melhor performance
    CREATE INDEX IX_Z111020_DATA_HORA ON Z111020(Z111_DATA, Z111_HORA)
    CREATE INDEX IX_Z111020_SERVICO ON Z111020(Z111_SERVICO)
    CREATE INDEX IX_Z111020_DATA ON Z111020(Z111_DATA)
    
    PRINT 'Tabela Z111 criada com sucesso!'
END
ELSE
BEGIN
    PRINT 'Tabela Z111 já existe!'
END
"@

        # Script para criar tabela Z112 (Informações de Reinício)
        $CreateZ112 = @"
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Z112020' AND xtype='U')
BEGIN
    CREATE TABLE Z112020 (
        Z112_DATA varchar(8) NOT NULL,      -- Data reinicio (YYYYMMDD)
        Z112_HORA varchar(5) NOT NULL,      -- Hora reinicio (HH:MM)
        Z112_TIPO varchar(1) NOT NULL,      -- Tipo reinicio: P=PROGRAMADO,F=FORCADO,A=ATUALIZACAO
        Z112_AUTOR varchar(100) NOT NULL,   -- Autor reinicio
        Z112_MOTIVO varchar(500) NOT NULL,  -- Motivo reinicio
        Z112_SISTEMA varchar(1) NOT NULL,   -- Reinicia sistema?: S=SIM,N=NAO
        Z112_SERVICO varchar(100) NOT NULL  -- Servico correspondente
    )
    
    -- Índices para melhor performance
    CREATE INDEX IX_Z112_DATA_HORA ON Z112(Z112_DATA, Z112_HORA)
    CREATE INDEX IX_Z112_SERVICO ON Z112(Z112_SERVICO)
    CREATE INDEX IX_Z112_TIPO ON Z112(Z112_TIPO)
    CREATE INDEX IX_Z112_AUTOR ON Z112(Z112_AUTOR)
    CREATE INDEX IX_Z112_DATA ON Z112(Z112_DATA)
    
    PRINT 'Tabela Z112 criada com sucesso!'
END
ELSE
BEGIN
    PRINT 'Tabela Z112 já existe!'
END
"@

        # Executa os comandos de criação
        Write-Host "Criando tabela Z111020 (Informações de Memória)..." -ForegroundColor Cyan
        $Result1 = Invoke-SQLCommand -Connection $Connection -Query $CreateZ111
        if (-not $Result1.Success) {
            Write-Error "Erro ao criar tabela Z111020: $($Result1.Error)"
        }
        
        Write-Host "Criando tabela Z112020 (Informações de Reinício)..." -ForegroundColor Cyan
        $Result2 = Invoke-SQLCommand -Connection $Connection -Query $CreateZ112
        if (-not $Result2.Success) {
            Write-Error "Erro ao criar tabela Z112020: $($Result2.Error)"
        }
        
        Write-Host "Estrutura do banco criada com sucesso!" -ForegroundColor Green
        
        # Fecha a conexão
        Close-SQLConnection -Connection $Connection
    }
}
catch {
    Write-Error "Erro ao criar estrutura do banco: $_"
}
finally {
    # Limpa a senha da memória
    if ($PasswordPlainText) {
        $PasswordPlainText = ""
    }
}

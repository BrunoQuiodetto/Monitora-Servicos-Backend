# Funções auxiliares para gerenciamento de logs
# Arquivo: log-functions.ps1

<#
.SYNOPSIS
    Rotaciona o arquivo de log quando ele fica muito grande

.DESCRIPTION
    Verifica o tamanho do arquivo de log e, se for maior que o limite configurado,
    move o arquivo atual para um backup com timestamp e cria um novo arquivo limpo.
    Mantém apenas um número limitado de backups para economizar espaço.

.PARAMETER LogFilePath
    Caminho completo para o arquivo de log a ser verificado

.PARAMETER MaxSizeMB
    Tamanho máximo em MB antes de rotacionar (padrão: 10MB)

.PARAMETER MaxBackups
    Número máximo de backups a manter (padrão: 5)

.EXAMPLE
    Start-LogRotation -LogFilePath "C:\logs\app.log"
    
.EXAMPLE
    Start-LogRotation -LogFilePath "C:\logs\app.log" -MaxSizeMB 20 -MaxBackups 10
#>
function Start-LogRotation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogFilePath,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxSizeMB = 10,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxBackups = 5
    )
    
    try {
        if (Test-Path $LogFilePath) {
            $LogInfo = Get-Item $LogFilePath
            $MaxSizeBytes = $MaxSizeMB * 1MB
            
            # Verificar se precisa rotacionar
            if ($LogInfo.Length -gt $MaxSizeBytes) {
                $BackupPath = $LogFilePath -replace "\.txt$", "_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                
                # Mover arquivo atual para backup
                Move-Item -Path $LogFilePath -Destination $BackupPath -Force
                
                # Criar novo arquivo de log com mensagem inicial
                $InitialMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Log rotacionado. Backup criado: $(Split-Path -Leaf $BackupPath)"
                $InitialMessage | Out-File -FilePath $LogFilePath -Encoding UTF8
                
                # Limpar backups antigos
                Remove-OldLogBackups -LogDirectory (Split-Path $LogFilePath) -MaxBackups $MaxBackups
                
                Write-Host "Log rotacionado: $LogFilePath -> $BackupPath" -ForegroundColor Green
            }
        }
    }
    catch {
        # Em caso de erro, apenas continua - não deve interromper o funcionamento principal
        Write-Warning "Erro ao rotacionar log: $_"
    }
}

<#
.SYNOPSIS
    Remove backups antigos de log para economizar espaço

.DESCRIPTION
    Identifica arquivos de backup de log pelo padrão de nome e remove os mais antigos,
    mantendo apenas o número especificado de backups mais recentes.

.PARAMETER LogDirectory
    Diretório onde estão os arquivos de log e backups

.PARAMETER MaxBackups
    Número máximo de backups a manter

.EXAMPLE
    Remove-OldLogBackups -LogDirectory "C:\logs" -MaxBackups 5
#>
function Remove-OldLogBackups {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogDirectory,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxBackups = 5
    )
    
    try {
        # Buscar arquivos de backup (padrão: *_YYYYMMDD_HHMMSS.txt)
        $BackupFiles = Get-ChildItem -Path $LogDirectory -Filter "*.txt" | 
                      Where-Object { $_.Name -match "_\d{8}_\d{6}\.txt$" } | 
                      Sort-Object LastWriteTime -Descending
        
        # Remover backups excedentes
        if ($BackupFiles.Count -gt $MaxBackups) {
            $FilesToRemove = $BackupFiles[$MaxBackups..($BackupFiles.Count-1)]
            
            foreach ($File in $FilesToRemove) {
                try {
                    Remove-Item -Path $File.FullName -Force
                    Write-Host "Backup antigo removido: $($File.Name)" -ForegroundColor Yellow
                }
                catch {
                    Write-Warning "Erro ao remover backup $($File.Name): $_"
                }
            }
        }
    }
    catch {
        Write-Warning "Erro ao limpar backups antigos: $_"
    }
}

<#
.SYNOPSIS
    Adiciona uma entrada ao log com timestamp automático

.DESCRIPTION
    Função auxiliar que adiciona uma linha ao arquivo de log com timestamp formatado,
    verificando se precisa rotacionar o log antes da escrita.

.PARAMETER LogFilePath
    Caminho para o arquivo de log

.PARAMETER Message
    Mensagem a ser logada

.PARAMETER Level
    Nível do log (INFO, WARNING, ERROR, DEBUG)

.EXAMPLE
    Write-Log -LogFilePath "C:\logs\app.log" -Message "Aplicação iniciada"
    
.EXAMPLE
    Write-Log -LogFilePath "C:\logs\app.log" -Message "Erro na conexão" -Level "ERROR"
#>
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogFilePath,
        
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    try {
        # Verificar se precisa rotacionar antes de escrever
        Start-LogRotation -LogFilePath $LogFilePath
        
        # Formatar mensagem com timestamp e nível
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $LogEntry = "$Timestamp - [$Level] $Message"
        
        # Adicionar ao arquivo
        Add-Content -Path $LogFilePath -Value $LogEntry -Encoding UTF8
    }
    catch {
        Write-Warning "Erro ao escrever no log: $_"
        # Fallback: tentar escrever diretamente
        try {
            $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "$Timestamp - [$Level] $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
        }
        catch {
            Write-Error "Falha crítica ao escrever no log: $_"
        }
    }
}

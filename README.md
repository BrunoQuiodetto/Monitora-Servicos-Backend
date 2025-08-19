# 🔍 Service Monitor - Sistema de Monitoramento de Memória

![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)
![Apache](https://img.shields.io/badge/Apache-D22128?style=flat&logo=apache&logoColor=white)
![SQL Server](https://img.shields.io/badge/SQL%20Server-CC2927?style=flat&logo=microsoft-sql-server&logoColor=white)

Um sistema completo de monitoramento em tempo real do consumo de memória do Apache HTTP Server (httpd), desenvolvido em PowerShell para ambientes Windows.

## 📋 Funcionalidades

- **Monitoramento Contínuo**: Verifica o consumo de memória do processo Apache em tempo real
- **Alertas Inteligentes**: Sistema de notificações por e-mail com thresholds configuráveis
- **Reinício Automático**: Capacidade de reiniciar o serviço Apache quando necessário
- **Registro de Logs**: Histórico completo de eventos e ações do sistema
- **Integração com Banco de Dados**: Armazenamento de métricas no SQL Server
- **Templates HTML**: E-mails personalizados com design profissional
- **Relatórios**: Consultas e relatórios de performance do sistema

## 📋 Pré-requisitos

- Windows Server 2008 R2 ou superior / Windows 7 ou superior
- PowerShell 2.0 ou superior
- Apache HTTP Server (httpd)
- Task Scheduler (incluído no Windows)
- SQL Server (opcional, para relatórios)
- Servidor SMTP configurado

## 🏗️ Estrutura do Projeto

```
monitoraApache/
├── conf/                          # Configurações
│   ├── config.psd1               # Configurações principais
│   ├── senha.txt                 # Senha de e-mail (criptografada)
│   └── senhadb.txt              # Senha do banco de dados
├── log/                          # Logs do sistema
│   └── apacheMonitor_log.txt    # Log principal
├── scripts/                      # Scripts PowerShell
│   ├── verificaMemoria.ps1      # Script principal de monitoramento
│   ├── reiniciaApache.ps1       # Script de reinício do Apache
│   ├── database-connection.ps1  # Conexão com banco de dados
│   ├── insertMemoryData.ps1     # Inserção de dados de memória
│   ├── insertRestartData.ps1    # Inserção de dados de reinício
│   ├── queryDatabaseReports.ps1 # Relatórios do banco
│   ├── createDatabaseStructure.ps1 # Criação da estrutura do BD
│   └── atualizaMonitoramento.ps1   # Atualizações do sistema
├── src/                          # Recursos
│   └── logo.png           # Logo para e-mails
└── templates/                    # Templates de e-mail
    ├── emailMonitor_alerts.html
    ├── emailMonitor_restart.html
    ├── emailMonitor_restartForce.html
    ├── emailMonitor_restartProgram.html
    └── emailMonitor_start.html
```

### 🚨 Considerações Importantes

### Execução Contínua
- O script `verificaMemoria.ps1` foi projetado para executar em **loop infinito**
- Ele só para quando o processo é interrompido manualmente ou o sistema é reiniciado
- **Não configure múltiplas execuções** da mesma tarefa simultaneamente

### Monitoramento de Performance
- O script consome recursos mínimos do sistema
- Verificações ocorrem em intervalos regulares (configurável no código)
- Logs são rotacionados automaticamente para evitar crescimento excessivo

## 📊 Funcionalidades Detalhadas

### Sistema de Alertas

O sistema utiliza um algoritmo inteligente de thresholds:

- **Threshold Dinâmico**: Aumenta automaticamente quando o consumo ultrapassa o limite
- **Ajuste Automático**: Reduz o threshold após 1 hora sem ultrapassar o limite
- **Notificações Escalonadas**: Evita spam de e-mails com lógica de intervalo

### Métricas Coletadas

- Consumo de memória do processo Apache (MB)
- Porcentagem de uso de memória
- Memória total disponível no sistema
- Memória disponível para a aplicação
- Timestamps de eventos

### Templates de E-mail

O sistema inclui templates HTML personalizados para diferentes tipos de notificação:

- **Início**: Notificação de início do monitoramento
- **Alertas**: Avisos de alto consumo de memória
- **Reinício**: Confirmação de reinício do serviço
- **Reinício Forçado**: Notificação de reinício manual

## ⚙️ Configuração

### 1. Configuração Inicial

Edite o arquivo `conf/config.psd1` com suas configurações:

```powershell
@{
    SMTPServer      = 'seu.servidor.smtp.com'
    SMTPPort        = 587
    EmailSender     = 'monitor@suaempresa.com'
    EmailRecipients = @(
        'admin@suaempresa.com',
        'ti@suaempresa.com'
    )
    LogFile         = '..\log\apacheMonitor_log.txt'
    SenhaPath       = '..\conf\senha.txt'
    EmailAlias      = 'sistema@suaempresa.com'
    EmailAliasName  = 'Sistema de Monitoramento'
    
    # Configurações do Banco de Dados
    DatabaseServer      = '192.168.1.100'
    DatabaseName        = 'MonitoringDB'
    DatabaseUser        = 'monitor_user'
    DatabasePasswordPath = '..\conf\senhadb.txt'
}
```

### 2. Configuração de Senhas

Crie os arquivos de senha:
- `conf/senha.txt` - Senha do e-mail (texto simples ou criptografada)
- `conf/senhadb.txt` - Senha do banco de dados

### 3. Estrutura do Banco de Dados

Execute o script para criar as tabelas necessárias:

```powershell
.\scripts\createDatabaseStructure.ps1
```

## 🚀 Uso

### Configuração no Task Scheduler (Recomendado)

O sistema foi projetado para executar continuamente através do Task Scheduler do Windows:

#### 1.1. Criação da Tarefa no Task Scheduler

**Via Interface Gráfica:**

1. Abra o **Task Scheduler** (`taskschd.msc`)
2. Clique em **"Create Task..."** (Criar Tarefa...)
3. Configure as abas conforme abaixo:

**Aba General:**
- Name: `Apache Memory Monitor`
- Description: `Monitoramento contínuo de memória do Apache HTTP Server`
- ✅ Run whether user is logged on or not
- ✅ Run with highest privileges
- Configure for: `Windows 7, Windows Server 2008 R2` (ou superior)

**Aba Triggers:**
- Click **New...**
- Begin the task: `At startup`
- ✅ Enabled

**Aba Actions:**
- Click **New...**
- Action: `Start a program`
- Program/script: `powershell.exe`
- Add arguments: `-ExecutionPolicy Bypass -File "U:\monitoraApache\scripts\verificaMemoria.ps1"`
- Start in: `U:\monitoraApache\scripts`

**Aba Conditions:**
- ❌ Start the task only if the computer is on AC power
- ❌ Stop if the computer switches to battery power
- ✅ Wake the computer to run this task

**Aba Settings:**
- ✅ Allow task to be run on demand
- ❌ Run task as soon as possible after a scheduled start is missed
- ❌ If the task fails, restart every: (deixar desmarcado)
- ❌ Stop the task if it runs longer than: (deixar desmarcado)
- If the running task does not end when requested: `Do not start a new instance`

#### 1.2. Criação via PowerShell (Método Alternativo)

```powershell
# Criar tarefa programada via PowerShell
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File 'U:\monitoraApache\scripts\verificaMemoria.ps1'" -WorkingDirectory "U:\monitoraApache\scripts"

$Trigger = New-ScheduledTaskTrigger -AtStartup

$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Days 365)

$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "Apache Memory Monitor" -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "Monitoramento contínuo de memória do Apache HTTP Server"
```

#### 2. Verificação da Tarefa

```powershell
# Verificar se a tarefa foi criada
Get-ScheduledTask -TaskName "Apache Memory Monitor"

# Executar a tarefa manualmente para teste
Start-ScheduledTask -TaskName "Apache Memory Monitor"

# Verificar status da tarefa
Get-ScheduledTask -TaskName "Apache Memory Monitor" | Get-ScheduledTaskInfo
```

### Reinício Manual do Apache

```powershell
# Reinício forçado
.\scripts\reiniciaApache.ps1 -NomeUsuario "Admin" -Motivo "Manutenção programada"

# Teste (sem executar ação)
.\scripts\reiniciaApache.ps1 -NomeUsuario "Admin" -Motivo "Teste" -TipoReinicio "Teste"
```

### Consulta de Relatórios

```powershell
# Gerar relatórios do banco de dados
.\scripts\queryDatabaseReports.ps1
```

### Monitoramento Manual (Para Testes)

```powershell
# Executar com configurações padrão
.\scripts\verificaMemoria.ps1

# Executar com threshold personalizado (em MB)
.\scripts\verificaMemoria.ps1 -ThresholdStep 1000

# Monitorar processo específico
.\scripts\verificaMemoria.ps1 -ProcessName "apache" -ThresholdStep 500
```

## 🔧 Parâmetros de Configuração

### verificaMemoria.ps1

| Parâmetro       | Tipo   | Padrão  | Descrição                    |
| --------------- | ------ | ------- | ---------------------------- |
| `ProcessName`   | string | "httpd" | Nome do processo a monitorar |
| `ThresholdStep` | int    | 500     | Incremento do threshold (MB) |

### reiniciaApache.ps1

| Parâmetro      | Tipo   | Obrigatório | Padrão    | Descrição                               |
| -------------- | ------ | ----------- | --------- | --------------------------------------- |
| `NomeUsuario`  | string | Sim         |           | Nome do usuário que solicita o reinício |
| `Motivo`       | string | Sim         |           | Motivo do reinício                      |
| `TipoReinicio` | string | Não         | "Forçado" | "Forçado", "Programado" ou "Teste"      |
| `ProcessName`  | string | Não         | "httpd"   | Nome do processo a monitorar            |

## ️🛡️ Segurança

- Senhas armazenadas em arquivos separados (incluídos no .gitignore)
- Configurações sensíveis não versionadas
- Conexões de banco de dados com autenticação
- Logs de auditoria completos

## 📈 Integração com Banco de Dados

O sistema integra com SQL Server para:

- Armazenar histórico de métricas de memória
- Registrar eventos de reinício
- Gerar relatórios de performance
- Análise de tendências

## 📝 Logs

Os logs são gravados em `log/apacheMonitor_log.txt` com formato:

```
2025-08-19 14:30:00 - httpd consumindo 1250.50 MB. NextNotificationLevel: 1500. LastNotifiedLevel: 1000. NotificationReason: upper
2025-08-19 14:31:00 - Notificação de alerta enviada para admin@empresa.com
2025-08-19 14:32:00 - Reinício solicitado por Admin. Motivo: Alto consumo de memória
```

## 🎢 Escalabilidade

Embora este sistema tenha sido **desenvolvido inicialmente para monitoramento do Apache HTTP Server**, sua arquitetura é **totalmente escalável** para monitorar qualquer tipo de serviço ou processo Windows:

### Adaptações Possíveis:
- **Serviços Web**: IIS, Nginx, Tomcat, Node.js
- **Bancos de Dados**: SQL Server, MySQL, PostgreSQL, Oracle
- **Aplicações**: Java, .NET, Python, aplicações customizadas
- **Serviços do Sistema**: Qualquer processo Windows

### Personalização:
- Altere o parâmetro `ProcessName` para o processo desejado
- Adapte os thresholds conforme a natureza do serviço
- Customize os templates de e-mail para o contexto específico
- Modifique as métricas coletadas conforme necessário

## 📄 Licença e Uso

**Licença de Uso Restrita - Somente Visualização e Execução**

### ✅ **PERMITIDO:**
- Visualizar e estudar o código fonte
- Executar o sistema em ambiente próprio
- Usar para fins educacionais e de aprendizado
- Realizar monitoramento em ambiente corporativo

### ❌ **NÃO PERMITIDO:**
- Modificar, editar ou alterar qualquer parte do código
- Redistribuir o código (modificado ou não)
- Criar trabalhos derivados
- Usar para fins comerciais de redistribuição
- Remover ou alterar avisos de copyright

### 📋 **CONDIÇÕES:**
- O código deve ser usado "como está" (AS IS)
- Nenhuma garantia é fornecida quanto ao funcionamento
- O autor não se responsabiliza por danos ou perdas
- Créditos ao autor original devem ser mantidos

**Copyright © 2025 - Todos os direitos reservados**

📄 **Para termos completos, consulte o arquivo [LICENSE](LICENSE)**

## 🆘 Suporte e Troubleshooting

### Problemas Comuns

**1. Tarefa não inicia automaticamente:**
- Verifique se a tarefa está habilitada no Task Scheduler
- Confirme se o usuário tem privilégios para executar como serviço
- Verifique a política de execução do PowerShell

**2. E-mails não são enviados:**
- Teste a conectividade SMTP: `Test-NetConnection -ComputerName "servidor.smtp.com" -Port 587`
- Verifique as credenciais nos arquivos `senha.txt`
- Confirme as configurações no `config.psd1`

**3. Processo Apache não encontrado:**
- Verifique se o nome do processo está correto (padrão: "httpd")
- Confirme se o Apache está em execução: `Get-Process -Name httpd`

### Logs e Diagnóstico

- **Logs do sistema**: `log/apacheMonitor_log.txt`
- **Logs do Task Scheduler**: Event Viewer → Windows Logs → System
- **Logs de aplicação**: Event Viewer → Applications and Services Logs

### Contato

Para suporte e dúvidas:
- Abra uma issue no GitHub
- Conecte-se através do [Linkedin](https://www.linkedin.com/in/brunoquiodetto/)
## � Administração e Manutenção

### Política de Execução
Se houver erros de política de execução, configure:

```powershell
# Configurar política de execução (executar como Administrador)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine

# Ou usar bypass na tarefa (já incluído nos exemplos acima)
```

### Gerenciar a Tarefa do Task Scheduler

```powershell
# Parar o monitoramento
Stop-ScheduledTask -TaskName "Apache Memory Monitor"

# Iniciar o monitoramento
Start-ScheduledTask -TaskName "Apache Memory Monitor"

# Desabilitar temporariamente
Disable-ScheduledTask -TaskName "Apache Memory Monitor"

# Reabilitar
Enable-ScheduledTask -TaskName "Apache Memory Monitor"

# Remover a tarefa (se necessário)
Unregister-ScheduledTask -TaskName "Apache Memory Monitor" -Confirm:$false
```

### Logs e Troubleshooting

```powershell
# Verificar logs do Task Scheduler
Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" | Where-Object {$_.Message -like "*Apache Memory Monitor*"} | Select-Object -First 10

# Verificar logs do sistema
Get-Content "U:\monitoraApache\log\apacheMonitor_log.txt" -Tail 20

# Testar conectividade SMTP
Test-NetConnection -ComputerName "seu.servidor.smtp.com" -Port 587
```

### Atualizações

Para atualizar o sistema de maneira padrão quando houver alguma modificação no script :

| Parâmetro      | Tipo   | Obrigatório | Padrão            | Descrição                                                               |
| -------------- | ------ | ----------- | ----------------- | ----------------------------------------------------------------------- |
| `NomeUsuario`  | string | Sim         |                   | Nome do usuário que solicita o reinício do serviço                      |
| `Motivo`       | string | Sim         |                   | O que foi modificado na atualização                                     |
| `$ProcessName` | string | Não         | "\MonitoraApache" | Nome que foi definido na [criação do serviço](#1-configuração-inicial) |

```powershell
.\scripts\atualizaMonitoramento.ps1 -
```
---

**Desenvolvido para monitoramento robusto e confiável do Apache HTTP Server em ambientes Windows.**

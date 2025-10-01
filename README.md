# 🔍 Service Monitor - Sistema de Monitoramento de Memória

[![PowerShell](https://img.shields.io/badge/PowerShell-2.0%2B-blue?style=flat&logo=powershell&logoColor=white)](https://docs.microsoft.com/powershell/)
[![SQL Server](https://img.shields.io/badge/SQL%20Server-CC2927?style=flat&logo=microsoft-sql-server&logoColor=white)](https://www.microsoft.com/pt-br/sql-server/sql-server-downloads)
[![Windows](https://img.shields.io/badge/Windows-7%2B_or_Server_2008%2B-green?logo=windows)](https://www.microsoft.com/windows/)


Um sistema completo de monitoramento em tempo real do consumo de memória de múltiplos processos (Apache, Node.js e outros), desenvolvido em PowerShell para ambientes Windows.

## 📋 Funcionalidades

- **Monitoramento Contínuo**: Verifica o consumo de memória de múltiplos processos simultaneamente em tempo real
- **Múltiplos Serviços**: Suporte nativo para Apache, Node.js e qualquer processo Windows
- **Alertas Inteligentes**: Sistema de notificações por e-mail com thresholds configuráveis por processo
- **Reinicialização Programada**: Reinício automático a cada 2 dias às 3h da manhã
- **Suporte a Serviços Windows**: Pode reiniciar tanto processos quanto serviços Windows
- **Registro de Logs**: Histórico completo de eventos e ações do sistema por processo
- **Integração com Banco de Dados**: Armazenamento de métricas no SQL Server
- **Templates HTML**: E-mails personalizados com design profissional
- **Configuração Flexível**: Lista de processos configurável via arquivo ou parâmetros

## 📋 Pré-requisitos

- Windows Server 2008 ou superior / Windows 7 ou superior
- PowerShell 2.0 ou superior
- Processos a monitorar (Apache HTTP Server, Node.js, etc.)
- Task Scheduler (incluído no Windows)
- SQL Server (opcional, para relatórios)
- Servidor SMTP configurado

## 🏗️ Estrutura do Projeto

```
serviceMonitor/
├── conf/                           # Configurações
│   ├── config.psd1                 # Configurações de funcionamento
│   ├── senha.txt                   # Senha de e-mail
│   └── senhadb.txt                 # Senha do banco de dados
├── log/                            # Logs do sistema
│   └── serviceMonitor_log.txt      # Log principal (múltiplos processos)
├── scripts/                        # Scripts PowerShell
│   ├── verificaMemoria.ps1         # Script de monitoramento
│   ├── reiniciaServico.ps1         # Script de reinício
│   ├── database-connection.ps1     # Conexão com banco de dados
│   ├── insertMemoryData.ps1        # Inserção de dados de memória
│   ├── insertRestartData.ps1       # Inserção de dados de reinício
│   ├── queryDatabaseReports.ps1    # Relatórios do banco
│   ├── createDatabaseStructure.ps1 # Criação da estrutura do BD
│   └── atualizaMonitoramento.ps1   # Atualizações do sistema de monitoramento
├── src/                            # Recursos
│   └── logo.png                    # Logo para e-mails
└── templates/                      # Templates de e-mail
    ├── emailMonitor_alerts.html
    ├── emailMonitor_restart.html
    ├── emailMonitor_restartForce.html
    ├── emailMonitor_restartProgram.html
    └── emailMonitor_start.html
```

### 🚨 Considerações Importantes

### Execução Contínua
- O script `verificaMemoria.ps1` foi projetado para executar em **loop infinito**, por isso, por padrão, em caso de modificação do código de monitoramento, é necessário utilizar o script `atualizaMonitoramento.ps1`
- **Não configure múltiplas execuções** da mesma tarefa simultaneamente

### Monitoramento de Performance
- O script consome recursos mínimos do sistema
- Verificações ocorrem em intervalos regulares (configurável no código)
- Logs são rotacionados automaticamente para evitar crescimento excessivo

## 📊 Funcionalidades Detalhadas

### Sistema de Alertas

O sistema utiliza um algoritmo inteligente de thresholds com novas funcionalidades:

- **Threshold Dinâmico**: Aumenta automaticamente quando o consumo ultrapassa o limite
- **Ajuste Automático**: Reduz o threshold após 1 hora sem ultrapassar o limite
- **Notificações Escalonadas**: Evita spam de e-mails com lógica de intervalo
- **Alertas por Intervalo**: Envia e-mails periódicos mesmo quando não ultrapassa o limite (configurável)
- **Sistema de Cores Inteligente**: 
  - 🔴 **Vermelho** (`upper`): Quando ultrapassa o limite definido
  - 🟡 **Amarelo** (`warning`): Menor que o limite, mas maior que o último valor informado
  - 🟢 **Verde** (`lower`): Menor que o limite e menor que o último valor informado

### Métricas Coletadas

- Consumo de memória individual por processo (MB)
- Porcentagem de uso de memória por processo
- Memória total disponível no sistema
- Timestamps de eventos por processo
- Controle independente de thresholds por processo

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
    LogFile         = '..\log\serviceMonitor_log.txt'
    SenhaPath       = '..\conf\senha.txt'
    EmailAlias      = 'sistema@suaempresa.com'
    EmailAliasName  = 'Sistema de Monitoramento'
    
    # Lista de processos a monitorar (NOVO)
    ProcessesToMonitor = @('httpd', 'node')  # Apache e Node.js
    
    # Configurações de reinicialização automática (NOVO)
    AutoRestartEnabled = $true          # Habilitar reinicialização automática a cada 2 dias
    LastAutoRestart = ''                # Data da última reinicialização automática (YYYY-MM-DD)
    
    # Configurações de notificações por e-mail (NOVO)
    EmailNotificationIntervalHours = 4  # Intervalo em horas para enviar e-mail quando não ultrapassar o limite
    
    # Mapeamento de processos para serviços Windows (NOVO)
    ProcessServiceMap = @{
        'httpd' = 'Apache'     # Nome do serviço Windows para Apache
        'node' =  ''           # Node.js normalmente não é serviço Windows
    }
    
    # Configurações do Banco de Dados
    DatabaseServer      = '192.168.1.100' # Servidor DB
    DatabaseName        = 'MonitoringDB'  # Nome DB
    DatabaseUser        = 'monitor_user'  # Seu usuario DB
    DatabasePasswordPath = '..\conf\senhadb.txt'
}
```

**📌 Configuração de Processos:**
- **Via Config**: Edite `ProcessesToMonitor` no arquivo `config.psd1`
- **Via Parâmetro**: Use `-ProcessNames @('httpd', 'node', 'java')` ao executar o script

- **!Prioridade**: Parâmetros sobrescrevem o arquivo de configuração

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
O sistema foi projetado para executar continuamente através do Task Scheduler do Windows. Consulte o guia de configuração em [Configurar Tasks](ConfigurarTasks). 

#### Verificação da Tarefa

```powershell
# Verificar se a tarefa foi criada
Get-ScheduledTask -TaskName "\MonitoraApache"

# Executar a tarefa manualmente para teste
Start-ScheduledTask -TaskName "\MonitoraApache"

# Verificar status da tarefa
Get-ScheduledTask -TaskName "\MonitoraApache" | Get-ScheduledTaskInfo
```

### Monitoramento Manual (Para Testes)

```powershell
# Executar com configurações do arquivo config.psd1
.\scripts\verificaMemoria.ps1

# Executar monitorando processos específicos
.\scripts\verificaMemoria.ps1 -ProcessNames @("httpd", "node", "java")

# Executar com threshold personalizado
.\scripts\verificaMemoria.ps1 -ThresholdStep 1000

# Executar com processos e threshold customizados
.\scripts\verificaMemoria.ps1 -ProcessNames @("httpd", "node") -ThresholdStep 750
```

### Reinício Manual de Serviços

```powershell
# Reinício forçado do Apache
.\scripts\reiniciaServico.ps1 -ProcessName "httpd" -NomeUsuario "Admin" -Motivo "Manutenção programada"

# Reinício do Node.js
.\scripts\reiniciaServico.ps1 -ProcessName "node" -NomeUsuario "Admin" -Motivo "Atualização de aplicação"

# Reinício usando serviço Windows (se configurado no ProcessServiceMap)
.\scripts\reiniciaServico.ps1 -ProcessName "httpd" -ServiceName "Apache2.4" -NomeUsuario "Admin" -Motivo "Manutenção"

# Teste (sem executar ação)
.\scripts\reiniciaServico.ps1 -ProcessName "httpd" -NomeUsuario "Admin" -Motivo "Teste" -TipoReinicio "Teste"
```

### Reinicialização Automática

O sistema possui reinicialização automática programada:

- **Quando**: A cada 2 dias às 3h da manhã (dia sim, dia não)
- **Processos**: Todos os processos listados em `ProcessesToMonitor`
- **Ativação**: Pode ser habilitada/desabilitada via `AutoRestartEnabled` no config
- **Logs**: Registra todas as reinicializações automáticas

**Para desabilitar:**
```powershell
# No config.psd1
AutoRestartEnabled = $false
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

| Parâmetro       | Tipo     | Padrão                  | Descrição                                    |
| --------------- | -------- | ----------------------- | -------------------------------------------- |
| `ProcessNames`  | string[] | do config.psd1          | Lista de processos a monitorar               |
| `ThresholdStep` | int      | 500                     | Incremento do threshold (MB)                 |
| `SMTPServer`    | string   | do config.psd1          | Servidor SMTP                                |
| `SMTPPort`      | int      | do config.psd1          | Porta SMTP                                   |
| `EmailSender`   | string   | do config.psd1          | E-mail remetente                             |
| `EmailPassword` | string   | do config.psd1          | Senha do e-mail                              |
| `EmailRecipients` | array  | do config.psd1          | Lista de destinatários                       |

### reiniciaServico.ps1

| Parâmetro      | Tipo   | Obrigatório | Padrão    | Descrição                                      |
| -------------- | ------ | ----------- | --------- | ---------------------------------------------- |
| `ProcessName`  | string | Não         | "httpd"   | Nome do processo a reiniciar                   |
| `ServiceName`  | string | Não         | auto      | Nome do serviço Windows (auto-detectado)      |
| `NomeUsuario`  | string | Sim         |           | Nome do usuário que solicita o reinício       |
| `Motivo`       | string | Sim         |           | Motivo do reinício                             |
| `TipoReinicio` | string | Não         | "Forçado" | "Forçado", "Programado" ou "Teste"             |

## 📚 Documentação das Funções

Todos os scripts do sistema possuem documentação completa seguindo padrões PowerShell, incluindo:

### 🔍 Documentação Inline Completa
- **Synopsis**: Resumo da função
- **Description**: Descrição detalhada do propósito e funcionamento
- **Parameters**: Explicação de cada parâmetro com tipos e valores padrão
- **Examples**: Exemplos práticos de uso
- **Notes**: Informações importantes, dependências e restrições

### 📖 Como Acessar a Documentação

```powershell
# Documentação do script principal
Get-Help .\scripts\verificaMemoria.ps1 -Full

# Documentação das funções de banco
Get-Help .\scripts\database-connection.ps1 -Full

# Documentação específica de uma função
Get-Help New-SQLConnection -Full

# Listar todas as funções disponíveis
Get-Command -Module .\scripts\database-connection.ps1
```

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

Os logs são gravados em `log/serviceMonitor_log.txt` com formato que identifica cada processo:

```
2025-08-21 14:30:00 - [httpd] consumindo 1250.50 MB. NextNotificationLevel: 1500. LastNotifiedLevel: 1000. NotificationReason: upper
2025-08-21 14:30:15 - [node] consumindo 850.25 MB. NextNotificationLevel: 1000. LastNotifiedLevel: 500. NotificationReason: upper
2025-08-21 14:31:00 - [httpd] Alerta de memória enviado. Consumo: 1520.75 MB
2025-08-21 14:32:00 - [node] Processo não encontrado em execução.
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

## 📄 Licença

Este projeto é licenciado sob a **Apache License 2.0** - uma licença permissiva que permite uso comercial, modificação, distribuição, uso de patentes e uso privado.

### ✅ **PERMITIDO:**
- ✓ Uso comercial
- ✓ Modificação
- ✓ Distribuição
- ✓ Uso privado
- ✓ Uso de patentes

### 📋 **CONDIÇÕES:**
- Incluir aviso de licença e copyright
- Documentar mudanças significativas
- Incluir aviso de licença em versões distribuídas

### ❌ **LIMITAÇÕES:**
- Sem garantia
- Sem responsabilidade do autor
- Não inclui uso de marcas registradas

**Copyright © 2025 BrunoQuiodetto**

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

**3. Processo não encontrado:**
- Verifique se o nome do processo está correto (ex: "httpd", "node")
- Confirme se o processo está em execução: `Get-Process -Name httpd,node`
- Verifique a lista em `ProcessesToMonitor` no config.psd1

### Logs e Diagnóstico

- **Logs do sistema**: `log/serviceMonitor_log.txt`
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

### Logs e Troubleshooting

```powershell
# Verificar logs do Task Scheduler
Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" | Where-Object {$_.Message -like "*Service Memory Monitor*"} | Select-Object -First 10

# Verificar logs do sistema
Get-Content "U:\monitoraApache\log\serviceMonitor_log.txt" -Tail 20

# Testar conectividade SMTP
Test-NetConnection -ComputerName "seu.servidor.smtp.com" -Port 587
```

### Atualizações

Para atualizar o sistema de maneira padrão quando houver alguma modificação no script :

| Parâmetro      | Tipo   | Obrigatório | Padrão            | Descrição                                                       |
| -------------- | ------ | ----------- | ----------------- | --------------------------------------------------------------- |
| `NomeUsuario`  | string | Sim         |                   | Nome do usuário que solicita o reinício do serviço              |
| `Motivo`       | string | Sim         |                   | O que foi modificado na atualização                             |
| `$ProcessName` | string | Não         | "\MonitoraApache" | Nome que foi definido na [criação do serviço](ConfigurarTasks) |

```powershell
.\scripts\atualizaMonitoramento.ps1 -
```
---

**Desenvolvido para monitoramento robusto e confiável do Apache HTTP Server em ambientes Windows.**

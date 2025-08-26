# Criação da Tarefa no Task Scheduler

#### Opção 1. Via Interface Gráfica

1. Abra o **Task Scheduler** (`taskschd.msc`)
2. Clique em **"Create Task..."** (Criar Tarefa...)
3. Configure as abas conforme abaixo:

**Aba General:**
- Name: `Service Memory Monitor`
- Description: `Monitoramento contínuo de memória de múltiplos serviços (Apache, Node.js, etc.)`
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

#### Opção 2. Via PowerShell

```powershell
# Criar tarefa programada via PowerShell
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File 'U:\monitoraApache\scripts\verificaMemoria.ps1'" -WorkingDirectory "U:\monitoraApache\scripts"

$Trigger = New-ScheduledTaskTrigger -AtStartup

$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Days 365)

$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "\MonitoraApache" -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "Monitoramento contínuo de memória de múltiplos serviços"
```
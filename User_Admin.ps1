$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    try {
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
        $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
        exit $process.ExitCode
    }
    catch {
        Write-Error -Message "Não foi possível iniciar como administrador: $($_.Exception.Message)" -ErrorAction Continue
        exit 1
    }
}

try {
    $requiredCommands = @('Get-LocalUser', 'New-LocalUser', 'Get-LocalGroup', 'Get-LocalGroupMember', 'Add-LocalGroupMember')
    foreach ($commandName in $requiredCommands) {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            throw "O comando '$commandName' não está disponível. Execute o script em uma versão compatível do Windows PowerShell."
        }
    }

    Clear-Host
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' USUÁRIO LOCAL | ACESSO ADMINISTRATIVO' -ForegroundColor Cyan
    Write-Host " COMPUTADOR: $env:COMPUTERNAME" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '[ETAPA 1/3] Identificação da conta:' -ForegroundColor Yellow
    $userName = (Read-Host 'Nome do novo usuário local:').Trim()
    if ([string]::IsNullOrWhiteSpace($userName)) {
        throw 'O nome do usuário não pode ficar vazio.'
    }

    $user = Get-LocalUser -ErrorAction Stop | Where-Object { $_.Name -ieq $userName }
    $isNewUser = $null -eq $user
    $password = $null

    if ($isNewUser) {
        $password = Read-Host 'Senha para o novo usuário:' -AsSecureString
        if ($password.Length -eq 0) {
            throw 'A senha não pode ficar vazia.'
        }
    }
    else {
        Write-Host "[INFO] A conta '$userName' já existe." -ForegroundColor Yellow
        Write-Host '[INFO] A senha existente não será alterada.'
    }

    $administratorsGroup = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
    $changeDescription = if ($isNewUser) {
        "Criar a conta local '$userName' e adicioná-la ao grupo Administradores."
    }
    else {
        "Adicionar a conta existente '$userName' ao grupo Administradores, se necessário."
    }
    Write-Host ''
    Write-Host '[ETAPA 2/3] Confirmação:' -ForegroundColor Yellow
    Write-Host '------------------------------------------------------------'
    Write-Host " CONTA: $userName"
    Write-Host " AÇÃO:  $changeDescription"
    Write-Host '------------------------------------------------------------'
    $confirmation = Read-Host 'Confirma? (S/N):'
    if ($confirmation -notmatch '^(S|SIM)$') {
        Write-Host ''
        Write-Host '================ RESULTADO ================' -ForegroundColor Yellow
        Write-Host '[AVISO] Operação cancelada. Nenhuma alteração foi realizada.' -ForegroundColor Yellow
        Write-Host '===========================================' -ForegroundColor Yellow
        exit 0
    }

    Write-Host ''
    Write-Host '[ETAPA 3/3] Aplicando alterações:' -ForegroundColor Yellow

    if ($isNewUser) {
        $user = New-LocalUser -Name $userName -Password $password -PasswordNeverExpires -ErrorAction Stop
    }

    $administrators = Get-LocalGroupMember -Group $administratorsGroup.Name -ErrorAction Stop
    $isAlreadyAdministrator = @($administrators | Where-Object { "$($_.SID)" -eq "$($user.SID)" }).Count -gt 0

    if (-not $isAlreadyAdministrator) {
        Add-LocalGroupMember -Group $administratorsGroup.Name -Member $user -ErrorAction Stop
    }

    Write-Host ''
    Write-Host '================ RESULTADO ================' -ForegroundColor Green
    if ($isNewUser) {
        Write-Host "[OK] Conta '$userName' criada." -ForegroundColor Green
        Write-Host '[OK] Conta adicionada ao grupo Administradores.' -ForegroundColor Green
    }
    elseif ($isAlreadyAdministrator) {
        Write-Host "[OK] A conta '$userName' já pertence ao grupo Administradores." -ForegroundColor Green
        Write-Host '[INFO] Nenhuma alteração adicional foi necessária.'
    }
    else {
        Write-Host "[OK] Conta '$userName' adicionada ao grupo Administradores." -ForegroundColor Green
    }
    Write-Host '===========================================' -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host '================ RESULTADO ================' -ForegroundColor Red
    Write-Host '[ERRO] Operação não concluída.' -ForegroundColor Red
    Write-Host "[DETALHE] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '===========================================' -ForegroundColor Red
    exit 1
}

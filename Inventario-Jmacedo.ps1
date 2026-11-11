#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$NoPause,
    [switch]$NoSave,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$warnings = New-Object 'System.Collections.Generic.List[string]'
$collectedAt = Get-Date
$reportLines = New-Object 'System.Collections.Generic.List[string]'
$separator = '  ' + ('-' * 72)

function Write-JmLine {
    param([string]$Text = '', [ConsoleColor]$Color = 'Gray')
    Write-Host $Text -ForegroundColor $Color
    [void]$reportLines.Add($Text)
}

function Format-JmValue {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return 'Não disponível'
    }
    return ([string]$Value).Trim()
}

function Write-JmField {
    param([string]$Label, $Value)
    Write-JmLine ('  {0,-24} : {1}' -f $Label, (Format-JmValue $Value))
}

function Get-JmCim {
    param([string]$ClassName)
    try {
        Get-CimInstance -ClassName $ClassName -OperationTimeoutSec 15 -ErrorAction Stop
    } catch {
        [void]$warnings.Add("Não foi possível consultar ${ClassName}: $($_.Exception.Message)")
    }
}

function Get-JmNetwork {
    # A seleção usa a tabela local de rotas. Não faz requisições à internet.
    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
        $interfaces = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.ConnectionState -eq 'Connected' })
        $routes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
        $candidates = @(foreach ($route in $routes) {
            $iface = $interfaces | Where-Object { $_.InterfaceIndex -eq $route.InterfaceIndex } | Select-Object -First 1
            if ($null -ne $iface) {
                [PSCustomObject]@{
                    InterfaceIndex = $route.InterfaceIndex
                    Metric = [long]$route.RouteMetric + [long]$iface.InterfaceMetric
                    Gateway = $route.NextHop
                }
            }
        })
        $selected = $candidates | Sort-Object Metric, InterfaceIndex | Select-Object -First 1
        $basis = 'Rota padrão IPv4 de menor métrica; não comprova acesso à internet.'
        $gateway = $null
        if ($null -ne $selected) {
            $selectedIndex = $selected.InterfaceIndex
            $gateway = $selected.Gateway
        } else {
            # Sem gateway, mostra uma interface local válida e identifica a limitação.
            $localAddresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.AddressState -eq 'Preferred' })
            $localAdapter = $adapters | Where-Object { $_.InterfaceIndex -in $localAddresses.InterfaceIndex } |
                Sort-Object InterfaceIndex | Select-Object -First 1
            if ($null -eq $localAdapter) { throw 'Nenhuma interface ativa com IPv4 utilizável.' }
            $selectedIndex = $localAdapter.InterfaceIndex
            $basis = 'Rede local sem rota padrão IPv4; acesso à internet não verificado.'
        }
        $adapter = $adapters | Where-Object { $_.InterfaceIndex -eq $selectedIndex } | Select-Object -First 1
        $iface = $interfaces | Where-Object { $_.InterfaceIndex -eq $selectedIndex } | Select-Object -First 1
        $addresses = @(Get-NetIPAddress -InterfaceIndex $selectedIndex -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.AddressState -eq 'Preferred' } |
            Select-Object -ExpandProperty IPAddress -Unique)
        if ($addresses.Count -eq 0) { throw 'A interface selecionada não possui IPv4 utilizável.' }
        $alias = if ($null -ne $adapter) { $adapter.Name } else { $iface.InterfaceAlias }
        return [PSCustomObject]@{
            Interface = $alias
            IPv4 = $addresses -join ', '
            MAC = if ($null -ne $adapter) { $adapter.MacAddress } else { $null }
            Gateway = $gateway
            Selection = $basis
        }
    } catch {
        [void]$warnings.Add("Consulta de rede padrão indisponível: $($_.Exception.Message)")
    }

    # Alternativa para máquinas onde os cmdlets de rede estão indisponíveis.
    try {
        $configs = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE' -OperationTimeoutSec 15 -ErrorAction Stop)
        $configs = @($configs | Where-Object {
            @($_.IPAddress | Where-Object { $_ -match '^\d+\.' -and $_ -notmatch '^(127\.|169\.254\.)' }).Count -gt 0
        })
        $config = $configs | Sort-Object @{ Expression = { @($_.DefaultIPGateway).Count -gt 0 }; Descending = $true }, Index |
            Select-Object -First 1
        if ($null -ne $config) {
            return [PSCustomObject]@{
                Interface = $config.Description
                IPv4 = @($config.IPAddress | Where-Object { $_ -match '^\d+\.' -and $_ -notmatch '^(127\.|169\.254\.)' }) -join ', '
                MAC = $config.MACAddress
                Gateway = @($config.DefaultIPGateway | Where-Object { $_ -match '^\d+\.' }) -join ', '
                Selection = 'Consulta alternativa CIM; prioridade da conexão não confirmada.'
            }
        }
    } catch {
        [void]$warnings.Add("Consulta alternativa de rede indisponível: $($_.Exception.Message)")
    }
    [void]$warnings.Add('Nenhuma rede IPv4 identificada. A coleta do equipamento foi mantida.')
    return [PSCustomObject]@{
        Interface = $null; IPv4 = $null; MAC = $null; Gateway = $null
        Selection = 'Sem conexão IPv4 identificada.'
    }
}

try {
    # No Windows PowerShell 5.1, resolva o caminho no corpo do script,
    # depois da vinculação dos parâmetros, inclusive ao abrir sem argumentos.
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'Relatorios'
    }
    try {
        $Host.UI.RawUI.WindowTitle = 'J. MACEDO | Inventário do computador'
        $Host.UI.RawUI.BackgroundColor = 'Black'
        $Host.UI.RawUI.ForegroundColor = 'Gray'
        if (-not $NoPause) { Clear-Host }
    } catch { }

    Write-JmLine
    Write-JmLine $separator 'DarkCyan'
    Write-JmLine '       _       __  __    _    ____ _____ ____   ___  ' 'Cyan'
    Write-JmLine '      | |     |  \/  |  / \  / ___| ____|  _ \ / _ \ ' 'Cyan'
    Write-JmLine '   _  | |     | |\/| | / _ \| |   |  _| | | | | | | |' 'Cyan'
    Write-JmLine '  | |_| |  _  | |  | |/ ___ \ |___| |___| |_| | |_| |' 'Cyan'
    Write-JmLine '   \___/  (_) |_|  |_/_/   \_\____|_____|____/ \___/ ' 'Cyan'
    Write-JmLine
    Write-JmLine '                G R U P O   J .   M A C E D O' 'White'
    Write-JmLine '              INVENTÁRIO PORTÁTIL DE EQUIPAMENTOS' 'Cyan'
    Write-JmLine $separator 'DarkCyan'
    Write-JmLine ('  Coleta: {0}' -f $collectedAt.ToString('dd/MM/yyyy HH:mm:ss zzz'))
    Write-JmLine
    Write-Host '  Consultando equipamento e rede. Aguarde...' -ForegroundColor DarkGray

    $computer = Get-JmCim 'Win32_ComputerSystem'
    $bios = Get-JmCim 'Win32_BIOS'
    $os = Get-JmCim 'Win32_OperatingSystem'
    $network = Get-JmNetwork
    $computerName = if ($computer.Name) { $computer.Name } else { $env:COMPUTERNAME }
    $memory = if ($computer.TotalPhysicalMemory) {
        [math]::Round([double]$computer.TotalPhysicalMemory / 1GB, 2)
    } else { $null }
    $memoryDisplay = if ($null -ne $memory) { $memory.ToString('N2', [cultureinfo]'pt-BR') + ' GB' } else { $null }

    Write-JmLine '  [01] EQUIPAMENTO' 'Cyan'
    Write-JmLine $separator 'DarkCyan'
    Write-JmField 'Nome do computador' $computerName
    Write-JmField 'Fabricante' $computer.Manufacturer
    Write-JmField 'Modelo' $computer.Model
    Write-JmField 'Número de série' $bios.SerialNumber
    Write-JmField 'Memória RAM total' $memoryDisplay
    Write-JmLine
    Write-JmLine '  [02] SISTEMA OPERACIONAL' 'Cyan'
    Write-JmLine $separator 'DarkCyan'
    Write-JmField 'Sistema operacional' $os.Caption
    Write-JmField 'Versão do SO' $os.Version
    Write-JmField 'Arquitetura' $os.OSArchitecture
    Write-JmLine
    Write-JmLine '  [03] CONEXÃO DE REDE' 'Cyan'
    Write-JmLine $separator 'DarkCyan'
    Write-JmField 'Hostname' $computerName
    Write-JmField 'Interface' $network.Interface
    Write-JmField 'Endereço IPv4' $network.IPv4
    Write-JmField 'Endereço MAC' $network.MAC
    Write-JmField 'Gateway' $network.Gateway
    Write-JmLine ('  Critério: {0}' -f $network.Selection) 'DarkGray'

    if ($warnings.Count -gt 0) {
        Write-JmLine
        Write-JmLine '  [!] OBSERVAÇÕES DA COLETA' 'Yellow'
        foreach ($item in $warnings) { Write-JmLine ('  - ' + $item) 'Yellow' }
    }
    Write-JmLine
    Write-JmLine $separator 'DarkCyan'

    if (-not $NoSave) {
        try {
            [void][System.IO.Directory]::CreateDirectory($OutputDirectory)
            $safeName = $computerName -replace '[^a-zA-Z0-9_.-]', '_'
            $fileBase = '{0}_{1}_{2}' -f $safeName, $collectedAt.ToString('yyyyMMdd_HHmmss_fff'), ([guid]::NewGuid().ToString('N').Substring(0, 6))
            $txtPath = Join-Path $OutputDirectory ($fileBase + '.txt')
            $csvPath = Join-Path $OutputDirectory ($fileBase + '.csv')
            $record = [PSCustomObject][ordered]@{
                'Data da coleta' = $collectedAt.ToString('o')
                'Nome do Computador' = $computerName
                'Fabricante' = $computer.Manufacturer
                'Modelo' = $computer.Model
                'Número de Série' = $bios.SerialNumber
                'Sistema Operacional' = $os.Caption
                'Versão do SO' = $os.Version
                'Arquitetura' = $os.OSArchitecture
                'Memória Total (GB)' = $memory
                'Interface' = $network.Interface
                'Endereço IP (IPv4)' = $network.IPv4
                'Endereço MAC' = $network.MAC
                'Gateway' = $network.Gateway
                'Critério de rede' = $network.Selection
                'Observações' = $warnings -join ' | '
            }
            $reportLines | Set-Content -LiteralPath $txtPath -Encoding UTF8
            $record | Export-Csv -LiteralPath $csvPath -Delimiter ';' -NoTypeInformation -Encoding UTF8
            Write-Host '  COLETA SALVA' -ForegroundColor Green
            Write-Host ('  TXT: ' + [System.IO.Path]::GetFullPath($txtPath)) -ForegroundColor Gray
            Write-Host ('  CSV: ' + [System.IO.Path]::GetFullPath($csvPath)) -ForegroundColor Gray
        } catch {
            Write-Host '  Não foi possível salvar os relatórios.' -ForegroundColor Yellow
            Write-Host ('  ' + $_.Exception.Message) -ForegroundColor Yellow
            Write-Host '  Os dados continuam disponíveis nesta tela.' -ForegroundColor Gray
            if (-not $NoPause) { [void](Read-Host '  Pressione ENTER para fechar') }
            exit 2
        }
    } else {
        Write-Host '  Coleta concluída sem salvar arquivos (-NoSave).' -ForegroundColor Green
    }
    Write-Host
    if (-not $NoPause) { [void](Read-Host '  Pressione ENTER para fechar') }
    exit 0
} catch {
    Write-Host ('  Falha na coleta: ' + $_.Exception.Message) -ForegroundColor Red
    if (-not $NoPause) { [void](Read-Host '  Pressione ENTER para fechar') }
    exit 1
}

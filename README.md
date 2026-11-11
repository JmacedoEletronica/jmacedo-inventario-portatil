# Inventário portátil — J. Macedo

Ferramenta para consultar informações do computador Windows e salvar relatórios locais em TXT e CSV.

## Download rápido

[Baixar o ZIP](https://github.com/JmacedoEletronica/jmacedo-inventario-portatil/releases/latest/download/Jmacedo-Inventario-Portatil.zip)

1. Baixe e extraia o ZIP.
2. Abra **ABRIR-INVENTARIO.cmd** com dois cliques.
3. Aguarde a coleta. Os resultados ficam na pasta **Relatorios**, criada junto ao script.
4. Para usar em outro computador, copie os três arquivos juntos ou baixe o ZIP novamente.

Execute após extrair o ZIP. Funciona também em pendrive com permissão de escrita.

## Informações coletadas

Nome, fabricante, modelo, série do BIOS, sistema operacional, arquitetura, memória RAM, interface de rede, IPv4, MAC e gateway. O CSV usa ponto e vírgula e pode ser aberto no Excel.

A coleta consulta o computador local, funciona sem internet e não envia informações ao ERP ou a servidores externos. Os relatórios contêm identificadores do equipamento e da rede; mantenha-os no armazenamento interno autorizado, fora do GitHub.

## Requisitos e opções

Windows 10/11 e Windows PowerShell 5.1. Não exige instalar módulos. Políticas da empresa podem restringir scripts e consultas; o iniciador não altera permanentemente a política do Windows.

```powershell
# Coletar e salvar sem aguardar Enter no final
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Inventario-Jmacedo.ps1 -NoPause

# Mostrar somente na tela, sem gerar relatórios
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Inventario-Jmacedo.ps1 -NoSave
```

Consulte [LEIA-ME.txt](LEIA-ME.txt) para detalhes sobre a seleção da interface de rede e limitações.
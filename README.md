# RSRRepair

Userspace binary and companion kernel extension to
recover from desynced kernel cache artifacts.

A Rapid *Stability* Response to [Rapid Security Response-induced issues](https://github.com/dortania/OpenCore-Legacy-Patcher/issues/1019)

#### Userspace binary arguments
- `--install` to manually install the binary to `/etc/rc.server`

#### Kernel extension boot arguments
- `-rsrrcoff` (or `-liluoff`) to disable
- `-rsrrcdbg` (or `-liludbgall`) to enable verbose logging (in DEBUG builds)
- `-rsrrcbeta` (or `-lilubetaall`) to enable on macOS versions other than Ventura.

#### Credits
- [Apple](https://www.apple.com) for macOS and [Rapid Security Response](https://support.apple.com/guide/deployment/rapid-security-responses-dep93ff7ea78/web)
- [flagers](https://github.com/flagersgit) for this software
- [Acidanthera](https://github.com/acidanthera) for [Lilu.kext](https://github.com/vit9696/Lilu)

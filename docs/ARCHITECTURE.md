# dnf-for-termux: Architecture

> ⚠️ **Este documento puede estar desactualizado**: describe el estado inicial del proyecto
> (fases del plan original y estructura con submódulos que ya no existen). La **fuente de
> verdad** del estado actual es [`PROGRESS.md`](../PROGRESS.md) y
> [`REPORT.md`](../REPORT.md). Se mantiene por su valor de referencia del stack y del mapeo
> de rutas FHS → Termux.

## Overview
Adaptación de DNF5 (Fedora package manager) para funcionar en Termux (Android).

## Component Stack
```
dnf5 CLI (C++17)
  └── libdnf5 (C++17 core)
       ├── librepo (C) - Repository operations
       ├── libsolv (C) - SAT dependency solver
       ├── libcomps (C) - Group management
       ├── zchunk (C) - Compressed metadata
       └── rpm (C) - RPM package manipulation
```

## Path Mapping (FHS → Termux)
| Original | Termux |
|----------|--------|
| /etc/dnf/ | @PREFIX@/etc/dnf/ |
| /var/lib/dnf/ | @PREFIX@/var/lib/dnf/ |
| /var/cache/dnf/ | @PREFIX@/var/cache/dnf/ |
| /etc/yum.repos.d/ | @PREFIX@/etc/yum.repos.d/ |
| /usr/share/dnf/ | @PREFIX@/share/dnf/ |

## State
- **Phase 0**: ✅ Structure & submodules
- **Phase 1**: 🔄 Patches in progress
- **Phase 2**: ⏳ RPM port
- **Phase 3**: ⏳ Integration & tests

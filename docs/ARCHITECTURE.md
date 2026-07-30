# dnf-for-termux: Architecture

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

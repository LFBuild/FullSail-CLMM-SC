# FullSail CLMM SC

© 2025 Metabyte Labs, Inc.  All Rights Reserved.

U.S. Patent Application No. 63/861,982. The technology described herein is the subject of a pending U.S. patent application.

Full Sail has added a license to its Full Sail protocol code. You can view the terms of the license at [URL](LICENSE/250825_Metabyte_Negotiated_Services_Agreement21634227_2_002.docx).

## Audits

Audit provider: **Asymptotic**

Final report date: May 29, 2025

Final commit: [here](https://github.com/LFBuild/FullSail-CLMM-SC/commit/e51f30a44b5a49b620608b9195aee72326a01581)

Published: [here](https://info.asymptotic.tech/full-sail-clmm-audit)

Audit scope:
- `./clmm_pool`
- `./gauge_cap`


## Overview

This repository contains the implementation of the FullSail CLMM SC.

## Docs

Check [docs](./docs) for more details.

## Mvr

You can use Full Sail via https://www.moveregistry.com/

```bash 
mvr add @pkg/fullsail-clmm
```

## Mainnet test deployments

- [move_stl](https://suivision.xyz/txblock/EUHqf4MGpxRjDodcW2TFq7EUDqRBcV8gsFgQARvE8zQF) 
    - package: `0x2d8a7d4c585f1c20758f9b2c500477e1be35e178e79efb6ddf9d14a0dceff211`
- [integer_mate](https://suivision.xyz/txblock/CWQ5cMDkAGu6o8nCWDix25KGpnBXRLt2bZdVchacjRVN) 
    - package: `0x6b904ae739b2baad330aae14991abcd3b7354d3dc3db72507ed8dabeeb7a36de`
- [gauge_cap](https://suivision.xyz/txblock/GvCKoRnkC33NCPpuiDkpPGLLMzcbvw2ne7sWbUNqTqvJ)
    - package: `0xc543ef4485b43149ff6a4f3e8df3a0e9d7ea73ea25381b2948c8a6c3efc62672`
- [price_provider](https://suivision.xyz/txblock/BWoFFHTXyKHYprCJUMadTuf41ETM7TWv6qGBkYzXAZyc)
    - package: `0x8efc19386b334f035ceaa121b84f331b295b947cd8c601aa37faa36ed0f7466b`
    - PriceProvider: `0x5654459f1754e16420c5a49639225e9b8295f6623fd484426378b75d4eb0169b`
- [clmm_pool](https://suivision.xyz/txblock/7DZ9HBQbzthrMoyRz47Jd8G6frQx94evW63o1fZYe8HE)
    - original package: `0x8c9b843944257991e5f813039d9fb70e0358ae2ff28b2bfdf2624dd6d8251bb3`
    - Pools: `0xf7c195f31e5659f830e42d0e467c5235ad0cf32c85cab27ace5d60a443795592`
    - RewarderGlobalVault `0x5d50fbada683f54ae6f2b98659522d0f2c6deb3eb11a4998434c40cc45d2eda9`
    - GlobalConfig `0x43b1eb08db4a1dfce2c6ca4e4710f56975fd06eb861091aa5ff984f88a39302a`
    - Stats `0xf350b6b218c44a7ccd8f6489f26d7e637dec55946f8d49e85d327e8188db1872`
    - Partners `0x1e21b34fd9d1b76af72de919cddbed2edcb12c0f47399ad2225fbaa01e266788`

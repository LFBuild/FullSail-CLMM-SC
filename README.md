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
- [gauge_cap](https://suivision.xyz/txblock/ADHzxNn8zz7mZgr4MbDLe5BysHBRZiTjCENcYZ3CenrD)
    - package: `0x00500636366963eb62bee705e420dacd6e3770447914043d7978deb49372401e`
- [price_provider](https://suivision.xyz/txblock/BWoFFHTXyKHYprCJUMadTuf41ETM7TWv6qGBkYzXAZyc)
    - package: `0x8bb9f5926f9464cd033391d05e077ddf9aab3a80fa17cce40d81ac6ad2b66ecb`
    - PriceProvider: `0x4ae40e45442ab65f094345adc252c1561d55c39f8a27c6968d544e02a2af091c`
- [clmm_pool](https://suivision.xyz/txblock/5q549epD7EM1fCHazZ3eHzzjBadvW6fZZazHwYVZWjod)
    - original package: `0xaa3ae572fb09f157d7368ce22c6b7f33fde0fe74cba75ae9679af52088b57bb0`
    - Pools: `0x3cdc2c78d609ff99f8ddfd8713492b4a0ddd6f0964668c20dd7b4fbcffb895b6`
    - RewarderGlobalVault `0x96eeac7f51cd7697c68d3026c782750f178e7e477d51c0f9e4a9972a80889a51`
    - GlobalConfig `0x03b9c9a7889bb4c1144c079d5074432fc9a58d67c062f27cf6390967f3095843`
    - Stats `0xe1182c8e079e70af62f95b13d22a4a4cdcf9f8dba9463a53e0b650151de187e1`
    - Partners `0x2f865e6a74bfd4fd2e87faa8684511a111d5bde93755c9d710e6f28587686bf7`

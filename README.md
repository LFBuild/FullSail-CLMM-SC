# FullSail CLMM SC

© 2025 Metabyte Labs, Inc.  All Rights Reserved.

U.S. Patent Application No. 63/861,982. The technology described herein is the subject of a pending U.S. patent application.

Full Sail has added a license to its Full Sail protocol code. You can view the terms of the license at [ULR](LICENSE/250825_Metabyte_Negotiated_Services_Agreement21634227_2_002.docx).

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

## Mainnet deployments

- [move_stl](https://suivision.xyz/txblock/EUHqf4MGpxRjDodcW2TFq7EUDqRBcV8gsFgQARvE8zQF) 
    - package: `0x2d8a7d4c585f1c20758f9b2c500477e1be35e178e79efb6ddf9d14a0dceff211`
- [integer_mate](https://suivision.xyz/txblock/CWQ5cMDkAGu6o8nCWDix25KGpnBXRLt2bZdVchacjRVN) 
    - package: `0x6b904ae739b2baad330aae14991abcd3b7354d3dc3db72507ed8dabeeb7a36de`
- [gauge_cap](https://suivision.xyz/txblock/EzgXx1xJNBMS6krkPWJxfgx6KpT4oPh4Y8zydVWVTJ34)
    - package: `0xfc5ce91b953f03c30e3e48ac1d2a7706d66697c25979aeb978f9fff3fbcde5b2`
- [price_provider](https://suivision.xyz/txblock/BP8hsrBNWZPc5tb29XZQzdc7gGPP1gBYyZUbZPUa6LJG?tab=Overview)
    - package: `0xb49be008cf304b1dae7e7ece661b5f1b0e15324bc1422ec8c73b10eb4a6dcb19`
    - PriceProvider: `0x854b2d2c0381bb656ec962f8b443eb082654384cf97885359d1956c7d76e33c9`
- [clmm_pool](https://suivision.xyz/txblock/4HVyzZWudh3LZSWZawyN3ZPgqotKiZ7fzbC5cycuT1AB)
    - original package: `0xe74104c66dd9f16b3096db2cc00300e556aa92edc871be4bc052b5dfb80db239`
    - Pools: `0x0efb954710df6648d090bdfa4a5e274843212d6eb3efe157ee465300086e3650`
    - RewarderGlobalVault `0xfb971d3a2fb98bde74e1c30ba15a3d8bef60a02789e59ae0b91660aeed3e64e1`
    - GlobalConfig `0xe93baa80cb570b3a494cbf0621b2ba96bc993926d34dc92508c9446f9a05d615`
    - Stats `0x6822a33d1d971e040c32f7cc74507010d1fe786f7d06ab89135083ddb07d2dc2`
    - Partners `0xd8bf42d4ab51ca7c938b44e0a83db4c1abe151ad36bb18e6934dce6ed299cbfd`
- [clmm_pool upgrade 1](https://suivision.xyz/txblock/7VdktfjzNjNF4AoKnTNpLACNECz2m8NXvNX3wHLhncnf)
    - latest package `0xecd737da1a3bdc7826dfda093bda6032f380b0e45265166c10b8041b125980b9`

# Synology version preparation evidence

## Change summary

- Upstream: `v1.98.9` at `6c167d40fa37aeb51afa7ff336730670ea4762bf`
- Previous upstream: `6c167d40fa37aeb51afa7ff336730670ea4762bf`
- Previous release: `8af4a530fb536bfc5717057000cc0ac5df23b162`
- Prepared branch: `work/v1.98.9-synology-r2`
- Prepared commit: `0fad8b81a3e0eb86c457bc79c474bcc213834c43`
- Prepared tree: `33f5c5927ae4db54b9d582650ed31cc6a2eb7161`

## Ordered logical history

1. `8a2204fa027bd56bb27d1e7f6af696e4eefa8c1a` -> `e467cd8100bda45a35ab78f7e2798906ad7167c8` — synology: permit routing and netfilter preferences
2. `1c5dcbe5cc7f6c1b237e74ca721bc10f2548506a` -> `3ad299ce2479d0d080520094ff136b6838401c33` — synology: use kernel TUN and subnet routing
3. `46c6f760abf06370ce5b4cfc0e878e2c854c4522` -> `dbed84ea9bc3b7aec2ace013d4413577900e9454` — synology: enable the Linux netfilter backend
4. `a2ac2a275f4b2f0d7f786ca670d8040c83a6ae73` -> `7e4cfa91e13cec0d75797e4ee8159a2ee39b69c0` — build: add v1.98.9 Synology netfilter patch
5. `01d9071ddceae34502978656f1f36b26906841ec` -> `f58ddb79af80342d390ca8640073188a46b8395c` — synology: require kernel TUN during package startup
6. `4d7586ff0238a41fc627cf905af0bdcae1c67d0e` -> `91f3ce6f846523f32a72d0e4463a4e55fb4c1cca` — synology: force kernel networking in the SPK launcher
7. `456f90c5bf5c383f37ab2f0ca6b7f0531730a140` -> `c5b8ec5191096d5e0854afb5a8ccde78ea068690` — synology: package safe and root privilege manifests
8. `f7f177695b8d5ade4107536afb2e0f164cde3b7e` -> `b1488524fe09ef2c26dbf168c38bb0051ecdcaae` — synology: add administrator root runtime bootstrap
9. `a471b0eb42e8487b47aa051b1198ba536e250669` -> `6ba18b9cd5ac5e3cace667f108ee770012200134` — synology: gate startup on administrator bootstrap
10. `a106ddb72822c61cefd068fef64ea1a473c47fae` -> `58c54e0422e26d1ca12dec24f154d3c953ded19a` — synology: verify root runtime prerequisites
11. `ffcabae3653570468ce490d7e77403e9576b904c` -> `7812a9d336fe9d0f7f0ef5fca6437f71dfa775d6` — build: produce and compare Synology package variants
12. `6c9b329bc322f39c29be89b89408c65bfccea545` -> `3daae24ab39a31d59d8d2149861c033927a8f28a` — test: cover Synology root runtime bootstrap
13. `9b7c0464a2b5561cfb3e70bf07c22a6906c88cc8` -> `410b3666ee586e17dfd2bc1b310c3b192f5ad436` — synology: require netfilter module package
14. `bcd28b33dcf62320b069562f017885ad0d4077be` -> `8586fe7b297891c5836f11b7842dbc58ce89b380` — synology: rebuild missing netfilter hooks
15. `e310e762b4919cad36a6e06fa8608da00660dc9d` -> `d5df025c176d08929d35380c6d253069498ea0a0` — synology: reconcile netfilter after startup
16. `c765b13f21e642b594236d2b1561cf5b519411f7` -> `eb90e3ea1e02a828af57132ea239200275988a70` — synology: supervise netfilter reconciliation
17. `c5ba81b3386ca96c5e0c4630addbb94b4eb7d4cf` -> `31373860813c44063dbdd72164d2380fddc1adad` — synology: avoid reconciler broken pipe diagnostics
18. `cc5d96275e9dd76fd8a4f38209a2df91199a425c` -> `95b9e348a1027140176682eaeaec546a9e569ea6` — synology: harden boot networking startup
19. `20c86229955a3d03de01901aee1499cab87c571d` -> `97cec50a2adbea8879529d087f9ea7c6fdedf05d` — build: make release artifacts reproducible
20. `8c9fe5239ee57a89ce687fc8c7608d3df91f6ede` -> `d761199bbf823a5ba22a32b8668a7719c1af6375` — release: prepare Synology r2 package
21. `94c1515161ff7b0db05c1556991b2d06b7299370` -> `1aaf5576281e0c4318adc8418def72c8d11b90e7` — docs: design agent upgrade workflow
22. `c69f0f786dc8b087e0a4fc88adf349cf5f55b7ce` -> `50bfb3e51fa5c9af600341c4bcc666e63b3b49bd` — chore: promote Synology release controls
23. `78780c5727e9e90cd4f45b7b97e8a08e7a652b88` -> `a8e1fbbaf713b772129064a75c235ad2f450c451` — docs: define agent upgrade contracts
24. `2d59da54d29adf802c7a44671d1c1cdad1d4e528` -> `ed51ca28982c1ae1dc9356f360dc3868cbf62171` — feat: prepare pinned Synology versions
25. `4283e963925e64b83737bf97d7abc555435ec733` -> `2045db12b670c56dc7343433899c91465ce37209` — test: enforce fail-closed version preparation
26. `4c7f06c5fdd438af87c959bd57ed991cdc636c4e` -> `dbad52632e9f61a0210fda29d086e2cb92f9a8fe` — docs: add version preparation runbook
27. `8e5b02a95bc8b34207b09bd8078f6f30d47c00e9` -> `31bfcafcf7b18bb36ec17356215bb608fca33836` — chore: complete source validation controls
28. `20899f9110a389a611c5557af07ccbf511eb02d6` -> `3ae0f4040e1dc2c82eb3a42b5ea86d0068e66b92` — fix: classify protected patch adjunct
29. `993f77a4fa18b4246bb4dc5ce6632968c92c5e62` -> `94012597cd013575da1a4c3941ce79df59a706c7` — docs: record pre-cleanup manifest
30. `bb5662ce80db6d8f6a2fe525d0bb2c0e4f8e343f` -> `53b7d4f7fb5f89a4818369e44d63e6d180519020` — docs: record post-cleanup inventory
31. `b7c45672aa537b0cc0d122d4727cb4bdc4c7186b` -> `77adfc0db8fa58d6bfb1f6f229fe32a365006b69` — fix: isolate preparation from inherited hooks
32. `0c8d38579085ca4e1419b51471be41cb76df5c92` -> `d92f28153cff3e86681c60be91827ff0a386c783` — fix: constrain control-only hook setup
33. `89c8676e39e1273041926f0e569f7b8029e8a7e1` -> `32636ae39bb7b5fd2b1e1851494afc8265acdf87` — docs: inventory follow-up cleanup targets
34. `71ac92c949d53f9fb54a91b43b95464bd957164d` -> `6bfc4775809f9c2fb897393485d7ed1a66e27695` — docs: record follow-up cleanup state
35. `5c0e8d45c575241f1c46b7f74aabcedf02c58d3d` -> `edbeea996d20970dc94a8f80a86f11569293a48b` — test: enforce canonical ShellCheck diagnostics
36. `d5a59df5d514bafec91491e9ce6e9acaec3f396c` -> `0bf0505d7fadea20e70a8ad09f69f6d419229733` — docs: normalize Markdown end-of-file whitespace
37. `723da638de9939fdc5f518fbbf0521539eebf1d2` -> `59528baa4d5e1bbe7384dc367598528b0627e9ce` — test: enforce read-only mismatch stop
38. `a8ac5196692afc04e179e7eb013f1710fce0f2b1` -> `ccc003ae51bbe3c02b0a846fd27229afa03c4f77` — docs: require complete preparation handoff
39. `c8b82f5621bba7ea1b587e75a782bd5560c70aee` -> `63e959f370d5f986e8a4330b632d2a22c2164308` — fix: fail closed on preparation output conflicts
40. `55743818090266bbb019719bd5ef0e2ebbab2fef` -> `9d64ceea10d0a2506f69e5c7f7e5fba378e7fc1e` — fix: bind control hooks to one worktree authority
41. `bef0cce0fd6fc5dc92814941518cb43bf9f86b16` -> `45da2a677e54cd707f8851b90eddedfdef2b3a05` — fix: retain release validation in control authority
42. `d91bec41b27afdc24cce5be2947fd2256e0b1fa9` -> `629887f1db9e3147936cbab1bc0a230b86e55624` — test: scope full-range whitespace exemptions
43. `0c36fb9d771a2265c622effc7d8456967488565d` -> `83a17c185805af30136129cb901ecb77dae1b691` — docs: correct cleanup target grouping
44. `50628f78a015dc97031a809e3d090055a93b072b` -> `5550e92a35bb9dcd071e1a40c91c8bfd53cf6e58` — fix: suppress inherited worktree hooks
45. `07e4b232f9f2748dc12446f4316a48b1641ef9cc` -> `067d60e46b655bde0da91fc602cfde34b56ffe7b` — fix: fail closed on round-trip cleanup
46. `4ecdb3d5daf49b03d2bab024d080d466aad9336a` -> `9c649700d3a4c8ee7338fb2f19a3c948320bd710` — fix: suppress legacy worktree hooks
47. `71a574eb76bcf3faaa2023bbe4d7ba5943928d3c` -> `01a6c8fdfbf4685d1cd7fc99b845067c5ec8e1fd` — fix: add required Synology Go license headers
48. `453dba177fff13f77dc521d9c2cb4e33dbda1b31` -> `4a638f8f341e2f07ded70bb3a45db66533462d9b` — ci: use fork-portable GitHub Actions
49. `8c68d216d9bf3661cfd769bf51960585db8716b8` -> `ef0bd07b4e52b9bb06e89b674a53084ae4087e93` — fix: enforce LF Synology dependency metadata
50. `b938683769f6f1a2581fb4057dbbddd74b5ce9e5` -> `9a5f884862fe307e98a450857982170dede7fb5c` — ci: allow intentional fork job skips
51. `3cafff3c351e8ff2c232e452ca8b0a7d544d51a2` -> `5696f5385b1f2d6c3004377c35b967877674365a` — ci: add focused Synology product gate
52. `db4b77cca05bd811f20e9df540a387d665516492` -> `6b26d08944728138a32e8d05b72bf3d64496f31c` — fix: make artifact installation coreutils-compatible
53. `e1b37e5dc5229ff048155d77ef06a0d63ee9245a` -> `650bae44ae0413eba267ca12519110defc3f65ca` — fix: cover trapped cleanup ShellCheck rules
54. `af9597f7c91b0ea231840c14d93b8b9717afbc80` -> `0e6356677bf23426d46fb0c03892b3ff74783609` — fix: correct Synology dependency minimum
55. `30144357afba319ca599d054cdd9914678dbca67` -> `6a1a6235a021ed05934e62c37ba171cf09904675` — synology: expose attended bootstrap command
56. `632aa3e9d3137d96447709484414f31b09370587` -> `3df4304bbb8ccb24fcd60aa7c3ab42c3599055f2` — synology: harden DSM root runtime lifecycle
57. `4afe53259e1a55085dc45a6128bdf7486ed80bf5` -> `8af4a530fb536bfc5717057000cc0ac5df23b162` — docs: record DSM 7.4.1 bootstrap hardening
58. `0fad8b81a3e0eb86c457bc79c474bcc213834c43` -> `0fad8b81a3e0eb86c457bc79c474bcc213834c43` — ci: make release gates deterministic

## Validation evidence

- Internal commit/apply hooks: disabled
- Source range: linear and ordered
- Prepared commits: signed with one matching sign-off each
- Patch series: mail format with verified SHA-256 digests
- Round-trip tree: `33f5c5927ae4db54b9d582650ed31cc6a2eb7161`

## Fixed product contract

- Dependency: `iptables-netfilter-extensions`
- Dependency minimum: `1.1.0-2`
- Dependency and Tailscale DSM minimum: `7.3-86009`
- Production `os_max_ver`: absent

## Risks and reviewer attention

Review the signed CI-only delta and run source/package/hardware validation separately.

## Prohibited side effects

No fetch, push, tag, release, publication, NAS installation, root bootstrap,
firewall mutation or reboot was performed by review-bundle generation.

## Verdict

`PASS — ready for independent source review`

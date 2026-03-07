# [1.4.0](https://github.com/Thomas-3145/homelab/compare/v1.3.1...v1.4.0) (2026-03-07)


### Features

* **longhorn:** lagt till Longhorn distributed storage ([2435214](https://github.com/Thomas-3145/homelab/commit/243521446461ba4a908a9839b8afc4254e3e6701))

## [1.3.1](https://github.com/Thomas-3145/homelab/compare/v1.3.0...v1.3.1) (2026-03-07)


### Bug Fixes

* **longhorn:** tog bort pre-upgrade checker hook ([3899f3c](https://github.com/Thomas-3145/homelab/commit/3899f3c79688c131f54ff7ee237612eb3e264a34))

# [1.3.0](https://github.com/Thomas-3145/homelab/compare/v1.2.0...v1.3.0) (2026-03-07)


### Features

* **longhorn:** lagt till Longhorn storage och Ansible förberedelser ([bbbb7e5](https://github.com/Thomas-3145/homelab/commit/bbbb7e56822ba59d027adc0b9f3a892527635198))

# [1.2.0](https://github.com/Thomas-3145/homelab/compare/v1.1.0...v1.2.0) (2026-03-05)


### Features

* **secrets:** add SOPS + KSOPS for encrypted secret management ([eacc318](https://github.com/Thomas-3145/homelab/commit/eacc318c5b769e1bc29f952beb0317e9e1bd26ad))

# [1.1.0](https://github.com/Thomas-3145/homelab/compare/v1.0.1...v1.1.0) (2026-03-05)


### Features

* **it-tools:** lagt till it-tools ([de94670](https://github.com/Thomas-3145/homelab/commit/de94670d36de094e503b0ac3ced2a92a94cd0471))

## [1.0.1](https://github.com/Thomas-3145/homelab/compare/v1.0.0...v1.0.1) (2026-03-04)


### Bug Fixes

* **commitlint-guide:** tog bor den då icke relevant ([a0f3d8f](https://github.com/Thomas-3145/homelab/commit/a0f3d8fa77f173791959e920226602be1f949017))

# 1.0.0 (2026-03-04)


### Bug Fixes

* **ansible:** råkade ta bort en rad ([5b83a46](https://github.com/Thomas-3145/homelab/commit/5b83a4647c6f578664f72f0dc07600109744e524))
* **docs:** fix README typo and add terraform.tfvars.example ([a5f0a8d](https://github.com/Thomas-3145/homelab/commit/a5f0a8d32adfe23c765953483efe2904234a872f))
* **homepage:** ghostikonerna som png ([4cadd81](https://github.com/Thomas-3145/homelab/commit/4cadd8174bf6f3d0eb0116d364e02a3d300942e1))
* **homepage:** provar andra iconer görst ghost och adguard ([d2616d2](https://github.com/Thomas-3145/homelab/commit/d2616d2938321f5881a657192061bbc057916984))
* **homepage:** ta till adguardhome och fixade iconer ([183916d](https://github.com/Thomas-3145/homelab/commit/183916d7b8fee63b77fec6159c9276616ba96e9c))
* **homepage:** Tailscale IP för Uptime Kuma widget ([bd66913](https://github.com/Thomas-3145/homelab/commit/bd6691303f8973d9cd46846ebf2d8d4911f6ec40))
* **terraform:** add temporary password for ubuntu user ([7b4026f](https://github.com/Thomas-3145/homelab/commit/7b4026fe8d9219170a763d444bdfac9e6275dabb))
* **terraform:** apply Opus security and architecture recommendations ([8a52d97](https://github.com/Thomas-3145/homelab/commit/8a52d977f49f7269afb7f564d583c12499df182b))
* **terraform:** increase timeouts for slow Proxmox operations ([ee32b6b](https://github.com/Thomas-3145/homelab/commit/ee32b6b0a9e92ac64bf74b0bee8672237974e7aa))
* **terraform:** la till en snutt yaml kod som referens i .tfvars.example ([012b1af](https://github.com/Thomas-3145/homelab/commit/012b1afd8c2432507f1cfb182e30c64092bc266f))
* **terraform:** remove SSH key injection due to provider limitations ([f6a479a](https://github.com/Thomas-3145/homelab/commit/f6a479a83db121e0e4d67c58f0757e4ab827dcb4))
* **terraform:** remove unsupported timeouts block ([0ba5030](https://github.com/Thomas-3145/homelab/commit/0ba5030ec32db947437aae76c63cefa797af71f0))
* **terraform:** remove VLAN tagging from network config ([b3b1846](https://github.com/Thomas-3145/homelab/commit/b3b18464b9571d1594ba5ebb27cfa8fcb389ef99))


### Features

* **ansible:** gjorde om install till prepare-test och la till basic updates ([7dd2d2a](https://github.com/Thomas-3145/homelab/commit/7dd2d2ace90fac70062f420e331e2a0f0879da6a))
* **ansible:** tailscale på nya test VM ([86ff3a0](https://github.com/Thomas-3145/homelab/commit/86ff3a095b5824d4c02a93da34cc03aab6b58bef))
* **argocd:** bytte ingress för argocd.3145.blog med TLS ([e5ea58c](https://github.com/Thomas-3145/homelab/commit/e5ea58c79ea2fd9040728c0b8cddcf49c995a42f))
* **cloudflare:** la till  ArgoCD ([2366f39](https://github.com/Thomas-3145/homelab/commit/2366f399efa1bb6bb07966009ef5905a6b983d62))
* **cloudflare:** lagt till Cloudflare TUnnel för k3s ([b5527e4](https://github.com/Thomas-3145/homelab/commit/b5527e474a3672269cd332fc91c88591dc896a79))
* **headlamp:** add permanent service account token ([decd60d](https://github.com/Thomas-3145/homelab/commit/decd60dc98de6452739009ad8a3760026fe6cd08))
* **homepage:** bytte till liknande layout som tidigare ([911eb47](https://github.com/Thomas-3145/homelab/commit/911eb47b74910a79035faea142f24e514d220dd4))
* **homepage:** datetime och väder widgets ([672f44c](https://github.com/Thomas-3145/homelab/commit/672f44c7e7bc0d9bcfd73f9c547379a83bc39930))
* **homepage:** fixade  nedladdningar-kategorin ([3ef0e44](https://github.com/Thomas-3145/homelab/commit/3ef0e445bcc946290cee21d91557e5d657376263))
* **homepage:** media ifrån tidigare homepage ([e5b93b0](https://github.com/Thomas-3145/homelab/commit/e5b93b08999d70b12e3840a08a142c7f4b432aff))
* **homepage:** nedladdningar.. ([a77ed7d](https://github.com/Thomas-3145/homelab/commit/a77ed7d1175ec528a1df71b021ee9f9037305eb6))
* **homepage:** Uptime Kuma widget ([9ff27e7](https://github.com/Thomas-3145/homelab/commit/9ff27e7f5e525cf777cfbf6467519715d77f3093))
* **kubernetes:** replace Traefik with MetalLB, ingress-nginx & cert-manager ([0072083](https://github.com/Thomas-3145/homelab/commit/007208313b431e76470eef861630a6f5399d070f))
* **terraform:** create 3x k3s control plane VMs with Proxmox ([933b57f](https://github.com/Thomas-3145/homelab/commit/933b57f3aa0ad4685d87522aa3c1882577796681))
* **terraform:** ta till en ny VM för att kunna ha till skolan ([fc8016e](https://github.com/Thomas-3145/homelab/commit/fc8016e4972e5473291329ee1a39afea1eded742))
* testar nya hooks ([78544c4](https://github.com/Thomas-3145/homelab/commit/78544c4555dc077503b1784e3b6d3a4b4cf3d6a2))

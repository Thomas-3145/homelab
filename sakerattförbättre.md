# Saker att förbättra – XPS och homelab

Senast granskad: 2026-08-04

Detta dokument sammanfattar en skrivskyddad granskning av XPS-datorn,
shellmiljön, homelab-repot, Proxmox-värdarna och Kubernetes-klustret. Inga
systeminställningar eller tjänster ändrades under granskningen.

## Sammanfattning

Miljön är överlag välbyggd och stabil i drift. Kubernetes-klustret är friskt,
GitOps-flödet fungerar och både hårdvara och resurser har god marginal. Den
viktigaste bristen är backupkedjan: Velero sparar Kubernetes-objekt men inte
innehållet i de persistenta volymerna. Proxmox-backupen behöver också
verifieras eftersom jobbet pekar på en PBS-lagring som inte visas som aktiv.

## Prioritering

| Prioritet | Problem | Konsekvens |
|---|---|---|
| Kritisk | Velero säkerhetskopierar inte PVC-data | Databaser och applikationsdata går inte att återställa från R2 |
| Kritisk | Proxmox-jobbet pekar på `pbs`, men lagringen syns inte i `pvesm status` | VM- och LXC-backuper kan saknas |
| Hög | Fedora-brandväggen tillåter TCP/UDP 1025–65535 på Wi-Fi | Stor angreppsyta på främmande nät |
| Hög | TuneD och TLP har båda påverkat energistyrningen | Inställningarna är inte deterministiska |
| Hög | Traefik kör parallellt med ingress-nginx | Konfigurationsdrift och onödig exponering |
| Hög | GitHub Actions har tio raka misslyckade körningar | Ändringar saknar fungerande kvalitetsgrind |
| Medel | DNS-konfigurationen överskrider Kubernetes gräns på tre nameservers | Kontinuerliga varningar och onödigt brus |
| Medel | pve3 har en oanvänd 30 GB swapfil | Onödigt utnyttjat diskutrymme |

## Det som redan är bra

### XPS

- Fedora 43 med aktuell kärna.
- 32 GiB RAM, cirka 23 GiB tillgängligt vid granskningen.
- Endast cirka 17 procent av systemdisken används.
- Batterihälsa cirka 95 procent.
- Laddgränserna 75–80 procent är bra för batteriets livslängd.
- BIOS är aktuellt.
- SELinux kör i `Enforcing`.
- Inga systemtjänster var markerade som failed.
- Grafisk uppstart tar cirka 12,7 sekunder.

### Homelab

- Proxmox-klustret har tre noder och var quorate.
- Alla sex k3s-noder var `Ready`.
- Alla Argo CD-appar var `Synced` och `Healthy`.
- Alla Longhorn-volymer var `healthy`.
- Alla cert-manager-certifikat var `Ready`.
- CPU-belastningen i klustret var låg.
- Proxmox-värdarna har gott om RAM och lagringsmarginal.
- Terraform-state och riktiga `tfvars` är ignorerade och inte Git-spårade.
- Hemligheter i repot är SOPS-krypterade.

### Zsh och egna skript

- `.zshrc` är versionshanterad via symlink till dotfiles-repot.
- Zsh-syntaxkontrollen passerar.
- Shellcheck hittade inga allvarliga fel i de egna shellskripten.
- Shellstart tar cirka 0,15–0,16 sekunder.
- Docker-rensning med volymer kräver redan en tydlig bekräftelse.
- Domänspecifika funktioner har börjat delas upp i moduler.

## 1. Reparera Kubernetes-backupen

### Nuläge

Minst de senaste tolv nattliga Velero-jobben är `PartiallyFailed` med tio fel
vardera. Senaste granskade jobbet sparade 1 180 Kubernetes-objekt, men inte
innehållet i de åtta persistenta volymerna.

Berörda data omfattar bland annat:

- Authentik PostgreSQL
- Ghost
- ibindex PostgreSQL
- Loki
- Stirling PDF
- Vaultwarden
- vcluster
- Vikunja

Orsaker:

- CSI snapshot-API och `VolumeSnapshotClass` saknas.
- Pod-volume-backup är bortvald för PVC:erna.
- `snapshotMoveData` är `false`.
- Longhorns backup target är tom och rapporterar `Available=false`.
- Longhorn-volymerna har ingen registrerad senaste backup.

Det innebär att en restore kan återskapa Kubernetes-resurserna men ge tomma
volymer.

### Åtgärder

- [ ] Välj backupmetod för volymdata:
  - Velero node-agent/filesystem-backup, eller
  - CSI snapshots med korrekt snapshot-controller, CRD:er,
    `VolumeSnapshotClass` och data mover.
- [ ] Säkerställ att snapshotdata verkligen flyttas off-site till R2.
- [ ] Lägg inte enbart Longhorn-snapshots på samma kluster och kalla dem backup.
- [ ] Skapa en manuell testbackup efter ändringen.
- [ ] Återställ minst Vaultwarden och en PostgreSQL-databas till ett separat
  namespace.
- [ ] Dokumentera RPO, RTO och restore-proceduren.
- [ ] Låt övervakningen larma även på `PartiallyFailed`, inte bara `Failed`.

## 2. Verifiera Proxmox/PBS-backup

Det finns ett dagligt Proxmox-jobb, `pbs-daily`, klockan 04:00. Jobbet pekar på
lagringen `pbs`, men `pbs` visades inte i `pvesm status` på pve1. Detta är en
stark indikation på att backupdestinationen saknas eller är frånkopplad.

- [ ] Kontrollera senaste `vzdump`-jobben i Proxmox GUI eller taskloggen.
- [ ] Återanslut/återskapa PBS-lagringen om den saknas.
- [ ] Kontrollera att samtliga VM:ar och LXC:er omfattas av jobbet.
- [ ] Kontrollera retention och prune-policy.
- [ ] Gör en testrestore av en liten VM eller LXC.
- [ ] Verifiera att PBS-datastore i sin tur har en separat kopia eller annan
  katastrofåterställningsstrategi.

## 3. Härda XPS-brandväggen

Den aktiva zonen `FedoraWorkstation` tillåter:

- SSH
- TCP 1025–65535
- UDP 1025–65535

Det är olämpligt för en laptop som kan anslutas till främmande Wi-Fi.

- [ ] Byt Wi-Fi-anslutningen till zonen `public`, eller skapa en egen strikt zon.
- [ ] Tillåt endast specifika tjänster och portar som faktiskt behövs.
- [ ] Överväg att begränsa SSH till Tailscale.
- [ ] Bind Rackpeek till localhost eller Tailscale-adressen i stället för
  `0.0.0.0:8080` om LAN-exponering inte behövs.
- [ ] Inaktivera Passim om lokal cachedelning inte används. Passim lyssnar på
  port 27500.
- [ ] Kontrollera brandväggen på nytt från en annan enhet på nätverket.

## 4. Förenkla energistyrningen på XPS

TuneD och TuneD-PPD körs, samtidigt som TLP tidigare har applicerat
inställningar. `tuned-adm verify` misslyckades. Därutöver finns egna tjänster
för CPU-effektgräns, cpupower och automatisk profilväxling.

- [ ] Välj en huvudlösning för energistyrning, lämpligen Fedora-standardens
  TuneD/TuneD-PPD.
- [ ] Inaktivera och avinstallera TLP om TuneD behålls.
- [ ] Ta bort `cpupower.service` om samma inställning hanteras av TuneD.
- [ ] Utvärdera om `power-profile-auto.service` behövs när målet alltid är
  `balanced`.
- [ ] Behåll bara den egna CPU-effektgränsen om temperatur- och
  prestandamätningar visar att den gör nytta.
- [ ] Kör `tuned-adm verify` efter förenklingen.
- [ ] Mät temperatur, fläktljud, batteritid och prestanda före och efter.

Det finns även återkommande resume-fel för Thunderbolt 3-kontrollerns xHCI:
`PCI post-resume error` och `HC died`. BIOS är redan aktuellt.

- [ ] Jämför beteendet mellan aktuell och föregående kärna.
- [ ] Testa utan anslutna Thunderbolt/USB-C-enheter.
- [ ] Samla en separat fellogg om problemet påverkar faktisk användning.

## 5. Ta bort Traefik-driften

Ingress-nginx kör på `192.168.10.200`, men Traefik har återkommit och kör på
`192.168.10.201`. Ingen kontrollplansnod har en aktiv `disable: traefik`-inställning.

Det finns redan en Ansible-playbook:
`ansible/playbooks/k3s/disable-traefik.yaml`.

Nuvarande playbook skriver dock ett helt nytt `/etc/rancher/k3s/config.yaml`.
Det kan radera andra k3s-inställningar.

- [ ] Ändra playbooken så att befintlig konfiguration bevaras eller hanteras
  fullständigt av Ansible.
- [ ] Lägg till `traefik` och `servicelb` under `disable` på alla servernoder.
- [ ] Rulla om en kontrollplansnod i taget.
- [ ] Ta bort Traefiks HelmChart-resurser först när inställningen är permanent.
- [ ] Bekräfta att samtliga Ingress-resurser använder ingress-nginx.
- [ ] Verifiera att LoadBalancer-IP `192.168.10.201` frigörs.

## 6. Rensa DNS-varningarna

Nodernas systemd-resolved-konfiguration genererar sex nameserver-rader:

- `1.1.1.1`
- `8.8.8.8`
- Tailscales IPv4- och IPv6-DNS via både `eth0` och `tailscale0`

Kubernetes använder högst tre och genererar därför kontinuerligt
`DNSConfigForming`.

- [ ] Skapa en dedikerad resolv.conf för k3s med högst tre nameservers.
- [ ] Ange filen som kubelet/k3s `resolv-conf` via Ansible.
- [ ] Behåll Tailscale DNS endast om poddar behöver MagicDNS.
- [ ] Kontrollera extern DNS och Tailscale-namn från en testpodd.
- [ ] Bekräfta att `DNSConfigForming`-events upphör.

## 7. Reparera CI och utvecklingsmiljön

GitHub Actions hade tio raka misslyckade körningar. Senaste körningen föll i
Ansible Lint medan Terraform, YAML, kubeconform och Trivy passerade.

Observerade CI-problem:

- Saknade `community.docker` och `ansible.posix` i requirements.
- Tasks utan namn.
- Tasks som bör vara handlers.
- Syntaxkontroll som faller för vissa k3s-playbooks.
- Kubernetes-Trivy använder `exit-code: 0` och stoppar därför aldrig CI.
- Trivy-action använder den rörliga taggen `@master`.
- Terraform CI testar Proxmox men inte `terraform/lia`.

Lokalt är Ansible-miljön också blandad: CLI 2.20.2 laddar en Python-modul från
Ansible 2.18.18rc1.

- [ ] Skapa en projektspecifik venv eller ett isolerat `uv tool`-upplägg.
- [ ] Lås kompatibla versioner av `ansible-core`, `ansible-lint` och collections.
- [ ] Lägg till `community.docker` och `ansible.posix` i
  `ansible/requirements.yaml`.
- [ ] Reparera återstående ansible-lint-fel.
- [ ] Lägg till Terraform fmt/validate för `terraform/lia`.
- [ ] Versionshantera `.terraform.lock.hcl`; den ignoreras i dagsläget.
- [ ] Fäst GitHub Actions till stabila versioner eller commit-SHA.
- [ ] Bestäm om HIGH/CRITICAL Trivy-fynd i Kubernetes ska stoppa CI.
- [ ] Lägg till en riktig Kustomization-rendering i CI.

Lokala `main` var sex commits före `origin/main` vid granskningen. Det förklarar
varför de senaste lokala ändringarna ännu inte hade fått nya CI-körningar.

## 8. Reparera bootstrap-dokumentationen

README anger:

```bash
kubectl apply -k kubernetes/bootstrap/
```

Kommandot fungerar inte eftersom katalogen saknar `kustomization.yaml`.

- [ ] Lägg till `kubernetes/bootstrap/kustomization.yaml` med `kube-vip.yaml`
  och `root-app.yaml`, eller ändra dokumentationen till två explicita
  `kubectl apply -f`-kommandon.
- [ ] Testa bootstrap från en ren miljö.

## 9. Proxmox-underhåll

- [ ] Uppdatera pve1, pve2 och pve3 en i taget så att quorum behålls.
- [ ] Verifiera kluster, gäster och lagring efter varje omstart.
- [ ] Kontrollera varför `corosync-qdevice.service` är enabled men trasig på
  pve3. Felet är `Can't read quorum.device.model cmap key`.
- [ ] Konfigurera qdevice korrekt på hela klustret eller ta bort den övergivna
  tjänsten.
- [ ] Ta bort eller minska pve3:s oanvända 30 GB swapfil efter verifiering.
  pve3 har dessutom en 8 GB swap-partition och använde ingen swap vid
  granskningen.
- [ ] Uppdatera k3s-VM:arna; de hade 4–9 väntande Ubuntu-paket.

## 10. Kubernetes-resurser

Vid granskningen saknade 130 containrar kompletta CPU-/minnes-requests.
Merparten kom från charts och systemkomponenter:

- Longhorn: 69
- MetalLB: 25
- Monitoring: 20
- Argo CD: 7
- kube-system: 5
- cert-manager: 3
- Velero: 1

Minnesanvändning per nod låg ungefär på:

- cp-01: 52 procent
- cp-02: 69 procent
- cp-03: 67 procent
- worker-01: 37 procent
- worker-02: 26 procent
- worker-03: 75 procent

- [ ] Sätt requests och limits för de egna applikationerna först.
- [ ] Undvik att mekaniskt skriva över vendors rimliga chart-standarder.
- [ ] Undersök varför worker-03 får oproportionerligt mycket last.
- [ ] Överväg att öka k3s-VM:arna från 6 till 8 GiB RAM; Proxmox-värdarna har
  kapacitet.
- [ ] Testa om klustret kan flytta workloads när en worker är nere.

## 11. Förbättra zsh-konfigurationen

Aktiv `.zshrc`:
`~/dev/dotfiles/zsh/.zshrc` – cirka 814 rader.

### Viktigast

- [ ] Ta bort automatisk `source` av `.venv/bin/activate`. Ett främmande repo
  kan annars exekvera kod bara genom att användaren går in i katalogen.
- [ ] Använd `direnv` och explicit `direnv allow` för projektmiljöer.
- [ ] Ersätt aliaset `reload="source ~/.zshrc"` med `exec zsh` för att undvika
  dubbla hooks och upprepad kube-prompt.
- [ ] Flytta hårdkodade IP-adresser och `root@...` till SSH-config och inventory.
- [ ] Skicka argument till remote-skript som riktiga argument i stället för att
  bygga shellsträngar.
- [ ] Begränsa tillåtna tecken i studieplugg-funktionerna; `&` och `?` är
  olämpliga i vissa remote-shellkontexter.

### Struktur

- [ ] Fortsätt dela upp filen, exempelvis:
  - `00-env.zsh`
  - `10-tools.zsh`
  - `20-git.zsh`
  - `30-docker.zsh`
  - `40-kubernetes.zsh`
  - `50-homelab.zsh`
  - `60-studieplugg.zsh`
  - `70-lia.zsh`
  - `90-hooks.zsh`
- [ ] Gör PATH unik med `typeset -U path PATH`.
- [ ] Flytta login-miljövariabler till `.zprofile` och behåll interaktiva
  aliases/funktioner i `.zshrc`.
- [ ] Ersätt Python-baserade `kalkylator` med exempelvis `bc`.
- [ ] Överväg tydligare alias i stället för att ersätta standardkommandon som
  `cat`, `top` och `nano`.
- [ ] Lägg till `zsh -n` och Shellcheck i dotfiles-repots CI.
- [ ] Kontrollera ntfy-autentisering och använd ett svårgissat topic om
  anonyma prenumerationer tillåts.

Oh My Zsh och ssh-agent-pluginen står för huvuddelen av starttiden, men en
shellstart på cirka 0,15 sekunder är redan bra. Prestandaoptimering här har låg
prioritet jämfört med säkerhet och underhållbarhet.

## 12. Mjukvarustädning på XPS

Docker hade ungefär följande återvinningsbara data:

- 5,7 GB build-cache
- 4,5 GB images
- 551 MB stoppade containrar
- 3,3 GB potentiellt återvinningsbara volymer

- [ ] Rensa stoppade containrar och build-cache efter kontroll.
- [ ] Radera inte Docker-volymer utan att först identifiera ägare och innehåll.
- [ ] Bestäm om både Docker och Podman behövs.
- [ ] Bestäm om både GNOME Boxes och virt-manager behövs.
- [ ] Avinstallera libvirt/QEMU eller Wine endast om de inte används i studier
  eller labb.
- [ ] Installera väntande Fedora/NSS/Docker Compose-uppdateringar.
- [ ] Reparera Tailscale-repots GPG-nyckel.
- [ ] Installera väntande Secure Boot dbx-uppdatering.
- [ ] Planera uppgradering från Fedora 43 före supportslut 2026-12-02.

## Rekommenderad arbetsordning

1. Reparera Velero och gör en riktig restoreövning.
2. Verifiera och reparera Proxmox/PBS-backupen.
3. Härda XPS-brandväggen och begränsa exponerade tjänster.
4. Förenkla TuneD/TLP/cpupower-konfigurationen.
5. Gör Traefik-avstängningen permanent och lös DNS-varningarna.
6. Reparera CI och den lokala Ansible-miljön.
7. Uppdatera Proxmox, k3s-noderna och XPS:en kontrollerat.
8. Förbättra resource requests och RAM-fördelning i klustret.
9. Strukturera om zsh-konfigurationen.
10. Rensa oanvänd mjukvara och Docker-cache.

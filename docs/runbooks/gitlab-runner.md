# GitLab Runner — Runbook

VM: `gitlab-runner` (192.168.10.30, pve2, VM ID 101)
SSH: `ssh -p 22456 ubuntu@192.168.10.30`

## 1. Provision VM

```bash
cd homelab/terraform/proxmox
terraform apply
```

## 2. Configure VM (Docker + GitLab Runner)

```bash
cd homelab/ansible
ansible-galaxy collection install -r requirements.yaml
ansible-playbook -i inventory/hosts.yaml playbooks/gitlab-runner.yaml
```

## 3. Register runner against a project

In GitLab: **Settings → CI/CD → Runners → New project runner**
Select "Run untagged jobs", copy the token, then SSH in and run:

```bash
ssh -p 22456 ubuntu@192.168.10.30

sudo gitlab-runner register \
  --url https://git.chas-lab.dev \
  --token <token> \
  --executor docker \
  --docker-image docker:latest \
  --docker-privileged
```

Repeat for each project (veckojournal, nerds-and-norrmies, etc.).

## 4. Verify

```bash
sudo gitlab-runner list
sudo gitlab-runner status
```

## Troubleshooting

### Docker-in-Docker fails with "mount: permission denied" / "Cannot connect to Docker daemon"

`--docker-privileged` during `register` does not always persist to `config.toml`. Check and fix manually:

```bash
sudo grep privileged /etc/gitlab-runner/config.toml
# Should show: privileged = true
# If false, fix:
sudo sed -i 's/privileged = false/privileged = true/g' /etc/gitlab-runner/config.toml
sudo gitlab-runner restart
```

### `.gitlab-ci.yml` must disable TLS for DinD and set alias

```yaml
services:
  - name: docker:dind
    alias: docker

variables:
  DOCKER_TLS_CERTDIR: ""
  DOCKER_HOST: tcp://docker:2375
```

## Notes

- Runner uses Docker executor with Docker-in-Docker (privileged) for `docker build/push`
- CI/CD variables `DOCKER_USERNAME` and `DOCKER_PASSWORD` must be set per project in GitLab
- `DOCKER_PASSWORD` should be a Docker Hub Personal Access Token (not your password)

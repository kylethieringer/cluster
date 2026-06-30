# 01 · Getting started on Hyak

Goal: go from "no account" to "I can log in and submit a job" on **Hyak Klone**, UW's
SLURM-based HPC cluster. Official docs: <https://hyak.uw.edu/docs/>.

## 1. Get an account

Hyak uses a *condo model*: research groups buy in, and members of those groups get access.

- If your lab/PI already has a Hyak allocation, ask them (or `help@uw.edu`) to **add your UW
  NetID** to the group.
- If your group has no allocation, you can still run on the free, preemptible **`ckpt-all`**
  partition (idle nodes contributed by other groups). See [04-running-inference.md](04-running-inference.md).
- Account requests / details: <https://hyak.uw.edu/docs/account/start>.

## 2. Log in

```bash
ssh <UWNetID>@klone.hyak.uw.edu
```

You will be prompted for your UW password and **2-factor (Duo)** authentication. SSH details:
<https://hyak.uw.edu/docs/setup/ssh>.

> **Tip:** set up an SSH key and a `~/.ssh/config` entry so you don't retype host/user. You
> will still do Duo.

## 3. Login nodes vs. compute nodes — read this

When you SSH in you land on a **login node**. Login nodes are shared and for light work only
(editing files, submitting jobs, small transfers). **Do not run inference, training, or any
heavy/long process on a login node** — Hyak's `arbiter2` monitor will throttle or kill it, and
it degrades the cluster for everyone.

All real work runs on **compute nodes**, reached by submitting jobs to SLURM:
- `sbatch` — submit a batch job (how this repo runs inference).
- `salloc` — get an interactive session on a compute node (good for testing).

## 4. Find your account and partitions

You need an **account** (`-A`) and a **partition** (`-p`) to submit jobs.

```bash
groups            # the accounts/groups you belong to (use one as -A)
hyakalloc         # your groups' allocations and current usage
sinfo -s          # partitions and node availability
```

Common GPU partitions on Klone include `gpu-a100` and `gpu-l40s`; `ckpt-all` runs on idle GPUs
for free but jobs can be **preempted** (interrupted and requeued). Scheduling docs:
<https://hyak.uw.edu/docs/compute/scheduling-jobs>.

Put the account and partition you choose into [`config/inference.yaml`](../config/inference.yaml).

## 5. Get this repo onto the cluster

Clone into your group's `gscratch` space (not your small home directory):

```bash
cd /gscratch/<group>/<UWNetID>
```

If the repo is **public**, you can clone read-only with no setup:

```bash
git clone https://github.com/kylethieringer/cluster.git
```

To push changes back, you need to authenticate. Pick one of the two options below.

### Option A — SSH key (recommended for ongoing work)

Generate a key **on the cluster** (this is separate from any key you use to log into Hyak),
then add the public half to GitHub.

```bash
# 1. Generate a key (press Enter through the prompts to accept defaults)
ssh-keygen -t ed25519 -C "<your-github-email>"

# 2. Print the PUBLIC key and copy the whole line
cat ~/.ssh/id_ed25519.pub
```

Add it on GitHub: **Settings → SSH and GPG keys → New SSH key**, paste the public key, save.
Then test and clone over SSH:

```bash
ssh -T git@github.com            # should greet you by username
git clone git@github.com:kylethieringer/cluster.git
```

> Never share or paste the **private** key (`~/.ssh/id_ed25519`, no `.pub`). Only the `.pub`
> file goes to GitHub.

### Option B — HTTPS + Personal Access Token

If you'd rather not use keys, clone over HTTPS and authenticate with a **Personal Access
Token** (GitHub no longer accepts your account password). Create one at **Settings → Developer
settings → Personal access tokens** with `repo` (or fine-grained Contents) scope, then:

```bash
git clone https://github.com/kylethieringer/cluster.git
# Username: your GitHub username
# Password: paste the token (not your GitHub password)

# Optional: cache it so you don't re-enter it each time
git config --global credential.helper 'cache --timeout=3600'
```

## Next

→ [02-storage-and-data.md](02-storage-and-data.md): where to put videos, models, and outputs,
and how to copy data onto the cluster.

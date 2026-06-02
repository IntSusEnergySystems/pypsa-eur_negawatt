# SPDX-License-Identifier: MIT
# Shared configuration for the NIC5 (CECI) cluster workflow.
# Sourced by cluster/nic5.sh. Edit these to match your account/cluster.

# --- SSH / paths -------------------------------------------------------------
# SSH host alias (must be defined in ~/.ssh/config, reachable via the CECI VPN).
REMOTE="${REMOTE:-nic5}"
# Working directory on the cluster (use GLOBALSCRATCH, NOT $HOME).
REMOTE_DIR="${REMOTE_DIR:-/scratch/ulg/thermlab/squoilin/pypsa-eur_negawatt}"

# Cluster workflow is headless. Override ~/.ssh/config ForwardX11=yes to avoid
# "No xauth data" warnings without loading modules or setting up xauth.
SSH_OPTS="${SSH_OPTS:--o ForwardX11=no}"

# --- conda environment on the cluster ---------------------------------------
CONDA_ROOT="${CONDA_ROOT:-\$HOME/miniforge3}"   # installed by `nic5.sh setup`
ENV_NAME="${ENV_NAME:-pypsa-eur}"

# Gurobi licence file (token server). Set by `nic5.sh setup`; the module's
# licence is copied to ~/gurobi.lic so no `module load` is needed in jobs.
GUROBI_LIC="${GUROBI_LIC:-\$HOME/gurobi.lic}"
# Path to the cluster Gurobi module licence (source for the copy above).
GUROBI_MODULE_LIC="${GUROBI_MODULE_LIC:-/opt/cecisw/arch/easybuild/2023b/software/Gurobi/13.0.0-GCCcore-13.2.0/gurobi.lic}"

# --- Slurm resources --------------------------------------------------------
# Snakemake runs on the login node and submits each rule to Slurm. Solve-job
# CPUs and Gurobi threads are set in cluster/config_cluster.yaml (solving.cpus
# and matching solver_options threads). See the README job-efficiency section:
# https://support.ceci-hpc.be/doc/SubmittingJobs/JobEfficiency/
SOLVE_PARTITION="${SOLVE_PARTITION:-hmem}"
SOLVE_RUNTIME="${SOLVE_RUNTIME:-1440}"   # minutes
DEFAULT_PARTITION="${DEFAULT_PARTITION:-hmem}"   # all cluster jobs use hmem
DEFAULT_MEM_MB="${DEFAULT_MEM_MB:-16000}"      # light rules (add_brownfield)
DEFAULT_RUNTIME="${DEFAULT_RUNTIME:-180}"
DEFAULT_CPUS="${DEFAULT_CPUS:-1}"              # light rules only; never set globally for solve
MAX_SLURM_JOBS="${MAX_SLURM_JOBS:-2}"

# --- scenarios & planning horizons ------------------------------------------
SCENARIOS="${SCENARIOS:-ref suff}"   # used by `prepare` only (both scenarios)
HORIZONS="${HORIZONS:-2030 2040 2050}"
CLUSTERS="${CLUSTERS:-adm}"
OPTS="${OPTS:-}"             # electricity opts wildcard (empty in both configs)

# --- local conda invocation --------------------------------------------------
# How to run the local environment (used by `nic5.sh prepare`).
LOCAL_RUN="${LOCAL_RUN:-conda run -n pypsa-eur}"
LOCAL_CORES="${LOCAL_CORES:-8}"

# SPDX-License-Identifier: MIT
# Shared configuration for the NIC5 (CECI) cluster workflow.
# Sourced by cluster/nic5.sh. Edit these to match your account/cluster.

# --- SSH / paths -------------------------------------------------------------
# SSH host alias (must be defined in ~/.ssh/config, reachable via the CECI VPN).
REMOTE="${REMOTE:-nic5}"
# Working directory on the cluster (use GLOBALSCRATCH, NOT $HOME).
REMOTE_DIR="${REMOTE_DIR:-/scratch/ulg/thermlab/squoilin/pypsa-eur_negawatt}"

# --- conda environment on the cluster ---------------------------------------
CONDA_ROOT="${CONDA_ROOT:-\$HOME/miniforge3}"   # installed by `nic5.sh setup`
ENV_NAME="${ENV_NAME:-pypsa-eur}"

# Gurobi licence file (token server). Set by `nic5.sh setup`; the module's
# licence is copied to ~/gurobi.lic so no `module load` is needed in jobs.
GUROBI_LIC="${GUROBI_LIC:-\$HOME/gurobi.lic}"
# Path to the cluster Gurobi module licence (source for the copy above).
GUROBI_MODULE_LIC="${GUROBI_MODULE_LIC:-/opt/cecisw/arch/easybuild/2023b/software/Gurobi/13.0.0-GCCcore-13.2.0/gurobi.lic}"

# --- Slurm resources --------------------------------------------------------
# Snakemake runs on the login node (which has internet, needed to resolve the
# data-retrieval storage providers at DAG-build time) and submits each rule as
# a Slurm job via the built-in slurm executor. The heavy solve runs on hmem;
# the light add_brownfield steps run on the default partition.
SOLVE_PARTITION="${SOLVE_PARTITION:-hmem}"
SOLVE_MEM_MB="${SOLVE_MEM_MB:-900000}"   # hmem nodes ~1 TB; 1h runs are memory heavy
SOLVE_RUNTIME="${SOLVE_RUNTIME:-1440}"   # minutes (max walltime is 2 days)
# cpus-per-task for the solve is taken from the rule's `threads` (= solver
# threads, 20 by default), so it does not need to be set here.
DEFAULT_PARTITION="${DEFAULT_PARTITION:-batch}"
DEFAULT_MEM_MB="${DEFAULT_MEM_MB:-80000}"
DEFAULT_RUNTIME="${DEFAULT_RUNTIME:-180}"
DEFAULT_CPUS="${DEFAULT_CPUS:-8}"
MAX_SLURM_JOBS="${MAX_SLURM_JOBS:-4}"

# --- scenarios & planning horizons ------------------------------------------
SCENARIOS="${SCENARIOS:-ref suff}"
HORIZONS="${HORIZONS:-2030 2040 2050}"
CLUSTERS="${CLUSTERS:-adm}"
OPTS="${OPTS:-}"             # electricity opts wildcard (empty in both configs)

# --- local conda invocation --------------------------------------------------
# How to run the local environment (used by `nic5.sh prepare`).
LOCAL_RUN="${LOCAL_RUN:-conda run -n pypsa-eur}"
LOCAL_CORES="${LOCAL_CORES:-8}"

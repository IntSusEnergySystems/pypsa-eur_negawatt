#!/bin/bash
# SPDX-License-Identifier: MIT
###############################################################################
# nic5.sh  -  Run the PyPSA-Eur Negawatt optimisation on the NIC5/CECI cluster
#
# Strategy: heavy LP solving runs on NIC5 (hmem node + Gurobi), everything else
# stays local. The (small) un-solved networks are prepared LOCALLY, transferred
# to the cluster, the myopic solve chain runs there, and the solved networks are
# pulled back.
#
# Execution model: Snakemake runs on the NIC5 *login* node and submits each rule
# to Slurm via its built-in slurm executor. This matters because NIC5 compute
# nodes have no internet, while Snakemake must reach the data-retrieval storage
# providers when it builds the DAG -- which it does on the login node. The
# compute nodes then only run the solve script (Gurobi via the token server).
#
#   ./cluster/nic5.sh setup            # one-time: install env on the cluster
#   ./cluster/nic5.sh run 1h           # full test: prepare+push+solve+wait+pull
#
# or step by step:
#   ./cluster/nic5.sh prepare 1h       # LOCAL: build un-solved inputs @1h
#   ./cluster/nic5.sh push             # rsync code+inputs to the cluster
#   ./cluster/nic5.sh solve 1h         # submit ref+suff solve jobs (Slurm)
#   ./cluster/nic5.sh status           # squeue + tail logs
#   ./cluster/nic5.sh wait             # block until jobs finish
#   ./cluster/nic5.sh pull             # rsync solved results back
#
# The time resolution (e.g. 1h, 6h, 24h) is passed as the Snakemake
# `sector_opts` wildcard, so NO config file is edited and local runs are
# unaffected.
###############################################################################
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
# shellcheck source=config.sh
source "$HERE/config.sh"
JOBFILE="$HERE/.last_jobs"
mkdir -p "$HERE/logs"

msg()  { printf '\033[1;34m[nic5]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[nic5] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Build the list of solved-network targets for one scenario / resolution.
solved_targets() {
    local sc=$1 res=$2 y
    for y in $HORIZONS; do
        echo "results/${sc}/networks/base_s_${CLUSTERS}_${OPTS}_${res}_${y}.nc"
    done
}

# Build the list of LOCAL prepare targets (un-solved solve inputs) for a scenario.
prepare_targets() {
    local sc=$1 res=$2 y first
    first=$(echo "$HORIZONS" | awk '{print $1}')
    # first horizon: brownfield from add_existing_baseyear (needs no solve)
    echo "resources/${sc}/networks/base_s_${CLUSTERS}_${OPTS}_${res}_${first}_brownfield.nc"
    # later horizons: prepared (un-solved) base networks
    for y in $HORIZONS; do
        [ "$y" = "$first" ] && continue
        echo "resources/${sc}/networks/base_s_${CLUSTERS}_${OPTS}_${res}_${y}.nc"
    done
    # co2 totals (resolution independent, but make sure they exist)
    for y in $HORIZONS; do
        echo "resources/${sc}/co2_totals_s_${CLUSTERS}_${y}.csv"
    done
}

cmd_prepare() {
    local res=${1:?usage: prepare <resolution e.g. 1h>}
    for sc in $SCENARIOS; do
        msg "Preparing un-solved inputs for '$sc' @ $res (local)"
        # shellcheck disable=SC2046
        ( cd "$REPO" && $LOCAL_RUN snakemake \
            --snakefile "Snakefile_${sc}" \
            --cores "$LOCAL_CORES" \
            --rerun-triggers mtime \
            -- $(prepare_targets "$sc" "$res") )
    done
    msg "Local preparation complete."
}

cmd_push() {
    msg "Syncing repo + inputs to ${REMOTE}:${REMOTE_DIR}"
    ssh "$REMOTE" "mkdir -p '$REMOTE_DIR'"
    # Everything except the build-only Atlite cutout (several GB, never read by
    # the solve chain) is transferred. Keeping the rest of data/ avoids missing
    # intermediate inputs that would otherwise make Snakemake try to rebuild
    # (and download) upstream rules on the compute node, which has no internet.
    # rsync preserves mtimes, so the pre-built prepared networks stay "current"
    # and only the solve chain runs. The first push is slow (~4 GB over the
    # VPN); subsequent pushes are incremental and fast.
    rsync -arh --no-g -e ssh \
        --exclude '.git' --exclude '.snakemake' --exclude '.pixi' \
        --exclude 'results' --exclude '__pycache__' --exclude '*.pyc' \
        --exclude 'cluster/logs' --exclude 'cutouts' --exclude 'data/cutout' \
        "$REPO/" "${REMOTE}:${REMOTE_DIR}/"
    # Ship Snakemake's provenance metadata too: without it the compute node
    # falls back to raw filesystem mtimes and would consider locally-built
    # resources stale (triggering rebuilds/downloads). With it, only the solve
    # chain runs.
    if [ -d "$REPO/.snakemake/metadata" ]; then
        ssh "$REMOTE" "mkdir -p '$REMOTE_DIR/.snakemake'"
        rsync -arh --no-g -e ssh "$REPO/.snakemake/metadata" "${REMOTE}:${REMOTE_DIR}/.snakemake/"
    fi
    msg "Push complete."
}

# Remote shell prologue: activate the conda env and wire up the Gurobi licence.
REMOTE_ENV='source $HOME/miniforge3/etc/profile.d/conda.sh && conda activate '"$ENV_NAME"' && unset PYTHONPATH && export GRB_LICENSE_FILE=$HOME/gurobi.lic'

cmd_solve() {
    local res=${1:?usage: solve <resolution e.g. 1h>}
    : > "$JOBFILE"
    for sc in $SCENARIOS; do
        msg "Launching Slurm orchestrator on the login node: scenario=$sc resolution=$res"
        local targets log pidf
        targets=$(solved_targets "$sc" "$res" | tr '\n' ' ')
        log="cluster/logs/orchestrate_${sc}_${res}.log"
        pidf="cluster/logs/orchestrate_${sc}_${res}.pid"
        # setsid fully detaches the orchestrator into its own session so the ssh
        # call returns immediately; the orchestrator keeps running on the login
        # node and writes its PID to a pidfile.
        ssh "$REMOTE" "cd '$REMOTE_DIR' && $REMOTE_ENV && \
            setsid bash -c 'snakemake --snakefile Snakefile_${sc} \
                --executor slurm --jobs $MAX_SLURM_JOBS \
                --rerun-triggers mtime --keep-going --printshellcmds --nolock \
                --default-resources slurm_partition=$DEFAULT_PARTITION runtime=$DEFAULT_RUNTIME mem_mb=$DEFAULT_MEM_MB cpus_per_task=$DEFAULT_CPUS \
                --set-resources solve_sector_network_myopic:slurm_partition=$SOLVE_PARTITION solve_sector_network_myopic:mem_mb=$SOLVE_MEM_MB solve_sector_network_myopic:runtime=$SOLVE_RUNTIME \
                -- $targets </dev/null >\"$log\" 2>&1 & echo \$! >\"$pidf\"' </dev/null >/dev/null 2>&1"
        sleep 2
        pid=$(ssh "$REMOTE" "cat '$REMOTE_DIR/$pidf' 2>/dev/null" | tr -d '[:space:]')
        echo "$sc $res ${pid:-unknown}" >> "$JOBFILE"
        msg "  orchestrator pid ${pid:-unknown} for $sc (log: $log)"
    done
    msg "Orchestrators launched. Track with: $0 status"
}

cmd_status() {
    msg "Slurm queue on $REMOTE (squeue --me):"
    ssh "$REMOTE" "squeue --me --format='%.18i %.10P %.26j %.8T %.10M %R'" 2>/dev/null
    [ -f "$JOBFILE" ] || return 0
    while read -r sc res pid; do
        echo
        if ssh "$REMOTE" "kill -0 $pid" 2>/dev/null; then
            msg "--- orchestrator $sc (pid $pid: RUNNING) ---"
        else
            msg "--- orchestrator $sc (pid $pid: finished) ---"
        fi
        ssh "$REMOTE" "grep -vE 'Lmod|Try: |module\(s\)|Python/3.7.4' '$REMOTE_DIR/cluster/logs/orchestrate_${sc}_${res}.log' 2>/dev/null | tail -n 12 || echo '(no log yet)'"
    done < "$JOBFILE"
}

cmd_wait() {
    [ -f "$JOBFILE" ] || die "no orchestrators recorded ($JOBFILE missing)"
    msg "Waiting for orchestrators to finish..."
    while true; do
        local alive=0
        while read -r sc res pid; do
            ssh "$REMOTE" "kill -0 $pid" 2>/dev/null && alive=$((alive+1))
        done < "$JOBFILE"
        [ "$alive" -eq 0 ] && break
        printf '\r[nic5] %s orchestrator(s) still running... %s' "$alive" "$(date +%H:%M:%S)"
        sleep 60
    done
    printf '\n'
    msg "All orchestrators finished. Per-scenario outcome:"
    while read -r sc res pid; do
        if ssh "$REMOTE" "grep -qE 'Nothing to be done|steps \(100%\) done|Complete log' '$REMOTE_DIR/cluster/logs/orchestrate_${sc}_${res}.log'" 2>/dev/null; then
            msg "  $sc: OK"
        else
            msg "  $sc: CHECK LOG (cluster/logs/orchestrate_${sc}_${res}.log) -- may have errors"
        fi
    done < "$JOBFILE"
}

cmd_pull() {
    msg "Pulling results + logs from cluster"
    mkdir -p "$REPO/results" "$HERE/logs"
    rsync -arh --no-g --info=progress2 -e ssh \
        "${REMOTE}:${REMOTE_DIR}/results/" "$REPO/results/" \
        || msg "(no results dir yet)"
    rsync -arh --no-g -e ssh \
        "${REMOTE}:${REMOTE_DIR}/cluster/logs/" "$HERE/logs/" || true
    msg "Pull complete. Solved networks are in results/<scenario>/networks/."
}

cmd_setup() {
    msg "One-time cluster setup on $REMOTE"
    ssh "$REMOTE" "mkdir -p '$REMOTE_DIR'"
    rsync -arh --no-g -e ssh "$HERE/cluster_setup.sh" "${REMOTE}:${REMOTE_DIR}/cluster/cluster_setup.sh"
    rsync -arh --no-g -e ssh "$REPO/envs/environment.yaml" "${REMOTE}:${REMOTE_DIR}/envs/environment.yaml"
    ssh "$REMOTE" "bash '$REMOTE_DIR/cluster/cluster_setup.sh'"
    msg "Setup finished."
}

cmd_run() {
    local res=${1:?usage: run <resolution e.g. 1h>}
    cmd_prepare "$res"
    cmd_push
    cmd_solve "$res"
    cmd_wait
    cmd_pull
}

cmd_shell() { ssh -t "$REMOTE" "cd '$REMOTE_DIR'; exec bash -l"; }

case "${1:-}" in
    setup)   shift; cmd_setup "$@";;
    prepare) shift; cmd_prepare "$@";;
    push)    shift; cmd_push "$@";;
    solve)   shift; cmd_solve "$@";;
    status)  shift; cmd_status "$@";;
    wait)    shift; cmd_wait "$@";;
    pull)    shift; cmd_pull "$@";;
    run)     shift; cmd_run "$@";;
    shell)   shift; cmd_shell "$@";;
    *) cat <<EOF
Usage: $0 <command> [resolution]
  setup              one-time: install conda env + Gurobi licence on the cluster
  prepare <res>      LOCAL: build un-solved solve inputs at <res> (e.g. 1h)
  push               rsync code + inputs to the cluster (scratch)
  solve <res>        submit ref+suff solve jobs on the hmem partition
  status             show queue and tail job logs
  wait               block until all submitted jobs finish
  pull               rsync solved results back into ./results
  run <res>          prepare + push + solve + wait + pull  (end to end)
  shell              open an interactive shell in the cluster repo
EOF
       exit 1;;
esac

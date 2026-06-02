# PyPSA-Eur Negawatt Belgium

A sector-coupled energy system optimisation model for Belgium and its neighbours,
built on top of [PyPSA-Eur](https://github.com/PyPSA/pypsa-eur).

This repository implements the **Negawatt Belgium** scenarios, studying two contrasting
energy transition pathways to 2050 for Belgium, Germany, France, Great Britain, and
the Netherlands.

## Authors

**Sylvain Quoilin** and **Umair Tareen**  
[University of Liège](https://www.uliege.be) — Energy Systems Research Unit (ESRU)

## Acknowledgements

This work is based on [PyPSA-Eur v2025.07.0](https://github.com/PyPSA/pypsa-eur), an
open-source sector-coupled energy model of the European energy system. Please cite
the original model if you use this repository:

> T. Brown, J. Hörsch, D. Schlachtberger, *PyPSA-Eur: An Open Optimisation Model
> of the European Transmission System*, 2018,
> [arXiv:1806.01613](https://arxiv.org/abs/1806.01613).

## Scenarios

Two scenarios are implemented, each run for planning horizons **2030, 2040, 2050**
using myopic foresight:

| Parameter | `ref` (Reference) | `suff` (Sufficiency) |
|---|---|---|
| Snakefile | `Snakefile_ref` | `Snakefile_suff` |
| Config file | `config/config_ref.yaml` | `config/config_suff.yaml` |
| Demand profile | Standard PyPSA-Eur | Reduced demand (`suff_demand: true`) |
| District heating potential | Default | Disabled (`potential: 0.0`) |
| Countries | BE, DE, FR, GB, NL | BE, DE, FR, GB, NL |
| Spatial resolution | Administrative regions (`adm`) | Administrative regions (`adm`) |
| Temporal resolution | 6-hourly (1 460 snapshots/year) | 6-hourly (1 460 snapshots/year) |
| CO2 budget | National per-country (`co2_budget_national: true`) | National per-country |
| CCL constraint | Enabled | Enabled |

### Reference scenario (`ref`)

The reference scenario represents a cost-optimal decarbonisation pathway with
standard demand assumptions. It includes:

- Full sector coupling (electricity, heat, transport, industry, hydrogen)
- CO2 sequestration potential capped at 40 Mt in 2030, 180 Mt in 2040, 250 Mt in 2050
- Imposed constraints for Belgium: battery storage minimum (4 GWh in 2030),
  minimum electrolyser capacity (150 MW in 2030), DAC capacity limits in 2040/2050
- TYNDP-based transmission expansion constraints

### Sufficiency scenario (`suff`)

The sufficiency scenario assumes reduced energy demand consistent with sufficiency
policies. Key differences from the reference:

- Reduced end-use demands via `suff_demand: true`
- District heating potential set to zero (`potential: 0.0`)
- Otherwise identical modelling assumptions

## Repository Structure

```
.
├── Snakefile_ref           # Master workflow for the ref scenario
├── Snakefile_suff          # Master workflow for the suff scenario
├── Snakefile_master        # Shared master Snakefile (called by both above)
├── config/
│   ├── config_ref.yaml     # Configuration for the ref scenario
│   ├── config_suff.yaml    # Configuration for the suff scenario
│   └── config.default.yaml # Default PyPSA-Eur configuration (reference)
├── rules/                  # Snakemake rule definitions
│   ├── build_electricity.smk
│   ├── build_sector.smk
│   ├── solve_myopic.smk
│   ├── postprocess.smk
│   └── ...
├── scripts/                # Python scripts for each workflow step
│   ├── prepare_sector_network.py   # Network preparation (adds sector components)
│   ├── solve_network.py            # LP optimisation wrapper
│   └── ...
├── data/                   # Static input data
├── cutouts/                # Atlite weather cutouts (downloaded automatically)
├── resources/              # Intermediate build artefacts (generated)
└── results/                # Final solved networks and plots (generated)
```

## Installation

### Prerequisites

- [Pixi](https://pixi.sh) or [Conda/Mamba](https://conda.io) for environment management
- A valid [Gurobi licence](https://www.gurobi.com) (academic licence is sufficient)
- ~50 GB disk space for cutouts and intermediate files

### Environment setup

Using pixi (recommended):

```bash
pixi install
```

Or using conda with the provided environment file:

```bash
conda env create -f envs/environment.yaml
conda activate pypsa-eur
```

### Gurobi licence

The workflow is configured to use Gurobi. A free academic licence can be obtained at
<https://www.gurobi.com/academia/academic-program-and-licenses/>.

Place the licence file at `~/gurobi.lic` or set the `GRB_LICENSE_FILE` environment
variable accordingly.

> **Warning**: The solver settings in both config files use `NumericFocus: 3`,
> `BarHomogeneous: 1`, and `DualReductions: 0` to handle the large, numerically
> challenging sector-coupled models. Do not change these without understanding the
> implications — in particular, `DualReductions: 0` is required to prevent Gurobi
> from incorrectly reporting infeasibility before solving.

## Running the Workflow
```bash
conda activate pypsa-eur
```

### Reference scenario

```bash
snakemake --snakefile Snakefile_ref --cores 20 -call
```

### Sufficiency scenario

```bash
snakemake --snakefile Snakefile_suff --cores 20 -call
```

### Dry run (check what would be executed)

```bash
snakemake --snakefile Snakefile_ref --cores 20 -n
```

### Reducing runtime for testing

The temporal resolution is controlled by the `sector_opts` entry in each config
file.  The default value `6h` gives 1 460 snapshots per year (one per 6-hour
block), which is a good balance between accuracy and solve time.  To run a faster
test:

1. Open `config/config_suff.yaml` (or `config_ref.yaml`) and change:
   ```yaml
   sector_opts:
     - "6h"    # default — change to "24h" for a quick test
   ```
2. A `24h` time step reduces snapshots to 365/year and cuts solve time by
   roughly 4×.  Note that this also re-triggers all upstream rules that build
   the time-resolved profiles (e.g. `prepare_sector_network`), so a full
   rebuild from intermediate files is needed when switching resolutions.
3. The `sector_opts` string is embedded in all intermediate and result file
   names (e.g. `base_s_adm__6h_2030.*`), so results at different resolutions
   coexist safely in the `results/` folder without overwriting each other.

### Logs

Snakemake job logs are written to `logs/`. Solver logs for each network solve are at
`results/{scenario}/logs/{network}_solver.log`. Python logs are at
`results/{scenario}/logs/{network}_python.log`.

## Running the optimisation on the NIC5 / CÉCI cluster

The LP solve is by far the most memory- and CPU-intensive step. The helper
scripts in [`cluster/`](cluster/) run **only the solve chain** on NIC5 (the
`hmem` partition + Gurobi), while everything else stays on your machine. Running
locally is unaffected — it is still just the `snakemake` commands above.

### Rationale

* NIC5 **compute nodes have no internet**, so the data-download / cutout-build
  steps cannot run there. Instead, the small un-solved networks are **prepared
  locally** (where all input data already lives), transferred, solved on the
  cluster, and the solved networks are pulled back.
* Gurobi on NIC5 uses a **floating token-server licence** (`nic5-login1`), so the
  conda `gurobipy` checks out a token automatically — no per-node licence file.
* Snakemake runs on the **login node** (which has internet, needed to resolve the
  data-retrieval storage providers when it builds the DAG) and submits each rule
  to Slurm with its built-in `slurm` executor. The compute nodes then only run
  the solve script. The time resolution is passed purely as the `sector_opts`
  Snakemake wildcard, so **no config file is edited**.

### One-time setup

Configure your SSH host and scratch path at the top of
[`cluster/config.sh`](cluster/config.sh) (defaults target the `nic5` SSH alias and
`$GLOBALSCRATCH`). Requires CÉCI SSH access (here over the `sqvpn` VPN). Then:

```bash
./cluster/nic5.sh setup      # installs Miniforge + the pypsa-eur env + Gurobi licence
```

### Full test run (ref + suff at 1-hour resolution)

```bash
./cluster/nic5.sh run ref 1h   # prepare (local) -> push -> solve -> wait -> pull
```

`run` chains the individual steps, which can also be invoked separately:

| Command | What it does |
|---------|--------------|
| `./cluster/nic5.sh prepare 1h` | **local**: builds the un-solved networks (`prepare_sector_network`, `add_existing_baseyear`) for **both** scenarios at the chosen resolution |
| `./cluster/nic5.sh prepare ref 1h` | same, but **one scenario only** (used automatically by `run ref 1h`) |
| `./cluster/nic5.sh push`       | `rsync`s code + prepared `resources/` + `data/` (minus the multi-GB Atlite cutout) to the cluster, plus Snakemake's `.snakemake/metadata` so the solve chain is recognised as up to date |
| `./cluster/nic5.sh solve ref 1h` | launches the `ref` Slurm orchestrator; each solve job gets **20 CPUs / 200 GB on `hmem`** |
| `./cluster/nic5.sh solve suff 1h` | same for the `suff` scenario (run after `ref` finishes) |
| `./cluster/nic5.sh stop`       | cancel all your Slurm jobs and Snakemake orchestrators on the cluster |
| `./cluster/nic5.sh status`     | shows `squeue`, **live per-thread CPU/RSS** on compute nodes (`top -H`, scoped per Slurm job), and tails orchestrator logs |
| `./cluster/nic5.sh wait`       | blocks until the orchestrators recorded in `.last_jobs` finish |
| `./cluster/nic5.sh pull`       | `rsync`s the solved `results/` (and logs) back |
| `./cluster/nic5.sh postprocess ref 6h` | **local**: `--touch` solve outputs, then `prepare_results` (see warning below) |
| `./cluster/nic5.sh shell`      | opens an interactive shell in the cluster repo |

`./cluster/nic5.sh solve all 1h` is reserved but **not supported yet**: `ref` and `suff` share the same cluster checkout and `.snakemake/` state, so concurrent orchestrators can interfere. Run them separately as above.

**Progress during `prepare`:** Snakemake output is streamed to the terminal and
tee'd to `cluster/logs/prepare_<scenario>_<res>.log`. While a run is in progress
you can also watch `.snakemake/log/` (latest `*.snakemake.log`) or per-rule logs
under `logs/<scenario>/`. At 1h resolution, prepare rebuilds many upstream profile
rules (~100+ steps) before the six solve-input targets — this can take hours.

Any resolution works the same way, e.g. `./cluster/nic5.sh run ref 6h` (includes `postprocess` after `pull`).

### Post-processing after pull

Run `./cluster/nic5.sh postprocess <scenario> <resolution>` locally once cluster results are pulled (same arguments as `solve`). The script:

1. Aligns local brownfield file timestamps with the pulled solved networks (so the myopic chain is not rebuilt).
2. Runs Snakemake with **`--touch`** on the solve outputs so Snakemake treats the cluster `.nc` files as up to date **without** re-running Gurobi.
3. Runs the **`prepare_results`** rule (and its Snakemake dependencies) to rebuild SEPIA HTML/Excel summaries and related artefacts.

> **Warning — `--touch`**: This only updates modification times and tells Snakemake the solve step is complete; it does **not** verify file contents. Use it only after a successful cluster solve and `pull`. Never combine this step with `--forcerun` on `solve_sector_network_myopic` or `add_brownfield`, or Snakemake will re-execute those rules and **overwrite** your pulled networks. The `postprocess` resolution must match the cluster solve (e.g. `6h` vs `1h`).

### Slurm resource settings (job efficiency)

CECI expects Slurm allocations to match what the job actually uses — see the
[CECI job efficiency guide](https://support.ceci-hpc.be/doc/SubmittingJobs/JobEfficiency/).

| What | Value | Why |
|------|-------|-----|
| Slurm `--cpus-per-task` | **30** | Set via `solving.cpus` in [`cluster/config_cluster.yaml`](cluster/config_cluster.yaml); the same file sets `solving.solver.options` and matching `solver_options.*.threads` on the cluster only. Must match Gurobi thread count (CECI [job efficiency](https://support.ceci-hpc.be/doc/SubmittingJobs/JobEfficiency/)). |
| Slurm memory | **500 GB** | Set via `solving.mem_mb` in `cluster/config_cluster.yaml` (local configs keep their own values). |
| Partition | **`hmem`** | Memory-heavy LP solve |

These are applied automatically by `./cluster/nic5.sh solve <scenario>`. To change solve CPUs or memory, edit [`cluster/config_cluster.yaml`](cluster/config_cluster.yaml) (`solving.cpus`, `solving.mem_mb`). Slurm partition and runtime defaults live in [`cluster/config.sh`](cluster/config.sh).

### Solver preset (cluster vs local)

Scenario configs (`config/config_ref.yaml`, `config/config_suff.yaml`) use
`gurobi-numeric-focus` for local runs — relaxed tolerances
(`FeasibilityTol`/`OptimalityTol` 0.01, `NumericFocus: 3`) that help the large
sector-coupled models converge. Cluster solves merge
[`cluster/config_cluster.yaml`](cluster/config_cluster.yaml), which **overrides**
the solver preset without touching the local configs.

To run cluster solves with standard Gurobi settings instead (typically faster,
but may fail or terminate sub-optimally on hard horizons), set in
`cluster/config_cluster.yaml`:

```yaml
solving:
  solver:
    options: gurobi-default
```

To restore strict numerics on the cluster, switch back to `gurobi-numeric-focus`.
Thread count is always taken from `solving.cpus` in the same file (applied to
whichever preset is active).

For a **local** full workflow with the same cluster solver settings (no NIC5),
pass the overlay to Snakemake:

```bash
snakemake --snakefile Snakefile_ref --cores 30 -call \
  --configfile cluster/config_cluster.yaml
```

(`prepare` / `postprocess` in `nic5.sh` do not use this overlay — only the
cluster `solve` step does, which is where Gurobi runs.)

To cancel a run in progress: `./cluster/nic5.sh stop`

For a full `ref` + `suff` test at the same resolution, run one scenario at a time:

```bash
./cluster/nic5.sh solve ref 1h    # wait until done
./cluster/nic5.sh solve suff 1h
```


> Note: with `gurobi-numeric-focus` the 1-hour solve is heavy (order of an hour
> or more per planning horizon), so a full `ref` + `suff` run spans many hours.
> The cluster default in `cluster/config_cluster.yaml` uses `gurobi-default`
> instead for faster solves; use a coarser resolution (`6h`, `24h`) for quick checks.

## Known Issues and Warnings

### linopy version pin — do not upgrade beyond 0.6.1

linopy 0.7.0 introduced a performance improvement in LP file writing
(`perf: speed up LP file writing`) that changed how `inf` bounds in PyPSA network
data structures are translated into LP variable bounds.  With linopy ≥ 0.7.0 the
resulting LP formulation contains **~12 000–15 000 truly free variables** (bounds
`[−∞, +∞]`) per planning horizon, causing:

- Gurobi to report **"Unbounded model"** for the `co2 atmosphere` and CO2
  sequestration stores (the specific subsections below document each case)
- **10–15× longer solve times** even after those individual fixes, because the
  remaining free variables degrade the barrier algorithm
- **Sub-optimal termination** in some horizons and incorrect dual variables /
  shadow prices as numerical artefacts

`envs/environment.yaml` therefore pins `linopy =0.6.1`, which produces a clean LP
with zero free variables reported by Gurobi.  All planning horizons then solve to
certified optimality in 230–530 s.  The individual `solve_network.py` fixes
documented below are still physically correct and are kept as defence-in-depth, but
they are **not sufficient** on their own to fix the linopy 0.7.0 regression.

> **Do not upgrade linopy** without verifying that the LP-writing regression
> introduced in 0.7.0 has been fixed upstream.

### Unbounded LP — co2 atmosphere store (suff and ref, all planning horizons)

The `co2 atmosphere` store is non-extendable and physically should hold all
remaining atmospheric CO2 (a very large but finite stock). In the raw network it
is initialised with `e_nom = inf` and `e_min_pu = -1`, which linopy translates
into bounds `[−∞, +∞]` for every `Store-e[t]` variable.  Because `noisy_costs`
gives the store a small positive marginal cost (≈ 0.01 €/tonne), the LP objective
is unbounded below: pushing `e[t] → −∞` drives the cost to −∞.  Gurobi's
homogeneous barrier detects this as **"Unbounded model"** after reporting
`Free vars: 1` (or `Free vars: 10` in the ref scenario).

**Fix (implemented in `prepare_network()`):** set `e_nom = 2×10⁹ t` (2 Gt, well
above any realistic annual CO₂ budget) and `e_min_pu = 0` (atmosphere stock
cannot go negative).  The resulting constraint `0 ≤ Store-e[t] ≤ 2e9` is
finite, Gurobi's presolve eliminates the free variable, and the LP is bounded.

### Unbounded LP — CO2 sequestered stores (ref scenario, all planning horizons)

In the ref scenario, CO2 sequestered stores for DE, FR, GB and NL are extendable
(`e_nom_extendable = True`) with `e_nom_max = inf` and a negative marginal cost
(≈ −0.09 €/tonne after `noisy_costs`).  This caused the LP to be unbounded: the
solver could increase sequestration capacity without limit and drive the objective
to −∞.

The existing `imposed_values_sequestration()` only capped Belgium's store at 2 Mt.
The stores for the other four countries remained uncapped.

**Fix (implemented in `imposed_values_sequestration()`):** cap `e_nom_max` for
DE, FR, GB and NL CO2 sequestered stores at the total EU sequestration potential
from `sector.co2_sequestration_potential` in `config_ref.yaml` (e.g. 40 Mt for
2030, 180 Mt for 2040, 250 Mt for 2050).  These per-country caps are conservative
upper bounds; actual sequestration is further limited by the CO₂ budget and
economics.

### Note on `add_co2_sequestration_limit()`

The `add_co2_sequestration_limit()` helper is currently **broken**: it passes
`carrier_attribute="co2 sequestered"` but that column does not exist in
`n.carriers`, so the computed LHS is always zero and the resulting constraint is
vacuous.  The function is called but has no effect; the actual sequestration caps
are enforced by the `e_nom_max` values set in `imposed_values_sequestration()`.

### Gurobi `DualReductions` flag

Setting `DualReductions: 1` (the Gurobi default) can cause Gurobi to incorrectly
report **infeasibility** for these models due to numerical issues in presolve.
Both config files set `DualReductions: 0` to avoid this. Do not re-enable it.

### Solver tolerances

The sector-coupled models are large (~3 million constraints, ~1.6 million variables
before presolve) and numerically challenging. The `gurobi-numeric-focus` option set
uses relaxed tolerances (`FeasibilityTol: 0.01`, `OptimalityTol: 0.01`,
`BarConvTol: 1e-3`) to ensure convergence in reasonable time. Tightening these
tolerances may cause solve failures or very long runtimes.

### Heat vent generators

Heat vent generators (`urban central heat vent`, `rural heat vent`,
`urban decentral heat vent`) are extendable with `p_nom_max = inf` and a small
negative marginal cost (−0.02 €/MWh). They are bounded in the LP via
`p ≤ 0` and `p ≥ −p_nom`, but their large coefficient range contributes to
numerical difficulties.

### Belgium-specific imposed values

The functions `imposed_values_sequestration()` and `imposed_values_generation()` in
`scripts/solve_network.py` impose Belgium-specific constraints after
`prepare_network()` and before the solve:

- Battery storage minimum: 4 GWh in 2030
- Minimum and maximum H₂ electrolyser capacity: 150 MW in 2030
- DAC capacity caps for 2040 and 2050 (ref scenario only)

Additionally, `imposed_values_generation()` sets `p_nom_max = inf` for *all*
generators, overriding any capacity limit set during network preparation. Review
this function before changing generator capacity assumptions.

## Hardware Requirements

The full workflow (both scenarios, 3 planning horizons each) requires significant
computational resources:

- **RAM**: ≥ 64 GB recommended (sector-coupled models can exceed 40 GB during solve)
- **CPU**: 20 threads are configured in `gurobi-numeric-focus`; a machine with
  ≥ 20 physical cores is recommended
- **Disk**: ~50 GB for all intermediate files and results
- **Solve time**: Each planning horizon solve takes approximately 15–60 minutes
  depending on hardware

## Output

Solved networks are written to `results/{scenario}/networks/` as NetCDF files
(`.nc`). Summary statistics and plots are produced by the postprocessing rules
defined in `rules/postprocess.smk` and `rules/collect.smk`.

## Licence

The code in this repository is derived from [PyPSA-Eur](https://github.com/PyPSA/pypsa-eur)
and inherits its [MIT licence](LICENSES/MIT.txt). Data files retain their original
licences as documented in [REUSE.toml](REUSE.toml).

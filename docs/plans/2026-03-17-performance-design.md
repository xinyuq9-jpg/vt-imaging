# Performance Improvement Design — VT-Imaging Pipeline

**Date:** 2026-03-17
**Context:** 50+ participants, up to 10k frames per block, running on laptop (4-8 cores, limited RAM), no Parallel Computing Toolbox. Primary bottleneck is Morpho0 (registration), secondary is Morpho4 (tracing/A*).

---

## Strategy Overview

Three complementary layers of improvement:

| Layer | Approach | Expected Speedup | Effort |
|-------|----------|-------------------|--------|
| **1. HPC batch processing** | Submit per-participant jobs to university SLURM cluster | ~50x (all participants in parallel) | Medium |
| **2. Laptop multi-instance** | Run 2-3 MATLAB instances via shell script | 2-3x | Low |
| **3. Algorithmic quick wins** | Fix per-frame overhead, warm-start registration, pyramid downsampling | 2-5x per participant | Low-Medium |

Layers compound: HPC + algorithmic = 100-250x total throughput improvement.

---

## Layer 1: HPC Batch Processing (SLURM)

### Architecture

```
Laptop (interactive)              Shared Network Drive              Cluster (compute)
────────────────────              ────────────────────              ──────────────────
Morpho0: ginput mask    ──write──>  /shared/masks/ADB##.mat
Morpho1: mask editing   ──write──>  /shared/morph/...
Morpho3: QA editing     ──write──>  /shared/morph/mat_QA/...
Morpho5: manual fixes   ──write──>  /shared/morph/vt_trace*_final/

                                    /shared/avi_raw/           ──read──>  Morpho0: registration
                                    /shared/morph/mat/         ──read──>  Morpho2: subsetting
                                    /shared/morph/mat_QA/      ──read──>  Morpho4: outlining
```

**Key insight**: The pipeline naturally splits into **interactive** stages (need GUI/ginput) and **compute** stages (headless). Only compute stages go to the cluster.

### What needs to change

#### 1. Headless batch entry point: `morpho_batch.m`

A new script that wraps each Morpho stage for non-interactive execution:

```matlab
function morpho_batch(stage, participant_id)
% MORPHO_BATCH  Run a single pipeline stage for one participant.
%   Called by SLURM job array. No GUI, no interactive prompts.
%
%   morpho_batch(0, 'ADB17')  — register all blocks for ADB17
%   morpho_batch(2, 'ADB17')  — subset all blocks for ADB17
%   morpho_batch(4, 'ADB17')  — outline all blocks for ADB17

    cfg = morpho.Config();

    switch stage
        case 0
            morpho_batch_register(cfg, participant_id);
        case 2
            morpho_batch_subset(cfg, participant_id);
        case 4
            morpho_batch_outline(cfg, participant_id);
        otherwise
            error('Stage %d not supported in batch mode.', stage);
    end
end
```

Each `morpho_batch_*` function contains the inner loop from the corresponding Morpho script, minus interactive prompts. Pre-computed masks/parameters are loaded from files saved by the interactive stages.

#### 2. Interactive pre-computation scripts

Before submitting batch jobs, run interactive stages on laptop to produce:

- **Morpho0 prep**: Save ginput mask cutoffs per ADB to `masks/ADB##_cutoffs.mat` (contains `cutoff_X`, `cutoff_Y`, `reference_frame_path`)
- **Morpho1 prep**: Save edited masks to `morph/masks/` (already done)
- **Morpho3 prep**: Save QA masks to `morph/mat_QA_masks/` (already done)

#### 3. SLURM job scripts

```bash
#!/bin/bash
#SBATCH --job-name=morpho0_reg
#SBATCH --array=1-50           # one job per participant
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=04:00:00
#SBATCH --output=logs/morpho0_%a.out
#SBATCH --error=logs/morpho0_%a.err

# Read participant ID from list file
PARTICIPANT=$(sed -n "${SLURM_ARRAY_TASK_ID}p" participant_list.txt)

module load matlab/R2025a

matlab -batch "morpho_batch(0, '${PARTICIPANT}')"
```

A `participant_list.txt` file (one ADB ID per line) drives the array:
```
ADB01
ADB02
ADB03
...
```

#### 4. Workflow

```
Step 1 (laptop):  Run interactive prep for all ADBs
                  → Saves cutoffs, masks, QA masks to shared drive
Step 2 (laptop):  Generate participant_list.txt
Step 3 (cluster): sbatch slurm_morpho0.sh    # registration
Step 4 (cluster): sbatch slurm_morpho2.sh    # subsetting (after step 3)
Step 5 (cluster): sbatch slurm_morpho4.sh    # outlining (after step 4)
Step 6 (laptop):  Run Morpho5 finaliser interactively
```

SLURM dependencies between stages:
```bash
JOB0=$(sbatch --parsable slurm_morpho0.sh)
JOB2=$(sbatch --parsable --dependency=afterok:$JOB0 slurm_morpho2.sh)
sbatch --dependency=afterok:$JOB2 slurm_morpho4.sh
```

### What to ask IT

Before implementing, confirm with IT:

1. Can cluster compute nodes mount the shared network drive? (If yes, no data transfer needed.)
2. Is MATLAB R2025a available as a module? (`module avail matlab`)
3. What is the MATLAB license pool size? (Limits concurrent jobs.)
4. What is the job scheduler? (Assuming SLURM; adapt if SGE/PBS.)

### Fallback: data transfer workflow

If the cluster cannot see the shared drive:

```bash
# Before submitting
rsync -avz /shared/data/ cluster:/scratch/$USER/vt-imaging/data/

# After jobs complete
rsync -avz cluster:/scratch/$USER/vt-imaging/avi_reg/ /shared/avi_reg/
```

Add rsync commands to a wrapper script so it's one command.

---

## Layer 2: Laptop Multi-Instance Parallelism

For when the cluster is unavailable or for quick runs. Uses the same `morpho_batch.m` entry point.

```bash
#!/bin/bash
# run_parallel.sh — run N MATLAB instances on laptop
# Usage: ./run_parallel.sh <stage> <max_concurrent>

STAGE=$1
MAX_JOBS=${2:-2}   # default 2 concurrent (safe for 8GB RAM)

PIDS=()
while IFS= read -r PARTICIPANT; do
    # Wait if at max capacity
    while [ ${#PIDS[@]} -ge $MAX_JOBS ]; do
        for i in "${!PIDS[@]}"; do
            if ! kill -0 "${PIDS[$i]}" 2>/dev/null; then
                unset 'PIDS[$i]'
            fi
        done
        PIDS=("${PIDS[@]}")  # reindex
        sleep 1
    done

    echo "Starting stage $STAGE for $PARTICIPANT..."
    matlab -batch "morpho_batch($STAGE, '$PARTICIPANT')" \
        > "logs/morpho${STAGE}_${PARTICIPANT}.log" 2>&1 &
    PIDS+=($!)

done < participant_list.txt

# Wait for all to finish
wait
echo "All done."
```

**RAM considerations**: Each MATLAB instance uses ~2-4GB. On 8GB laptop, run max 2 concurrent. On 16GB, run 3-4.

---

## Layer 3: Algorithmic Quick Wins

These improvements reduce per-frame compute time and apply whether running on laptop or cluster.

### 3a. Fix VideoReader-per-frame overhead in Morpho4 (HIGH IMPACT, LOW EFFORT)

**Problem**: In [Morpho4_outliner.m:103](Morpho4_outliner.m#L103), `morpho.video.read_single()` is called inside the frame loop. Each call creates a **new VideoReader object**, which involves file open/seek overhead. For 10k frames, this means 10k VideoReader instantiations.

**Fix**: Open VideoReader once before the loop, read frames sequentially:

```matlab
% Before frame loop
v_reader = VideoReader(fullfile(input_avi_dir, [input_rootname '.avi']));

for f = 1:no_frames
    this_frame = morpho.video.to_gray_single(read(v_reader, frame_positions(f)));
    ...
end
```

**Expected improvement**: Eliminates ~10k file open/close cycles per block. Likely saves 30-60 seconds per block depending on I/O.

### 3b. Warm-start registration transforms (HIGH IMPACT, MEDIUM EFFORT)

**Problem**: In [Morpho0_register.m:296](Morpho0_register.m#L296), `imregtform` starts from scratch every frame. Consecutive MRI frames barely move — the optimizer wastes iterations converging to nearly the same transform.

**Fix**: Use the previous frame's transform as `InitialTransformation`:

```matlab
prev_tform = [];
for f = 1:no_frames
    frame = read(aviObj, f);
    frame = morpho.registration.ensure_gray_2d(frame);

    if isempty(prev_tform)
        tform = imregtform(frame, fixed_masked, 'rigid', optimizer, metric);
    else
        tform = imregtform(frame, fixed_masked, 'rigid', optimizer, metric, ...
            'InitialTransformation', prev_tform);
    end

    prev_tform = tform;
    registered = imwarp(frame, tform, 'OutputView', outView);
    ...
end
```

**Expected improvement**: 2-4x faster registration per frame (fewer optimizer iterations to converge).

### 3c. Pyramid (downsampled) registration (MEDIUM IMPACT, MEDIUM EFFORT)

**Problem**: `imregtform` cost scales with pixel count. MRI frames may be larger than needed for computing the rigid transform.

**Fix**: Downsample frames 2x for registration, apply the resulting transform at full resolution:

```matlab
scale = 0.5;
frame_small = imresize(frame, scale);
fixed_small = imresize(fixed_masked, scale);
outView_small = imref2d(size(fixed_small));

tform = imregtform(frame_small, fixed_small, 'rigid', optimizer, metric);
% tform is scale-invariant for rigid transforms (rotation + translation need rescaling)
% Adjust translation components:
tform.T(3,1:2) = tform.T(3,1:2) / scale;

registered = imwarp(frame, tform, 'OutputView', outView);
```

**Expected improvement**: ~4x fewer pixels to optimize over → ~2-3x speedup on top of warm-starting.

**Caution**: Translation rescaling needs validation. Run on a few blocks and compare output to full-resolution registration.

### 3d. A* bridge caching in Morpho4 (MEDIUM IMPACT, LOW EFFORT)

**Problem**: A* pathfinding runs on every frame with 2+ compartments. Consecutive frames often have identical or very similar topology.

**Fix**: Cache the bridge path and reuse if the skeleton topology hasn't changed:

```matlab
prev_bridge = [];
prev_vt_hash = [];

for f = 1:no_frames
    vt_frame = vt_output(:,:,f) > 0;

    if n_compartments >= 2 && draw_connector == "a_star"
        % Simple hash: sum of VT pixels (cheap topology check)
        vt_hash = sum(vt_frame(:));

        if ~isempty(prev_bridge) && abs(vt_hash - prev_vt_hash) < threshold
            bridge = prev_bridge;  % reuse
        else
            bridge = morpho.tracing.a_star_bridge(vt_frame, vt_ever, this_frame, a_star_weight);
            prev_bridge = bridge;
            prev_vt_hash = vt_hash;
        end
        ...
    end
end
```

**Expected improvement**: Depends on how often topology changes. Could skip 50-80% of A* calls.

---

## Implementation Priority

| Priority | Task | Impact | Effort |
|----------|------|--------|--------|
| **1** | Fix VideoReader-per-frame in Morpho4 (3a) | High | ~30 min |
| **2** | Warm-start registration (3b) | High | ~1 hour |
| **3** | Create `morpho_batch.m` entry point | High | ~2 hours |
| **4** | SLURM job scripts | High | ~1 hour |
| **5** | Interactive prep scripts (save cutoffs to file) | Medium | ~1 hour |
| **6** | Pyramid registration (3c) | Medium | ~2 hours |
| **7** | A* bridge caching (3d) | Medium | ~1 hour |
| **8** | Laptop parallel runner script | Low | ~30 min |

**Recommended order**: Do 1-2 first (free speed on any machine), then 3-5 (enable HPC), then 6-8 (polish).

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Cluster can't see shared drive | Fallback to rsync workflow (documented above) |
| MATLAB license pool too small for 50 concurrent jobs | Limit `--array` to license count, e.g. `--array=1-50%10` for max 10 concurrent |
| Warm-start registration diverges on large motion | Keep it as `InitialTransformation` hint — optimizer can still escape if needed |
| Pyramid translation rescaling introduces error | Validate on 3-5 blocks by comparing to full-res output before committing |
| A* cache reuses stale bridge | Use conservative threshold; fall back to fresh A* when topology changes significantly |

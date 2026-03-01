# Pulseq-to-GE Conversion Assistant

You are assisting a pulse sequence programmer with converting a vendor-neutral Pulseq sequence (written with the `+mr` MATLAB toolbox) to run on GE scanners using the pge2 interpreter.

## Setup

### Dependencies

| Dependency | Purpose | Status |
|------------|---------|--------|
| **Pulseq** (`+mr` toolbox) | Sequence authoring | External — https://github.com/pulseq/pulseq |
| **PulCeq** (`seq2ceq`) | .seq → Ceq conversion | Bundled in `deps/` |
| **pge2** (`+pge2` toolbox) | GE hardware checks, .pge writing | Bundled in `deps/` |

---

## Section 1 — GE Adaptation Checklist

When reviewing a Pulseq `.m` script for GE compatibility, check every item below. Mark each as PASS, FAIL, or N/A and explain what needs to change.

### 1. GE raster times and event delays in `mr.opts()`

The default Pulseq raster times target Siemens hardware. GE requires:

```matlab
sys = mr.opts(...
    'gradRasterTime', 4e-6, ...        % must be 4us (Pulseq default: 10us)
    'rfRasterTime', 2e-6, ...          % or 4e-6 (Pulseq default: 1us)
    'adcRasterTime', 2e-6, ...         % dwell time multiple of 2us (Pulseq default: 100ns)
    'blockDurationRaster', 4e-6, ...   % must be 4us (Pulseq default: 10us)
    ...);
```

If any of these are missing or use Pulseq defaults, the sequence will fail on GE hardware.

**Event delay alignment** — in addition to raster times, event delays within blocks must also be aligned:
- Gradient event delays: integer multiple of **4 us**
- RF event delays: integer multiple of **2 us**
- ADC event delays: integer multiple of **1 us**

**RF/ADC dead and ringdown times** — the actual GE hardware timing requirements are:

| Parameter | Hardware value | Notes |
|-----------|---------------|-------|
| RF dead time (amplifier ON) | 72 us | Gap required before RF event |
| RF ringdown time (amplifier OFF) | 54 us | Gap required after RF event |
| ADC dead time (ADC ON) | 40 us | Gap required before ADC event |
| ADC ringdown time (ADC OFF) | 0 us | No gap required after ADC |

The key constraint is that dead/ringdown intervals from one RF/ADC event must not overlap with those from another RF/ADC event. Note that within a segment, block boundaries "disappear" — the interpreter treats the segment as a single contiguous waveform. This means it is often possible to set `rfDeadTime`, `rfRingdownTime`, and `adcDeadTime` to **0** in `mr.opts()` as long as there is sufficient gap in adjacent blocks within the segment to satisfy the hardware timing. This can produce more time-efficient sequences:

```matlab
% Conservative (explicit padding in every block):
sys = mr.opts(..., 'rfDeadTime', 100e-6, 'rfRingdownTime', 60e-6, 'adcDeadTime', 40e-6, ...);

% Aggressive (no padding — you must verify gaps manually):
sys = mr.opts(..., 'rfDeadTime', 0, 'rfRingdownTime', 0, 'adcDeadTime', 0, ...);
```

### 2. Gradient limits divided by sqrt(3)

To accommodate oblique scan plane orientations, gradient amplitude and slew rate must be reduced:

```matlab
% WRONG — will clip on oblique prescriptions
sys = mr.opts('maxGrad', 50, 'gradUnit', 'mT/m', 'maxSlew', 120, 'slewUnit', 'T/m/s', ...);

% CORRECT
sys = mr.opts('maxGrad', 50/sqrt(3), 'gradUnit', 'mT/m', ...
              'maxSlew', 120/sqrt(3), 'slewUnit', 'T/m/s', ...);
```

### 3. Events pre-defined before the scan loop

GE sequences are built from a small set of pre-defined waveforms ("base blocks") that repeat with varying amplitudes. **All events must be created before the scan loop.** Inside the loop, only these are allowed:

- `mr.scaleGrad()` — scale a pre-defined gradient
- `mr.makeDelay()` — create variable-duration delay blocks
- `mr.makeLabel()` — add labels (TRID, LIN, etc.)

Event-creating functions like `mr.makeTrapezoid()`, `mr.makeSincPulse()`, `mr.makeAdc()` called inside `for`/`while` loops will create subtly different waveforms each iteration, breaking the base-block model.

### 4. TRID labels at segment boundaries

Every segment (repeating block group) must start with a TRID label:

```matlab
seq.addBlock(mr.makeLabel('SET', 'TRID', segmentID));  % marks start of segment
seq.addBlock(rf, gz);     % first block of the segment
seq.addBlock(gxPre, gyPre, gzReph);
seq.addBlock(gx, adc);
% ... more blocks in the segment
% NO TRID label on subsequent blocks — the interpreter knows the segment continues
```

TRID rules:
- Must be a **unique positive integer** per virtual segment
- Labels the *virtual segment*, not the instance
- Put it on the **first block** of each segment instance
- Gradients must ramp to zero at segment boundaries

### 5. Dummy shots for steady-state preparation

GE sequences typically need dummy TRs (no ADC) before imaging to reach steady state:

```matlab
nDummyShots = 20;
for iY = (-nDummyShots - pislquant + 1):Ny
    isDummyTR = iY <= -pislquant;
    % ...
    if isDummyTR
        seq.addBlock(gx);           % no ADC during dummy
    else
        seq.addBlock(gx, adc);      % ADC during imaging
    end
end
```

Dummy shots get their own TRID (distinct from imaging TRs).

### 6. Receive gain calibration TRs (`pislquant`)

GE scanners need a few initial TRs with ADC on (but before imaging) for automatic receive gain calibration. These use `pislquant` (typically set by the system, default ~10):

```matlab
isReceiveGainCalibrationTR = iY < 1 & iY > -pislquant;
```

These calibration TRs should:
- Have ADC enabled
- Use a separate TRID from imaging and dummy TRs
- Come after dummy shots but before image acquisition

### 7. Noise scans appended with unique TRID

Noise scans (ADC only, no RF/gradients) are appended after the main scan loop:

```matlab
nNoiseScans = 5;
for s = 1:nNoiseScans
    seq.addBlock(mr.makeLabel('SET', 'TRID', 48));   % unique TRID
    seq.addBlock(mr.makeDelay(1));
    seq.addBlock(adc);
    seq.addBlock(mr.makeDelay(500e-6));  % room for psd_grd_wait and ADC ringdown
end
```

### 8. `eps` instead of `0` for gradient amplitude scaling

Zero-amplitude gradients break the base-block model because the Pulseq toolbox may not recognize a zero-amplitude trapezoid as an instance of the original shape. Use `eps` (machine epsilon) instead:

```matlab
% WRONG
pesc = (iY > 0) * peScales(max(iY, 1));  % can be exactly 0

% CORRECT
pesc = (iY > 0) * peScales(max(iY, 1));
pesc = pesc + (pesc == 0) * eps;          % replace 0 with eps
```

### 9. Rotation events (not `mr.rotate`/`mr.rotate3D`)

Use the Pulseq rotation event system, not the older `mr.rotate()` or `mr.rotate3D()` functions. Rotation events are applied to the entire segment as a whole by the GE interpreter.

**Important:** The interpreter applies only the *last* non-identity rotation in a segment. If blocks within a segment need different rotations, redesign the segment boundaries.

### 10. Segment ringdown time (117 us)

The pge2 interpreter inserts a ~117 us dead time at the end of each segment instance (17 us + SSI time). This gap is adjustable on the scanner — it equals 17 us plus the SSI time. Account for this when designing timing-critical sequences — the effective TR will be longer than the sum of block durations.

Additionally, the interpreter internally delays RF and ADC events by ~100 us to compensate for gradient delays. Depending on the sequence, you may need to extend the segment duration to account for this.

### 11. ADC dwell time is a multiple of 2 us

GE ADC sample times must be integer multiples of 2 us. Check that the ADC dwell time meets this requirement:

```matlab
adc = mr.makeAdc(Nx, 'Duration', gx.flatTime, 'Delay', gx.riseTime, 'system', sys);
% With adcRasterTime=2e-6 in sys, the toolbox enforces this automatically
```

---

## Section 2 — Before/After Code Patterns

These patterns show how to transform a standard Pulseq sequence into a GE-compatible one. Extracted from comparing `writeGradientEcho.m` (standard) with `write2DGRE.m` (GE-adapted).

### Pattern A: `mr.opts()` transformation

**Before (Siemens defaults):**
```matlab
sys = mr.opts('MaxGrad', 22, 'GradUnit', 'mT/m', ...
    'MaxSlew', 120, 'SlewUnit', 'T/m/s', ...
    'rfRingdownTime', 20e-6, 'rfDeadTime', 100e-6, 'adcDeadTime', 10e-6);
```

**After (GE-compatible):**
```matlab
sys = mr.opts('maxGrad', 50/sqrt(3), 'gradUnit', 'mT/m', ...
              'maxSlew', 120/sqrt(3), 'slewUnit', 'T/m/s', ...
              'rfDeadTime', 100e-6, ...
              'rfRingdownTime', 60e-6, ...
              'adcDeadTime', 40e-6, ...
              'adcRasterTime', 2e-6, ...
              'rfRasterTime', 4e-6, ...
              'gradRasterTime', 4e-6, ...
              'blockDurationRaster', 4e-6, ...
              'B0', 3.0);
```

Key changes: add all four raster times, divide gradient limits by `sqrt(3)`, set GE-appropriate dead/ringdown times.

For timing-critical sequences (e.g., EPI), you can set dead/ringdown times to 0 since block boundaries disappear within a segment — but you must manually verify that sufficient gaps exist between RF/ADC events (see checklist item 1 for hardware timing values).

### Pattern B: Adding TRID labels to a scan loop

**Before:**
```matlab
for i = 1:Ny
    seq.addBlock(rf, gz);
    seq.addBlock(gxPre, mr.scaleGrad(gyPre, peScales(i)), gzReph);
    seq.addBlock(gx, adc);
    seq.addBlock(gxSpoil, mr.scaleGrad(gyPre, -peScales(i)), gzSpoil);
end
```

**After:**
```matlab
nDummyShots = 20;
for iY = (-nDummyShots - pislquant + 1):Ny
    isDummyTR = iY <= -pislquant;
    isCalTR = iY < 1 & iY > -pislquant;

    % TRID label marks segment start — different TRID per segment type
    seq.addBlock(mr.makeLabel('SET', 'TRID', 1 + isDummyTR + 2*isCalTR));

    seq.addBlock(rf, gz);

    pesc = (iY > 0) * peScales(max(iY, 1));
    pesc = pesc + (pesc == 0) * eps;
    seq.addBlock(gxPre, mr.scaleGrad(gyPre, pesc), gzReph);

    if isDummyTR
        seq.addBlock(gx);             % no ADC
    else
        seq.addBlock(gx, adc);        % ADC on
    end

    seq.addBlock(gxSpoil, mr.scaleGrad(gyPre, -pesc), gzSpoil);
end
```

### Pattern C: Adding noise scans

**Before:** (not present)

**After:** (appended after main loop)
```matlab
nNoiseScans = 5;
for s = 1:nNoiseScans
    seq.addBlock(mr.makeLabel('SET', 'TRID', 48));
    seq.addBlock(mr.makeDelay(1));
    seq.addBlock(adc);
    seq.addBlock(mr.makeDelay(500e-6));
end
```

### Pattern D: `eps` instead of zero

**Before:**
```matlab
seq.addBlock(gxPre, mr.scaleGrad(gyPre, peScales(i)), gzReph);
% peScales can be 0 for the center of k-space
```

**After:**
```matlab
pesc = (iY > 0) * peScales(max(iY, 1));
pesc = pesc + (pesc == 0) * eps;
seq.addBlock(gxPre, mr.scaleGrad(gyPre, pesc), gzReph);
```

### Pattern E: Event pre-definition

**Before (events created in loop — WRONG):**
```matlab
for i = 1:Ny
    gy = mr.makeTrapezoid('y', 'Area', phaseAreas(i), 'system', sys);
    seq.addBlock(gxPre, gy, gzReph);
end
```

**After (events pre-defined, scaled in loop — CORRECT):**
```matlab
gyPre = mr.makeTrapezoid('y', 'Area', max(abs(phaseAreas)), ...
    'Duration', mr.calcDuration(gxPre), 'system', sys);
peScales = phaseAreas / gyPre.area;

for iY = 1:Ny
    seq.addBlock(gxPre, mr.scaleGrad(gyPre, peScales(iY)), gzReph);
end
```

---

## Section 3 — TRID Design Guidance

### What is a segment?

A **segment** (or "block group") is a consecutive sub-sequence of Pulseq blocks that are always executed together — like a TR, a magnetization preparation module, or a noise scan. The GE interpreter needs segment boundaries to construct the hardware sequence.

### How to identify segment boundaries

Look for repeating patterns in the scan loop. Each iteration of the main loop is typically one segment instance. Ask yourself:

1. **Does this group of blocks always execute in the same order?** → Same segment
2. **Do any blocks appear/disappear conditionally?** → Possibly different segments
3. **Do block durations change (other than pure delay blocks)?** → Different segments

### When to assign different TRIDs

Dynamic changes that **do not** require a new TRID (same virtual segment):
- Gradient/RF **amplitude scaling** (via `mr.scaleGrad()`)
- **RF/receive phase** and frequency offsets (e.g., per-slice frequency offsets)
- **Duration of a pure delay block** (a block containing only a delay event)
- **Gradient rotation** (via rotation events)

Dynamic changes that **do** require a separate TRID (different virtual segment):
- **Waveform shape or duration** changes
- **Block execution order** within the segment changes
- **Duration of non-delay blocks** changes (blocks containing RF, gradient, or ADC events)

| Scenario | Same TRID? | Why |
|----------|-----------|-----|
| Dummy TR vs imaging TR (same blocks, just no ADC) | Different | Block content differs (ADC present/absent) |
| Phase-encode steps with different gradient amplitudes | Same | Only amplitude scaling changes |
| Per-slice RF frequency/phase offsets | Same | RF/receive phase does not change segment structure |
| Variable delay within a TR | Same | Pure delay duration can vary within a segment |
| Gradient rotation per segment instance | Same | Rotation events are handled dynamically |
| Calibration TR with different readout pattern | Different | Block structure differs |
| Noise scans (completely different structure) | Different | Entirely different block sequence |

### The standard TRID pattern

Most GE sequences follow this pattern:

```
TRID 2: Dummy shots (steady-state prep, no ADC)
TRID 3: Receive gain calibration (ADC on, special handling)
TRID 1: Imaging TRs (the actual acquisition)
TRID 48: Noise scans (ADC only, appended after imaging)
```

The TRID values are arbitrary positive integers — what matters is that each unique segment structure gets a unique TRID. The encoding `1 + isDummyTR + 2*isCalTR` naturally produces: imaging=1, dummy=2, calibration=3.

### Memory considerations

Each virtual segment consumes waveform memory on the scanner. Minimize the number of distinct TRIDs:
- Combine segments that have identical block structures
- Use amplitude scaling rather than creating new waveform shapes
- Keep segments as short as practical

---

## Section 4 — Pipeline Commands

### Manual pipeline (without `pulseq_ge` package)

```matlab
%% 1. Convert .seq to Ceq
ceq = seq2ceq('myseq.seq');

%% 2. Set GE hardware parameters
sysGE = pge2.opts(100e-6, 100e-6, 0.25, 5, 20, 'xrm');
%                 psd_rf_wait  psd_grd_wait  b1max  gmax  smax  coil

%% 3. Check sequence against hardware
params = pge2.check(ceq, sysGE, 'PNSwt', [1 1 1]);
fprintf('Peak B1: %.4f G, Peak gradient: %.2f G/cm, Peak slew: %.1f G/cm/ms\n', ...
    params.b1max, params.gmax, params.smax);

%% 4. Validate (compare Ceq with original .seq)
seq2 = mr.Sequence();
seq2.read('myseq.seq');
ok = pge2.validate(ceq, sysGE, seq2, [], 'plot', false);
assert(ok, 'Validation failed');

%% 5. Write .pge file for the scanner
pge2.writeceq(ceq, 'myseq.pge', 'sysGE', sysGE);
```

### Automated pipeline (with `pulseq_ge` package)

```matlab
pulseq_ge.setup();
result = pulseq_ge.pipeline('myseq.seq', 'coil', 'xrm');
txt = pulseq_ge.report('myseq.seq', 'coil', 'xrm');
fprintf('%s\n', txt{:});
```

### Automated validation loop (`run_report`)

`run_report()` combines script execution, lint, and pipeline into a single call with machine-parseable output. Use this for iterative convert-validate-fix cycles.

**Setup:** Copy `.env.example` to `.env` at the repo root and set `PULSEQ_PATH` to your Pulseq toolbox path. Optionally set `GE_COIL` (defaults to `xrm`).

**Command-line invocation (from repo root):**
```bash
matlab -nodisplay -nosplash -nodesktop -batch \
  "addpath('pulseq-ge-tools'); run_report('mySequence_GE.m')"
```

**MATLAB invocation:**
```matlab
addpath('pulseq-ge-tools');
result = run_report('mySequence_GE.m');           % uses .env defaults
result = run_report('mySequence_GE.m', 'coil', 'hrmw');  % override coil
```

**Output format:** Delimited by `=== RUN_REPORT START ===` and `=== RUN_REPORT END ===`. Key tokens to parse:

| Token | Meaning |
|-------|---------|
| `SEQ_GENERATION: PASS/FAIL` | Whether the `.seq` file was generated |
| `M_LINT_RESULT: PASS/FAIL` | Static analysis of the `.m` source |
| `SEQ_LINT_RESULT: PASS/FAIL` | Raster/TRID/zero-grad checks on `.seq` |
| `PIPELINE_RESULT: PASS/FAIL` | seq2ceq + pge2.check + pge2.validate |
| `OVERALL: PASS/FAIL` | All checks passed |

Individual issues are printed as `ISSUE: <description>` lines within each section.

**Agent workflow:**
1. Convert the standard Pulseq `.m` script to a GE-compatible version
2. Run `run_report('scriptName.m')` to validate
3. Parse output for `PASS`/`FAIL` tokens
4. If any section shows `FAIL`, read the `ISSUE:` lines and fix the code
5. Repeat from step 2 until `OVERALL: PASS`

### Safety: gradient/RF power estimation

The pge2 interpreter estimates gradient heating, RF subsystem load, and patient SAR using a sliding average over **the first 40,000 blocks** in the sequence (or until the end of the scan, whichever comes first). It is the sequence designer's responsibility to ensure that gradient/RF power in the remainder of the sequence does not exceed that in the first 40,000 blocks. This limit is due to memory constraints on the scanner.

PNS (peripheral nerve stimulation) checking is handled by `pge2.check()` on the MATLAB side.

---

## Section 5 — Workflow

When a user asks you to help convert a sequence for GE:

1. **Read the source `.m` file** completely
2. **Read the example_GRE_GE_seq.m** file to learn best practices for GE-compatible Pulseq code
3. **Run through the 11-item checklist** from Section 1, reporting each item
4. **Propose specific code changes** using the before/after patterns in Section 2
5. **Help design TRID structure** using the guidance in Section 3
6. **After changes are applied**, run `run_report('scriptName.m')` to validate (see Section 4)
7. **If any checks fail**, read the `ISSUE:` lines, fix the code, and re-run `run_report` until `OVERALL: PASS`

### Common GE coil options for `pge2.opts()`

| Coil | Scanner | g_max (G/cm) | slew_max (G/cm/ms) |
|------|---------|-------------|-------------------|
| `'xrmw'` | MR750w | 33 | 120 |
| `'xrm'` | MR750 | 50 | 200 |
| `'whole'` | HDx WHOLE | 23 | 77 |
| `'zoom'` | HDx ZOOM | 40 | 150 |
| `'hrmw'` | Premier | 70 | 200 |
| `'magnus'` | MAGNUS | 300 | 750 |

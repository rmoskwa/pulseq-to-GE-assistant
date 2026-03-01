# pulseq-ge-tools

A MATLAB package and AI agent instructions for converting vendor-neutral Pulseq sequences to run on GE scanners.

## Overview

Two components:

1. **`AGENTS.md`** — Agent-agnostic instructions with a GE adaptation checklist, before/after code patterns, and TRID design guidance. Symlink as `CLAUDE.md`, `.cursorrules`, or `.github/copilot-instructions.md` depending on your editor.

2. **`+pulseq_ge` MATLAB package** — Static analysis, pipeline automation, and reporting.

## Dependencies

| Dependency | Required for | Source |
|------------|-------------|--------|
| Pulseq (`+mr`) | `lint()` on .seq files, `pipeline()` | https://github.com/pulseq/pulseq |
| PulCeq (`seq2ceq`) | `pipeline()` | https://github.com/HarmonizedMRI/PulCeq |
| pge2 (`+pge2`) | `pipeline()` | https://github.com/GEHC-External/pulseq-ge-interpreter |

`lint()` on `.m` files works without any dependencies.

## Setup

```matlab
addpath('/path/to/pulseq-ge-tools');

% Pass the directories that contain +mr, seq2ceq.m, and +pge2 (same as addpath)
pulseq_ge.setup('/path/to/pulseq/matlab', ...
                '/path/to/PulCeq/matlab', ...
                '/path/to/pge2/matlab');

% If dependencies are already on your MATLAB path, just call:
pulseq_ge.setup();
```

## Usage

### Lint a sequence script

```matlab
r = pulseq_ge.lint('mySequence.m');
% r.issues      — cell array of issue descriptions
% r.tridPresent — true if TRID labels found
% r.sqrtThreePresent — true if gradient limits divided by sqrt(3)
```

### Lint a .seq file

```matlab
r = pulseq_ge.lint('myseq.seq');
% additionally checks raster alignment and zero-amplitude gradients
```

### Run the full validation pipeline

```matlab
result = pulseq_ge.pipeline('myseq.seq', 'coil', 'xrm');
% result.validationOK — true if pge2.validate passes
% result.params.b1max — peak B1 in Gauss
```

### Generate a combined report

```matlab
txt = pulseq_ge.report('myseq.seq', 'coil', 'xrm');
fprintf('%s\n', txt{:});
```

## Pipeline parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `coil` | `'xrm'` | Gradient coil (xrmw, xrm, whole, zoom, hrmw, magnus) |
| `psd_rf_wait` | `100e-6` | RF wait time [s] |
| `psd_grd_wait` | `100e-6` | Gradient wait time [s] |
| `b1_max` | `0.25` | Max B1 [Gauss] |
| `g_max` | `5` | Max gradient [G/cm] |
| `slew_max` | `20` | Max slew rate [G/cm/ms] |
| `PNSwt` | `[1 1 1]` | PNS channel weights |

## Testing

```matlab
cd pulseq-ge-tools
test_pulseq_ge          % lint tests only
test_pulseq_ge(true)    % includes pipeline tests (requires all dependencies)
```

## Using AGENTS.md with AI coding assistants

The `AGENTS.md` file contains structured instructions for any AI coding agent to assist with GE conversion. Symlink it for your tool:

```bash
# Claude Code
ln -s AGENTS.md CLAUDE.md

# Cursor
ln -s AGENTS.md .cursorrules

# GitHub Copilot
mkdir -p .github && ln -s ../AGENTS.md .github/copilot-instructions.md
```

## License

See [LICENSE](LICENSE).

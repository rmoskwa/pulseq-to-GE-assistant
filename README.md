# Pulseq-to-GE Conversion Workspace

A simple setup for allowing a coding AI agent to convert vendor-neutral [Pulseq](https://github.com/pulseq/pulseq) MRI sequences to run on GE scanners using the [pge2 interpreter](https://github.com/GEHC-External/pulseq-ge-interpreter). There are two simple ingredients:
1. Grant the agent any specifications context (`pulseq-ge-tools/AGENTS.md`)  
2. Grant the agent a validation loop to self-revise any coding errors ('run_report.m')

In a production setting, agents should also be given the ability to fetch/reference relevant examples if possible to assist with its reasoning. 'pulseq-ge-tools\example_GRE_GE_seq.m' is an official demo for understanding how a Pulseq GRE sequence written for a GE scanner may look. 

The exercise here is to observe the performance of an AI agent in converting a Pulseq sequence written for Siemens ('writeGradientEcho.m') to GE given a set of guidelines. Do note that this repository was made for demonstrational purposes and is not intended to be generalizable across all Pulseq sequences -- more surrounding work is required for that.

## Repository Structure

```
.
├── writeGradientEcho.m          # Standard Pulseq GRE sequence (written for Siemens)
├── pulseq-ge-tools/             # MATLAB tooling and AI agent instructions
│   ├── +pulseq_ge/              # MATLAB package (lint, pipeline, report, setup)
│   ├── deps/                    # Bundled dependencies (pge2, PulCeq, DataHash)
│   ├── example_GRE_GE_seq.m     # Reference GE-compatible GRE sequence
│   ├── run_report.m             # Automated validate-fix loop for agents/CLI
│   ├── AGENTS.md                # AI agent instructions (symlinked as CLAUDE.md)
│   └── LICENSE                  # MIT License
├── CLAUDE.md                    # AI assistant instructions (GE adaptation checklist)
└── .env.example                 # Configuration template (Pulseq path, coil selection)
```

## Prerequisites

- **MATLAB** (R2020b or later recommended)
- **Pulseq toolbox** (`+mr`) — https://github.com/pulseq/pulseq

The GE conversion dependencies (PulCeq and pge2) are bundled in `pulseq-ge-tools/deps/`.

## Setup

1. Clone this repository.

2. Copy `.env.example` to `.env` and set your Pulseq toolbox path:
   ```
   PULSEQ_PATH=/path/to/pulseq-source-code/matlab
   GE_COIL=xrm
   ```

3. In MATLAB, add the tools to your path:
   ```matlab
   addpath('pulseq-ge-tools');
   pulseq_ge.setup('/path/to/pulseq/matlab');
   ```

## Usage

`run_report` combines script execution, linting, and the pipeline into a single call with machine-parseable output:

```matlab
addpath('pulseq-ge-tools');
result = run_report('mySequence_GE.m');
```

Or from the command line (e.g. MATLAB extension with VScode):

```bash
matlab -nodisplay -nosplash -nodesktop -batch \
  "addpath('pulseq-ge-tools'); run_report('mySequence_GE.m')"
```

## Supported GE Coils

| Coil | Scanner | Max Gradient (G/cm) | Max Slew (G/cm/ms) |
|------|---------|---------------------|---------------------|
| `xrmw` | MR750w | 33 | 120 |
| `xrm` | MR750 | 50 | 200 |
| `whole` | HDx WHOLE | 23 | 77 |
| `zoom` | HDx ZOOM | 40 | 150 |
| `hrmw` | Premier | 70 | 200 |
| `magnus` | MAGNUS | 300 | 750 |

## AI Assistant Integration

The `AGENTS.md` file (in `pulseq-ge-tools/`) provides structured instructions for AI coding assistants to help with GE conversion. It can be symlinked for other tools from the repo root:

```bash
# Cursor
ln -s pulseq-ge-tools/AGENTS.md .cursorrules

# GitHub Copilot
mkdir -p .github && ln -s ../pulseq-ge-tools/AGENTS.md .github/copilot-instructions.md
```
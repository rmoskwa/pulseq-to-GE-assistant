function result = run_report(scriptName, varargin)
% RUN_REPORT Automated validation loop for GE-adapted Pulseq sequences.
%
%   run_report(scriptName)
%   run_report(scriptName, 'coil', 'xrm')
%   result = run_report(...)
%
%   Runs a GE-adapted Pulseq .m script, generates the .seq file, then
%   validates using pulseq_ge.lint() and pulseq_ge.pipeline(). Outputs
%   machine-parseable PASS/FAIL results delimited by markers.
%
%   Reads PULSEQ_PATH and GE_COIL from a .env file in the current or
%   parent directory.
%
%   Input:
%     scriptName  - filename of the .m script (e.g., 'write2DGRE_GE.m')
%
%   Optional key-value parameters:
%     coil        - GE gradient coil name (default: from .env or 'xrm')
%     Any additional parameters are forwarded to pulseq_ge.pipeline()
%
%   Output format (machine-parseable):
%     Delimited by === RUN_REPORT START === and === RUN_REPORT END ===
%     Sub-sections: M_LINT, SEQ_LINT, PIPELINE, SUMMARY
%     Each section ends with a PASS/FAIL token
%
%   Example (from repo root):
%     matlab -nodisplay -nosplash -nodesktop -batch ...
%       "addpath('pulseq-ge-tools'); run_report('write2DGRE_GE.m')"

%% Parse inputs
p = inputParser;
p.KeepUnmatched = true;
p.addRequired('scriptName', @ischar);
p.addParameter('coil', '', @ischar);
p.parse(scriptName, varargin{:});

% Forward unmatched params to pipeline
unmatchedFields = fieldnames(p.Unmatched);
pipelineArgs = {};
for k = 1:numel(unmatchedFields)
    pipelineArgs{end+1} = unmatchedFields{k}; %#ok<AGROW>
    pipelineArgs{end+1} = p.Unmatched.(unmatchedFields{k}); %#ok<AGROW>
end

%% Read .env file
env = read_dotenv();

if isempty(p.Results.coil)
    if isfield(env, 'GE_COIL') && ~isempty(env.GE_COIL)
        coil = env.GE_COIL;
    else
        coil = 'xrm';
    end
else
    coil = p.Results.coil;
end

%% Setup paths
if isfield(env, 'PULSEQ_PATH') && ~isempty(env.PULSEQ_PATH)
    pulseq_ge.setup(env.PULSEQ_PATH);
else
    pulseq_ge.setup();
end

%% Detect .seq output filename from script
seqFile = detect_seq_filename(scriptName);

%% Initialize result
result.overall = false;
result.mLint = struct();
result.seqLint = struct();
result.pipeline = struct();
result.seqFile = seqFile;
result.seqGenerated = false;

%% Begin machine-parseable output
fprintf('\n=== RUN_REPORT START ===\n');
fprintf('SCRIPT: %s\n', scriptName);
fprintf('SEQ_FILE: %s\n', seqFile);

%% Generate .seq file
seqExistedBefore = exist(seqFile, 'file') == 2;
try
    run(scriptName);
    close all force;
catch ME
    % Script may fail in plotting sections — that's OK if .seq was written
    fprintf('SCRIPT_WARNING: %s\n', ME.message);
    close all force;
end

if exist(seqFile, 'file') == 2
    result.seqGenerated = true;
    fprintf('SEQ_GENERATION: PASS\n');
else
    % Fallback: look for any new .seq file
    seqFile = find_new_seq_file(seqExistedBefore);
    if ~isempty(seqFile)
        result.seqFile = seqFile;
        result.seqGenerated = true;
        fprintf('SEQ_FILE: %s\n', seqFile);
        fprintf('SEQ_GENERATION: PASS\n');
    else
        fprintf('SEQ_GENERATION: FAIL\n');
        fprintf('--- SUMMARY ---\n');
        fprintf('OVERALL: FAIL\n');
        fprintf('=== RUN_REPORT END ===\n');
        if nargout == 0, clear result; end
        return;
    end
end

%% Lint .m file
fprintf('--- M_LINT ---\n');
mLintOK = false;
try
    mResult = pulseq_ge.lint(scriptName);
    result.mLint = mResult;
    fprintf('ISSUES: %d\n', numel(mResult.issues));
    fprintf('TRID: %s\n', bool2str(mResult.tridPresent));
    fprintf('SQRT3: %s\n', bool2str(mResult.sqrtThreePresent));
    fprintf('LOOP_EVENTS: %d\n', numel(mResult.loopEvents));
    for k = 1:numel(mResult.issues)
        fprintf('ISSUE: %s\n', mResult.issues{k});
    end
    mLintOK = isempty(mResult.issues);
catch ME
    fprintf('ERROR: %s\n', ME.message);
end
fprintf('M_LINT_RESULT: %s\n', pass_fail(mLintOK));

%% Lint .seq file
fprintf('--- SEQ_LINT ---\n');
seqLintOK = false;
try
    sResult = pulseq_ge.lint(seqFile);
    result.seqLint = sResult;
    fprintf('ISSUES: %d\n', numel(sResult.issues));
    fprintf('RASTER: %s\n', bool2str(sResult.rasterOK));
    fprintf('TRID: %s\n', bool2str(sResult.tridPresent));
    fprintf('ZERO_GRADS: %d\n', sResult.zeroGrads);
    for k = 1:numel(sResult.issues)
        fprintf('ISSUE: %s\n', sResult.issues{k});
    end
    seqLintOK = isempty(sResult.issues);
catch ME
    fprintf('ERROR: %s\n', ME.message);
end
fprintf('SEQ_LINT_RESULT: %s\n', pass_fail(seqLintOK));

%% Pipeline
fprintf('--- PIPELINE ---\n');
pipelineOK = false;
try
    pResult = pulseq_ge.pipeline(seqFile, 'coil', coil, pipelineArgs{:});
    result.pipeline = pResult;
    fprintf('SEQ2CEQ: PASS\n');
    fprintf('PGE2_CHECK: PASS\n');
    fprintf('PEAK_B1: %.4f G\n', pResult.params.b1max);
    fprintf('PEAK_GRAD: %.2f G/cm\n', pResult.params.gmax);
    fprintf('PEAK_SLEW: %.1f G/cm/ms\n', pResult.params.smax);
    if pResult.validationOK
        fprintf('PGE2_VALIDATE: PASS\n');
        pipelineOK = true;
    else
        fprintf('PGE2_VALIDATE: FAIL\n');
    end
catch ME
    fprintf('PIPELINE_ERROR: %s\n', ME.message);
end
fprintf('PIPELINE_RESULT: %s\n', pass_fail(pipelineOK));

%% Summary
result.overall = mLintOK && seqLintOK && pipelineOK;
fprintf('--- SUMMARY ---\n');
fprintf('OVERALL: %s\n', pass_fail(result.overall));
fprintf('=== RUN_REPORT END ===\n');

if nargout == 0
    clear result;
end

end


%% --- Local helper functions ---

function env = read_dotenv()
% Read .env file from current directory or parent directory
    env = struct();
    envPath = '';
    if exist('.env', 'file') == 2
        envPath = '.env';
    elseif exist(fullfile('..', '.env'), 'file') == 2
        envPath = fullfile('..', '.env');
    end
    if isempty(envPath)
        return;
    end
    fid = fopen(envPath, 'r');
    if fid == -1, return; end
    cleanup = onCleanup(@() fclose(fid));
    while ~feof(fid)
        line = strtrim(fgetl(fid));
        if isempty(line) || line(1) == '#'
            continue;
        end
        eqIdx = find(line == '=', 1);
        if isempty(eqIdx), continue; end
        key = strtrim(line(1:eqIdx-1));
        val = strtrim(line(eqIdx+1:end));
        if isvarname(key)
            env.(key) = val;
        end
    end
end


function seqFile = detect_seq_filename(scriptName)
% Detect the .seq output filename by scanning for seq.write('...') in the script
    seqFile = '';
    if exist(scriptName, 'file') ~= 2
        seqFile = 'output.seq';
        return;
    end
    text = fileread(scriptName);
    tokens = regexp(text, 'seq\.write\s*\(\s*[''"]([^''"]+\.seq)[''"]', 'tokens');
    if ~isempty(tokens)
        seqFile = tokens{end}{1};  % use last match (in case of multiple)
        return;
    end
    % Fallback: look for any string ending in .seq assigned or used
    tokens = regexp(text, '[''"]([^''"]+\.seq)[''"]', 'tokens');
    if ~isempty(tokens)
        seqFile = tokens{end}{1};
        return;
    end
    seqFile = 'output.seq';
end


function seqFile = find_new_seq_file(seqExistedBefore)
% Look for any .seq file in current directory as a fallback
    seqFile = '';
    d = dir('*.seq');
    if isempty(d), return; end
    % Sort by date, newest first
    [~, idx] = sort([d.datenum], 'descend');
    d = d(idx);
    seqFile = d(1).name;
end


function s = bool2str(v)
    if v
        s = 'yes';
    else
        s = 'no';
    end
end


function s = pass_fail(v)
    if v
        s = 'PASS';
    else
        s = 'FAIL';
    end
end

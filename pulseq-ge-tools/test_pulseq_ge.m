% test_pulseq_ge.m
%
% Smoke test for the pulseq_ge package.
% Tests lint() on both a standard and a GE-adapted sequence,
% and optionally runs the full pipeline on a .seq file.
%
% Usage:
%   test_pulseq_ge           % run from the pulseq-ge-tools directory
%   test_pulseq_ge(true)     % also run the pipeline test (requires dependencies)

function test_pulseq_ge(runPipeline)

if nargin < 1
    runPipeline = false;
end

% Add this package to the path
thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

% Try to discover dependencies
try
    paths = pulseq_ge.setup();
catch
    fprintf('Warning: pulseq_ge.setup() failed. Some tests may be skipped.\n');
    paths = struct('mr', '', 'pulceq', '', 'pge2', '');
end

nPassed = 0;
nFailed = 0;
nSkipped = 0;

%% ============================================================
%% Test 1: Lint a standard Pulseq sequence (should find issues)
%% ============================================================
fprintf('\n=== Test 1: Lint standard writeGradientEcho.m ===\n');

greFile = fullfile(thisDir, '..', 'pulseq-source-code', 'matlab', 'demoSeq', 'writeGradientEcho.m');
if exist(greFile, 'file')
    try
        r = pulseq_ge.lint(greFile);

        % Should find issues (no GE raster times, no TRID, no sqrt(3))
        assert(~isempty(r.issues), ...
            'Expected issues in standard GRE, but none found');
        assert(~r.tridPresent, ...
            'Expected no TRID labels in standard GRE');
        assert(~r.sqrtThreePresent, ...
            'Expected no sqrt(3) in standard GRE');

        fprintf('  PASSED: Found %d issue(s) as expected\n', numel(r.issues));
        for k = 1:numel(r.issues)
            fprintf('    - %s\n', r.issues{k});
        end
        nPassed = nPassed + 1;
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
        nFailed = nFailed + 1;
    end
else
    fprintf('  SKIPPED: writeGradientEcho.m not found at:\n  %s\n', greFile);
    nSkipped = nSkipped + 1;
end

%% ============================================================
%% Test 2: Lint GE-adapted write2DGRE.m (should be clean or minimal)
%% ============================================================
fprintf('\n=== Test 2: Lint GE-adapted write2DGRE.m ===\n');

geFile = fullfile(thisDir, '..', 'ge-sequence-examples', 'pge2', '2DGRE', 'write2DGRE.m');
if exist(geFile, 'file')
    try
        r = pulseq_ge.lint(geFile);

        % Should have TRID labels and sqrt(3)
        assert(r.tridPresent, ...
            'Expected TRID labels in GE-adapted sequence');
        assert(r.sqrtThreePresent, ...
            'Expected sqrt(3) in GE-adapted sequence');
        assert(isempty(r.loopEvents), ...
            'Expected no event-creation inside loops');

        fprintf('  PASSED: TRID present, sqrt(3) present, no loop events\n');
        if ~isempty(r.issues)
            fprintf('  Note: %d issue(s) found (may be acceptable):\n', numel(r.issues));
            for k = 1:numel(r.issues)
                fprintf('    - %s\n', r.issues{k});
            end
        end
        nPassed = nPassed + 1;
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
        nFailed = nFailed + 1;
    end
else
    fprintf('  SKIPPED: write2DGRE.m not found at:\n  %s\n', geFile);
    nSkipped = nSkipped + 1;
end

%% ============================================================
%% Test 3: Lint a .seq file (requires +mr on path)
%% ============================================================
fprintf('\n=== Test 3: Lint gre2d.seq ===\n');

seqFile = fullfile(thisDir, '..', 'gre2d.seq');
if exist(seqFile, 'file') && ~isempty(paths.mr)
    try
        r = pulseq_ge.lint(seqFile);

        fprintf('  PASSED: Lint completed\n');
        fprintf('    TRID present:  %s\n', bool2str(r.tridPresent));
        fprintf('    Raster OK:     %s\n', bool2str(r.rasterOK));
        fprintf('    Zero grads:    %d\n', r.zeroGrads);
        if ~isempty(r.issues)
            fprintf('    Issues:\n');
            for k = 1:numel(r.issues)
                fprintf('      - %s\n', r.issues{k});
            end
        end
        nPassed = nPassed + 1;
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
        nFailed = nFailed + 1;
    end
else
    if ~exist(seqFile, 'file')
        fprintf('  SKIPPED: gre2d.seq not found\n');
    else
        fprintf('  SKIPPED: +mr not on path\n');
    end
    nSkipped = nSkipped + 1;
end

%% ============================================================
%% Test 4: Full pipeline (optional)
%% ============================================================
fprintf('\n=== Test 4: Full pipeline on gre2d.seq ===\n');

if ~runPipeline
    fprintf('  SKIPPED: pass true to run pipeline test\n');
    nSkipped = nSkipped + 1;
elseif ~exist(seqFile, 'file') || isempty(paths.mr) || ...
       isempty(paths.pulceq) || isempty(paths.pge2)
    fprintf('  SKIPPED: missing dependencies\n');
    nSkipped = nSkipped + 1;
else
    try
        result = pulseq_ge.pipeline(seqFile, 'coil', 'xrm');

        assert(result.validationOK, 'Validation failed');
        fprintf('  PASSED: Pipeline completed successfully\n');
        fprintf('    Peak B1:   %.4f G\n', result.params.b1max);
        fprintf('    Peak grad: %.2f G/cm\n', result.params.gmax);
        fprintf('    Peak slew: %.1f G/cm/ms\n', result.params.smax);
        nPassed = nPassed + 1;
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
        nFailed = nFailed + 1;
    end
end

%% ============================================================
%% Test 5: Report generation (optional)
%% ============================================================
fprintf('\n=== Test 5: Report generation ===\n');

if ~runPipeline
    fprintf('  SKIPPED: pass true to run report test\n');
    nSkipped = nSkipped + 1;
elseif ~exist(seqFile, 'file') || isempty(paths.mr) || ...
       isempty(paths.pulceq) || isempty(paths.pge2)
    fprintf('  SKIPPED: missing dependencies\n');
    nSkipped = nSkipped + 1;
else
    try
        txt = pulseq_ge.report(seqFile, 'coil', 'xrm');
        assert(~isempty(txt), 'Report is empty');
        fprintf('  PASSED: Report generated (%d lines)\n', numel(txt));
        fprintf('\n--- Report preview ---\n');
        for k = 1:min(numel(txt), 20)
            fprintf('%s', txt{k});
        end
        if numel(txt) > 20
            fprintf('... (%d more lines)\n', numel(txt) - 20);
        end
        nPassed = nPassed + 1;
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
        nFailed = nFailed + 1;
    end
end

%% ============================================================
%% Summary
%% ============================================================
fprintf('\n=== Summary ===\n');
fprintf('  Passed:  %d\n', nPassed);
fprintf('  Failed:  %d\n', nFailed);
fprintf('  Skipped: %d\n', nSkipped);
fprintf('\n');

if nFailed > 0
    error('test_pulseq_ge: %d test(s) failed', nFailed);
end

end


function s = bool2str(v)
    if v
        s = 'yes';
    else
        s = 'no';
    end
end

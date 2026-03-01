function result = report(filepath, varargin)
% REPORT Generate a human-readable GE compatibility report.
%
%   pulseq_ge.report(filepath)
%   pulseq_ge.report(filepath, 'coil', 'xrm')
%   result = pulseq_ge.report(...)
%
%   Combines lint() analysis with pipeline() results (for .seq files)
%   and prints a formatted report to the console.
%
%   Input:
%     filepath   - path to a .m or .seq file
%
%   Optional key-value parameters: same as pulseq_ge.pipeline()
%
%   Optionally returns a struct with fields:
%     lint       - the lint result struct
%     pipeline   - the pipeline result struct (empty for .m files)

assert(exist(filepath, 'file') == 2, 'File not found: %s', filepath);

[~, fname, ext] = fileparts(filepath);

result.lint = [];
result.pipeline = [];

%% Header
fprintf('\n=== Pulseq-GE Compatibility Report ===\n');
fprintf('File: %s%s\n', fname, ext);
fprintf('Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));

%% Lint results
fprintf('\n--- Static Analysis ---\n');
try
    lintResult = lint(filepath);
    result.lint = lintResult;

    if isempty(lintResult.issues)
        fprintf('  No issues found.\n');
    else
        for k = 1:numel(lintResult.issues)
            fprintf('  [%d] %s\n', k, lintResult.issues{k});
        end
    end

    fprintf('\n');
    fprintf('  TRID labels:   %s\n', bool2str(lintResult.tridPresent));
    fprintf('  sqrt(3):       %s\n', bool2str(lintResult.sqrtThreePresent));

    if strcmpi(ext, '.seq')
        fprintf('  Raster OK:     %s\n', bool2str(lintResult.rasterOK));
        fprintf('  Zero-amp grads: %d\n', lintResult.zeroGrads);
    end

    if ~isempty(lintResult.loopEvents)
        fprintf('  Loop events:   %d occurrence(s)\n', numel(lintResult.loopEvents));
        for k = 1:numel(lintResult.loopEvents)
            fprintf('    - %s (line %d)\n', lintResult.loopEvents(k).name, lintResult.loopEvents(k).line);
        end
    end
catch ME
    fprintf('  Lint error: %s\n', ME.message);
end

%% Pipeline results (only for .seq files)
if strcmpi(ext, '.seq')
    fprintf('\n--- Pipeline Validation ---\n');
    try
        pipeResult = pulseq_ge.pipeline(filepath, varargin{:});
        result.pipeline = pipeResult;

        fprintf('  seq2ceq:       OK\n');
        fprintf('  pge2.check:    OK\n');
        fprintf('    Peak B1:     %.4f G\n', pipeResult.params.b1max);
        fprintf('    Peak grad:   %.2f G/cm\n', pipeResult.params.gmax);
        fprintf('    Peak slew:   %.1f G/cm/ms\n', pipeResult.params.smax);
        if pipeResult.validationOK
            fprintf('  pge2.validate: PASSED\n');
        else
            fprintf('  pge2.validate: FAILED\n');
        end
    catch ME
        fprintf('  Pipeline error: %s\n', ME.message);
    end
else
    fprintf('\n--- Pipeline Validation ---\n');
    fprintf('  Skipped (pipeline requires a .seq file)\n');
end

fprintf('\n======================================\n\n');

% Suppress ans display when output is not captured
if nargout == 0
    clear result;
end

end


function s = bool2str(v)
    if v
        s = 'yes';
    else
        s = 'NO';
    end
end

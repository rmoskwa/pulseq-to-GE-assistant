function result = lint(filepath)
% LINT Static analysis of a Pulseq .m or .seq file for GE compatibility.
%
%   result = lint(filepath)
%
%   For .m files: regex-based analysis of the MATLAB source code.
%   For .seq files: loads via mr.Sequence and inspects events.
%
%   Returns a struct with fields:
%     issues           - cell array of human-readable issue descriptions
%     rasterOK         - true if all raster checks pass (N/A for .m)
%     tridPresent      - true if TRID labels are found
%     zeroGrads        - count of zero-amplitude gradient events (0 for .m)
%     sqrtThreePresent - true if /sqrt(3) found in gradient limits
%     loopEvents       - struct array of event-creation calls inside loops

assert(exist(filepath, 'file') == 2, 'File not found: %s', filepath);

[~, ~, ext] = fileparts(filepath);

if strcmpi(ext, '.m')
    result = lint_mfile(filepath);
elseif strcmpi(ext, '.seq')
    result = lint_seqfile(filepath);
else
    error('Unsupported file type: %s (expected .m or .seq)', ext);
end

end


function result = lint_mfile(filepath)
% Lint a MATLAB .m file using text-based analysis

    result.issues = {};
    result.rasterOK = true;     % N/A for .m — set true by default
    result.tridPresent = false;
    result.zeroGrads = 0;
    result.sqrtThreePresent = false;
    result.loopEvents = struct('name', {}, 'line', {});

    text = fileread(filepath);

    %% 1. Check mr.opts() call
    optsInfo = parse_opts_call(text);

    if ~optsInfo.found
        result.issues{end+1} = 'No mr.opts() call found in file';
    else
        if ~optsInfo.hasGradRaster
            result.issues{end+1} = ...
                'Missing or incorrect gradRasterTime (need 4e-6) in mr.opts()';
        end
        if ~optsInfo.hasRfRaster
            result.issues{end+1} = ...
                'Missing or incorrect rfRasterTime (need 2e-6 or 4e-6) in mr.opts()';
        end
        if ~optsInfo.hasAdcRaster
            result.issues{end+1} = ...
                'Missing or incorrect adcRasterTime (need 2e-6) in mr.opts()';
        end
        if ~optsInfo.hasBlockRaster
            result.issues{end+1} = ...
                'Missing or incorrect blockDurationRaster (need 4e-6) in mr.opts()';
        end
    end

    %% 2. Check for sqrt(3) in gradient limits
    result.sqrtThreePresent = optsInfo.hasSqrt3;
    if ~result.sqrtThreePresent
        % Also check outside opts call — some users divide separately
        result.sqrtThreePresent = ~isempty(regexp(text, ...
            '(maxGrad|maxSlew|max_grad|max_slew).*?/\s*sqrt\s*\(\s*3\s*\)', ...
            'ignorecase', 'once'));
    end
    if ~result.sqrtThreePresent
        result.issues{end+1} = ...
            'Gradient limits not divided by sqrt(3) for oblique support';
    end

    %% 3. Check for events created inside loops
    result.loopEvents = find_loop_events(text);
    if ~isempty(result.loopEvents)
        names = unique({result.loopEvents.name});
        result.issues{end+1} = sprintf( ...
            'Event-creation function(s) inside loop: %s', strjoin(names, ', '));
    end

    %% 4. Check for TRID labels
    tridPattern = 'makeLabel\s*\(\s*[''"]SET[''"].*?[''"]TRID[''"]';
    result.tridPresent = ~isempty(regexp(text, tridPattern, 'ignorecase', 'once'));
    if ~result.tridPresent
        result.issues{end+1} = 'No TRID labels found — segments are not marked';
    end

    %% 5. Check for mr.rotate or mr.rotate3D calls
    rotatePattern = 'mr\.rotate\s*\(|mr\.rotate3D\s*\(';
    lines = strsplit(text, '\n');
    hasRotateCall = false;
    for k = 1:numel(lines)
        ln = strtrim(lines{k});
        if ~startsWith(ln, '%') && ~isempty(regexp(ln, rotatePattern, 'once'))
            hasRotateCall = true;
            break;
        end
    end
    if hasRotateCall
        result.issues{end+1} = ...
            'Uses mr.rotate() or mr.rotate3D() — should use rotation events instead';
    end

    %% 6. Check for zero-amplitude gradient patterns near scaleGrad
    zeroScalePattern = 'scaleGrad\s*\([^,]+,\s*0\s*\)';
    hasZeroScale = false;
    for k = 1:numel(lines)
        ln = strtrim(lines{k});
        if ~startsWith(ln, '%') && ~isempty(regexp(ln, zeroScalePattern, 'once'))
            hasZeroScale = true;
            break;
        end
    end
    if hasZeroScale
        result.issues{end+1} = ...
            'scaleGrad() called with amplitude 0 — use eps instead';
    end

end


function result = lint_seqfile(filepath)
% Lint a .seq file by loading it and inspecting events

    result.issues = {};
    result.rasterOK = true;
    result.tridPresent = false;
    result.zeroGrads = 0;
    result.sqrtThreePresent = false;   % N/A for .seq
    result.loopEvents = struct('name', {}, 'line', {});  % N/A for .seq

    % Load the sequence
    seq = mr.Sequence();
    seq.read(filepath);

    % Run raster checks
    rasterResult = check_raster(seq);

    result.tridPresent = rasterResult.tridPresent;
    result.zeroGrads = rasterResult.zeroGrads;

    if ~rasterResult.blockRasterOK
        result.rasterOK = false;
        for k = 1:numel(rasterResult.blockIssues)
            result.issues{end+1} = rasterResult.blockIssues{k}; %#ok<AGROW>
        end
    end

    if ~rasterResult.rfRasterOK
        result.rasterOK = false;
        for k = 1:numel(rasterResult.rfIssues)
            result.issues{end+1} = rasterResult.rfIssues{k}; %#ok<AGROW>
        end
    end

    if ~rasterResult.adcRasterOK
        result.rasterOK = false;
        for k = 1:numel(rasterResult.adcIssues)
            result.issues{end+1} = rasterResult.adcIssues{k}; %#ok<AGROW>
        end
    end

    if ~result.tridPresent
        result.issues{end+1} = 'No TRID labels found in .seq file';
    end

    if result.zeroGrads > 0
        result.issues{end+1} = sprintf( ...
            '%d zero-amplitude gradient event(s) found — use eps instead of 0', ...
            result.zeroGrads);
    end

end

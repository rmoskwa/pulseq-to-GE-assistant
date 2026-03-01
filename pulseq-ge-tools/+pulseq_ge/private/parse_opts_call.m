function info = parse_opts_call(text)
% PARSE_OPTS_CALL Extract mr.opts() parameters from MATLAB source text.
%
%   info = parse_opts_call(text)
%
%   Parses the source text for calls to mr.opts() and checks whether
%   GE-required raster time parameters are specified.
%
%   Returns a struct with fields:
%     found            - true if mr.opts() call was found
%     hasGradRaster    - true if gradRasterTime is set to 4e-6
%     hasRfRaster      - true if rfRasterTime is set to 2e-6 or 4e-6
%     hasAdcRaster     - true if adcRasterTime is set to 2e-6
%     hasBlockRaster   - true if blockDurationRaster is set to 4e-6
%     hasSqrt3         - true if /sqrt(3) appears near gradient limits
%     rawMatch         - the matched mr.opts() text (for debugging)

info.found = false;
info.hasGradRaster = false;
info.hasRfRaster = false;
info.hasAdcRaster = false;
info.hasBlockRaster = false;
info.hasSqrt3 = false;
info.rawMatch = '';

% Remove comments (lines starting with %)
lines = strsplit(text, '\n');
cleanLines = {};
for k = 1:numel(lines)
    ln = strtrim(lines{k});
    if ~startsWith(ln, '%')
        cleanLines{end+1} = lines{k}; %#ok<AGROW>
    end
end
cleanText = strjoin(cleanLines, '\n');

% Find mr.opts() call — may span multiple lines via ...
% Look for the pattern: mr.opts(...)
optsPattern = 'mr\.opts\s*\(';
optsStart = regexp(cleanText, optsPattern, 'start');
if isempty(optsStart)
    return;
end

info.found = true;

% Extract from the first mr.opts( to its closing paren
% Handle continuation lines (...) by working with the clean text
startIdx = optsStart(1);
parenDepth = 0;
endIdx = startIdx;
for k = startIdx:numel(cleanText)
    if cleanText(k) == '('
        parenDepth = parenDepth + 1;
    elseif cleanText(k) == ')'
        parenDepth = parenDepth - 1;
        if parenDepth == 0
            endIdx = k;
            break;
        end
    end
end

optsText = cleanText(startIdx:endIdx);
info.rawMatch = optsText;

% Check for raster time parameters
% gradRasterTime = 4e-6
info.hasGradRaster = ~isempty(regexp(optsText, ...
    '[''"]gradRasterTime[''"].*?4e-6', 'ignorecase', 'once'));

% rfRasterTime = 2e-6 or 4e-6
info.hasRfRaster = ~isempty(regexp(optsText, ...
    '[''"]rfRasterTime[''"].*?[24]e-6', 'ignorecase', 'once'));

% adcRasterTime = 2e-6
info.hasAdcRaster = ~isempty(regexp(optsText, ...
    '[''"]adcRasterTime[''"].*?2e-6', 'ignorecase', 'once'));

% blockDurationRaster = 4e-6
info.hasBlockRaster = ~isempty(regexp(optsText, ...
    '[''"]blockDurationRaster[''"].*?4e-6', 'ignorecase', 'once'));

% Check for /sqrt(3) in gradient specification
info.hasSqrt3 = ~isempty(regexp(optsText, '/\s*sqrt\s*\(\s*3\s*\)', 'once'));

end

function events = find_loop_events(text)
% FIND_LOOP_EVENTS Detect event-creation functions called inside loops.
%
%   events = find_loop_events(text)
%
%   Scans MATLAB source text for calls to mr.make* functions that appear
%   inside for/while blocks. These create new events each iteration,
%   breaking the GE base-block model.
%
%   Allowed inside loops:
%     mr.makeDelay, mr.scaleGrad, mr.makeLabel
%
%   Returns a struct array with fields:
%     name     - the function name (e.g., 'mr.makeTrapezoid')
%     line     - approximate line number

events = struct('name', {}, 'line', {});

% Event-creation functions that should NOT be inside loops
badPatterns = { ...
    'mr\.makeTrapezoid', ...
    'mr\.makeSincPulse', ...
    'mr\.makeGaussPulse', ...
    'mr\.makeBlockPulse', ...
    'mr\.makeArbitraryRf', ...
    'mr\.makeArbitraryGrad', ...
    'mr\.makeAdc', ...
    'mr\.makeExtendedTrapezoid', ...
    'mr\.makeExtendedTrapezoidArea', ...
    'mr\.makeSpiralGradient', ...
};

lines = strsplit(text, '\n');

% Use a stack to track block nesting. Each entry is the keyword
% that opened the block ('for', 'while', 'if', 'switch', 'try', 'function').
% We count how many stack entries are 'for' or 'while' to get loopDepth.
blockStack = {};

for lineNum = 1:numel(lines)
    ln = strtrim(lines{lineNum});

    % Skip comment lines
    if startsWith(ln, '%')
        continue;
    end

    % Remove inline comments
    commentIdx = strfind(ln, '%');
    if ~isempty(commentIdx)
        ln = ln(1:commentIdx(1)-1);
    end

    % Detect block-opening keywords
    openers = regexp(ln, '\b(for|while|if|switch|try|function)\b', 'match');
    for k = 1:numel(openers)
        blockStack{end+1} = openers{k}; %#ok<AGROW>
    end

    % Detect 'end' keywords and pop from stack
    endMatches = regexp(ln, '\bend\b', 'match');
    for k = 1:numel(endMatches)
        if ~isempty(blockStack)
            blockStack(end) = [];
        end
    end

    % Count loop depth = number of 'for' or 'while' entries on the stack
    loopDepth = sum(strcmp(blockStack, 'for') | strcmp(blockStack, 'while'));

    % Only check for bad patterns inside loops
    if loopDepth > 0
        for k = 1:numel(badPatterns)
            match = regexp(ln, badPatterns{k}, 'match', 'once');
            if ~isempty(match)
                events(end+1).name = strrep(match, '\.', '.'); %#ok<AGROW>
                events(end).line = lineNum;
            end
        end
    end
end

end

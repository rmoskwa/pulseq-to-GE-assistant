function paths = setup(varargin)
% SETUP Add paths for Pulseq, PulCeq, and pge2 dependencies.
%
%   pulseq_ge.setup('path1', 'path2', ...)
%
%   Calls addpath(genpath(...)) on each argument to add it and all
%   subdirectories, then verifies that +mr, seq2ceq, and +pge2 are
%   reachable. Reports which dependencies are found.
%
%   With no arguments, just checks what is already on the path.
%
%   Examples:
%     % Add a single root containing all dependencies
%     pulseq_ge.setup('/repos/my-pulseq-project');
%
%     % Or add each dependency separately
%     pulseq_ge.setup('/repos/pulseq', '/repos/PulCeq', '/repos/pge2');
%
%     % Or if already on path:
%     pulseq_ge.setup();

%% Add all supplied paths
for k = 1:numel(varargin)
    p = varargin{k};
    assert(ischar(p) || isstring(p), 'Arguments must be path strings');
    assert(isfolder(p), 'Directory not found: %s', p);
    addpath(genpath(p));
end

%% Verify each dependency is now reachable
% Note: exist('pkg.func', 'file') returns 0 for +package functions,
% so we use which() instead.
paths.mr = '';
paths.pulceq = '';
paths.pge2 = '';

w = which('mr.opts');
if ~isempty(w)
    paths.mr = fileparts(fileparts(w));   % parent of +mr/
end

w = which('seq2ceq');
if ~isempty(w)
    paths.pulceq = fileparts(w);
end

w = which('pge2.opts');
if ~isempty(w)
    paths.pge2 = fileparts(fileparts(w)); % parent of +pge2/
end

%% Print status summary
fprintf('\n--- pulseq_ge.setup() ---\n');
print_status('Pulseq (+mr)', paths.mr);
print_status('PulCeq (seq2ceq)', paths.pulceq);
print_status('pge2 (+pge2)', paths.pge2);
fprintf('-------------------------\n\n');

end


function print_status(name, foundPath)
    if isempty(foundPath)
        fprintf('  [NOT FOUND] %s\n', name);
    else
        fprintf('  [OK] %s: %s\n', name, foundPath);
    end
end

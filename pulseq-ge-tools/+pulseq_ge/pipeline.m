function result = pipeline(seqfile, varargin)
% PIPELINE Run the full seq2ceq -> pge2.check -> pge2.validate chain.
%
%   result = pulseq_ge.pipeline(seqfile)
%   result = pulseq_ge.pipeline(seqfile, 'coil', 'xrm')
%   result = pulseq_ge.pipeline(seqfile, 'coil', 'xrm', 'psd_rf_wait', 100e-6)
%
%   Converts a .seq file to a Ceq struct, checks it against GE hardware
%   parameters, and validates the conversion.
%
%   Input:
%     seqfile   - path to a .seq file
%
%   Optional key-value parameters:
%     psd_rf_wait    - RF wait time [s]         (default: 100e-6)
%     psd_grd_wait   - gradient wait time [s]   (default: 100e-6)
%     b1_max         - max B1 [Gauss]           (default: 0.25)
%     g_max          - max gradient [G/cm]      (default: 5)
%     slew_max       - max slew [G/cm/ms]       (default: 20)
%     coil           - gradient coil name        (default: 'xrm')
%     pislquant      - # calibration TRs        (default: 1)
%     PNSwt          - PNS channel weights [3x1] (default: [1 1 1])
%
%   Returns a struct with fields:
%     ceq            - the PulCeq struct
%     sysGE          - GE system parameters struct
%     params         - struct with b1max, gmax, smax from pge2.check
%     validationOK   - true if pge2.validate passes

assert(exist(seqfile, 'file') == 2, 'File not found: %s', seqfile);

%% Parse optional arguments
p = inputParser;
p.addParameter('psd_rf_wait', 100e-6, @isnumeric);
p.addParameter('psd_grd_wait', 100e-6, @isnumeric);
p.addParameter('b1_max', 0.25, @isnumeric);
p.addParameter('g_max', 5, @isnumeric);
p.addParameter('slew_max', 20, @isnumeric);
p.addParameter('coil', 'xrm', @ischar);
p.addParameter('pislquant', 1, @isnumeric);
p.addParameter('PNSwt', [1 1 1], @isnumeric);
p.parse(varargin{:});
args = p.Results;

%% Step 1: Convert .seq to Ceq
fprintf('Step 1/4: Converting .seq to Ceq... ');
try
    ceq = seq2ceq(seqfile);
    fprintf('done\n');
catch ME
    error('seq2ceq failed: %s', ME.message);
end

%% Step 2: Create GE system parameters
fprintf('Step 2/4: Setting GE hardware parameters (coil: %s)... ', args.coil);
try
    sysGE = pge2.opts(args.psd_rf_wait, args.psd_grd_wait, ...
        args.b1_max, args.g_max, args.slew_max, args.coil);
    fprintf('done\n');
catch ME
    error('pge2.opts failed: %s', ME.message);
end

%% Step 3: Check sequence
fprintf('Step 3/4: Running pge2.check... ');
try
    params = pge2.check(ceq, sysGE, 'PNSwt', args.PNSwt);
    fprintf('done\n');
    fprintf('  Peak B1: %.4f G\n', params.b1max);
    fprintf('  Peak gradient: %.2f G/cm\n', params.gmax);
    fprintf('  Peak slew: %.1f G/cm/ms\n', params.smax);
catch ME
    error('pge2.check failed: %s', ME.message);
end

%% Step 4: Validate
fprintf('Step 4/4: Running pge2.validate... ');
validationOK = false;
try
    seq2 = mr.Sequence();
    seq2.read(seqfile);
    validationOK = pge2.validate(ceq, sysGE, seq2, [], ...
        'row', [], 'plot', false);
    if validationOK
        fprintf('PASSED\n');
    else
        fprintf('FAILED\n');
    end
catch ME
    fprintf('ERROR: %s\n', ME.message);
end

%% Build result
result.ceq = ceq;
result.sysGE = sysGE;
result.params = params;
result.validationOK = validationOK;

end

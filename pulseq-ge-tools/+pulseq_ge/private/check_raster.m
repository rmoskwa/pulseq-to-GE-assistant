function result = check_raster(seq)
% CHECK_RASTER Validate raster alignment of events in a Pulseq sequence object.
%
%   result = check_raster(seq)
%
%   Checks that block durations, RF durations, and ADC dwell times
%   align with GE raster time requirements.
%
%   Input:
%     seq   - an mr.Sequence object (already loaded)
%
%   Returns a struct with fields:
%     blockRasterOK   - true if all block durations are multiples of 4us
%     rfRasterOK      - true if all RF durations are multiples of 2us
%     adcRasterOK     - true if all ADC dwell times are multiples of 2us
%     blockIssues     - cell array of issue description strings
%     rfIssues        - cell array of issue description strings
%     adcIssues       - cell array of issue description strings
%     zeroGrads       - number of zero-amplitude gradient events found
%     tridPresent     - true if TRID labels are found

GE_BLOCK_RASTER = 4e-6;
GE_RF_RASTER = 2e-6;
GE_ADC_RASTER = 2e-6;
TOL = 1e-10;

result.blockRasterOK = true;
result.rfRasterOK = true;
result.adcRasterOK = true;
result.blockIssues = {};
result.rfIssues = {};
result.adcIssues = {};
result.zeroGrads = 0;
result.tridPresent = false;

nBlocks = numel(seq.blockEvents);
if nBlocks == 0
    return;
end

for n = 1:nBlocks
    block = seq.getBlock(n);

    % Check block duration raster
    dur = mr.calcDuration(block);
    remainder = mod(dur, GE_BLOCK_RASTER);
    if remainder > TOL && (GE_BLOCK_RASTER - remainder) > TOL
        result.blockRasterOK = false;
        result.blockIssues{end+1} = sprintf( ...
            'Block %d: duration %.6f us not on 4us raster', n, dur*1e6);
    end

    % Check RF raster
    if isfield(block, 'rf') && ~isempty(block.rf)
        rfDur = numel(block.rf.signal) * block.rf.t(end) / max(numel(block.rf.t)-1, 1);
        % More reliable: check the shape duration
        if isfield(block.rf, 'shape_dur')
            rfDur = block.rf.shape_dur;
        end
        remainder = mod(rfDur, GE_RF_RASTER);
        if remainder > TOL && (GE_RF_RASTER - remainder) > TOL
            result.rfRasterOK = false;
            result.rfIssues{end+1} = sprintf( ...
                'Block %d: RF duration %.6f us not on 2us raster', n, rfDur*1e6);
        end
    end

    % Check ADC dwell time raster
    if isfield(block, 'adc') && ~isempty(block.adc) && block.adc.numSamples > 0
        dwellTime = block.adc.dwell;
        remainder = mod(dwellTime, GE_ADC_RASTER);
        if remainder > TOL && (GE_ADC_RASTER - remainder) > TOL
            result.adcRasterOK = false;
            result.adcIssues{end+1} = sprintf( ...
                'Block %d: ADC dwell %.6f us not a multiple of 2us', n, dwellTime*1e6);
        end
    end

    % Check for zero-amplitude gradients
    gradChannels = {'gx', 'gy', 'gz'};
    for ch = 1:3
        chName = gradChannels{ch};
        if isfield(block, chName) && ~isempty(block.(chName))
            g = block.(chName);
            if isfield(g, 'amplitude') && g.amplitude == 0
                result.zeroGrads = result.zeroGrads + 1;
            elseif isfield(g, 'waveform') && all(g.waveform == 0)
                result.zeroGrads = result.zeroGrads + 1;
            end
        end
    end

    % Check for TRID labels
    if isfield(block, 'label') && ~isempty(block.label)
        labels = block.label;
        if ~iscell(labels)
            labels = {labels};
        end
        for lbl = 1:numel(labels)
            if isfield(labels{lbl}, 'label') && strcmpi(labels{lbl}.label, 'TRID')
                result.tridPresent = true;
            end
        end
    end
end

end

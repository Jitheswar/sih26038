function minimumArea = defaultLesionMinimumArea(lesionTypes)
%DEFAULTLESIONMINIMUMAREA Smallest component size kept, per lesion type.
%   MINIMUMAREA = segment.defaultLesionMinimumArea(LESIONTYPES) returns the
%   default minimum connected-component area, in pixels, for each lesion
%   type in LESIONTYPES.
%
%   The defaults follow the physical scale of each lesion at the IDRiD
%   capture resolution.  Microaneurysms are the smallest object the pipeline
%   looks for and §3.2 warns they sit near the resolution limit, so their
%   floor is deliberately low; haemorrhages and exudates are larger and a
%   component of a handful of pixels is far more likely to be noise.
%
%   This lives in one function because two callers depend on the same
%   numbers and a silent divergence between them would be invisible in the
%   results: segment.lesionEvidence uses them at the operating thresholds,
%   and eval/lesionThresholdTransfer.m uses them while sweeping candidate
%   thresholds.  A sweep run at a different area floor than the pipeline
%   would select thresholds the pipeline never reproduces.

if ischar(lesionTypes)
    lesionTypes = {lesionTypes};
end
if ~iscell(lesionTypes)
    error('segment:InvalidLesionTypes', ...
        'Lesion types must be a cell array of character vectors.');
end

defaults = struct('MA', 3, 'HE', 10, 'EX', 10, 'SE', 20);
typeCount = numel(lesionTypes);
minimumArea = zeros(typeCount, 1);
for typeIndex = 1:typeCount
    lesionType = lesionTypes{typeIndex};
    if isfield(defaults, lesionType)
        minimumArea(typeIndex) = defaults.(lesionType);
    else
        minimumArea(typeIndex) = 1;
    end
end
end

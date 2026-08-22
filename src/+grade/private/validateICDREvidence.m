function evidence = validateICDREvidence(inputEvidence)
%VALIDATEICDREVIDENCE Validate and normalize structured ICDR evidence.

if ~isstruct(inputEvidence) || ~isscalar(inputEvidence)
    error('grade:InvalidEvidence', ...
        'ICDR evidence must be one scalar structure.');
end

requiredFields = { ...
    'microaneurysmCount', ...
    'haemorrhageCountPerQuadrant', ...
    'hardExudateCount', ...
    'softExudateCount', ...
    'venousBeadingPerQuadrant', ...
    'irmaPerQuadrant', ...
    'neovascularisation'};
for index = 1:numel(requiredFields)
    fieldName = requiredFields{index};
    if ~isfield(inputEvidence, fieldName)
        error('grade:MissingEvidenceField', ...
            'ICDR evidence is missing required field "%s".', fieldName);
    end
end

evidence = struct();
evidence.microaneurysmCount = localCountItem( ...
    inputEvidence.microaneurysmCount, 'microaneurysmCount');
evidence.haemorrhageCountPerQuadrant = localCountVectorItem( ...
    inputEvidence.haemorrhageCountPerQuadrant, ...
    'haemorrhageCountPerQuadrant');
evidence.hardExudateCount = localCountItem( ...
    inputEvidence.hardExudateCount, 'hardExudateCount');
evidence.softExudateCount = localCountItem( ...
    inputEvidence.softExudateCount, 'softExudateCount');
evidence.venousBeadingPerQuadrant = localLogicalVectorItem( ...
    inputEvidence.venousBeadingPerQuadrant, ...
    'venousBeadingPerQuadrant');
evidence.irmaPerQuadrant = localLogicalVectorItem( ...
    inputEvidence.irmaPerQuadrant, 'irmaPerQuadrant');
evidence.neovascularisation = localLogicalItem( ...
    inputEvidence.neovascularisation, 'neovascularisation');
if isfield(inputEvidence, 'vitreousOrPreretinalHaemorrhage')
    evidence.vitreousOrPreretinalHaemorrhage = localLogicalItem( ...
        inputEvidence.vitreousOrPreretinalHaemorrhage, ...
        'vitreousOrPreretinalHaemorrhage');
elseif isfield(inputEvidence, 'vitreousHaemorrhage') && ...
        isfield(inputEvidence, 'preretinalHaemorrhage')
    vitreous = localLogicalItem(inputEvidence.vitreousHaemorrhage, ...
        'vitreousHaemorrhage');
    preretinal = localLogicalItem(inputEvidence.preretinalHaemorrhage, ...
        'preretinalHaemorrhage');
    evidence.vitreousOrPreretinalHaemorrhage = localLogicalOrItem( ...
        vitreous, preretinal);
else
    error('grade:MissingEvidenceField', ...
        ['ICDR evidence must contain vitreousOrPreretinalHaemorrhage, ', ...
        'or both vitreousHaemorrhage and preretinalHaemorrhage.']);
end

evidence.evidenceSource = localTextField(inputEvidence, ...
    'evidenceSource', 'unspecified evidence source');
evidence.clinicalValidationStatus = localTextField(inputEvidence, ...
    'clinicalValidationStatus', 'not clinically validated');
end

function item = localCountItem(item, fieldName)
item = localEvidenceItem(item, fieldName);
if ~item.known
    return;
end
if ~isnumeric(item.value) || ~isscalar(item.value) || ~isreal(item.value) || ...
        ~isfinite(item.value) || item.value < 0 || item.value ~= floor(item.value)
    error('grade:InvalidEvidenceValue', ...
        '%s must be a non-negative integer count when known.', fieldName);
end
item.value = double(item.value);
end

function item = localCountVectorItem(item, fieldName)
item = localEvidenceItem(item, fieldName);
if ~item.known
    return;
end
value = localQuadrantValue(item.value, fieldName, false);
if ~isnumeric(value) || ~isreal(value) || numel(value) ~= 4 || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || ...
        any(value(:) ~= floor(value(:)))
    error('grade:InvalidEvidenceValue', ...
        '%s must contain four non-negative integer counts when known.', fieldName);
end
item.value = double(value(:)).';
end

function item = localLogicalVectorItem(item, fieldName)
item = localEvidenceItem(item, fieldName);
if ~item.known
    return;
end
value = localQuadrantValue(item.value, fieldName, true);
if ~islogical(value) || numel(value) ~= 4
    error('grade:InvalidEvidenceValue', ...
        '%s must contain four logical values when known.', fieldName);
end
item.value = logical(value(:)).';
end

function value = localQuadrantValue(value, fieldName, logicalExpected)
if isstruct(value) && isscalar(value)
    labels = {'ST', 'IT', 'SN', 'IN'};
    if ~all(isfield(value, labels))
        error('grade:InvalidEvidenceValue', ...
            '%s must contain ST, IT, SN, and IN quadrant values.', fieldName);
    end
    value = reshape([value.ST, value.IT, value.SN, value.IN], 1, 4);
elseif ~(isnumeric(value) || (logicalExpected && islogical(value)))
    return;
end
end

function item = localLogicalItem(item, fieldName)
item = localEvidenceItem(item, fieldName);
if ~item.known
    return;
end
if ~islogical(item.value) || ~isscalar(item.value)
    error('grade:InvalidEvidenceValue', ...
        '%s must be one logical value when known.', fieldName);
end
item.value = logical(item.value);
end

function item = localEvidenceItem(item, fieldName)
if ~isstruct(item) || ~isscalar(item) || ...
        ~isfield(item, 'value') || ~isfield(item, 'known')
    error('grade:InvalidEvidenceItem', ...
        '%s must be a structure with value and known fields.', fieldName);
end
if ~islogical(item.known) || ~isscalar(item.known)
    error('grade:InvalidEvidenceKnownStatus', ...
        '%s.known must be a logical scalar; use false with an empty value for unknown evidence.', ...
        fieldName);
end
if ~item.known && ~isempty(item.value)
    error('grade:InvalidEvidenceUnknown', ...
        '%s must use an empty value when known is false.', fieldName);
end
end

function item = localLogicalOrItem(first, second)
item = struct();
if (first.known && first.value) || (second.known && second.value)
    item.value = true;
    item.known = true;
elseif first.known && second.known
    item.value = false;
    item.known = true;
else
    item.value = [];
    item.known = false;
end
end

function value = localTextField(inputEvidence, fieldName, defaultValue)
if ~isfield(inputEvidence, fieldName) || isempty(inputEvidence.(fieldName))
    value = defaultValue;
    return;
end
candidate = inputEvidence.(fieldName);
if isstring(candidate) && isscalar(candidate)
    value = char(candidate);
elseif ischar(candidate) && isrow(candidate)
    value = candidate;
else
    error('grade:InvalidEvidenceMetadata', ...
        '%s must be a character vector or scalar string.', fieldName);
end
end

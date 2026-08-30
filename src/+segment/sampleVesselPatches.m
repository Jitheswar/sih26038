function [patches, masks] = sampleVesselPatches(prepared, vessels, ...
    fieldOfView, patchCount, vessel, augment)
%SAMPLEVESSELPATCHES Draw training patches from one DRIVE frame.
%   [PATCHES, MASKS] = segment.sampleVesselPatches(PREPARED, VESSELS,
%   FIELDOFVIEW, PATCHCOUNT, VESSEL, AUGMENT) returns PATCHCOUNT patches of
%   VESSEL.patch_size, as HxWx1xN single and HxWx1xN logical.
%
%   PREPARED is the output of segment.vesselPreprocess, not a raw frame.
%   Preparing here instead would put a second preprocessing path in the
%   training loop, which §5.4 forbids.
%
%   Patch centres are constrained to the field of view.  A DRIVE frame is
%   31 per cent black corner outside the camera aperture, and a uniform
%   sampler spends that share of every epoch learning that black is not a
%   vessel, which it can already tell.
%
%   VESSEL.vessel_patch_fraction of the centres are additionally required to
%   land on an annotated vessel pixel.  At 12.5 per cent prevalence this is
%   not the rescue the lesion sampler performs at 0.1 per cent; it is here
%   because vessel width varies by an order of magnitude across the tree and
%   uniform centres are dominated by the trunks.

if nargin < 6
    augment = false;
end

patchSize = vessel.patch_size;
half = floor(patchSize / 2);
[height, width] = size(prepared);

if height < patchSize || width < patchSize
    error('segment:VesselFrameTooSmall', ...
        ['A DRIVE frame is %dx%d and the configured patch is %d, which ' ...
        'does not fit.'], height, width, patchSize);
end

% Centres must leave a whole patch inside the frame.
valid = false(height, width);
valid(half + 1:height - (patchSize - half), ...
    half + 1:width - (patchSize - half)) = true;
insideField = valid & fieldOfView;
onVessel = insideField & vessels;

vesselTarget = round(patchCount * vessel.vessel_patch_fraction);
vesselIndices = find(onVessel);
backgroundIndices = find(insideField);

if isempty(backgroundIndices)
    error('segment:NoVesselPatchSites', ...
        'No patch centre fits inside the field of view of this frame.');
end
if isempty(vesselIndices)
    vesselTarget = 0;
end

chosen = zeros(patchCount, 1);
if vesselTarget > 0
    chosen(1:vesselTarget) = vesselIndices( ...
        randi(numel(vesselIndices), vesselTarget, 1));
end
remaining = patchCount - vesselTarget;
if remaining > 0
    chosen(vesselTarget + 1:end) = backgroundIndices( ...
        randi(numel(backgroundIndices), remaining, 1));
end

patches = zeros(patchSize, patchSize, 1, patchCount, 'single');
masks = false(patchSize, patchSize, 1, patchCount);

for patchIndex = 1:patchCount
    [centreRow, centreColumn] = ind2sub([height, width], chosen(patchIndex));
    rows = centreRow - half + (0:patchSize - 1);
    columns = centreColumn - half + (0:patchSize - 1);

    patch = prepared(rows, columns);
    mask = vessels(rows, columns);

    if augment
        % Flips and quarter turns only.  A vessel tree has no canonical
        % orientation, so these are label-preserving.  Intensity jitter is
        % deliberately absent: segment.vesselPreprocess has already
        % equalised local contrast, and jittering after that would undo the
        % normalisation the network is being given.
        if rand() < 0.5
            patch = fliplr(patch);
            mask = fliplr(mask);
        end
        if rand() < 0.5
            patch = flipud(patch);
            mask = flipud(mask);
        end
        quarterTurns = randi(4) - 1;
        if quarterTurns > 0
            patch = rot90(patch, quarterTurns);
            mask = rot90(mask, quarterTurns);
        end
    end

    patches(:, :, 1, patchIndex) = patch;
    masks(:, :, 1, patchIndex) = mask;
end
end

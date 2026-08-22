function summary = lesionEvidenceSmoke(numberOfImages)
%LESIONEVIDENCESMOKE Run classical candidate evidence on APTOS images.
%   SUMMARY = lesionEvidenceSmoke(N) processes the first N APTOS training
%   images, writes original images, candidate overlays, and JSON metadata to
%   a new dated results directory, and prints a concise run summary.
%
%   This smoke workflow intentionally reads only data/raw/aptos2019 and
%   asserts that data/sealed is not in the selected paths.

rng(42, 'twister');
if nargin < 1 || isempty(numberOfImages)
    numberOfImages = 5;
end
if ~isnumeric(numberOfImages) || ~isscalar(numberOfImages) || ...
        ~isfinite(numberOfImages) || numberOfImages < 1
    error('lesionEvidenceSmoke:InvalidCount', ...
        'The number of images must be a positive finite scalar.');
end
numberOfImages = floor(numberOfImages);

scriptDirectory = fileparts(mfilename('fullpath'));
projectRoot = fileparts(scriptDirectory);
imageDirectory = fullfile(projectRoot, 'data', 'raw', 'aptos2019', 'train_images');
assert(~contains(lower(imageDirectory), [filesep, 'data', filesep, 'sealed']));
files = dir(fullfile(imageDirectory, '*.png'));
if isempty(files)
    error('lesionEvidenceSmoke:NoImages', ...
        'No APTOS training images were found at %s.', imageDirectory);
end
files = files(1:min(numberOfImages, numel(files)));

resultsDirectory = localDatedDirectory(fullfile(projectRoot, 'results'));
mkdir(resultsDirectory);

counts = zeros(numel(files), 1);
vesselAvailable = false(numel(files), 1);
coordinateMethods = cell(numel(files), 1);
overlayPaths = cell(numel(files), 1);
metadataPaths = cell(numel(files), 1);
originalPaths = cell(numel(files), 1);

for index = 1:numel(files)
    sourcePath = fullfile(files(index).folder, files(index).name);
    assert(~contains(lower(sourcePath), [filesep, 'data', filesep, 'sealed']));
    image = imread(sourcePath);
    detection = segment.detect(image);
    evidence = explain.buildLesionEvidence(image, detection);

    stem = erase(files(index).name, '.png');
    originalPaths{index} = fullfile(resultsDirectory, [stem, '_original.png']);
    overlayPaths{index} = fullfile(resultsDirectory, [stem, '_candidate_overlay.png']);
    metadataPaths{index} = fullfile(resultsDirectory, [stem, '_diagnostic.json']);
    imwrite(image, originalPaths{index});
    imwrite(evidence.candidateOverlay, overlayPaths{index});

    diagnostic = struct();
    diagnostic.image = files(index).name;
    diagnostic.candidateCount = detection.candidateCount;
    diagnostic.candidateCountsByQuadrant = detection.quadrantCounts;
    diagnostic.vesselSuppression = detection.vesselSuppression;
    diagnostic.quadrantCoordinateMethod = detection.quadrantCoordinateMethod;
    diagnostic.detector = detection.diagnostic;
    diagnostic.evidenceText = evidence.evidenceText;
    diagnostic.sealedDataAccessed = false;
    fid = fopen(metadataPaths{index}, 'w');
    if fid < 0
        error('lesionEvidenceSmoke:WriteFailed', ...
            'Could not write diagnostic metadata for %s.', files(index).name);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, jsonencode(diagnostic), 'char');

    counts(index) = detection.candidateCount;
    vesselAvailable(index) = detection.vesselSuppression.available;
    coordinateMethods{index} = detection.quadrantCoordinateMethod;
    fprintf('%s: %d microaneurysm candidates | overlay %s\n', ...
        files(index).name, counts(index), overlayPaths{index});
end

summary = struct();
summary.resultsDirectory = resultsDirectory;
summary.numberOfImagesProcessed = numel(files);
summary.imageNames = {files.name};
summary.candidateCountPerImage = counts;
summary.numberOfImagesWithZeroCandidates = sum(counts == 0);
summary.numberOfImagesWithVesselSuppressionAvailable = sum(vesselAvailable);
summary.coordinateFrameMethods = unique(coordinateMethods);
summary.candidateOverlayPaths = overlayPaths;
summary.originalImagePaths = originalPaths;
summary.diagnosticMetadataPaths = metadataPaths;
summary.sealedDataAccessed = false;
summary.terminology = 'classical candidate evidence';

fid = fopen(fullfile(resultsDirectory, 'summary.json'), 'w');
if fid < 0
    error('lesionEvidenceSmoke:WriteFailed', 'Could not write smoke summary.');
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(summary), 'char');

fprintf('Processed images: %d\n', summary.numberOfImagesProcessed);
fprintf('Candidate count per image: %s\n', mat2str(summary.candidateCountPerImage.'));
fprintf('Images with zero candidates: %d\n', ...
    summary.numberOfImagesWithZeroCandidates);
fprintf('Images with vessel suppression available: %d\n', ...
    summary.numberOfImagesWithVesselSuppressionAvailable);
fprintf('Coordinate-frame method(s): %s\n', strjoin(summary.coordinateFrameMethods, ', '));
fprintf('Candidate overlay paths: %s\n', strjoin(summary.candidateOverlayPaths, ', '));
fprintf('Confirmation: data/sealed/ was not accessed.\n');
end

function directory = localDatedDirectory(resultsRoot)
stamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<DATST>
directory = fullfile(resultsRoot, stamp);
suffix = 1;
while isfolder(directory)
    directory = fullfile(resultsRoot, sprintf('%s_%d', stamp, suffix));
    suffix = suffix + 1;
end
end

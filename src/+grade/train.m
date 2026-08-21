function result = train(varargin)
%TRAIN Placeholder grading entry point with the shared input seam wired in.

rng(42);
result = struct('status', 'placeholder');
if nargin == 0 || ~localIsImage(varargin{1})
    return;
end

config = [];
if nargin >= 2
    config = varargin{2};
end
[result.preprocessedImage, result.qualityMetadata, ...
    result.preprocessingMetadata] = common.preprocess( ...
    varargin{1}, config, 'training');
end

function result = localIsImage(value)
result = (isnumeric(value) || islogical(value)) && ~isempty(value);
end

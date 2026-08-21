function image = readPreprocessedImage(filename, config)
%READPREPROCESSEDIMAGE Read one image through the single shared pipeline.

rawImage = imread(filename);
[image, ~, ~] = common.preprocess(rawImage, config, 'training');
if size(image, 3) == 1
    image = repmat(image, 1, 1, 3);
end
image = single(image);
end

function [image, originalClass] = toUnitDouble(inputImage)
%TOUNITDOUBLE Validate an image and represent it on the [0, 1] scale.

if isempty(inputImage)
    error('quality:EmptyImage', 'The input image must not be empty.');
end
if ~(isnumeric(inputImage) || islogical(inputImage)) || ~isreal(inputImage)
    error('quality:InvalidImage', ...
        'The input image must be a real numeric or logical image.');
end
if ndims(inputImage) > 3 || (ndims(inputImage) == 3 && ...
        ~ismember(size(inputImage, 3), [1, 3]))
    error('quality:InvalidImage', ...
        'The input image must be a 2-D grayscale or 3-D RGB image.');
end

originalClass = class(inputImage);
if islogical(inputImage)
    image = double(inputImage);
elseif isinteger(inputImage)
    image = im2double(inputImage);
else
    image = double(inputImage);
end

if any(~isfinite(image(:))) || any(image(:) < 0) || any(image(:) > 1)
    error('quality:InvalidImage', ...
        'Floating-point image values must be finite and lie in [0, 1].');
end
end

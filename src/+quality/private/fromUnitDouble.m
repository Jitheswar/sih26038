function outputImage = fromUnitDouble(image, originalClass)
%FROMUNITDOUBLE Restore the input image class after enhancement.

image = min(max(image, 0), 1);
switch originalClass
    case 'uint8'
        outputImage = im2uint8(image);
    case 'uint16'
        outputImage = im2uint16(image);
    case 'uint32'
        outputImage = uint32(round(image .* double(intmax('uint32'))));
    case 'int8'
        outputImage = int8(round(image .* double(intmax('int8'))));
    case 'int16'
        outputImage = int16(round(image .* double(intmax('int16'))));
    case 'int32'
        outputImage = int32(round(image .* double(intmax('int32'))));
    case 'single'
        outputImage = single(image);
    case 'logical'
        outputImage = image >= 0.5;
    otherwise
        outputImage = image;
end
end

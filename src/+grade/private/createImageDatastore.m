function imageStore = createImageDatastore(data, config)
%CREATEIMAGEDATASTORE Create a lazy APTOS datastore using shared preprocessing.

imageStore = imageDatastore(cellstr(data.files));
imageStore.Labels = categorical(data.grades, 0:4, string(0:4));
imageStore.ReadFcn = @(filename) readPreprocessedImage(filename, config);
end

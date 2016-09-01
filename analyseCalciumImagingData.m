function imageStack = analyseCalciumImagingData(imageStackFiles,varargin)
    if nargin < 1 || (~ischar(imageStackFiles) && ~iscell(imageStackFiles))
        supportedImageFormats = imformats;
        supportedImageFormatExtensions = ['*.' strjoin([supportedImageFormats.ext],';*.')];
        
        supportedVideoFormats = VideoReader.getFileFormats;
        supportedVideoFormatExtensions = ['*.' strjoin({supportedVideoFormats.Extension},';*.')];
        
        imageStackFiles = uigetfile(    ...
            {supportedImageFormatExtensions,    sprintf('Image Files (%s)',supportedImageFormatExtensions); ...
             supportedVideoFormatExtensions,    sprintf('Video Files (%s)',supportedVideoFormatExtensions); ...
             '*.mat',                           'Matlab MAT Files (*.mat)';                                                     ...
             '*.qcamraw',                       'QCam RAW Data Files (*.qcamraw)';                                              ...
            }, 'Choose file(s) containing image stacks...', 'MultiSelect', 'on');
    end
       
    if ~iscell(imageStackFiles) && imageStackFiles == 0
        return
    end
    
    if ischar(imageStackFiles)
        imageStackFiles = {imageStackFiles};
    end
    
    [header,type] = acid.getHeaderInformation(imageStackFiles{1},varargin{:});
    
    imageStack = acid.loadImageStack(imageStackFiles,header,type,varargin{:});
    
    parser = inputParser;
    parser.KeepUnmatched = true;
    parser.addParameter('ROIType','freehand',@(s) any(strcmpi(s,{'ellipse' 'freehand' 'poly' 'rect'})));
    parser.addParameter('PreviewFrameOrFun',@(x) median(x,4),@(x) (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x <= size(imageStack,4) && round(x) == x) || isa(x,'function_handle') || (ischar(x) && any(strcmpi(x,{'mean' 'median' 'maxIntensity'}))));
    parser.addParameter('TrialStarts',[],@(x) isnumeric(x) && isvector(x) && all(isfinite(x) & x > 0 & round(x) == x));
    parser.addParameter('Conditions',[],@(x) isnumeric(x) && ismatrix(x) && all(isfinite(x(:)) & x(:) > 0 & round(x(:)) == x(:)));
    parser.parse(varargin{:});
    
    previewFrameOrFun = parser.Results.PreviewFrameOrFun;
    
    if isa(previewFrameOrFun,'function_handle')
        preview = previewFrameOrFun(imageStack);
    elseif ischar(previewFrameOrFun)
        switch previewFrameOrFun
            case 'mean'
                preview = mean(imageStack,4);
            case 'median'
                preview = median(imageStack,4);
            case 'max'
                preview = max(imageStack,[],4);
        end
    else
        preview = imageStack(:,:,:,previewFrameOrFun);
    end
    
    imshow(preview);
    caxis([min(preview(:)) max(preview(:))]);
    
    switch lower(parser.Results.ROIType)
        case 'ellipse'
            roifun = @imellipse;
        case 'freehand'
            roifun = @imfreehand;
        case 'poly'
            roifun = @impoly;
        case 'rect'
            roifun = @imrect;
        otherwise
            error('acid:BadROIType:Unknown ROI type %s',parser.Results.ROIType);
    end
    
    roi = roifun();
    
    while ~isempty(roi)
        if exist('rois','var')
            rois(end+1) = roi; %#ok<AGROW>
        else
            rois = roi;
        end
        
        roi = roifun();
    end
    
    if isempty(rois)
        return
    end
    
    masks = arrayfun(@createMask,rois,'UniformOutput',false);
    
    % can't do this all with bsxfun because the resulting array is too big :(
    traces = cell2mat(cellfun(@(mask) squeeze(mean(mean(mean(bsxfun(@times,imageStack,mask),1),2),3)),masks,'UniformOutput',false));
    
    figure;
   
    plot(traces);
    
    trialStarts = parser.Results.TrialStarts;
    conditions = parser.Results.Conditions;
    
    assert(isempty(trialStarts) || isempty(conditions) || numel(trialStarts) == size(conditions,1),'There must be one set of conditions for each trial');
    
    if isempty(trialStarts)
        trialStarts = 1;
    end
    
    if isempty(conditions)
        conditions = ones(size(trialStarts));
    end
    
    nTrials = numel(trialStarts);
    [uniqueConditions,~,conditionIndices] = unique(conditions,'rows');
    nConditions = size(uniqueConditions,1);
    nTrialsPerCondition = accumarray(conditionIndices,1);
    
    trialStacks = zeros(size(imageStack,1),size(imageStack,2),size(imageStack,3),max(diff([trialStarts size(imageStack,4)+1])),max(nTrialsPerCondition),nConditions);
    trialTraces = zeros(max(diff([trialStarts size(imageStack,4)+1])),max(nTrialsPerCondition),nConditions,size(traces,2));
    seenTrials = zeros(nConditions,1);
    
    for ii = 1:nTrials
        startIndex = trialStarts(ii);
        
        if ii == nTrials
            endIndex = size(imageStack,4);
        else
            endIndex = trialStarts(ii+1)-1;
        end
        
        nSamples = endIndex-startIndex+1;
        
        conditionIndex = conditionIndices(ii);
        trialIndex = seenTrials(conditionIndex)+1;
        seenTrials(conditionIndex) = trialIndex;
        
        trialStacks(:,:,:,1:nSamples,trialIndex,conditionIndex) = imageStack(:,:,:,startIndex:endIndex);
        trialTraces(1:nSamples,trialIndex,conditionIndex,:) = traces(startIndex:endIndex,:);
    end
end


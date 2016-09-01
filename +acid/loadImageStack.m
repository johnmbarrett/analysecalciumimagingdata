function imageStack = loadImageStack(imageStackFiles,header,type,varargin)
    switch type
        case 'IMAGE'
            rawImageStack = loadImageImageStack(imageStackFiles,header,varargin{:});
        case 'VIDEO'
            rawImageStack = loadVideoImageStack(imageStackFiles,header,varargin{:});
        case 'MATRIX'
            rawImageStack = loadMatrixImageStack(imageStackFiles,header,varargin{:});
        case 'QCAM'
            rawImageStack = loadQCamImageStack(imageStackFiles,header,varargin{:});
    end
    
    parser = inputParser;
    parser.KeepUnmatched = true;
    parser.addParameter('Binning',1,@(x) isnumeric(x) && ismember(numel(x),[1 2]) && all(isfinite(x)) && all(x > 0));
    parser.parse(varargin{:});
    
    ybins = parser.Results.Binning(1);
    xbins = parser.Results.Binning(end);
    
    if xbins == 1 && ybins == 1
        imageStack = rawImageStack;
        return
    end
    
    imageStack = zeros(ceil(size(rawImageStack)./[ybins xbins 1 1]));
    
    for hh = 1:size(imageStack,4)
        rawFrame = rawImageStack(:,:,:,hh);
        binnedFrame = zeros(size(imageStack,1),size(imageStack,2),size(imageStack,3));
        
        tic;
        for ii = 1:ybins
            for jj = 2:xbins
                binnedFrame = binnedFrame + rawFrame(ii:ybins:end,jj:xbins:end,:);
            end
        end
        toc;
        
        imageStack(:,:,:,hh) = binnedFrame/(xbins*ybins);
        
        continue
        
        temp = rawImageStack(:,:,:,hh); % don't read the whole absurdly huge array into data at once
        
        for ii = 1:size(imageStack,1)
            for jj = 1:size(imageStack,2)
                tic;
                imageStack(ii,jj,:,hh) = mean(mean(temp((ybins*(ii-1))+(1:ybins),(xbins*(jj-1))+(1:xbins),:),1),2);
                toc;
            end
        end
    end
end

function imageStack = loadImageImageStack(imageStackFiles,header,varargin)
    width = header(1).Width;
    height = header(1).Height;
    nSamples = header(1).NumberOfSamples;
    nFrames = zeros(size(imageStackFiles));
    nFrames(1) = header(1).NumberOfFrames;
    
    for ii = 2:numel(imageStackFiles)
        newHeader = acid.getHeaderInformation(imageStackFiles{ii});
        assert(width == newHeader(1).Width,'acid:MismatchedImageStackFiles','All image stack files must have the same width');
        assert(height == newHeader(1).Height,'acid:MismatchedImageStackFiles','All image stack files must have the same height');
        assert(nSamples == newHeader(1).NumberOfSamples,'acid:MismatchedImageStackFiles','All image stack files must have the same number of samples per pixel');
        nFrames(ii) = newHeader(1).NumberOfFrames;
    end
    
    imageStack = zeros(height,width,nSamples,sum(nFrames));
    cFrames = [0; cumsum(nFrames(:))];
    
    for ii = 1:numel(imageStackFiles)
        imageStackFile = imageStackFiles{ii};
        
        [~,~,extension] = fileparts(imageStackFile);
        
        switch extension
            case {'.cur','.gif','.hdf4','.ico','.tif','.tiff'}
                for jj = 1:nFrames(ii)
                    imageStack(:,:,:,cFrames(ii)+jj) = imread(imageStackFile,jj);
                end
            otherwise
                imageStack(:,:,:,ii) = imread(imageStackFile);
        end
    end     
end

function imageStack = loadVideoImageStack(imageStackFiles,header,varargin)
    for ii = 1:numel(imageStackFiles)
        if ii == 1
            reader = header;
        else
            reader = VideoReader(imageStackFiles{ii}); %#ok<TNMLP>
        end
        
        format = header.VideoFormat;
    
        if strncmpi(format,'RGB',3) || strcmpi(format,'Indexed')
            nSamples = 3;
        else
            nSamples = 1;
        end
        
        if exist(imageStack,'var')
            assert(reader.Width == size(imageStack,2),'acid:MismatchedImageStackFiles','All image stack files must have the same width');
            assert(reader.Height == size(imageStack,1),'acid:MismatchedImageStackFiles','All image stack files must have the same height');
            assert(nSamples == size(imageStack,3),'acid:MismatchedImageStackFiles','All image stack files must have the same number of samples per pixel');
        else
            imageStack = zeros(reader.Height,reader.Width,nSamples,0);
        end
        
        while hasFrame(reader)
            imageStack(:,:,:,end+1) = readFrame(reader); %#ok<AGROW>
        end
    end
end

function imageStack = loadMatrixImageStack(imageStackFiles,header,varargin)
    imageStack = header.Data;

    for ii = 2:numel(imageStackFiles)
        nextStack = load(imageStackFiles{ii});
        
        fields = fieldnames(nextStack);
        
        assert(numel(fields) == 1,'acid:BadMATFile','.mat file must contain a single 3 or 4 dimensional matrix');
        
        nextStack = nextStack.(fields{1});
        
        assert(size(imageStack,1) == size(nextStack,1),'acid:MismatchedImageStackFiles','All image stack files must have the same height');
        assert(size(imageStack,2) == size(nextStack,2),'acid:MismatchedImageStackFiles','All image stack files must have the same width');
        assert(size(imageStack,3) == size(nextStack,3),'acid:MismatchedImageStackFiles','All image stack files must have the same number of samples per pixel');
        
        imageStack = cat(4,imageStack,nextStack);
    end
end

function imageStack = loadQCamImageStack(imageStackFiles,header,varargin)
    nFiles = numel(imageStackFiles);
    nFrames = zeros(nFiles,1);
    qcamHeaders = struct([]);
    fins = zeros(nFiles,1);
    
    cleanup = onCleanup(@() arrayfun(@fclose,fins));
    
    for ii = 1:nFiles
        fins(ii) = fopen(imageStackFiles{ii});
        
        if ii == 1 % TODO : god I hate Matlab structs, let's move this to proper OO
            qcamHeaders = repmat(parseQCamHeader(fins(ii)),nFiles,1);
        else
            qcamHeaders(ii) = parseQCamHeader(fins(ii));
        end
        
        fseek(fins(ii),0,1);
        
        nFrames(ii) = (ftell(fins(ii))-qcamHeaders(ii).FixedHeaderSize)/qcamHeaders(ii).FrameSize; % TODO : duplicated code
    end

    imageStack = zeros(header.Height,header.Width,header.NumberOfSamples,sum(nFrames)); % TODO : get number of frames for all files
    
    for ii = 1:nFiles
        fin = fins(ii);
        
        fseek(fin,qcamHeaders(ii).FixedHeaderSize,-1); % pull this from the header once I have a proper header parser
        
        for jj = 1:nFrames(ii)
            tic;
            imageStack(:,:,:,jj) = fread(fin,[header.Width header.Height],'uint16')';
            toc;
        end
    end
end
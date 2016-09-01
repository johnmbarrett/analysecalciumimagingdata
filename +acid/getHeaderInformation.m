function [header,type] = getHeaderInformation(imageStackFile,varargin) % TODO : refactor
    [header,type] = getHeaderInformationHelper(imageStackFile);
    
    isRealFinitePositiveNumericScalar = @(x) isnumeric(x) && isscalar(x) && isfinite(x) && isreal(x) && x > 0;
    isFinitePositiveIntegerScalar = @(x) isRealFinitePositiveNumericScalar(x) && round(x) == x;
    parser = inputParser;
    parser.KeepUnmatched = true;
    parser.addParameter('Width',header(1).Width,isFinitePositiveIntegerScalar);
    parser.addParameter('Height',header(1).Height,isFinitePositiveIntegerScalar);
    parser.addParameter('FrameRate',header(1).FrameRate,isRealFinitePositiveNumericScalar);
    parser.parse(varargin{:});
    
    [header.Width] = deal(parser.Results.Width);
    [header.Height] = deal(parser.Results.Height);
    [header.FrameRate] = deal(parser.Results.FrameRate);
end

function [header,type] = getHeaderInformationHelper(imageStackFile) % TODO : refactor
    [~,~,extension] = fileparts(imageStackFile);
    extension = extension(2:end);
    
    if ~isempty(imformats(extension))
        header = imfinfo(imageStackFile);
        
        if isfield(header(1),'DelayTime')
            [header.FrameRate] = deal(100/header(1).DelayTime);
        else % TODO : other ways we can get this
            [header.FrameRate] = deal(NaN);
        end
        
        if ~isfield(header,'NumberOfSamples')
            image = imread(imageStackFile);
            [header.NumberOfSamples] = deal(size(image,3));
        end
        
        [header.NumberOfFrames] = deal(numel(header));
        
        type = 'IMAGE';
        return
    end
    
    supportedVideoFormats = VideoReader.getFileFormats();
    
    if any(ismember({supportedVideoFormats.Extension},extension))
        header = VideoReader(imageStackFile);
        type = 'VIDEO';
        return
    end
    
    switch extension
        case 'mat'
            data = load(imageStackFile);
            
            fields = fieldnames(data);
            
            assert(numel(fields) == 1,'acid:BadMATFile','.mat file must contain a single 2-4 dimensional matrix');
            
            data = data.(fields{1});
            
            assert(ismember(ndims(data),2:4),'acid:BadMATFile','.mat file must contain a single 2-4 dimensional matrix');
            
            header.Data = data;
            header.Width = size(data,2);
            header.Height = size(data,1);
            header.NumberOfSamples = size(data,3);
            header.NumberOfFrames = size(data,4);
            header.FrameRate = NaN;
            type = 'MATRIX';
        case 'qcamraw'
            header = readQCamRawFile(imageStackFile);
            type = 'QCAM';
        otherwise
            error('acid:UnsupportedFileType','File type %s is not supported',extension);
    end
end

function header = readQCamRawFile(imageStackFile)
    fin = fopen(imageStackFile);

    qcamHeader = parseQCamHeader(fin);
    header = struct([]);
    header(1).Width = qcamHeader.ROI(3)-qcamHeader.ROI(1);
    header(1).Height = qcamHeader.ROI(4)-qcamHeader.ROI(2);
    header(1).FrameRate = 1/(qcamHeader.Exposure*1e-9); % TODO : units?
    header(1).NumberOfSamples = 1; % TODO : get this from the header
    
    fseek(fin,0,1);
    
    header(1).NumberOfFrames = (ftell(fin)-qcamHeader.FixedHeaderSize)/qcamHeader.FrameSize;
    
    fclose(fin);
end
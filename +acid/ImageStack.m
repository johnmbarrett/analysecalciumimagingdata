classdef (Abstract) ImageStack
    properties (GetAccess=public,SetAccess=immutable)
        Height
        Width
        NumberOfSamples
        NumberOfFrames
        Size
    end
    
    methods (Abstract,Access=protected)
        data = subsref_(obj,subs)
    end
        
    methods (Access=public)
        function obj = ImageStack(h,w,s,f)
            % could also use a dependent property but that would mean four
            % calls to builtin('subsref',...) in size@acid.ImageStack
            obj.Height = h;
            obj.Width = w;
            obj.NumberOfSamples = s;
            obj.NumberOfFrames = f;
            obj.Size = [h w s f];
        end
        
        function index = end(obj,k,~)
            index = size(obj,k);
        end
        
        function sz = size(obj,dim)
            sz = builtin('subsref',obj,substruct('.','Size'));
            
            if nargin < 2
                return
            end
            
            sz = sz(dim);
        end
        
        function data = subsref(obj,subs)
            if subs(1).type == '.'
                data = builtin('subsref',obj,subs);
                return
            end
            
            if any([subs.type] == '{')
                error('acid:ImageStack:NotACellArray','An ImageStack cannot be indexed as a cell array');
            end
            
            data = obj.subsref_(subs);
        end
    end
end
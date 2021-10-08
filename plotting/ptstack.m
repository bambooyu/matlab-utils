function [traceCenters, hLines] = ptstack(timeDim, stackDims, varargin)
% ptstack(timeDim, dataTensor, ...)
% ptstack(timeDim, timeVec, dataTensor, ...)
%
% parameters:
%   colormap
%   other parameters will be passed thru to plot(...)
%
% uses plotStackedTraces to quickly plot a tensor. timeDim is the time
% dimension, stackDims are the dimensions to stack vertically, remaining
% dimensions will be superimposed in the same plots

narg = numel(varargin);

timeDim = makecol(timeDim);
stackDims = makecol(stackDims);

if isvector(varargin{1}) && narg > 1 && isnumeric(varargin{2})
    x = varargin{2};
    tvec = makecol(varargin{1});
    args = varargin(3:end);
else
    x = varargin{1};
    nTime = prod(TensorUtils.sizeMultiDim(x, timeDim));
    tvec = (1:nTime)';
    args = varargin(2:end);
end

p = inputParser();
%p.addParameter('colormap', TrialDataUtilities.Color.hslmap(nSuperimpose, 'fracHueSpan', 0.9), @(x) ~ischar(x) && ismatrix(x));
p.addParameter('data_ci', [], @(x) true);
p.addParameter('ci_dim', ndims(x) + 1, @isscalar);
p.addParameter('namesAlongDims', {}, @iscell);
p.addParameter('labelsSuperimposed', {}, @isstringlike);
p.addParameter('labelsStacked', {}, @isstringlike);
p.addParameter('maxStack', 30, @islogical);
p.addParameter('pca', false, @(x) islogical(x) || isscalar(x)); % pca on stacking dim
p.addParameter('pcaInput', [], @(x) isnumeric(x));
p.addParameter('pcaDim', [],  @(x) isempty(x) || isscalar(x)); % pca on superimposed dim
p.addParameter('colorDim', [], @(x) true);
p.addParameter('colormap', [], @(x) true); % applied along colorDim
%p.addParameter('alpha', 1, @isscalar);
p.KeepUnmatched = true;
p.PartialMatching = false;
p.parse(args{:});

% sz = size(x);
% nStack = prod(sz(stackDims));
% if nStack > 200
%     error('Refusing to stack more than 200 traces');
% end

superimposeDims = TensorUtils.otherDims(size(x), [timeDim; stackDims]);

% nSuperimpose = prod(sz(superimposeDims));
% if nSuperimpose > 50
%     error('Refusing to superimpose more than 50 traces');
% end

x_ci = p.Results.data_ci;
has_ci = ~isempty(x_ci);
ci_dim = p.Results.ci_dim;
if has_ci
    superimposeDims = setdiff(superimposeDims, ci_dim);
    assert(size(x, ci_dim) == 1, 'Data must have size 1 along ci_dim');
else
    ci_dim = [];
end

if p.Results.pca
    if isempty(p.Results.pcaInput)
        pcaInput = x;
    else
        pcaInput = p.Results.pcaInput;
    end
    
    if isempty(p.Results.pcaDim)
        pcaDim = stackDims;
    else
        pcaDim = p.Results.pcaDim;
    end
    if islogical(p.Results.pca)
        pcaK = prod(size(x, pcaDim));
    else
        pcaK = p.Results.pca;
    end
    
    if numel(pcaDim) > 1
        if isequal(sort(pcaDim), sort(stackDims))
            pcaDim = 2;
        elseif isequal(sort(pcaDim), sort(superimposeDims))
            pcaDim = 3;
        else
            error('Non-scalar pca dim must match stack or superimpose dimensions');
        end
        
        % reshape, then do pca on the combined dim,
        % xr will be T x nStack x nSuperimpose
        xr = TensorUtils.reshapeByConcatenatingDims(x, {timeDim, stackDims, superimposeDims, ci_dim});
        pcaInput = TensorUtils.reshapeByConcatenatingDims(pcaInput, {timeDim, stackDims, superimposeDims, ci_dim});
        coeff = TensorUtils.pcaAlongDim(pcaInput, pcaDim, 'NumComponents', pcaK);
        
        mean_xr = mean(xr, pcaDim);
        xr = TensorUtils.linearCombinationAlongDimension(xr - mean_xr, pcaDim, coeff');
        
        if has_ci
            x_ci =  TensorUtils.reshapeByConcatenatingDims(x, {timeDim, stackDims, superimposeDims, ci_dim});
            x_ci = TensorUtils.linearCombinationAlongDimension(x_ci - mean_xr, pcaDim, coeff');
        end
    else
        coeff = TensorUtils.pcaAlongDim(pcaInput, pcaDim, 'NumComponents', pcaK);
        mean_x = mean(x, pcaDim);
        x = TensorUtils.linearCombinationAlongDimension(x - mean_x, pcaDim, coeff');
        
        % xr will be T x nStack x nSuperimpose
        xr = TensorUtils.reshapeByConcatenatingDims(x, {timeDim, stackDims, superimposeDims, ci_dim});
        
        if has_ci
            x_ci = TensorUtils.linearCombinationAlongDimension(x_ci - mean_x, pcaDim, coeff');
            x_ci =  TensorUtils.reshapeByConcatenatingDims(x_ci, {timeDim, stackDims, superimposeDims, ci_dim});
        end
    end
else
    xr = TensorUtils.reshapeByConcatenatingDims(x, {timeDim, stackDims, superimposeDims, ci_dim});
    if has_ci
        x_ci = TensorUtils.reshapeByConcatenatingDims(x_ci, {timeDim, stackDims, superimposeDims, ci_dim});
    end
end

colorArgs = {};
if ~isempty(p.Results.colorDim)
    colorDim = p.Results.colorDim;
    colormap = p.Results.colormap;
    if isempty(colormap)
        colormap = @(n) TrialDataUtilities.Colormaps.linspecer(n, 'seq');
    end
    
    nColor = size(x, colorDim);
    colormap = TrialDataUtilities.Plotting.expandWrapColormap(colormap, nColor);
    colorInds = TensorUtils.orientVectorAlongDim(1:nColor, colorDim);
    
    if ismember(colorDim, stackDims)
        % specifying the stacking colormap
        szOtherStack = TensorUtils.sizeMultiDim(x, setdiff(stackDims, colorDim));
        colorInds = TensorUtils.repmatAlongDims(colorInds, setdiff(stackDims, colorDim), szOtherStack);
        colorArgs = {'colormapStacked', colormap(colorInds(:), :)};
    elseif ismember(colorDim, superimposeDims)
        % specifying the superimposed colormap
        szOtherSuper = TensorUtils.sizeMultiDim(x, setdiff(superimposeDims, colorDim));
        colorInds = TensorUtils.repmatAlongDims(colorInds, setdiff(superimposeDims, colorDim), szOtherSuper);
        colorArgs = {'colormap', colormap(colorInds(:), :)};
    elseif colorDim == timeDim
        error('Cannot color by time dim');
    else
        szSuper = TensorUtils.sizeMultiDim(x, superimposeDims);
        colorInds = TensorUtils.repmatAlongDims(colorInds, superimposeDims, szSuper);
        colorArgs = {'colormap', colormap(colorInds(:), :)};
    end
else
    colorArgs = {'colormap', p.Results.colormap};
end

% 
% if p.Results.pca
%     if isempty(p.Results.pcaInput)
%         if islogical(p.Results.pca)
%             [~, xr] = TensorUtils.pcaAlongDim(xr, 2);
%         else
%             [~, xr] = TensorUtils.pcaAlongDim(xr, 2, 'NumComponents', p.Results.pca);
%         end
%     else
%         pcaInput = TensorUtils.reshapeByConcatenatingDims(p.Results.pcaInput, {timeDim, stackDims, superimposeDims});
%         if islogical(p.Results.pca)
%             coeff = TensorUtils.pcaAlongDim(pcaInput, 2);
%         else
%             coeff = TensorUtils.pcaAlongDim(pcaInput, 2, 'NumComponents', p.Results.pca);
%         end
%         xr = TensorUtils.linearCombinationAlongDimension(xr - mean(xr, 2), 2, coeff');
%     end
% end

% if p.Results.pcaSuperimposed
%     if islogical(p.Results.pcaSuperimposed)
%         [~, xr] = TensorUtils.pcaAlongDim(xr, 3);
%     else
%         [~, xr] = TensorUtils.pcaAlongDim(xr, 3, 'NumComponents', p.Results.pcaSuperimposed);
%     end
% end

nStack = size(xr, 2);
maxStack = p.Results.maxStack;
if nStack > maxStack
    xr = xr(:, 1:maxStack, :);
    nStack = maxStack;
end

nSuperimpose = size(xr, 3);
if nStack > 400
    warning('Truncating to stack only 400 traces');
    xr = xr(:, 1:400, :);
end
if nSuperimpose > 500
    warning('Truncating to superimpose only 500 traces');
    xr = xr(:, :, 1:500);
end

if ~isempty(p.Results.namesAlongDims)
    namesAlongDims = p.Results.namesAlongDims;
    if numel(namesAlongDims) ~= ndims(x)
        error('namesAlongDims must be cell with lengths ndims (including time dim)');
    end
    
    namesStack = namesAlongDims(stackDims);
    namesSuperimpose = namesAlongDims(superimposeDims);
    
    labelsStack = TensorUtils.flatten(TensorUtils.buildCombinatorialStringTensorFromLists(namesStack));
    labelsSuperimpose = TensorUtils.flatten(TensorUtils.buildCombinatorialStringTensorFromLists(namesSuperimpose));
else
    labelsStack = p.Results.labelsStacked;
    labelsSuperimpose = p.Results.labelsSuperimposed;
end   

if ~isempty(labelsStack)
    labelsStack = labelsStack(1:size(xr, 2));
end
if ~isempty(labelsSuperimpose)
    labelsSuperimpose = labelsSuperimpose(1:size(xr, 3));
end

[traceCenters, hLines] = TrialDataUtilities.Plotting.plotStackedTraces(tvec, xr, ...
    'data_ci', x_ci, 'labels', labelsStack, 'labelsSuperimposed', labelsSuperimpose, 'labels', labelsStack, ...
    colorArgs{:}, p.Unmatched);
hold off;

% set(gca, 'ColorOrder', cmap, 'ColorOrderIndex', 1);
% hold on;
% h = plot(tvec, xr, p.Unmatched);
% for iH = 1:numel(h)
%     h(iH).Color(4) = p.Results.alpha;
% end
% hold off;

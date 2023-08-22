module FastRunningMedian

using Base.Iterators: isdone
using Base: tail

export running_median, running_median!

include("stateful_api.jl")

"""
    running_median(input, window_length, tapering=:symmetric; kwargs...) -> output

Run a median filter of `window_length` over the input array and return the
result. 

If the input array is multidimensional, the median will be run only over the
first dimension, i.e. over all columns indepedently.

## Taperings

The tapering decides the behaviour at the ends of the input. All taperings are
mirror symmetric with respect to the middle of the input array. The available
taperings are:
- `:symmteric` or `:sym`: Ensure that the window is symmetric around each point
  of the output array by always growing or shrinking the window by 2. The output
  has the same length as the input if `window_length` is odd. If `window_length`
  is even, the output has one element less. 
- `:asymmetric` or `:asym`: Always adds or removes one element when calculating
  the next output value. Creates asymmetric windowing at the edges of the array.
  If the input is N long, the output is N+window_length-1 elements long. 
- `:asymmetric_truncated` or `:asym_trunc`: The same as asymmetric, but
  truncated at beginning and end to match the length of `:symmetric`. 
- `:none` or `:no`: No tapering towards the ends. If the input has N elements,
  the output is only N-window_length+1 long. 

If you choose an even `window_length`, the elements of the output array lie in
the middle between the input elements on a continuous underlying axis. 

## Keyword Arguments

- `nan=:include`: By default, NaN values in the window will turn the median NaN
  as well. Use `nan = :ignore` to ignore NaN values and calculate the median
  over the remaining values in the window. If there are only NaNs in the window,
  the median will be NaN regardless. 
- `output_eltype=Float64`: Element type of the output array. The output element
  type should allow converting from Float64 and the input element type. The
  exception is odd window lengths with taperings `:no` or `:sym`, in which case
  the output element type only has to allow converting from the input element
  type. 

## Performance

The underlying algorithm should scale as O(N log w) with the input length N and
the window_length w. 
"""
function running_median(
    input::AbstractArray{T}, 
    window_length::Integer, 
    tapering=:symmetric;
    nan=:include,
    output_eltype=Float64,
    ) where {T<:Real}

    input_length = first(size(input))
    window_length = _validated_window_length(window_length, input_length, tapering)
    mf = MedianFilter{eltype(input)}(window_length)

    output_length = _output_length(input_length, window_length, tapering)
    output = Array{output_eltype}(undef, output_length, tail(size(input))...)

    _unchecked_running_median!(mf, output, input, tapering, nan)
end

"""
    running_median!(mf::MedianFilter, output, input, tapering=:sym; nan=:include) -> output

Use `mf` to calculate the running median of `input` and write the result to
`output`.

For all details, see [`running_median`](@ref).

# Examples
```jldoctest
input = [4 5 6;
         1 0 9;
         9 8 7;
         3 1 2;]
output = similar(input, (4,3))
mf = MedianFilter(eltype(input), 3)
for j in axes(input, 2) # run median over each column
    # re-use mf in every iteration
    running_median!(mf, @view(output[:,j]), input[:,j])
end
output

# output
4×3 Matrix{Int64}:
 4  5  6
 4  5  7
 3  1  7
 3  1  2
```
"""
function running_median!(
    mf::MedianFilter,
    output::AbstractArray{V},
    input::AbstractArray{T},
    tapering=:symmetric;
    nan=:include) where {T<:Real,V<:Real}

    winlen = window_length(mf)
    input_length = first(size(input))
    expected_winlen = _validated_window_length(winlen, input_length, tapering)
    winlen == expected_winlen || throw(ArgumentError(
        "unexpected median filter window length of $winlen instead of $expected_winlen"))

    expected_output_length = _output_length(input_length, winlen, tapering)
    output_length = first(size(output))
    output_length == expected_output_length || throw(ArgumentError(
        "unexpected output length $(length(output)) instead of $expected_output_length"))

    tail(size(output)) == tail(size(input)) || throw(ArgumentError(
        "input and output size must be equal for any dimension after the first"
    ))

    _unchecked_running_median!(mf, output, input, tapering, nan)
end

function _validated_window_length(window_length, input_length, tapering)
    input_length > 0 || throw(ArgumentError("input array must be non-empty"))
    if tapering in (:symmetric, :sym) && input_length |> iseven
        window_length = min(window_length, input_length - 1)
    else
        window_length = min(window_length, input_length)
    end
    window_length
end

function _output_length(input_length, window_length, tapering)
    if tapering in (:symmetric, :sym)
        window_length |> isodd ? input_length : input_length - 1
    elseif tapering in (:asymmetric, :asym)
        input_length + window_length - 1
    elseif tapering in (:asymmetric_truncated, :asym_trunc)
        window_length |> isodd ? input_length : input_length - 1
    elseif tapering in (:none, :no)
        input_length - window_length + 1
    else
        _throw_invalid_tapering()
    end
end


function _unchecked_running_median!(mf, output, input, tapering, nan)
    input_reshaped = reshape(input, first(size(input)), :)
    output_reshaped = reshape(output, first(size(output)), :)

    for i in axes(input_reshaped)[2]
        # input iterator
        input_view = @view input_reshaped[:,i]
        init = Iterators.Stateful(input_view)
        # output index iterator
        output_view = @view output_reshaped[:,i]
        outindit = Iterators.Stateful(eachindex(output_view))

        reset!(mf, popfirst!(init))

        if tapering in (:symmetric, :sym)
            _symmetric_phases!(init, mf, output_view, outindit, nan)
        elseif tapering in (:asymmetric, :asym)
            _asymmetric_phases!(init, mf, output_view, outindit, nan)
        elseif tapering in (:asymmetric_truncated, :asym_trunc)
            _asymmetric_truncated_phases!(init, mf, output_view, outindit, nan)
        elseif tapering in (:none, :no)
            _untapered_phases!(init, mf, output_view, outindit, nan)
        else
            _throw_invalid_tapering()
        end
    end

    output
end

_throw_invalid_tapering() = throw(ArgumentError("Invalid tapering. Must be one of [:sym, :asym, :asym_trunc, :no]"))

function _symmetric_phases!(init, mf, output, outindit, nan)
    # if even, start with two elements in mf at index 1.5
    if window_length(mf) |> iseven
        grow!(mf, popfirst!(init))
    end

    # first median
    output[popfirst!(outindit)] = median(mf, nan=nan)

    # grow phase
    while !isfull(mf)
        grow!(mf, popfirst!(init))
        grow!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf, nan=nan)
    end

    # roll phase
    while !isdone(init)
        roll!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf, nan=nan)
    end

    # shrink phase
    while !isdone(outindit)
        shrink!(mf)
        shrink!(mf)
        output[popfirst!(outindit)] = median(mf, nan=nan)
    end
end

function _asymmetric_phases!(init, mf, output, outindit, nan)
    # first median
    output[popfirst!(outindit)] = median(mf, nan=nan)

    # grow phase
    while !isfull(mf)
        grow!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf, nan=nan)
    end

    # roll phase
    while !isdone(init)
        roll!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf, nan=nan)
    end

    # shrink phase
    while !isdone(outindit)
        shrink!(mf)
        output[popfirst!(outindit)] = median(mf, nan=nan)
    end
end

function _asymmetric_truncated_phases!(init, mf, output, outindit, nan)
    # pre-output grow phase
    while length(mf) <= window_length(mf) / 2
        grow!(mf, popfirst!(init))
    end

    # first median
    output[popfirst!(outindit)] = median(mf, nan=nan)

    # grow phase
    while !isfull(mf)
        grow!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf, nan=nan)
    end

    # roll phase
    while !isdone(init)
        roll!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf, nan=nan)
    end

    # shrink phase
    while !isdone(outindit)
        shrink!(mf)
        output[popfirst!(outindit)] = median(mf, nan=nan)
    end
end

function _untapered_phases!(init, mf, output, outindit, nan)
    # grow phase - no output yet
    while !isfull(mf)
        grow!(mf, popfirst!(init))
    end

    # first median
    output[popfirst!(outindit)] = median(mf, nan=nan)

    # roll phase
    while !isdone(init)
        roll!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf, nan=nan)
    end
end

end # module

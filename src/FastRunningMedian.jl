module FastRunningMedian

using Base.Iterators: isdone

export running_median, running_median!

# TODO repo-wide, change from window_size to window_length, as it is more in line with Julia conventions

include("stateful_api.jl")

"""
    running_median(input, window_size, tapering=:symmetric; kwargs...) -> output

Run a median filter of `window_size` over the input array and return the result. 

## Taperings

The tapering decides the behaviour at the ends of the input. All taperings are
mirror symmetric with respect to the middle of the input array. The available
taperings are:
- `:symmteric` or `:sym`: Ensure that the window is symmetric around each point
  of the output array by always growing or shrinking the window by 2. The output
  has the same length as the input if `window_size` is odd. If `window_size` is
  even, the output has one element less. 
- `:asymmetric` or `:asym`: Always adds or removes one element when calculating
  the next output value. Creates asymmetric windowing at the edges of the array.
  If the input is N long, the output is N+window_size-1 elements long. 
- `:asymmetric_truncated` or `:asym_trunc`: The same as asymmetric, but
  truncated at beginning and end to match the size of `:symmetric`. 
- `:none` or `:no`: No tapering towards the ends. If the input has N elements,
  the output is only N-window_size+1 long. 

If you choose an even `window_size`, the elements of the output array lie in the
middle between the input elements on a continuous underlying axis. 

## Keyword Arguments

- `nan=:include`: By default, NaN values in the window will turn the median NaN
  as well. Use `nan = :ignore` to ignore NaN values and calculate the median
  over the remaining values in the window. If there are only NaNs in the window,
  the median will be NaN regardless. 
- `output_eltype=Float64`: Element type of the output array. The output element
  type should allow converting from Float64 and the input element type. The
  exception is odd window sizes with taperings `:no` or `:sym`, in which case
  the output element type only has to allow converting from the input element
  type. 

## Performance

The underlying algorithm should scale as O(N log w) with the input size N and
the window_size w. 
"""
function running_median(
    input::AbstractVector{T}, 
    window_size::Integer, 
    tapering=:symmetric;
    nan=:include,
    output_eltype=Float64,
    ) where {T<:Real}

    window_size = _validated_window_size(window_size, length(input), tapering)
    # TODO zero value will later be reset anyway
    # change when an initial value is not required anymore
    mf = MedianFilter(zero(eltype(input)), window_size)

    output_length = _output_length(length(input), window_size, tapering)
    output = Array{output_eltype,1}(undef, output_length)

    _unchecked_running_median!(mf, output, input, tapering, nan)
end

"""
    running_median!(mf::MedianFilter, output, input, tapering=:sym; nan=:include) -> output

Use `mf` to calculate the running median of `input` and write the result to
`output`.

Compared to [`running_median`](@ref), this function lets you take control of
allocation for the median filter and the output vector. This is useful when you
have to calculate many running medians of the same window size (see
examples below).

For all details, see [`running_median`](@ref).

# Examples
```jldoctest
input = [4 5 6;
         1 0 9;
         9 8 7;
         3 1 2;]
output = similar(input, (4,3))
mf = MedianFilter(42, 3) # first value does not matter
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
    output::AbstractVector{V},
    input::AbstractVector{T},
    tapering=:symmetric;
    nan=:include) where {T<:Real,V<:Real}

    winsize = window_size(mf)
    expected_winsize = _validated_window_size(winsize, length(input), tapering)
    winsize == expected_winsize || error(
        "unexpected median filter window size of $winsize instead of $expected_winsize")

    expected_output_length = _output_length(length(input), winsize, tapering)
    length(output) == expected_output_length || error(
        "unexpected output length $(length(output)) instead of $expected_output_length")

    _unchecked_running_median!(mf, output, input, tapering, nan)
end

function _validated_window_size(window_size, input_length, tapering)
    input_length > 0 || error("input array must be non-empty")
    window_size >= 1 || error("window_size must be 1 or bigger")
    if tapering in (:symmetric, :sym) && input_length |> iseven
        window_size = min(window_size, input_length - 1)
    else
        window_size = min(window_size, input_length)
    end
    window_size
end

function _output_length(input_length, window_size, tapering)
    if tapering in (:symmetric, :sym)
        window_size |> isodd ? input_length : input_length - 1
    elseif tapering in (:asymmetric, :asym)
        input_length + window_size - 1
    elseif tapering in (:asymmetric_truncated, :asym_trunc)
        window_size |> isodd ? input_length : input_length - 1
    elseif tapering in (:none, :no)
        input_length - window_size + 1
    else
        error("Invalid tapering. Must be one of [:sym, :asym, :asym_trunc, :no]")
    end
end


function _unchecked_running_median!(mf, output, input, tapering, nan)
    # input iterator
    init = Iterators.Stateful(input)
    # output index iterator
    outindit = Iterators.Stateful(eachindex(output))

    reset!(mf, popfirst!(init))

    if tapering in (:symmetric, :sym)
        _symmetric_phases!(init, mf, output, outindit, nan)
    elseif tapering in (:asymmetric, :asym)
        _asymmetric_phases!(init, mf, output, outindit, nan)
    elseif tapering in (:asymmetric_truncated, :asym_trunc)
        _asymmetric_truncated_phases!(init, mf, output, outindit, nan)
    elseif tapering in (:none, :no)
        _untapered_phases!(init, mf, output, outindit, nan)
    else
        error("Invalid tapering. Must be one of [:sym, :asym, :asym_trunc, :no]")
    end

    output
end

function _symmetric_phases!(init, mf, output, outindit, nan)
    # if even, start with two elements in mf at index 1.5
    if window_size(mf) |> iseven
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
    while length(mf) <= window_size(mf) / 2
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

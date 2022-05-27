module FastRunningMedian

using Base.Iterators: isdone

export running_median

include("stateful_api.jl")

"""
    running_median(input, window_size, tapering=:symmetric)

Run a median filter of `window_size` over the input array and return the result. 

## Taperings

The tapering decides the behaviour at the ends of the input. All taperings are mirror symmetric with respect to the middle of the input array. The available taperings are:
- `:symmteric` or `:sym`: Ensure that the window is symmetric around each point of the output array by always growing or shrinking the window by 2. The output has the same length as the input if `window_size` is odd. If `window_size` is even, the output has one element less. 
- `:asymmetric` or `:asym`: Always adds or removes one element when calculating the next output value. Creates asymmetric windowing at the edges of the array. If the input is N long, the output is N+window_size-1 elements long. 
- `:asymmetric_truncated` or `:asym_trunc`: The same as asymmetric, but truncated at beginning and end to match the size of `:symmetric`. 
- `:none` or `:no`: No tapering towards the ends. If the input has N elements, the output is only N-window_size+1 long. 

If you choose an even `window_size`, the elements of the output array lie in the middle between the input elements on a continuous underlying axis. 

## Performance

The underlying algorithm should scale as O(N log w) with the input size N and the window_size w. 
"""
function running_median(input::AbstractVector{T}, window_size::Integer, tapering=:symmetric) where T <: Real
    if length(input) == 0
        error("input array must be non-empty")
    end

    if window_size < 1
        error("window_size must be 1 or bigger")
    end

    if tapering == :symmetric || tapering == :sym
        symmetric_running_median(input, window_size)
    elseif tapering == :asymmetric || tapering == :asym
        asymmetric_running_median(input, window_size)
    elseif tapering == :asymmetric_truncated || tapering == :asym_trunc
        asymmetric_truncated_running_median(input, window_size)
    elseif tapering == :none || tapering == :no
        untapered_running_median(input, window_size)
    else
        error("Invalid tapering. Must be one of [:sym, :asym, :asym_trunc, :no]")
    end
end

function symmetric_running_median(input::AbstractVector{T}, window_size::Integer) where T <: Real
    N = length(input)

    # calculate maximum possible window size
    if N |> isodd
        max_possible_window_size = N
    else
        max_possible_window_size = N - 1
    end
    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < window_size
        window_size = max_possible_window_size
    end

    # allocate output
    if window_size |> iseven
        N_out = N - 1
    else
        N_out = N
    end
    output = Array{Float64,1}(undef, N_out)

    # input iterator
    it = Iterators.Stateful(input)

    # construct MedianFilter
    mf = MedianFilter(popfirst!(it), window_size)

    # if even, start with two elements in mf at index 1.5
    if window_size |> iseven
        grow!(mf, popfirst!(it))
    end

    # first median
    j = 1
    output[j] = median(mf)
    j += 1

    # grow phase
    while !isfull(mf)
        grow!(mf, popfirst!(it))
        grow!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    # roll phase
    while !isdone(it)
        roll!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    # shrink phase
    while j <= N_out
        shrink!(mf)
        shrink!(mf)
        output[j] = median(mf)
        j += 1
    end

    return output
end

function asymmetric_running_median(input::AbstractVector{T}, window_size::Integer) where T <: Real
    N = length(input)

    # calculate maximum possible window size
    max_possible_window_size = N
    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < window_size
        window_size = max_possible_window_size
    end
    
    # allocate output
    N_out = N + window_size - 1
    output = Array{Float64,1}(undef, N_out)

    # input iterator
    it = Iterators.Stateful(input)

    # construct MedianFilter
    mf = MedianFilter(popfirst!(it), window_size)

    # first median
    j = 1
    output[j] = median(mf)
    j += 1

    # grow phase
    while !isfull(mf)
        grow!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    # roll phase
    while !isdone(it)
        roll!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    # shrink phase
    while j <= N_out
        shrink!(mf)
        output[j] = median(mf)
        j += 1
    end

    return output
end

function asymmetric_truncated_running_median(input::AbstractVector{T}, window_size::Integer) where T <: Real
    N = length(input)

    # calculate maximum possible window size
    max_possible_window_size = N
    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < window_size
        window_size = max_possible_window_size
    end

    # allocate output
    if window_size |> iseven
        N_out = N - 1
    else
        N_out = N
    end
    output = Array{Float64,1}(undef, N_out)

    # input iterator
    it = Iterators.Stateful(input)

    # construct MedianFilter
    mf = MedianFilter(popfirst!(it), window_size)

    # pre-output grow phase
    while length(mf) <= window_size / 2
        grow!(mf, popfirst!(it))
    end

    # first median
    j = 1
    output[j] = median(mf)
    j += 1

    # grow phase
    while !isfull(mf)
        grow!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    # roll phase
    while !isdone(it)
        roll!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    # shrink phase
    while j <= N_out
        shrink!(mf)
        output[j] = median(mf)
        j += 1
    end

    return output
end

function untapered_running_median(input::AbstractVector{T}, window_size::Integer) where T <: Real
    N = length(input)

    # calculate maximum possible window size
    max_possible_window_size = N
    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < window_size
        window_size = max_possible_window_size
    end

    # allocate output
    N_out = N - window_size + 1
    output = Array{Float64,1}(undef, N_out)

    # input iterator
    it = Iterators.Stateful(input)

    # construct MedianFilter
    mf = MedianFilter(popfirst!(it), window_size)

    # grow phase - no output yet
    while !isfull(mf)
        grow!(mf, popfirst!(it))
    end
    
    # first median
    j = 1
    output[j] = median(mf)
    j += 1

    # roll phase
    while !isdone(it)
        roll!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    return output
end

end # module

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
function running_median(input::AbstractVector{T}, window_size::Integer, tapering=:symmetric) where {T<:Real}
    if length(input) == 0
        error("input array must be non-empty")
    end

    if window_size < 1
        error("window_size must be 1 or bigger")
    end

    N = length(input)

    # clamp window size to N
    window_size = min(window_size, N)

    if tapering in (:symmetric, :sym)
        if N |> iseven
            max_window_size = N - 1
            window_size = min(window_size, max_window_size)
        end
        N_out = window_size |> isodd ? N : N - 1
        prep = _prepare_running_median(input, window_size, N_out)
        _symmetric_phases!(prep...)
    elseif tapering in (:asymmetric, :asym)
        N_out = N + window_size - 1
        prep = _prepare_running_median(input, window_size, N_out)
        _asymmetric_phases!(prep...)
    elseif tapering in (:asymmetric_truncated, :asym_trunc)
        N_out = window_size |> isodd ? N : N - 1
        prep = _prepare_running_median(input, window_size, N_out)
        _asymmetric_truncated_phases!(prep...)
    elseif tapering in (:none, :no)
        N_out = N - window_size + 1
        prep = _prepare_running_median(input, window_size, N_out)
        _untapered_phases!(prep...)
    else
        error("Invalid tapering. Must be one of [:sym, :asym, :asym_trunc, :no]")
    end

    return prep.output
end

function _prepare_running_median(input, window_size, N_out)
    # input iterator
    init = Iterators.Stateful(input)

    output = Array{Float64,1}(undef, N_out)
    mf = MedianFilter(popfirst!(init), window_size)

    # output index iterator
    outindit = Iterators.Stateful(eachindex(output))

    return (
        init=init,
        mf=mf,
        output=output,
        outindit=outindit,
    )
end

function _symmetric_phases!(init, mf, output, outindit)
    # if even, start with two elements in mf at index 1.5
    if window_size(mf) |> iseven
        grow!(mf, popfirst!(init))
    end

    # first median
    output[popfirst!(outindit)] = median(mf)

    # grow phase
    while !isfull(mf)
        grow!(mf, popfirst!(init))
        grow!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf)
    end

    # roll phase
    while !isdone(init)
        roll!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf)
    end

    # shrink phase
    while !isdone(outindit)
        shrink!(mf)
        shrink!(mf)
        output[popfirst!(outindit)] = median(mf)
    end
end

function _asymmetric_phases!(init, mf, output, outindit)
    # first median
    output[popfirst!(outindit)] = median(mf)

    # grow phase
    while !isfull(mf)
        grow!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf)
    end

    # roll phase
    while !isdone(init)
        roll!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf)
    end

    # shrink phase
    while !isdone(outindit)
        shrink!(mf)
        output[popfirst!(outindit)] = median(mf)
    end
end

function _asymmetric_truncated_phases!(init, mf, output, outindit)
    # pre-output grow phase
    while length(mf) <= window_size(mf) / 2
        grow!(mf, popfirst!(init))
    end

    # first median
    output[popfirst!(outindit)] = median(mf)

    # grow phase
    while !isfull(mf)
        grow!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf)
    end

    # roll phase
    while !isdone(init)
        roll!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf)
    end

    # shrink phase
    while !isdone(outindit)
        shrink!(mf)
        output[popfirst!(outindit)] = median(mf)
    end
end

function _untapered_phases!(init, mf, output, outindit)
    # grow phase - no output yet
    while !isfull(mf)
        grow!(mf, popfirst!(init))
    end

    # first median
    output[popfirst!(outindit)] = median(mf)

    # roll phase
    while !isdone(init)
        roll!(mf, popfirst!(init))
        output[popfirst!(outindit)] = median(mf)
    end
end

end # module

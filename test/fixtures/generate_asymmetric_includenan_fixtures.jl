# please instantiate ./test/Manifest.toml for this

using JLD2, Statistics

# ========================================
# Asymmetric Fuzz Test Fixtures
# ========================================

# format: [(values, window_size, expected_medians)]

fixtures = Vector{Tuple{Vector{Float16}, Integer, Vector{Float64}}}(undef, 0)

function naive_ignorenan_median_asymmetric(input, window_size)
    if window_size > length(input)
        window_size = length(input)
    end
    growing_phase_inds = [1:k for k in 1:window_size]
    rolling_phase_inds = [k:k + window_size - 1 for k in 2:(length(input) - window_size + 1)]
    shrinking_phase_inds = [length(input) - k + 1:length(input) for k in window_size - 1:-1:1]
    phase_inds = [growing_phase_inds; rolling_phase_inds; shrinking_phase_inds]
    [median(input[inds]) for inds in phase_inds]
end

for i in 1:100
    N = rand(1:50)
    window_size = rand(1:60)
    start = rand(-3:0)
    stop = rand(0:5)
    values = rand(start:stop, N).|>Float16
    local nan_mask
    while true
        nan_mask_noise = rand(Int8, N)
        nan_mask_threshold = rand(Int8)
        nan_mask = nan_mask_noise .> nan_mask_threshold
        if sum(nan_mask) > 0 # ensure one NaN is in there
            break
        end
    end
    for i in eachindex(values)
        if nan_mask[i]
            values[i] = NaN
        end
    end
    expected_medians = naive_ignorenan_median_asymmetric(values, window_size)
    push!(fixtures, (values, window_size, expected_medians))
end

filename = dirname(@__FILE__) * "/asymmetric_includenan.jld2"
jldsave(filename; fixtures, compress=true)
# please instantiate ./test/Manifest.toml for this

using JLD2
import Statistics

# ========================================
# Asymmetric Fuzz Test Fixtures
# ========================================

# format: [(values, window_length, expected_medians)]

fixtures = Vector{Tuple{Vector{Float64}, Integer, Vector{Float64}}}(undef, 0)

function naive_asymmetric_median(input, window_length)
    if window_length > length(input)
        window_length = length(input)
    end
    growing_phase_inds = [1:k for k in 1:window_length]
    rolling_phase_inds = [k:k + window_length - 1 for k in 2:(length(input) - window_length + 1)]
    shrinking_phase_inds = [length(input) - k + 1:length(input) for k in window_length - 1:-1:1]
    phase_inds = [growing_phase_inds; rolling_phase_inds; shrinking_phase_inds]
    output = [Statistics.median(input[inds]) for inds in phase_inds]
    return output
end

for i in 1:100
    N = rand(1:50)
    window_length = rand(1:60)
    values = rand(N)
    expected_medians = naive_asymmetric_median(values, window_length)
    push!(fixtures, (values, window_length, expected_medians))
end

filename = dirname(@__FILE__) * "/asymmetric.jld2"
@save filename fixtures

# Again with full Int32 range

fixtures = Vector{Tuple{Vector{Int32}, Integer, Vector{Float64}}}(undef, 0)

for i in 1:100
    N = rand(1:50)
    window_length = rand(1:60)
    values = rand(Int32, N)
    expected_medians = naive_asymmetric_median(values, window_length)
    push!(fixtures, (values, window_length, expected_medians))
end

filename = dirname(@__FILE__) * "/asymmetric_int.jld2"
@save filename fixtures
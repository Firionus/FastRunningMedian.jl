# please instantiate ./test/Manifest.toml for this

using JLD2
import Statistics

# ========================================
# Asymmetric Truncated Fuzz Test Fixtures
# ========================================

# format: [(values, window_length, expected_medians)]

asym_trunc_fixtures = Vector{Tuple{Vector{Float64}, Integer, Vector{Float64}}}(undef, 0)

function naive_asymmetric_truncated_median(input, window_length)
    if window_length > length(input)
        window_length = length(input)
    end

    if window_length |> iseven
        alpha = (window_length / 2 + 1) |> Int
    else
        alpha = ((window_length + 1) / 2) |> Int
    end
    growing_phase_inds = [1:k for k in alpha:window_length]
    rolling_phase_inds = [k:k + window_length - 1 for k in 2:(length(input) - window_length + 1)]
    shrinking_phase_inds = [length(input) - k + 1:length(input) for k in window_length - 1:-1:alpha]
    phase_inds = [growing_phase_inds; rolling_phase_inds; shrinking_phase_inds]
    output = [Statistics.median(input[inds]) for inds in phase_inds]
    return output
end

for i in 1:100
    N = rand(1:40)
    window_length = rand(1:50)
    values = rand(N)
    expected_medians = naive_asymmetric_truncated_median(values, window_length)
    push!(asym_trunc_fixtures, (values, window_length, expected_medians))
end

asym_trunc_filename = dirname(@__FILE__) * "/asym_trunc.jld2"
@save asym_trunc_filename asym_trunc_fixtures

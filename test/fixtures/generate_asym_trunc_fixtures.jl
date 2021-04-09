# please instantiate ./test/Manifest.toml for this

using JLD2, RollingFunctions

# ========================================
# Asymmetric Truncated Fuzz Test Fixtures
# ========================================

# format: [(values, window_size, expected_medians)]

asym_trunc_fixtures = Vector{Tuple{Vector{Float64}, Integer, Vector{Float64}}}(undef, 0)

function naive_asymmetric_truncated_median(input, window_size)
    if window_size > length(input)
        window_size = length(input)
    end

    if window_size |> iseven
        alpha = (window_size / 2 + 1) |> Int
    else
        alpha = ((window_size + 1) / 2) |> Int
    end
    growing_phase_inds = [1:k for k in alpha:window_size]
    rolling_phase_inds = [k:k + window_size - 1 for k in 2:(length(input) - window_size + 1)]
    shrinking_phase_inds = [length(input) - k + 1:length(input) for k in window_size - 1:-1:alpha]
    phase_inds = [growing_phase_inds; rolling_phase_inds; shrinking_phase_inds]
    output = [Statistics.median(input[inds]) for inds in phase_inds]
    return output
end

for i in 1:100
    N = rand(1:40)
    window_size = rand(1:50)
    values = rand(N)
    expected_medians = naive_asymmetric_truncated_median(values, window_size)
    push!(asym_trunc_fixtures, (values, window_size, expected_medians))
end

asym_trunc_filename = dirname(@__FILE__) * "/asym_trunc.jld2"
@save asym_trunc_filename asym_trunc_fixtures

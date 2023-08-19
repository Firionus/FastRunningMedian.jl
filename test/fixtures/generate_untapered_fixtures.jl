# please instantiate ./test/Manifest.toml for this

using JLD2, RollingFunctions

# ===============================
# Untapered Fuzz Test Fixtures
# ===============================

# format: [(values, window_length, expected_medians)]

untapered_fixtures = Vector{Tuple{Vector{Float64}, Integer, Vector{Float64}}}(undef, 0)

for i in 1:100
    N = rand(1:50)
    window_length = rand(1:60)
    values = rand(N)
    if window_length > N
        rf_w = N
    else
        rf_w = window_length
    end
    expected_medians = rollmedian(values, rf_w)
    push!(untapered_fixtures, (values, window_length, expected_medians))
end

untapered_filename = dirname(@__FILE__) * "/untapered.jld2"
@save untapered_filename untapered_fixtures

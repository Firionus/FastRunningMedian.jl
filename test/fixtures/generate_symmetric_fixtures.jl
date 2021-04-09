# please instantiate ./test/Manifest.toml for this

using JLD2
import Statistics

# ========================================
# Symmetric Fuzz Test Fixtures
# ========================================

# format: [(values, window_size, expected_medians)]

fixtures = Vector{Tuple{Vector{Float64}, Integer, Vector{Float64}}}(undef, 0)

function naive_symmetric_median(arr, window)       
    output = similar(arr)
    offset = round((window - 1) / 2, Base.Rounding.RoundNearestTiesAway) |> Int
    for j in eachindex(arr)
        temp_offset = min(offset, j - 1, length(arr) - j)
        beginning = j - temp_offset
        ending = j + temp_offset
        to_median = arr[beginning:ending] |> skipmissing
        output[j] = Statistics.median(to_median)
    end
    output
end

function push_fixture(N, window_size)
    values = rand(N)
    expected_medians = naive_symmetric_median(values, window_size)
    push!(fixtures, (values, window_size, expected_medians))
end

push_fixture(100_000, 101)

for i in 1:50
    push_fixture(rand(3:20), rand(19:2:100))
    push_fixture(rand(10:1_000), rand(3:2:11))
    push_fixture(rand(100:10_000), rand(11:2:1_000))
end

filename = dirname(@__FILE__) * "/symmetric.jld2"
@save filename fixtures
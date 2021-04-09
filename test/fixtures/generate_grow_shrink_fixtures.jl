# please instantiate ./test/Manifest.toml for this

using Combinatorics, JLD2, DataStructures
import Statistics

# ===============================
# Grow and Shrink Fuzz Fixtures
# ===============================

# format: [(values, expected_medians)]

grow_shrink_values = [[1.], [1,2], [2,1]]
append!(grow_shrink_values, permutations([1,2,3])|>collect)
append!(grow_shrink_values, permutations([1,2,3,4])|>collect)
for n in [6,7,13,14,50,51], _ in 1:20
    push!(grow_shrink_values, rand(n))
end

function generate_grow_shrink_medians(values)
    N = length(values)
    medians = Array{Float64}(undef, 2N-1)
    # grow phase
    for i in 1:N
        medians[i] = Statistics.median(values[1:i])
    end
    # shrink phase
    for i in N+1:2N-1
        medians[i] = Statistics.median(values[i-N+1:end])
    end
    return medians
end

grow_shrink_medians = map(generate_grow_shrink_medians, grow_shrink_values)

grow_shrink_fixtures = [(grow_shrink_values[i], grow_shrink_medians[i]) for i in eachindex(grow_shrink_values)]

grow_shrink_filename = dirname(@__FILE__) * "/grow_shrink.jld2"
@save grow_shrink_filename grow_shrink_fixtures

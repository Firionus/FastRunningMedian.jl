# please instantiate ./test/Manifest.toml for this

using Combinatorics, JLD2, DataStructures
import Statistics

# ===============================
# Roll Fuzz Fixtures
# ===============================

# format: [(initial_values, roll_values, expected_medians)]
# window_size == length(initial_values)
# length(roll_values) == length(expected_medians)
# check each expected_median after pushing the corresponding push_value

roll_fixtures = [([1.], [2., 0.], [2., 0.])]

function generate_roll_fixture(initial_values, N)
    roll_values = rand(N)
    cb = CircularBuffer{Float64}(length(initial_values))
    for i in eachindex(initial_values)
        push!(cb, initial_values[i])
    end
    expected_medians = Array{Float64}(undef, N)
    for i in 1:N
        push!(cb, roll_values[i])
        expected_medians[i] = Statistics.median(cb)
    end
    return (initial_values, roll_values, expected_medians)
end

function append_roll_fixtures(window_size, push_N)
    initial_values = rand(window_size)
    push!(roll_fixtures, generate_roll_fixture(initial_values, push_N))
end

append_roll_fixtures(2, 20)
append_roll_fixtures(3, 20)
append_roll_fixtures(9, 5000)
append_roll_fixtures(10, 5000)
append_roll_fixtures(1_000, 10_000)

roll_filename = dirname(@__FILE__) * "/roll.jld2"
@save roll_filename roll_fixtures
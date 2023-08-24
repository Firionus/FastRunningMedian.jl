using FastRunningMedian, Test, DataStructures, JLD2, OffsetArrays
import Statistics
import FastRunningMedian: lo, hi, nan

"""
    check_health(mf::MedianFilter)

Check that all pointers point at a thing that again points back at them. Also check that low_heap is smaller than high_heap. 

Debug Function for MedianFilter. 
"""
function check_health(mf::MedianFilter)
    nan_count = 0
    #println(mf)
    for k in 1:length(mf.heap_pos)
        current_heap, current_heap_ind = mf.heap_pos[k]
        if current_heap == lo
            a = mf.low_heap[current_heap_ind][2] - mf.heap_pos_offset
            # println(k, " ?= ", a)
            @assert k == a
        elseif current_heap == hi
            a = mf.high_heap[current_heap_ind][2] - mf.heap_pos_offset
            # println(k, " ?= ", a)
            @assert k == a
        else # nan
            nan_count += 1
        end
    end

    @assert nan_count == mf.nans

    if !isempty(mf.high_heap)
        @assert first(mf.low_heap) <= first(mf.high_heap)
    end
end

println("running tests...")

@testset "FastRunningMedian Tests" begin

    @testset "Stateful API Tests" begin
        
        @testset "Grow and Shrink Fuzz" begin
            # load test cases
            @load "fixtures/grow_shrink.jld2" grow_shrink_fixtures

            function grow_and_shrink_test(values, expected_medians)
                N = length(values)
                mf = MedianFilter{eltype(values)}(N)
                check_health(mf)
                #grow phase
                for i in 1:N
                    grow!(mf, values[i])
                    check_health(mf)
                    @test median(mf) == expected_medians[i]
                end
                # shrink phase
                for i in N+1:2N-1
                    shrink!(mf)
                    check_health(mf)
                    @test median(mf) == expected_medians[i]
                end
                @test length(mf) == 1
            end
            
            for fixture in grow_shrink_fixtures
                grow_and_shrink_test(fixture...)
            end
        end
        
        @testset "Roll Fuzz" begin
            #load test cases
            @load "fixtures/roll.jld2" roll_fixtures

            function roll_test(initial_values, roll_values, expected_medians, window_length = length(initial_values))
                mf = MedianFilter{eltype(initial_values)}(window_length)
                for i in eachindex(initial_values)
                    grow!(mf, initial_values[i])
                end
                @test length(mf) == length(initial_values)
                for i in 1:length(roll_values)
                    roll!(mf, roll_values[i])
                    check_health(mf)
                    @test median(mf) == expected_medians[i]
                end
            end

            for fixture in roll_fixtures
                roll_test(fixture...)
                roll_test(fixture..., length(fixture[1])+1) # allow roll! with less than full window
                roll_test(fixture..., length(fixture[1])+2) # allow roll! with less than full window
            end
        end

        @testset "Roll does work with window length 1" begin
            mf = MedianFilter{Float64}(1)
            grow!(mf, 1.)
            @test 1. == median(mf)
            roll!(mf, 2.)
            @test 2. == median(mf)
            roll!(mf, 1.)
            @test 1. == median(mf)
        end
    
        @testset "Grow! does not grow beyond capacity" begin
            mf = MedianFilter{Float64}(3)
            grow!(mf, 1.)
            grow!(mf, 2.)
            grow!(mf, 3.)
            @test_throws ErrorException grow!(mf, 4.)
        end

        @testset "shrink! below 1-element errors" begin
            mf = MedianFilter{Float64}(4)
            @test_throws ErrorException shrink!(mf)
        end

        @testset "Including NaN is default and makes whole window NaN" begin
            mf = MedianFilter{Float64}(2)
            @test median(mf) |> isnan # TODO questionable
            grow!(mf, NaN)
            @test median(mf) |> isnan
            grow!(mf, 1.)
            @test median(mf) |> isnan
            shrink!(mf)
            @test median(mf) == 1.

            mf = MedianFilter{Float64}(3)
            grow!(mf, 1.); check_health(mf)
            @test median(mf) == 1.
            grow!(mf, 2.); check_health(mf)
            @test median(mf) == 1.5
            grow!(mf, NaN); check_health(mf)
            @test median(mf) |> isnan
            roll!(mf, 3.); check_health(mf)
            @test median(mf) |> isnan
            roll!(mf, 4.); check_health(mf)
            @test median(mf) |> isnan
            roll!(mf, 5.); check_health(mf)
            @test median(mf) == 4.
            roll!(mf, NaN); check_health(mf)
            @test median(mf) |> isnan
            roll!(mf, 6.); check_health(mf)
            @test median(mf) |> isnan
            shrink!(mf); check_health(mf)
            @test median(mf) |> isnan
            shrink!(mf); check_health(mf)
            @test median(mf) == 6.

            mf = MedianFilter{Float64}(1)
            grow!(mf, 1.); check_health(mf)
            @test median(mf) == 1.
            roll!(mf, NaN); check_health(mf)
            @test median(mf) |> isnan
            roll!(mf, 2.); check_health(mf)
            @test median(mf) == 2.
        end

        @testset "NaN can be ignored in median" begin
            mf = MedianFilter{Float64}(2)
            grow!(mf, NaN)
            @test median(mf, nan=:ignore) |> isnan
            grow!(mf, 1.); check_health(mf)
            @test median(mf, nan=:ignore) == 1.
            shrink!(mf); check_health(mf)
            @test median(mf) == 1.

            mf = MedianFilter{Float64}(3)
            grow!(mf, -1.)
            @test median(mf, nan=:ignore) == -1.0
            grow!(mf, NaN); check_health(mf)
            @test median(mf, nan=:ignore) == -1.0
            grow!(mf, NaN); check_health(mf)
            @test median(mf, nan=:ignore) == -1.0
            roll!(mf, 0.0); check_health(mf)
            @test median(mf, nan=:ignore) == 0.0
            roll!(mf, NaN); check_health(mf)
            @test median(mf, nan=:ignore) == 0.0
            shrink!(mf); check_health(mf)
            @test median(mf, nan=:ignore) == 0.0
            shrink!(mf); check_health(mf)
            @test median(mf, nan=:ignore) |> isnan
        end

        @testset "Pure NaN Input" begin
            mf = MedianFilter{Float64}(2)
            grow!(mf, NaN)
            @test median(mf) |> isnan
            grow!(mf, NaN); check_health(mf)
            @test median(mf) |> isnan
            roll!(mf, NaN); check_health(mf)
            @test median(mf) |> isnan
            shrink!(mf)
            @test median(mf) |> isnan

            mf = MedianFilter{Float64}(3)
            grow!(mf, NaN); check_health(mf)
            grow!(mf, NaN); check_health(mf)
            @test median(mf) |> isnan
            grow!(mf, NaN); check_health(mf)
            @test median(mf) |> isnan
            roll!(mf, NaN); check_health(mf)
            @test median(mf) |> isnan
            roll!(mf, NaN); check_health(mf)
            @test median(mf) |> isnan
            roll!(mf, NaN); check_health(mf)
            @test median(mf) |> isnan
            shrink!(mf); check_health(mf)
            @test median(mf) |> isnan
            shrink!(mf); check_health(mf)
            @test median(mf) |> isnan
        end

        @testset "Reset Median Filter" begin
            mf = MedianFilter{Float64}(2)
            @test grow!(mf, 1) == mf
            @test median(mf) == 1
            @test grow!(mf, 2) == mf
            @test median(mf) == 1.5
            @test FastRunningMedian.reset!(mf) == mf
            check_health(mf)
            @test length(mf) == 0
            @test median(mf) |> isnan
            grow!(mf, 3); check_health(mf)
            @test median(mf) == 3
            @test grow!(mf, 4) == mf
            check_health(mf)
            @test median(mf) == 3.5
        end

        @testset "MedianFilter Constructor" begin
            mf = MedianFilter(3)
            @test typeof(mf).parameters|>first == Float64
            @test window_length(mf) == 3

            mf = MedianFilter{Int}(3)
            @test typeof(mf).parameters|>first == Int
            @test window_length(mf) == 3

            mf = MedianFilter(Int16, Int16(3))
            @test typeof(mf).parameters|>first == Int16
            @test window_length(mf) == 3

            @test_throws ArgumentError MedianFilter(-1)
            @test_throws MethodError MedianFilter(ComplexF64, 3)
            
            # TODO not specifying window_length or value 0 might be possible in 
            # the future, with flexibly growing buffers
            @test_throws ArgumentError MedianFilter(0)
            @test_throws MethodError mf = MedianFilter(Int)
            @test_throws MethodError mf = MedianFilter()
        end

        @testset "Compare running_median! to Naive Asymmetric Median" begin
            @load "fixtures/asymmetric.jld2" fixtures
            for fixture in fixtures
                mf = MedianFilter{Float64}(min(length(fixture[1]), fixture[2]))
                output_length = length(fixture[1])+window_length(mf)-1
                output = zeros(output_length)
                @test fixture[3] == running_median!(mf, output, fixture[1], :asym)
            end
        end

        @testset "running_median! with integers" begin
            mf = MedianFilter{Int}(2)
            input = [1,2,3,4]
            output = [0,0,0]
            @test_throws InexactError running_median!(mf, output, input, :no)

            mf = MedianFilter{Int}(3)
            input = [1,2,3,4]
            output = [0,0]
            running_median!(mf, output, input, :no)
            @test output == [2,3]
        end
    end

    @testset "High Level API Tests" begin
        @testset "Basic API examples" begin
            @test_throws ArgumentError running_median(zeros(0), 1)
            @test running_median([1.], 1) == [1.]
            @test running_median([1., 2., 3.], 1) == [1., 2., 3.]
            @test running_median([1., 4., 2., 1.], 3) == [1., 2., 2., 1.]
            @test running_median([1, 4, 2, 1], 3) == [1, 2, 2, 1]
            @test running_median([1, 4, 2, 1], 3, :asym) == [1, 2.5, 2, 2, 1.5, 1]
            @test running_median([1., 4., 2., 1.], 3, :sym) == [1., 2., 2., 1.]
            @test running_median([1., 4., 2., 1.], 3, :symmetric) == [1., 2., 2., 1.]
            @test running_median([1., 4., 2., 1.], 3, :asym) == [1., 2.5, 2., 2., 1.5, 1.]
            @test running_median([1., 4., 2., 1.], 3, :asymmetric) == [1., 2.5, 2., 2., 1.5, 1.]
            @test running_median([1., 4., 2., 1.], 3, :asym_trunc) == [2.5, 2., 2., 1.5]
            @test running_median([1., 4., 2., 1.], 3, :asymmetric_truncated) == [2.5, 2., 2., 1.5]
            @test running_median([1., 4., 2., 1.], 3, :no) == [2., 2.]
            @test running_median([1., 4., 2., 1.], 3, :none) == [2., 2.]
            @test running_median([1., 2., 1., 2., 1., 3.], 101) == [1., 1., 1., 2., 2., 3.]
            @test running_median([1., 1., 2., 1., 1., 1., 1., 1., 2., 1.], 99) == 
                [1., 1., 1., 1., 1., 1., 1., 1., 1., 1.]
        end

        @testset "Basic API Examples with OffsetArrays" begin
            for offset in (-999, -1, 1, 888)
                @test running_median(OffsetArray([1.], offset), 1) == [1.]
                @test running_median(OffsetArray([1., 2., 3.], offset), 1) == [1., 2., 3.]
                @test running_median(OffsetArray([1., 4., 2., 1.], offset), 3) == [1., 2., 2., 1.]
                @test running_median(OffsetArray([1, 4, 2, 1], offset), 3) == [1, 2, 2, 1]
                @test running_median(OffsetArray([1, 4, 2, 1], offset), 3, :asym) == [1, 2.5, 2, 2, 1.5, 1]
                @test running_median(OffsetArray([1., 4., 2., 1.], offset), 3, :sym) == [1., 2., 2., 1.]
                @test running_median(OffsetArray([1., 4., 2., 1.], offset), 3, :asym) == [1., 2.5, 2., 2., 1.5, 1.]
                @test running_median(OffsetArray([1., 4., 2., 1.], offset), 3, :asym_trunc) == [2.5, 2., 2., 1.5]
                @test running_median(OffsetArray([1., 4., 2., 1.], offset), 3, :no) == [2., 2.]
                @test running_median(OffsetArray([1., 2., 1., 2., 1., 3.], offset), 101) == [1., 1., 1., 2., 2., 3.]
                @test running_median(OffsetArray([1., 1., 2., 1., 1., 1., 1., 1., 2., 1.], offset), 99) == 
                    [1., 1., 1., 1., 1., 1., 1., 1., 1., 1.]
            end
        end
        
        @testset "Compare to Naive Symmetric Median" begin
            @load "fixtures/symmetric.jld2" fixtures
            for fixture in fixtures
                @test fixture[3] == running_median(fixture[1], fixture[2], :sym)
            end
        end

        @testset "Compare to Naive Asymmetric Median" begin
            @testset "Float Input" begin
                @load "fixtures/asymmetric.jld2" fixtures
                for fixture in fixtures
                    @test fixture[3] == running_median(fixture[1], fixture[2], :asym)
                end
            end

            @testset "Int Input" begin
                @load "fixtures/asymmetric_int.jld2" fixtures
                for fixture in fixtures
                    @test fixture[3] == running_median(fixture[1], fixture[2], :asym)
                end
            end
        end

        @testset "Compare to Untapered Median from RollingFunctions" begin
            @load "fixtures/untapered.jld2" untapered_fixtures
            for fixture in untapered_fixtures
                @test fixture[3] == running_median(fixture[1], fixture[2], :none)
            end
        end

        @testset "Compare to Naive Asymmetric Truncated Median" begin
            @load "fixtures/asym_trunc.jld2" asym_trunc_fixtures
            for fixture in asym_trunc_fixtures
                @test fixture[3] == running_median(fixture[1], fixture[2], :asym_trunc)
            end
        end

        @testset "NaN should be included and turn whole window NaN by default" begin
            @load "fixtures/asymmetric_includenan.jld2" fixtures
            for fixture in fixtures
                @test all(fixture[3] .=== running_median(fixture[1], fixture[2], :asym))
            end
        end

        @testset "Ignore NaN on demand" begin
            @load "fixtures/asymmetric_ignorenan.jld2" fixtures
            for fixture in fixtures
                @test all(fixture[3] .=== running_median(fixture[1], fixture[2], :asym, nan=:ignore))
            end
        end

        @testset "Ignore NaN Example" begin
            @test all(running_median([-1.0, NaN, NaN, 0.0, NaN], 3, :asym, nan=:ignore) .=== [-1.0, -1.0, -1.0, 0.0, 0.0, 0.0, NaN])
        end

        @testset "Check views into arrays can be handled" begin
            data, window = collect(1:10), 3
            @test running_median(@view(data[2:end]), window) == running_median(data[2:end], window)
        end
        
        @testset "Multi-Series API" begin
            input = [
                4 5 6;
                1 0 9;
                9 8 7;
                3 1 2;]
            expected = [
                4 5 6;
                4 5 7;
                3 1 7;
                3 1 2;
            ]
            # High-level API
            @test running_median(input, 3) == expected

            # Mid-level API
            output = similar(input)
            mf = MedianFilter(eltype(input), 3)
            @test running_median!(mf, output, input) == expected
            @test output == expected

            # 3D and offset array
            input = Array{Int64,3}(undef, (4,3,2))
            input[:,:,1] = [
                4 4 1;
                2 -2 1;
                -3 0 0;
                4 3 -3;
            ]
            input[:,:,2] = [
                3 -4 0;
                -3 1 -3;
                -3 2 -4;
                2 -1 3;
            ]
            input = OffsetArrays.Origin(2,3,2)(input)
            expected = Array{Float64,3}(undef, (4,3,2))
            expected[:,:,1] = [
                4 4 1;
                2 0 1;
                2 0 0;
                4 3 -3;
            ]
            expected[:,:,2] = [
                3 -4 0;
                -3 1 -3;
                -3 1 -3;
                2 -1 3;
            ]
            output = running_median(input,3)
            @test output == expected
            @test typeof(output) == Array{Float64,3}

            output = similar(input)
            mf = MedianFilter(eltype(input), 3)
            @test running_median!(mf, output, input) == OffsetArrays.Origin(2,3,2)(Int64.(expected))

            output = Array{Int32,3}(undef, (4,3,2))
            mf = MedianFilter(eltype(input), 3)
            @test running_median!(mf, output, input) == expected
        end

        @testset "Beginning Only Tapering" begin
            @test running_median([1., 2., 3.], 2, :beginning_only) == [1., 1.5, 2.5]
            @test running_median([1., 2., 3.], 3, :start) == [1., 1.5, 2.]
            @test running_median([1., 2., 3.], 4, :start) == [1., 1.5, 2.]
            @test running_median([1., 4., 2., 1.], 3, :start) == [1., 2.5, 2., 2.]
            @test running_median([1., 4., 2., 1.], 4, :start) == [1., 2.5, 2., 1.5]
            @test running_median([1., 4., 2., 1.], 5, :start) == [1., 2.5, 2., 1.5]
        end
    end

    @testset "Allocation Regression Test" begin
        x = range(1, step=1, length=1002)
        w = 1001
        _allocs_jit = @allocations(running_median(x,w))
        allocations = @allocations(running_median(x,w))
        @test allocations <= 28
    end

    @testset "Aqua - Auto Quality Assurance" begin
        using Aqua
        Aqua.test_all(FastRunningMedian)
    end
    

end # all tests
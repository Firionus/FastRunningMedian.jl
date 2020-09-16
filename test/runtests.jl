using FastRunningMedian, Test
import Statistics

@testset "FastRunningMedian Tests" begin

@testset "simple examples" begin
    @test runningmedian([1., 2., 1., 2., 1., 3.]) == [1., 1., 1., 2., 2., 3.]
    @test runningmedian([1., 1., 2., 1., 1., 1., 1., 1., 2., 1.]) == 
                        [1., 1., 1., 1., 1., 1., 1., 1., 1., 1.]
end


#=
import FastRunningMedian.MedianFilter, FastRunningMedian.growby2!, FastRunningMedian.shrinkby2!, FastRunningMedian.roll!, FastRunningMedian.median

function runningmedian_with_sanity_check(input::Array{Float64, 1}, max_window_size=53)
    if iseven(max_window_size)
        error("max_window_size must be odd number")
    end

    # allocate output array
    output = similar(input)
    
    # maximum one-sided offset
    max_offset = round((max_window_size-1)/2, Base.Rounding.RoundNearestTiesAway)|>Int
    
    prev_offset = 0
    mymf = MedianFilter(input[1], max_window_size)
    output[1] = median(mymf)
    
    for j in 2:length(input)
        current_offset = min(max_offset, j-1, length(input)-j)
        #println(prev_offset, " followed by ", current_offset)
        if current_offset == prev_offset + 1
            #grow
            output[j] = growby2!(mymf, input[j+current_offset-1:j+current_offset])
        elseif current_offset == prev_offset - 1
            #shrink
            output[j] = shrinkby2!(mymf)
        elseif current_offset == prev_offset
            #roll
            output[j] = roll!(mymf, input[j+current_offset])
        else
            println("max_offset is ", max_offset)
            error("current_offset and prev_offset do not differ by -2, 0 or 2.")
        end
        prev_offset = current_offset

        # sanity check
        for k in 1:length(mymf.heap_pos)
            current_heap, current_heap_ind = mymf.heap_pos[k]
            if current_heap == true
                a = mymf.low_heap[current_heap_ind][2] - mymf.heap_pos_offset
                #println(k, " ?= ", a)
                @assert k == a
            else
                a = mymf.high_heap[current_heap_ind][2] - mymf.heap_pos_offset
                #println(k, " ?= ", a)
                @assert k == a
            end
        end
    end
    output
end
=#

function naivemedianfilter(arr, window=53)
    flag = [false, false]
    if arr[1]|>ismissing
        arr = arr[2:end]
        flag[1] = true
    end
    if arr[end]|>ismissing
        arr = arr[1:end-1]
        flag[2] = true
    end
    
    output = similar(arr)
    offset = round(window/2, Base.Rounding.RoundNearestTiesAway)|>Int
    for j in eachindex(arr)
        temp_offset = min(offset, j-1, length(arr)-j)
        
        beginning = j-temp_offset
        ending = j+temp_offset
        to_median = arr[beginning:ending]|>skipmissing
        if to_median|>isempty
            output[j] = missing
        else
            output[j] = Statistics.median(to_median)
        end
    end
    if flag[1] == true
        output = [missing; output]
    end
    if flag[2] == true
        output = [output; missing]
    end
    output
end

function compare_to_naive(N, w)
    x = rand(N)
    y = runningmedian(x, w)
    y2 = naivemedianfilter(x, w-1)
    @test y == y2
end

@testset "compare to naive filter" begin
    println("running tests...")

    @testset "long input to test roll!" begin
        compare_to_naive(1_000_000, 101)
    end

    @testset "short input, long window" begin
        for i = 1:200
            N = rand(3:20)
            w = rand(19:2:100)
            compare_to_naive(N, w)
        end
    end

    @testset "short windows" begin
        for i = 1:200
            N = rand(10:1_000)
            w = rand(3:2:11)
            compare_to_naive(N, w)
        end
    end

    @testset "intermediate stuff" begin
        for i = 1:200
            compare_to_naive(rand(100:10_000), rand(11:2:1_000))
        end
    end

    @testset "even length windows not allowed" begin
        for i in 1:100
            w = rand(0:2:1_000_000)  
            x = rand(100)
            @test_throws ErrorException runningmedian(x, w)
        end
    end

    @testset "window of lenght 1 not allowed" begin
        for i in 1:10
            w = 1
            x = rand(rand(1:1_000))
            @test_throws ErrorException runningmedian(x, w)
        end
    end

    @testset "input of lenght 1 or 2 not allowed" begin
        for i in 1:10
            w = rand(3:2:15)
            input = rand(rand(1:2))
            @test_throws ErrorException runningmedian(input, w)
        end
    end
end

end #all tests
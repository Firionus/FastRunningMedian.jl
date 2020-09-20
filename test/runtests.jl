using FastRunningMedian, Test, DataStructures
import Statistics

function check_health(mymf::MedianFilter)
    # check that all pointers point at a thing that again points back at them
    for k in 1:length(mymf.heap_pos)
        current_heap, current_heap_ind = mymf.heap_pos[k]
        if current_heap == true
            a = mymf.low_heap[current_heap_ind][2] - mymf.heap_pos_offset
            # println(k, " ?= ", a)
            @assert k == a
        else
            a = mymf.high_heap[current_heap_ind][2] - mymf.heap_pos_offset
            # println(k, " ?= ", a)
            @assert k == a
        end
    end
end

@testset "FastRunningMedian Tests" begin
    println("running tests...")

    @testset "Stateful API Tests" begin

        @testset "Grow and Shrink Fuzz" begin
            for j in 1:50
                N = rand(1:200)
                x = rand(N)
                mf = MedianFilter(x[1], N)
                check_health(mf)
                # grow phase
                for i in 2:length(x)
                    grow!(mf, x[i])
                    check_health(mf)
                    @assert Statistics.median(x[1:i]) == median(mf)
                end
                # shrink phase
                for i in 2:length(x)
                    shrink!(mf)
                    check_health(mf)
                    @assert Statistics.median(x[i:end]) == median(mf)
                end
            end
        end

        @testset "Roll Fuzz" begin
            for i in 1:50
                N = rand(1:1_000)
                x = rand(N)
                mf = MedianFilter(x[1], N)
                cb = CircularBuffer{Float64}(N)
                push!(cb, x[1])
                for i in 2:length(x)
                    grow!(mf, x[i])
                    check_health(mf)
                    push!(cb, x[i])
                end
                @assert capacity(cb) == length(cb)
                n = rand(1_000:2_000)
                for i in 1:n
                    random_number = rand()
                    push!(cb, random_number)
                    mf_median = roll!(mf, random_number)
                    check_health(mf)
                    cb_median = Statistics.median(cb)
                    @assert mf_median == cb_median
                end
            end

            @testset "Grow! does not grow beyond capacity" begin
                mf = MedianFilter(1., 3)
                grow!(mf, 2.)
                grow!(mf, 3.)
                @test_throws ErrorException grow!(mf, 4.)
            end

            @testset "shrink! below 1-element errors" begin
                mf = MedianFilter(1., 4)
                @test_throws ErrorException shrink!(mf)
            end

            @testset "can only roll when capacity is exactly met" begin
                mf = MedianFilter(1., 3)
                grow!(mf, 2.)
                @test_throws ErrorException roll!(mf, 3.)
                grow!(mf, 3.)
                roll!(mf, 4.)
                shrink!(mf)
                @test_throws ErrorException roll!(mf, 5.)
            end

        end

    end

    @testset "High Level API Tests" begin
        # Desired API
        # running_median(input::Array{T, 1}, window_size::Integer, tapering=:symmetric) where T <: Real
        # (taperings: :symmteric or :sym, :asymmetric or :asym, :trunc or :truncate)
        # window_size must be odd and positive
        # input of any size, Array{T, 1} where T <: Real

        @testset "Basic API examples" begin
            @test running_median([], 1) == []
            @test running_median([1.], 1) == [1.]
            @test running_median([1., 2., 3.], 1) == [1., 2., 3.]
            @test running_median([1., 4., 2., 1.], 3) == [1., 2., 2., 1.]
            @test running_median([1, 4, 2, 1], 3) == [1, 2, 2, 1]
            @test running_median([1., 4., 2., 1.], 3, :sym) == [1., 2., 2., 1.]
            @test running_median([1., 4., 2., 1.], 3, :symmetric) == [1., 2., 2., 1.]
            @test running_median([1., 4., 2., 1.], 3, :asym) == [2.5, 2., 2., 1.5]
            @test running_median([1., 4., 2., 1.], 3, :asymmetric) == [2.5, 2., 2., 1.5]
            @test running_median([1., 4., 2., 1.], 3, :trunc) == [2., 2.]
            @test running_median([1., 4., 2., 1.], 3, :truncate) == [2., 2.]
            @test running_median([1., 2., 1., 2., 1., 3.], 101) == [1., 1., 1., 2., 2., 3.]
            @test running_median([1., 1., 2., 1., 1., 1., 1., 1., 2., 1.], 99) == 
                [1., 1., 1., 1., 1., 1., 1., 1., 1., 1.]
        end

        @testset "even length windows not allowed" begin
            for i in 1:100
                w = rand(0:2:1_000_000)  
                x = rand(10:1_000)
                @test_throws ErrorException running_median(x, w)
            end
        end

        @testset "compare to naive_symmteric_median" begin

            function naive_symmteric_median(arr, window)       
                output = similar(arr)
                offset = round((window - 1) / 2, Base.Rounding.RoundNearestTiesAway) |> Int
                for j in eachindex(arr)
                    temp_offset = min(offset, j - 1, length(arr) - j)
            
                    beginning = j - temp_offset
                    ending = j + temp_offset
                    to_median = arr[beginning:ending] |> skipmissing
                    if to_median |> isempty
                        output[j] = missing
                    else
                        output[j] = Statistics.median(to_median)
                    end
                end
                output
            end    
        
            function compare_to_naive(N, w)
                x = rand(N)
                y = running_median(x, w)
                y2 = naiveme_symmetric_median(x, w)
                @test y == y2
            end

    
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
        end

        @testset "compare to naive_asymmetric_median" begin
            # runningfunctions.jl?
        end

        @testset "compare to naive_truncating_median" begin
            # rollingfunctions.jl?
        end
    end
end


#= 

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
end =#

    function naivemedianfilter(arr, window=53)
        flag = [false, false]
        if arr[1] |> ismissing
            arr = arr[2:end]
            flag[1] = true
        end
        if arr[end] |> ismissing
            arr = arr[1:end - 1]
            flag[2] = true
        end
    
        output = similar(arr)
        offset = round(window / 2, Base.Rounding.RoundNearestTiesAway) |> Int
        for j in eachindex(arr)
            temp_offset = min(offset, j - 1, length(arr) - j)
        
            beginning = j - temp_offset
            ending = j + temp_offset
            to_median = arr[beginning:ending] |> skipmissing
            if to_median |> isempty
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
        y2 = naivemedianfilter(x, w - 1)
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

end # all tests =#
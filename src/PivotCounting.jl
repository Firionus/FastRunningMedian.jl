using Revise, Statistics, DataStructures

# TODO this approach needs more documentation and strong ties into the algorithm code
"""
The approach for this algorithm, that is fast for small windows, is taken from
`runmed` in R, specifically the Stuetzle implementation.

Since it updates median values by counting the amount of elements below and
above the old median, I will call the approach "pivot counting".

To explain the "pivot counting" approach, we first define the median of an
iterable `window``.

If `length(window)|>iseven``, then the median is a value that satisfies:

    median in window &&
    count(x -> x < median, window) < length(window)/2 &&
    count(x -> x > median, window) < length(window)/2

This holds intuitively, because if median is chosen too high, the count of
elements lower than it would be too large. If the median is chosen too low, the
number of elements higher than it would be too large. 

If `lenth(window)|>isodd`, the median is defined by two values `lower` and 
`upper` that satisfy:

    lower <= upper && # TODO redundant?
    lower in window &&
    upper in window &&
    count(x -> x < lower, window) < length(window)/2 && 
    count(x -> x > lower, window) <= length(window)/2 && 
    count(x -> x > upper, window) < length(window)/2 && 
    count(x -> x < upper, window) <= length(window)/2
    
TODO intuitive explanation
"""

mutable struct PivotCountingState
    lower
    upper # unused if winsize is odd
    winsize
end

import Base.iseven, Base.isodd

iseven(mf::PivotCountingState) = mf.winsize |> iseven
isodd(mf::PivotCountingState) = mf.winsize |> isodd

median(mf::PivotCountingState) = begin
    mf.winsize > 0 || error("winsize too small for median")
    if mf |> iseven
        mf.lower/2 + mf.upper/2
    else ## mf |> isodd
        mf.lower|>float # ensure type stability of output
    end
end

# Basic API

# TODO lots of incompatibility with OffsetArrays here...

function PivotCountingState(input)
    N = length(input)
    if N |> isodd
        PivotCountingState(
            Statistics.median(input),
            first(input), #unused
            N,
        )
    else # N |> iseven
        midpoint = (N + 1)/2
        lower_ind = midpoint|>floor|>Int
        upper_ind = midpoint|>ceil|>Int
        lower, upper = partialsort(input, lower_ind:upper_ind)
        PivotCountingState(
            lower,
            upper,
            N,
        )
    end
end

# window: new window of data
function grow!(mf::PivotCountingState, window, yin)
    @assert mf.lower in window
    # @assert mf.upper in window
    @assert yin in window
    mf.winsize>= 1 || error("winsize too small. Create PivotCountingState first from input with at least 1 element")
    # grow even -> odd
    if mf |> iseven 
        if yin < mf.lower
            # new median is lower
            # no change
        elseif yin > mf.upper
            # new median is upper
            mf.lower = mf.upper
        else
            # insert between lower and upper
            # yin is new median
            mf.lower = yin
        end
    # grow odd -> even
    else # mf |> isodd
        if yin < mf.lower
            # previous median becomes upper
            mf.upper = mf.lower
            # new lower value is hard to find
            mf.lower = find_lower(window) # TODO not sure if we can speed this up
            # TODO calling this repeatedly might be slow compared to keeping a sorted array, heaps or skiplist and updating it
        elseif yin > mf.lower
            # previous median stays lower
            # new upper value is hard to find
            mf.upper = find_upper(window) # TODO not sure if we can speed this up
            # TODO same performance problem as above
        else # yin == mf.lower
            # "nothing" to do, median does not change
            mf.upper = mf.yin
        end
    end
    mf.winsize += 1
end

function find_lower(window) 
    @assert length(window) |> iseven
    lower_sorted_ind = Int(length(window)/2)
    partialsort(window, lower_sorted_ind)
end

function find_upper(window) 
    @assert length(window) |> iseven
    upper_sorted_ind = Int(length(window)/2) + 1
    partialsort(window, upper_sorted_ind)
end

function roll!(mf::PivotCountingState, yout, window, yin)
    @assert yin in window # TODO remove for performance testing, maybe move into a check_health testing tool called extra
    @assert yout <= mf.lower || yout >= mf.upper # yout can't be between lower and upper
    if mf |> isodd 
        if yin > mf.lower && yout <= mf.lower
            # median might shift up, count to see if it will and also collect next highest element
            count = 0
            next_highest = Inf # TODO I don't know if this all that elegant
            for el in window
                if el > mf.lower
                    count += 1
                    if el < next_highest
                        next_highest = el
                    end
                end
            end
            if count > mf.winsize/2
                mf.lower = next_highest
            end
        elseif yin < mf.lower && yout >= mf.lower
            # median might shift down, count to see if it will and also collect next smallest element
            count = 0
            next_smaller = -Inf # TODO I don't know if this all that elegant
            for el in window
                if el < mf.lower # TODO some testing with long arrays and high equality might be a good idea to assert everything is right here, e.g. on rand(1:3, 10^6) or rand(1:2, 10^6)
                    count += 1
                    if el > next_smaller
                        next_smaller = el
                    end
                end
            end
            if count > mf.winsize/2
                mf.lower = next_smaller
            end
        end
    else # mf |> iseven
        if yin < mf.lower
            # TODO this if structure might be able to be arranged more nicely
            if yout >= mf.upper
                mf.upper = mf.lower
                mf.lower = find_lower(window) # TODO we can definitely speed this up somewhat by doing pivot counting like for odd window
            elseif yout == mf.lower
                mf.lower = find_lower(window)  # TODO we can definitely speed this up somewhat by doing pivot counting like for odd window
            end # nothing in case yout < a, since it's a "deep replacement", not affecting lower/upper/median
        elseif yin > mf.upper
            if yout <= mf.lower
                mf.lower = mf.upper
                mf.upper = find_upper(window)  # TODO we can definitely speed this up somewhat by doing pivot counting like for odd window
            elseif yout == mf.upper
                mf.upper = find_upper(window)  # TODO we can definitely speed this up somewhat by doing pivot counting like for odd window (check if condition holds for old value, otherwise switch to next one)
            end # else nothing as it's a deep replacement
        else # yin is in [lower; upper] (inclusive)
            if yout <= mf.lower
                mf.lower = yin
            else # yout >= mf.upper, since yout has to come from previous window, so removing between lower and upper is not possible
                mf.upper = yin
            end
        end
    end
end

function shrink!(mf::PivotCountingState, window, yout)
    # shrink even -> odd
    if mf |> iseven 
        if yout <= mf.lower
            mf.lower = mf.upper
        end # else lower becomes median and stays lower
    #shrink odd -> even
    else # mf |> isodd
        elements_bigger_prev_med = 0
        elements_smaller_prev_med = 0
        next_highest = Inf
        next_smaller = -Inf
        # TODO possible logic error here because we only check 2 conditions instead of all 4?
        for el in window
            if el > mf.lower
                elements_bigger_prev_med += 1
                if el < next_highest
                    next_highest = el
                end
            end
            if el < mf.lower
                elements_smaller_prev_med += 1
                if el > next_smaller
                    next_smaller = el
                end
            end
        end
        if elements_bigger_prev_med >= length(window)/2
            mf.upper = next_highest
        else
            mf.upper = mf.lower
        end
        if elements_smaller_prev_med >= length(window)/2
            mf.lower = next_smaller
        end
    end
    mf.winsize -= 1
end

# Utils

using Test, Statistics

@testset "median" begin
    @test median(PivotCountingState(42, 99, 5)) == 42
    @test median(PivotCountingState(42, 99, 6)) == mean([42, 99])
end

@testset "grow!" begin
    # start empty
    mf = PivotCountingState(98, 99, 0)
    @test_throws Exception median(mf)
    @test_throws Exception grow!(mf, [1], 1)

    mf = PivotCountingState([1])
    @test mf.lower == 1
    # mf.upper shall not be accessed when winsize is odd and its value does not matter
    @test mf.winsize == 1
    @test median(mf) === 1.

    grow!(mf, [1,2], 2)
    @test mf.lower == 1
    @test mf.upper == 2
    @test mf.winsize == 2
    @test median(mf) === 1.5

    grow!(mf, [1,2,-1], -1)
    @test mf.lower == 1
    # mf.upper shall not be accessed when winsize is odd and its value does not matter
    @test mf.winsize == 3
    @test median(mf) === 1.
end

@testset "find_lower and find_upper" begin
    @test find_lower([5,3,5,1]) == 3
    @test find_upper([5,3,5,1]) == 5

    @test find_lower([1,2,3,4]) == 2
    @test find_upper([1,2,3,4]) == 3
end

@testset "roll!" begin
    @testset "odd winsize" begin
        mf = PivotCountingState([1,9,5])
        @test mf.lower == 5
        @test mf.winsize == 3
    
        roll!(mf, 1, [9,5,3], 3)
        @test mf.lower == 5
        @test mf.winsize == 3
    
        roll!(mf, 9, [5,3,6], 6)
        @test mf.lower == 5
        @test mf.winsize == 3
    
        roll!(mf, 5, [3,6,1], 1)
        @test mf.lower == 3
        @test mf.winsize == 3
    end

    @testset "even winsize" begin
        mf = PivotCountingState([1,9,5,3])
        @test mf.lower == 3
        @test mf.upper == 5
        @test mf.winsize == 4
        @test mf |> median === 4.
    
        roll!(mf, 1, [9,5,3,5], 5)
        @test mf.lower == 5
        @test mf.upper == 5
        @test mf.winsize == 4
        @test mf |> median === 5.
    
        roll!(mf, 9, [5,3,5,1], 1)
        @test mf.lower == 3
        @test mf.upper == 5
        @test mf.winsize == 4
        @test mf |> median === 4.
    
        roll!(mf, 5, [3,5,1,3], 3)
        @test mf.lower == 3
        @test mf.upper == 3
        @test mf.winsize == 4
        @test mf |> median === 3.
    end
end

@testset "shrink!" begin
    mf = PivotCountingState([1,9,5,3])
    @test mf.lower == 3
    @test mf.upper == 5
    @test mf.winsize == 4
    @test mf |> median === 4.

    shrink!(mf, [1,9,5], 3)
    @test mf.lower == 5
    @test mf.winsize == 3
    @test mf |> median === 5.

    shrink!(mf, [1,9], 5)
    @test mf.lower == 1
    @test mf.upper == 9
    @test mf.winsize == 2
    @test mf |> median === 5.

    shrink!(mf, [1], 9)
    @test mf.lower == 1
    @test mf.winsize == 1
    @test mf |> median === 1.
end

# TODO large fuzz testing (floats and 1:2 or 1:3)
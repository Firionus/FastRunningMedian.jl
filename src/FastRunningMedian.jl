module FastRunningMedian

using DataStructures

export runningmedian, MedianFilter, grow!, median, length, shrink!, roll!, running_median

# Custom Orderings for DataStructures.MutableBinaryHeap
struct TupleForward <: Base.Ordering end
Base.lt(o::TupleForward, a, b) = a[1] < b[1]

struct TupleReverse <: Base.Ordering end
Base.lt(o::TupleReverse, a, b) = a[1] > b[1]

# TODO constructor and grow! with multiple values (sort should be faster than a lot of growing, right? Gotta push! onto heap in the right order to avoid bubbling though. )

mutable struct MedianFilter 
    low_heap::MutableBinaryHeap{Tuple{Float64,Int64},TupleReverse} 
    high_heap::MutableBinaryHeap{Tuple{Float64,Int64},TupleForward}
    # first tuple value is data, second tuple value is index in heap_pos (see heap_pos_offset!)

    # ordered like data in moving window would be
    # first tuple value true if in low_heap, false if in high_heap
    # second value is handle in corresponding heap
    heap_pos::CircularBuffer{Tuple{Bool,Int64}}

    heap_pos_offset::Int64 
    # heap_pos is indexed with the first element at index 1. 
    # However the indices in the heaps might go out of date whenever overwriting elements at the beginning of the circular buffer
    # This is why index_in_heap_pos = heap_pos_indices_in_heaps - heap_pos_offset
end
# TODO generic typing (Real?) instead of Float64

# Constructor
# TODO Documentation (here and in other places)
function MedianFilter(first_val::Float64, max_window_size::Int64)
    low_heap = MutableBinaryHeap{Tuple{Float64,Int64},TupleReverse}()
    high_heap = MutableBinaryHeap{Tuple{Float64,Int64},TupleForward}()
    heap_positions = CircularBuffer{Tuple{Bool,Int64}}(max_window_size)
    
    first_val_ind = push!(low_heap, (first_val, 1))
    
    push!(heap_positions, (true, first_val_ind))
    
    MedianFilter(low_heap, high_heap, heap_positions, 0)
end

"""
    median(mf::MedianFilter)

Determine the current median in mf. 

If the number of elements in MedianFilter is odd, the low_heap shall always be one element bigger than
the high_heap. The top element of the low_heap then is the median. 

If the number of elements in MedianFilter is even, both heaps are the same size and the
median is the mean of both top elements. 
"""
function median(mf::MedianFilter)
    if length(mf.low_heap) == length(mf.high_heap)
        # even number of elements
        # median is mean of both top elements
        return (first(mf.low_heap)[1] + first(mf.high_heap)[1]) / 2
    else
        # odd number of elements
        return first(mf.low_heap)[1]
    end
end

Base.length(mf::MedianFilter) = mf.heap_pos |> length

isfull(mf::MedianFilter) = mf.heap_pos |> DataStructures.isfull

"""
    grow!(mf::MedianFilter, val)

Grow mf with the new element val. 

Returns the updated median. If mf would grow beyond
maximum window size, an error is thrown. In this case you probably wanted to use roll!. 

The new element is pushed onto the end of the circular buffer. 
"""
function grow!(mf::MedianFilter, val)
    # check that we don't grow beyond circular buffer capacity
    if length(mf.heap_pos) + 1 > capacity(mf.heap_pos)
        error("grow! would grow circular buffer length by 1 and therefore exceed circular buffer capacity")
    end

    if length(mf.low_heap) == length(mf.high_heap)
        # even number of elements
        # low_heap needs to grow
        middle_high = first(mf.high_heap)
        if val <= middle_high[1]
            # just push! new value onto low_heap
            _push_onto_heap!(mf, val, onto_low_heap=true)
        else
            # replace middle_high in high_heap with new val and move middle_high to low_heap

            # push new val to end of circular buffer an onto high_heap where it replaces to_displace
            push!(mf.heap_pos, mf.heap_pos[middle_high[2]])
            update!(mf.high_heap, mf.heap_pos[middle_high[2] - mf.heap_pos_offset][2], 
                (val, length(mf.heap_pos) + mf.heap_pos_offset))
            # move middle_high onto low_heap
            pushed_handle = push!(mf.low_heap, middle_high)
            # update heap_pos
            mf.heap_pos[middle_high[2] - mf.heap_pos_offset] = (true, pushed_handle)
        end
    else
        # odd number of elements
        # high_heap needs to grow
        current_median = first(mf.low_heap)
        if val >= current_median[1]
            # just push! new value onto high_heap
            _push_onto_heap!(mf, val, onto_low_heap=false)
        else
            # replace current_median in low_heap with new val and move current_median to high_heap

            # push new val to end of circular buffer and onto low_heap where it replaces current_median
            push!(mf.heap_pos, mf.heap_pos[current_median[2]])
            update!(mf.low_heap, mf.heap_pos[current_median[2] - mf.heap_pos_offset][2], 
                (val, length(mf.heap_pos) + mf.heap_pos_offset))
            # move current_median onto high_heap
            pushed_handle = push!(mf.high_heap, current_median)
            # update heap_pos
            mf.heap_pos[current_median[2] - mf.heap_pos_offset] = (false, pushed_handle)
        end
    end

    return median(mf)
end

"just push a new value onto one of the heaps and update heap_pos accordingly"
function _push_onto_heap!(mf::MedianFilter, val; onto_low_heap::Bool)
    if onto_low_heap == true
        pushed_handle = push!(mf.low_heap, (val, 0))
        push!(mf.heap_pos, (true, pushed_handle))
        mf.low_heap[pushed_handle] = (val, length(mf.heap_pos) + mf.heap_pos_offset)
    else
        pushed_handle = push!(mf.high_heap, (val, 0))
        push!(mf.heap_pos, (false, pushed_handle))
        mf.high_heap[pushed_handle] = (val, length(mf.heap_pos) + mf.heap_pos_offset)
    end
end



"""
    shrink!(mf::MedianFilter)

Shrinks mf by removing the first and oldest element in the circular buffer. 

Returns the updated median. Will error if mf contains only one element as a MedianFilter with zero elements
would not have a median. 
"""
function shrink!(mf::MedianFilter)
    if length(mf.heap_pos) <= 1
        error("MedianFilter of length 1 cannot be shrunk further because it would not have a median anymore")
    end

    to_remove = popfirst!(mf.heap_pos)
    mf.heap_pos_offset += 1

    if length(mf.low_heap) == length(mf.high_heap)
        # even number of elements
        # high_heap needs to get smaller
        if to_remove[1] == true
            # element-to-remove is in low_heap
            medium_high = pop!(mf.high_heap)
            update!(mf.low_heap, to_remove[2], medium_high)
            mf.heap_pos[medium_high[2] - mf.heap_pos_offset] = to_remove
        else
            # element-to-remove is in high_heap
            delete!(mf.high_heap, to_remove[2])
        end
    else
        # odd number of elements
        # low_heap needs to get smaller
        if to_remove[1] == true
            # element-to-remove is in low_heap
            delete!(mf.low_heap, to_remove[2])
        else
            # element-to-remove is in high_heap
            current_median = pop!(mf.low_heap)
            update!(mf.high_heap, to_remove[2], current_median)
            mf.heap_pos[current_median[2] - mf.heap_pos_offset] = to_remove
        end
    end

    return median(mf)
end

function roll!(mf::MedianFilter, val::Float64)
    if length(mf.heap_pos) != capacity(mf.heap_pos)
        error("When rolling, maximum capacity of ring buffer must be met")
    end

    to_replace = mf.heap_pos[1]
    new_heap_element = (val, capacity(mf.heap_pos) + mf.heap_pos_offset + 1)

    if capacity(mf.heap_pos) == 1
        update!(mf.low_heap, to_replace[2], new_heap_element)
        push!(mf.heap_pos, to_replace)
        mf.heap_pos_offset += 1
    else
        if val < first(mf.low_heap)[1]
            # val should go into low_heap
            if to_replace[1] == true
                # hole in low_heap
                update!(mf.low_heap, to_replace[2], new_heap_element)
                push!(mf.heap_pos, to_replace)
                mf.heap_pos_offset += 1
            else
                # hole in high_heap
                low_top, low_top_ind = top_with_handle(mf.low_heap)
                # shift low_top into hole in high_heap
                update!(mf.high_heap, to_replace[2], low_top)
                # don't forget to update indices in heap_pos
                mf.heap_pos[low_top[2] - mf.heap_pos_offset] = (false, to_replace[2])
                # put new val where low_top is
                update!(mf.low_heap, low_top_ind, new_heap_element)
                # perform circular push on circular buffer
                push!(mf.heap_pos, (true, low_top_ind))
                mf.heap_pos_offset += 1
            end
        elseif val > first(mf.high_heap)[1]
            # val should go into high_heap
            if to_replace[1] == true
                # hole in low_heap
                high_top, high_top_ind = top_with_handle(mf.high_heap)
                # shift high_top into hole in low_heap
                update!(mf.low_heap, to_replace[2], high_top)
                # dont't forget to udpate indices in heap_pos
                mf.heap_pos[high_top[2] - mf.heap_pos_offset] = (true, to_replace[2])
                # put new val where high_top is
                update!(mf.high_heap, high_top_ind, new_heap_element)
                # perform circular push on circular buffer
                push!(mf.heap_pos, (false, high_top_ind))
                mf.heap_pos_offset += 1
            else
                # hole in high_heap
                update!(mf.high_heap, to_replace[2], new_heap_element)
                push!(mf.heap_pos, to_replace)
                mf.heap_pos_offset += 1
            end
        else
            # low_top <= val <= high_top
            # put whereever hole is
            if to_replace[1] == true
                # hole in low_heap
                update!(mf.low_heap, to_replace[2], new_heap_element)
                push!(mf.heap_pos, to_replace)
                mf.heap_pos_offset += 1
            else
                # hole in high_heap
                update!(mf.high_heap, to_replace[2], new_heap_element)
                push!(mf.heap_pos, to_replace)
                mf.heap_pos_offset += 1
            end
        end
    end

    return median(mf)
end

function running_median(input::Array{T,1}, window_size::Integer, tapering=:symmetric) where T <: Real
    if length(input) == 0
        error("input array must be non-empty")
    end

    if window_size < 1
        error("window_size must be 1 or bigger")
    elseif window_size == 1
        return input
    end



    if tapering == :symmetric || tapering == :sym
        symmetric_running_median(input, window_size)
    elseif tapering == :asymmetric || tapering == :asym
        asymmetric_running_median(input, window_size)
    elseif tapering == :asymmetric_truncated || tapering == :asym_trunc
        asymmetric_truncated_running_median(input, window_size)
    elseif tapering == :none || tapering == :no
        untapered_running_median(input, window_size)
    else
        error("Invalid tapering. Must be one of [:sym, :asym, :asym_trunc, :no]")
    end
end

function symmetric_running_median(input::Array{T,1}, window_size::Integer) where T <: Real
    N = length(input)

    # calculate maximum possible window size
    if N |> isodd
        max_possible_window_size = N
    else
        max_possible_window_size = N - 1
    end
    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < window_size
        window_size = max_possible_window_size
    end

    # allocate output
    if window_size |> iseven
        N_out = N - 1
    else
        N_out = N
    end
    output = Array{T,1}(undef, N_out)

    # construct MedianFilter
    i = 1
    mf = MedianFilter(input[i], window_size)
    i += 1

    # if even, start with two elements in mf at index 1.5
    if window_size |> iseven
        grow!(mf, input[i])
        i += 1
    end

    # first median
    j = 1
    output[j] = median(mf)
    j += 1

    # grow phase
    while !isfull(mf)
        grow!(mf, input[i])
        i += 1
        output[j] = grow!(mf, input[i])
        i += 1
        j += 1
    end

    # roll phase
    while i <= N
        output[j] = roll!(mf, input[i])
        i += 1
        j += 1
    end

    # shrink phase
    while j <= N_out
        shrink!(mf)
        output[j] = shrink!(mf)
        j += 1
    end

    return output
end

function asymmetric_running_median(input::Array{T,1}, window_size::Integer) where T <: Real
    N = length(input)

    # calculate maximum possible window size
    max_possible_window_size = N
    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < window_size
        window_size = max_possible_window_size
    end
    
    # allocate output
    N_out = N + window_size - 1
    output = Array{T,1}(undef, N_out)

    # construct MedianFilter
    i = 1
    mf = MedianFilter(input[i], window_size)
    i += 1

    # first median
    j = 1
    output[j] = median(mf)
    j += 1

    # grow phase
    while !isfull(mf)
        output[j] = grow!(mf, input[i])
        i += 1
        j += 1
    end

    # roll phase
    while i <= N
        output[j] = roll!(mf, input[i])
        i += 1
        j += 1
    end

    # shrink phase
    while j <= N_out
        output[j] = shrink!(mf)
        j += 1
    end

    return output
end

function asymmetric_truncated_running_median(input::Array{T,1}, window_size::Integer) where T <: Real
    N = length(input)

    # calculate maximum possible window size
    max_possible_window_size = N
    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < window_size
        window_size = max_possible_window_size
    end

    # allocate output
    if window_size |> iseven
        N_out = N - 1
    else
        N_out = N
    end
    output = Array{T,1}(undef, N_out)

    # construct MedianFilter
    i = 1
    mf = MedianFilter(input[i], window_size)
    i += 1

    # pre-output grow phase
    while length(mf) <= window_size/2
        grow!(mf, input[i])
        i += 1
    end

    # first median
    j = 1
    output[j] = median(mf)
    j += 1

    # grow phase
    while !isfull(mf)
        output[j] = grow!(mf, input[i])
        i += 1
        j += 1
    end

    # roll phase
    while i <= N
        output[j] = roll!(mf, input[i])
        i += 1
        j += 1
    end

    # shrink phase
    while j <= N_out
        output[j] = shrink!(mf)
        j += 1
    end

    return output
end

function untapered_running_median(input::Array{T,1}, window_size::Integer) where T <: Real
    N = length(input)

    # calculate maximum possible window size
    max_possible_window_size = N
    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < window_size
        window_size = max_possible_window_size
    end

    # allocate output
    N_out = N - window_size + 1
    output = Array{T,1}(undef, N_out)

    # construct MedianFilter
    i = 1
    mf = MedianFilter(input[i], window_size)
    i += 1

    # grow phase - no output yet
    while !isfull(mf)
        grow!(mf, input[i])
        i += 1
    end
    
    # first median
    j = 1
    output[j] = median(mf)
    j += 1

    # roll phase
    while i <= N
        output[j] = roll!(mf, input[i])
        i += 1
        j += 1
    end

    return output
end

# TODO remove restrictions on input and window size where reasonably well defined behaviour can be accomplished
# TODO add asymmetric tapering of window towards end
"""
    runningmedian(input::Array{Float64, 1}, max_window_size=53)

Compute the running median over input with maximum window size of `max_window_size`. 

`max_window_size` must be an odd number. 

The window is shrinked towards the start and end such that it is symmetric around the center value. 
Therefore, the first and last values of the returned array are the same as in input. 

The implementation uses an efficient double heap algorithm that scales roughly O(N log(W)) where 
N is the size of `input` and W is the window size. 
"""
function runningmedian(input::Array{Float64,1}, max_window_size=53)
    if iseven(max_window_size) || max_window_size <= 1
        error("max_window_size must be odd number of 3 or bigger")
    elseif length(input) < 3
       error("input must be at least 3 elements long, otherwise function would return identity")
    else # max_window_size is odd
        if length(input) |> isodd
            max_possible_window_size = length(input)
        else
            max_possible_window_size = length(input) - 1
        end
    end

    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < max_window_size
        max_window_size = max_possible_window_size
    end

    # allocate output array
    output = similar(input)
    
    # maximum one-sided offset
    max_offset = round((max_window_size - 1) / 2, Base.Rounding.RoundNearestTiesAway) |> Int
    
    prev_offset = 0
    mymf = MedianFilter(input[1], max_window_size)
    output[1] = median(mymf)
    
    for j in 2:length(input)
        current_offset = min(max_offset, j - 1, length(input) - j)
        # println(prev_offset, " followed by ", current_offset)
        if current_offset == prev_offset + 1
            # grow
            output[j] = growby2!(mymf, input[j + current_offset - 1:j + current_offset])
        elseif current_offset == prev_offset - 1
            # shrink
            output[j] = shrinkby2!(mymf)
        elseif current_offset == prev_offset
            # roll
            output[j] = roll!(mymf, input[j + current_offset])
        else
            println("max_offset is ", max_offset)
            error("current_offset and prev_offset do not differ by -2, 0 or 2.")
        end
        prev_offset = current_offset
        # println(mymf)
        # DEBUG STATEMENT ONLY REMOVE IN PRODUCTION
        check_health(mymf)
    end
    output
end



end # module
